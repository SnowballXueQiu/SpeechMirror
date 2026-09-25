import 'dart:async';

import 'package:file_picker/file_picker.dart' as picker;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api_client.dart';
import '../auth_controller.dart';
import '../models.dart';
import '../project_editor.dart';
import '../theme.dart';
import '../widgets.dart';

class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.projectId});
  final String projectId;
  @override
  ConsumerState<ProjectDetailScreen> createState() =>
      _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  late Future<(Project, List<ProjectDocument>)> _data;
  Timer? _statusTimer;
  bool _uploading = false;
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    _data = _loadData();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<(Project, List<ProjectDocument>)> _loadData() {
    final api = ref.read(apiClientProvider);
    final result = Future.wait(
      [api.getProject(widget.projectId), api.listDocuments(widget.projectId)],
    ).then((items) => (items[0] as Project, items[1] as List<ProjectDocument>));
    result.then<void>((data) {
      if (!mounted) return;
      _statusTimer?.cancel();
      if (data.$2.any((document) => document.status == 'processing')) {
        _statusTimer = Timer(const Duration(seconds: 2), _reload);
      }
    }, onError: (_) {});
    return result;
  }

  void _reload() {
    _statusTimer?.cancel();
    setState(() {
      _data = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('项目训练台'),
      actions: [
        IconButton(
          tooltip: '编辑项目',
          onPressed: _mutating ? null : _editProject,
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: '删除项目',
          onPressed: _mutating ? null : _deleteProject,
          icon: const Icon(Icons.delete_outline),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: FutureBuilder<(Project, List<ProjectDocument>)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text(snapshot.error.toString()));
        }
        final (project, documents) = snapshot.data!;
        final ready = documents.where((item) => item.status == 'ready').length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
          children: [
            PageIntro(
              eyebrow: 'PROJECT / ${project.durationSeconds ~/ 60} MIN',
              title: project.name,
              description: project.description ?? '上传材料后即可开始一次基于证据的模拟答辩。',
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ready > 0 ? AppColors.jadeDark : AppColors.ink,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    ready > 0
                        ? Icons.check_circle_outline
                        : Icons.hourglass_empty,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      ready > 0 ? '$ready 份材料已进入项目知识库' : '至少上传一份材料后开始训练',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: ready > 0
                        ? () => context.push('/projects/${project.id}/training')
                        : null,
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('开始模拟答辩'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'AI评委',
                  onPressed: ready > 0
                      ? () => context.push('/projects/${project.id}/jury')
                      : null,
                  icon: const Icon(Icons.forum_outlined),
                ),
              ],
            ),
            const SizedBox(height: 30),
            SectionLabel(
              '答辩材料',
              trailing: IconButton(
                tooltip: '刷新状态',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ),
            const SizedBox(height: 12),
            for (final document in documents) ...[
              Card(
                child: ListTile(
                  onTap: document.status == 'processing'
                      ? null
                      : () async {
                          await context.push(
                            '/projects/${project.id}/documents/${document.id}',
                          );
                          if (mounted) _reload();
                        },
                  leading: Icon(
                    _documentIcon(document.mediaType),
                    color: AppColors.jade,
                  ),
                  title: Text(
                    document.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _statusText(document),
                    style: TextStyle(
                      color: document.status == 'failed'
                          ? AppColors.vermilion
                          : AppColors.muted,
                    ),
                  ),
                  trailing: document.status == 'processing'
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (documents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '尚未添加材料。支持PDF、PPTX、DOCX、文本和图片。',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickFile,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file),
              label: Text(_uploading ? '正在上传' : '添加材料'),
            ),
            const SizedBox(height: 28),
            const SectionLabel('训练方法'),
            const SizedBox(height: 12),
            const _MethodRow(
              number: '01',
              title: '完整陈述',
              body: '按照真实时长完成一次连续答辩，训练中仅接收必要提醒。',
            ),
            const _MethodRow(
              number: '02',
              title: '证据复盘',
              body: '报告把内容缺口对应到材料片段，不用不可解释的总分替代建议。',
            ),
            const _MethodRow(
              number: '03',
              title: '评委追问',
              body: '基于论文内容生成问题，回答后继续追问薄弱环节。',
            ),
          ],
        );
      },
    ),
  );

  Future<void> _editProject() async {
    try {
      final (project, _) = await _data;
      if (!mounted) return;
      final draft = await showProjectEditor(context, project: project);
      if (draft == null || !mounted) return;
      setState(() => _mutating = true);
      await ref
          .read(apiClientProvider)
          .updateProject(
            project.id,
            draft.name,
            draft.description,
            draft.durationSeconds,
          );
      if (mounted) _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _deleteProject() async {
    try {
      final (project, _) = await _data;
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('彻底删除项目？'),
          content: Text('将删除“${project.name}”的材料、训练记录、报告和评委问答。此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton.icon(
              key: const ValueKey('confirm-project-deletion'),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('彻底删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      setState(() => _mutating = true);
      await ref.read(apiClientProvider).deleteProject(project.id);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/projects');
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await picker.FilePicker.platform.pickFiles(
      type: picker.FileType.custom,
      allowedExtensions: const [
        'pdf',
        'pptx',
        'docx',
        'txt',
        'md',
        'png',
        'jpg',
        'jpeg',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    if (file.size > 25 * 1024 * 1024) {
      if (mounted) showError(context, const ApiException('材料大小不能超过 25 MiB'));
      return;
    }
    setState(() => _uploading = true);
    try {
      await ref
          .read(apiClientProvider)
          .uploadDocument(
            widget.projectId,
            PlatformFile(
              name: file.name,
              path: file.path,
              extension: file.extension,
            ),
          );
      _reload();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  IconData _documentIcon(String mediaType) => mediaType.startsWith('image/')
      ? Icons.image_outlined
      : mediaType.contains('presentation')
      ? Icons.slideshow_outlined
      : Icons.description_outlined;
  String _statusText(ProjectDocument item) => switch (item.status) {
    'ready' => '已完成解析',
    'processing' => '正在建立知识库',
    'failed' => item.error ?? '解析失败',
    _ => item.status,
  };
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
    required this.number,
    required this.title,
    required this.body,
  });
  final String number;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 13),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 42,
          child: Text(
            number,
            style: const TextStyle(
              color: AppColors.vermilion,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(body, style: const TextStyle(color: AppColors.muted)),
            ],
          ),
        ),
      ],
    ),
  );
}
