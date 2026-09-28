import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
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

  CameraController? _camera;
  Timer? _timer;
  Project? _project;
  List<JuryQuestion> _questions = const [];
  JuryAnswer? _pendingAnswer;
  String? _sessionId;
  String? _activePrompt;
  String? _parentAnswerId;
  String? _error;
  int _elapsedSeconds = 0;
  bool _loading = true;
  bool _recording = false;
  bool _transcribing = false;
  bool _submitting = false;
  bool _finishing = false;
  bool _speaking = false;
  bool _timerRunning = false;
  bool _deadlineSignaled = false;
  bool _pendingFinish = false;

  JuryQuestion? get _currentQuestion =>
      _questions.isEmpty ? null : _questions.last;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _initialize();
  }

  Future<void> _initialize() async {
    unawaited(_initializeCamera());
    try {
      await _configureSpeech();
      final api = ref.read(apiClientProvider);
      final project = await api.getProject(widget.projectId);
      final session = await _ensureSession(project);
      final questions = await api.generateQuestions(
        widget.projectId,
        sessionId: session,
        count: 1,
      );
      if (!mounted) return;
      setState(() {
        _project = project;
        _questions = questions;
        _activePrompt = questions.lastOrNull?.question;
        _loading = false;
        _error = questions.isEmpty ? '暂时没有生成有效问题' : null;
      });
      if (questions.isNotEmpty) await _speakCurrent();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final selected = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (_) {
      // The defense can continue with voice if a simulator has no camera.
    }
  }

  Future<void> _configureSpeech() async {
    await _tts.setLanguage('zh-CN');
    await _tts.setSpeechRate(0.46);
    await _tts.setPitch(0.94);
    await _tts.setVolume(1.0);
    await _tts.awaitSpeakCompletion(true);
    final voices = await _tts.getVoices;
    if (voices is! List) return;
    final chineseVoices = voices
        .whereType<Map>()
        .map((voice) => Map<String, dynamic>.from(voice))
        .where(
          (voice) =>
              voice['locale']?.toString().toLowerCase().startsWith('zh') ??
              false,
        )
        .toList();
    if (chineseVoices.isEmpty) return;
    chineseVoices.sort((left, right) {
      int rank(Map<String, dynamic> voice) {
        final name = '${voice['name']} ${voice['identifier']}'.toLowerCase();
        if (name.contains('ting-ting') || name.contains('premium')) return 0;
        if (name.contains('enhanced')) return 1;
        return 2;
      }

      return rank(left).compareTo(rank(right));
    });
    await _tts.setVoice(
      chineseVoices.first.map((key, value) => MapEntry(key, value.toString())),
    );
  }

  Future<String> _ensureSession(Project project) async {
    if (_sessionId != null) return _sessionId!;
    final session = await ref
        .read(apiClientProvider)
        .createSession(project.id, project.durationSeconds, null);
    _sessionId = session.id;
    return session.id;
  }

  void _resumeTimer() {
    if (_timerRunning || !mounted || _finishing) return;
    _timerRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _elapsedSeconds + 1;
      final target = _project?.durationSeconds ?? 300;
      if (!_deadlineSignaled && next >= target) {
        _deadlineSignaled = true;
        HapticFeedback.mediumImpact();
      }
      setState(() => _elapsedSeconds = next);
    });
  }

  void _pauseTimer() {
    _timerRunning = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _speakCurrent() async {
    final prompt = _activePrompt?.trim();
    if (prompt == null || prompt.isEmpty || _recording) return;
    _pauseTimer();
    await _tts.stop();
    if (mounted) setState(() => _speaking = true);
    try {
      await _tts.speak(prompt);
    } finally {
      if (mounted) {
        setState(() => _speaking = false);
        _resumeTimer();
      }
    }
  }

  Future<void> _toggleVoice() async {
    if (_recording) {
      _pauseTimer();
      final path = await _recorder.stop();
      if (mounted) {
        setState(() {
          _recording = false;
          _transcribing = true;
        });
      }
      if (path == null) {
        if (mounted) {
          setState(() => _transcribing = false);
          _resumeTimer();
        }
        return;
      }
      try {
        final transcript = await ref
            .read(apiClientProvider)
            .uploadAudio(_sessionId!, path, answerOnly: true);
        _answer.text = transcript;
        if (mounted) {
          setState(() => _transcribing = false);
          _resumeTimer();
          await _showAnswerSheet();
        }
      } catch (error) {
        if (mounted) {
          setState(() => _transcribing = false);
          _resumeTimer();
          showError(context, error);
        }
      } finally {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      return;
    }

    if (_speaking || _submitting || _finishing || _transcribing) return;
    if (!await _recorder.hasPermission()) {
      if (mounted) showError(context, StateError('需要麦克风权限才能回答问题'));
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
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

  Future<void> _showAnswerSheet() async {
    if (!mounted || _submitting || _finishing) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 18,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '确认回答',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '收起键盘',
                    onPressed: () =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    icon: const Icon(Icons.keyboard_hide_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _answer,
                autofocus: _answer.text.isEmpty,
                minLines: 3,
                maxLines: 7,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(hintText: '输入或修改你的回答'),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('继续准备'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.of(sheetContext).pop();
                        _submitAnswer();
                      },
                      icon: const Icon(Icons.send_outlined),
                      label: const Text('提交回答'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitAnswer() async {
    final question = _currentQuestion;
    final text = _answer.text.trim();
    if (question == null || text.isEmpty) {
      if (mounted) {
        showError(context, const FormatException('请先录制或输入回答'));
        await _showAnswerSheet();
      }
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _pauseTimer();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(apiClientProvider)
          .submitAnswer(
            question.id,
            _sessionId!,
            text,
            parentAnswerId: _parentAnswerId,
            elapsedSeconds: _elapsedSeconds,
          );
      if (!mounted) return;
      setState(() {
        _turns[question.id] = [...?_turns[question.id], result];
        _answer.clear();
        _pendingAnswer = result;
      });
      await _advanceAfterAnswer(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString();
      });
      _resumeTimer();
    }
  }

  Future<void> _advanceAfterAnswer(JuryAnswer answer) async {
    if (!mounted) return;
    if (answer.decision == JuryDecision.followUp && answer.followUp != null) {
      setState(() {
        _parentAnswerId = answer.id;
        _activePrompt = answer.followUp;
        _pendingAnswer = null;
        _submitting = false;
      });
      await _speakCurrent();
      return;
    }
    if (answer.decision == JuryDecision.endDefense) {
      setState(() {
        _pendingAnswer = null;
        _submitting = false;
      });
      await _finish(announce: true);
      return;
    }

    try {
      final questions = await ref
          .read(apiClientProvider)
          .generateQuestions(
            widget.projectId,
            sessionId: _sessionId,
            count: _questions.length + 1,
          );
      if (!mounted) return;
      if (questions.length <= _questions.length) {
        throw StateError('AI评委暂时没有生成下一道有效问题');
      }
      setState(() {
        _questions = questions;
        _activePrompt = questions.last.question;
        _parentAnswerId = null;
        _pendingAnswer = null;
        _submitting = false;
        _error = null;
      });
      await _speakCurrent();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _retry() async {
    if (_loading || _submitting || _finishing) return;
    setState(() => _error = null);
    if (_pendingFinish) {
      await _finish(announce: false);
      return;
    }
    if (_pendingAnswer != null) {
      setState(() => _submitting = true);
      await _advanceAfterAnswer(_pendingAnswer!);
      return;
    }
    setState(() => _loading = true);
    await _initialize();
  }

  Future<void> _finish({required bool announce}) async {
    if (_finishing) return;
    _pauseTimer();
    if (_recording) {
      final path = await _recorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
    await _tts.stop();
    if (!mounted) return;
    setState(() {
      _recording = false;
      _finishing = true;
      _pendingFinish = true;
      _error = null;
    });
    try {
      if (announce) {
        setState(() => _speaking = true);
        await _tts.speak('本次答辩结束。');
        if (mounted) setState(() => _speaking = false);
      }
      await ref.read(apiClientProvider).analyzeSession(_sessionId!);
      if (mounted) context.go('/reports/${_sessionId!}');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _finishing = false;
        _speaking = false;
      });
    }
  }

  Future<void> _confirmManualEnd() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('结束本次答辩？'),
        content: const Text('评委将停止提问并生成综合报告。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续答辩'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('结束答辩'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _finish(announce: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _answer.dispose();
    _recorder.dispose();
    _tts.stop();
    _camera?.dispose();
    super.dispose();
  }

  String get _statusText {
    if (_finishing) return _speaking ? '评委宣布结束' : '正在生成综合报告';
    if (_loading) return '评委正在阅读材料与现场陈述';
    if (_transcribing) return '正在识别回答';
    if (_submitting) return '评委正在思考';
    if (_speaking) return '评委提问';
    if (_recording) return '正在回答';
    return '请回答';
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loading || _transcribing || _submitting || _finishing;
    return PopScope(
      canPop: !_recording && !busy,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _CameraSurface(controller: _camera),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton.filled(
                          tooltip: '结束答辩',
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: busy ? null : _confirmManualEnd,
                          icon: const Icon(Icons.close),
                        ),
                        const Spacer(),
                        _ElapsedClock(seconds: _elapsedSeconds),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const Spacer(),
                    if (_error != null)
                      _ErrorBanner(message: _error!, onRetry: _retry),
                    if (_error != null) const SizedBox(height: 10),
                    _QuestionOverlay(
                      status: _statusText,
                      question: _activePrompt,
                      speaking: _speaking,
                      loading: _loading,
                      onReplay: busy || _activePrompt == null
                          ? null
                          : _speakCurrent,
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RoundControl(
                          tooltip: '输入文字回答',
                          icon: Icons.keyboard_alt_outlined,
                          onPressed: busy || _recording
                              ? null
                              : _showAnswerSheet,
                        ),
                        _RoundControl(
                          tooltip: _recording ? '结束回答' : '开始回答',
                          icon: _recording ? Icons.stop : Icons.mic,
                          emphasized: true,
                          active: _recording,
                          onPressed: busy && !_recording ? null : _toggleVoice,
                        ),
                        _RoundControl(
                          tooltip: '结束答辩',
                          icon: Icons.call_end,
                          destructive: true,
                          onPressed: busy ? null : _confirmManualEnd,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraSurface extends StatelessWidget {
  const _CameraSurface({required this.controller});

  final CameraController? controller;

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized) {
      return const ColoredBox(
        color: Color(0xFF151B19),
        child: Center(
          child: Icon(Icons.person_outline, color: Colors.white24, size: 96),
        ),
      );
    }
    final screen = MediaQuery.sizeOf(context);
    var scale = screen.aspectRatio * camera.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        child: Center(child: CameraPreview(camera)),
      ),
    );
  }
}

class _ElapsedClock extends StatelessWidget {
  const _ElapsedClock({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white24),
    ),
    child: Text(
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}

class _QuestionOverlay extends StatelessWidget {
  const _QuestionOverlay({
    required this.status,
    required this.question,
    required this.speaking,
    required this.loading,
    required this.onReplay,
  });

  final String status;
  final String? question;
  final bool speaking;
  final bool loading;
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    constraints: const BoxConstraints(maxHeight: 220),
    padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
    decoration: BoxDecoration(
      color: const Color(0xD91A211E),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white24),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (loading)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF8AD8C1),
                ),
              )
            else
              Icon(
                speaking ? Icons.graphic_eq : Icons.record_voice_over_outlined,
                size: 17,
                color: const Color(0xFF8AD8C1),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status,
                style: const TextStyle(
                  color: Color(0xFFB6C5BF),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: '重新播放问题',
              onPressed: onReplay,
              icon: const Icon(Icons.volume_up_outlined),
              color: Colors.white,
            ),
          ],
        ),
        if (question != null) ...[
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                question!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  height: 1.45,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    decoration: BoxDecoration(
      color: const Color(0xE6451F1A),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: const Text('重试', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
    this.active = false,
    this.destructive = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool active;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final background = destructive
        ? const Color(0xFFD84B3E)
        : emphasized
        ? (active ? const Color(0xFFF1F3EF) : AppColors.jade)
        : Colors.black54;
    final foreground = active ? AppColors.ink : Colors.white;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: Size.square(emphasized ? 68 : 54),
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: Colors.black26,
          disabledForegroundColor: Colors.white30,
          side: const BorderSide(color: Colors.white24),
        ),
        iconSize: emphasized ? 31 : 25,
        icon: Icon(icon),
      ),
    );
  }
}
