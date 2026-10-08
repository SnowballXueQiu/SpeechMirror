import { router } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { DocumentItem, Project, SessionItem } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

interface ProjectParams { projectId: string; }

@Entry
@Component
struct ProjectPage {
  @State project?: Project = undefined;
  @State documents: DocumentItem[] = [];
  @State sessions: SessionItem[] = [];
  @State loading: boolean = true;
  @State uploading: boolean = false;
  @State deleting: boolean = false;
  @State showMenu: boolean = false;
  @State showDelete: boolean = false;
  @State error: string = '';
  private projectId: string = (router.getParams() as ProjectParams).projectId;

  onPageShow(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.loading = true;
    try {
      const results = await Promise.all([
        apiClient.getProject(this.projectId),
        apiClient.listDocuments(this.projectId),
        apiClient.listSessions(this.projectId)
      ]);
      this.project = results[0] as Project;
      this.documents = results[1] as DocumentItem[];
      this.sessions = results[2] as SessionItem[];
      this.error = '';
    } catch (reason) {
      this.error = String(reason);
    } finally {
      this.loading = false;
    }
  }

  private readyCount(): number {
    return this.documents.filter((item: DocumentItem) => item.status === 'ready').length;
  }

  private async chooseMaterial(): Promise<void> {
    if (this.uploading) return;
    this.error = '';
    try {
      const documentPicker = new picker.DocumentViewPicker();
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.pdf', '.pptx', '.docx', '.txt', '.md', '.png', '.jpg', '.jpeg'];
      const selected = await documentPicker.select(options);
      if (selected.length === 0) return;
      this.uploading = true;
      await apiClient.uploadDocument(this.projectId, selected[0]);
      await this.reload();
    } catch (reason) {
      this.error = String(reason).includes('Picker') ? '未选择材料' : String(reason);
    } finally {
      this.uploading = false;
    }
  }

  private async deleteProject(): Promise<void> {
    this.deleting = true;
    try {
      await apiClient.deleteProject(this.projectId);
      router.replaceUrl({ url: 'pages/ProjectsPage' });
    } catch (reason) {
      this.error = String(reason);
      this.showDelete = false;
      this.deleting = false;
    }
  }

  private statusLabel(document: DocumentItem): string {
    if (document.status === 'ready') return '已完成解析';
    if (document.status === 'failed') return '解析失败';
    return '正在建立知识库';
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Button('‹').width(42).height(42).fontSize(28).fontColor(Palette.INK)
            .backgroundColor(Color.Transparent).onClick(() => router.back())
          Text('答辩项目').fontSize(17).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          Blank()
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ic_history')).width(23).height(23)
          }.width(42).height(42).onClick(() => router.pushUrl({
            url: 'pages/HistoryPage',
            params: { projectId: this.projectId, projectName: this.project?.name ?? '答辩项目' }
          }))
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ic_more')).width(23).height(23)
          }.width(42).height(42).borderRadius(21).backgroundColor(Palette.WHITE)
            .border({ width: 1, color: Palette.LINE }).margin({ left: 4, right: 8 })
            .onClick(() => this.showMenu = !this.showMenu)
        }.width('100%').height(54)
        if (this.loading && this.project === undefined) {
          Column({ space: 12 }) {
            LoadingProgress().width(30).height(30).color(Palette.BLUE)
            Text('正在同步项目').fontSize(13).fontColor(Palette.MUTED)
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              Text(this.project?.name ?? '项目训练台').fontSize(28).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                .maxLines(2).margin({ top: 10 }).width('100%')
              if ((this.project?.description ?? '').trim().length > 0) {
                Text(this.project?.description ?? '').fontSize(14).fontColor(Palette.MUTED).lineHeight(21).maxLines(4)
                  .margin({ top: 8 }).width('100%')
              }
              Column() {
                Row() {
                  Row({ space: 8 }) {
                    Text('').width(8).height(8)
                      .backgroundColor(this.readyCount() > 0 ? Palette.SIGNAL : '#55FFFFFF').borderRadius(4)
                    Text(this.readyCount() > 0 ? '知识库已就绪' : '等待材料')
                      .fontSize(12).fontWeight(FontWeight.Bold).fontColor('#A6FFFFFF')
                  }
                  Blank()
                  Text(String(Math.floor((this.project?.defense_duration_seconds ?? 300) / 60)) +
                    ' MIN  ·  ' + String(this.documents.length) + ' FILES')
                    .fontSize(11).fontWeight(FontWeight.Bold).fontColor('#66FFFFFF')
                }.width('100%')
                Row() {
                  Column({ space: 8 }) {
                    Text('模拟答辩').fontSize(25).fontWeight(FontWeight.Bold).fontColor(Palette.WHITE)
                    Text('项目陈述 · 动态追问 · 综合报告').fontSize(13).fontColor('#88FFFFFF')
                  }.alignItems(HorizontalAlign.Start)
                  Blank()
                  Column({ space: 4 }) {
                    Row({ space: 4 }) {
                      Text('').width(4).height(13).backgroundColor(Palette.SIGNAL).borderRadius(2)
                      Text('').width(4).height(25).backgroundColor(Palette.SIGNAL).borderRadius(2)
                      Text('').width(4).height(18).backgroundColor(Palette.SIGNAL).borderRadius(2)
                      Text('').width(4).height(32).backgroundColor(Palette.SIGNAL).borderRadius(2)
                    }.alignItems(VerticalAlign.Bottom)
                    Text('LIVE').fontSize(9).fontWeight(FontWeight.Bold).fontColor(Palette.SIGNAL)
                  }
                }.width('100%').alignItems(VerticalAlign.Bottom).margin({ top: 24 })
                Button(this.readyCount() > 0 ? '进入答辩  →' : '添加材料后开始')
                  .enabled(this.readyCount() > 0).height(50).width('100%').margin({ top: 25 }).borderRadius(6)
                  .fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                  .backgroundColor(this.readyCount() > 0 ? Palette.SIGNAL : '#22FFFFFF')
                  .onClick(() => router.pushUrl({
                    url: 'pages/TrainingPage',
                    params: {
                      projectId: this.projectId,
                      targetSeconds: this.project?.defense_duration_seconds ?? 300
                    }
                  }))
              }.alignItems(HorizontalAlign.Start).padding(21).width('100%').margin({ top: 22 })
                .backgroundColor(Palette.NIGHT).borderRadius(8)
              Row() {
                Text('项目材料').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                Blank()
                Button(this.uploading ? '正在上传' : '+ 添加材料').type(ButtonType.Normal).height(40)
                  .fontSize(13).fontWeight(FontWeight.Bold).fontColor(Palette.BLUE_DARK)
                  .backgroundColor(Color.Transparent).enabled(!this.uploading).onClick(() => this.chooseMaterial())
              }.width('100%').margin({ top: 30, bottom: 8 })
              if (this.error.length > 0) {
                Row({ space: 8 }) {
                  Text('!').fontSize(12).fontWeight(FontWeight.Bold).fontColor(Palette.RED)
                  Text(this.error).fontSize(13).fontColor(Palette.RED).layoutWeight(1)
                }.padding(12).width('100%').backgroundColor(Palette.SOFT_RED).borderRadius(7).margin({ bottom: 10 })
              }
              if (this.documents.length === 0) {
                Column({ space: 8 }) {
                  Text('暂无材料').fontSize(16).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
                  Text('支持 PDF、PPTX、DOCX、文本和图片').fontSize(13).fontColor(Palette.MUTED)
                }.width('100%').padding({ top: 28, bottom: 28 })
              } else {
                Column() {
                  ForEach(this.documents, (document: DocumentItem, index: number) => {
                    Column() {
                      Row() {
                        Text(document.filename.split('.').pop()?.slice(0, 3).toUpperCase() ?? 'DOC')
                          .fontSize(10).fontWeight(FontWeight.Bold).fontColor(Palette.BLUE_DARK)
                          .textAlign(TextAlign.Center).width(42).height(42).backgroundColor(Palette.SOFT_BLUE).borderRadius(6)
                        Column({ space: 5 }) {
                          Text(document.filename).fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.INK).maxLines(1)
                          Text(this.statusLabel(document)).fontSize(12)
                            .fontColor(document.status === 'ready' ? Palette.SUCCESS :
                              (document.status === 'failed' ? Palette.RED : Palette.GOLD))
                        }.alignItems(HorizontalAlign.Start).layoutWeight(1).margin({ left: 12 })
                        Text('›').fontSize(25).fontColor(Palette.MUTED).margin({ left: 8 })
                      }.padding({ top: 14, bottom: 14 }).width('100%')
                        .onClick(() => router.pushUrl({
                          url: 'pages/MaterialPage',
                          params: { documentId: document.id }
                        }))
                      if (index < this.documents.length - 1) {
                        Divider().strokeWidth(1).color(Palette.LINE).margin({ left: 54 })
                      }
                    }.width('100%')
                  }, (document: DocumentItem) => document.id)
                }.width('100%').border({ width: { top: 1, bottom: 1 }, color: Palette.LINE })
              }
            }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20, bottom: 36 })
          }.layoutWeight(1).width('100%')
        }
      }.width('100%').height('100%').backgroundColor(Palette.PAPER)
      if (this.showMenu) {
        Column() {
          Row() {
            Blank().layoutWeight(1).onClick(() => this.showMenu = false)
            Column() {
              Row({ space: 14 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Image($r('app.media.ic_edit')).width(21).height(21)
                }.width(40).height(40).borderRadius(7).backgroundColor(Palette.PAPER)
                Text('编辑项目').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
              }.width('100%').height(64).padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.showMenu = false;
                  router.pushUrl({
                    url: 'pages/ProjectEditorPage',
                    params: { projectJson: JSON.stringify(this.project) }
                  });
                })
              Row({ space: 14 }) {
                Stack({ alignContent: Alignment.Center }) {
                  Image($r('app.media.ic_delete_red')).width(21).height(21)
                }.width(40).height(40).borderRadius(7).backgroundColor(Palette.SOFT_RED)
                Text('删除项目').fontSize(15).fontWeight(FontWeight.Bold).fontColor(Palette.RED)
              }.width('100%').height(64).padding({ left: 14, right: 14 })
                .onClick(() => {
                  this.showMenu = false;
                  this.showDelete = true;
                })
            }.width(206).backgroundColor(Palette.WHITE).borderRadius(12)
              .border({ width: 1, color: Palette.LINE })
              .shadow({ radius: 18, color: '#26000000', offsetX: 0, offsetY: 7 })
          }.width('100%')
          Blank().layoutWeight(1).onClick(() => this.showMenu = false)
        }.width('100%').height('100%').padding({ top: 64, right: 20, left: 20 })
      }
      if (this.showDelete) {
        Column() {
          Blank().layoutWeight(1).onClick(() => this.showDelete = false)
          Column({ space: 12 }) {
            Row() {
              Text('删除项目').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
              Blank()
              Button('×').width(38).height(38).fontSize(22).fontColor(Palette.INK)
                .backgroundColor(Palette.PAPER_STRONG).borderRadius(19).onClick(() => this.showDelete = false)
            }.width('100%')
            Text('项目材料、训练记录和报告将一起删除，此操作无法撤销。')
              .fontSize(14).fontColor(Palette.MUTED).lineHeight(21).width('100%')
            Button(this.deleting ? '正在删除' : '确认删除项目').height(50).width('100%').margin({ top: 8 })
              .fontWeight(FontWeight.Bold).fontColor(Palette.WHITE).backgroundColor(Palette.RED).borderRadius(7)
              .enabled(!this.deleting).onClick(() => this.deleteProject())
          }.alignItems(HorizontalAlign.Start).padding(22).width('100%')
            .backgroundColor(Palette.WHITE).borderRadius({ topLeft: 14, topRight: 14 })
        }.width('100%').height('100%').backgroundColor('#66000000')
      }
    }.width('100%').height('100%')
  }
}
