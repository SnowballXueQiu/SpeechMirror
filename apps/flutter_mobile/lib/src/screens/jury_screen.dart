import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../auth_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class JuryScreen extends ConsumerStatefulWidget {
  const JuryScreen({super.key, required this.projectId, this.sessionId});
  final String projectId;
  final String? sessionId;

  @override
  ConsumerState<JuryScreen> createState() => _JuryScreenState();
}

class _JuryScreenState extends ConsumerState<JuryScreen> {
  List<JuryQuestion> _questions = const [];
  final Map<String, TextEditingController> _answers = {};
  final Map<String, List<JuryAnswer>> _turns = {};
  final AudioRecorder _recorder = AudioRecorder();
  String? _sessionId;
  String? _recordingQuestionId;
  String? _submittingQuestionId;
  bool _loading = true;
  bool _generating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _load();
  }

  Future<void> _load() async {
    try {
      final questions = await ref
          .read(apiClientProvider)
          .listQuestions(widget.projectId);
      if (mounted) {
        setState(() {
          _questions = questions;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<String> _ensureSession([String? questionSessionId]) async {
    if (questionSessionId != null) {
      _sessionId = questionSessionId;
      return questionSessionId;
    }
    if (_sessionId != null) return _sessionId!;
    final project = await ref
        .read(apiClientProvider)
        .getProject(widget.projectId);
    final sessions = await ref
        .read(apiClientProvider)
        .listSessions(widget.projectId);
    if (sessions.isNotEmpty) {
      _sessionId = sessions.first.id;
    } else {
      _sessionId =
          (await ref
                  .read(apiClientProvider)
                  .createSession(project.id, project.durationSeconds, null))
              .id;
    }
    return _sessionId!;
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final session = await _ensureSession();
      final questions = await ref
          .read(apiClientProvider)
          .generateQuestions(widget.projectId, sessionId: session);
      if (mounted) setState(() => _questions = questions);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _submit(JuryQuestion question) async {
    final answer = _controller(question.id).text.trim();
    if (answer.isEmpty) {
      showError(context, const FormatException('请先输入或录制回答'));
      return;
    }
    setState(() {
      _submittingQuestionId = question.id;
      _error = null;
    });
    try {
      final session = await _ensureSession(question.sessionId);
      final questionTurns = _turns[question.id] ?? const <JuryAnswer>[];
      final parentAnswerId = questionTurns.isEmpty
          ? null
          : questionTurns.last.id;
      final result = await ref
          .read(apiClientProvider)
          .submitAnswer(
            question.id,
            session,
            answer,
            parentAnswerId: parentAnswerId,
          );
      if (mounted) {
        setState(() {
          _turns[question.id] = [...questionTurns, result];
          _controller(question.id).clear();
        });
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _submittingQuestionId = null);
    }
  }

  Future<void> _toggleVoice(JuryQuestion question) async {
    if (_recordingQuestionId == question.id) {
      final path = await _recorder.stop();
      setState(() => _recordingQuestionId = null);
      if (path == null) return;
      try {
        final session = await _ensureSession(question.sessionId);
        final transcript = await ref
            .read(apiClientProvider)
            .uploadAudio(session, path, answerOnly: true);
        _controller(question.id).text = transcript;
        if (mounted) setState(() {});
      } catch (error) {
        if (mounted) showError(context, error);
      }
      return;
    }
    if (_recordingQuestionId != null) return;
    if (!await _recorder.hasPermission()) {
      if (mounted) showError(context, StateError('需要麦克风权限才能录制回答'));
      return;
    }
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/jury-${question.id}.m4a';
    await Directory(directory.path).create(recursive: true);
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    if (mounted) setState(() => _recordingQuestionId = question.id);
  }

  TextEditingController _controller(String id) =>
      _answers.putIfAbsent(id, TextEditingController.new);

  @override
  void dispose() {
    for (final controller in _answers.values) {
      controller.dispose();
    }
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI评委席')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
            children: [
              const PageIntro(
                eyebrow: 'MATERIAL-GROUNDED Q&A',
                title: '让追问逼近薄弱处',
                description: '问题和评价均以当前项目材料为依据，不评价性格、情绪或可信度。',
              ),
              const SizedBox(height: 22),
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.vermilion),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_outlined),
                label: Text(
                  _generating
                      ? '正在研读材料'
                      : (_questions.isEmpty ? '生成一组评委问题' : '重新生成问题'),
                ),
              ),
              const SizedBox(height: 26),
              if (_questions.isEmpty)
                const _EmptyJury()
              else
                for (var i = 0; i < _questions.length; i++) ...[
                  _QuestionPanel(
                    index: i + 1,
                    question: _questions[i],
                    controller: _controller(_questions[i].id),
                    turns: _turns[_questions[i].id] ?? const [],
                    recording: _recordingQuestionId == _questions[i].id,
                    submitting: _submittingQuestionId == _questions[i].id,
                    onVoice: () => _toggleVoice(_questions[i]),
                    onSubmit: () => _submit(_questions[i]),
                  ),
                  const SizedBox(height: 14),
                ],
            ],
          ),
  );
}

class _QuestionPanel extends StatelessWidget {
  const _QuestionPanel({
    required this.index,
    required this.question,
    required this.controller,
    required this.turns,
    required this.recording,
    required this.submitting,
    required this.onVoice,
    required this.onSubmit,
  });
  final int index;
  final JuryQuestion question;
  final TextEditingController controller;
  final List<JuryAnswer> turns;
  final bool recording;
  final bool submitting;
  final VoidCallback onVoice;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                index.toString().padLeft(2, '0'),
                style: const TextStyle(
                  color: AppColors.vermilion,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.paperStrong,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  question.category,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            question.question,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          if (question.evidence.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '依据：${question.evidence.first.quote}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
          for (var i = 0; i < turns.length; i++) ...[
            const Divider(height: 28),
            Text(
              '第${i + 1}轮 · ${turns[i].askedQuestion}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('你的回答：${turns[i].answerText}'),
            const SizedBox(height: 10),
            _EvaluationView(data: turns[i].evaluation),
          ],
          const SizedBox(height: 14),
          if (turns.isNotEmpty && turns.last.followUp != null) ...[
            Text(
              '当前追问：${turns.last.followUp}',
              style: const TextStyle(
                color: AppColors.vermilion,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 7,
            decoration: InputDecoration(
              hintText: turns.isEmpty ? '组织你的回答……' : '回答当前追问……',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: recording ? '停止录音并转写' : '用语音回答',
                onPressed: submitting ? null : onVoice,
                icon: Icon(recording ? Icons.stop : Icons.mic_none),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: submitting ? null : onSubmit,
                  icon: submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.fact_check_outlined),
                  label: Text(turns.isEmpty ? '提交评议' : '回答追问'),
                ),
              ),
            ],
          ),
          if (recording) ...[
            const SizedBox(height: 8),
            const Text(
              '正在录音，再次点按停止并进行真实语音识别。',
              style: TextStyle(color: AppColors.vermilion, fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
}

class _EvaluationView extends StatelessWidget {
  const _EvaluationView({required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final score = (data['score'] as num?)?.toInt();
    final suggestion = data['suggestions'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.rate_review_outlined,
              color: AppColors.jade,
              size: 19,
            ),
            const SizedBox(width: 8),
            Text(
              score == null ? '评委反馈' : '评委反馈  $score / 100',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 9),
        if (data['relevance'] != null) Text('相关性：${data['relevance']}'),
        if (data['accuracy'] != null) Text('准确性：${data['accuracy']}'),
        if (suggestion != null) ...[
          const SizedBox(height: 7),
          Text('建议：${suggestion is List ? suggestion.join('；') : suggestion}'),
        ],
      ],
    );
  }
}

class _EmptyJury extends StatelessWidget {
  const _EmptyJury();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Icon(Icons.forum_outlined, size: 42, color: AppColors.jade),
        SizedBox(height: 12),
        Text(
          '还没有评委问题',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 6),
        Text('生成时会读取已解析的项目材料。', style: TextStyle(color: AppColors.muted)),
      ],
    ),
  );
}
