import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth_controller.dart';
import '../models.dart';
import '../project_editor.dart';
import '../theme.dart';
import '../widgets.dart';

enum _AccountAction { logout }

class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  late Future<List<Project>> _projects;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final projects = ref.read(apiClientProvider).listProjects();
    setState(() {
      _projects = projects;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 72,
      titleSpacing: 20,
      title: const _Wordmark(),
      actions: [
        IconButton.filled(
          tooltip: '新建项目',
          style: IconButton.styleFrom(
            fixedSize: const Size.square(40),
            backgroundColor: AppColors.ink,
            foregroundColor: Colors.white,
          ),
          onPressed: _createProject,
          icon: const Icon(Icons.add_rounded),
        ),
        const SizedBox(width: 4),
        PopupMenuButton<_AccountAction>(
          tooltip: '账户菜单',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (_) => ref.read(authControllerProvider).logout(),
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _AccountAction.logout,
              child: Row(
                children: [
                  Icon(Icons.logout_rounded, size: 20),
                  SizedBox(width: 12),
                  Text('退出登录'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () async => _reload(),
      child: FutureBuilder<List<Project>>(
        future: _projects,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [Text(snapshot.error.toString())],
            );
          }
          final projects = snapshot.data ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 48),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '我的答辩',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const Spacer(),
                  Text(
                    '${projects.length} 个项目',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (projects.isEmpty) _EmptyProjects(onCreate: _createProject),
              if (projects.isNotEmpty)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.line),
                      bottom: BorderSide(color: AppColors.line),
                    ),
                  ),
                  child: Column(
                    children: [
                      for (var index = 0; index < projects.length; index++) ...[
                        _ProjectRow(
                          index: index,
                          project: projects[index],
                          onTap: () => _openProject(projects[index].id),
                        ),
                        if (index < projects.length - 1)
                          const Divider(height: 1, indent: 48),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );

  Future<void> _createProject() async {
    final draft = await showProjectEditor(context);
    if (draft == null) return;
    try {
      final project = await ref
          .read(apiClientProvider)
          .createProject(draft.name, draft.description, draft.durationSeconds);
      if (!mounted) return;
      _reload();
      await _openProject(project.id);
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _openProject(String projectId) async {
    await context.push<void>('/projects/$projectId');
    if (mounted) _reload();
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 27,
        height: 27,
        decoration: const BoxDecoration(
          color: AppColors.ink,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.graphic_eq_rounded,
          color: AppColors.signal,
          size: 17,
        ),
      ),
      const SizedBox(width: 10),
      const Text(
        '言镜',
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      ),
    ],
  );
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    required this.index,
    required this.project,
    required this.onTap,
  });

  final int index;
  final Project project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${index + 1}'.padLeft(2, '0'),
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '${project.durationSeconds ~/ 60} 分钟',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    if (project.description?.trim().isNotEmpty == true) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          '·',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          project.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: AppColors.ink,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_outward_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
        ],
      ),
    ),
  );
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(24, 34, 24, 30),
    decoration: BoxDecoration(
      color: AppColors.night,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: const BoxDecoration(
            color: AppColors.signal,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add_rounded, color: AppColors.ink),
        ),
        const SizedBox(height: 24),
        const Text(
          '从第一个项目开始',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '创建项目，加入论文、PPT 或其他答辩材料。',
          style: TextStyle(color: Colors.white60, height: 1.5),
        ),
        const SizedBox(height: 26),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.signal,
            foregroundColor: AppColors.ink,
          ),
          onPressed: onCreate,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('创建第一个项目'),
        ),
      ],
    ),
  );
}
