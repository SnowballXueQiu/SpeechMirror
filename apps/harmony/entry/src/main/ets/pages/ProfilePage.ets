import { router } from '@kit.ArkUI';
import { ActivityDay, ActivitySummary, UserProfile } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

interface ActivityCell extends ActivityDay {
  visible: boolean;
}

@Entry
@Component
struct ProfilePage {
  @State profile?: UserProfile = undefined;
  @State activity?: ActivitySummary = undefined;
  @State loading: boolean = true;
  @State error: string = '';
  @State cacheMessage: string = '';
  @State showLogout: boolean = false;

  onPageShow(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.loading = true;
    try {
      const results = await Promise.all([apiClient.getProfile(), apiClient.getActivity()]);
      this.profile = results[0] as UserProfile;
      this.activity = results[1] as ActivitySummary;
      this.error = '';
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.loading = false;
    }
  }

  private activityColor(day: ActivityCell): string {
    if (!day.visible) return '#00000000';
    const count = day.use_count + day.practice_count * 2;
    if (count === 0) return '#293029';
    if (count === 1) return '#4C6632';
    if (count === 2) return '#71983B';
    if (count === 3) return '#9DCC4C';
    return Palette.SIGNAL;
  }

  private dateKey(date: Date): string {
    return String(date.getFullYear()).padStart(4, '0') + '-' +
      String(date.getMonth() + 1).padStart(2, '0') + '-' +
      String(date.getDate()).padStart(2, '0');
  }

  private activityWeeks(): ActivityCell[][] {
    const weeks: ActivityCell[][] = [];
    const values = new Map<string, ActivityDay>();
    (this.activity?.days ?? []).forEach((day: ActivityDay) => values.set(day.date.slice(0, 10), day));

    const throughValue = this.activity?.through ?? new Date().toISOString().slice(0, 10);
    const through = new Date(throughValue.slice(0, 10) + 'T12:00:00');
    const first = new Date(through.getTime() - 181 * 24 * 60 * 60 * 1000);
    const mondayOffset = (first.getDay() + 6) % 7;
    const start = new Date(first.getTime() - mondayOffset * 24 * 60 * 60 * 1000);

    for (let weekIndex = 0; weekIndex < 26; weekIndex += 1) {
      const week: ActivityCell[] = [];
      for (let weekday = 0; weekday < 7; weekday += 1) {
        const date = new Date(start.getTime() + (weekIndex * 7 + weekday) * 24 * 60 * 60 * 1000);
        const key = this.dateKey(date);
        const value = values.get(key);
        const visible = date.getTime() >= first.getTime() && date.getTime() <= through.getTime();
        week.push({
          date: key,
          use_count: value?.use_count ?? 0,
          practice_count: value?.practice_count ?? 0,
          visible: visible
        });
      }
      weeks.push(week);
    }
    return weeks;
  }

  private displayIdentity(): string {
    if (this.profile?.identity === '其他') return this.profile?.identity_other ?? '其他';
    return this.profile?.identity ?? '未设置身份';
  }

  private async logout(): Promise<void> {
    await apiClient.logout();
    router.replaceUrl({ url: 'pages/LoginPage' });
  }

  @Builder
  private menuRow(icon: string, title: string, subtitle: string) {
    Row() {
      Text(icon).width(38).height(38).textAlign(TextAlign.Center).fontSize(17)
        .fontWeight(FontWeight.Bold).fontColor(Palette.BLUE_DARK).backgroundColor(Palette.SOFT_BLUE).borderRadius(7)
      Column({ space: 4 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        Text(subtitle).fontSize(12).fontColor(Palette.MUTED)
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12 })
      Text('›').fontSize(24).fontColor(Palette.MUTED)
    }.width('100%').padding({ top: 13, bottom: 13 })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Button('‹').width(42).height(42).fontSize(28).fontColor(Palette.INK)
            .backgroundColor(Color.Transparent).onClick(() => router.back())
          Text('用户中心').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          Blank()
          Button('编辑').type(ButtonType.Normal).height(40).fontSize(13).fontColor(Palette.BLUE_DARK)
            .backgroundColor(Color.Transparent).onClick(() => router.pushUrl({ url: 'pages/PreferencesPage' }))
        }.width('100%').height(56).padding({ left: 4, right: 12 })
        if (this.loading && this.profile === undefined) {
          Column({ space: 12 }) {
            LoadingProgress().width(30).height(30).color(Palette.BLUE)
            Text('正在同步个人资料').fontSize(13).fontColor(Palette.MUTED)
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              Row() {
                Stack({ alignContent: Alignment.Center }) {
                  Text((this.profile?.username ?? 'U').slice(0, 1).toUpperCase())
                    .fontSize(31).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                }.width(78).height(78).borderRadius(39).backgroundColor(Palette.SIGNAL)
                Column({ space: 6 }) {
                  Text(this.profile?.username ?? '用户').fontSize(24).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                  Text(this.displayIdentity()).fontSize(13).fontColor(Palette.BLUE_DARK)
                  Text('ID  ' + (this.profile?.id ?? '').slice(0, 12)).fontSize(11).fontColor(Palette.MUTED)
                }.alignItems(HorizontalAlign.Start).margin({ left: 16 })
              }.width('100%')
              if ((this.profile?.bio ?? '').trim().length > 0) {
                Text(this.profile?.bio ?? '').fontSize(14).fontColor(Palette.MUTED).lineHeight(21)
                  .margin({ top: 16 }).width('100%')
              }
              if (this.error.length > 0) {
                Text(this.error).fontSize(13).fontColor(Palette.RED).padding(12).width('100%')
                  .backgroundColor(Palette.SOFT_RED).borderRadius(7).margin({ top: 16 })
              }
              Column() {
                Row() {
                  Text('近半年').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
                  Blank()
                  Text('练习活跃度')
                    .fontSize(12).fontColor('#88FFFFFF')
                }.width('100%')
                Row({ space: 3 }) {
                  ForEach(this.activityWeeks(), (week: ActivityCell[], weekIndex: number) => {
                    Column({ space: 3 }) {
                      ForEach(week, (day: ActivityCell) => {
                        Row().width(7).height(7).borderRadius(2).backgroundColor(this.activityColor(day))
                      }, (day: ActivityCell) => day.date)
                    }
                  }, (week: ActivityCell[], weekIndex: number) => String(weekIndex))
                }.width('100%').margin({ top: 18, bottom: 19 })
                Row() {
                  Column({ space: 4 }) {
                    Text(String(this.activity?.active_days ?? 0)).fontSize(23).fontWeight(FontWeight.Bold).fontColor(Palette.SIGNAL)
                    Text('活跃天数').fontSize(10).fontColor('#77FFFFFF')
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Column({ space: 4 }) {
                    Text(String(this.activity?.current_streak ?? 0) + ' 天').fontSize(23).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
                    Text('连续天数').fontSize(10).fontColor('#77FFFFFF')
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Column({ space: 4 }) {
                    Text(String(this.activity?.total_practices ?? 0)).fontSize(23).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
                    Text('模拟答辩').fontSize(10).fontColor('#77FFFFFF')
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                }.width('100%')
              }.alignItems(HorizontalAlign.Start).padding(20).width('100%').margin({ top: 26 })
                .backgroundColor(Palette.NIGHT).borderRadius(8)
              Text('账户与偏好').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Palette.MUTED)
                .margin({ top: 28, bottom: 4 }).width('100%')
              Column() {
                Column() {
                  this.menuRow('人', '身份与训练偏好', '场景、用途与个人简介')
                }.onClick(() => router.pushUrl({ url: 'pages/PreferencesPage' }))
                Divider().strokeWidth(1).color(Palette.LINE).margin({ left: 50 })
                Column() {
                  this.menuRow('隐', '隐私政策', '了解数据如何被处理')
                }.onClick(() => router.pushUrl({ url: 'pages/LegalPage', params: { kind: 'privacy' } }))
                Divider().strokeWidth(1).color(Palette.LINE).margin({ left: 50 })
                Column() {
                  this.menuRow('约', '用户协议', '服务使用规则')
                }.onClick(() => router.pushUrl({ url: 'pages/LegalPage', params: { kind: 'terms' } }))
                Divider().strokeWidth(1).color(Palette.LINE).margin({ left: 50 })
                Column() {
                  this.menuRow('清', '清理缓存', this.cacheMessage.length > 0 ? this.cacheMessage : '释放本地临时数据')
                }.onClick(() => this.cacheMessage = '缓存已清理')
              }.width('100%').border({ width: { top: 1, bottom: 1 }, color: Palette.LINE })
              Button('退出登录').type(ButtonType.Normal).height(50).width('100%').margin({ top: 24, bottom: 26 })
                .fontWeight(FontWeight.Bold).fontColor(Palette.RED).backgroundColor(Palette.SOFT_RED).borderRadius(7)
                .onClick(() => this.showLogout = true)
            }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20, top: 14 })
          }.layoutWeight(1).width('100%')
        }
      }.width('100%').height('100%').backgroundColor(Palette.PAPER)
      if (this.showLogout) {
        Column() {
          Blank().layoutWeight(1).onClick(() => this.showLogout = false)
          Column({ space: 12 }) {
            Text('退出当前账号？').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK).width('100%')
            Text('本机登录状态将被清除，你可以随时重新登录。').fontSize(14).fontColor(Palette.MUTED).width('100%')
            Row({ space: 10 }) {
              Button('取消').height(48).layoutWeight(1).fontColor(Palette.INK)
                .backgroundColor(Palette.PAPER_STRONG).borderRadius(7).onClick(() => this.showLogout = false)
              Button('退出登录').height(48).layoutWeight(1).fontColor(Palette.WHITE)
                .backgroundColor(Palette.RED).borderRadius(7).onClick(() => this.logout())
            }.width('100%').margin({ top: 8 })
          }.padding(22).width('100%').backgroundColor(Palette.WHITE)
            .borderRadius({ topLeft: 14, topRight: 14 })
        }.width('100%').height('100%').backgroundColor('#66000000')
      }
    }.width('100%').height('100%')
  }
}
