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

  build() {
    Column() {
      Row() {
        Row({ space: 10 }) {
          Image($r('app.media.app_icon')).width(32).height(32).objectFit(ImageFit.Contain).borderRadius(8)
          Text('言镜').fontSize(19).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        }
        Blank()
        Button('+').fontSize(24).fontColor(Palette.WHITE).width(40).height(40).borderRadius(20)
          .backgroundColor(Palette.INK).onClick(() => router.pushUrl({ url: 'pages/ProjectEditorPage' }))
        Button((this.profile?.username ?? 'U').slice(0, 1).toUpperCase()).fontSize(15).fontWeight(FontWeight.Bold)
          .fontColor(Palette.INK).width(40).height(40).borderRadius(20).margin({ left: 8 })
          .backgroundColor(Palette.PAPER_STRONG).onClick(() => router.pushUrl({ url: 'pages/ProfilePage' }))
      }.width('100%').height(54)
      Row() {
        Column({ space: 5 }) {
          Text('我的答辩').fontSize(29).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          Text('从材料到追问，完成一次真实演练').fontSize(13).fontColor(Palette.MUTED)
        }.alignItems(HorizontalAlign.Start)
        Blank()
        Text(String(this.projects.length) + ' 个项目').fontSize(13).fontWeight(FontWeight.Medium).fontColor(Palette.MUTED)
      }.width('100%').margin({ top: 22, bottom: 22 })
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
            .onClick(() => router.pushUrl({ url: 'pages/ProjectEditorPage' }))
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
                    Text(String(Math.floor(project.defense_duration_seconds / 60)) + ' 分钟  ·  ' +
                      (project.description ?? '未填写说明')).fontSize(13).fontColor(Palette.MUTED).maxLines(1)
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
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 18, bottom: 18 }).backgroundColor(Palette.PAPER)
  }
}
