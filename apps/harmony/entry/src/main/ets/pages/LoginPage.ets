import { router } from '@kit.ArkUI';
import { UserProfile } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

@Entry
@Component
struct LoginPage {
  @State username: string = '';
  @State password: string = '';
  @State registering: boolean = false;
  @State busy: boolean = false;
  @State restoring: boolean = true;
  @State error: string = '';
  @State showPassword: boolean = false;

  aboutToAppear(): void {
    this.restore();
  }

  private async restore(): Promise<void> {
    try {
      if (await apiClient.restoreSession()) {
        const profile = await apiClient.getProfile();
        this.openHome(profile);
        return;
      }
    } catch (_) {}
    this.restoring = false;
  }

  private openHome(profile: UserProfile): void {
    router.replaceUrl({ url: profile.onboarding_completed ? 'pages/ProjectsPage' : 'pages/OnboardingPage' });
  }

  private async submit(): Promise<void> {
    if (!/^[A-Za-z0-9_-]{3,32}$/.test(this.username.trim())) {
      this.error = '请输入 3-32 位字母、数字、下划线或连字符';
      return;
    }
    if (this.password.length < 8 || this.password.length > 128) {
      this.error = '密码长度需为 8-128 个字符';
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      const profile = await apiClient.login(this.username.trim(), this.password, this.registering);
      this.openHome(profile);
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.busy = false;
    }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.restoring) {
        Column({ space: 16 }) {
          Image($r('app.media.app_icon')).width(86).height(86).objectFit(ImageFit.Contain)
          LoadingProgress().width(26).height(26).color(Palette.INK)
        }
      } else {
        Scroll() {
          Column() {
            Row({ space: 13 }) {
              Image($r('app.media.app_icon')).width(58).height(58).objectFit(ImageFit.Contain).borderRadius(12)
              Column({ space: 2 }) {
                Text('言镜').fontSize(23).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                Text('SpeechMirror').fontSize(13).fontColor(Palette.MUTED)
              }.alignItems(HorizontalAlign.Start)
            }.width('100%')
            Text(this.registering ? '创建账号' : '欢迎回来')
              .fontSize(30).fontWeight(FontWeight.Bold).fontColor(Palette.INK).margin({ top: 46 }).width('100%')
            Text(this.registering ? '创建你的个人答辩训练空间' : '登录后继续你的答辩训练')
              .fontSize(15).fontColor(Palette.MUTED).margin({ top: 8, bottom: 30 }).width('100%')
            Column({ space: 8 }) {
              Text('用户名').fontSize(12).fontWeight(FontWeight.Medium).fontColor(Palette.MUTED).width('100%')
              TextInput({ text: this.username, placeholder: '用户名' })
                .onChange((value: string) => this.username = value)
                .height(54).padding({ left: 15, right: 15 }).backgroundColor(Palette.WHITE)
                .border({ width: 1, color: Palette.LINE, radius: 8 })
            }.width('100%').alignItems(HorizontalAlign.Start)
            Column({ space: 8 }) {
              Text('密码').fontSize(12).fontWeight(FontWeight.Medium).fontColor(Palette.MUTED).width('100%')
              Row() {
                TextInput({ text: this.password, placeholder: '密码' })
                  .type(this.showPassword ? InputType.Normal : InputType.Password)
                  .onChange((value: string) => this.password = value)
                  .height(52).layoutWeight(1).backgroundColor(Color.Transparent)
                Button(this.showPassword ? '隐藏' : '显示').type(ButtonType.Normal)
                  .height(40).fontSize(12).fontColor(Palette.BLUE_DARK).backgroundColor(Color.Transparent)
                  .onClick(() => this.showPassword = !this.showPassword)
              }.height(54).padding({ left: 3, right: 6 }).backgroundColor(Palette.WHITE)
                .border({ width: 1, color: Palette.LINE, radius: 8 })
            }.width('100%').alignItems(HorizontalAlign.Start).margin({ top: 16 })
            if (this.error.length > 0) {
              Row({ space: 8 }) {
                Text('!').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.RED)
                Text(this.error).fontSize(13).fontColor(Palette.RED).layoutWeight(1)
              }.padding(12).width('100%').margin({ top: 14 }).backgroundColor(Palette.SOFT_RED).borderRadius(7)
            }
            Button(this.busy ? '正在连接' : (this.registering ? '创建账号' : '进入训练台'))
              .enabled(!this.busy).height(52).width('100%').margin({ top: 22 }).borderRadius(7)
              .fontWeight(FontWeight.Bold).fontColor(Palette.WHITE).backgroundColor(Palette.INK)
              .onClick(() => this.submit())
            Button(this.registering ? '已有账号，直接登录' : '第一次使用，创建账号')
              .type(ButtonType.Normal).height(48).width('100%').margin({ top: 8 }).borderRadius(7)
              .fontColor(Palette.BLUE_DARK).backgroundColor(Color.Transparent)
              .onClick(() => {
                this.registering = !this.registering;
                this.error = '';
              })
          }.width('100%').padding({ left: 24, right: 24, top: 38, bottom: 30 })
        }.width('100%').height('100%')
      }
    }.width('100%').height('100%').backgroundColor(Palette.PAPER)
  }
}
