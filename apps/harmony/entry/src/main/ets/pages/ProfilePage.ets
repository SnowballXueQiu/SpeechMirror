import { router } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { ActivityDay, ActivitySummary, UserProfile, UserProfileUpdate } from '../models/Models';
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
  @State showAvatarActions: boolean = false;
  @State avatarBusy: boolean = false;
  @State avatar?: image.PixelMap = undefined;
  private activityScroller: Scroller = new Scroller();

  onPageShow(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.loading = true;
    try {
      const results = await Promise.all([apiClient.getProfile(), apiClient.getActivity()]);
      this.profile = results[0] as UserProfile;
      this.activity = results[1] as ActivitySummary;
      await this.loadAvatar();
      this.error = '';
      setTimeout((): void => {
        this.activityScroller.scrollEdge(Edge.End);
      }, 80);
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.loading = false;
    }
  }

  private async loadAvatar(): Promise<void> {
    if (!(this.profile?.has_avatar ?? false)) {
      this.avatar = undefined;
      return;
    }
    try {
      const source = image.createImageSource(await apiClient.getAvatarBytes());
      try {
        this.avatar = await source.createPixelMap({ desiredSize: { width: 144, height: 144 } });
      } finally {
        await source.release();
      }
    } catch (_) {
      this.avatar = undefined;
    }
  }

  private async prepareAvatar(uri: string): Promise<ArrayBuffer> {
    const source = image.createImageSource(uri);
    try {
      const info = await source.getImageInfo();
      const maxSide = Math.max(info.size.width, info.size.height);
      const scale = maxSide > 1024 ? 1024 / maxSide : 1;
      const width = Math.max(1, Math.round(info.size.width * scale));
      const height = Math.max(1, Math.round(info.size.height * scale));
      const pixelMap = await source.createPixelMap({ desiredSize: { width, height } });
      try {
        const packer = image.createImagePacker();
        try {
          return await packer.packToData(pixelMap, {
            format: 'image/jpeg',
            quality: 80,
            bufferSize: 2 * 1024 * 1024
          });
        } finally {
          await packer.release();
        }
      } finally {
        await pixelMap.release();
      }
    } finally {
      await source.release();
    }
  }

  private async uploadAvatarUri(uri: string): Promise<void> {
    if (this.avatarBusy) return;
    this.avatarBusy = true;
    this.error = '';
    try {
      await apiClient.uploadAvatar(await this.prepareAvatar(uri));
      this.profile = await apiClient.getProfile();
      await this.loadAvatar();
    } catch (reason) {
      this.error = `头像更新失败：${String(reason)}`;
    } finally {
      this.avatarBusy = false;
    }
  }

  private async chooseAvatarFromGallery(): Promise<void> {
    this.showAvatarActions = false;
    try {
      const options = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await new photoAccessHelper.PhotoViewPicker().select(options);
      if (result.photoUris.length > 0) await this.uploadAvatarUri(result.photoUris[0]);
    } catch (_) {}
  }

  private async chooseAvatarFromFiles(): Promise<void> {
    this.showAvatarActions = false;
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.png', '.jpg', '.jpeg'];
      const selected = await new picker.DocumentViewPicker().select(options);
      if (selected.length > 0) await this.uploadAvatarUri(selected[0]);
    } catch (_) {}
  }

  private async removeAvatar(): Promise<void> {
    if (this.avatarBusy) return;
    this.showAvatarActions = false;
    this.avatarBusy = true;
    this.error = '';
    try {
      await apiClient.deleteAvatar();
      this.profile = await apiClient.getProfile();
      this.avatar = undefined;
    } catch (reason) {
      this.error = `头像移除失败：${String(reason)}`;
    } finally {
      this.avatarBusy = false;
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
    const first = new Date(through.getTime() - 364 * 24 * 60 * 60 * 1000);
    const mondayOffset = (first.getDay() + 6) % 7;
    const start = new Date(first.getTime() - mondayOffset * 24 * 60 * 60 * 1000);
    for (let weekIndex = 0; weekIndex < 53; weekIndex += 1) {
      const week: ActivityCell[] = [];
      for (let weekday = 0; weekday < 7; weekday += 1) {
        const date = new Date(start.getTime() + (weekIndex * 7 + weekday) * 24 * 60 * 60 * 1000);
        const key = this.dateKey(date);
        const value = values.get(key);
        week.push({
          date: key,
          use_count: value?.use_count ?? 0,
          practice_count: value?.practice_count ?? 0,
          visible: date.getTime() >= first.getTime() && date.getTime() <= through.getTime()
        });
      }
      weeks.push(week);
    }
    return weeks;
  }

  private profileSummary(): string {
    const parts: string[] = [];
    if (this.profile?.identity === '其他') {
      if ((this.profile?.identity_other ?? '').length > 0) parts.push(this.profile?.identity_other ?? '');
    } else if ((this.profile?.identity ?? '').length > 0) {
      parts.push(this.profile?.identity ?? '');
    }
    const scenarios = this.profile?.scenarios ?? [];
    if (scenarios.length > 0) parts.push(scenarios.join('、'));
    return parts.length > 0 ? parts.join(' · ') : '尚未设置';
  }

  private async setResearchConsent(value: boolean): Promise<void> {
    if (this.profile === undefined) return;
    const update: UserProfileUpdate = {
      bio: this.profile.bio,
      identity: this.profile.identity,
      identity_other: this.profile.identity_other,
      scenario: this.profile.scenario,
      scenarios: this.profile.scenarios,
      scenario_other: this.profile.scenario_other,
      purposes: this.profile.purposes,
      purpose_other: this.profile.purpose_other,
      onboarding_completed: true,
      research_consent: value
    };
    try {
      this.profile = await apiClient.updateProfile(update);
    } catch (reason) {
      this.error = String(reason);
    }
  }

  private async logout(): Promise<void> {
    await apiClient.logout();
    router.replaceUrl({ url: 'pages/LoginPage' });
  }

  @Builder
  private activityStat(value: string, label: string, last: boolean = false) {
    Column({ space: 3 }) {
      Text(value).fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
      Text(label).fontSize(11).fontColor('#8AFFFFFF')
    }.justifyContent(FlexAlign.Center).layoutWeight(1)
      .border({ width: { right: last ? 0 : 1 }, color: '#1FFFFFFF' })
  }

  @Builder
  private menuRow(icon: Resource, title: string, subtitle: string = '', destructive: boolean = false) {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Image(icon).width(21).height(21).objectFit(ImageFit.Contain)
      }.width(40).height(40).backgroundColor(destructive ? Palette.SOFT_RED : Palette.WHITE)
        .borderRadius(7).border({ width: 1, color: Palette.LINE })
      Column({ space: 2 }) {
        Text(title).fontSize(15).fontWeight(FontWeight.Bold)
          .fontColor(destructive ? Palette.RED : Palette.INK)
        if (subtitle.length > 0) {
          Text(subtitle).fontSize(12).fontColor(Palette.MUTED).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 14 })
      if (!destructive) {
        Text('›').fontSize(23).fontColor(Palette.MUTED)
      }
    }.width('100%').constraintSize({ minHeight: 66 }).border({ width: { bottom: 1 }, color: Palette.LINE })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Button('‹').width(42).height(42).fontSize(28).fontColor(Palette.INK)
            .backgroundColor(Color.Transparent).onClick(() => router.back())
          Text('账户').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        }.width('100%').height(56)
        if (this.loading && this.profile === undefined) {
          LoadingProgress().width(30).height(30).color(Palette.BLUE).layoutWeight(1)
        } else {
          Scroll() {
            Column() {
              Row() {
                Stack({ alignContent: Alignment.Center }) {
                  if (this.avatar !== undefined) {
                    Image(this.avatar).width(72).height(72).objectFit(ImageFit.Cover).borderRadius(36)
                  } else {
                    Text((this.profile?.username ?? 'U').slice(0, 1).toUpperCase())
                      .fontSize(26).fontWeight(FontWeight.Bold).fontColor(Palette.SIGNAL)
                  }
                  Stack({ alignContent: Alignment.Center }) {
                    if (this.avatarBusy) {
                      LoadingProgress().width(14).height(14).color(Palette.WHITE)
                    } else {
                      Image($r('app.media.ic_edit_white')).width(14).height(14)
                    }
                  }.width(26).height(26).borderRadius(13).backgroundColor(Palette.BLUE)
                    .border({ width: 2, color: Palette.PAPER }).position({ x: 49, y: 49 })
                }.width(72).height(72).borderRadius(36).backgroundColor(Palette.INK)
                  .onClick(() => this.showAvatarActions = true)
                Column({ space: 5 }) {
                  Text(this.profile?.username ?? '用户').fontSize(24).fontWeight(FontWeight.Bold)
                    .fontColor(Palette.INK).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Row({ space: 5 }) {
                    Text('ID ' + (this.profile?.id ?? '')).fontSize(10).fontColor(Palette.MUTED).maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                    Image($r('app.media.ic_copy')).width(14).height(14)
                  }.width('100%')
                }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 16 })
              }.width('100%')
              Row() {
                Text((this.profile?.bio ?? '').trim().length > 0 ? (this.profile?.bio ?? '') : '添加个人简介')
                  .fontSize(14).fontColor((this.profile?.bio ?? '').trim().length > 0 ? Palette.INK : Palette.MUTED)
                  .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                Image($r('app.media.ic_edit')).width(19).height(19)
              }.width('100%').padding({ top: 11, bottom: 11 }).margin({ top: 18 })
                .border({ width: { top: 1, bottom: 1 }, color: Palette.LINE })
                .onClick(() => router.pushUrl({ url: 'pages/PreferencesPage' }))
              if (this.error.length > 0) {
                Text(this.error).fontSize(13).fontColor(Palette.RED).padding(12).width('100%')
                  .backgroundColor(Palette.SOFT_RED).borderRadius(7).margin({ top: 16 })
              }
              Column() {
                Row() {
                  Row({ space: 9 }) {
                    Text('▦').fontSize(18).fontColor(Palette.SIGNAL)
                    Text('过去一年').fontSize(16).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
                  }
                  Blank()
                  Text('练习活跃度').fontSize(12).fontColor('#8AFFFFFF')
                }.width('100%')
                Scroll(this.activityScroller) {
                  Row({ space: 3 }) {
                    ForEach(this.activityWeeks().slice(21), (week: ActivityCell[], weekIndex: number) => {
                      Column({ space: 3 }) {
                        ForEach(week, (day: ActivityCell) => {
                          Row().width(7).height(7).borderRadius(2).backgroundColor(this.activityColor(day))
                        }, (day: ActivityCell) => day.date)
                      }
                    }, (week: ActivityCell[], weekIndex: number) => String(weekIndex))
                  }
                }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
                  .edgeEffect(EdgeEffect.None).width('100%').height(68).margin({ top: 18, bottom: 18 })
                Row() {
                  this.activityStat(String(this.activity?.active_days ?? 0), '活跃天数')
                  this.activityStat(String(this.activity?.current_streak ?? 0), '连续天数')
                  this.activityStat(String(this.activity?.total_practices ?? 0), '模拟答辩', true)
                }.width('100%').height(48)
              }.alignItems(HorizontalAlign.Start).padding({ left: 18, right: 18, top: 18, bottom: 16 })
                .width('100%').margin({ top: 28 }).backgroundColor(Palette.NIGHT).borderRadius(8)
              Text('个人设置').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.MUTED)
                .margin({ top: 32, bottom: 5 }).width('100%')
              Column() { this.menuRow($r('app.media.ic_preferences'), '身份与训练偏好', this.profileSummary()) }
                .onClick(() => router.pushUrl({ url: 'pages/PreferencesPage' }))
              Row() {
                Stack({ alignContent: Alignment.Center }) {
                  Image($r('app.media.ic_research')).width(21).height(21)
                }.width(40).height(40).backgroundColor(Palette.WHITE).borderRadius(7)
                  .border({ width: 1, color: Palette.LINE })
                Column({ space: 2 }) {
                  Text('匿名产品调研').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                  Text('仅汇总身份、场景和训练目标').fontSize(12).fontColor(Palette.MUTED)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 14 })
                Toggle({ type: ToggleType.Switch, isOn: this.profile?.research_consent ?? false })
                  .selectedColor(Palette.BLUE).onChange((value: boolean) => this.setResearchConsent(value))
              }.width('100%').constraintSize({ minHeight: 66 }).border({ width: { bottom: 1 }, color: Palette.LINE })
              Text('存储与规则').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.MUTED)
                .margin({ top: 26, bottom: 5 }).width('100%')
              Column() { this.menuRow($r('app.media.ic_cache'), '清理缓存', this.cacheMessage.length > 0 ? this.cacheMessage : '0 B') }
                .onClick(() => this.cacheMessage = '缓存已清理')
              Column() { this.menuRow($r('app.media.ic_privacy'), '隐私政策') }
                .onClick(() => router.pushUrl({ url: 'pages/LegalPage', params: { kind: 'privacy' } }))
              Column() { this.menuRow($r('app.media.ic_terms'), '用户协议') }
                .onClick(() => router.pushUrl({ url: 'pages/LegalPage', params: { kind: 'terms' } }))
              Text('账户').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.MUTED)
                .margin({ top: 26, bottom: 5 }).width('100%')
              Column() { this.menuRow($r('app.media.ic_logout'), '退出登录', '', true) }.onClick(() => this.showLogout = true)
              Text('SpeechMirror 1.0.0').fontSize(12).fontColor(Palette.MUTED)
                .margin({ top: 24, bottom: 48 }).width('100%').textAlign(TextAlign.Center)
            }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20, top: 10 })
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
            .borderRadius({ topLeft: 22, topRight: 22 })
        }.width('100%').height('100%').backgroundColor('#70111412')
      }
      if (this.showAvatarActions) {
        Column() {
          Blank().layoutWeight(1).onClick(() => this.showAvatarActions = false)
          Column({ space: 12 }) {
            Row() {
              Column({ space: 4 }) {
                Text('个人头像').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                Text('支持 PNG、JPG 或 JPEG 图片').fontSize(13).fontColor(Palette.MUTED)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Button('×').width(38).height(38).fontSize(24).fontColor(Palette.MUTED)
                .backgroundColor(Palette.PAPER_STRONG).borderRadius(19)
                .onClick(() => this.showAvatarActions = false)
            }.width('100%')
            Button(this.profile?.has_avatar ? '从图库更换' : '从图库选择')
              .width('100%').height(50).fontSize(15).fontWeight(FontWeight.Bold)
              .fontColor(Palette.WHITE).backgroundColor(Palette.BLUE).borderRadius(7)
              .onClick(() => this.chooseAvatarFromGallery())
            Button('从文件选择').width('100%').height(50).fontSize(15).fontWeight(FontWeight.Bold)
              .fontColor(Palette.INK).backgroundColor(Palette.PAPER_STRONG).borderRadius(7)
              .onClick(() => this.chooseAvatarFromFiles())
            if (this.profile?.has_avatar ?? false) {
              Button('移除当前头像').width('100%').height(50).fontSize(15).fontWeight(FontWeight.Bold)
                .fontColor(Palette.RED).backgroundColor(Palette.SOFT_RED).borderRadius(7)
                .onClick(() => this.removeAvatar())
            }
          }.padding({ left: 22, right: 22, top: 22, bottom: 30 }).width('100%')
            .backgroundColor(Palette.WHITE).borderRadius({ topLeft: 22, topRight: 22 })
        }.width('100%').height('100%').backgroundColor('#70111412')
      }
    }.width('100%').height('100%')
  }
}
