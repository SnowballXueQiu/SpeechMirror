import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

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
}) => showAppSheet<ProjectDraft>(
  context,
  builder: (context) => _ProjectEditorSheet(project: project),
);

class _ProjectEditorSheet extends StatefulWidget {
  const _ProjectEditorSheet({this.project});

  final Project? project;

  @override
  State<_ProjectEditorSheet> createState() => _ProjectEditorSheetState();
}

class _ProjectEditorSheetState extends State<_ProjectEditorSheet> {
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
  Widget build(BuildContext context) => AnimatedPadding(
    duration: const Duration(milliseconds: 180),
    curve: Curves.easeOutCubic,
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: AppSheet(
      title: widget.project == null ? '新建答辩项目' : '编辑答辩项目',
      subtitle: '设置名称、简介和项目陈述时长',
      icon: widget.project == null ? Icons.add_rounded : Icons.edit_outlined,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _FieldLabel('项目名称'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _name,
                autofocus: true,
                maxLength: 80,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  hintText: '例如：SpeechMirror AI答辩教练',
                  counterText: '',
                ),
                validator: (value) =>
                    (value?.trim().isEmpty ?? true) ? '请输入项目名称' : null,
              ),
              const SizedBox(height: 18),
              const _FieldLabel('项目简介'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _description,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '用一两句话说明项目解决的问题',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 9, 9, 9),
                decoration: BoxDecoration(
                  color: AppColors.paper,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '目标时长',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: 2),
                          Text(
                            '项目陈述的参考时间',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '减少一分钟',
                      onPressed: _minutes > 1
                          ? () => setState(() => _minutes--)
                          : null,
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(36),
                        backgroundColor: AppColors.white,
                        side: const BorderSide(color: AppColors.line),
                      ),
                      icon: const Icon(Icons.remove_rounded, size: 18),
                    ),
                    SizedBox(
                      width: 68,
                      child: Text(
                        '$_minutes 分钟',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '增加一分钟',
                      onPressed: _minutes < 30
                          ? () => setState(() => _minutes++)
                          : null,
                      style: IconButton.styleFrom(
                        fixedSize: const Size.square(36),
                        backgroundColor: AppColors.ink,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _submit,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.project == null
                                ? Icons.add_rounded
                                : Icons.check_rounded,
                          ),
                          const SizedBox(width: 8),
                          Text(widget.project == null ? '创建项目' : '保存'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppColors.ink,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
  );
}
