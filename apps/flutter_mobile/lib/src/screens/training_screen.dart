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
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class TrainingScreen extends ConsumerStatefulWidget {
  const TrainingScreen({super.key, required this.projectId});
  final String projectId;

  @override
  ConsumerState<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends ConsumerState<TrainingScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  CameraController? _camera;
  Project? _project;
  RehearsalSession? _session;
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _initializing = true;
  bool _recording = false;
  bool _processing = false;
  bool _deadlineSignaled = false;
  String? _audioPath;
  String? _videoPath;
  String? _setupError;
  String? _processError;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final project = await ref
          .read(apiClientProvider)
          .getProject(widget.projectId);
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
    });
    try {
      if (!await _audioRecorder.hasPermission()) {
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
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: audioPath,
        );
      } catch (_) {
        await camera.stopVideoRecording();
        rethrow;
      }
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
    final next = _elapsedSeconds + 1;
    if (!_deadlineSignaled && next >= (_project?.durationSeconds ?? 300)) {
      _deadlineSignaled = true;
      HapticFeedback.heavyImpact();
    }
    setState(() => _elapsedSeconds = next);
  }

  Future<void> _stop() async {
    if (!_recording || _processing) return;
    _timer?.cancel();
    setState(() {
      _recording = false;
      _processing = true;
      _processError = null;
    });
    try {
      await _audioRecorder.stop();
      final captured = await _camera!.stopVideoRecording();
      final directory = await getApplicationDocumentsDirectory();
      final videoDirectory = Directory('${directory.path}/speechmirror/video');
      await videoDirectory.create(recursive: true);
      final destination = '${videoDirectory.path}/${_session!.id}.mp4';
      await File(captured.path).copy(destination);
      if (mounted) setState(() => _videoPath = destination);
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
    final audioPath = _audioPath;
    final session = _session;
    if (audioPath == null || session == null) return;
    setState(() {
      _processing = true;
      _processError = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final transcript = await api.uploadAudio(session.id, audioPath);
      await api.completeSession(
        session.id,
        _elapsedSeconds.clamp(1, 3600),
        transcript,
      );
      await api.analyzeSession(session.id);
      if (mounted) context.go('/reports/${session.id}');
    } catch (error) {
      if (mounted) {
        setState(() {
          _processError = '本地视频未上传，音频分析失败：$error';
          _processing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera?.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = _project;
    return Scaffold(
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
                PageIntro(
                  eyebrow: _recording
                      ? 'RECORDING / LOCAL ONLY'
                      : 'PRIVATE REHEARSAL',
                  title: project?.name ?? '模拟答辩',
                  description: '视频仅保存在本机；服务端只接收音频用于语音识别。',
                ),
                const SizedBox(height: 22),
                _CameraStage(
                  controller: _camera!,
                  recording: _recording,
                  overtime: _deadlineSignaled,
                ),
                const SizedBox(height: 18),
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
                if (_videoPath != null) ...[
                  Text(
                    '本地视频：$_videoPath',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_session != null && !_recording && _processError != null)
                  FilledButton.icon(
                    onPressed: _processing ? null : _submitForAnalysis,
                    icon: const Icon(Icons.sync),
                    label: const Text('重试音频分析'),
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
                      _processing ? '正在处理' : (_recording ? '结束并生成报告' : '开始录制'),
                    ),
                  ),
                const SizedBox(height: 20),
                const _PrivacyNote(),
              ],
            ),
    );
  }

  String _clock(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _CameraStage extends StatelessWidget {
  const _CameraStage({
    required this.controller,
    required this.recording,
    required this.overtime,
  });
  final CameraController controller;
  final bool recording;
  final bool overtime;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 3 / 4,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: AppColors.ink, child: CameraPreview(controller)),
          IgnorePointer(child: CustomPaint(painter: _GuidePainter())),
          Positioned(
            top: 14,
            left: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      recording ? Icons.circle : Icons.lock_outline,
                      size: 12,
                      color: recording ? AppColors.vermilion : Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      recording ? (overtime ? '已超时' : '录制中') : '视频不上传',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.32),
        width: size.width * 0.36,
        height: size.height * 0.25,
      ),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.73),
      Offset(size.width * 0.82, size.height * 0.73),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();
  @override
  Widget build(BuildContext context) => const Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(Icons.privacy_tip_outlined, size: 19, color: AppColors.jade),
      SizedBox(width: 10),
      Expanded(
        child: Text(
          '当前版本不上传原始视频。端侧视觉模型接入前，不生成视线或姿态分数。',
          style: TextStyle(color: AppColors.muted),
        ),
      ),
    ],
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
