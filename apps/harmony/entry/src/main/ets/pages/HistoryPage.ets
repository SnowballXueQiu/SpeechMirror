import { router } from '@kit.ArkUI';
import { SessionItem, TrendPoint, Trends } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

interface HistoryParams { projectId: string; projectName: string; }

@Entry
@Component
struct HistoryPage {
  @State sessions: SessionItem[] = [];
  @State points: TrendPoint[] = [];
  @State loading: boolean = true;
  @State error: string = '';
  @State metric: number = 0;
  private params: HistoryParams = router.getParams() as HistoryParams;

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.loading = true;
    try {
      const values = await Promise.all([
        apiClient.listSessions(this.params.projectId), apiClient.getTrends(this.params.projectId)
      ]);
      this.sessions = values[0] as SessionItem[];
      this.points = (values[1] as Trends).points;
      this.error = '';
    } catch (reason) { this.error = String(reason); } finally { this.loading = false; }
  }

  private duration(item: SessionItem): string {
    const seconds = item.actual_seconds ?? item.target_seconds;
    return String(Math.floor(seconds / 60)).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
  }
  private completedCount(): number {
    return this.sessions.filter((item: SessionItem) => item.status === 'completed' || item.status === 'analyzed').length;
  }
  private hasReport(item: SessionItem): boolean {
    return this.points.some((point: TrendPoint) => point.session_id === item.id);
  }
  private metricValue(point: TrendPoint): number | undefined {
    if (this.metric === 0) return point.duration_deviation_seconds;
    if (this.metric === 1) return point.filler_per_minute;
    if (this.metric === 2) return point.content_score;
    return point.qa_score;
  }
  private metricDescription(): string {
    if (this.metric === 0) return '实际时长与目标时长之差，负数表示提前结束';
    if (this.metric === 1) return '每分钟识别到的口头禅次数';
    if (this.metric === 2) return '有材料依据的内容评价';
    return '已完成评委问答的评价';
  }
  private metricUnit(): string { return this.metric === 0 ? '秒' : this.metric === 1 ? '次/分' : '分'; }
  private valueText(value: number): string { return this.metric === 1 ? value.toFixed(1) : String(Math.round(value)); }
  private chartHeight(point: TrendPoint): number {
    const values = this.points.map((item: TrendPoint) => this.metricValue(item))
      .filter((value: number | undefined) => value !== undefined) as number[];
    const current = this.metricValue(point);
    if (current === undefined || values.length === 0) return 5;
    const min = Math.min(...values); const max = Math.max(...values);
    return max === min ? 54 : 18 + ((current - min) / (max - min)) * 74;
  }

  @Builder private summaryMetric(label: string, value: number, unit: string) {
    Column({ space: 5 }) {
      Text(label).fontSize(11).fontColor('#7F8781')
      Row({ space: 4 }) {
        Text(String(value)).fontSize(23).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
        Text(unit).fontSize(10).fontColor('#7F8781').margin({ top: 9 })
      }
    }.layoutWeight(1)
  }
  @Builder private metricButton(label: string, index: number) {
    Text(label).fontSize(13).fontWeight(FontWeight.Medium)
      .fontColor(this.metric === index ? Palette.WHITE : Palette.INK).textAlign(TextAlign.Center)
      .layoutWeight(1).height(38).backgroundColor(this.metric === index ? Palette.INK : Color.Transparent)
      .onClick(() => this.metric = index)
  }
  @Builder private trendPanel() {
    if (this.points.length === 0) {
      Column({ space: 8 }) {
        Text('⌁').fontSize(34).fontColor(Palette.MUTED)
        Text('暂无可比较报告').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        Text('完成分析并生成真实报告后，这里才会显示趋势。').fontSize(12).fontColor(Palette.MUTED)
      }.width('100%').padding({ top: 32, bottom: 32, left: 20, right: 20 })
        .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE }).borderRadius(8)
    } else {
      Column() {
        Row() {
          Text(this.metricDescription()).fontSize(12).fontColor(Palette.MUTED).layoutWeight(1).maxLines(2)
          Text(this.valueText(this.metricValue(this.points[this.points.length - 1]) ?? 0) + ' ' + this.metricUnit())
            .fontSize(14).fontWeight(FontWeight.Bold).fontColor(Palette.SUCCESS)
        }.width('100%')
        Row({ space: 8 }) {
          ForEach(this.points, (point: TrendPoint, index: number) => {
            Column() {
              Blank().layoutWeight(1)
              Text(this.metricValue(point) === undefined ? '' : this.valueText(this.metricValue(point) ?? 0))
                .fontSize(9).fontColor(Palette.MUTED).margin({ bottom: 3 })
              Column().width(8).height(this.chartHeight(point)).backgroundColor(Palette.SUCCESS).borderRadius(4)
              Text(String(index + 1)).fontSize(9).fontColor(Palette.MUTED).margin({ top: 6 })
            }.layoutWeight(1).height(154)
          }, (_point: TrendPoint, index: number) => String(index))
        }.width('100%').height(154).margin({ top: 18 })
        Text('训练次序').fontSize(11).fontColor(Palette.MUTED).width('100%').textAlign(TextAlign.Center)
      }.width('100%').padding({ top: 16, bottom: 12, left: 14, right: 14 })
        .backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE }).borderRadius(8)
    }
  }

  build() {
    Column() {
      Row() {
        Button('‹').width(42).height(42).fontSize(28).fontColor(Palette.INK).backgroundColor(Color.Transparent)
          .onClick(() => router.back())
        Text('训练历史').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK).layoutWeight(1)
        Stack({ alignContent: Alignment.Center }) {
          Image($r('app.media.ic_refresh')).width(23).height(23)
        }.width(42).height(42).onClick(() => this.reload())
      }.width('100%').height(56)
      if (this.loading) {
        LoadingProgress().width(30).height(30).color(Palette.BLUE).margin({ top: 100 })
      } else {
        Scroll() {
          Column() {
            Text(String(this.points.length) + ' 份可比较报告').fontSize(13).fontWeight(FontWeight.Bold)
              .fontColor(Palette.MUTED).width('100%')
            Text(this.params.projectName).fontSize(25).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
              .maxLines(2).width('100%').margin({ top: 5, bottom: 22 })
            Row() {
              this.summaryMetric('训练', this.sessions.length, '次')
              Divider().vertical(true).height(44).color('#29302B')
              this.summaryMetric('已完成', this.completedCount(), '次')
              Divider().vertical(true).height(44).color('#29302B')
              this.summaryMetric('可比较', this.points.length, '份')
            }.width('100%').padding({ top: 18, bottom: 18, left: 12, right: 12 })
              .backgroundColor(Palette.NIGHT).borderRadius(8)
            Text('训练趋势').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Palette.MUTED)
              .width('100%').margin({ top: 28, bottom: 14 })
            Row() {
              this.metricButton('时长', 0); this.metricButton('口头禅', 1)
              this.metricButton('内容', 2); this.metricButton('问答', 3)
            }.width('100%').height(40).border({ width: 1, color: Palette.LINE }).borderRadius(8).clip(true)
            Column().height(16)
            this.trendPanel()
            Text(String(this.sessions.length) + ' 次训练记录').fontSize(13).fontWeight(FontWeight.Bold)
              .fontColor(Palette.MUTED).width('100%').margin({ top: 30, bottom: 12 })
            if (this.sessions.length === 0) {
              Text('还没有训练记录。').fontSize(13).fontColor(Palette.MUTED).width('100%').padding({ top: 24, bottom: 24 })
            } else {
              ForEach(this.sessions, (item: SessionItem) => {
                Row({ space: 12 }) {
                  Text(this.hasReport(item) ? '▤' : '◷').fontSize(20)
                    .fontColor(this.hasReport(item) ? Palette.WHITE : Palette.MUTED).width(40).height(40)
                    .textAlign(TextAlign.Center).backgroundColor(this.hasReport(item) ? Palette.SUCCESS : Palette.PAPER_STRONG)
                    .borderRadius(6)
                  Column({ space: 4 }) {
                    Text(item.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.INK).maxLines(1)
                    Text((item.created_at ?? '').slice(5, 16).replace('T', ' ') + ' · ' + this.duration(item) +
                      ' · ' + (this.hasReport(item) ? '查看报告' : item.status))
                      .fontSize(12).fontColor(Palette.MUTED).maxLines(2)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  if (this.hasReport(item)) { Text('›').fontSize(24).fontColor(Palette.MUTED) }
                }.width('100%').padding(14).backgroundColor(Palette.WHITE)
                  .border({ width: 1, color: Palette.LINE }).borderRadius(8).margin({ bottom: 10 })
                  .onClick(() => {
                    if (this.hasReport(item)) router.pushUrl({ url: 'pages/ReportPage', params: {
                      sessionId: item.id, projectId: this.params.projectId, generate: false
                    }});
                  })
              }, (item: SessionItem) => item.id)
            }
            Column().height(36)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      }
      if (this.error.length > 0) {
        Text(this.error).fontSize(12).fontColor(Palette.RED).padding(10).width('100%')
          .backgroundColor(Palette.SOFT_RED).borderRadius(7)
      }
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 14 }).backgroundColor(Palette.PAPER)
  }
}
