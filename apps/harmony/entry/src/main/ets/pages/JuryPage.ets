import { router } from '@kit.ArkUI';
import { JuryQuestion } from '../models/Models';
import { apiClient } from '../services/ApiClient';

interface JuryParams { projectId: string; targetSeconds: number; }

@Entry
@Component
struct JuryPage {
  @State questions: JuryQuestion[] = [];
  @State busy: boolean = false;
  @State error: string = '';
  private params: JuryParams = router.getParams() as JuryParams;
  private sessionId: string = '';

  aboutToAppear(): void { this.load(); }
  private async load(): Promise<void> {
    try { this.questions = await apiClient.listQuestions(this.params.projectId); } catch (reason) { this.error = `${reason}`; }
  }
  private async generate(): Promise<void> {
    this.busy = true;
    try {
      if (this.sessionId.length === 0) this.sessionId = (await apiClient.createSession(this.params.projectId, this.params.targetSeconds)).id;
      this.questions = await apiClient.generateQuestions(this.params.projectId, this.sessionId);
      this.error = '';
    } catch (reason) { this.error = `${reason}`; }
    this.busy = false;
  }

  build() {
    Column() {
      Row() { Button('‹').width(42).height(42).fontSize(28).fontColor('#18211D').backgroundColor(Color.Transparent).onClick(() => router.back()); Text('AI评委席').fontSize(22).fontWeight(FontWeight.Bold) }.width('100%')
      Text('让追问逼近薄弱处').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#18211D').margin({ top: 18 }).width('100%')
      Text('问题依据当前项目材料').fontSize(14).fontColor('#67716B').margin({ top: 7 }).width('100%')
      Button(this.busy ? '正在研读材料' : '生成一组评委问题').enabled(!this.busy).width('100%').height(50).margin({ top: 20 }).borderRadius(6).backgroundColor('#176B5B').onClick(() => this.generate())
      if (this.error.length > 0) { Text(this.error).fontColor('#C8573B').margin({ top: 10 }).width('100%') }
      List({ space: 12 }) {
        ForEach(this.questions, (question: JuryQuestion, index: number) => {
          ListItem() {
            Column({ space: 9 }) {
              Row() { Text(`${index + 1}`.padStart(2, '0')).fontColor('#C8573B').fontWeight(FontWeight.Bold); Text(question.category).fontSize(12).fontWeight(FontWeight.Bold).padding({ left: 8, right: 8, top: 3, bottom: 3 }).margin({ left: 10 }).backgroundColor('#E8E2D4').borderRadius(4) }.width('100%')
              Text(question.question).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#18211D').width('100%')
              if (question.evidence.length > 0) { Text(`依据：${question.evidence[0].quote}`).fontSize(12).fontColor('#67716B').maxLines(2).width('100%') }
            }.alignItems(HorizontalAlign.Start).padding(16).backgroundColor('#FFFDF8').border({ width: 1, color: '#D4CEC0', radius: 7 })
          }
        }, (question: JuryQuestion) => question.id)
      }.layoutWeight(1).width('100%').margin({ top: 20 })
    }.width('100%').height('100%').padding(20).backgroundColor('#F4F1E8')
  }
}
