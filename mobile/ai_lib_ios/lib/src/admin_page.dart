import 'package:flutter/material.dart';

import 'admin_resources.dart';
import 'admin_system.dart';
import 'app_controller.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({required this.controller, super.key});
  final AppController controller;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String section = 'categories';
  static const sections = {
    'categories': '分类管理',
    'providers': 'AI 服务管理',
    'profiles': '系统提示词模板',
    'jobs': '分析任务',
    'backup': '导入导出',
    'users': '账号管理',
    'settings': '系统设置',
  };

  Widget page() => switch (section) {
    'providers' => ProvidersAdmin(controller: widget.controller),
    'profiles' => ProfilesAdmin(controller: widget.controller),
    'jobs' => JobsAdmin(controller: widget.controller),
    'backup' => BackupAdmin(controller: widget.controller),
    'users' => UsersAdmin(controller: widget.controller),
    'settings' => SettingsAdmin(controller: widget.controller),
    _ => CategoriesAdmin(controller: widget.controller),
  };

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: DropdownButtonFormField<String>(
          initialValue: section,
          decoration: const InputDecoration(
            labelText: '管理模块',
            prefixIcon: Icon(Icons.tune),
          ),
          items: sections.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: (value) => setState(() => section = value ?? section),
        ),
      ),
      Expanded(child: page()),
    ],
  );
}
