import 'package:flutter/material.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui.dart';

class CategoriesAdmin extends StatelessWidget {
  const CategoriesAdmin({required this.controller, super.key});
  final AppController controller;

  Future<void> edit(BuildContext context, [JsonMap? item]) async {
    final name = TextEditingController(text: asString(item?['name']));
    final description = TextEditingController(
      text: asString(item?['description']),
    );
    final order = TextEditingController(text: '${asInt(item?['sort_order'])}');
    var enabled = asBool(item?['enabled'], true);
    final save = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(item == null ? '新增分类' : '编辑分类'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '描述'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: order,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '排序'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用'),
                  value: enabled,
                  onChanged: (value) => setLocal(() => enabled = value),
                ),
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
    if (save != true || name.text.trim().isEmpty) return;
    try {
      final body = {
        'name': name.text.trim(),
        'description': description.text,
        'sort_order': int.tryParse(order.text) ?? 0,
        'enabled': enabled,
      };
      item == null
          ? await controller.createCategory(body)
          : await controller.updateCategory(asInt(item['id']), body);
      if (context.mounted) toast(context, '分类已保存');
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
        icon: const Icon(Icons.add),
        label: const Text('新增分类'),
      ),
      const SizedBox(height: 8),
      if (controller.categories.isEmpty)
        const EmptyView('暂无分类', '创建分类后即可上传素材', icon: Icons.folder_outlined)
      else
        ...controller.categories.map(
          (item) => Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text('${asInt(item['asset_count'])}'),
              ),
              title: Text(
                asString(item['name']),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${asBool(item['enabled'], true) ? '启用' : '停用'} · ${asString(item['description'], '无描述')}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  if (action == 'edit') return edit(context, item);
                  if (await confirm(context, '分类必须为空才能删除。确定删除？')) {
                    try {
                      await controller.deleteCategory(asInt(item['id']));
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

class ProvidersAdmin extends StatelessWidget {
  const ProvidersAdmin({required this.controller, super.key});
  final AppController controller;

  Future<void> edit(BuildContext context, [JsonMap? item]) async {
    final name = TextEditingController(text: asString(item?['name']));
    final base = TextEditingController(
      text: asString(item?['base_url'], 'http://host.docker.internal:1234/v1'),
    );
    final key = TextEditingController();
    final models = TextEditingController(
      text: (item?['models'] as List? ?? []).map(asString).join('\n'),
    );
    var enabled = asBool(item?['enabled'], true);
    final save = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(item == null ? '新增 AI 服务' : '编辑 AI 服务'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '服务名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: base,
                  decoration: const InputDecoration(labelText: 'Base URL'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: key,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: item == null ? 'API Key' : 'API Key（留空保持不变）',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: models,
                  minLines: 3,
                  maxLines: 7,
                  decoration: const InputDecoration(labelText: '模型列表（每行一个）'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用'),
                  value: enabled,
                  onChanged: (value) => setLocal(() => enabled = value),
                ),
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
    if (save != true || name.text.trim().isEmpty || base.text.trim().isEmpty) {
      return;
    }
    try {
      final body = <String, dynamic>{
        'name': name.text.trim(),
        'base_url': base.text.trim(),
        'models': models.text
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        'enabled': enabled,
      };
      if (key.text.isNotEmpty) body['api_key'] = key.text;
      item == null
          ? await controller.createProvider(body)
          : await controller.updateProvider(asInt(item['id']), body);
      if (context.mounted) toast(context, 'AI 服务已保存');
    } catch (error) {
      if (context.mounted) toast(context, error);
    }
  }

  Future<void> action(BuildContext context, String action, JsonMap item) async {
    try {
      if (action == 'edit') return edit(context, item);
      if (action == 'test') {
        final result = await controller.testProvider(asInt(item['id']));
        if (context.mounted) toast(context, asString(result['message']));
      }
      if (action == 'pull') {
        final result = await controller.pullProviderModels(asInt(item['id']));
        if (context.mounted) {
          toast(context, '已拉取 ${asInt(result['count'])} 个模型');
        }
      }
      if (action == 'delete') {
        if (!context.mounted) return;
        final shouldDelete = await confirm(context, '确定删除该 AI 服务？');
        if (!context.mounted) return;
        if (shouldDelete) {
          await controller.deleteProvider(asInt(item['id']));
        }
      }
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
        icon: const Icon(Icons.add),
        label: const Text('新增 AI 服务'),
      ),
      const SizedBox(height: 8),
      if (controller.providers.isEmpty)
        const EmptyView(
          '暂无 AI 服务',
          '添加 LM Studio 或 OpenAI Compatible 服务',
          icon: Icons.hub_outlined,
        )
      else
        ...controller.providers.map(
          (item) => Card(
            child: ListTile(
              isThreeLine: true,
              leading: const CircleAvatar(child: Icon(Icons.hub_outlined)),
              title: Text(
                asString(item['name']),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${asString(item['base_url'])}\n${asString(item['api_key_masked'], '无 Key')} · ${(item['models'] as List? ?? []).length} 个模型',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) => action(context, value, item),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'test', child: Text('测试连接')),
                  PopupMenuItem(value: 'pull', child: Text('拉取模型')),
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

class ProfilesAdmin extends StatelessWidget {
  const ProfilesAdmin({required this.controller, super.key});
  final AppController controller;

  Future<void> edit(BuildContext context, [JsonMap? item]) async {
    final name = TextEditingController(text: asString(item?['name']));
    final systemPrompt = TextEditingController(
      text: asString(item?['system_prompt']),
    );
    final temperature = TextEditingController(
      text: '${item?['temperature'] ?? .2}',
    );
    final tokens = TextEditingController(
      text: '${asInt(item?['max_tokens'], 1200)}',
    );
    var enabled = asBool(item?['enabled'], true);
    final save = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(item == null ? '新增提示词模板' : '编辑提示词模板'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: '模板名称'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: systemPrompt,
                  minLines: 8,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: 'System Prompt',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: temperature,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Temperature',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: tokens,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Max Tokens',
                        ),
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用'),
                  value: enabled,
                  onChanged: (value) => setLocal(() => enabled = value),
                ),
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
        name.text.trim().isEmpty ||
        systemPrompt.text.trim().isEmpty) {
      return;
    }
    try {
      final body = {
        'name': name.text.trim(),
        'system_prompt': systemPrompt.text,
        'temperature': double.tryParse(temperature.text) ?? .2,
        'max_tokens': int.tryParse(tokens.text) ?? 1200,
        'enabled': enabled,
      };
      item == null
          ? await controller.createProfile(body)
          : await controller.updateProfile(asInt(item['id']), body);
      if (context.mounted) toast(context, '模板已保存');
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
        icon: const Icon(Icons.add),
        label: const Text('新增模板'),
      ),
      const SizedBox(height: 8),
      ...controller.profiles.map((item) {
        final text = asString(item['system_prompt']).replaceAll('\n', ' ');
        return Card(
          child: ListTile(
            isThreeLine: true,
            leading: const Icon(Icons.description_outlined),
            title: Text(
              asString(item['name']),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${asInt(item['max_tokens'])} tokens · temperature ${asString(item['temperature'])}\n${text.length > 90 ? '${text.substring(0, 90)}…' : text}',
            ),
            trailing: IconButton(
              onPressed: () => edit(context, item),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        );
      }),
    ],
  );
}
