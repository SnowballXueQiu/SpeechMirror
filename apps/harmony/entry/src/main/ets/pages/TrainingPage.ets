import { router, window } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { apiClient } from '../services/ApiClient';
import { CameraStage } from '../ui/CameraStage';
import { Palette } from '../ui/Palette';

interface TrainingParams { projectId: string; targetSeconds: number; }

@Entry
@Component
struct TrainingPage {
  @State elapsed: number = 0;
  @State recording: boolean = false;
  @State processing: boolean = false;
  @State statement: string = '';
  @State draftStatement: string = '';
  @State error: string = '';
  @State showExit: boolean = false;
  @State showStatement: boolean = false;
  private params: TrainingParams = router.getParams() as TrainingParams;
  private timer: number = -1;
  private sessionId: string = '';
  private enteringJury: boolean = false;

  aboutToAppear(): void {
    this.setImmersive(true);
    setTimeout(() => this.start(), 450);
  }

  aboutToDisappear(): void {
    this.stopTimer();
    if (!this.enteringJury) this.setImmersive(false);
  }

  private async setImmersive(enabled: boolean): Promise<void> {
    try {
      const mainWindow = await window.getLastWindow(getContext(this));
      await mainWindow.setWindowLayoutFullScreen(enabled);
      await mainWindow.setWindowSystemBarProperties({
        statusBarColor: enabled ? '#00000000' : '#FFFFFFFF',
        statusBarContentColor: enabled ? '#FFFFFFFF' : '#FF111111'
      });
    } catch (_) {
    }
  }

  private stopTimer(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private clock(seconds: number): string {
    return String(Math.floor(seconds / 60)).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
  }

  private async start(): Promise<void> {
    if (this.processing || this.recording) return;
    this.processing = true;
    this.error = '';
    try {
      if (this.sessionId.length === 0) {
        const session = await apiClient.createSession(this.params.projectId, this.params.targetSeconds);
        this.sessionId = session.id;
      }
      this.elapsed = 0;
      this.recording = true;
      this.timer = setInterval(() => {
        this.elapsed += 1;
        if (this.elapsed === this.params.targetSeconds) {
          vibrator.startVibration({ type: 'time', duration: 500 }, { id: 0, usage: 'alarm' });
        }
      }, 1000);
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.processing = false;
    }
  }

  private openStatementSheet(): void {
    this.draftStatement = this.statement;
    this.showStatement = true;
  }

  private closeStatementSheet(): void {
    this.getUIContext().getFocusController().clearFocus();
    this.showStatement = false;
  }

  private async requestFinish(): Promise<void> {
    if (this.statement.trim().length < 10) {
      this.openStatementSheet();
      return;
    }
    await this.finishIntroduction();
  }

  private async finishIntroduction(): Promise<void> {
    if (!this.recording || this.processing) return;
    if (this.draftStatement.trim().length >= 10) this.statement = this.draftStatement.trim();
    if (this.statement.trim().length < 10) return;
    this.closeStatementSheet();
    this.stopTimer();
    this.recording = false;
    this.processing = true;
    this.error = '';
    try {
      await apiClient.completeSession(this.sessionId, Math.max(1, this.elapsed), this.statement.trim());
      this.enteringJury = true;
      router.replaceUrl({
        url: 'pages/JuryPage',
        params: {
          projectId: this.params.projectId,
          targetSeconds: this.params.targetSeconds,
          sessionId: this.sessionId
        }
      });
    } catch (reason) {
      this.enteringJury = false;
      this.error = '陈述尚未提交：' + String(reason);
      this.recording = true;
      this.timer = setInterval(() => this.elapsed += 1, 1000);
    } finally {
      this.processing = false;
    }
  }

  private exit(): void {
    this.stopTimer();
    router.back();
  }

  @Builder
  private topBar() {
    Row() {
      Button('×')
        .width(42)
        .height(42)
        .fontSize(26)
        .fontWeight(FontWeight.Lighter)
        .fontColor(Palette.WHITE)
        .backgroundColor('#66000000')
        .borderRadius(21)
        .onClick(() => this.recording ? this.showExit = true : router.back())
      Row({ space: 7 }) {
        Text('').width(7).height(7).backgroundColor(Palette.RED).borderRadius(4)
        Text('项目陈述').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
      }.margin({ left: 10 })
      Blank()
      Text(this.clock(this.elapsed))
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.elapsed >= this.params.targetSeconds ? Palette.SIGNAL : Palette.WHITE)
        .fontFamily('monospace')
    }.width('100%')
  }

  @Builder
  private statusArea() {
    Column({ space: 9 }) {
      Row({ space: 7 }) {
        if (this.processing) {
          LoadingProgress().width(13).height(13).color(Palette.SIGNAL)
        } else {
          Text('').width(7).height(7).backgroundColor(Palette.SIGNAL).borderRadius(4)
        }
        Text(this.processing ? '正在准备' : (this.recording ? '项目陈述进行中' : '模拟答辩'))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#B8FFFFFF')
      }
      Text(this.processing ? '正在连接训练服务' : (this.recording ? '面向镜头完成项目介绍' : '准备好后开始'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(Palette.WHITE)
        .textAlign(TextAlign.Center)
        .maxLines(2)
      Row() {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_keyboard')).width(23).height(23)
        }
          .width(50)
          .height(50)
          .backgroundColor('#4DFFFFFF')
          .borderRadius(25)
          .enabled(this.recording && !this.processing)
          .onClick(() => this.openStatementSheet())
        Column({ space: 8 }) {
          Button(this.processing ? '···' : (this.recording ? '→' : '●'))
            .width(70)
            .height(70)
            .fontSize(this.recording ? 30 : 20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.INK)
            .backgroundColor(this.recording ? Palette.WHITE : Palette.SIGNAL)
            .borderRadius(35)
            .enabled(!this.processing)
            .onClick(() => this.recording ? this.requestFinish() : this.start())
          Text(this.processing ? '正在准备' : (this.recording ? '结束介绍' : '开始介绍'))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor(Palette.WHITE)
        }.alignItems(HorizontalAlign.Center).width(116)
        Blank().width(50)
      }.width('100%').justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Top)
    }.width('100%').alignItems(HorizontalAlign.Center)
  }

  @Builder
  private errorBanner() {
    Row({ space: 10 }) {
      Text('!').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
      Text(this.error).fontSize(13).fontColor(Palette.WHITE).layoutWeight(1).maxLines(3)
      Button('重试')
        .height(34)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(Palette.WHITE)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.recording ? this.requestFinish() : this.start())
    }
      .padding({ left: 14, right: 8, top: 10, bottom: 10 })
      .width('100%')
      .backgroundColor('#E6451F1A')
      .borderRadius(8)
  }

  @Builder
  private statementSheet() {
    Column() {
      Blank().layoutWeight(1).onClick(() => this.closeStatementSheet())
      Column({ space: 16 }) {
        Text('').width(38).height(4).borderRadius(2).backgroundColor('#CBD0CA')
        Row() {
          Column({ space: 4 }) {
            Text('现场陈述').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
            Text('模拟器输入将作为本次现场介绍').fontSize(13).fontColor(Palette.MUTED)
          }.alignItems(HorizontalAlign.Start)
          Blank()
          Button('×')
            .width(38)
            .height(38)
            .fontSize(22)
            .fontColor(Palette.INK)
            .backgroundColor(Palette.PAPER_STRONG)
            .borderRadius(19)
            .onClick(() => this.closeStatementSheet())
        }.width('100%')
        TextArea({ text: this.draftStatement, placeholder: '输入你的项目陈述…' })
          .onChange((value: string) => this.draftStatement = value)
          .height(150)
          .width('100%')
          .fontSize(16)
          .fontColor(Palette.INK)
          .placeholderColor(Palette.MUTED)
          .backgroundColor(Palette.PAPER)
          .border({ width: 1, color: Palette.LINE, radius: 8 })
          .padding(14)
        Button('完成并进入答辩')
          .height(52)
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor(Palette.INK)
          .backgroundColor(Palette.SIGNAL)
          .borderRadius(8)
          .enabled(this.draftStatement.trim().length >= 10)
          .onClick(() => this.finishIntroduction())
      }
        .padding({ left: 20, right: 20, top: 10, bottom: 24 })
        .width('100%')
        .backgroundColor(Palette.WHITE)
        .borderRadius({ topLeft: 16, topRight: 16 })
    }.width('100%').height('100%').backgroundColor('#70000000')
  }

  @Builder
  private exitSheet() {
    Column() {
      Blank().layoutWeight(1).onClick(() => this.showExit = false)
      Column({ space: 12 }) {
        Text('').width(38).height(4).borderRadius(2).backgroundColor('#CBD0CA')
        Text('退出本次陈述？').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK).width('100%')
        Text('当前尚未提交的陈述内容不会进入答辩报告。')
          .fontSize(14).fontColor(Palette.MUTED).lineHeight(21).width('100%')
        Row({ space: 10 }) {
          Button('继续陈述').height(48).layoutWeight(1).fontColor(Palette.INK)
            .backgroundColor(Palette.PAPER_STRONG).borderRadius(8).onClick(() => this.showExit = false)
          Button('退出').height(48).layoutWeight(1).fontColor(Palette.WHITE)
            .backgroundColor(Palette.RED).borderRadius(8).onClick(() => this.exit())
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
          colors: [['#66000000', 0.0], ['#00000000', 0.19], ['#00000000', 0.54], ['#E6000000', 1.0]]
        })
      Column() {
        this.topBar()
        Blank().layoutWeight(1)
        if (this.error.length > 0) {
          this.errorBanner()
          Blank().height(10)
        }
        this.statusArea()
      }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 48, bottom: 24 })
      if (this.showStatement) this.statementSheet()
      if (this.showExit) this.exitSheet()
    }
      .width('100%')
      .height('100%')
      .backgroundColor(Palette.NIGHT)
      .expandSafeArea(
        [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
        [SafeAreaEdge.TOP]
      )
  }
}
