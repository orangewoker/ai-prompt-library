import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'ui.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({required this.controller, super.key});
  final AppController controller;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final server = TextEditingController(text: widget.controller.baseUrl);
  final username = TextEditingController(text: 'admin');
  final password = TextEditingController();
  bool hide = true;

  @override
  void dispose() {
    server.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (server.text.trim().isEmpty ||
        username.text.trim().isEmpty ||
        password.text.isEmpty) {
      toast(context, '请填写服务地址、账号和密码');
      return;
    }
    try {
      await widget.controller.login(
        server.text,
        username.text.trim(),
        password.text,
      );
    } catch (error) {
      if (mounted) toast(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: Colors.white,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'AI-Lib',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'AI 图片反推提示词素材库',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: server,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: '服务端地址',
                    hintText: 'http://192.168.1.10:8765',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: username,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: '账号',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: hide,
                  onSubmitted: (_) => login(),
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => hide = !hide),
                      icon: Icon(
                        hide
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: widget.controller.busy ? null : login,
                    icon: widget.controller.busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login),
                    label: const Text('登录 AI-Lib'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'iPhone 无法访问电脑的 127.0.0.1。连接电脑或 NAS 时，请填写同一局域网可访问的 IP 地址。',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
