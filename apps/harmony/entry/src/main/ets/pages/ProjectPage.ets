import { router } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { DocumentItem, Project } from '../models/Models';
import { apiClient } from '../services/ApiClient';
import { Palette } from '../ui/Palette';

interface ProjectParams { projectId: string; }

@Entry
@Component
struct ProjectPage {
  @State project?: Project = undefined;
  @State documents: DocumentItem[] = [];
  @State loading: boolean = true;
  @State uploading: boolean = false;
  @State deleting: boolean = false;
  @State showMenu: boolean = false;
  @State showEdit: boolean = false;
  @State showDelete: boolean = false;
  @State editName: string = '';
  @State editDescription: string = '';
  @State editMinutes: number = 5;
  @State updating: boolean = false;
  @State editError: string = '';
  @State error: string = '';
  private projectId: string = (router.getParams() as ProjectParams).projectId;

  onPageShow(): void { this.reload(); }

  private async reload(): Promise<void> {
    this.loading = true;
    try {
      const results = await Promise.all([
        apiClient.getProject(this.projectId),
        apiClient.listDocuments(this.projectId)
      ]);
      this.project = results[0] as Project;
      this.documents = results[1] as DocumentItem[];
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

  private openEdit(): void {
    if (this.project === undefined) return;
    this.editName = this.project.name;
    this.editDescription = this.project.description ?? '';
    this.editMinutes = Math.max(1, Math.min(30, Math.floor(this.project.defense_duration_seconds / 60)));
    this.editError = '';
    this.showMenu = false;
    this.showEdit = true;
  }

  private closeEdit(): void {
    if (this.updating) return;
    this.getUIContext().getFocusController().clearFocus();
    this.showEdit = false;
  }

  private async updateProject(): Promise<void> {
    if (this.editName.trim().length === 0 || this.updating) {
      this.editError = '请输入项目名称';
      return;
    }
    this.getUIContext().getFocusController().clearFocus();
    this.updating = true;
    this.editError = '';
    try {
      this.project = await apiClient.updateProject(
        this.projectId, this.editName.trim(), this.editDescription.trim(), this.editMinutes * 60
      );
      this.showEdit = false;
    } catch (reason) {
      this.editError = String(reason);
    } finally {
      this.updating = false;
    }
  }

  private statusLabel(document: DocumentItem): string {
    if (document.status === 'ready') return '已完成解析';
    if (document.status === 'failed') return '解析失败';
    return '正在建立知识库';
  }

  @Builder
  private editSheet() {
    Column() {
      Blank().layoutWeight(1).onClick(() => this.closeEdit())
      Column() {
        Text('').width(38).height(4).borderRadius(2).backgroundColor('#CBD0CA').margin({ bottom: 14 })
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ic_edit_blue')).width(21).height(21)
          }.width(42).height(42).borderRadius(8).backgroundColor(Palette.SOFT_BLUE)
          Column({ space: 3 }) {
            Text('编辑答辩项目').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
            Text('设置名称、简介和项目陈述时长').fontSize(12).fontColor(Palette.MUTED)
          }.alignItems(HorizontalAlign.Start).margin({ left: 12 }).layoutWeight(1)
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ic_close')).width(20).height(20)
          }.width(38).height(38).backgroundColor(Palette.PAPER_STRONG).borderRadius(19)
            .onClick(() => this.closeEdit())
        }.width('100%')
        Text('项目名称').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          .width('100%').margin({ top: 22, bottom: 8 })
        TextInput({ text: this.editName, placeholder: '例如：SpeechMirror AI答辩教练' })
          .onChange((value: string) => this.editName = value).height(50).width('100%')
          .fontSize(15).backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 8 })
        Text('项目简介').fontSize(13).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          .width('100%').margin({ top: 18, bottom: 8 })
        TextArea({ text: this.editDescription, placeholder: '用一两句话说明项目解决的问题' })
          .onChange((value: string) => this.editDescription = value).height(92).width('100%')
          .fontSize(15).backgroundColor(Palette.WHITE).border({ width: 1, color: Palette.LINE, radius: 8 })
        Row() {
          Column({ space: 3 }) {
            Text('目标时长').fontSize(14).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
            Text('项目陈述的参考时间').fontSize(12).fontColor(Palette.MUTED)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ic_minus')).width(19).height(19)
          }.width(36).height(36).borderRadius(18).backgroundColor(Palette.WHITE)
            .border({ width: 1, color: Palette.LINE }).enabled(this.editMinutes > 1)
            .onClick(() => this.editMinutes -= 1)
          Text(String(this.editMinutes) + ' 分钟').width(68).fontSize(14).fontWeight(FontWeight.Bold)
            .fontColor(Palette.INK).textAlign(TextAlign.Center)
          Stack({ alignContent: Alignment.Center }) {
            Image($r('app.media.ic_plus')).width(19).height(19)
          }.width(36).height(36).borderRadius(18).backgroundColor(Palette.INK).enabled(this.editMinutes < 30)
            .onClick(() => this.editMinutes += 1)
        }.width('100%').padding({ left: 14, right: 9, top: 9, bottom: 9 }).margin({ top: 12 })
          .backgroundColor(Palette.PAPER).border({ width: 1, color: Palette.LINE, radius: 8 })
        if (this.editError.length > 0) {
          Text(this.editError).fontSize(12).fontColor(Palette.RED).width('100%').margin({ top: 10 })
        }
        Row({ space: 10 }) {
          Button('取消').height(48).layoutWeight(1).fontColor(Palette.INK).backgroundColor(Palette.WHITE)
            .border({ width: 1, color: Palette.LINE }).borderRadius(8).onClick(() => this.closeEdit())
          Button(this.updating ? '正在保存' : '✓  保存').height(48).layoutWeight(2)
            .fontColor(Palette.WHITE).fontWeight(FontWeight.Bold).backgroundColor(Palette.INK).borderRadius(8)
            .enabled(!this.updating).onClick(() => this.updateProject())
        }.width('100%').margin({ top: 20 })
      }.alignItems(HorizontalAlign.Center).padding({ left: 20, right: 20, top: 10, bottom: 24 })
        .width('100%').backgroundColor(Palette.WHITE).borderRadius({ topLeft: 22, topRight: 22 })
    }.width('100%').height('100%').backgroundColor('#70111412')
  }

  @Builder
  private deleteDialog() {
    Column() {
      Blank().layoutWeight(1).onClick(() => { if (!this.deleting) this.showDelete = false; })
      Column() {
        Stack({ alignContent: Alignment.Center }) {
          Image($r('app.media.ic_delete_red')).width(24).height(24)
        }.width(44).height(44).borderRadius(9).backgroundColor(Palette.SOFT_RED)
        Text('彻底删除项目？').fontSize(22).fontWeight(FontWeight.Bold).fontColor(Palette.INK)
          .width('100%').margin({ top: 20 })
        Text('将删除“' + (this.project?.name ?? '') + '”的材料、训练记录、报告和评委问答。此操作无法撤销。')
          .fontSize(14).fontColor(Palette.MUTED).lineHeight(22).width('100%').margin({ top: 12 })
        Row({ space: 10 }) {
          Button('取消').height(48).layoutWeight(1).fontColor(Palette.INK).backgroundColor(Palette.WHITE)
            .border({ width: 1, color: Palette.LINE }).borderRadius(8)
            .enabled(!this.deleting).onClick(() => this.showDelete = false)
          Button(this.deleting ? '正在删除' : '彻底删除').height(48).layoutWeight(1)
            .fontColor(Palette.WHITE).fontWeight(FontWeight.Bold).backgroundColor(Palette.RED).borderRadius(8)
            .enabled(!this.deleting).onClick(() => this.deleteProject())
        }.width('100%').margin({ top: 24 })
      }.alignItems(HorizontalAlign.Start).padding(22).width('88%')
        .backgroundColor(Palette.WHITE).borderRadius(14)
        .shadow({ radius: 28, color: '#33000000', offsetX: 0, offsetY: 12 })
      Blank().layoutWeight(1).onClick(() => { if (!this.deleting) this.showDelete = false; })
    }.width('100%').height('100%').padding({ left: 16, right: 16 }).backgroundColor('#70000000')
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
                        Stack({ alignContent: Alignment.Center }) {
                          Image($r('app.media.ic_document')).width(24).height(24)
                        }.width(42).height(42)
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
                .onClick(() => this.openEdit())
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
      if (this.showEdit) this.editSheet()
      if (this.showDelete) this.deleteDialog()
    }.width('100%').height('100%')
  }
}
