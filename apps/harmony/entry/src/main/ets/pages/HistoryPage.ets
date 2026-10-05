import { router } from '@kit.ArkUI';
import { SessionItem } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

interface HistoryParams { projectId: string; projectName: string; }

@Entry
@Component
struct HistoryPage {
  @State sessions: SessionItem[] = [];
  @State loading: boolean = true;
  @State error: string = '';
  private params: HistoryParams = router.getParams() as HistoryParams;

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.loading = true;
    try {
      this.sessions = await apiClient.listSessions(this.params.projectId);
      this.error = '';
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.loading = false;
    }
  }

  private duration(item: SessionItem): string {
    const seconds = item.actual_seconds ?? item.target_seconds;
    return String(Math.floor(seconds / 60)).padStart(2, '0') + ':' + String(seconds % 60).padStart(2, '0');
  }

  build() {
    Column() {
      Row() {
        Button('‹').width(42).height(42).fontSize(28).fontColor(Palette.INK)
          .backgroundColor(Color.Transparent).onClick(() => router.back())
        Text('训练记录').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
      }.width('100%').height(56)
      Column({ space: 6 }) {
        Text(this.params.projectName).fontSize(26).fontWeight(FontWeight.Bold).fontColor(Palette.INK).maxLines(2)
        Text(String(this.sessions.length) + ' 次练习记录').fontSize(13).fontColor(Palette.MUTED)
      }.alignItems(HorizontalAlign.Start).width('100%').margin({ top: 8, bottom: 20 })
      if (this.error.length > 0) {
        Text(this.error).fontSize(13).fontColor(Palette.RED).padding(12).width('100%')
          .backgroundColor(Palette.SOFT_RED).borderRadius(7).margin({ bottom: 12 })
      }
      if (this.loading) {
        LoadingProgress().width(30).height(30).color(Palette.BLUE).margin({ top: 80 })
      } else if (this.sessions.length === 0) {
        Column({ space: 8 }) {
          Text('还没有训练记录').fontSize(18).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          Text('完成一次模拟答辩后，报告会出现在这里。').fontSize(13).fontColor(Palette.MUTED)
        }.width('100%').padding({ top: 60, bottom: 60 })
      } else {
        List() {
          ForEach(this.sessions, (item: SessionItem, index: number) => {
            ListItem() {
              Column() {
                Row() {
                  Text(String(this.sessions.length - index).padStart(2, '0')).fontSize(11).fontWeight(FontWeight.Bold)
                    .fontColor(Palette.MUTED).width(36)
                  Column({ space: 5 }) {
                    Text(item.title).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.INK).maxLines(1)
                    Text((item.completed_at ?? item.created_at ?? '').slice(0, 10) + '  ·  ' + this.duration(item))
                      .fontSize(12).fontColor(Palette.MUTED)
                  }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                  Text(item.status === 'analyzed' ? '查看报告' : item.status).fontSize(12)
                    .fontColor(item.status === 'analyzed' ? Palette.BLUE_DARK : Palette.GOLD)
                  Text('›').fontSize(22).fontColor(Palette.MUTED).margin({ left: 8 })
                }.width('100%').padding({ top: 17, bottom: 17 })
                  .onClick(() => {
                    if (item.status === 'analyzed') {
                      router.pushUrl({
                        url: 'pages/ReportPage',
                        params: { sessionId: item.id, projectId: this.params.projectId, generate: false }
                      });
                    }
                  })
                if (index < this.sessions.length - 1) {
                  Divider().strokeWidth(1).color(Palette.LINE).margin({ left: 36 })
                }
              }.width('100%')
            }
          }, (item: SessionItem) => item.id)
        }.layoutWeight(1).width('100%').border({ width: { top: 1, bottom: 1 }, color: Palette.LINE })
      }
    }.width('100%').height('100%').padding({ left: 20, right: 20, top: 14, bottom: 20 })
      .backgroundColor(Palette.PAPER)
  }
}
