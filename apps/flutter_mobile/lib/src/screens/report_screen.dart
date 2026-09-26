import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  late Future<RehearsalReport> _report;

  @override
  void initState() {
    super.initState();
    _report = ref.read(apiClientProvider).getReport(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('训练报告'),
      actions: [
        IconButton(
          tooltip: '返回项目列表',
          onPressed: () => context.go('/projects'),
          icon: const Icon(Icons.home_outlined),
        ),
      ],
    ),
    body: FutureBuilder<RehearsalReport>(
      future: _report,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReportError(error: snapshot.error!, onRetry: _reload);
        }
        final report = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            const DefenseStageRail(activeStage: 2),
            const SizedBox(height: 22),
            const PageIntro(
              eyebrow: 'STAGE 03 / REVIEW',
              title: '综合答辩报告',
              description: '结合产品陈述、端侧画面指标和AI评委问答定位本次最值得改进的问题。',
            ),
            const SizedBox(height: 24),
            _OverallScore(score: report.overallScore),
            const SizedBox(height: 12),
            _SummaryBand(report: report),
            if (report.audioWaveform.isNotEmpty) ...[
              const SizedBox(height: 26),
              const SectionLabel('声音波形与停顿'),
              const SizedBox(height: 12),
              _AudioWaveform(points: report.audioWaveform),
            ],
            const SizedBox(height: 28),
            const SectionLabel('五维分析'),
            const SizedBox(height: 8),
            ScoreRow(
              label: '内容',
              score: report.content.score,
              summary: report.content.summary,
            ),
            ScoreRow(
              label: '表达',
              score: report.delivery.score,
              summary: report.delivery.summary,
            ),
            ScoreRow(
              label: '时间',
              score: report.timing.score,
              summary: report.timing.summary,
            ),
            ScoreRow(
              label: '视觉',
              score: report.visual.score,
              summary: report.visual.summary,
            ),
            ScoreRow(
              label: '问答',
              score: report.qa.score,
              summary: report.qa.summary,
            ),
            const SizedBox(height: 26),
            const SectionLabel('材料依据'),
            const SizedBox(height: 12),
            if (report.content.evidence.isEmpty && report.qa.evidence.isEmpty)
              const Text(
                '本次内容评价未返回可展示的材料片段。',
                style: TextStyle(color: AppColors.muted),
              )
            else ...[
              if (report.content.evidence.isNotEmpty)
                const _EvidenceGroupLabel('陈述评价依据'),
              for (final item in report.content.evidence)
                _EvidenceQuote(item: item),
              if (report.qa.evidence.isNotEmpty) ...[
                const SizedBox(height: 8),
                const _EvidenceGroupLabel('问答评价依据'),
                for (final item in report.qa.evidence)
                  _EvidenceQuote(item: item),
              ],
            ],
            const SizedBox(height: 26),
            const SectionLabel('下一次练习'),
            const SizedBox(height: 12),
            if (report.suggestions.isEmpty)
              const Text('暂无额外建议。', style: TextStyle(color: AppColors.muted))
            else
              for (var i = 0; i < report.suggestions.length; i++)
                _Suggestion(index: i + 1, text: report.suggestions[i]),
            if (report.timeline.isNotEmpty) ...[
              const SizedBox(height: 26),
              const SectionLabel('时间定位'),
              const SizedBox(height: 12),
              for (final item in report.timeline) _TimelineRow(item: item),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => context.go('/projects'),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回项目'),
            ),
          ],
        );
      },
    ),
  );

  void _reload() {
    final report = ref.read(apiClientProvider).getReport(widget.sessionId);
    setState(() {
      _report = report;
    });
  }
}

class _OverallScore extends StatelessWidget {
  const _OverallScore({required this.score});

  final int? score;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    decoration: BoxDecoration(
      color: AppColors.white,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.workspace_premium_outlined,
          color: AppColors.vermilion,
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            '本次综合表现',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          score == null ? '—' : '$score',
          style: const TextStyle(
            fontFamily: 'Songti SC',
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: AppColors.vermilion,
          ),
        ),
        if (score != null)
          const Text(' / 100', style: TextStyle(color: AppColors.muted)),
      ],
    ),
  );
}

class _EvidenceGroupLabel extends StatelessWidget {
  const _EvidenceGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({required this.report});
  final RehearsalReport report;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      children: [
        Expanded(
          child: _Metric(
            label: '语速',
            value: '${report.charactersPerMinute.round()}',
            unit: '字/分',
          ),
        ),
        Container(width: 1, height: 44, color: Colors.white24),
        Expanded(
          child: _Metric(
            label: '时长',
            value: '${report.actualSeconds}',
            unit: '秒',
          ),
        ),
        Container(width: 1, height: 44, color: Colors.white24),
        Expanded(
          child: _Metric(
            label: '口头禅',
            value:
                '${report.fillerCounts.values.fold<int>(0, (sum, value) => sum + value)}',
            unit: '次',
          ),
        ),
        Container(width: 1, height: 44, color: Colors.white24),
        Expanded(
          child: _Metric(
            label: '长停顿',
            value: report.longPauseCount?.toString() ?? '--',
            unit: report.longPauseCount == null ? '未计算' : '次',
          ),
        ),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      const SizedBox(height: 4),
      Text.rich(
        TextSpan(
          text: value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
          children: [
            TextSpan(
              text: ' $unit',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _AudioWaveform extends StatelessWidget {
  const _AudioWaveform({required this.points});

  final List<AudioWavePoint> points;

  @override
  Widget build(BuildContext context) => Container(
    height: 130,
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
    decoration: BoxDecoration(
      color: AppColors.white,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '低谷持续约 1.5 秒以上时记为长停顿',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: CustomPaint(
            painter: _AudioWaveformPainter(points),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    ),
  );
}

class _AudioWaveformPainter extends CustomPainter {
  const _AudioWaveformPainter(this.points);

  final List<AudioWavePoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final baseline = size.height / 2;
    canvas.drawLine(
      Offset(0, baseline),
      Offset(size.width, baseline),
      Paint()
        ..color = AppColors.line
        ..strokeWidth = 1,
    );
    final barWidth = size.width / points.length;
    for (var index = 0; index < points.length; index++) {
      final level = points[index].level.clamp(0.0, 1.0);
      final barHeight = (3 + level * (size.height - 6)).clamp(3.0, size.height);
      final x = index * barWidth + barWidth / 2;
      canvas.drawLine(
        Offset(x, baseline - barHeight / 2),
        Offset(x, baseline + barHeight / 2),
        Paint()
          ..color = level < 0.12 ? AppColors.gold : AppColors.jade
          ..strokeWidth = (barWidth * 0.48).clamp(1.0, 4.0)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AudioWaveformPainter oldDelegate) => false;
}

class _EvidenceQuote extends StatelessWidget {
  const _EvidenceQuote({required this.item});
  final EvidenceRef item;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: const BoxDecoration(
      color: AppColors.white,
      border: Border(left: BorderSide(color: AppColors.jade, width: 3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(item.quote, style: const TextStyle(height: 1.55)),
        const SizedBox(height: 6),
        Text(
          '材料片段 ${item.chunkId.substring(0, item.chunkId.length.clamp(0, 8))}',
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.index, required this.text});
  final int index;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.vermilion,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(child: Text(text, style: const TextStyle(height: 1.55))),
      ],
    ),
  );
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item});
  final Map<String, dynamic> item;
  @override
  Widget build(BuildContext context) {
    final milliseconds = (item['timestamp_ms'] as num?)?.toInt() ?? 0;
    final seconds = milliseconds ~/ 1000;
    final time =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              time,
              style: const TextStyle(
                color: AppColors.vermilion,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(child: Text(item['message']?.toString() ?? '需要复盘')),
        ],
      ),
    );
  }
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.description_outlined,
            size: 42,
            color: AppColors.vermilion,
          ),
          const SizedBox(height: 12),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重新读取'),
          ),
        ],
      ),
    ),
  );
}
