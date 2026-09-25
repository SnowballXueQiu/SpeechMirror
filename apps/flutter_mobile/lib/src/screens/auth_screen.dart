import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth_controller.dart';
import '../theme.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _showPassword = false;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(authControllerProvider)
        .submit(_username.text, _password.text, register: _register);
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'SPEECHMIRROR / 01',
                      style: TextStyle(
                        color: AppColors.vermilion,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text('言镜', style: Theme.of(context).textTheme.displayLarge),
                    const SizedBox(height: 10),
                    const Text(
                      '把每一次答辩，变成可复盘的证据。',
                      style: TextStyle(fontSize: 18, color: AppColors.muted),
                    ),
                    const SizedBox(height: 44),
                    TextFormField(
                      controller: _username,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: '用户名',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        final username = value?.trim() ?? '';
                        if (!RegExp(
                          r'^[A-Za-z0-9_-]{3,32}$',
                        ).hasMatch(username)) {
                          return '请输入 3–32 位字母、数字、下划线或连字符';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: auth.busy ? null : (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _showPassword ? '隐藏密码' : '显示密码',
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                          icon: Icon(
                            _showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        final length = value?.characters.length ?? 0;
                        if (length < 8 || length > 128) {
                          return '密码长度需为 8–128 个字符';
                        }
                        return null;
                      },
                    ),
                    if (auth.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        auth.error!,
                        style: const TextStyle(color: AppColors.vermilion),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: auth.busy ? null : _submit,
                      child: auth.busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_register ? '创建账号' : '进入训练台'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: auth.busy
                          ? null
                          : () => setState(() => _register = !_register),
                      child: Text(_register ? '已有账号，直接登录' : '第一次使用，创建账号'),
                    ),
                    const SizedBox(height: 34),
                    const Divider(),
                    const SizedBox(height: 18),
                    const Row(
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: AppColors.jade,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '训练视频默认只保存在本机，服务端仅处理必要音频与结构化指标。',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
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
      ),
    );
  }
}
