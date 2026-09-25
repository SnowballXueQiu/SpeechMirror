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
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;

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
                  TextField(
                    controller: _username,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '用户名',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
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
                    onPressed: auth.busy
                        ? null
                        : () => auth.submit(
                            _username.text,
                            _password.text,
                            register: _register,
                          ),
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
    );
  }
}
