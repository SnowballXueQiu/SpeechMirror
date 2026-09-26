import 'dart:io';

import 'package:flutter/services.dart';

class AudioLevelSample {
  const AudioLevelSample({required this.timestampMs, required this.level});

  final int timestampMs;
  final double level;

  Map<String, dynamic> toJson() => {
    'timestamp_ms': timestampMs,
    'level': level,
  };

  factory AudioLevelSample.fromJson(Map<String, dynamic> json) =>
      AudioLevelSample(
        timestampMs: (json['timestamp_ms'] as num?)?.toInt() ?? 0,
        level: (json['level'] as num?)?.toDouble() ?? 0,
      );
}

class VisualSample {
  const VisualSample({
    required this.timestampMs,
    required this.faceDetected,
    required this.gazeCentered,
    required this.postureScore,
  });

  final int timestampMs;
  final bool faceDetected;
  final double gazeCentered;
  final double postureScore;

  factory VisualSample.fromJson(Map<Object?, Object?> json) => VisualSample(
    timestampMs: (json['timestamp_ms'] as num?)?.toInt() ?? 0,
    faceDetected: json['face_detected'] == true,
    gazeCentered: (json['gaze_centered'] as num?)?.toDouble() ?? 0,
    postureScore: (json['posture_score'] as num?)?.toDouble() ?? 0,
  );
}

class DeviceAnalysis {
  const DeviceAnalysis();

  static const _channel = MethodChannel('speechmirror/device_analysis');

  Future<List<VisualSample>> analyzeVideo(String path, int durationMs) async {
    if (!Platform.isIOS) return const [];
    try {
      final result = await _channel.invokeListMethod<Object?>('analyzeVideo', {
        'path': path,
        'duration_ms': durationMs,
      });
      return (result ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map(VisualSample.fromJson)
          .toList()
        ..sort((left, right) => left.timestampMs.compareTo(right.timestampMs));
    } on MissingPluginException {
      return const [];
    }
  }
}

double normalizeDecibels(double decibels) {
  if (!decibels.isFinite) return 0;
  return ((decibels + 60) / 60).clamp(0.0, 1.0);
}

List<Map<String, dynamic>> mergeDeviceMetrics(
  List<AudioLevelSample> audio,
  List<VisualSample> visual,
) {
  if (visual.isEmpty) return const [];
  final levels = audio.isEmpty
      ? visual
            .map(
              (sample) =>
                  AudioLevelSample(timestampMs: sample.timestampMs, level: 0.5),
            )
            .toList()
      : audio;
  var visualIndex = 0;
  return levels.map((sample) {
    while (visualIndex + 1 < visual.length &&
        (visual[visualIndex + 1].timestampMs - sample.timestampMs).abs() <
            (visual[visualIndex].timestampMs - sample.timestampMs).abs()) {
      visualIndex += 1;
    }
    final frame = visual[visualIndex];
    return <String, dynamic>{
      'timestamp_ms': sample.timestampMs,
      'face_detected': frame.faceDetected,
      'gaze_centered': frame.gazeCentered.clamp(0.0, 1.0),
      'posture_score': frame.postureScore.clamp(0.0, 1.0),
      'audio_level': sample.level.clamp(0.0, 1.0),
    };
  }).toList();
}
