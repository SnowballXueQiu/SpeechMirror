import 'dart:async';
import 'dart:io';
import 'dart:math';

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
  static const _maxAutomaticRetries = 5;

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
  String? _pendingAudioPath;
  String? _pendingRequestId;
  String? _error;
  int _elapsedSeconds = 0;
  int _automaticRetryAttempt = 0;
  bool _loading = true;
  bool _recording = false;
  bool _transcribing = false;
  bool _submitting = false;
  bool _finishing = false;
  bool _speaking = false;
  bool _timerRunning = false;
  bool _deadlineSignaled = false;
  bool _requiresNewRecording = false;

  JuryQuestion? get _currentQuestion =>
      _questions.isEmpty ? null : _questions.last;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _initialize();
  }

  Future<void> _initialize() async {
    if (_camera == null) unawaited(_initializeCamera());
    try {
      await _configureSpeech();
      final api = ref.read(apiClientProvider);
      final project = await _withAutomaticRetry(
        () => api.getProject(widget.projectId),
      );
      final session = await _ensureSession(project);
      final questions = await _withAutomaticRetry(
        () => api.generateQuestions(
          widget.projectId,
          sessionId: session,
          count: 1,
        ),
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

  Future<T> _withAutomaticRetry<T>(Future<T> Function() operation) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _maxAutomaticRetries; attempt += 1) {
      if (attempt > 0) {
        if (!mounted) throw StateError('答辩页面已关闭');
        setState(() {
          _automaticRetryAttempt = attempt;
          _error = null;
        });
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
      try {
        final result = await operation();
        if (mounted && _automaticRetryAttempt != 0) {
          setState(() => _automaticRetryAttempt = 0);
        }
        return result;
      } catch (error) {
        lastError = error;
      }
    }
    if (mounted && _automaticRetryAttempt != 0) {
      setState(() => _automaticRetryAttempt = 0);
    }
    throw lastError ?? StateError('AI服务暂时未完成请求');
  }

  Future<void> _initializeCamera() async {
    if (_camera != null) return;
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
      _pendingAudioPath = path;
      await _transcribePendingAudio();
      return;
    }

    if (_speaking || _submitting || _finishing || _transcribing) return;
    if (!await _recorder.hasPermission()) {
      if (mounted) showError(context, StateError('需要麦克风权限才能回答问题'));
      return;
    }
    await _discardPendingAudio();
    if (!mounted) return;
    setState(() {
      _answer.clear();
      _error = null;
      _requiresNewRecording = false;
      _pendingRequestId = null;
    });
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

  Future<void> _transcribePendingAudio() async {
    final path = _pendingAudioPath;
    if (path == null) return;
    _pauseTimer();
    if (mounted) {
      setState(() {
        _transcribing = true;
        _error = null;
      });
    }
    try {
      final transcript = await _withAutomaticRetry(
        () => ref
            .read(apiClientProvider)
            .uploadAudio(_sessionId!, path, answerOnly: true),
      );
      _answer.text = transcript;
      _pendingAudioPath = null;
      final file = File(path);
      if (await file.exists()) await file.delete();
      if (!mounted) return;
      setState(() => _transcribing = false);
      _resumeTimer();
      await _showAnswerSheet();
    } catch (error) {
      final requiresNewRecording = _isNoSpeechError(error);
      if (requiresNewRecording) await _discardPendingAudio();
      if (!mounted) return;
      setState(() {
        _transcribing = false;
        _error = error.toString();
        _requiresNewRecording = requiresNewRecording;
      });
      if (requiresNewRecording) _resumeTimer();
    }
  }

  bool _isNoSpeechError(Object error) => error.toString().contains('未识别到有效语音');

  Future<void> _discardPendingAudio() async {
    final path = _pendingAudioPath;
    _pendingAudioPath = null;
    if (path == null) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<void> _rerecord() async {
    await _discardPendingAudio();
    if (!mounted) return;
    setState(() {
      _error = null;
      _requiresNewRecording = false;
    });
    await _toggleVoice();
  }

  Future<void> _showAnswerSheet() async {
    if (!mounted || _submitting || _finishing) return;
    await showAppSheet<void>(
      context,
      builder: (sheetContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: AppSheet(
          title: '确认回答',
          subtitle: '提交前检查语音转写内容',
          icon: Icons.mic_none_rounded,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _answer,
                autofocus: _answer.text.isEmpty,
                minLines: 3,
                maxLines: 7,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: InputDecoration(
                  hintText: '输入或修改你的回答',
                  suffixIcon: IconButton(
                    tooltip: '收起键盘',
                    onPressed: () =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    icon: const Icon(Icons.keyboard_hide_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.of(sheetContext).pop();
                        _submitAnswer();
                      },
                      icon: const Icon(Icons.send_rounded),
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
      _pendingRequestId ??= _createRequestId(question.id);
    });
    try {
      final result = await _withAutomaticRetry(
        () => ref
            .read(apiClientProvider)
            .submitAnswer(
              question.id,
              _sessionId!,
              text,
              parentAnswerId: _parentAnswerId,
              requestId: _pendingRequestId,
              elapsedSeconds: _elapsedSeconds,
            ),
      );
      if (!mounted) return;
      setState(() {
        _turns[question.id] = [...?_turns[question.id], result];
        _answer.clear();
        _pendingRequestId = null;
        _pendingAnswer = result;
      });
      await _advanceAfterAnswer(result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.toString();
      });
    }
  }

  String _createRequestId(String questionId) {
    final nonce = Random.secure().nextInt(1 << 32);
    return '${_sessionId}_${questionId}_${DateTime.now().microsecondsSinceEpoch}_$nonce';
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
      final questions = await _withAutomaticRetry(
        () => ref
            .read(apiClientProvider)
            .generateQuestions(
              widget.projectId,
              sessionId: _sessionId,
              count: _questions.length + 1,
            ),
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
    setState(() {
      _error = null;
      _requiresNewRecording = false;
    });
    if (_pendingAudioPath != null) {
      await _transcribePendingAudio();
      return;
    }
    if (_pendingRequestId != null) {
      await _submitAnswer();
      return;
    }
    if (_pendingAnswer != null) {
      setState(() => _submitting = true);
      await _advanceAfterAnswer(_pendingAnswer!);
      return;
    }
    if (_currentQuestion != null) {
      _resumeTimer();
      return;
    }
    setState(() => _loading = true);
    await _initialize();
  }

  Future<void> _finish({required bool announce}) async {
    if (_finishing) return;
    _pauseTimer();
    if (mounted) {
      setState(() {
        _finishing = true;
        _error = null;
        _requiresNewRecording = false;
      });
    }
    if (_recording) {
      final path = await _recorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
    await _discardPendingAudio();
    await _tts.stop();
    if (!mounted) return;
    setState(() => _recording = false);
    if (announce) {
      HapticFeedback.mediumImpact();
    }
    if (mounted) context.go('/reports/${_sessionId!}?generate=1');
  }

  Future<void> _confirmManualEnd() async {
    final confirmed = await showAppConfirmation(
      context,
      title: '结束本次答辩？',
      message: '评委将停止提问并生成综合报告。',
      confirmLabel: '结束答辩',
      cancelLabel: '继续答辩',
      icon: Icons.flag_outlined,
    );
    if (confirmed) await _finish(announce: true);
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
    if (_automaticRetryAttempt > 0) {
      return 'AI服务暂时未完成请求，正在自动重试（$_automaticRetryAttempt/$_maxAutomaticRetries）';
    }
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
    final processing =
        _loading ||
        _transcribing ||
        _submitting ||
        _finishing ||
        _automaticRetryAttempt > 0;
    final answerControlsDisabled =
        processing || _currentQuestion == null || _pendingAnswer != null;
    return PopScope(
      canPop: !_recording && !_finishing,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _CameraSurface(controller: _camera),
            const IgnorePointer(child: _JuryScrim()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _CallBadge(active: _speaking || _recording),
                        const Spacer(),
                        _ElapsedClock(seconds: _elapsedSeconds),
                      ],
                    ),
                    const Spacer(),
                    if (_error != null)
                      _ErrorBanner(
                        message: _error!,
                        actionLabel: _requiresNewRecording ? '重新录制' : '重试',
                        onAction: _requiresNewRecording ? _rerecord : _retry,
                      ),
                    if (_error != null) const SizedBox(height: 10),
                    _QuestionOverlay(
                      status: _statusText,
                      question: _activePrompt,
                      speaking: _speaking,
                      loading: _loading,
                      onReplay: processing || _activePrompt == null
                          ? null
                          : _speakCurrent,
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _RoundControl(
                          tooltip: '输入文字回答',
                          icon: Icons.keyboard_alt_outlined,
                          onPressed: answerControlsDisabled || _recording
                              ? null
                              : _showAnswerSheet,
                        ),
                        const SizedBox(width: 22),
                        _RoundControl(
                          tooltip: _recording ? '结束回答' : '开始回答',
                          icon: _recording ? Icons.stop_rounded : Icons.mic,
                          emphasized: true,
                          active: _recording,
                          onPressed: answerControlsDisabled && !_recording
                              ? null
                              : _toggleVoice,
                        ),
                        const SizedBox(width: 22),
                        _RoundControl(
                          tooltip: '结束答辩',
                          icon: Icons.call_end,
                          destructive: true,
                          onPressed: _finishing ? null : _confirmManualEnd,
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

class _JuryScrim extends StatelessWidget {
  const _JuryScrim();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x66000000),
          Colors.transparent,
          Colors.transparent,
          Color(0xE8000000),
        ],
        stops: [0, 0.17, 0.45, 1],
      ),
    ),
  );
}

class _CallBadge extends StatelessWidget {
  const _CallBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: active ? const Color(0xFF4ADE80) : const Color(0xFF9AB8FF),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 7),
      const Text(
        'AI 答辩',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _CameraSurface extends StatelessWidget {
  const _CameraSurface({required this.controller});

  final CameraController? controller;

  @override
  Widget build(BuildContext context) {
    final camera = controller;
    if (camera == null || !camera.value.isInitialized) {
      return const ColoredBox(
        color: Color(0xFF101216),
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
  Widget build(BuildContext context) => Text(
    '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
    style: const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w700,
      fontFeatures: [FontFeature.tabularFigures()],
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
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 230),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (loading)
              const SizedBox.square(
                dimension: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.signal,
                ),
              )
            else
              Icon(
                speaking ? Icons.graphic_eq_rounded : Icons.circle,
                size: speaking ? 18 : 7,
                color: AppColors.signal,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: '重新播放问题',
              onPressed: onReplay,
              icon: const Icon(Icons.volume_up_outlined, size: 21),
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
                  fontSize: 21,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 9)],
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
  const _ErrorBanner({
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;

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
          onPressed: onAction,
          child: Text(actionLabel, style: const TextStyle(color: Colors.white)),
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
        ? (active ? Colors.white : AppColors.signal)
        : const Color(0xA61B1F1C);
    final foreground = active ? AppColors.ink : Colors.white;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: Size.square(emphasized ? 70 : 54),
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: Colors.black26,
          disabledForegroundColor: Colors.white30,
          side: BorderSide(
            color: emphasized ? Colors.transparent : Colors.white24,
          ),
        ),
        iconSize: emphasized ? 31 : 25,
        icon: Icon(icon),
      ),
    );
  }
}
