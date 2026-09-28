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
                color: Color(0xFF151B19),
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
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton.filled(
                                tooltip: '退出训练',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _recording || _processing
                                    ? null
                                    : () => context.pop(),
                                icon: const Icon(Icons.close),
                              ),
                              const Spacer(),
                              _PresentationClock(seconds: _elapsedSeconds),
                              const Spacer(),
                              const SizedBox(width: 48),
                            ],
                          ),
                          const Spacer(),
                          if (_processError != null) ...[
                            _TrainingErrorBanner(
                              message: _processError!,
                              onRetry: _pendingTraining != null
                                  ? _submitForAnalysis
                                  : _start,
                            ),
                            const SizedBox(height: 10),
                          ],
                          _TrainingStatusPanel(
                            title: _greeting
                                ? 'AI评委'
                                : _processing
                                ? '正在准备'
                                : _recording
                                ? '项目介绍'
                                : '模拟答辩',
                            message: _greeting
                                ? _openingLine
                                : _processing
                                ? _processingLabel
                                : _recording
                                ? '请完整介绍你的项目，介绍结束后进入答辩。'
                                : '准备好后开始介绍项目。',
                            busy: _greeting || _processing,
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(56),
                                backgroundColor: _recording
                                    ? const Color(0xFFF1F3EF)
                                    : AppColors.jade,
                                foregroundColor: _recording
                                    ? AppColors.ink
                                    : Colors.white,
                              ),
                              onPressed: _greeting || _processing
                                  ? null
                                  : _pendingTraining != null
                                  ? _submitForAnalysis
                                  : _recording
                                  ? _stop
                                  : _start,
                              icon: _greeting || _processing
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      _recording
                                          ? Icons.arrow_forward
                                          : Icons.fiber_manual_record,
                                    ),
                              label: Text(
                                _greeting
                                    ? '评委正在说明流程'
                                    : _processing
                                    ? _processingLabel
                                    : _pendingTraining != null
                                    ? '继续进入答辩'
                                    : _recording
                                    ? '介绍完毕，开始答辩'
                                    : '开始项目介绍',
                              ),
                            ),
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

class _PresentationClock extends StatelessWidget {
  const _PresentationClock({required this.seconds});

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
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xD91A211E),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (busy)
              const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF8AD8C1),
                ),
              )
            else
              const Icon(
                Icons.videocam_outlined,
                size: 17,
                color: Color(0xFF8AD8C1),
              ),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFFB6C5BF),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _TrainingErrorBanner extends StatelessWidget {
  const _TrainingErrorBanner({required this.message, required this.onRetry});

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

class _DarkSetupError extends StatelessWidget {
  const _DarkSetupError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF151B19),
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
