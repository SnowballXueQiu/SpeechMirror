import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth_controller.dart';
import '../models.dart';
import '../profile_options.dart';
import '../theme.dart';
import '../widgets.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _identityOther = TextEditingController();
  final _scenarioOther = TextEditingController();
  final _purposeOther = TextEditingController();
  var _step = 0;
  String? _identity;
  final Set<String> _scenarios = {};
  final Set<String> _purposes = {};
  var _researchConsent = false;
  var _saving = false;

  @override
  void dispose() {
    _identityOther.dispose();
    _scenarioOther.dispose();
    _purposeOther.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
    child: Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('设置你的训练方式'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _skip,
            child: const Text('跳过'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
              child: Row(
                children: List.generate(
                  3,
                  (index) => Expanded(
                    child: Container(
                      height: 3,
                      margin: EdgeInsets.only(right: index == 2 ? 0 : 6),
                      decoration: BoxDecoration(
                        color: index <= _step
                            ? AppColors.ink
                            : AppColors.paperStrong,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: ListView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: switch (_step) {
                    0 => _identityStep(),
                    1 => _scenarioStep(),
                    _ => _purposeStep(),
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              decoration: const BoxDecoration(
                color: AppColors.paper,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  if (_step > 0)
                    IconButton.outlined(
                      tooltip: '上一步',
                      onPressed: _saving
                          ? null
                          : () => setState(() => _step -= 1),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  if (_step > 0) const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _next,
                      icon: Icon(
                        _step == 2
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                      ),
                      label: Text(_step == 2 ? '完成设置' : '继续'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _identityStep() => [
    const _StepHeading(
      number: '01',
      title: '你现在的身份',
      description: '用于调整提问难度与表达方式，可随时修改。',
    ),
    const SizedBox(height: 24),
    for (final option in profileIdentities)
      _OptionTile(
        label: option,
        selected: _identity == option,
        onTap: () => setState(() => _identity = option),
      ),
    if (_identity == '其他') ...[
      const SizedBox(height: 10),
      TextField(
        controller: _identityOther,
        autofocus: true,
        maxLength: 50,
        decoration: const InputDecoration(labelText: '输入你的身份', counterText: ''),
      ),
    ],
  ];

  List<Widget> _scenarioStep() => [
    const _StepHeading(
      number: '02',
      title: '主要训练场景',
      description: '可多选，言镜会据此组织评委视角和训练重点。',
    ),
    const SizedBox(height: 24),
    for (final option in profileScenarios)
      _OptionTile(
        label: option,
        selected: _scenarios.contains(option),
        onTap: () => setState(() {
          _scenarios.contains(option)
              ? _scenarios.remove(option)
              : _scenarios.add(option);
        }),
      ),
    if (_scenarios.contains('其他')) ...[
      const SizedBox(height: 10),
      TextField(
        controller: _scenarioOther,
        autofocus: true,
        maxLength: 50,
        decoration: const InputDecoration(labelText: '输入使用场景', counterText: ''),
      ),
    ],
  ];

  List<Widget> _purposeStep() => [
    const _StepHeading(
      number: '03',
      title: '你想重点提升什么',
      description: '可多选，也可以暂不选择。',
    ),
    const SizedBox(height: 24),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in profilePurposes)
          FilterChip(
            label: Text(option),
            selected: _purposes.contains(option),
            onSelected: (selected) => setState(() {
              selected ? _purposes.add(option) : _purposes.remove(option);
            }),
            showCheckmark: false,
            selectedColor: AppColors.ink,
            labelStyle: TextStyle(
              color: _purposes.contains(option) ? Colors.white : AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: const BorderSide(color: AppColors.line),
            ),
          ),
      ],
    ),
    if (_purposes.contains('其他')) ...[
      const SizedBox(height: 14),
      TextField(
        controller: _purposeOther,
        maxLength: 50,
        decoration: const InputDecoration(labelText: '输入其他目标', counterText: ''),
      ),
    ],
    const SizedBox(height: 30),
    const Divider(),
    SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: _researchConsent,
      onChanged: (value) => setState(() => _researchConsent = value),
      title: const Text(
        '参与匿名产品调研',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: const Padding(
        padding: EdgeInsets.only(top: 5),
        child: Text('仅汇总身份、场景和训练目标，不包含论文材料、录音、视频或答辩回答。'),
      ),
    ),
  ];

  Future<void> _next() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_step < 2) {
      setState(() => _step += 1);
      return;
    }
    if (_identity == '其他' && _identityOther.text.trim().isEmpty) {
      showError(context, '请填写你的身份，或选择其他选项');
      return;
    }
    if (_scenarios.contains('其他') && _scenarioOther.text.trim().isEmpty) {
      showError(context, '请填写使用场景，或选择其他选项');
      return;
    }
    if (_purposes.contains('其他') && _purposeOther.text.trim().isEmpty) {
      showError(context, '请填写其他训练目标');
      return;
    }
    await _save();
  }

  Future<void> _skip() async {
    _identity = null;
    _scenarios.clear();
    _purposes.clear();
    _researchConsent = false;
    await _save();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(authControllerProvider)
          .updateProfile(
            UserProfileUpdate(
              identity: _identity,
              identityOther: _identity == '其他'
                  ? _identityOther.text.trim()
                  : null,
              scenarios: _scenarios.toList(),
              scenarioOther: _scenarios.contains('其他')
                  ? _scenarioOther.text.trim()
                  : null,
              purposes: _purposes.toList(),
              purposeOther: _purposes.contains('其他')
                  ? _purposeOther.text.trim()
                  : null,
              onboardingCompleted: true,
              researchConsent: _researchConsent,
            ),
          );
      if (mounted) context.go('/projects');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _StepHeading extends StatelessWidget {
  const _StepHeading({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.ink,
          shape: BoxShape.circle,
        ),
        child: Text(
          number,
          style: const TextStyle(
            color: AppColors.signal,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 5),
            Text(description, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    ],
  );
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 52,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: selected ? AppColors.ink : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.ink : AppColors.line,
              ),
            ),
            child: selected
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : null,
          ),
        ],
      ),
    ),
  );
}
