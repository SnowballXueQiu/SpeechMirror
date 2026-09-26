import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  AudioRecorder? _audioRecorder;
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
    } catch (error) {
      if (mounted) {
        setState(() {
          _setupError = error.toString();
          _initializing = false;
        });
      }
    }
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
          _processError = '录制已保存在本机，但分析尚未完成：$error';
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
          _processError = '本地视频未上传，待恢复记录已保留：$error';
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    return PopScope(
      canPop: !_recording && !_processing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_recording ? '请先结束当前录制' : '正在保存训练记录，请稍候')),
        );
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('模拟答辩')),
        body: _initializing
            ? const Center(child: CircularProgressIndicator())
            : _setupError != null
            ? _SetupError(
                message: _setupError!,
                onRetry: () {
                  setState(() {
                    _initializing = true;
                    _setupError = null;
                  });
                  _initialize();
                },
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  const DefenseStageRail(activeStage: 0),
                  const SizedBox(height: 22),
                  PageIntro(
                    eyebrow: _recording
                        ? 'PRESENTING / LOCAL VIDEO'
                        : 'STAGE 01 / PRESENTATION',
                    title: project?.name ?? '模拟答辩',
                    description: '',
                  ),
                  const SizedBox(height: 22),
                  if (_pendingTraining != null)
                    _PendingTrainingStage(
                      training: _pendingTraining!,
                      status: _processing ? _processingLabel : null,
                    )
                  else
                    _CameraStage(controller: _camera!),
                  const SizedBox(height: 18),
                  if (_recording || _recentLevels.isNotEmpty) ...[
                    _LiveWaveform(levels: _recentLevels),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: _TimeBlock(
                          label: '当前',
                          value: _clock(_elapsedSeconds),
                          accent: _deadlineSignaled,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TimeBlock(
                          label: '目标',
                          value: _clock(project?.durationSeconds ?? 0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_processError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        border: Border.all(color: AppColors.vermilion),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _processError!,
                        style: const TextStyle(color: AppColors.vermilion),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_pendingTraining != null && !_recording)
                    FilledButton.icon(
                      onPressed: _processing ? null : _submitForAnalysis,
                      icon: const Icon(Icons.sync),
                      label: Text(
                        _processError == null ? '继续进入AI答辩' : '重试陈述分析',
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _processing
                          ? null
                          : (_recording ? _stop : _start),
                      icon: _processing
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _recording
                                  ? Icons.stop_circle_outlined
                                  : Icons.fiber_manual_record,
                            ),
                      label: Text(
                        _processing
                            ? _processingLabel
                            : (_recording ? '结束陈述，进入答辩' : '开始产品陈述'),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
      ),
    );
  }

  String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _PendingTrainingStage extends StatelessWidget {
  const _PendingTrainingStage({required this.training, this.status});

  final PendingTraining training;
  final String? status;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('pending-training-stage'),
    constraints: const BoxConstraints(minHeight: 280),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (status == null)
          const Icon(Icons.video_file_outlined, size: 48, color: Colors.white)
        else
          const SizedBox.square(
            dimension: 42,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white,
            ),
          ),
        const SizedBox(height: 16),
        Text(
          status ?? '陈述已保存在本机',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          status == null
              ? '已保留 ${training.actualSeconds} 秒视频与音频，可继续进入AI答辩。'
              : '正在处理 ${training.actualSeconds} 秒陈述，请保持应用在前台。',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
      ],
    ),
  );
}

class _CameraStage extends StatelessWidget {
  const _CameraStage({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 3 / 4,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: AppColors.ink, child: CameraPreview(controller)),
        ],
      ),
    ),
  );
}

class _LiveWaveform extends StatelessWidget {
  const _LiveWaveform({required this.levels});

  final List<double> levels;

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.white,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(6),
    ),
    child: CustomPaint(
      painter: _WaveformPainter(levels),
      child: const SizedBox.expand(),
    ),
  );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.levels);

  final List<double> levels;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height / 2;
    final centerPaint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      centerPaint,
    );
    if (levels.isEmpty) return;
    final barWidth = size.width / levels.length;
    final paint = Paint()
      ..color = AppColors.jade
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (barWidth * 0.42).clamp(2.0, 5.0);
    for (var index = 0; index < levels.length; index++) {
      final height = (4 + levels[index] * (size.height - 8)).clamp(
        4.0,
        size.height,
      );
      final x = barWidth * index + barWidth / 2;
      canvas.drawLine(
        Offset(x, baseline - height / 2),
        Offset(x, baseline + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}

class _TimeBlock extends StatelessWidget {
  const _TimeBlock({
    required this.label,
    required this.value,
    this.accent = false,
  });
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.white,
      border: Border.all(color: accent ? AppColors.vermilion : AppColors.line),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: accent ? AppColors.vermilion : AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _SetupError extends StatelessWidget {
  const _SetupError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.no_photography_outlined,
            size: 42,
            color: AppColors.vermilion,
          ),
          const SizedBox(height: 14),
          const Text(
            '无法启动训练摄像头',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重新检查'),
          ),
        ],
      ),
    ),
  );
}
