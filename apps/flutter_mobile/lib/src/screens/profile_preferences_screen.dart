import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth_controller.dart';
import '../models.dart';
import '../profile_options.dart';
import '../theme.dart';
import '../widgets.dart';

class ProfilePreferencesScreen extends ConsumerStatefulWidget {
  const ProfilePreferencesScreen({super.key});

  @override
  ConsumerState<ProfilePreferencesScreen> createState() =>
      _ProfilePreferencesScreenState();
}

class _ProfilePreferencesScreenState
    extends ConsumerState<ProfilePreferencesScreen> {
  final _identityOther = TextEditingController();
  final _scenarioOther = TextEditingController();
  final _purposeOther = TextEditingController();
  String? _identity;
  String? _scenario;
  final Set<String> _purposes = {};
  var _consent = false;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(authControllerProvider).profile;
    _identity = profile?.identity;
    _scenario = profile?.scenario;
    _purposes.addAll(profile?.purposes ?? const []);
    _identityOther.text = profile?.identityOther ?? '';
    _scenarioOther.text = profile?.scenarioOther ?? '';
    _purposeOther.text = profile?.purposeOther ?? '';
    _consent = profile?.researchConsent ?? false;
  }

  @override
  void dispose() {
    _identityOther.dispose();
    _scenarioOther.dispose();
    _purposeOther.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authControllerProvider).profile;
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('训练偏好'),
          actions: [
            TextButton(
              onPressed: _saving || profile == null
                  ? null
                  : () => _save(profile),
              child: _saving ? const Text('保存中') : const Text('保存'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: profile == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
                children: [
                  const _SectionHeading(
                    title: '身份与场景',
                    caption: '用于调整训练侧重点，不影响账户功能。',
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    initialValue: _identity,
                    decoration: const InputDecoration(labelText: '身份'),
                    items: profileIdentities
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _identity = value),
                  ),
                  if (_identity == '其他') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _identityOther,
                      maxLength: 50,
                      decoration: const InputDecoration(
                        labelText: '其他身份',
                        counterText: '',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _scenario,
                    decoration: const InputDecoration(labelText: '主要场景'),
                    items: profileScenarios
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _scenario = value),
                  ),
                  if (_scenario == '其他') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _scenarioOther,
                      maxLength: 50,
                      decoration: const InputDecoration(
                        labelText: '其他场景',
                        counterText: '',
                      ),
                    ),
                  ],
                  const SizedBox(height: 34),
                  const _SectionHeading(title: '训练目标', caption: '可多选。'),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in profilePurposes)
                        FilterChip(
                          label: Text(option),
                          selected: _purposes.contains(option),
                          onSelected: (selected) => setState(() {
                            selected
                                ? _purposes.add(option)
                                : _purposes.remove(option);
                          }),
                          showCheckmark: false,
                          selectedColor: AppColors.ink,
                          labelStyle: TextStyle(
                            color: _purposes.contains(option)
                                ? Colors.white
                                : AppColors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  if (_purposes.contains('其他')) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _purposeOther,
                      maxLength: 50,
                      decoration: const InputDecoration(
                        labelText: '其他训练目标',
                        counterText: '',
                      ),
                    ),
                  ],
                  const SizedBox(height: 34),
                  const Divider(),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _consent,
                    onChanged: (value) => setState(() => _consent = value),
                    title: const Text(
                      '参与匿名产品调研',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Text('仅汇总身份、场景和训练目标；关闭后不再用于后续调研统计。'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _save(UserProfile profile) async {
    if (_identity == '其他' && _identityOther.text.trim().isEmpty) {
      showError(context, '请填写其他身份');
      return;
    }
    if (_scenario == '其他' && _scenarioOther.text.trim().isEmpty) {
      showError(context, '请填写其他场景');
      return;
    }
    if (_purposes.contains('其他') && _purposeOther.text.trim().isEmpty) {
      showError(context, '请填写其他训练目标');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(authControllerProvider)
          .updateProfile(
            UserProfileUpdate(
              bio: profile.bio,
              identity: _identity,
              identityOther: _identity == '其他'
                  ? _identityOther.text.trim()
                  : null,
              scenario: _scenario,
              scenarioOther: _scenario == '其他'
                  ? _scenarioOther.text.trim()
                  : null,
              purposes: _purposes.toList(),
              purposeOther: _purposes.contains('其他')
                  ? _purposeOther.text.trim()
                  : null,
              onboardingCompleted: true,
              researchConsent: _consent,
            ),
          );
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.caption});

  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      Text(caption, style: const TextStyle(color: AppColors.muted)),
    ],
  );
}
