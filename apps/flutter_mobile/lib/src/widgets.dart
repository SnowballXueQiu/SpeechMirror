import 'package:flutter/material.dart';

import 'api_client.dart';
import 'theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Image.asset(
      'assets/branding/speechmirror_logo.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    ),
  );
}

Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  isDismissible: isDismissible,
  enableDrag: isDismissible,
  useSafeArea: false,
  backgroundColor: Colors.transparent,
  barrierColor: AppColors.ink.withValues(alpha: 0.42),
  builder: builder,
);

class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.onClose,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.white,
    clipBehavior: Clip.antiAlias,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.softBlue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: AppColors.jade, size: 21),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (subtitle?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: onClose ?? () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.paper,
                    foregroundColor: AppColors.ink,
                    fixedSize: const Size.square(38),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Flexible(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: child,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<bool> showAppConfirmation(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '取消',
  IconData icon = Icons.help_outline_rounded,
  bool destructive = false,
  Key? confirmKey,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: AppColors.ink.withValues(alpha: 0.46),
    builder: (dialogContext) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24000000),
                blurRadius: 32,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: destructive ? AppColors.softRed : AppColors.softBlue,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    color: destructive ? AppColors.vermilion : AppColors.jade,
                    size: 23,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: Text(cancelLabel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: confirmKey,
                        style: destructive
                            ? FilledButton.styleFrom(
                                backgroundColor: AppColors.vermilion,
                              )
                            : null,
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return result ?? false;
}

class AppMenuAction<T> {
  const AppMenuAction({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
}

class AppMenuButton<T> extends StatelessWidget {
  const AppMenuButton({
    super.key,
    required this.tooltip,
    required this.actions,
    required this.onSelected,
    this.enabled = true,
  });

  final String tooltip;
  final List<AppMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => MenuAnchor(
    alignmentOffset: const Offset(-170, 6),
    style: MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(AppColors.white),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(12),
      shadowColor: WidgetStatePropertyAll(
        AppColors.ink.withValues(alpha: 0.18),
      ),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
      minimumSize: const WidgetStatePropertyAll(Size(210, 0)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
    ),
    builder: (context, controller, child) => IconButton(
      tooltip: tooltip,
      onPressed: enabled
          ? () => controller.isOpen ? controller.close() : controller.open()
          : null,
      style: IconButton.styleFrom(
        fixedSize: const Size.square(40),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.line),
      ),
      icon: const Icon(Icons.more_horiz_rounded),
    ),
    menuChildren: [
      for (final action in actions)
        MenuItemButton(
          onPressed: () => onSelected(action.value),
          leadingIcon: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: action.destructive ? AppColors.softRed : AppColors.paper,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              action.icon,
              size: 17,
              color: action.destructive ? AppColors.vermilion : AppColors.ink,
            ),
          ),
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size(196, 50)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 10),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          child: Text(
            action.label,
            style: TextStyle(
              color: action.destructive ? AppColors.vermilion : AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
    ],
  );
}

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
  Widget build(BuildContext context) => Container(
    height: 46,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: AppColors.white,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        for (var index = 0; index < _labels.length; index++)
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: index == activeStage
                    ? AppColors.softBlue
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _icons[index],
                    size: 16,
                    color: index <= activeStage
                        ? AppColors.jade
                        : AppColors.muted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _labels[index],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: index == activeStage
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: index == activeStage
                            ? AppColors.jadeDark
                            : AppColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.eyebrow,
    required this.title,
    this.description = '',
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
          color: AppColors.jade,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
      const SizedBox(height: 6),
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
      if (description.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
      ],
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
  if (error is AuthenticationRequiredException) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(error.toString())));
}
