import { router } from '@kit.ArkUI';
import { apiClient } from '../services/ApiClient';

@Entry
@Component
struct LoginPage {
  @State username: string = '';
  @State password: string = '';
  @State registering: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';

  private async submit(): Promise<void> {
    if (this.username.trim().length < 3 || this.password.length < 8) {
      this.error = '用户名至少3位，密码至少8位';
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      await apiClient.login(this.username.trim(), this.password, this.registering);
      router.replaceUrl({ url: 'pages/ProjectsPage' });
    } catch (reason) {
      this.error = `${reason}`;
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Blank().layoutWeight(1)
      Column({ space: 8 }) {
        Text('SPEECHMIRROR').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#C8573B')
        Text('言镜').fontSize(42).fontWeight(FontWeight.Bold).fontColor('#18211D')
        Text('把每一次答辩，变成下一次的证据').fontSize(16).fontColor('#67716B')
      }.alignItems(HorizontalAlign.Start).width('100%')
      Blank().height(40)
      TextInput({ text: this.username, placeholder: '用户名' })
        .onChange((value: string) => this.username = value)
        .height(52).backgroundColor('#FFFDF8').border({ width: 1, color: '#D4CEC0', radius: 6 })
      TextInput({ text: this.password, placeholder: '密码' })
        .type(InputType.Password)
        .onChange((value: string) => this.password = value)
        .height(52).margin({ top: 12 }).backgroundColor('#FFFDF8').border({ width: 1, color: '#D4CEC0', radius: 6 })
      if (this.error.length > 0) {
        Text(this.error).fontSize(13).fontColor('#C8573B').margin({ top: 10 }).width('100%')
      }
      Button(this.busy ? '正在连接' : (this.registering ? '注册并进入' : '登录'))
        .enabled(!this.busy).height(50).width('100%').margin({ top: 18 }).borderRadius(6)
        .fontWeight(FontWeight.Bold).backgroundColor('#176B5B').onClick(() => this.submit())
      Button(this.registering ? '已有账号，返回登录' : '第一次使用，创建账号')
        .type(ButtonType.Normal).height(46).width('100%').margin({ top: 8 }).borderRadius(6)
        .fontColor('#18211D').backgroundColor(Color.Transparent).onClick(() => this.registering = !this.registering)
      Blank().layoutWeight(1)
      Text('视频仅保存在本机').fontSize(12).fontColor('#67716B')
    }
    .width('100%').height('100%').padding({ left: 24, right: 24, top: 24, bottom: 24 }).backgroundColor('#F4F1E8')
  }
}
