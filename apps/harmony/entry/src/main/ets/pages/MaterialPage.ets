import { router } from '@kit.ArkUI';
import { DocumentItem } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

interface MaterialParams { documentId: string; }

@Entry
@Component
struct MaterialPage {
  @State document?: DocumentItem = undefined;
  @State text: string = '';
  @State loading: boolean = true;
  @State saving: boolean = false;
  @State error: string = '';
  @State saved: boolean = false;
  private documentId: string = (router.getParams() as MaterialParams).documentId;

  aboutToAppear(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.loading = true;
    try {
      this.document = await apiClient.getDocument(this.documentId);
      this.text = this.document.extracted_text ?? '';
      this.error = '';
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.loading = false;
    }
  }

  private async save(): Promise<void> {
    if (this.text.trim().length === 0) {
      this.error = '材料文本不能为空';
      return;
    }
    this.saving = true;
    this.saved = false;
    try {
      this.document = await apiClient.correctDocumentText(this.documentId, this.text.trim());
      this.text = this.document.extracted_text ?? this.text;
      this.saved = true;
      this.error = '';
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.saving = false;
    }
  }

  build() {
    Column() {
      Row() {
        Button('‹').width(42).height(42).fontSize(28).fontColor(Palette.INK)
          .backgroundColor(Color.Transparent).onClick(() => router.back())
        Text('材料内容').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
        Blank()
        if (this.document?.status === 'processing') {
          Button('刷新').type(ButtonType.Normal).height(40).fontSize(13).fontColor(Palette.BLUE_DARK)
            .backgroundColor(Color.Transparent).onClick(() => this.reload())
        }
      }.width('100%').height(56).padding({ left: 4, right: 12 })
      if (this.loading) {
        Column({ space: 12 }) {
          LoadingProgress().width(30).height(30).color(Palette.BLUE)
          Text('正在读取材料').fontSize(13).fontColor(Palette.MUTED)
        }.layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        Column() {
          Text(this.document?.filename ?? '材料').fontSize(24).fontWeight(FontWeight.Bold)
            .fontColor(Palette.INK).maxLines(2).width('100%')
          Row({ space: 7 }) {
            Text('').width(7).height(7).borderRadius(4)
              .backgroundColor(this.document?.status === 'ready' ? Palette.SUCCESS :
                (this.document?.status === 'failed' ? Palette.RED : Palette.GOLD))
            Text(this.document?.status === 'ready' ? '知识库内容已就绪' :
              (this.document?.status === 'failed' ? '材料解析失败' : '正在解析材料'))
              .fontSize(12).fontColor(Palette.MUTED)
          }.width('100%').margin({ top: 10, bottom: 20 })
          TextArea({ text: this.text, placeholder: '解析后的材料文本会显示在这里' })
            .onChange((value: string) => {
              this.text = value;
              this.saved = false;
            }).layoutWeight(1).width('100%').padding(14).backgroundColor(Palette.WHITE)
            .border({ width: 1, color: Palette.LINE, radius: 8 })
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor(Palette.RED).padding(10).width('100%')
              .backgroundColor(Palette.SOFT_RED).borderRadius(7).margin({ top: 10 })
          } else if (this.saved) {
            Text('已保存并重新建立索引').fontSize(13).fontColor(Palette.SUCCESS).margin({ top: 10 }).width('100%')
          }
          Button(this.saving ? '正在保存' : '保存修改').height(50).width('100%').margin({ top: 14 })
            .fontWeight(FontWeight.Bold).fontColor(Palette.WHITE).backgroundColor(Palette.INK).borderRadius(7)
            .enabled(!this.saving && this.document?.status === 'ready').onClick(() => this.save())
        }.alignItems(HorizontalAlign.Start).layoutWeight(1).width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 16 })
      }
    }.width('100%').height('100%').backgroundColor(Palette.PAPER)
  }
}
