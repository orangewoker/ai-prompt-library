import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_controller.dart';
import 'assets_page.dart';
import 'models.dart';
import 'ui.dart';

class RandomPage extends StatefulWidget {
  const RandomPage({required this.controller, super.key});
  final AppController controller;

  @override
  State<RandomPage> createState() => _RandomPageState();
}

class _RandomPageState extends State<RandomPage> {
  final selected = <int>{};
  final seed = TextEditingController(text: '0');
  int count = 1;
  bool busy = false;
  List<JsonMap> items = [];

  @override
  void dispose() {
    seed.dispose();
    super.dispose();
  }

  Future<void> randomize() async {
    if (selected.isEmpty) return toast(context, '至少选择一个分类');
    setState(() => busy = true);
    try {
      final result = await widget.controller.randomPrompts(
        selected.toList(),
        count,
        int.tryParse(seed.text) ?? 0,
      );
      setState(
        () => items = (result['items'] as List? ?? [])
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(),
      );
    } catch (error) {
      if (mounted) toast(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openAsset(int id) async {
    try {
      final asset = Map<String, dynamic>.from(
        await widget.controller.api!.get('/api/v1/assets/$id') as Map,
      );
      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) =>
              AssetDetail(controller: widget.controller, asset: asset),
        );
      }
    } catch (error) {
      if (mounted) toast(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
    children: [
      Text(
        '抽取完整提示词',
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
      Text(
        '多分类会合并候选池，不会拼接不同素材的提示词。',
        style: TextStyle(color: Colors.grey.shade600),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择分类', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: widget.controller.activeCategories.map((category) {
                  final id = asInt(category['id']);
                  return FilterChip(
                    label: Text(asString(category['name'])),
                    selected: selected.contains(id),
                    onSelected: (value) => setState(
                      () => value ? selected.add(id) : selected.remove(id),
                    ),
                  );
                }).toList(),
              ),
              const Divider(height: 28),
              Row(
                children: [
                  const Text('数量'),
                  Expanded(
                    child: Slider(
                      value: count.toDouble(),
                      min: 1,
                      max: 100,
                      divisions: 99,
                      label: '$count',
                      onChanged: (value) =>
                          setState(() => count = value.round()),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      '$count',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: seed,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Seed',
                  helperText: '0 为真随机，其他数字可复现',
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 50,
        child: FilledButton.icon(
          onPressed: busy ? null : randomize,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.casino_outlined),
          label: const Text('开始随机抽取'),
        ),
      ),
      const SizedBox(height: 18),
      if (items.isEmpty)
        const EmptyView(
          '等待抽取结果',
          '选择分类并开始随机抽取',
          icon: Icons.auto_awesome_outlined,
        )
      else
        ...items.map(
          (item) => Card(
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: () async {
                    try {
                      await widget.controller.saveImageToPhotos(
                        asString(item['thumbnail_url']),
                        name: 'AI-Lib-${asInt(item['asset_id'])}',
                      );
                      if (context.mounted) toast(context, '已保存到相册');
                    } catch (error) {
                      if (context.mounted) toast(context, error);
                    }
                  },
                  child: SizedBox(
                    height: 170,
                    width: double.infinity,
                    child: NetworkImageView(
                      controller: widget.controller,
                      path: asString(item['thumbnail_url']),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#${asInt(item['asset_id'])}',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            asString(item['category_name']),
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: asString(item['prompt'])),
                              );
                              if (context.mounted) toast(context, '已复制');
                            },
                            icon: const Icon(Icons.copy_outlined),
                          ),
                          IconButton(
                            onPressed: () => openAsset(asInt(item['asset_id'])),
                            icon: const Icon(Icons.open_in_new),
                          ),
                        ],
                      ),
                      Text(asString(item['prompt'])),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
