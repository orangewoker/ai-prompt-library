import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui.dart';

class JobsAdmin extends StatelessWidget {
  const JobsAdmin({required this.controller, super.key});
  final AppController controller;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: controller.loadJobs,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
      children: [
        if (controller.jobs.isEmpty)
          const EmptyView('暂无分析任务', '上传图片后，后台任务会显示在这里', icon: Icons.task_alt)
        else
          ...controller.jobs.map(
            (job) => Card(
              child: ListTile(
                leading: Icon(
                  job['status'] == 'completed'
                      ? Icons.check_circle
                      : job['status'] == 'failed'
                      ? Icons.error
                      : Icons.hourglass_top,
                  color: statusColor(job['status']),
                ),
                title: Text(
                  '#${asInt(job['asset_id'])}  ${asString(job['original_filename'], '素材')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${asString(job['category_name'])} · ${statusText(job['status'])}${asString(job['error_message']).isEmpty ? '' : '\n${asString(job['error_message'])}'}',
                ),
                trailing: job['status'] == 'failed'
                    ? IconButton(
                        onPressed: () async {
                          try {
                            await controller.reanalyzeAsset(
                              asInt(job['asset_id']),
                            );
                            if (context.mounted) toast(context, '已重新加入队列');
                          } catch (error) {
                            if (context.mounted) toast(context, error);
                          }
                        },
                        icon: const Icon(Icons.refresh),
                      )
                    : null,
              ),
            ),
          ),
      ],
    ),
  );
}

class BackupAdmin extends StatelessWidget {
  const BackupAdmin({required this.controller, super.key});
  final AppController controller;

  Future<void> run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
      if (context.mounted) toast(context, '已打开系统分享面板');
    } catch (error) {
      if (context.mounted) toast(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
    children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: const Text(
            '完整数据备份',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: const Text('包含 SQLite 数据库、图片和缩略图'),
          trailing: FilledButton(
            onPressed: () => run(context, controller.shareBackup),
            child: const Text('分享'),
          ),
        ),
      ),
      const SizedBox(height: 10),
      const Text('按分类导出 JSON', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      ...controller.categories.map(
        (category) => Card(
          child: ListTile(
            leading: const Icon(Icons.data_object),
            title: Text(asString(category['name'])),
            subtitle: Text('${asInt(category['asset_count'])} 条素材'),
            trailing: IconButton(
              onPressed: () => run(
                context,
                () => controller.shareCategoryExport(asInt(category['id'])),
              ),
              icon: const Icon(Icons.ios_share_outlined),
            ),
          ),
        ),
      ),
    ],
  );
}

class UsersAdmin extends StatelessWidget {
  const UsersAdmin({required this.controller, super.key});
  final AppController controller;

  Future<void> edit(BuildContext context, [JsonMap? item]) async {
    final username = TextEditingController(text: asString(item?['username']));
    final password = TextEditingController();
    var role = asString(item?['role'], 'user');
    var enabled = asBool(item?['enabled'], true);
    final categoryIds = (item?['category_ids'] as List? ?? [])
        .map(asInt)
        .toSet();
    final save = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(item == null ? '新增账号' : '编辑账号'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: username,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: item == null ? '初始密码（至少 6 位）' : '新密码（留空不修改）',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: '角色'),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('管理员')),
                    DropdownMenuItem(value: 'user', child: Text('普通用户')),
                  ],
                  onChanged: (value) => setLocal(() => role = value ?? role),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用'),
                  value: enabled,
                  onChanged: (value) => setLocal(() => enabled = value),
                ),
                if (role == 'user') ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '可见分类',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  ...controller.categories.map((category) {
                    final id = asInt(category['id']);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(asString(category['name'])),
                      value: categoryIds.contains(id),
                      onChanged: (value) => setLocal(
                        () => value == true
                            ? categoryIds.add(id)
                            : categoryIds.remove(id),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (save != true ||
        username.text.trim().isEmpty ||
        (item == null && password.text.length < 6)) {
      return;
    }
    try {
      final body = <String, dynamic>{
        'username': username.text.trim(),
        'role': role,
        'enabled': enabled,
        'category_ids': categoryIds.toList(),
      };
      if (password.text.isNotEmpty) body['password'] = password.text;
      item == null
          ? await controller.createUser(body)
          : await controller.updateUser(asInt(item['id']), body);
      if (context.mounted) toast(context, '账号已保存');
    } catch (error) {
      if (context.mounted) toast(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
    children: [
      FilledButton.icon(
        onPressed: () => edit(context),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('新增账号'),
      ),
      const SizedBox(height: 8),
      ...controller.users.map(
        (user) => Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(asString(user['username'], 'U')[0].toUpperCase()),
            ),
            title: Text(
              asString(user['username']),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${user['role'] == 'admin' ? '管理员' : '普通用户'} · ${asBool(user['enabled'], true) ? '启用' : '停用'}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) async {
                if (action == 'edit') return edit(context, user);
                if (await confirm(context, '确定删除该账号？')) {
                  try {
                    await controller.deleteUser(asInt(user['id']));
                  } catch (error) {
                    if (context.mounted) toast(context, error);
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class SettingsAdmin extends StatefulWidget {
  const SettingsAdmin({required this.controller, super.key});
  final AppController controller;

  @override
  State<SettingsAdmin> createState() => _SettingsAdminState();
}

class _SettingsAdminState extends State<SettingsAdmin> {
  late final server = TextEditingController(text: widget.controller.baseUrl);
  final comfyKey = TextEditingController();
  String health = '未检测';

  @override
  void dispose() {
    server.dispose();
    comfyKey.dispose();
    super.dispose();
  }

  Future<void> check() async {
    setState(() => health = '检测中…');
    try {
      await widget.controller.api!.get('/api/v1/health');
      setState(() => health = '服务正常');
    } catch (_) {
      setState(() => health = '无法连接');
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '服务连接',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: server,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'API 服务地址'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('状态：$health')),
                  OutlinedButton.icon(
                    onPressed: check,
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('检测'),
                  ),
                ],
              ),
              FilledButton(
                onPressed: () async {
                  await widget.controller.setBaseUrl(server.text);
                  if (context.mounted) toast(context, '地址已保存');
                },
                child: const Text('保存服务地址'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ComfyUI 访问密钥',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              Text(
                '当前：${asString(widget.controller.settings['comfyui_api_key_masked'], '未设置')}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: comfyKey,
                obscureText: true,
                decoration: const InputDecoration(labelText: '新密钥'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  if (comfyKey.text.isEmpty) return toast(context, '请输入新密钥');
                  try {
                    await widget.controller.updateSettings(comfyKey.text);
                    comfyKey.clear();
                    if (context.mounted) toast(context, '密钥已更新');
                  } catch (error) {
                    if (context.mounted) toast(context, error);
                  }
                },
                child: const Text('更新密钥'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
