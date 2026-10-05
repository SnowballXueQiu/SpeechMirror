import { router } from '@kit.ArkUI';
import { DefenseScoreItem, DimensionReport, ReportPayload } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

interface ReportParams { sessionId: string; projectId: string; generate?: boolean; }

@Entry
@Component
struct ReportPage {
  @State report?: ReportPayload = undefined;
  @State loading: boolean = true;
  @State retryAttempt: number = 0;
  @State error: string = '';
  private params: ReportParams = router.getParams() as ReportParams;

  aboutToAppear(): void { this.load(); }

  private async delay(milliseconds: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => setTimeout(resolve, milliseconds));
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.error = '';
    let lastMessage: string = '报告暂时未生成完成';
    for (let attempt = 0; attempt <= 5; attempt += 1) {
      if (attempt > 0) {
        this.retryAttempt = attempt;
        await this.delay(350 * attempt);
      }
      try {
        this.report = this.params.generate === true ?
          await apiClient.analyzeSession(this.params.sessionId) :
          await apiClient.getReport(this.params.sessionId);
        this.retryAttempt = 0;
        this.loading = false;
        return;
      } catch (reason) {
        lastMessage = String(reason);
      }
    }
    this.retryAttempt = 0;
    this.error = lastMessage;
    this.loading = false;
  }

  private grade(score?: number | null): string {
    if (score === undefined || score === null) return '未评分';
    if (score >= 90) return '优秀';
    if (score >= 80) return '良好';
    if (score >= 70) return '中等';
    if (score >= 60) return '及格';
    return '不及格';
  }

  private clock(seconds: number): string {
    return String(Math.floor(seconds / 60)).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
  }

  @Builder
  private scoreRow(label: string, item: DimensionReport) {
    Column({ space: 8 }) {
      Row() {
        Text(label).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.INK).width(58)
        Progress({ value: item.score ?? 0, total: 100, type: ProgressType.Linear })
          .color(item.score === null ? Palette.MUTED : ((item.score ?? 0) >= 75 ? Palette.BLUE : Palette.GOLD))
          .backgroundColor(Palette.PAPER_STRONG).layoutWeight(1)
        Text(item.score === null ? '—' : String(item.score)).fontSize(15).fontWeight(FontWeight.Bold)
          .fontColor(Palette.INK).width(38).textAlign(TextAlign.End)
      }.width('100%')
      Text(item.summary).fontSize(13).fontColor(Palette.MUTED).lineHeight(20)
        .margin({ left: 58 }).width('100%')
      if (item.evidence.length > 0 && item.evidence[0].quote.trim().length > 0) {
        Text('材料依据：' + item.evidence[0].quote).fontSize(12).fontColor(Palette.BLUE_DARK)
          .lineHeight(18).maxLines(3).margin({ left: 58 }).width('100%')
      }
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 14, bottom: 14 })
  }

  build() {
    Column() {
      Row() {
        Button('‹').width(42).height(42).fontSize(28).fontColor(Palette.INK)
          .backgroundColor(Color.Transparent).onClick(() => router.back())
        Text('训练报告').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        Blank()
        if (this.report !== undefined) {
          Text('已完成').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.SUCCESS)
        }
      }.width('100%').height(56).padding({ left: 4, right: 20 })
      if (this.loading) {
        Column({ space: 16 }) {
          LoadingProgress().width(36).height(36).color(Palette.BLUE)
          Text(this.retryAttempt > 0 ? '正在自动重试 ' + String(this.retryAttempt) + '/5' : '正在生成综合报告')
            .fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          Text('评委正在综合项目材料、现场陈述和答辩回答')
            .fontSize(13).fontColor(Palette.MUTED).textAlign(TextAlign.Center)
        }.layoutWeight(1).padding(28).justifyContent(FlexAlign.Center)
      } else if (this.error.length > 0 || this.report === undefined) {
        Column({ space: 14 }) {
          Text('报告尚未生成').fontSize(22).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          Text(this.error).fontSize(14).fontColor(Palette.MUTED).textAlign(TextAlign.Center).lineHeight(21)
          Button('重新生成').height(50).width('100%').margin({ top: 8 }).borderRadius(7)
            .fontWeight(FontWeight.Bold).fontColor(Palette.WHITE).backgroundColor(Palette.INK)
            .onClick(() => this.load())
          Button('返回项目').type(ButtonType.Normal).height(46).width('100%')
            .fontColor(Palette.BLUE_DARK).backgroundColor(Color.Transparent)
            .onClick(() => router.replaceUrl({
              url: 'pages/ProjectPage', params: { projectId: this.params.projectId }
            }))
        }.layoutWeight(1).padding(24).justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            Text('本次答辩表现').fontSize(28).fontWeight(FontWeight.Bold).fontColor(Palette.INK).width('100%')
            Column() {
              Row() {
                Column({ space: 7 }) {
                  Text('答辩最终评分').fontSize(13).fontColor('#99FFFFFF')
                  Text(this.grade(this.report?.overall_score)).fontSize(22).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text(this.report?.overall_score === null || this.report?.overall_score === undefined ?
                  '—' : String(this.report?.overall_score))
                  .fontSize(54).fontWeight(FontWeight.Bold).fontColor(Palette.SIGNAL)
                if (this.report?.overall_score !== null && this.report?.overall_score !== undefined) {
                  Text('/ 100').fontSize(11).fontColor('#66FFFFFF').margin({ left: 4, bottom: 6 })
                }
              }.width('100%').alignItems(VerticalAlign.Bottom)
              Divider().strokeWidth(1).color('#1FFFFFFF').margin({ top: 20, bottom: 16 })
              Row() {
                Column({ space: 5 }) {
                  Text('语速').fontSize(10).fontColor('#66FFFFFF')
                  Text(String(Math.round(this.report?.characters_per_minute ?? 0)) + ' 字/分')
                    .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Column({ space: 5 }) {
                  Text('时长').fontSize(10).fontColor('#66FFFFFF')
                  Text(this.clock(this.report?.actual_seconds ?? 0))
                    .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Column({ space: 5 }) {
                  Text('长停顿').fontSize(10).fontColor('#66FFFFFF')
                  Text(this.report?.long_pause_count === null || this.report?.long_pause_count === undefined ?
                    '—' : String(this.report?.long_pause_count) + ' 次')
                    .fontSize(16).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }.width('100%')
            }.padding(20).width('100%').margin({ top: 18 }).backgroundColor(Palette.NIGHT).borderRadius(8)
            Text('五维分析').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
              .margin({ top: 29, bottom: 6 }).width('100%')
            this.scoreRow('内容', this.report!.content)
            this.scoreRow('表达', this.report!.delivery)
            this.scoreRow('时间', this.report!.timing)
            this.scoreRow('视觉', this.report!.visual)
            this.scoreRow('问答', this.report!.qa)
            if ((this.report?.defense_scores ?? []).length > 0) {
              Text('答辩评分明细').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                .margin({ top: 28, bottom: 8 }).width('100%')
              Column() {
                ForEach(this.report?.defense_scores ?? [], (item: DefenseScoreItem, index: number) => {
                  Column({ space: 7 }) {
                    Row() {
                      Text(item.label).fontSize(14).fontWeight(FontWeight.Bold).fontColor(Palette.INK).layoutWeight(1)
                      Text(String(item.score) + ' / ' + String(item.max_score)).fontSize(13)
                        .fontWeight(FontWeight.Bold).fontColor(Palette.BLUE_DARK)
                    }.width('100%')
                    Progress({ value: item.score, total: item.max_score, type: ProgressType.Linear })
                      .color(Palette.BLUE).backgroundColor(Palette.PAPER_STRONG).width('100%')
                    Text(item.summary).fontSize(12).fontColor(Palette.MUTED).lineHeight(18).width('100%')
                    if (index < (this.report?.defense_scores ?? []).length - 1) {
                      Divider().strokeWidth(1).color(Palette.LINE).margin({ top: 5 })
                    }
                  }.alignItems(HorizontalAlign.Start).padding({ top: 12, bottom: 12 }).width('100%')
                })
              }.width('100%')
            }
            Text('下一次练习').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
              .margin({ top: 28, bottom: 14 }).width('100%')
            ForEach(this.report?.suggestions ?? [], (suggestion: string, index: number) => {
              Row({ space: 12 }) {
                Text(String(index + 1)).fontSize(12).fontColor(Palette.WHITE).fontWeight(FontWeight.Bold)
                  .textAlign(TextAlign.Center).width(27).height(27).backgroundColor(Palette.BLUE).borderRadius(14)
                Text(suggestion).fontSize(14).lineHeight(21).layoutWeight(1).fontColor(Palette.INK)
              }.alignItems(VerticalAlign.Top).margin({ bottom: 15 })
            })
            Button('返回项目').height(50).width('100%').margin({ top: 18 }).borderRadius(7)
              .fontWeight(FontWeight.Bold).fontColor(Palette.WHITE).backgroundColor(Palette.INK)
              .onClick(() => router.replaceUrl({
                url: 'pages/ProjectPage', params: { projectId: this.params.projectId }
              }))
          }.alignItems(HorizontalAlign.Start).width('100%')
            .padding({ left: 20, right: 20, top: 12, bottom: 38 })
        }.layoutWeight(1).width('100%')
      }
    }.width('100%').height('100%').backgroundColor(Palette.PAPER)
  }
}
