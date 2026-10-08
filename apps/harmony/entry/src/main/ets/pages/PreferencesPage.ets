import { router } from '@kit.ArkUI';
import { UserProfile, UserProfileUpdate } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

const EDIT_IDENTITIES: string[] = ['本科生', '硕士研究生', '博士研究生', '高职学生', '教师或指导老师', '创业团队成员', '职场人士', '其他'];
const EDIT_SCENARIOS: string[] = ['毕业答辩', '课程答辩', '创新创业大赛', '学科竞赛', '项目路演', '技术面试', '其他'];
const EDIT_PURPOSES: string[] = ['提升表达', '熟悉项目', '准备评委提问', '发现材料漏洞', '控制答辩时间', '复盘长期进步', '其他'];

interface PreferenceOption { value: string; }

@Entry
@Component
struct PreferencesPage {
  @State profile?: UserProfile = undefined;
  @State identity: string = '';
  @State identityOther: string = '';
  @State scenarios: string[] = [];
  @State scenarioOther: string = '';
  @State purposes: string[] = [];
  @State purposeOther: string = '';
  @State researchConsent: boolean = false;
  @State loading: boolean = true;
  @State saving: boolean = false;
  @State error: string = '';

  aboutToAppear(): void { this.load(); }

  private async load(): Promise<void> {
    try {
      this.profile = await apiClient.getProfile();
      this.identity = this.profile.identity ?? '';
      this.identityOther = this.profile.identity_other ?? '';
      this.scenarios = this.profile.scenarios ?? [];
      this.scenarioOther = this.profile.scenario_other ?? '';
      this.purposes = this.profile.purposes ?? [];
      this.purposeOther = this.profile.purpose_other ?? '';
      this.researchConsent = this.profile.research_consent;
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.loading = false;
    }
  }

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

  private identityOptions(): PreferenceOption[] {
    return EDIT_IDENTITIES.map((value: string): PreferenceOption => ({ value }));
  }

  private async save(): Promise<void> {
    if (this.identity === '其他' && this.identityOther.trim().length === 0) {
      this.error = '请填写其他身份';
      return;
    }
    if (this.contains(this.scenarios, '其他') && this.scenarioOther.trim().length === 0) {
      this.error = '请填写其他训练场景';
      return;
    }
    if (this.contains(this.purposes, '其他') && this.purposeOther.trim().length === 0) {
      this.error = '请填写其他训练目标';
      return;
    }
    this.saving = true;
    this.error = '';
    const update: UserProfileUpdate = {
      bio: this.profile?.bio ?? '',
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
      router.back();
    } catch (reason) {
      this.error = String(reason);
      this.saving = false;
    }
  }

  @Builder
  private sectionHeading(title: string, caption: string) {
    Column({ space: 4 }) {
      Text(title).fontSize(21).fontWeight(FontWeight.Bold).fontColor(Palette.INK).width('100%')
      Text(caption).fontSize(13).fontColor(Palette.MUTED).width('100%')
    }.alignItems(HorizontalAlign.Start).width('100%')
  }

  build() {
    Column() {
      Row() {
        Button('‹').width(42).height(42).fontSize(28).fontColor(Palette.INK)
          .backgroundColor(Color.Transparent).onClick(() => router.back())
        Text('训练偏好').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        Blank()
        Button(this.saving ? '保存中' : '保存').type(ButtonType.Normal).height(40).fontSize(13)
          .fontWeight(FontWeight.Bold).fontColor(Palette.BLUE_DARK).backgroundColor(Color.Transparent)
          .enabled(!this.saving && !this.loading).onClick(() => this.save())
      }.width('100%').height(56).padding({ left: 4, right: 12 })
      if (this.loading) {
        LoadingProgress().width(30).height(30).color(Palette.BLUE).layoutWeight(1)
      } else {
        Scroll() {
          Column() {
            this.sectionHeading('身份与场景', '用于调整训练侧重点，不影响账户功能。')
            Select(this.identityOptions())
              .selected(this.identity.length > 0 ? EDIT_IDENTITIES.indexOf(this.identity) : -1)
              .value(this.identity.length > 0 ? this.identity : '身份')
              .onSelect((_index: number, value: string) => this.identity = value)
              .height(56).width('100%').font({ size: 15 }).fontColor(Palette.INK)
              .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 8 })
              .margin({ top: 18 })
            if (this.identity === '其他') {
              TextInput({ text: this.identityOther, placeholder: '其他身份' })
                .onChange((value: string) => this.identityOther = value).height(50).margin({ top: 12 })
                .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 8 })
            }
            Column().height(28)
            this.sectionHeading('主要场景', '可多选。')
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(EDIT_SCENARIOS, (option: string) => {
                Text(option).fontSize(13).fontWeight(FontWeight.Medium)
                  .fontColor(this.contains(this.scenarios, option) ? Palette.WHITE : Palette.INK)
                  .padding({ left: 13, right: 13, top: 10, bottom: 10 }).margin({ right: 8, bottom: 8 })
                  .backgroundColor(this.contains(this.scenarios, option) ? Palette.INK : Color.Transparent)
                  .border({ width: 1, color: this.contains(this.scenarios, option) ? Palette.INK : Palette.INK, radius: 7 })
                  .onClick(() => this.toggleScenario(option))
              }, (option: string) => option)
            }.width('100%').margin({ top: 16 })
            if (this.contains(this.scenarios, '其他')) {
              TextInput({ text: this.scenarioOther, placeholder: '其他场景' })
                .onChange((value: string) => this.scenarioOther = value).height(50).margin({ top: 4 })
                .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 8 })
            }
            Column().height(26)
            this.sectionHeading('训练目标', '可多选。')
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
              ForEach(EDIT_PURPOSES, (option: string) => {
                Text(option).fontSize(13).fontWeight(FontWeight.Medium)
                  .fontColor(this.contains(this.purposes, option) ? Palette.WHITE : Palette.INK)
                  .padding({ left: 13, right: 13, top: 10, bottom: 10 }).margin({ right: 8, bottom: 8 })
                  .backgroundColor(this.contains(this.purposes, option) ? Palette.INK : Color.Transparent)
                  .border({ width: 1, color: this.contains(this.purposes, option) ? Palette.INK : Palette.INK, radius: 7 })
                  .onClick(() => this.togglePurpose(option))
              }, (option: string) => option)
            }.width('100%').margin({ top: 16 })
            if (this.contains(this.purposes, '其他')) {
              TextInput({ text: this.purposeOther, placeholder: '其他训练目标' })
                .onChange((value: string) => this.purposeOther = value).height(50).margin({ top: 4 })
                .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 8 })
            }
            Divider().strokeWidth(1).color(Palette.LINE).margin({ top: 26, bottom: 20 })
            Row() {
              Column({ space: 5 }) {
                Text('参与匿名产品调研').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                Text('仅汇总身份、场景和训练目标；关闭后不再用于后续调研统计。')
                  .fontSize(12).fontColor(Palette.MUTED).lineHeight(18).maxLines(2)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.researchConsent })
                .selectedColor(Palette.BLUE).onChange((value: boolean) => this.researchConsent = value)
            }.width('100%')
            if (this.error.length > 0) {
              Text(this.error).fontSize(13).fontColor(Palette.RED).padding(12).width('100%')
                .backgroundColor(Palette.SOFT_RED).borderRadius(7).margin({ top: 18 })
            }
            Column().height(36)
          }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20, top: 12 })
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      }
    }.width('100%').height('100%').backgroundColor(Palette.PAPER)
  }
}
