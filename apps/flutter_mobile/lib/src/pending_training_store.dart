import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class PendingTraining {
  const PendingTraining({
    required this.projectId,
    required this.sessionId,
    required this.audioPath,
    required this.videoPath,
    required this.actualSeconds,
    required this.savedAt,
    this.transcript,
  });

  final String projectId;
  final String sessionId;
  final String audioPath;
  final String videoPath;
  final int actualSeconds;
  final DateTime savedAt;
  final String? transcript;

  PendingTraining withTranscript(String value) => PendingTraining(
    projectId: projectId,
    sessionId: sessionId,
    audioPath: audioPath,
    videoPath: videoPath,
    actualSeconds: actualSeconds,
    savedAt: savedAt,
    transcript: value,
  );

  Map<String, dynamic> toJson() => {
    'project_id': projectId,
    'session_id': sessionId,
    'audio_path': audioPath,
    'video_path': videoPath,
    'actual_seconds': actualSeconds,
    'saved_at': savedAt.toUtc().toIso8601String(),
    'transcript': transcript,
  };

  factory PendingTraining.fromJson(Map<String, dynamic> json) {
    final projectId = json['project_id'] as String?;
    final sessionId = json['session_id'] as String?;
    final audioPath = json['audio_path'] as String?;
    final videoPath = json['video_path'] as String?;
    final actualSeconds = json['actual_seconds'] as int?;
    final savedAt = DateTime.tryParse(json['saved_at'] as String? ?? '');
    if (projectId == null ||
        sessionId == null ||
        audioPath == null ||
        videoPath == null ||
        actualSeconds == null ||
        actualSeconds < 1 ||
        savedAt == null) {
      throw const FormatException('待恢复训练记录格式无效');
    }
    return PendingTraining(
      projectId: projectId,
      sessionId: sessionId,
      audioPath: audioPath,
      videoPath: videoPath,
      actualSeconds: actualSeconds,
      savedAt: savedAt,
      transcript: json['transcript'] as String?,
    );
  }
}

abstract class PendingTrainingStore {
  Future<PendingTraining?> load(String projectId);
  Future<bool> mediaExists(PendingTraining training);
  Future<void> save(PendingTraining training);
  Future<void> delete(String projectId);
}

class FilePendingTrainingStore implements PendingTrainingStore {
  FilePendingTrainingStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider =
          directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directoryProvider;

  @override
  Future<PendingTraining?> load(String projectId) async {
    final file = await _file(projectId);
    if (!await file.exists()) return null;
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('待恢复训练记录格式无效');
    }
    final training = PendingTraining.fromJson(value);
    if (training.projectId != projectId) {
      throw const FormatException('待恢复训练记录与项目不匹配');
    }
    return training;
  }

  @override
  Future<bool> mediaExists(PendingTraining training) async =>
      await File(training.audioPath).exists() &&
      await File(training.videoPath).exists();

  @override
  Future<void> save(PendingTraining training) async {
    final file = await _file(training.projectId);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(training.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<void> delete(String projectId) async {
    final file = await _file(projectId);
    if (await file.exists()) await file.delete();
  }

  Future<File> _file(String projectId) async {
    final root = await _directoryProvider();
    final safeProjectId = projectId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(
      '${root.path}/speechmirror/pending-training/$safeProjectId.json',
    );
  }
}
