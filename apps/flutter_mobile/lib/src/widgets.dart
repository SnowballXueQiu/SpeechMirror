import 'package:flutter/material.dart';

import 'theme.dart';

class DefenseStageRail extends StatelessWidget {
  const DefenseStageRail({super.key, required this.activeStage});

  final int activeStage;

  static const _labels = ['产品陈述', 'AI答辩', '综合报告'];
  static const _icons = [
    Icons.videocam_outlined,
    Icons.record_voice_over_outlined,
    Icons.assessment_outlined,
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < _labels.length; index++) ...[
        Expanded(
          child: Column(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index <= activeStage
                      ? AppColors.jade
                      : AppColors.paperStrong,
                ),
                child: Icon(
                  _icons[index],
                  size: 18,
                  color: index <= activeStage ? Colors.white : AppColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _labels[index],
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: index == activeStage
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: index == activeStage ? AppColors.ink : AppColors.muted,
                ),
              ),
            ],
          ),
        ),
        if (index < _labels.length - 1)
          Container(
            width: 28,
            height: 2,
            margin: const EdgeInsets.only(bottom: 24),
            color: index < activeStage ? AppColors.jade : AppColors.line,
          ),
      ],
    ],
  );
}

class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
  });
  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow.toUpperCase(),
        style: const TextStyle(
          color: AppColors.vermilion,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
      const SizedBox(height: 8),
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      Text(
        description,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
      ),
    ],
  );
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(width: 4, height: 18, color: AppColors.vermilion),
      const SizedBox(width: 9),
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      ),
      if (trailing != null) trailing!,
    ],
  );
}

class ScoreRow extends StatelessWidget {
  const ScoreRow({
    super.key,
    required this.label,
    required this.score,
    required this.summary,
  });
  final String label;
  final int? score;
  final String summary;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: (score ?? 0) / 100,
                  minHeight: 7,
                  backgroundColor: AppColors.paperStrong,
                  color: score == null
                      ? AppColors.muted
                      : (score! >= 75 ? AppColors.jade : AppColors.gold),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 30,
              child: Text(
                score?.toString() ?? '—',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Padding(
          padding: const EdgeInsets.only(left: 72),
          child: Text(
            summary,
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error.toString()),
      backgroundColor: AppColors.vermilion,
    ),
  );
}
