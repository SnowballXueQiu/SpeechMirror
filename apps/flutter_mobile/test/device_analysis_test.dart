import 'package:flutter_test/flutter_test.dart';
import 'package:speechmirror/src/device_analysis.dart';

void main() {
  test('normalizes recorder decibels into a bounded audio level', () {
    expect(normalizeDecibels(double.negativeInfinity), 0);
    expect(normalizeDecibels(-60), 0);
    expect(normalizeDecibels(-30), 0.5);
    expect(normalizeDecibels(0), 1);
    expect(normalizeDecibels(12), 1);
  });

  test('merges every audio sample with the closest visual sample', () {
    final result = mergeDeviceMetrics(
      const [
        AudioLevelSample(timestampMs: 100, level: 0.2),
        AudioLevelSample(timestampMs: 900, level: 0.8),
      ],
      const [
        VisualSample(
          timestampMs: 0,
          faceDetected: true,
          gazeCentered: 0.9,
          postureScore: 0.7,
        ),
        VisualSample(
          timestampMs: 1000,
          faceDetected: false,
          gazeCentered: 1.2,
          postureScore: -0.1,
        ),
      ],
    );

    expect(result, hasLength(2));
    expect(result.first['face_detected'], isTrue);
    expect(result.first['audio_level'], 0.2);
    expect(result.last['face_detected'], isFalse);
    expect(result.last['gaze_centered'], 1.0);
    expect(result.last['posture_score'], 0.0);
  });

  test('does not upload audio-only metrics without visual observations', () {
    expect(
      mergeDeviceMetrics(const [
        AudioLevelSample(timestampMs: 0, level: 0.5),
      ], const []),
      isEmpty,
    );
  });
}
