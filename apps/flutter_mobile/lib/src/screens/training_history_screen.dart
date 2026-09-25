import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../auth_controller.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

enum _TrendMetric { duration, filler, content, qa }

class TrainingHistoryScreen extends ConsumerStatefulWidget {
  const TrainingHistoryScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<TrainingHistoryScreen> createState() =>
      _TrainingHistoryScreenState();
}

class _TrainingHistoryScreenState extends ConsumerState<TrainingHistoryScreen> {
  late Future<(Project, List<RehearsalSession>, TrainingTrends)> _data;
  _TrendMetric _metric = _TrendMetric.duration;

  @override
  void initState() {
    super.initState();
    _data = _loadData();
  }

  Future<(Project, List<RehearsalSession>, TrainingTrends)> _loadData() async {
    final api = ref.read(apiClientProvider);
    final values = await Future.wait([
      api.getProject(widget.projectId),
      api.listSessions(widget.projectId),
      api.getTrends(widget.projectId),
    ]);
    return (
      values[0] as Project,
      values[1] as List<RehearsalSession>,
      values[2] as TrainingTrends,
    );
  }

  void _reload() {
    setState(() {
      _data = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('训练历史'),
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: FutureBuilder<(Project, List<RehearsalSession>, TrainingTrends)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _HistoryError(error: snapshot.error!, onRetry: _reload);
        }
        final (project, sessions, trends) = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 48),
          children: [
            PageIntro(
              eyebrow: 'PROGRESS / ${trends.points.length} REPORTS',
              title: project.name,
              description: '按真实训练报告观察变化，未生成报告的练习只保留在历史记录中。',
            ),
            const SizedBox(height: 24),
            _SummaryBand(sessions: sessions, points: trends.points),
            const SizedBox(height: 28),
            const SectionLabel('训练趋势'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<_TrendMetric>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _TrendMetric.duration,
                    label: Text('时长'),
                  ),
                  ButtonSegment(value: _TrendMetric.filler, label: Text('口头禅')),
                  ButtonSegment(value: _TrendMetric.content, label: Text('内容')),
                  ButtonSegment(value: _TrendMetric.qa, label: Text('问答')),
                ],
                selected: {_metric},
                onSelectionChanged: (value) {
                  setState(() => _metric = value.single);
                },
              ),
            ),
            const SizedBox(height: 16),
            if (trends.points.isEmpty)
              const _NoReports()
            else
              _TrendPanel(points: trends.points, metric: _metric),
            const SizedBox(height: 30),
            SectionLabel('${sessions.length} 次训练记录'),
            const SizedBox(height: 12),
            if (sessions.isEmpty)
              const _NoSessions()
            else
              for (final session in sessions) ...[
                _SessionRow(
                  session: session,
                  hasReport: trends.points.any(
                    (point) => point.sessionId == session.id,
                  ),
                ),
                const SizedBox(height: 10),
              ],
          ],
        );
      },
    ),
  );
}

class _SummaryBand extends StatelessWidget {
  const _SummaryBand({required this.sessions, required this.points});

  final List<RehearsalSession> sessions;
  final List<TrainingTrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final completed = sessions
        .where((item) => item.status == 'completed')
        .length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryMetric(
              label: '训练',
              value: '${sessions.length}',
              unit: '次',
            ),
          ),
          const _BandDivider(),
          Expanded(
            child: _SummaryMetric(label: '已完成', value: '$completed', unit: '次'),
          ),
          const _BandDivider(),
          Expanded(
            child: _SummaryMetric(
              label: '可比较',
              value: '${points.length}',
              unit: '份',
            ),
          ),
        ],
      ),
    );
  }
}

class _BandDivider extends StatelessWidget {
  const _BandDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 44, color: Colors.white24);
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.unit,
  });

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
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({required this.points, required this.metric});

  final List<TrainingTrendPoint> points;
  final _TrendMetric metric;

  @override
  Widget build(BuildContext context) {
    final chartPoints = <({double x, double y})>[];
    for (var index = 0; index < points.length; index++) {
      final value = _value(points[index]);
      if (value != null) chartPoints.add((x: index.toDouble(), y: value));
    }
    if (chartPoints.isEmpty) {
      return const _MetricEmpty();
    }
    final values = chartPoints.map((item) => item.y).toList();
    final rawMin = values.reduce(math.min);
    final rawMax = values.reduce(math.max);
    final padding = math.max(
      (rawMax - rawMin).abs() * 0.18,
      metric == _TrendMetric.duration ? 10.0 : 5.0,
    );
    final minY = metric == _TrendMetric.duration
        ? rawMin - padding
        : math.max(0.0, rawMin - padding);
    final maxY = rawMax + padding;
    final latest = chartPoints.last.y;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _description,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_formatValue(latest)} $_unit',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: AppColors.jadeDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 210,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: math.max(1, points.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  horizontalInterval: (maxY - minY) / 4,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.paperStrong,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) => SideTitleWidget(
                        meta: meta,
                        child: Text(
                          _formatValue(value),
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (index < 0 ||
                            index >= points.length ||
                            (points.length > 5 && index.isOdd)) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.muted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.ink,
                    getTooltipItems: (spots) => spots
                        .map(
                          (spot) => LineTooltipItem(
                            '第 ${spot.x.round() + 1} 次\n${_formatValue(spot.y)} $_unit',
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: chartPoints
                        .map((item) => FlSpot(item.x, item.y))
                        .toList(),
                    isCurved: false,
                    color: AppColors.jade,
                    barWidth: 3,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.jade.withValues(alpha: 0.08),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Center(
            child: Text(
              '训练次序',
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }

  double? _value(TrainingTrendPoint point) => switch (metric) {
    _TrendMetric.duration => point.durationDeviationSeconds.toDouble(),
    _TrendMetric.filler => point.fillerPerMinute,
    _TrendMetric.content => point.contentScore?.toDouble(),
    _TrendMetric.qa => point.qaScore?.toDouble(),
  };

  String get _description => switch (metric) {
    _TrendMetric.duration => '实际时长与目标时长之差，负数表示提前结束',
    _TrendMetric.filler => '每分钟识别到的口头禅次数',
    _TrendMetric.content => '有材料依据的内容评价',
    _TrendMetric.qa => '已完成评委问答的评价',
  };

  String get _unit => switch (metric) {
    _TrendMetric.duration => '秒',
    _TrendMetric.filler => '次/分',
    _TrendMetric.content || _TrendMetric.qa => '分',
  };

  String _formatValue(double value) => metric == _TrendMetric.filler
      ? value.toStringAsFixed(1)
      : value.round().toString();
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.hasReport});

  final RehearsalSession session;
  final bool hasReport;

  @override
  Widget build(BuildContext context) {
    final actual = session.actualSeconds;
    return Card(
      child: ListTile(
        onTap: hasReport ? () => context.push('/reports/${session.id}') : null,
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hasReport ? AppColors.jadeDark : AppColors.paperStrong,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            hasReport ? Icons.description_outlined : Icons.schedule_outlined,
            color: hasReport ? Colors.white : AppColors.muted,
            size: 21,
          ),
        ),
        title: Text(
          session.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${_date(session.createdAt)} · ${actual == null ? '尚无时长' : _duration(actual)} · ${_statusLabel(session, hasReport)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        trailing: hasReport ? const Icon(Icons.chevron_right) : null,
      ),
    );
  }

  String _date(DateTime? date) =>
      date == null ? '时间未知' : DateFormat('MM月dd日 HH:mm').format(date.toLocal());

  String _duration(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

  String _statusLabel(RehearsalSession session, bool hasReport) {
    if (hasReport) return '查看报告';
    return switch (session.status) {
      'recording' => '录制待完成',
      'completed' => '报告待生成',
      _ => session.status,
    };
  }
}

class _NoReports extends StatelessWidget {
  const _NoReports();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
    decoration: BoxDecoration(
      color: AppColors.white,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Column(
      children: [
        Icon(Icons.query_stats_outlined, size: 36, color: AppColors.muted),
        SizedBox(height: 12),
        Text('暂无可比较报告', style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text(
          '完成分析并生成真实报告后，这里才会显示趋势。',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );
}

class _MetricEmpty extends StatelessWidget {
  const _MetricEmpty();

  @override
  Widget build(BuildContext context) => Container(
    height: 184,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.white,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Text('现有报告没有这项数据', style: TextStyle(color: AppColors.muted)),
  );
}

class _NoSessions extends StatelessWidget {
  const _NoSessions();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Text('还没有训练记录。', style: TextStyle(color: AppColors.muted)),
  );
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 42, color: AppColors.vermilion),
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
