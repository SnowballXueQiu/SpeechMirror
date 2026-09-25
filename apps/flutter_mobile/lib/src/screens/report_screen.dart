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
            const PageIntro(
              eyebrow: 'EVIDENCE-BASED REVIEW',
              title: '这一次，你说清楚了吗？',
              description: '分数用于定位问题；内容判断必须能回到项目材料。',
            ),
            const SizedBox(height: 24),
            _SummaryBand(report: report),
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
            if (report.content.evidence.isEmpty)
              const Text(
                '本次内容评价未返回可展示的材料片段。',
                style: TextStyle(color: AppColors.muted),
              )
            else
              for (final item in report.content.evidence)
                _EvidenceQuote(item: item),
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
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('返回项目'),
            ),
          ],
        );
      },
    ),
  );

  void _reload() => setState(
    () => _report = ref.read(apiClientProvider).getReport(widget.sessionId),
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
