import { router } from '@kit.ArkUI';
import { JuryAnswer, JuryEvaluation, JuryQuestion } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { CameraStage } from '../ui/CameraStage';
import { Palette } from '../ui/Palette';

interface JuryParams { projectId: string; targetSeconds: number; sessionId: string; }

@Entry
@Component
struct JuryPage {
  @State questions: JuryQuestion[] = [];
  @State activePrompt: string = '';
  @State answerText: string = '';
  @State draftAnswer: string = '';
  @State elapsed: number = 0;
  @State busy: boolean = true;
  @State retryAttempt: number = 0;
  @State error: string = '';
  @State showEnd: boolean = false;
  @State showAnswer: boolean = false;
  @State showReview: boolean = false;
  @State voiceRecording: boolean = false;
  @State pendingAdvance: boolean = false;
  @State lastEvaluation?: JuryEvaluation = undefined;
  private params: JuryParams = router.getParams() as JuryParams;
  private parentAnswerId?: string = undefined;
  private pendingRequestId: string = '';
  private timer: number = -1;
  private timerRunning: boolean = false;

  aboutToAppear(): void {
    this.initialize();
  }

  aboutToDisappear(): void {
    this.pauseTimer();
  }

  private clock(seconds: number): string {
    return String(Math.floor(seconds / 60)).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
  }

  private resumeTimer(): void {
    if (this.timerRunning || this.busy) return;
    this.timerRunning = true;
    this.timer = setInterval(() => this.elapsed += 1, 1000);
  }

  private pauseTimer(): void {
    this.timerRunning = false;
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private currentQuestion(): JuryQuestion | undefined {
    return this.questions.length === 0 ? undefined : this.questions[this.questions.length - 1];
  }

  private statusText(): string {
    if (this.retryAttempt > 0) return 'AI 服务暂时未完成请求，正在自动重试（' + String(this.retryAttempt) + '/5）';
    if (this.busy && this.questions.length === 0) return '评委正在阅读材料与现场陈述';
    if (this.busy) return '评委正在思考';
    if (this.voiceRecording) return '正在回答';
    return '请回答';
  }

  private async delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => setTimeout(resolve, milliseconds));
  }

  private async generateWithRetry(count: number): Promise<JuryQuestion[]> {
    let lastMessage: string = 'AI 服务暂时未完成请求';
    for (let attempt = 0; attempt <= 5; attempt += 1) {
      if (attempt > 0) {
        this.retryAttempt = attempt;
        await this.delay(250 * attempt);
      }
      try {
        const questions = await apiClient.generateQuestions(this.params.projectId, this.params.sessionId, count);
        this.retryAttempt = 0;
        return questions;
      } catch (reason) {
        lastMessage = String(reason);
      }
    }
    this.retryAttempt = 0;
    throw new Error(lastMessage);
  }

  private async submitWithRetry(question: JuryQuestion): Promise<JuryAnswer> {
    let lastMessage: string = 'AI 服务暂时未完成请求';
    for (let attempt = 0; attempt <= 5; attempt += 1) {
      if (attempt > 0) {
        this.retryAttempt = attempt;
        await this.delay(250 * attempt);
      }
      try {
        const result = await apiClient.submitAnswer(
          question.id,
          this.params.sessionId,
          this.answerText.trim(),
          this.parentAnswerId,
          this.pendingRequestId,
          this.elapsed
        );
        this.retryAttempt = 0;
        return result;
      } catch (reason) {
        lastMessage = String(reason);
      }
    }
    this.retryAttempt = 0;
    throw new Error(lastMessage);
  }

  private async initialize(): Promise<void> {
    this.pauseTimer();
    this.busy = true;
    this.error = '';
    try {
      const questions = await this.generateWithRetry(1);
      this.questions = questions;
      this.activePrompt = this.currentQuestion()?.question ?? '';
      if (this.activePrompt.length === 0) this.error = '暂时没有生成有效问题';
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.busy = false;
      if (this.activePrompt.length > 0) this.resumeTimer();
    }
  }

  private openAnswerSheet(): void {
    if (this.busy || this.activePrompt.length === 0) return;
    this.voiceRecording = false;
    this.draftAnswer = this.answerText;
    this.showAnswer = true;
  }

  private closeAnswerSheet(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.showAnswer = false;
  }

  private toggleVoice(): void {
    if (this.busy || this.activePrompt.length === 0) return;
    if (!this.voiceRecording) {
      this.voiceRecording = true;
      return;
    }
    this.voiceRecording = false;
    this.openAnswerSheet();
  }

  private async submitDraft(): Promise<void> {
    if (this.draftAnswer.trim().length === 0) return;
    this.answerText = this.draftAnswer.trim();
    this.closeAnswerSheet();
    await this.submit();
  }

  private async submit(): Promise<void> {
    const question = this.currentQuestion();
    if (question === undefined || this.answerText.trim().length === 0 || this.busy) return;
    this.pauseTimer();
    this.busy = true;
    this.error = '';
    if (this.pendingRequestId.length === 0) {
      this.pendingRequestId = this.params.sessionId + '_' + question.id + '_' + String(Date.now());
    }
    try {
      const answer = await this.submitWithRetry(question);
      this.lastEvaluation = answer.evaluation;
      this.showReview = false;
      this.answerText = '';
      this.draftAnswer = '';
      this.pendingRequestId = '';
      const followUp = answer.evaluation.follow_up?.trim() ?? '';
      if (answer.evaluation.decision === 'follow_up' && followUp.length > 0) {
        this.parentAnswerId = answer.id;
        this.activePrompt = followUp;
        this.busy = false;
        this.resumeTimer();
        return;
      }
      if (answer.evaluation.decision === 'end_defense') {
        this.busy = false;
        this.finish();
        return;
      }
      this.parentAnswerId = undefined;
      this.pendingAdvance = true;
      await this.loadNext();
    } catch (reason) {
      this.error = String(reason);
      this.busy = false;
      this.resumeTimer();
    }
  }

  private async loadNext(): Promise<void> {
    this.pauseTimer();
    this.busy = true;
    try {
      const next = await this.generateWithRetry(this.questions.length + 1);
      if (next.length <= this.questions.length) throw new Error('AI 评委暂时没有生成下一道有效问题');
      this.questions = next;
      this.activePrompt = this.currentQuestion()?.question ?? '';
      this.pendingAdvance = false;
      this.error = '';
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.busy = false;
      this.resumeTimer();
    }
  }

  private async retry(): Promise<void> {
    if (this.busy) return;
    this.error = '';
    if (this.pendingAdvance) {
      await this.loadNext();
    } else if (this.questions.length === 0) {
      await this.initialize();
    } else if (this.answerText.trim().length > 0) {
      await this.submit();
    } else {
      await this.loadNext();
    }
  }

  private finish(): void {
    this.pauseTimer();
    this.voiceRecording = false;
    this.showEnd = false;
    router.replaceUrl({
      url: 'pages/ReportPage',
      params: {
        sessionId: this.params.sessionId,
        projectId: this.params.projectId,
        generate: true
      }
    });
  }

  @Builder
  private topBar() {
    Row() {
      Row({ space: 7 }) {
        Text('').width(7).height(7)
          .backgroundColor(this.voiceRecording ? '#4ADE80' : '#9AB8FF').borderRadius(4)
        Text('AI 答辩').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
      }
      Blank()
      Text(this.clock(this.elapsed))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Palette.WHITE)
        .fontFamily('monospace')
    }.width('100%')
  }

  @Builder
  private questionOverlay() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        if (this.busy) {
          LoadingProgress().width(13).height(13).color(Palette.SIGNAL)
        } else {
          Text(this.voiceRecording ? '≋' : '').width(this.voiceRecording ? 16 : 7)
            .height(this.voiceRecording ? 16 : 7)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.SIGNAL)
            .backgroundColor(this.voiceRecording ? Color.Transparent : Palette.SIGNAL)
            .borderRadius(4)
        }
        Text(this.statusText())
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#B8FFFFFF')
          .layoutWeight(1)
          .maxLines(2)
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_volume')).width(21).height(21)
        }
          .width(36)
          .height(36)
          .backgroundColor(Color.Transparent)
          .enabled(!this.busy && this.activePrompt.length > 0)
      }.width('100%')
      if (this.activePrompt.length > 0) {
        Text(this.activePrompt)
          .fontSize(21)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.WHITE)
          .lineHeight(29)
          .width('100%')
          .maxLines(5)
      }
      if (this.lastEvaluation !== undefined) {
        Column({ space: 7 }) {
          Row() {
            Text('上一轮评议').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.SIGNAL)
            Blank()
            Text(this.showReview ? '收起 ︿' : '展开 ﹀').fontSize(11).fontColor('#A6FFFFFF')
          }.width('100%').onClick(() => this.showReview = !this.showReview)
          if (this.showReview) {
            Text(this.lastEvaluation?.relevance ?? this.lastEvaluation?.accuracy ?? '本轮回答已记录')
              .fontSize(12).fontColor('#C2FFFFFF').lineHeight(18).width('100%').maxLines(4)
          }
        }.padding({ top: 4 }).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private callControls() {
    Row({ space: 22 }) {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_keyboard')).width(24).height(24)
      }
        .width(54)
        .height(54)
        .backgroundColor('#4DFFFFFF')
        .borderRadius(27)
        .enabled(!this.busy && !this.voiceRecording)
        .onClick(() => this.openAnswerSheet())
      Button({ type: ButtonType.Circle }) {
        Image(this.voiceRecording ? $r('app.media.ic_stop') : $r('app.media.ic_mic_dark'))
          .width(this.voiceRecording ? 22 : 29)
          .height(this.voiceRecording ? 22 : 29)
      }
        .width(70)
        .height(70)
        .backgroundColor(this.voiceRecording ? Palette.RED : Palette.SIGNAL)
        .borderRadius(35)
        .enabled(!this.busy)
        .onClick(() => this.toggleVoice())
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.ic_call_end')).width(28).height(28)
      }
        .width(54)
        .height(54)
        .backgroundColor(Palette.RED)
        .borderRadius(27)
        .onClick(() => this.showEnd = true)
    }.width('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
  }

  @Builder
  private errorBanner() {
    Row({ space: 9 }) {
      Text('!').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
      Text(this.error).fontSize(13).fontColor(Palette.WHITE).layoutWeight(1).maxLines(3)
      Button('重试').height(34).fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
        .backgroundColor(Color.Transparent).onClick(() => this.retry())
    }
      .padding({ left: 14, right: 8, top: 10, bottom: 10 })
      .width('100%')
      .backgroundColor('#E6451F1A')
      .borderRadius(8)
  }

  @Builder
  private answerSheet() {
    Column() {
      Blank().layoutWeight(1).onClick(() => this.closeAnswerSheet())
      Column({ space: 16 }) {
        Text('').width(38).height(4).borderRadius(2).backgroundColor('#CBD0CA')
        Row() {
          Column({ space: 4 }) {
            Text('确认回答').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
            Text('确认后由 AI 评委继续追问').fontSize(13).fontColor(Palette.MUTED)
          }.alignItems(HorizontalAlign.Start)
          Blank()
          Button('×').width(38).height(38).fontSize(22).fontColor(Palette.INK)
            .backgroundColor(Palette.PAPER_STRONG).borderRadius(19).onClick(() => this.closeAnswerSheet())
        }.width('100%')
        TextArea({ text: this.draftAnswer, placeholder: '输入你的回答…' })
          .onChange((value: string) => this.draftAnswer = value)
          .height(150)
          .width('100%')
          .fontSize(16)
          .fontColor(Palette.INK)
          .placeholderColor(Palette.MUTED)
          .backgroundColor(Palette.PAPER)
          .border({ width: 1, color: Palette.LINE, radius: 8 })
          .padding(14)
        Button('提交回答')
          .height(52)
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.INK)
          .backgroundColor(Palette.SIGNAL)
          .borderRadius(8)
          .enabled(this.draftAnswer.trim().length > 0)
          .onClick(() => this.submitDraft())
      }
        .padding({ left: 20, right: 20, top: 10, bottom: 24 })
        .width('100%')
        .backgroundColor(Palette.WHITE)
        .borderRadius({ topLeft: 16, topRight: 16 })
    }.width('100%').height('100%').backgroundColor('#70000000')
  }

  @Builder
  private endSheet() {
    Column() {
      Blank().layoutWeight(1).onClick(() => this.showEnd = false)
      Column({ space: 12 }) {
        Text('').width(38).height(4).borderRadius(2).backgroundColor('#CBD0CA')
        Text('结束本次答辩？').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK).width('100%')
        Text('评委将停止提问，并根据项目陈述与已完成的回答生成综合报告。')
          .fontSize(14).fontColor(Palette.MUTED).lineHeight(21).width('100%')
        Row({ space: 10 }) {
          Button('继续答辩').height(48).layoutWeight(1).fontColor(Palette.INK)
            .backgroundColor(Palette.PAPER_STRONG).borderRadius(8).onClick(() => this.showEnd = false)
          Button('结束答辩').height(48).layoutWeight(1).fontColor(Palette.WHITE)
            .backgroundColor(Palette.RED).borderRadius(8).onClick(() => this.finish())
        }.width('100%').margin({ top: 8 })
      }.padding({ left: 22, right: 22, top: 10, bottom: 24 }).width('100%').backgroundColor(Palette.WHITE)
        .borderRadius({ topLeft: 16, topRight: 16 })
    }.width('100%').height('100%').backgroundColor('#70000000')
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      CameraStage()
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [['#66000000', 0.0], ['#00000000', 0.18], ['#00000000', 0.45], ['#EB000000', 1.0]]
        })
      Column() {
        this.topBar()
        Blank().layoutWeight(1)
        if (this.error.length > 0) {
          this.errorBanner()
          Blank().height(10)
        }
        this.questionOverlay()
        Blank().height(20)
        this.callControls()
      }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 24 })
      if (this.showAnswer) this.answerSheet()
      if (this.showEnd) this.endSheet()
    }.width('100%').height('100%').backgroundColor(Palette.NIGHT)
  }
}
