import 'package:flutter/material.dart';

import 'models.dart';

class ProjectDraft {
  const ProjectDraft({
    required this.name,
    required this.description,
    required this.durationSeconds,
  });

  final String name;
  final String? description;
  final int durationSeconds;
}

Future<ProjectDraft?> showProjectEditor(
  BuildContext context, {
  Project? project,
}) => showDialog<ProjectDraft>(
  context: context,
  builder: (context) => _ProjectEditorDialog(project: project),
);

class _ProjectEditorDialog extends StatefulWidget {
  const _ProjectEditorDialog({this.project});

  final Project? project;

  @override
  State<_ProjectEditorDialog> createState() => _ProjectEditorDialogState();
}

class _ProjectEditorDialogState extends State<_ProjectEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late int _minutes;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.project?.name);
    _description = TextEditingController(text: widget.project?.description);
    _minutes = (widget.project?.durationSeconds ?? 300) ~/ 60;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.project == null ? '新建答辩项目' : '编辑答辩项目'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '项目名称'),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? '请输入项目名称' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(labelText: '一句话说明'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('目标时长'),
                  const Spacer(),
                  IconButton(
                    tooltip: '减少一分钟',
                    onPressed: _minutes > 1
                        ? () => setState(() => _minutes--)
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      '$_minutes 分钟',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: '增加一分钟',
                    onPressed: _minutes < 30
                        ? () => setState(() => _minutes++)
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _submit,
        child: Text(widget.project == null ? '创建' : '保存'),
      ),
    ],
  );

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final detail = _description.text.trim();
    Navigator.pop(
      context,
      ProjectDraft(
        name: _name.text.trim(),
        description: detail.isEmpty ? null : detail,
        durationSeconds: _minutes * 60,
      ),
    );
  }
}
