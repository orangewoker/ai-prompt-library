import 'package:flutter/material.dart';

import 'admin_page.dart';
import 'app_controller.dart';
import 'assets_page.dart';
import 'models.dart';
import 'random_page.dart';
import 'ui.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.controller, super.key});
  final AppController controller;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final titles = [
      '仪表盘',
      '素材库',
      '随机提示词',
      if (widget.controller.isAdmin) '管理中心',
    ];
    final pages = <Widget>[
      Dashboard(
        controller: widget.controller,
        openAssets: () => setState(() => index = 1),
        openRandom: () => setState(() => index = 2),
      ),
      AssetsPage(controller: widget.controller),
      RandomPage(controller: widget.controller),
      if (widget.controller.isAdmin) AdminPage(controller: widget.controller),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[index],
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () async {
              try {
                await widget.controller.refreshAll();
                if (context.mounted) toast(context, '已刷新');
              } catch (error) {
                if (context.mounted) toast(context, error);
              }
            },
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 16,
              child: Text(
                (widget.controller.user?.username ?? 'A')[0].toUpperCase(),
              ),
            ),
            onSelected: (value) {
              if (value == 'logout') widget.controller.logout();
              if (value == 'admin') setState(() => index = 3);
            },
            itemBuilder: (_) => [
              if (widget.controller.isAdmin)
                const PopupMenuItem(value: 'admin', child: Text('管理中心')),
              const PopupMenuItem(value: 'logout', child: Text('退出登录')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(index: index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: '仪表盘',
          ),
          const NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: '素材库',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '随机',
          ),
          if (widget.controller.isAdmin)
            const NavigationDestination(
              icon: Icon(Icons.tune_outlined),
              selectedIcon: Icon(Icons.tune),
              label: '管理',
            ),
        ],
      ),
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({
    required this.controller,
    required this.openAssets,
    required this.openRandom,
    super.key,
  });
  final AppController controller;
  final VoidCallback openAssets;
  final VoidCallback openRandom;

  @override
  Widget build(BuildContext context) {
    final active = controller.jobs
        .where((e) => ['pending', 'processing'].contains(e['status']))
        .length;
    final failed = controller.jobs.where((e) => e['status'] == 'failed').length;
    return RefreshIndicator(
      onRefresh: controller.refreshAll,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            '你好，${controller.user?.username}',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(
            '把图片变成可复用的完整提示词。',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  '素材',
                  '${controller.assetTotal}',
                  Icons.photo_library_outlined,
                  const Color(0xff6658d3),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _Metric(
                  '分析中',
                  '$active',
                  Icons.hourglass_top,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _Metric(
                  '失败',
                  '$failed',
                  Icons.error_outline,
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Shortcut(
                  Icons.add_photo_alternate_outlined,
                  '上传图片',
                  '提取视觉提示词',
                  openAssets,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Shortcut(
                  Icons.casino_outlined,
                  '随机提示词',
                  '从素材库抽取',
                  openRandom,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '最近素材',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (controller.assets.isEmpty)
            const EmptyView(
              '还没有素材',
              '进入素材库上传第一张图片',
              icon: Icons.photo_library_outlined,
            )
          else
            ...controller.assets
                .take(8)
                .map(
                  (asset) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: NetworkImageView(
                          controller: controller,
                          path: asString(asset['thumbnail_url']),
                          width: 48,
                          height: 48,
                        ),
                      ),
                      title: Text(
                        asString(
                          asset['original_filename'],
                          '素材 #${asInt(asset['id'])}',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${asString(asset['category_name'])} · ${statusText(asset['status'])}',
                      ),
                      trailing: Text('#${asInt(asset['id'])}'),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
