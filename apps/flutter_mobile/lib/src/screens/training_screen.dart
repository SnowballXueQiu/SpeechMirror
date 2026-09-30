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
import '../device_analysis.dart';
import '../models.dart';
import '../pending_training_store.dart';
import '../theme.dart';
import '../widgets.dart';

final pendingTrainingStoreProvider = Provider<PendingTrainingStore>(
  (ref) => FilePendingTrainingStore(),
);

class TrainingScreen extends ConsumerStatefulWidget {
  const TrainingScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends ConsumerState<TrainingScreen> {
  static const _openingLine = '好的，请开始介绍你的项目。我会先完整听你介绍，介绍结束后正式开始答辩。';

  AudioRecorder? _audioRecorder;
  final FlutterTts _tts = FlutterTts();
  CameraController? _camera;
  Project? _project;
  RehearsalSession? _session;
  PendingTraining? _pendingTraining;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  final Stopwatch _recordingClock = Stopwatch();
  final List<AudioLevelSample> _audioLevels = [];
  final List<double> _recentLevels = [];
  int _elapsedSeconds = 0;
  bool _initializing = true;
  bool _recording = false;
  bool _processing = false;
  bool _greeting = false;
  bool _deadlineSignaled = false;
  String? _audioPath;
  String? _setupError;
  String? _processError;
  String _processingLabel = '正在准备';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final pendingStore = ref.read(pendingTrainingStoreProvider);
      final pending = await pendingStore.load(widget.projectId);
      final project = await ref
          .read(apiClientProvider)
          .getProject(widget.projectId);
      if (pending != null) {
        if (!await pendingStore.mediaExists(pending)) {
          throw StateError('待恢复训练记录引用的本地音视频不完整，请保留文件并重新检查。');
        }
        if (!mounted) return;
        setState(() {
          _project = project;
          _session = RehearsalSession(
            id: pending.sessionId,
            projectId: pending.projectId,
            title: '待恢复训练',
            status: 'pending_analysis',
            targetSeconds: project.durationSeconds,
            actualSeconds: pending.actualSeconds,
            transcript: pending.transcript,
          );
          _pendingTraining = pending;
          _audioPath = pending.audioPath;
          _elapsedSeconds = pending.actualSeconds;
          _initializing = false;
        });
        return;
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('cameraUnavailable', '未检测到可用摄像头');
      }
      final selected =
          cameras
              .where((item) => item.lensDirection == CameraLensDirection.front)
              .firstOrNull ??
          cameras.first;
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
      setState(() {
        _project = project;
        _camera = controller;
        _initializing = false;
      });
      unawaited(_greetAndStart());
    } catch (error) {
      if (mounted) {
        setState(() {
          _setupError = error.toString();
          _initializing = false;
        });
      }
    }
  }

  Future<void> _greetAndStart() async {
    if (_recording || _processing || _greeting || _pendingTraining != null) {
      return;
    }
    setState(() => _greeting = true);
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(0.94);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
      await _tts.speak(_openingLine);
    } catch (_) {
      // Recording remains available even when the simulator has no TTS voice.
    } finally {
      if (mounted) setState(() => _greeting = false);
    }
    if (mounted) await _start();
  }

  Future<void> _start() async {
    final camera = _camera;
    final project = _project;
    if (camera == null || project == null) return;
    setState(() {
      _processError = null;
      _processing = true;
      _processingLabel = '正在创建训练记录';
    });
    try {
      final audioRecorder = _audioRecorder ??= AudioRecorder();
      if (!await audioRecorder.hasPermission()) {
        throw StateError('需要麦克风权限才能生成真实转写和训练报告');
      }
      final session = await ref
          .read(apiClientProvider)
          .createSession(project.id, project.durationSeconds, null);
      final directory = await getApplicationDocumentsDirectory();
      final audioDirectory = Directory('${directory.path}/speechmirror/audio');
      await audioDirectory.create(recursive: true);
      final audioPath = '${audioDirectory.path}/${session.id}.m4a';
      await camera.startVideoRecording();
      try {
        await audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: audioPath,
        );
      } catch (_) {
        await camera.stopVideoRecording();
        rethrow;
      }
      _audioLevels.clear();
      _recentLevels.clear();
      _recordingClock
        ..reset()
        ..start();
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 250))
          .listen(_collectAmplitude);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      if (mounted) {
        setState(() {
          _session = session;
          _audioPath = audioPath;
          _recording = true;
          _processing = false;
          _elapsedSeconds = 0;
          _deadlineSignaled = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _processError = error.toString();
          _processing = false;
        });
      }
    }
  }

  void _tick() {
    if (!mounted || !_recording) return;
    final next = _recordingClock.elapsed.inSeconds;
    if (!_deadlineSignaled && next >= (_project?.durationSeconds ?? 300)) {
      _deadlineSignaled = true;
      HapticFeedback.heavyImpact();
    }
    setState(() => _elapsedSeconds = next);
  }

  void _collectAmplitude(Amplitude amplitude) {
    if (!_recordingClock.isRunning) return;
    final level = normalizeDecibels(amplitude.current);
    _audioLevels.add(
      AudioLevelSample(
        timestampMs: _recordingClock.elapsedMilliseconds,
        level: level,
      ),
    );
    if (!mounted) return;
    setState(() {
      _recentLevels.add(level);
      if (_recentLevels.length > 42) _recentLevels.removeAt(0);
    });
  }

  Future<void> _stop() async {
    if (!_recording || _processing) return;
    _timer?.cancel();
    _recordingClock.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    setState(() {
      _recording = false;
      _processing = true;
      _processingLabel = '正在保存陈述';
      _processError = null;
    });
    try {
      final stoppedAudioPath = await _audioRecorder!.stop();
      final captured = await _camera!.stopVideoRecording();
      final directory = await getApplicationDocumentsDirectory();
      final videoDirectory = Directory('${directory.path}/speechmirror/video');
      await videoDirectory.create(recursive: true);
      final destination = '${videoDirectory.path}/${_session!.id}.mp4';
      await File(captured.path).copy(destination);
      final pending = PendingTraining(
        projectId: widget.projectId,
        sessionId: _session!.id,
        audioPath: stoppedAudioPath ?? _audioPath!,
        videoPath: destination,
        actualSeconds: _elapsedSeconds.clamp(1, 3600),
        savedAt: DateTime.now(),
        audioLevels: List.unmodifiable(_audioLevels),
      );
      await ref.read(pendingTrainingStoreProvider).save(pending);
      if (mounted) {
        setState(() {
          _pendingTraining = pending;
          _audioPath = pending.audioPath;
        });
      }
      await _submitForAnalysis();
    } catch (error) {
      if (mounted) {
        setState(() {
          _processError = '陈述已保存，分析尚未完成：$error';
          _processing = false;
        });
      }
    }
  }

  Future<void> _submitForAnalysis() async {
    var pending = _pendingTraining;
    if (pending == null) return;
    setState(() {
      _processing = true;
      _processError = null;
      _processingLabel = '正在识别陈述内容';
    });
    try {
      if (!await ref.read(pendingTrainingStoreProvider).mediaExists(pending)) {
        throw StateError('本地音视频文件不完整，已停止提交以避免丢失恢复线索');
      }
      final api = ref.read(apiClientProvider);
      var transcript = pending.transcript;
      if (transcript == null || transcript.trim().isEmpty) {
        transcript = await api.uploadAudio(
          pending.sessionId,
          pending.audioPath,
        );
        pending = pending.withTranscript(transcript);
        await ref.read(pendingTrainingStoreProvider).save(pending);
        if (mounted) setState(() => _pendingTraining = pending);
      }
      if (!pending.metricsUploaded) {
        if (mounted) setState(() => _processingLabel = '正在分析画面与停顿');
        final visual = await const DeviceAnalysis().analyzeVideo(
          pending.videoPath,
          pending.actualSeconds * 1000,
        );
        final metrics = mergeDeviceMetrics(pending.audioLevels, visual);
        if (metrics.isNotEmpty) {
          await api.uploadMetrics(pending.sessionId, metrics);
          pending = pending.withMetricsUploaded();
          await ref.read(pendingTrainingStoreProvider).save(pending);
          if (mounted) setState(() => _pendingTraining = pending);
        }
      }
      if (mounted) setState(() => _processingLabel = '正在准备AI评委');
      await api.completeSession(
        pending.sessionId,
        pending.actualSeconds,
        transcript,
      );
      await ref.read(pendingTrainingStoreProvider).delete(widget.projectId);
      final audio = File(pending.audioPath);
      if (await audio.exists()) await audio.delete();
      await _releaseCameraForTransition();
      if (mounted) {
        setState(() => _pendingTraining = null);
        context.go(
          '/projects/${widget.projectId}/jury?session=${pending.sessionId}&autostart=1',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _processError = '陈述已保存，分析尚未完成：$error';
          _processing = false;
        });
      }
    }
  }

  Future<void> _confirmRerecord() async {
    final pending = _pendingTraining;
    if (pending == null || _processing) return;
    final confirmed = await showAppConfirmation(
      context,
      title: '重新录制项目陈述？',
      message: '当前未提交成功的本地录音和录像将被删除，然后重新打开摄像头。',
      confirmLabel: '重新录制',
      icon: Icons.replay_rounded,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _processing = true;
      _processingLabel = '正在重新准备';
      _processError = null;
    });
    try {
      await ref.read(pendingTrainingStoreProvider).delete(widget.projectId);
      for (final path in [pending.audioPath, pending.videoPath]) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
      await _camera?.dispose();
      _camera = null;
      await _audioRecorder?.dispose();
      _audioRecorder = null;
      if (!mounted) return;
      setState(() {
        _pendingTraining = null;
        _session = null;
        _audioPath = null;
        _elapsedSeconds = 0;
        _processing = false;
        _initializing = true;
      });
      await _initialize();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _processError = '重新录制准备失败：$error';
        _processing = false;
        _initializing = false;
      });
    }
  }

  Future<void> _releaseCameraForTransition() async {
    final camera = _camera;
    _camera = null;
    if (camera != null) await camera.dispose();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordingClock.stop();
    _amplitudeSubscription?.cancel();
    _camera?.dispose();
    _audioRecorder?.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_recording && !_processing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_recording ? '请先结束当前录制' : '正在保存训练记录，请稍候')),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _initializing
            ? const ColoredBox(
                color: Color(0xFF101216),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            : _setupError != null
            ? _DarkSetupError(
                message: _setupError!,
                onRetry: () {
                  setState(() {
                    _initializing = true;
                    _setupError = null;
                  });
                  _initialize();
                },
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  _TrainingCameraSurface(controller: _camera),
                  const IgnorePointer(child: _VideoScrim()),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: '退出训练',
                                style: IconButton.styleFrom(
                                  fixedSize: const Size.square(42),
                                  backgroundColor: const Color(0x66000000),
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.black26,
                                ),
                                onPressed: _recording || _processing
                                    ? null
                                    : () => context.pop(),
                                icon: const Icon(Icons.close),
                              ),
                              const SizedBox(width: 10),
                              const _StageBadge(),
                              const Spacer(),
                              _PresentationClock(seconds: _elapsedSeconds),
                            ],
                          ),
                          const Spacer(),
                          if (_processError != null) ...[
                            _TrainingErrorBanner(
                              message: _processError!,
                              onRetry: _pendingTraining != null
                                  ? _submitForAnalysis
                                  : _start,
                              onRerecord: _pendingTraining != null
                                  ? _confirmRerecord
                                  : null,
                            ),
                            const SizedBox(height: 10),
                          ],
                          _TrainingStatusPanel(
                            title: _greeting
                                ? 'AI评委'
                                : _processing
                                ? '正在准备'
                                : _recording
                                ? '项目陈述进行中'
                                : '模拟答辩',
                            message: _greeting
                                ? _openingLine
                                : _processing
                                ? _processingLabel
                                : _recording
                                ? '面向镜头完成项目介绍'
                                : '准备好后开始',
                            busy: _greeting || _processing,
                          ),
                          const SizedBox(height: 22),
                          _PrimaryCallAction(
                            busy: _greeting || _processing,
                            active: _recording,
                            onPressed: _greeting || _processing
                                ? null
                                : _pendingTraining != null
                                ? _submitForAnalysis
                                : _recording
                                ? _stop
                                : _start,
                            label: _greeting
                                ? '评委正在说明'
                                : _processing
                                ? _processingLabel
                                : _pendingTraining != null
                                ? '继续进入答辩'
                                : _recording
                                ? '结束介绍'
                                : '开始介绍',
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

class _TrainingCameraSurface extends StatelessWidget {
  const _TrainingCameraSurface({required this.controller});

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

class _VideoScrim extends StatelessWidget {
  const _VideoScrim();

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
          Color(0xD9000000),
        ],
        stops: [0, 0.18, 0.54, 1],
      ),
    ),
  );
}

class _StageBadge extends StatelessWidget {
  const _StageBadge();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFFFF5B4D),
          shape: BoxShape.circle,
        ),
        child: SizedBox.square(dimension: 7),
      ),
      SizedBox(width: 7),
      Text(
        '项目陈述',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _PresentationClock extends StatelessWidget {
  const _PresentationClock({required this.seconds});

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

class _TrainingStatusPanel extends StatelessWidget {
  const _TrainingStatusPanel({
    required this.title,
    required this.message,
    required this.busy,
  });

  final String title;
  final String message;
  final bool busy;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            const SizedBox.square(
              dimension: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.signal,
              ),
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.signal,
                shape: BoxShape.circle,
              ),
              child: SizedBox.square(dimension: 7),
            ),
          const SizedBox(width: 7),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: 9),
      Text(
        message,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          height: 1.42,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
        ),
      ),
    ],
  );
}

class _PrimaryCallAction extends StatelessWidget {
  const _PrimaryCallAction({
    required this.busy,
    required this.active,
    required this.onPressed,
    required this.label,
  });

  final bool busy;
  final bool active;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.filled(
        tooltip: label,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(70),
          backgroundColor: active ? Colors.white : AppColors.signal,
          foregroundColor: AppColors.ink,
          disabledBackgroundColor: Colors.white24,
          disabledForegroundColor: Colors.white60,
        ),
        iconSize: 29,
        icon: busy
            ? const SizedBox.square(
                dimension: 21,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Icon(active ? Icons.arrow_forward_rounded : Icons.mic_rounded),
      ),
      const SizedBox(height: 9),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _TrainingErrorBanner extends StatelessWidget {
  const _TrainingErrorBanner({
    required this.message,
    required this.onRetry,
    this.onRerecord,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onRerecord;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    decoration: BoxDecoration(
      color: const Color(0xE6451F1A),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: onRetry,
              child: const Text('重试', style: TextStyle(color: Colors.white)),
            ),
            if (onRerecord != null) ...[
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onRerecord,
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('重新录制'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

class _DarkSetupError extends StatelessWidget {
  const _DarkSetupError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF101216),
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              size: 42,
              color: Colors.white70,
            ),
            const SizedBox(height: 14),
            const Text(
              '无法启动训练摄像头',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
              ),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重新检查'),
            ),
          ],
        ),
      ),
    ),
  );
}
