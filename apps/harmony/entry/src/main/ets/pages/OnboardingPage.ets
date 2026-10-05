import { router } from '@kit.ArkUI';
import { UserProfileUpdate } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

const IDENTITIES: string[] = ['本科生', '硕士研究生', '博士研究生', '高职学生', '教师或指导老师', '创业团队成员', '职场人士', '其他'];
const SCENARIOS: string[] = ['毕业答辩', '课程答辩', '创新创业大赛', '学科竞赛', '项目路演', '技术面试', '其他'];
const PURPOSES: string[] = ['提升表达', '熟悉项目', '准备评委提问', '发现材料漏洞', '控制答辩时间', '复盘长期进步', '其他'];

@Entry
@Component
struct OnboardingPage {
  @State step: number = 0;
  @State identity: string = '';
  @State identityOther: string = '';
  @State scenarios: string[] = [];
  @State scenarioOther: string = '';
  @State purposes: string[] = [];
  @State purposeOther: string = '';
  @State researchConsent: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';

  private contains(items: string[], value: string): boolean {
    return items.indexOf(value) >= 0;
  }

  private toggleScenario(value: string): void {
    this.scenarios = this.contains(this.scenarios, value) ?
      this.scenarios.filter((item: string) => item !== value) : this.scenarios.concat(value);
  }

  private togglePurpose(value: string): void {
    this.purposes = this.contains(this.purposes, value) ?
      this.purposes.filter((item: string) => item !== value) : this.purposes.concat(value);
  }

  private async next(): Promise<void> {
    this.error = '';
    if (this.step === 0 && this.identity === '其他' && this.identityOther.trim().length === 0) {
      this.error = '请填写你的身份';
      return;
    }
    if (this.step === 1 && this.contains(this.scenarios, '其他') && this.scenarioOther.trim().length === 0) {
      this.error = '请填写其他训练场景';
      return;
    }
    if (this.step < 2) {
      this.step += 1;
      return;
    }
    if (this.contains(this.purposes, '其他') && this.purposeOther.trim().length === 0) {
      this.error = '请填写其他训练目标';
      return;
    }
    await this.save();
  }

  private async skip(): Promise<void> {
    this.identity = '';
    this.scenarios = [];
    this.purposes = [];
    this.researchConsent = false;
    await this.save();
  }

  private async save(): Promise<void> {
    this.busy = true;
    this.error = '';
    const update: UserProfileUpdate = {
      identity: this.identity.length > 0 ? this.identity : undefined,
      identity_other: this.identity === '其他' ? this.identityOther.trim() : undefined,
      scenario: this.scenarios.length > 0 ? this.scenarios[0] : undefined,
      scenarios: this.scenarios,
      scenario_other: this.contains(this.scenarios, '其他') ? this.scenarioOther.trim() : undefined,
      purposes: this.purposes,
      purpose_other: this.contains(this.purposes, '其他') ? this.purposeOther.trim() : undefined,
      onboarding_completed: true,
      research_consent: this.researchConsent
    };
    try {
      await apiClient.updateProfile(update);
      router.replaceUrl({ url: 'pages/ProjectsPage' });
    } catch (reason) {
      this.error = String(reason);
      this.busy = false;
    }
  }

  @Builder
  private heading(number: string, title: string, description: string) {
    Column({ space: 8 }) {
      Text(number).fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.BLUE)
      Text(title).fontSize(27).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
      Text(description).fontSize(14).fontColor(Palette.MUTED).lineHeight(21)
    }.alignItems(HorizontalAlign.Start).width('100%')
  }

  build() {
    Column() {
      Row() {
        Text('设置你的训练方式').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        Blank()
        Button('跳过').type(ButtonType.Normal).height(40).fontColor(Palette.BLUE_DARK)
          .backgroundColor(Color.Transparent).enabled(!this.busy).onClick(() => this.skip())
      }.width('100%').height(58).padding({ left: 20, right: 12 })
      Row({ space: 6 }) {
        ForEach([0, 1, 2], (index: number) => {
          Row().height(3).layoutWeight(1).borderRadius(2)
            .backgroundColor(index <= this.step ? Palette.INK : Palette.PAPER_STRONG)
        })
      }.width('100%').padding({ left: 20, right: 20 }).margin({ bottom: 12 })
      Scroll() {
        Column() {
          if (this.step === 0) {
            this.heading('01', '你现在的身份', '用于调整提问难度与表达方式，可随时修改。')
            Column({ space: 9 }) {
              ForEach(IDENTITIES, (option: string) => {
                Row() {
                  Text(option).fontSize(15).fontWeight(FontWeight.Medium)
                    .fontColor(this.identity === option ? Palette.WHITE : Palette.INK)
                  Blank()
                  Text(this.identity === option ? '✓' : '').fontSize(17).fontWeight(FontWeight.Bold)
                    .fontColor(Palette.SIGNAL)
                }.height(50).padding({ left: 15, right: 15 }).width('100%').borderRadius(7)
                  .backgroundColor(this.identity === option ? Palette.INK : Palette.WHITE)
                  .border({ width: this.identity === option ? 0 : 1, color: Palette.LINE })
                  .onClick(() => this.identity = option)
              }, (option: string) => option)
            }.width('100%').margin({ top: 24 })
            if (this.identity === '其他') {
              TextInput({ text: this.identityOther, placeholder: '输入你的身份' })
                .onChange((value: string) => this.identityOther = value).height(52).margin({ top: 12 })
                .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 7 })
            }
          } else if (this.step === 1) {
            this.heading('02', '主要训练场景', '可多选，言镜会据此组织评委视角和训练重点。')
            Column({ space: 9 }) {
              ForEach(SCENARIOS, (option: string) => {
                Row() {
                  Text(option).fontSize(15).fontWeight(FontWeight.Medium).fontColor(Palette.INK)
                  Blank()
                  Checkbox({ name: option, group: 'scenario' }).select(this.contains(this.scenarios, option))
                    .selectedColor(Palette.INK).onChange(() => this.toggleScenario(option))
                }.height(50).padding({ left: 15, right: 10 }).width('100%').backgroundColor(Palette.WHITE)
                  .border({ width: 1, color: this.contains(this.scenarios, option) ? Palette.INK : Palette.LINE, radius: 7 })
                  .onClick(() => this.toggleScenario(option))
              }, (option: string) => option)
            }.width('100%').margin({ top: 24 })
            if (this.contains(this.scenarios, '其他')) {
              TextInput({ text: this.scenarioOther, placeholder: '输入其他使用场景' })
                .onChange((value: string) => this.scenarioOther = value).height(52).margin({ top: 12 })
                .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 7 })
            }
          } else {
            this.heading('03', '你想重点提升什么', '可多选，也可以暂不选择。')
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(PURPOSES, (option: string) => {
                Text(option).fontSize(14).fontWeight(FontWeight.Medium)
                  .fontColor(this.contains(this.purposes, option) ? Palette.WHITE : Palette.INK)
                  .padding({ left: 14, right: 14, top: 10, bottom: 10 }).margin({ right: 8, bottom: 8 })
                  .backgroundColor(this.contains(this.purposes, option) ? Palette.INK : Palette.WHITE)
                  .border({ width: 1, color: this.contains(this.purposes, option) ? Palette.INK : Palette.LINE, radius: 6 })
                  .onClick(() => this.togglePurpose(option))
              }, (option: string) => option)
            }.width('100%').margin({ top: 24 })
            if (this.contains(this.purposes, '其他')) {
              TextInput({ text: this.purposeOther, placeholder: '输入其他训练目标' })
                .onChange((value: string) => this.purposeOther = value).height(52).margin({ top: 6 })
                .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 7 })
            }
            Divider().strokeWidth(1).color(Palette.LINE).margin({ top: 26, bottom: 20 })
            Row() {
              Column({ space: 5 }) {
                Text('参与匿名产品调研').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                Text('仅汇总身份、场景和训练目标').fontSize(12).fontColor(Palette.MUTED)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.researchConsent })
                .selectedColor(Palette.BLUE).onChange((value: boolean) => this.researchConsent = value)
            }.width('100%')
          }
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor(Palette.RED).padding(12).width('100%')
              .backgroundColor(Palette.SOFT_RED).borderRadius(7).margin({ top: 18 })
          }
        }.width('100%').padding({ left: 20, right: 20, top: 14, bottom: 30 })
      }.layoutWeight(1).width('100%')
      Row({ space: 10 }) {
        if (this.step > 0) {
          Button('‹').width(50).height(50).fontSize(25).fontColor(Palette.INK)
            .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 7 })
            .enabled(!this.busy).onClick(() => this.step -= 1)
        }
        Button(this.busy ? '正在保存' : (this.step === 2 ? '完成设置' : '继续  →'))
          .height(50).layoutWeight(1).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
          .backgroundColor(Palette.INK).borderRadius(7).enabled(!this.busy).onClick(() => this.next())
      }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 14 })
        .border({ width: { top: 1 }, color: Palette.LINE }).backgroundColor(Palette.PAPER)
    }.width('100%').height('100%').backgroundColor(Palette.PAPER)
  }
}
