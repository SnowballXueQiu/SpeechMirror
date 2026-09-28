import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api_client.dart';
import '../auth_controller.dart';
import '../cache_service.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _cache = CacheService();
  late Future<ActivitySummary> _activity;
  late Future<List<int>?> _avatar;
  late Future<int> _cacheSize;

  @override
  void initState() {
    super.initState();
    _reloadSecondaryData();
  }

  void _reloadSecondaryData() {
    final api = ref.read(apiClientProvider);
    _activity = api.getActivity();
    _avatar = _loadAvatar(api);
    _cacheSize = _cache.sizeBytes();
  }

  Future<List<int>?> _loadAvatar(ApiClient api) async {
    final hasAvatar =
        ref.read(authControllerProvider).profile?.hasAvatar ?? false;
    if (!hasAvatar) return null;
    try {
      return await api.getAvatarBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final profile = auth.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('账户')),
      body: profile == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 48),
                children: [
                  _ProfileHeader(
                    profile: profile,
                    avatar: _avatar,
                    onAvatarTap: _changeAvatar,
                    onBioTap: () => _editBio(profile),
                    onCopyId: () => _copyId(profile.id),
                  ),
                  const SizedBox(height: 28),
                  FutureBuilder<ActivitySummary>(
                    future: _activity,
                    builder: (context, snapshot) => _ActivityPanel(
                      summary: snapshot.data,
                      loading: snapshot.connectionState != ConnectionState.done,
                      error: snapshot.hasError,
                      onRetry: () => setState(
                        () => _activity = ref
                            .read(apiClientProvider)
                            .getActivity(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const _GroupTitle('个人设置'),
                  _SettingsRow(
                    icon: Icons.tune_rounded,
                    title: '身份与训练偏好',
                    subtitle: _profileSummary(profile),
                    onTap: _openPreferences,
                  ),
                  _SettingsRow(
                    icon: Icons.insights_outlined,
                    title: '匿名产品调研',
                    subtitle: '仅汇总身份、场景和训练目标',
                    trailing: Switch.adaptive(
                      value: profile.researchConsent,
                      onChanged: (value) => _setResearchConsent(profile, value),
                    ),
                  ),
                  const SizedBox(height: 26),
                  const _GroupTitle('存储与规则'),
                  FutureBuilder<int>(
                    future: _cacheSize,
                    builder: (context, snapshot) => _SettingsRow(
                      icon: Icons.cleaning_services_outlined,
                      title: '清理缓存',
                      subtitle: snapshot.hasData
                          ? formatCacheSize(snapshot.data!)
                          : '正在计算',
                      onTap: _clearCache,
                    ),
                  ),
                  _SettingsRow(
                    icon: Icons.shield_outlined,
                    title: '隐私政策',
                    onTap: () => context.push('/profile/privacy'),
                  ),
                  _SettingsRow(
                    icon: Icons.description_outlined,
                    title: '用户协议',
                    onTap: () => context.push('/profile/terms'),
                  ),
                  const SizedBox(height: 26),
                  const _GroupTitle('账户'),
                  _SettingsRow(
                    icon: Icons.logout_rounded,
                    title: '退出登录',
                    destructive: true,
                    onTap: _logout,
                  ),
                  const SizedBox(height: 24),
                  const Center(
                    child: Text(
                      'SpeechMirror 1.0.0',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _profileSummary(UserProfile profile) {
    final parts = [
      profile.displayIdentity,
      if (profile.displayScenarios.isNotEmpty)
        profile.displayScenarios.join('、'),
    ].whereType<String>().where((value) => value.isNotEmpty).toList();
    return parts.isEmpty ? '尚未设置' : parts.join(' · ');
  }

  Future<void> _refresh() async {
    await ref.read(authControllerProvider).refreshProfile();
    if (!mounted) return;
    setState(_reloadSecondaryData);
    await Future.wait([_activity, _cacheSize]);
  }

  Future<void> _copyId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('用户 ID 已复制')));
  }

  Future<void> _changeAvatar() async {
    final profile = ref.read(authControllerProvider).profile!;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('头像', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, 'choose'),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(profile.hasAvatar ? '更换头像' : '选择头像'),
              ),
              if (profile.hasAvatar)
                TextButton.icon(
                  onPressed: () => Navigator.pop(context, 'delete'),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('移除当前头像'),
                ),
            ],
          ),
        ),
      ),
    );
    if (action == null) return;
    try {
      final api = ref.read(apiClientProvider);
      if (action == 'delete') {
        await api.deleteAvatar();
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['png', 'jpg', 'jpeg'],
          allowMultiple: false,
        );
        final path = result?.files.single.path;
        if (path == null) return;
        await api.uploadAvatar(path);
      }
      await ref.read(authControllerProvider).refreshProfile();
      if (mounted) setState(() => _avatar = _loadAvatar(api));
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _editBio(UserProfile profile) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _BioEditorSheet(initialValue: profile.bio ?? ''),
    );
    if (result == null) return;
    await _updateProfile(profile, bio: result);
  }

  Future<void> _setResearchConsent(UserProfile profile, bool value) async {
    await _updateProfile(profile, researchConsent: value);
  }

  Future<void> _updateProfile(
    UserProfile profile, {
    String? bio,
    bool? researchConsent,
  }) async {
    try {
      await ref
          .read(authControllerProvider)
          .updateProfile(
            UserProfileUpdate(
              bio: bio ?? profile.bio,
              identity: profile.identity,
              identityOther: profile.identityOther,
              scenarios: profile.scenarios,
              scenarioOther: profile.scenarioOther,
              purposes: profile.purposes,
              purposeOther: profile.purposeOther,
              onboardingCompleted: true,
              researchConsent: researchConsent ?? profile.researchConsent,
            ),
          );
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _openPreferences() async {
    await context.push('/profile/preferences');
    if (mounted) await ref.read(authControllerProvider).refreshProfile();
  }

  Future<void> _clearCache() async {
    try {
      await _cache.clear();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (!mounted) return;
      setState(() => _cacheSize = _cache.sizeBytes());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缓存已清理，项目与待上传训练不受影响')));
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> _logout() async {
    await ref.read(authControllerProvider).logout();
    if (mounted) context.go('/login');
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.avatar,
    required this.onAvatarTap,
    required this.onBioTap,
    required this.onCopyId,
  });

  final UserProfile profile;
  final Future<List<int>?> avatar;
  final VoidCallback onAvatarTap;
  final VoidCallback onBioTap;
  final VoidCallback onCopyId;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                FutureBuilder<List<int>?>(
                  future: avatar,
                  builder: (context, snapshot) => CircleAvatar(
                    radius: 36,
                    backgroundColor: AppColors.ink,
                    backgroundImage:
                        snapshot.data == null || snapshot.data!.isEmpty
                        ? null
                        : MemoryImage(Uint8List.fromList(snapshot.data!)),
                    child: snapshot.data == null || snapshot.data!.isEmpty
                        ? Text(
                            profile.username.characters.first.toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.signal,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                ),
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.jade,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.paper, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                InkWell(
                  onTap: onCopyId,
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'ID ${profile.id}',
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 18),
      InkWell(
        onTap: onBioTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.line),
              bottom: BorderSide(color: AppColors.line),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  profile.bio?.isNotEmpty == true ? profile.bio! : '添加个人简介',
                  style: TextStyle(
                    color: profile.bio?.isNotEmpty == true
                        ? AppColors.ink
                        : AppColors.muted,
                  ),
                ),
              ),
              const Icon(Icons.edit_outlined, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    ],
  );
}

class _BioEditorSheet extends StatefulWidget {
  const _BioEditorSheet({required this.initialValue});

  final String initialValue;

  @override
  State<_BioEditorSheet> createState() => _BioEditorSheetState();
}

class _BioEditorSheetState extends State<_BioEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      4,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('个人简介', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 200,
          maxLines: 4,
          minLines: 2,
          decoration: const InputDecoration(hintText: '简单介绍你的方向或正在准备的答辩'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    ),
  );
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({
    required this.summary,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final ActivitySummary? summary;
  final bool loading;
  final bool error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
    decoration: BoxDecoration(
      color: AppColors.night,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.grid_view_rounded, color: AppColors.signal, size: 18),
            SizedBox(width: 9),
            Text(
              '过去一年',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            Spacer(),
            Text(
              '练习活跃度',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (loading)
          const SizedBox(
            height: 90,
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.signal,
                strokeWidth: 2,
              ),
            ),
          )
        else if (error)
          SizedBox(
            height: 90,
            child: Center(
              child: TextButton(
                onPressed: onRetry,
                child: const Text('加载失败，点击重试'),
              ),
            ),
          )
        else ...[
          _ActivityGrid(summary: summary!),
          const SizedBox(height: 18),
          Row(
            children: [
              _ActivityStat(value: '${summary!.activeDays}', label: '活跃天数'),
              _ActivityStat(value: '${summary!.currentStreak}', label: '连续天数'),
              _ActivityStat(
                value: '${summary!.totalPractices}',
                label: '模拟答辩',
                last: true,
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _ActivityGrid extends StatelessWidget {
  const _ActivityGrid({required this.summary});

  final ActivitySummary summary;

  @override
  Widget build(BuildContext context) {
    final values = {
      for (final day in summary.days)
        _dateKey(day.date): day.useCount + day.practiceCount * 2,
    };
    final first = summary.through.subtract(const Duration(days: 364));
    final start = first.subtract(Duration(days: first.weekday - 1));
    final end = summary.through;
    return Semantics(
      label: '过去一年活跃${summary.activeDays}天，共完成${summary.totalPractices}次模拟答辩',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(53, (week) {
            return Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Column(
                children: List.generate(7, (weekday) {
                  final date = start.add(Duration(days: week * 7 + weekday));
                  final inRange = !date.isBefore(first) && !date.isAfter(end);
                  final intensity = inRange ? values[_dateKey(date)] ?? 0 : -1;
                  return Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.only(bottom: 3),
                    decoration: BoxDecoration(
                      color: _activityColor(intensity),
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  );
                }),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _ActivityStat extends StatelessWidget {
  const _ActivityStat({
    required this.value,
    required this.label,
    this.last = false,
  });

  final String value;
  final String label;
  final bool last;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(right: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(
      title,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: destructive ? AppColors.softRed : AppColors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.line),
            ),
            child: Icon(
              icon,
              size: 18,
              color: destructive ? AppColors.vermilion : AppColors.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: destructive ? AppColors.vermilion : AppColors.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          trailing ??
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
        ],
      ),
    ),
  );
}

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

Color _activityColor(int intensity) => switch (intensity) {
  < 0 => Colors.transparent,
  0 => const Color(0xFF293029),
  1 => const Color(0xFF4C6632),
  2 => const Color(0xFF71983B),
  3 => const Color(0xFF9DCC4C),
  _ => AppColors.signal,
};
