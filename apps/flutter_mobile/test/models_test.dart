import 'package:flutter_test/flutter_test.dart';
import 'package:speechmirror/src/models.dart';

void main() {
  test('parses an evidence-linked report envelope', () {
    final report = RehearsalReport.fromJson({
      'report': {
        'session_id': 'session-1',
        'actual_seconds': 300,
        'character_count': 900,
        'characters_per_minute': 180.0,
        'filler_counts': {'然后': 2},
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
    expect(report.fillerCounts['然后'], 2);
    expect(report.content.evidence.single.chunkId, 'chunk-1');
    expect(report.visual.score, isNull);
    expect(report.qa.score, isNull);
  });
}
