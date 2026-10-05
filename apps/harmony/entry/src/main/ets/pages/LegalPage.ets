import { router } from '@kit.ArkUI';
import { Palette } from '../ui/Palette';

interface LegalParams { kind: string; }

@Entry
@Component
struct LegalPage {
  private kind: string = (router.getParams() as LegalParams).kind;

  @Builder
  private section(title: string, content: string) {
    Column({ space: 8 }) {
      Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK).width('100%')
      Text(content).fontSize(14).fontColor(Palette.MUTED).lineHeight(23).width('100%')
    }.alignItems(HorizontalAlign.Start).width('100%').margin({ bottom: 24 })
  }

  build() {
    Column() {
      Row() {
        Button('‹').width(42).height(42).fontSize(28).fontColor(Palette.INK)
          .backgroundColor(Color.Transparent).onClick(() => router.back())
        Text(this.kind === 'privacy' ? '隐私政策' : '用户协议')
          .fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
      }.width('100%').height(56).padding({ left: 4, right: 20 })
      Scroll() {
        Column() {
          Text(this.kind === 'privacy' ? '言镜隐私政策' : '言镜用户协议')
            .fontSize(28).fontWeight(FontWeight.Bold).fontColor(Palette.INK).width('100%')
          Text('更新日期：2026 年 10 月').fontSize(12).fontColor(Palette.MUTED)
            .margin({ top: 8, bottom: 28 }).width('100%')
          if (this.kind === 'privacy') {
            this.section('一、信息范围', '账号用于识别你的个人训练空间。项目名称、材料、陈述转写、回答和报告用于提供答辩训练服务。身份、场景和训练目标仅在你主动保存后记录。')
            this.section('二、处理方式', '项目材料会在服务端解析并建立项目专属知识库，用于生成问题、核对回答和形成报告。训练页面产生的原始视频不作为长期服务端资料保存；语音识别所需临时音频按服务配置清理。')
            this.section('三、权限使用', '摄像头、麦克风、文件选择和振动权限仅在对应功能被使用时申请。拒绝可选权限不会影响账号和项目管理功能。')
            this.section('四、你的权利', '你可以查看和修改个人资料、校正材料文本、退出账号或删除项目。删除项目会同步删除其材料、知识库、训练记录与报告。')
            this.section('五、安全与联系', '服务通过访问令牌校验身份，并限制材料访问范围。如发现异常，请停止提交敏感材料并联系项目维护者处理。')
          } else {
            this.section('一、服务说明', '言镜提供个人答辩训练、材料检索、模拟提问和训练报告。AI 输出用于练习参考，不替代学校、赛事或专家的正式评审结论。')
            this.section('二、账号使用', '你应妥善保管账号凭据，不得利用服务上传违法内容、侵犯他人权益的材料，或对系统进行未经授权的攻击和批量调用。')
            this.section('三、内容责任', '你应确保对上传材料具有合法使用权。系统会尽力提供与材料相关的提问和评价，但生成式模型可能存在遗漏或误差，请结合原文核验。')
            this.section('四、服务变更', '测试期间的功能、模型和接口可能调整。因网络、模型供应商或设备能力造成的暂时不可用，系统会提供重试或保留可恢复信息。')
            this.section('五、终止使用', '你可以随时退出登录并停止使用服务。需要彻底删除某一项目时，可在项目页面执行删除操作。')
          }
        }.alignItems(HorizontalAlign.Start).width('100%')
          .padding({ left: 22, right: 22, top: 16, bottom: 36 })
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(Palette.PAPER)
  }
}
