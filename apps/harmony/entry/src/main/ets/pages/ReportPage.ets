import { router } from '@kit.ArkUI';
import { DimensionReport, ReportPayload } from '../models/Models';

interface ReportParams { reportJson: string; }

@Entry
@Component
struct ReportPage {
  private report: ReportPayload = JSON.parse((router.getParams() as ReportParams).reportJson) as ReportPayload;

  @Builder scoreRow(label: string, item: DimensionReport) {
    Column({ space: 7 }) {
      Row() { Text(label).fontWeight(FontWeight.Bold).width(60); Progress({ value: item.score ?? 0, total: 100, type: ProgressType.Linear }).color(item.score === null ? '#67716B' : (item.score >= 75 ? '#176B5B' : '#C49A43')).layoutWeight(1); Text(item.score === null ? '—' : `${item.score}`).fontWeight(FontWeight.Bold).width(34).textAlign(TextAlign.End) }
      Text(item.summary).fontSize(13).fontColor('#67716B').margin({ left: 60 }).width('100%')
    }.width('100%').padding({ top: 11, bottom: 11 })
  }

  build() {
    Scroll() {
      Column() {
        Row() { Button('‹').width(42).height(42).fontSize(28).fontColor('#18211D').backgroundColor(Color.Transparent).onClick(() => router.back()); Text('训练报告').fontSize(22).fontWeight(FontWeight.Bold) }.width('100%')
        Text('这一次，你说清楚了吗？').fontSize(28).fontWeight(FontWeight.Bold).fontColor('#18211D').margin({ top: 20 }).width('100%')
        Row() {
          Column({ space: 4 }) { Text('语速').fontSize(11).fontColor('#AAAAAA'); Text(`${Math.round(this.report.characters_per_minute)} 字/分`).fontSize(19).fontWeight(FontWeight.Bold).fontColor(Color.White) }.layoutWeight(1)
          Column({ space: 4 }) { Text('时长').fontSize(11).fontColor('#AAAAAA'); Text(`${this.report.actual_seconds} 秒`).fontSize(19).fontWeight(FontWeight.Bold).fontColor(Color.White) }.layoutWeight(1)
        }.padding(18).width('100%').margin({ top: 18 }).backgroundColor('#18211D').borderRadius(7)
        Text('五维分析').fontSize(19).fontWeight(FontWeight.Bold).margin({ top: 28, bottom: 8 }).width('100%')
        this.scoreRow('内容', this.report.content)
        this.scoreRow('表达', this.report.delivery)
        this.scoreRow('时间', this.report.timing)
        this.scoreRow('视觉', this.report.visual)
        this.scoreRow('问答', this.report.qa)
        Text('下一次练习').fontSize(19).fontWeight(FontWeight.Bold).margin({ top: 26, bottom: 10 }).width('100%')
        ForEach(this.report.suggestions, (suggestion: string, index: number) => {
          Row({ space: 10 }) { Text(`${index + 1}`).fontColor(Color.White).fontWeight(FontWeight.Bold).textAlign(TextAlign.Center).width(26).height(26).backgroundColor('#C8573B').borderRadius(4); Text(suggestion).layoutWeight(1).fontColor('#18211D') }.margin({ bottom: 12 })
        })
      }.width('100%').padding(20).backgroundColor('#F4F1E8')
    }.width('100%').height('100%')
  }
}
