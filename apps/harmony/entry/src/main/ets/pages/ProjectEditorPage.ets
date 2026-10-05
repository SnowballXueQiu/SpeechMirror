import { router } from '@kit.ArkUI';
import { Project } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

interface EditorParams { projectJson?: string; }

@Entry
@Component
struct ProjectEditorPage {
  @State name: string = '';
  @State description: string = '';
  @State duration: number = 300;
  @State busy: boolean = false;
  @State error: string = '';
  private project?: Project = undefined;

  aboutToAppear(): void {
    const params = router.getParams() as EditorParams;
    if (params.projectJson !== undefined && params.projectJson.length > 0) {
      try {
        this.project = JSON.parse(params.projectJson) as Project;
        this.name = this.project.name;
        this.description = this.project.description ?? '';
        this.duration = this.project.defense_duration_seconds;
      } catch (_) {}
    }
  }

  private async save(): Promise<void> {
    if (this.name.trim().length === 0) {
      this.error = '请填写项目名称';
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      if (this.project === undefined) {
        const created = await apiClient.createProject(this.name.trim(), this.description.trim(), this.duration);
        router.replaceUrl({ url: 'pages/ProjectPage', params: { projectId: created.id } });
      } else {
        await apiClient.updateProject(this.project.id, this.name.trim(), this.description.trim(), this.duration);
        router.back();
      }
    } catch (reason) {
      this.error = String(reason);
      this.busy = false;
    }
  }

  @Builder
  private durationButton(label: string, seconds: number) {
    Button(label).height(44).layoutWeight(1).borderRadius(6)
      .fontWeight(FontWeight.Bold).fontColor(this.duration === seconds ? Palette.WHITE : Palette.INK)
      .backgroundColor(this.duration === seconds ? Palette.INK : Palette.WHITE)
      .border({ width: 1, color: this.duration === seconds ? Palette.INK : Palette.LINE })
      .onClick(() => this.duration = seconds)
  }

  build() {
    Column() {
      Row() {
        Button('‹').width(42).height(42).fontSize(28).fontColor(Palette.INK)
          .backgroundColor(Color.Transparent).onClick(() => router.back())
        Text(this.project === undefined ? '新建答辩项目' : '编辑答辩项目')
          .fontSize(18).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
      }.width('100%').height(58)
      Scroll() {
        Column() {
          Text(this.project === undefined ? '准备一次新演练' : '调整项目信息')
            .fontSize(28).fontWeight(FontWeight.Bold).fontColor(Palette.INK).width('100%')
          Text('项目信息会帮助 AI 评委理解答辩目标。')
            .fontSize(14).fontColor(Palette.MUTED).margin({ top: 8, bottom: 30 }).width('100%')
          Text('项目名称').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.MUTED).width('100%')
          TextInput({ text: this.name, placeholder: '例如：AI 答辩与演讲教练' })
            .onChange((value: string) => this.name = value).height(54).margin({ top: 8 })
            .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 7 })
          Text('项目简介').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.MUTED)
            .margin({ top: 22 }).width('100%')
          TextArea({ text: this.description, placeholder: '说明项目要解决的问题、核心功能和技术特点' })
            .onChange((value: string) => this.description = value).height(128).margin({ top: 8 })
            .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 7 })
          Row() {
            Text('预计答辩时长').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.MUTED)
            Blank()
            Text(String(Math.floor(this.duration / 60)) + ' 分钟').fontSize(12).fontColor(Palette.BLUE_DARK)
          }.width('100%').margin({ top: 22 })
          Row({ space: 8 }) {
            this.durationButton('5 分钟', 300)
            this.durationButton('10 分钟', 600)
            this.durationButton('15 分钟', 900)
          }.width('100%').margin({ top: 9 })
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor(Palette.RED).padding(12).width('100%')
              .backgroundColor(Palette.SOFT_RED).borderRadius(7).margin({ top: 18 })
          }
        }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20, top: 16, bottom: 28 })
      }.layoutWeight(1).width('100%')
      Button(this.busy ? '正在保存' : (this.project === undefined ? '创建项目' : '保存修改'))
        .height(52).width('100%').borderRadius(7).fontWeight(FontWeight.Bold)
        .fontColor(Palette.WHITE).backgroundColor(Palette.INK).enabled(!this.busy)
        .margin({ left: 20, right: 20, bottom: 16 }).onClick(() => this.save())
    }.width('100%').height('100%').backgroundColor(Palette.PAPER)
  }
}
