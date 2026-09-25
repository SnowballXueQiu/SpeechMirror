import { router } from '@kit.ArkUI';
import { JuryAnswer, JuryQuestion } from '../models/Models';
import { apiClient } from '../services/ApiClient';

interface JuryParams { projectId: string; targetSeconds: number; }
interface JuryThread { question: JuryQuestion; answerText: string; turns: JuryAnswer[]; busy: boolean; }

@Entry
@Component
struct JuryPage {
  @State threads: JuryThread[] = [];
  @State busy: boolean = false;
  @State error: string = '';
  private params: JuryParams = router.getParams() as JuryParams;
  private sessionId: string = '';

  aboutToAppear(): void { this.load(); }
  private async load(): Promise<void> {
    try { this.threads = this.toThreads(await apiClient.listQuestions(this.params.projectId)); } catch (reason) { this.error = `${reason}`; }
  }
  private async generate(): Promise<void> {
    this.busy = true;
    try {
      if (this.sessionId.length === 0) this.sessionId = (await apiClient.createSession(this.params.projectId, this.params.targetSeconds)).id;
      this.threads = this.toThreads(await apiClient.generateQuestions(this.params.projectId, this.sessionId));
      this.error = '';
    } catch (reason) { this.error = `${reason}`; }
    this.busy = false;
  }
  private toThreads(questions: JuryQuestion[]): JuryThread[] {
    const result: JuryThread[] = [];
    questions.forEach((question: JuryQuestion) => result.push({ question, answerText: '', turns: [], busy: false }));
    return result;
  }
  private updateAnswer(index: number, value: string): void {
    const current = this.threads[index];
    this.threads[index] = { question: current.question, answerText: value, turns: current.turns, busy: current.busy };
    this.threads = this.threads.slice();
  }
  private async ensureSession(question: JuryQuestion): Promise<string> {
    if (question.session_id !== undefined && question.session_id.length > 0) return question.session_id;
    if (this.sessionId.length === 0) this.sessionId = (await apiClient.createSession(this.params.projectId, this.params.targetSeconds)).id;
    return this.sessionId;
  }
  private async submit(index: number): Promise<void> {
    const current = this.threads[index];
    const answer = current.answerText.trim();
    if (answer.length === 0 || current.busy) return;
    this.threads[index] = { question: current.question, answerText: current.answerText, turns: current.turns, busy: true };
    this.threads = this.threads.slice();
    try {
      const sessionId = await this.ensureSession(current.question);
      const parentId = current.turns.length === 0 ? undefined : current.turns[current.turns.length - 1].id;
      const result = await apiClient.submitAnswer(current.question.id, sessionId, answer, parentId);
      this.threads[index] = { question: current.question, answerText: '', turns: current.turns.concat(result), busy: false };
      this.error = '';
    } catch (reason) {
      this.threads[index] = { question: current.question, answerText: current.answerText, turns: current.turns, busy: false };
      this.error = `${reason}`;
    }
    this.threads = this.threads.slice();
  }

  build() {
    Column() {
      Row() { Button('‹').width(42).height(42).fontSize(28).fontColor('#18211D').backgroundColor(Color.Transparent).onClick(() => router.back()); Text('AI评委席').fontSize(22).fontWeight(FontWeight.Bold) }.width('100%')
      Text('让追问逼近薄弱处').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#18211D').margin({ top: 18 }).width('100%')
      Text('问题依据当前项目材料').fontSize(14).fontColor('#67716B').margin({ top: 7 }).width('100%')
      Button(this.busy ? '正在研读材料' : '生成一组评委问题').enabled(!this.busy).width('100%').height(50).margin({ top: 20 }).borderRadius(6).backgroundColor('#176B5B').onClick(() => this.generate())
      if (this.error.length > 0) { Text(this.error).fontColor('#C8573B').margin({ top: 10 }).width('100%') }
      List({ space: 12 }) {
        ForEach(this.threads, (thread: JuryThread, index: number) => {
          ListItem() {
            Column({ space: 9 }) {
              Row() { Text(`${index + 1}`.padStart(2, '0')).fontColor('#C8573B').fontWeight(FontWeight.Bold); Text(thread.question.category).fontSize(12).fontWeight(FontWeight.Bold).padding({ left: 8, right: 8, top: 3, bottom: 3 }).margin({ left: 10 }).backgroundColor('#E8E2D4').borderRadius(4) }.width('100%')
              Text(thread.question.question).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#18211D').width('100%')
              if (thread.question.evidence.length > 0) { Text(`依据：${thread.question.evidence[0].quote}`).fontSize(12).fontColor('#67716B').maxLines(2).width('100%') }
              ForEach(thread.turns, (turn: JuryAnswer, turnIndex: number) => {
                Divider().color('#D4CEC0').margin({ top: 6, bottom: 6 })
                Text(`第${turnIndex + 1}轮 · ${turn.asked_question}`).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#18211D').width('100%')
                Text(`你的回答：${turn.answer_text}`).fontSize(13).fontColor('#3C4641').width('100%')
                Text(`评委反馈 ${turn.evaluation.score} / 100`).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#176B5B').width('100%')
                if (turn.evaluation.relevance !== undefined) { Text(`相关性：${turn.evaluation.relevance}`).fontSize(13).fontColor('#3C4641').width('100%') }
                if (turn.evaluation.accuracy !== undefined) { Text(`准确性：${turn.evaluation.accuracy}`).fontSize(13).fontColor('#3C4641').width('100%') }
              }, (turn: JuryAnswer) => turn.id)
              if (thread.turns.length > 0) { Text(`当前追问：${thread.turns[thread.turns.length - 1].evaluation.follow_up}`).fontSize(14).fontWeight(FontWeight.Bold).fontColor('#C8573B').width('100%') }
              TextArea({ text: thread.answerText, placeholder: thread.turns.length === 0 ? '组织你的回答' : '回答当前追问' }).height(92).backgroundColor('#F7F4EC').border({ width: 1, color: '#D4CEC0', radius: 5 }).onChange((value: string) => this.updateAnswer(index, value))
              Button(thread.busy ? '正在评议' : (thread.turns.length === 0 ? '提交评议' : '回答追问')).enabled(!thread.busy && thread.answerText.trim().length > 0).width('100%').height(44).borderRadius(5).backgroundColor('#176B5B').onClick(() => this.submit(index))
            }.alignItems(HorizontalAlign.Start).padding(16).backgroundColor('#FFFDF8').border({ width: 1, color: '#D4CEC0', radius: 7 })
          }
        }, (thread: JuryThread) => thread.question.id)
      }.layoutWeight(1).width('100%').margin({ top: 20 })
    }.width('100%').height('100%').padding(20).backgroundColor('#F4F1E8')
  }
}
