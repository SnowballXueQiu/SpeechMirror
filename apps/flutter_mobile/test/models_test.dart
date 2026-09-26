import 'package:flutter_test/flutter_test.dart';
import 'package:speechmirror/src/models.dart';

void main() {
  test('parses the session binding on jury questions', () {
    final question = JuryQuestion.fromJson(const {
      'id': 'question-1',
      'session_id': 'session-1',
      'category': '技术',
      'question': '如何实现端云协同？',
      'evidence': <dynamic>[],
    });

    expect(question.sessionId, 'session-1');
  });

  test('parses an evidence-linked report envelope', () {
    final report = RehearsalReport.fromJson({
      'report': {
        'session_id': 'session-1',
        'overall_score': 86,
        'actual_seconds': 300,
        'character_count': 900,
        'characters_per_minute': 180.0,
        'filler_counts': {'然后': 2},
        'long_pause_count': null,
        'audio_waveform': [
          {'timestamp_ms': 250, 'level': 0.42},
          {'timestamp_ms': 500, 'level': 0.71},
        ],
        'content': {
          'score': 82,
          'summary': '覆盖了技术路线',
          'evidence': [
            {'chunk_id': 'chunk-1', 'quote': '采用端云协同架构'},
          ],
        },
        'delivery': {'score': 80, 'summary': '表达稳定'},
        'timing': {'score': 100, 'summary': '时长准确'},
        'visual': {'score': null, 'summary': '未采集'},
        'qa': {'score': null, 'summary': '未完成'},
        'suggestions': ['补充测试数据'],
        'timeline': <Map<String, dynamic>>[],
        'model_confidence': 0.8,
      },
    });

    expect(report.sessionId, 'session-1');
    expect(report.overallScore, 86);
    expect(report.audioWaveform.length, 2);
    expect(report.audioWaveform.last.level, 0.71);
    expect(report.fillerCounts['然后'], 2);
    expect(report.longPauseCount, isNull);
    expect(report.content.evidence.single.chunkId, 'chunk-1');
    expect(report.visual.score, isNull);
    expect(report.qa.score, isNull);
  });

  test('parses sessions and typed trend points', () {
    final session = RehearsalSession.fromJson({
      'id': 'session-1',
      'project_id': 'project-1',
      'title': '第1次训练',
      'status': 'completed',
      'target_seconds': 300,
      'actual_seconds': 318,
      'transcript': '答辩转写',
      'created_at': '2026-09-25T02:30:00Z',
      'completed_at': '2026-09-25T02:36:00Z',
    });
    final trends = TrainingTrends.fromJson({
      'project_id': 'project-1',
      'points': [
        {
          'session_id': 'session-1',
          'created_at': '2026-09-25T02:36:01Z',
          'target_seconds': 300,
          'actual_seconds': 318,
          'duration_deviation_seconds': 18,
          'characters_per_minute': 178.5,
          'filler_count': 3,
          'filler_per_minute': 0.566,
          'delivery_score': 81,
          'timing_score': 92,
          'visual_score': null,
          'content_score': 84,
          'qa_score': null,
        },
      ],
    });

    expect(session.createdAt, DateTime.utc(2026, 9, 25, 2, 30));
    expect(session.completedAt, isNotNull);
    expect(trends.projectId, 'project-1');
    expect(trends.points.single.durationDeviationSeconds, 18);
    expect(trends.points.single.fillerPerMinute, closeTo(0.566, 0.0001));
    expect(trends.points.single.qaScore, isNull);
  });
}
