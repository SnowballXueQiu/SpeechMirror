import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

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

  void _reload() =>
      setState(() => _projects = ref.read(apiClientProvider).listProjects());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('言镜'),
      actions: [
        IconButton(
          tooltip: '退出登录',
          onPressed: () => ref.read(authControllerProvider).logout(),
          icon: const Icon(Icons.logout),
        ),
        const SizedBox(width: 8),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _createProject,
      backgroundColor: AppColors.vermilion,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: const Text('新建项目'),
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
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(snapshot.error.toString()),
                ),
              ],
            );
          }
          final projects = snapshot.data ?? const [];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 110),
            children: [
              const PageIntro(
                eyebrow: 'YOUR REHEARSAL DESK',
                title: '我的答辩项目',
                description: '材料、训练、追问和改进记录集中在同一个项目中。',
              ),
              const SizedBox(height: 30),
              SectionLabel('${projects.length} 个项目'),
              const SizedBox(height: 14),
              if (projects.isEmpty) _EmptyProjects(onCreate: _createProject),
              for (final project in projects) ...[
                Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.push('/projects/${project.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 56,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.ink,
                              borderRadius: BorderRadius.all(
                                Radius.circular(4),
                              ),
                            ),
                            child: Text(
                              '${project.durationSeconds ~/ 60}\nMIN',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  project.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  project.description?.isNotEmpty == true
                                      ? project.description!
                                      : '尚未填写项目简介',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    ),
  );

  Future<void> _createProject() async {
    final name = TextEditingController();
    final description = TextEditingController();
    var minutes = 5;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('新建答辩项目'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '项目名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '一句话说明'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('目标时长'),
                    const Spacer(),
                    IconButton(
                      onPressed: minutes > 1
                          ? () => setDialogState(() => minutes--)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Text(
                      '$minutes 分钟',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      onPressed: minutes < 30
                          ? () => setDialogState(() => minutes++)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || name.text.trim().isEmpty) return;
    try {
      final project = await ref
          .read(apiClientProvider)
          .createProject(
            name.text,
            description.text.trim().isEmpty ? null : description.text.trim(),
            minutes * 60,
          );
      if (!mounted) return;
      _reload();
      context.push('/projects/${project.id}');
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onCreate});
  final VoidCallback onCreate;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 56),
    child: Column(
      children: [
        const Icon(Icons.mic_none, size: 48, color: AppColors.jade),
        const SizedBox(height: 16),
        Text('从一份真实材料开始', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          '创建项目后上传论文或PPT，言镜将据此训练和追问。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('创建第一个项目'),
        ),
      ],
    ),
  );
}
