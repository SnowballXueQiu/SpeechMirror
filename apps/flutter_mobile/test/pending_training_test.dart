import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:speechmirror/src/device_analysis.dart';
import 'package:speechmirror/src/pending_training_store.dart';

void main() {
  test('persists, reloads and removes a pending training manifest', () async {
    final directory = await Directory.systemTemp.createTemp(
      'speechmirror-pending-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FilePendingTrainingStore(
      directoryProvider: () async => directory,
    );
    final pending = PendingTraining(
      projectId: 'project-1',
      sessionId: 'session-1',
      audioPath: '${directory.path}/audio.m4a',
      videoPath: '${directory.path}/video.mp4',
      actualSeconds: 42,
      savedAt: DateTime.utc(2026, 9, 25, 12),
      audioLevels: const [
        AudioLevelSample(timestampMs: 250, level: 0.4),
        AudioLevelSample(timestampMs: 500, level: 0.7),
      ],
    );

    await store.save(pending);
    final restored = await store.load('project-1');

    expect(restored?.sessionId, 'session-1');
    expect(restored?.actualSeconds, 42);
    expect(restored?.transcript, isNull);
    expect(restored?.audioLevels.length, 2);
    expect(restored?.audioLevels.last.level, 0.7);
    expect(restored?.metricsUploaded, isFalse);

    await store.save(pending.withTranscript('真实转写'));
    expect((await store.load('project-1'))?.transcript, '真实转写');

    await store.save(pending.withMetricsUploaded());
    expect((await store.load('project-1'))?.metricsUploaded, isTrue);

    await store.delete('project-1');
    expect(await store.load('project-1'), isNull);
  });
}
