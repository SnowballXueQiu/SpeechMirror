import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../auth_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class JuryScreen extends ConsumerStatefulWidget {
  const JuryScreen({
    super.key,
    required this.projectId,
    this.sessionId,
    this.autoStart = false,
  });

  final String projectId;
  final String? sessionId;
  final bool autoStart;

  @override
  ConsumerState<JuryScreen> createState() => _JuryScreenState();
}

class _JuryScreenState extends ConsumerState<JuryScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final FlutterTts _tts = FlutterTts();
  final TextEditingController _answer = TextEditingController();
  final Map<String, List<JuryAnswer>> _turns = {};
  Timer? _timer;
  Project? _project;
  List<JuryQuestion> _questions = const [];
  String? _sessionId;
  int _currentIndex = 0;
  int _elapsedSeconds = 0;
  bool _loading = true;
  bool _recording = false;
  bool _transcribing = false;
  bool _submitting = false;
  bool _finishing = false;
  bool _speaking = false;
  bool _answeringFollowUp = false;
  bool _deadlineSignaled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _configureSpeech();
      final api = ref.read(apiClientProvider);
      final project = await api.getProject(widget.projectId);
      _project = project;
      final session = await _ensureSession(project);
      List<JuryQuestion> questions;
      if (widget.autoStart) {
        questions = await _generateQuestions(project, session);
      } else {
        final existing = await api.listQuestions(widget.projectId);
        questions = existing
            .where((question) => question.sessionId == session)
            .toList();
        if (questions.isEmpty) {
          questions = await _generateQuestions(project, session);
        }
      }
      if (!mounted) return;
      setState(() {
        _questions = questions;
        _loading = false;
      });
      _startTimer();
      await _speakCurrent();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _configureSpeech() async {
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.46);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<String> _ensureSession(Project project) async {
    if (_sessionId != null) return _sessionId!;
    final created = await ref
        .read(apiClientProvider)
        .createSession(project.id, project.durationSeconds, null);
    _sessionId = created.id;
    return created.id;
  }

  Future<List<JuryQuestion>> _generateQuestions(
    Project project,
    String sessionId,
  ) => ref
      .read(apiClientProvider)
      .generateQuestions(
        widget.projectId,
        sessionId: sessionId,
        count: _questionCount(project.durationSeconds),
      );

  int _questionCount(int seconds) {
    if (seconds <= 6 * 60) return 3;
    if (seconds <= 11 * 60) return 5;
    return 7;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _elapsedSeconds + 1;
      final target = _project?.durationSeconds ?? 300;
      if (!_deadlineSignaled && next >= target) {
        _deadlineSignaled = true;
        HapticFeedback.heavyImpact();
      }
      setState(() => _elapsedSeconds = next);
    });
  }

  JuryQuestion? get _currentQuestion =>
      _currentIndex < _questions.length ? _questions[_currentIndex] : null;

  List<JuryAnswer> get _currentTurns {
    final question = _currentQuestion;
    return question == null ? const [] : (_turns[question.id] ?? const []);
  }

  String get _currentPrompt {
    final question = _currentQuestion;
    if (question == null) return '';
    if (_answeringFollowUp && _currentTurns.isNotEmpty) {
      return _currentTurns.last.followUp ?? question.question;
    }
    return question.question;
  }

  Future<void> _speakCurrent() async {
    final prompt = _currentPrompt.trim();
    if (prompt.isEmpty || _recording) return;
    await _tts.stop();
    if (mounted) setState(() => _speaking = true);
    try {
      await _tts.speak(prompt);
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _toggleVoice() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (mounted) {
        setState(() {
          _recording = false;
          _transcribing = true;
        });
      }
      if (path == null) {
        if (mounted) setState(() => _transcribing = false);
        return;
      }
      try {
        final transcript = await ref
            .read(apiClientProvider)
            .uploadAudio(_sessionId!, path, answerOnly: true);
        _answer.text = transcript;
      } catch (error) {
        if (mounted) showError(context, error);
      } finally {
        final file = File(path);
        if (await file.exists()) await file.delete();
        if (mounted) setState(() => _transcribing = false);
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) showError(context, StateError('需要麦克风权限才能回答问题'));
      return;
    }
    await _tts.stop();
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/jury-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _submitAnswer() async {
    final question = _currentQuestion;
    final text = _answer.text.trim();
    if (question == null || text.isEmpty) {
      showError(context, const FormatException('请先录制或输入回答'));
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final turns = _currentTurns;
      final result = await ref
          .read(apiClientProvider)
          .submitAnswer(
            question.id,
            _sessionId!,
            text,
            parentAnswerId: _answeringFollowUp && turns.isNotEmpty
                ? turns.last.id
                : null,
          );
      if (!mounted) return;
      setState(() {
        _turns[question.id] = [...turns, result];
        _answer.clear();
        _answeringFollowUp = false;
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _acceptFollowUp() async {
    setState(() {
      _answeringFollowUp = true;
      _answer.clear();
    });
    await _speakCurrent();
  }

  Future<void> _nextQuestion() async {
    if (_currentIndex + 1 >= _questions.length) {
      await _finish();
      return;
    }
    setState(() {
      _currentIndex += 1;
      _answeringFollowUp = false;
      _answer.clear();
    });
    await _speakCurrent();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    if (_recording) await _recorder.stop();
    await _tts.stop();
    _timer?.cancel();
    setState(() {
      _recording = false;
      _finishing = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).analyzeSession(_sessionId!);
      if (mounted) context.go('/reports/${_sessionId!}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _finishing = false;
      });
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answer.dispose();
    _recorder.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _transcribing || _submitting || _finishing;
    return PopScope(
      canPop: !_recording && !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('模拟答辩'),
          actions: [
            IconButton(
              tooltip: '结束答辩',
              onPressed: _loading || busy ? null : _finish,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          ],
        ),
        body: _loading
            ? _LoadingJury(error: _error)
            : _questions.isEmpty
            ? _LoadingJury(error: _error ?? '未能生成有效的评委问题')
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
                children: [
                  const DefenseStageRail(activeStage: 1),
                  const SizedBox(height: 22),
                  const PageIntro(
                    eyebrow: 'STAGE 02 / AI JURY',
                    title: '评委提问',
                    description: '问题来自项目材料和刚才的现场陈述。完成关键追问即可，不按秒强制结束。',
                  ),
                  const SizedBox(height: 20),
                  _TimeBand(
                    elapsed: _elapsedSeconds,
                    target: _project?.durationSeconds ?? 300,
                    reached: _deadlineSignaled,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.vermilion),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _QuestionStage(
                    index: _currentIndex,
                    total: _questions.length,
                    category: _currentQuestion!.category,
                    prompt: _currentPrompt,
                    turns: _currentTurns,
                    speaking: _speaking,
                    answeringFollowUp: _answeringFollowUp,
                    onReplay: busy ? null : _speakCurrent,
                  ),
                  const SizedBox(height: 16),
                  if (_currentTurns.isEmpty || _answeringFollowUp) ...[
                    TextField(
                      controller: _answer,
                      minLines: 2,
                      maxLines: 5,
                      enabled: !busy && !_recording,
                      decoration: const InputDecoration(
                        hintText: '语音转写会显示在这里，也可以直接编辑',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: _recording ? '结束回答' : '开始语音回答',
                          onPressed: busy ? null : _toggleVoice,
                          icon: Icon(_recording ? Icons.stop : Icons.mic_none),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: busy || _recording
                                ? null
                                : _submitAnswer,
                            icon: busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_outlined),
                            label: Text(
                              _transcribing
                                  ? '正在识别回答'
                                  : (_submitting ? '正在评议' : '提交回答'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_recording) ...[
                      const SizedBox(height: 8),
                      const Text(
                        '正在录音，再次点按麦克风按钮结束。',
                        style: TextStyle(color: AppColors.vermilion),
                      ),
                    ],
                  ] else ...[
                    _TurnEvaluation(answer: _currentTurns.last),
                    const SizedBox(height: 14),
                    if (_currentTurns.last.followUp != null &&
                        _currentTurns.length < 2)
                      OutlinedButton.icon(
                        onPressed: busy ? null : _acceptFollowUp,
                        icon: const Icon(Icons.subdirectory_arrow_right),
                        label: const Text('回答这一项关键追问'),
                      ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: busy ? null : _nextQuestion,
                      icon: Icon(
                        _currentIndex + 1 >= _questions.length
                            ? Icons.assessment_outlined
                            : Icons.arrow_forward,
                      ),
                      label: Text(
                        _currentIndex + 1 >= _questions.length
                            ? (_finishing ? '正在生成综合报告' : '结束答辩并生成报告')
                            : '下一题',
                      ),
                    ),
                  ],
                  if (_deadlineSignaled) ...[
                    const SizedBox(height: 14),
                    const Text(
                      '预计答辩时间已到。可以完成当前回答后结束，也可以继续一项关键追问。',
                      style: TextStyle(color: AppColors.vermilion),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _LoadingJury extends StatelessWidget {
  const _LoadingJury({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error == null)
            const CircularProgressIndicator()
          else
            const Icon(
              Icons.error_outline,
              size: 42,
              color: AppColors.vermilion,
            ),
          const SizedBox(height: 16),
          Text(
            error ?? 'AI评委正在阅读材料和现场陈述',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _TimeBand extends StatelessWidget {
  const _TimeBand({
    required this.elapsed,
    required this.target,
    required this.reached,
  });

  final int elapsed;
  final int target;
  final bool reached;

  String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Column(
      children: [
        Row(
          children: [
            const Icon(Icons.schedule, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Text(
              '${_clock(elapsed)} / 预计 ${_clock(target)}',
              style: TextStyle(
                color: reached ? const Color(0xFFFFA98E) : Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              reached ? '可结束' : '进行中',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: (elapsed / target.clamp(1, 3600)).clamp(0.0, 1.0),
          minHeight: 5,
          color: reached ? AppColors.vermilion : AppColors.jade,
          backgroundColor: Colors.white24,
        ),
      ],
    ),
  );
}

class _QuestionStage extends StatelessWidget {
  const _QuestionStage({
    required this.index,
    required this.total,
    required this.category,
    required this.prompt,
    required this.turns,
    required this.speaking,
    required this.answeringFollowUp,
    required this.onReplay,
  });

  final int index;
  final int total;
  final String category;
  final String prompt;
  final List<JuryAnswer> turns;
  final bool speaking;
  final bool answeringFollowUp;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${(index + 1).toString().padLeft(2, '0')} / ${total.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: AppColors.vermilion,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                answeringFollowUp ? '追问' : category,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '重新播放问题',
                onPressed: onReplay,
                icon: Icon(
                  speaking ? Icons.volume_up : Icons.volume_up_outlined,
                  color: AppColors.jade,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            prompt,
            style: const TextStyle(
              fontFamily: 'Songti SC',
              fontSize: 22,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (turns.isNotEmpty && answeringFollowUp) ...[
            const Divider(height: 28),
            Text(
              '上一轮回答：${turns.last.answerText}',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ],
      ),
    ),
  );
}

class _TurnEvaluation extends StatelessWidget {
  const _TurnEvaluation({required this.answer});

  final JuryAnswer answer;

  @override
  Widget build(BuildContext context) {
    final data = answer.evaluation;
    final score = (data['score'] as num?)?.toInt();
    final suggestions = data['suggestions'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: AppColors.jade),
              const SizedBox(width: 8),
              Text(
                score == null ? '本轮反馈' : '本轮反馈  $score 分',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('你的回答：${answer.answerText}'),
          if (data['relevance'] != null) ...[
            const SizedBox(height: 8),
            Text('相关性：${data['relevance']}'),
          ],
          if (data['accuracy'] != null) Text('准确性：${data['accuracy']}'),
          if (suggestions != null) ...[
            const SizedBox(height: 8),
            Text(
              '改进：${suggestions is List ? suggestions.join('；') : suggestions}',
            ),
          ],
        ],
      ),
    );
  }
}
