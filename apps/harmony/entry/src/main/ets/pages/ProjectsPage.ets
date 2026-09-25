import { router } from '@kit.ArkUI';
import { Project } from '../models/Models';
import { apiClient } from '../services/ApiClient';

@Entry
@Component
struct ProjectsPage {
  @State projects: Project[] = [];
  @State busy: boolean = true;
  @State error: string = '';

  onPageShow(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.busy = true;
    try {
      this.projects = await apiClient.listProjects();
      this.error = '';
    } catch (reason) {
      this.error = `${reason}`;
    } finally {
      this.busy = false;
    }
  }

  private async createProject(): Promise<void> {
    try {
      const project = await apiClient.createProject('我的答辩项目', 'HarmonyOS 6 端创建', 300);
      router.pushUrl({ url: 'pages/ProjectPage', params: { projectId: project.id } });
    } catch (reason) {
      this.error = `${reason}`;
    }
  }

  build() {
    Column() {
      Row() {
        Column({ space: 5 }) {
          Text('YOUR REHEARSAL DESK').fontSize(11).fontWeight(FontWeight.Bold).fontColor('#C8573B')
          Text('我的答辩项目').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#18211D')
        }.alignItems(HorizontalAlign.Start)
        Blank()
        Button('+').fontSize(24).width(46).height(46).borderRadius(6).backgroundColor('#C8573B').onClick(() => this.createProject())
      }.width('100%')
      if (this.error.length > 0) { Text(this.error).fontColor('#C8573B').margin({ top: 16 }).width('100%') }
      if (this.busy) {
        LoadingProgress().width(34).height(34).color('#176B5B').margin({ top: 80 })
      } else {
        List({ space: 12 }) {
          ForEach(this.projects, (project: Project) => {
            ListItem() {
              Row() {
                Column({ space: 6 }) {
                  Text(project.name).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#18211D')
                  Text(`${Math.floor(project.defense_duration_seconds / 60)} 分钟 · ${project.description ?? '未填写说明'}`)
                    .fontSize(13).fontColor('#67716B').maxLines(2)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text('›').fontSize(28).fontColor('#176B5B')
              }.padding(17).width('100%').backgroundColor('#FFFDF8').border({ width: 1, color: '#D4CEC0', radius: 7 })
              .onClick(() => router.pushUrl({ url: 'pages/ProjectPage', params: { projectId: project.id } }))
            }
          }, (project: Project) => project.id)
        }.layoutWeight(1).width('100%').margin({ top: 26 })
      }
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 28, bottom: 18 }).backgroundColor('#F4F1E8')
  }
}
