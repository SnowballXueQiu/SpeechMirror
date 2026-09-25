import { router } from '@kit.ArkUI';
import { Project, DocumentItem } from '../models/Models';
import { apiClient } from '../services/ApiClient';

interface ProjectParams { projectId: string; }

@Entry
@Component
struct ProjectPage {
  @State project?: Project = undefined;
  @State documents: DocumentItem[] = [];
  @State error: string = '';
  private projectId: string = (router.getParams() as ProjectParams).projectId;

  aboutToAppear(): void { this.reload(); }
  private async reload(): Promise<void> {
    try {
      this.project = await apiClient.getProject(this.projectId);
      this.documents = await apiClient.listDocuments(this.projectId);
    } catch (reason) { this.error = `${reason}`; }
  }

  build() {
    Column() {
      Row() {
        Button('‹').width(42).height(42).fontSize(28).fontColor('#18211D').backgroundColor(Color.Transparent).onClick(() => router.back())
        Text(this.project?.name ?? '项目训练台').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#18211D')
      }.width('100%')
      Text(this.project?.description ?? '材料、训练与评委追问').fontColor('#67716B').margin({ top: 12 }).width('100%')
      Row({ space: 10 }) {
        Button('开始模拟答辩').layoutWeight(1).height(50).borderRadius(6).backgroundColor('#176B5B')
          .onClick(() => router.pushUrl({ url: 'pages/TrainingPage', params: { projectId: this.projectId, targetSeconds: this.project?.defense_duration_seconds ?? 300 } }))
        Button('评委席').height(50).borderRadius(6).fontColor('#18211D').backgroundColor('#E8E2D4')
          .onClick(() => router.pushUrl({ url: 'pages/JuryPage', params: { projectId: this.projectId, targetSeconds: this.project?.defense_duration_seconds ?? 300 } }))
      }.width('100%').margin({ top: 24 })
      Text('答辩材料').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#18211D').margin({ top: 30, bottom: 12 }).width('100%')
      if (this.error.length > 0) { Text(this.error).fontColor('#C8573B').width('100%') }
      List({ space: 10 }) {
        ForEach(this.documents, (document: DocumentItem) => {
          ListItem() {
            Row() {
              Text('文').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#176B5B').width(40)
              Column({ space: 4 }) {
                Text(document.filename).fontWeight(FontWeight.Bold).fontColor('#18211D').maxLines(1)
                Text(document.status === 'ready' ? '已完成解析' : document.status).fontSize(12).fontColor('#67716B')
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.padding(15).backgroundColor('#FFFDF8').border({ width: 1, color: '#D4CEC0', radius: 6 })
          }
        }, (document: DocumentItem) => document.id)
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').padding(20).backgroundColor('#F4F1E8')
  }
}
