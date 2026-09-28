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

enum _ProjectAction { edit, delete }

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
      toolbarHeight: 64,
      title: const Text('答辩项目'),
      actions: [
        IconButton(
          tooltip: '训练历史',
          onPressed: () =>
              context.push('/projects/${widget.projectId}/history'),
          icon: const Icon(Icons.history_rounded),
        ),
        PopupMenuButton<_ProjectAction>(
          tooltip: '项目操作',
          enabled: !_mutating,
          onSelected: (action) {
            switch (action) {
              case _ProjectAction.edit:
                _editProject();
              case _ProjectAction.delete:
                _deleteProject();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _ProjectAction.edit,
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('编辑项目'),
                ],
              ),
            ),
            PopupMenuItem(
              value: _ProjectAction.delete,
              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: AppColors.vermilion,
                  ),
                  SizedBox(width: 12),
                  Text('删除项目'),
                ],
              ),
            ),
          ],
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
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 48),
          children: [
            Text(
              project.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 25,
                height: 1.24,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (project.description?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                project.description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, height: 1.5),
              ),
            ],
            const SizedBox(height: 22),
            _DefenseStage(
              minutes: project.durationSeconds ~/ 60,
              readyDocuments: ready,
              enabled: ready > 0,
              onStart: () => context.push('/projects/${project.id}/training'),
            ),
            const SizedBox(height: 30),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '项目材料',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: '刷新状态',
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded, size: 21),
                ),
                TextButton.icon(
                  onPressed: _uploading ? null : _pickFile,
                  icon: _uploading
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_rounded, size: 20),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (documents.isEmpty)
              _EmptyMaterials(onAdd: _uploading ? null : _pickFile),
            if (documents.isNotEmpty)
              DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.line),
                    bottom: BorderSide(color: AppColors.line),
                  ),
                ),
                child: Column(
                  children: [
                    for (var index = 0; index < documents.length; index++) ...[
                      _MaterialRow(
                        document: documents[index],
                        icon: _documentIcon(documents[index].mediaType),
                        status: _statusText(documents[index]),
                        onTap: documents[index].status == 'processing'
                            ? null
                            : () async {
                                await context.push(
                                  '/projects/${project.id}/documents/${documents[index].id}',
                                );
                                if (mounted) _reload();
                              },
                      ),
                      if (index < documents.length - 1)
                        const Divider(height: 1, indent: 52),
                    ],
                  ],
                ),
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

class _DefenseStage extends StatelessWidget {
  const _DefenseStage({
    required this.minutes,
    required this.readyDocuments,
    required this.enabled,
    required this.onStart,
  });

  final int minutes;
  final int readyDocuments;
  final bool enabled;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(20, 20, 18, 18),
    decoration: BoxDecoration(
      color: AppColors.night,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: enabled ? AppColors.signal : Colors.white30,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              enabled ? '已就绪' : '等待材料',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              '$minutes MIN  ·  $readyDocuments FILES',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                '模拟答辩',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _SignalBars(),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          enabled ? '项目陈述 · AI 追问 · 综合报告' : '添加材料后即可开始',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.signal,
              foregroundColor: AppColors.ink,
              disabledBackgroundColor: Colors.white12,
              disabledForegroundColor: Colors.white38,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: enabled ? onStart : null,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: const Text('进入答辩'),
          ),
        ),
      ],
    ),
  );
}

class _SignalBars extends StatelessWidget {
  const _SignalBars();

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      for (final height in const [12.0, 24.0, 17.0, 31.0, 21.0, 13.0])
        Container(
          width: 3,
          height: height,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: AppColors.signal,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
    ],
  );
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.document,
    required this.icon,
    required this.status,
    required this.onTap,
  });

  final ProjectDocument document;
  final IconData icon;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Icon(icon, color: AppColors.ink, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: document.status == 'failed'
                            ? AppColors.vermilion
                            : document.status == 'ready'
                            ? AppColors.success
                            : AppColors.gold,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: document.status == 'failed'
                              ? AppColors.vermilion
                              : AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (document.status == 'processing')
            const SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: AppColors.muted,
              size: 15,
            ),
        ],
      ),
    ),
  );
}

class _EmptyMaterials extends StatelessWidget {
  const _EmptyMaterials({required this.onAdd});

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onAdd,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.line),
          bottom: BorderSide(color: AppColors.line),
        ),
      ),
      child: const Row(
        children: [
          Icon(Icons.upload_file_outlined, color: AppColors.muted),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('添加项目材料', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text(
                  'PDF、PPTX、DOCX、文本或图片',
                  style: TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.add_rounded),
        ],
      ),
    ),
  );
}
