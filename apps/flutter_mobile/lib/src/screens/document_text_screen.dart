import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api_client.dart';
import '../auth_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class DocumentTextScreen extends ConsumerStatefulWidget {
  const DocumentTextScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<DocumentTextScreen> createState() => _DocumentTextScreenState();
}

class _DocumentTextScreenState extends ConsumerState<DocumentTextScreen> {
  final _controller = TextEditingController();
  ProjectDocument? _document;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final document = await ref
          .read(apiClientProvider)
          .getDocument(widget.documentId);
      if (!mounted) return;
      _controller.text = document.text ?? '';
      setState(() {
        _document = document;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showError(context, error);
    }
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      showError(context, const ApiException('提取文本不能为空'));
      return;
    }
    setState(() => _saving = true);
    try {
      final document = await ref
          .read(apiClientProvider)
          .correctDocumentText(widget.documentId, text);
      if (!mounted) return;
      _controller.text = document.text ?? text;
      setState(() => _document = document);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('文本已保存，知识库索引已更新')));
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    return Scaffold(
      appBar: AppBar(
        title: const Text('材料文本'),
        actions: [
          IconButton(
            tooltip: '保存并重建索引',
            onPressed:
                document == null || document.status == 'processing' || _saving
                ? null
                : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : document == null
          ? const Center(child: Text('无法读取材料'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
              children: [
                Text(
                  document.filename,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      document.status == 'ready'
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 18,
                      color: document.status == 'ready'
                          ? AppColors.jade
                          : AppColors.vermilion,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        document.status == 'ready'
                            ? '已进入知识库，可校对下方文本'
                            : document.error ?? '材料处理失败，可手动录入文本',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const ValueKey('document-text-editor'),
                  controller: _controller,
                  minLines: 18,
                  maxLines: null,
                  enabled: document.status != 'processing' && !_saving,
                  decoration: const InputDecoration(
                    labelText: '提取文本',
                    alignLabelWithHint: true,
                    hintText: '检查 OCR 或文档解析结果，必要时在这里修正。',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: document.status == 'processing' || _saving
                      ? null
                      : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存并重建索引'),
                ),
              ],
            ),
    );
  }
}
