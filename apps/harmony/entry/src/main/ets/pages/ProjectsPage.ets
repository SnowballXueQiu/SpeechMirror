import { router } from '@kit.ArkUI';
import { Project, UserProfile } from '../models/Models';
import { ApiError, apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

@Entry
@Component
struct ProjectsPage {
  @State projects: Project[] = [];
  @State profile?: UserProfile = undefined;
  @State busy: boolean = true;
  @State error: string = '';
  @State showCreate: boolean = false;
  @State createName: string = '';
  @State createDescription: string = '';
  @State createMinutes: number = 5;
  @State creating: boolean = false;
  @State createError: string = '';

  onPageShow(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.busy = true;
    try {
      const results = await Promise.all([apiClient.listProjects(), apiClient.getProfile()]);
      this.projects = results[0] as Project[];
      this.profile = results[1] as UserProfile;
      this.error = '';
      apiClient.recordActivity().catch(() => {});
    } catch (reason) {
      if (reason instanceof ApiError && reason.statusCode === 401) {
        router.replaceUrl({ url: 'pages/LoginPage' });
        return;
      }
      this.error = String(reason);
    } finally {
      this.busy = false;
    }
  }

  private openCreate(): void {
    this.createName = '';
    this.createDescription = '';
    this.createMinutes = 5;
    this.createError = '';
    this.showCreate = true;
  }

  private closeCreate(): void {
    if (this.creating) return;
    this.getUIContext().getFocusController().clearFocus();
    this.showCreate = false;
  }

  private async createProject(): Promise<void> {
    if (this.createName.trim().length === 0 || this.creating) {
      this.createError = '请输入项目名称';
      return;
    }
    this.getUIContext().getFocusController().clearFocus();
    this.creating = true;
    this.createError = '';
    try {
      const project = await apiClient.createProject(
        this.createName.trim(), this.createDescription.trim(), this.createMinutes * 60
      );
      this.showCreate = false;
      router.pushUrl({ url: 'pages/ProjectPage', params: { projectId: project.id } });
    } catch (reason) {
      this.createError = String(reason);
    } finally {
      this.creating = false;
    }
  }

  @Builder
  private createSheet() {
    Column() {
      Blank().layoutWeight(1).onClick(() => this.closeCreate())
      Column() {
        Text('').width(38).height(4).borderRadius(2).backgroundColor('#CBD0CA').margin({ bottom: 14 })
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ic_plus')).width(20).height(20)
          }.width(42).height(42).borderRadius(21).backgroundColor(Palette.INK)
          Column({ space: 3 }) {
            Text('新建答辩项目').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
            Text('设置名称、简介和项目陈述时长').fontSize(12).fontColor(Palette.MUTED)
          }.alignItems(HorizontalAlign.Start).margin({ left: 12 }).layoutWeight(1)
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ic_close')).width(20).height(20)
          }.width(38).height(38).backgroundColor(Palette.PAPER_STRONG).borderRadius(19)
            .onClick(() => this.closeCreate())
        }.width('100%')
        Text('项目名称').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          .width('100%').margin({ top: 22, bottom: 8 })
        TextInput({ text: this.createName, placeholder: '例如：SpeechMirror AI答辩教练' })
          .onChange((value: string) => this.createName = value).height(50).width('100%')
          .fontSize(15).backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 8 })
        Text('项目简介').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          .width('100%').margin({ top: 18, bottom: 8 })
        TextArea({ text: this.createDescription, placeholder: '用一两句话说明项目解决的问题' })
          .onChange((value: string) => this.createDescription = value).height(92).width('100%')
          .fontSize(15).backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 8 })
        Row() {
          Column({ space: 3 }) {
            Text('目标时长').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
            Text('项目陈述的参考时间').fontSize(12).fontColor(Palette.MUTED)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ic_minus')).width(19).height(19)
          }.width(36).height(36).borderRadius(18).backgroundColor(Palette.WHITE)
            .border({ width: 1, color: Palette.LINE })
            .enabled(this.createMinutes > 1).onClick(() => this.createMinutes -= 1)
          Text(String(this.createMinutes) + ' 分钟').width(68).fontSize(14).fontWeight(FontWeight.Bold)
            .fontColor(Palette.INK).textAlign(TextAlign.Center)
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ic_plus')).width(19).height(19)
          }.width(36).height(36).borderRadius(18).backgroundColor(Palette.INK).enabled(this.createMinutes < 30)
            .onClick(() => this.createMinutes += 1)
        }.width('100%').padding({ left: 14, right: 9, top: 9, bottom: 9 }).margin({ top: 12 })
          .backgroundColor(Palette.PAPER).border({ width: 1, color: Palette.LINE, radius: 8 })
        if (this.createError.length > 0) {
          Text(this.createError).fontSize(12).fontColor(Palette.RED).width('100%').margin({ top: 10 })
        }
        Row({ space: 10 }) {
          Button('取消').height(48).layoutWeight(1).fontColor(Palette.INK).backgroundColor(Palette.WHITE)
            .border({ width: 1, color: Palette.LINE }).borderRadius(8).onClick(() => this.closeCreate())
          Button(this.creating ? '正在创建' : '+  创建项目').height(48).layoutWeight(2)
            .fontColor(Palette.WHITE).fontWeight(FontWeight.Bold).backgroundColor(Palette.INK).borderRadius(8)
            .enabled(!this.creating).onClick(() => this.createProject())
        }.width('100%').margin({ top: 20 })
      }.alignItems(HorizontalAlign.Center).padding({ left: 20, right: 20, top: 10, bottom: 24 })
        .width('100%').backgroundColor(Palette.WHITE).borderRadius({ topLeft: 22, topRight: 22 })
    }.width('100%').height('100%').backgroundColor('#70111412')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
      Row() {
        Row({ space: 10 }) {
          Image($r('app.media.app_icon')).width(30).height(30).objectFit(ImageFit.Cover).borderRadius(7)
          Text('言镜').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        }
        Blank()
        Stack({ alignContent: Alignment.Center }) {
          Image($r('app.media.ic_plus')).width(22).height(22)
        }.width(40).height(40).borderRadius(20).backgroundColor(Palette.INK)
          .onClick(() => this.openCreate())
        Stack({ alignContent: Alignment.Center }) {
          Text((this.profile?.username ?? 'U').slice(0, 1).toUpperCase()).fontSize(15)
            .fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        }.width(38).height(38).borderRadius(19).margin({ left: 6 }).backgroundColor(Palette.PAPER_STRONG)
          .onClick(() => router.pushUrl({ url: 'pages/ProfilePage' }))
      }.width('100%').height(72)
      Row() {
        Text('我的答辩').fontSize(26).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        Blank()
        Text(String(this.projects.length) + ' 个项目').fontSize(13).fontWeight(FontWeight.Medium).fontColor(Palette.MUTED)
      }.width('100%').margin({ top: 18, bottom: 24 })
      if (this.error.length > 0) {
        Row({ space: 8 }) {
          Text('!').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.RED)
          Text(this.error).fontSize(13).fontColor(Palette.RED).layoutWeight(1)
          Button('重试').type(ButtonType.Normal).height(34).fontSize(12).fontColor(Palette.RED)
            .backgroundColor(Color.Transparent).onClick(() => this.reload())
        }.padding(12).width('100%').backgroundColor(Palette.SOFT_RED).borderRadius(7).margin({ bottom: 14 })
      }
      if (this.busy) {
        Column({ space: 14 }) {
          LoadingProgress().width(30).height(30).color(Palette.BLUE)
          Text('正在同步项目').fontSize(13).fontColor(Palette.MUTED)
        }.margin({ top: 84 })
      } else if (this.projects.length === 0) {
        Column() {
          Row() {
            Text('+').width(46).height(46).textAlign(TextAlign.Center).fontSize(28).fontColor(Palette.INK)
              .backgroundColor(Palette.SIGNAL).borderRadius(23)
            Blank()
            Text('01').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#55FFFFFF')
          }.width('100%')
          Text('从第一个项目开始').fontSize(23).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
            .margin({ top: 34 }).width('100%')
          Text('加入论文、PPT 或其他答辩材料，AI 评委会据此组织提问。')
            .fontSize(14).fontColor('#99FFFFFF').lineHeight(21).margin({ top: 9 }).width('100%')
          Button('创建第一个项目  →').height(50).width('100%').margin({ top: 28 }).borderRadius(6)
            .fontWeight(FontWeight.Bold).fontColor(Palette.INK).backgroundColor(Palette.SIGNAL)
            .onClick(() => this.openCreate())
        }.alignItems(HorizontalAlign.Start).padding(24).width('100%').backgroundColor(Palette.NIGHT).borderRadius(8)
      } else {
        List({ space: 0 }) {
          ForEach(this.projects, (project: Project, index: number) => {
            ListItem() {
              Column() {
                Row() {
                  Text(String(index + 1).padStart(2, '0')).fontSize(12).fontWeight(FontWeight.Bold)
                    .fontColor(Palette.MUTED).width(38)
                  Column({ space: 6 }) {
                    Text(project.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK).maxLines(1)
                    Row() {
                      Text('◷').fontSize(14).fontColor(Palette.MUTED)
                      Text(String(Math.floor(project.defense_duration_seconds / 60)) + ' 分钟')
                        .fontSize(13).fontColor(Palette.MUTED).margin({ left: 5 })
                      if ((project.description ?? '').trim().length > 0) {
                        Text('·').fontSize(13).fontColor(Palette.MUTED).margin({ left: 8, right: 8 })
                        Text(project.description ?? '').fontSize(13).fontColor(Palette.MUTED).maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                      }
                    }.width('100%')
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text('↗').width(38).height(38).textAlign(TextAlign.Center).fontSize(20).fontColor(Palette.WHITE)
                    .backgroundColor(Palette.INK).borderRadius(19).margin({ left: 12 })
                }.padding({ top: 18, bottom: 18 }).width('100%')
                if (index < this.projects.length - 1) {
                  Divider().strokeWidth(1).color(Palette.LINE).margin({ left: 38 })
                }
              }.width('100%').onClick(() =>
                router.pushUrl({ url: 'pages/ProjectPage', params: { projectId: project.id } }))
            }
          }, (project: Project) => project.id)
        }.layoutWeight(1).width('100%').border({ width: { top: 1, bottom: 1 }, color: Palette.LINE })
      }
      }.width('100%').height('100%').padding({ left: 20, right: 20, bottom: 48 }).backgroundColor(Palette.PAPER)
      if (this.showCreate) this.createSheet()
    }.width('100%').height('100%')
  }
}
