import { router } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { apiClient } from '../services/ApiClient';

interface TrainingParams { projectId: string; targetSeconds: number; }

@Entry
@Component
struct TrainingPage {
  @State elapsed: number = 0;
  @State recording: boolean = false;
  @State processing: boolean = false;
  @State error: string = '';
  private params: TrainingParams = router.getParams() as TrainingParams;
  private timer: number = -1;
  private sessionId: string = '';

  aboutToDisappear(): void { if (this.timer >= 0) clearInterval(this.timer); }

  private clock(seconds: number): string {
    return `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${(seconds % 60).toString().padStart(2, '0')}`;
  }

  private async start(): Promise<void> {
    this.processing = true;
    try {
      const session = await apiClient.createSession(this.params.projectId, this.params.targetSeconds);
      this.sessionId = session.id;
      this.elapsed = 0;
      this.recording = true;
      this.timer = setInterval(() => {
        this.elapsed += 1;
        if (this.elapsed === this.params.targetSeconds) {
          vibrator.startVibration({ type: 'time', duration: 500 }, { id: 0, usage: 'alarm' });
        }
      }, 1000);
    } catch (reason) { this.error = `${reason}`; }
    this.processing = false;
  }

  private stop(): void {
    if (this.timer >= 0) clearInterval(this.timer);
    this.recording = false;
    this.error = '媒体管线尚未绑定当前设备的 CameraKit/AVRecorder；本次未上传或生成分析结果。';
  }

  build() {
    Column() {
      Row() {
        Button('‹').width(42).height(42).fontSize(28).fontColor('#18211D').backgroundColor(Color.Transparent).onClick(() => router.back())
        Text('模拟答辩').fontSize(22).fontWeight(FontWeight.Bold).fontColor('#18211D')
      }.width('100%')
      Stack({ alignContent: Alignment.TopStart }) {
        XComponent({ id: 'speechmirrorCameraSurface', type: XComponentType.SURFACE })
          .width('100%').height('100%').backgroundColor('#18211D')
        Text(this.recording ? (this.elapsed > this.params.targetSeconds ? '已超时' : '录制中') : '视频仅保存在本机')
          .fontSize(12).fontColor(Color.White).fontWeight(FontWeight.Bold).padding({ left: 10, right: 10, top: 7, bottom: 7 })
          .backgroundColor('#9918211D').margin(14).borderRadius(4)
      }.width('100%').aspectRatio(0.75).margin({ top: 16 }).borderRadius(8).clip(true)
      Row({ space: 10 }) {
        Column({ space: 4 }) { Text('当前').fontSize(12).fontColor('#67716B'); Text(this.clock(this.elapsed)).fontSize(25).fontWeight(FontWeight.Bold).fontColor(this.elapsed > this.params.targetSeconds ? '#C8573B' : '#18211D') }
          .alignItems(HorizontalAlign.Start).layoutWeight(1).padding(14).backgroundColor('#FFFDF8').border({ width: 1, color: '#D4CEC0', radius: 6 })
        Column({ space: 4 }) { Text('目标').fontSize(12).fontColor('#67716B'); Text(this.clock(this.params.targetSeconds)).fontSize(25).fontWeight(FontWeight.Bold).fontColor('#18211D') }
          .alignItems(HorizontalAlign.Start).layoutWeight(1).padding(14).backgroundColor('#FFFDF8').border({ width: 1, color: '#D4CEC0', radius: 6 })
      }.width('100%').margin({ top: 14 })
      if (this.error.length > 0) { Text(this.error).fontSize(12).fontColor('#C8573B').margin({ top: 10 }).width('100%') }
      Button(this.processing ? '正在准备' : (this.recording ? '结束录制' : '开始录制'))
        .enabled(!this.processing).width('100%').height(50).margin({ top: 16 }).borderRadius(6)
        .backgroundColor(this.recording ? '#C8573B' : '#176B5B').onClick(() => this.recording ? this.stop() : this.start())
    }.width('100%').height('100%').padding(20).backgroundColor('#F4F1E8')
  }
}
