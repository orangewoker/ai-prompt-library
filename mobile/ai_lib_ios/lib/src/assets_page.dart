import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'app_controller.dart';
import 'models.dart';
import 'ui.dart';

class AssetsPage extends StatefulWidget {
  const AssetsPage({required this.controller, super.key});
  final AppController controller;

  @override
  State<AssetsPage> createState() => _AssetsPageState();
}

class _AssetsPageState extends State<AssetsPage> {
  final search = TextEditingController();
  int? categoryId;
  String status = '';
  bool loading = false;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      await widget.controller.loadAssets(
        search: search.text,
        categoryId: categoryId,
        status: status,
      );
    } catch (error) {
      if (mounted) toast(context, error);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void upload() {
    if (widget.controller.categories.isEmpty) {
      toast(context, '请先在管理中心创建分类');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => UploadSheet(controller: widget.controller),
    );
  }

  void detail(JsonMap asset) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AssetDetail(controller: widget.controller, asset: asset),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: search,
                onSubmitted: (_) => load(),
                decoration: const InputDecoration(
                  hintText: '搜索文件名或提示词',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: upload,
              child: const Icon(Icons.add_a_photo_outlined),
            ),
          ],
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            FilterChip(
              label: const Text('全部'),
              selected: categoryId == null,
              onSelected: (_) {
                setState(() => categoryId = null);
                load();
              },
            ),
            const SizedBox(width: 7),
            ...widget.controller.categories.map((category) {
              final id = asInt(category['id']);
              return Padding(
                padding: const EdgeInsets.only(right: 7),
                child: FilterChip(
                  label: Text(asString(category['name'])),
                  selected: categoryId == id,
                  onSelected: (_) {
                    setState(() => categoryId = id);
                    load();
                  },
                ),
              );
            }),
            DropdownButton<String>(
              value: status,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: '', child: Text('全部状态')),
                DropdownMenuItem(value: 'completed', child: Text('已完成')),
                DropdownMenuItem(value: 'pending', child: Text('待分析')),
                DropdownMenuItem(value: 'failed', child: Text('失败')),
              ],
              onChanged: (value) {
                setState(() => status = value ?? '');
                load();
              },
            ),
          ],
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: load,
          child: widget.controller.assets.isEmpty
              ? ListView(
                  children: const [
                    EmptyView(
                      '暂无素材',
                      '点击右上角上传图片',
                      icon: Icons.photo_library_outlined,
                    ),
                  ],
                )
              : LayoutBuilder(
                  builder: (_, constraints) {
                    final columns = constraints.maxWidth >= 700
                        ? 4
                        : constraints.maxWidth >= 450
                        ? 3
                        : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 28),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 9,
                        mainAxisSpacing: 9,
                        childAspectRatio: .72,
                      ),
                      itemCount: widget.controller.assets.length,
                      itemBuilder: (_, index) {
                        final asset = widget.controller.assets[index];
                        return AssetCard(
                          controller: widget.controller,
                          asset: asset,
                          onTap: () => detail(asset),
                        );
                      },
                    );
                  },
                ),
        ),
      ),
      if (loading) const LinearProgressIndicator(minHeight: 2),
    ],
  );
}

class AssetCard extends StatelessWidget {
  const AssetCard({
    required this.controller,
    required this.asset,
    required this.onTap,
    super.key,
  });
  final AppController controller;
  final JsonMap asset;
  final VoidCallback onTap;

  Future<void> longPress(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: const Text('保存原图到相册'),
              onTap: () => Navigator.pop(context, 'save'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制提示词'),
              onTap: () => Navigator.pop(context, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('查看详情'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    try {
      if (action == 'save') {
        await controller.saveImageToPhotos(
          asString(asset['image_url']),
          name: 'AI-Lib-${asInt(asset['id'])}',
        );
        if (context.mounted) toast(context, '已保存到相册');
      } else if (action == 'copy') {
        await Clipboard.setData(
          ClipboardData(text: asString(asset['prompt_text'])),
        );
        if (context.mounted) toast(context, '提示词已复制');
      } else {
        onTap();
      }
    } catch (error) {
      if (context.mounted) toast(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onLongPress: () => longPress(context),
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetworkImageView(
                    controller: controller,
                    path: asString(asset['thumbnail_url']),
                  ),
                  Positioned(
                    left: 7,
                    top: 7,
                    child: StatusPill(asset['status']),
                  ),
                  const Positioned(
                    right: 7,
                    top: 7,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: Colors.black45,
                      child: Icon(
                        Icons.touch_app_outlined,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${asInt(asset['id'])}  ${asString(asset['category_name'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    asString(asset['original_filename']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class AssetDetail extends StatefulWidget {
  const AssetDetail({required this.controller, required this.asset, super.key});
  final AppController controller;
  final JsonMap asset;

  @override
  State<AssetDetail> createState() => _AssetDetailState();
}

class _AssetDetailState extends State<AssetDetail> {
  late final prompt = TextEditingController(
    text: asString(widget.asset['prompt_text']),
  );
  late int categoryId = asInt(widget.asset['category_id']);
  bool busy = false;

  @override
  void dispose() {
    prompt.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() task, {bool close = false}) async {
    setState(() => busy = true);
    try {
      await task();
      if (mounted) {
        toast(context, '操作成功');
        if (close) Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) toast(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> savePhoto() async {
    try {
      await widget.controller.saveImageToPhotos(
        asString(widget.asset['image_url']),
        name: 'AI-Lib-${asInt(widget.asset['id'])}',
      );
      if (mounted) toast(context, '已保存到相册');
    } catch (error) {
      if (mounted) toast(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .9,
    minChildSize: .55,
    maxChildSize: .97,
    expand: false,
    builder: (_, scroll) => Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(17, 10, 17, 28),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onLongPress: savePhoto,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 1,
                child: NetworkImageView(
                  controller: widget.controller,
                  path: asString(widget.asset['image_url']),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '#${asInt(widget.asset['id'])}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              StatusPill(widget.asset['status']),
              const Spacer(),
              IconButton(
                tooltip: '保存图片',
                onPressed: savePhoto,
                icon: const Icon(Icons.download_outlined),
              ),
              IconButton(
                tooltip: '复制提示词',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: prompt.text));
                  if (context.mounted) toast(context, '已复制');
                },
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          Text(
            asString(widget.asset['original_filename']),
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: categoryId,
            decoration: const InputDecoration(labelText: '素材分类'),
            items: widget.controller.categories
                .map(
                  (item) => DropdownMenuItem(
                    value: asInt(item['id']),
                    child: Text(asString(item['name'])),
                  ),
                )
                .toList(),
            onChanged: (value) => categoryId = value ?? categoryId,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: prompt,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: '当前提示词',
              alignLabelWithHint: true,
            ),
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('AI 原始分析'),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  asString(widget.asset['ai_original_text'], '暂无原始分析'),
                ),
              ),
            ],
          ),
          if (asString(widget.asset['error_message']).isNotEmpty)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  asString(widget.asset['error_message']),
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await widget.controller.updateAsset(
                          asInt(widget.asset['id']),
                          {
                            'prompt_text': prompt.text,
                            'category_id': categoryId,
                          },
                        );
                      }, close: true),
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => setState(
                        () => prompt.text = asString(
                          widget.asset['ai_original_text'],
                        ),
                      ),
                icon: const Icon(Icons.restore),
                label: const Text('恢复原文'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => run(
                        () => widget.controller.reanalyzeAsset(
                          asInt(widget.asset['id']),
                        ),
                      ),
                icon: const Icon(Icons.refresh),
                label: const Text('重新分析'),
              ),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        if (await confirm(context, '删除后不可恢复，确定继续？') &&
                            context.mounted) {
                          await run(
                            () => widget.controller.deleteAsset(
                              asInt(widget.asset['id']),
                            ),
                            close: true,
                          );
                        }
                      },
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class UploadSheet extends StatefulWidget {
  const UploadSheet({required this.controller, super.key});
  final AppController controller;

  @override
  State<UploadSheet> createState() => _UploadSheetState();
}

class _UploadFile {
  const _UploadFile(this.name, this.bytes, this.mime);
  final String name;
  final Uint8List bytes;
  final String mime;
}

class _UploadSheetState extends State<UploadSheet> {
  final picker = ImagePicker();
  final files = <_UploadFile>[];
  int? categoryId;
  int? providerId;
  int? profileId;
  String? model;
  bool busy = false;

  List<String> get models {
    final matching = widget.controller.providers.where(
      (item) => asInt(item['id']) == providerId,
    );
    if (matching.isEmpty) return [];
    return (matching.first['models'] as List? ?? []).map(asString).toList();
  }

  Future<void> pick(bool camera) async {
    final picked = <XFile>[];
    if (camera) {
      final one = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 95,
      );
      if (one != null) picked.add(one);
    } else {
      picked.addAll(
        await picker.pickMultiImage(
          imageQuality: 95,
          requestFullMetadata: false,
        ),
      );
    }
    for (final file in picked) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty) {
        files.add(_UploadFile(file.name, bytes, mime(file.name)));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> submit({bool force = false}) async {
    if (files.isEmpty) return toast(context, '请先选择图片');
    if (categoryId == null) return toast(context, '请选择素材分类');
    if (providerId != null && (model == null || model!.isEmpty)) {
      return toast(context, '请选择本次分析使用的模型');
    }
    setState(() => busy = true);
    try {
      final result = await widget.controller.uploadAssets(
        files
            .map(
              (file) => (
                name: 'files',
                bytes: file.bytes,
                filename: file.name,
                contentType: file.mime,
              ),
            )
            .toList(),
        categoryId: categoryId!,
        providerId: providerId,
        modelName: model,
        profileId: profileId,
        force: force,
      );
      final duplicates = result['duplicates'] as List? ?? [];
      if (duplicates.isNotEmpty && !force && mounted) {
        setState(() => busy = false);
        if (await confirm(context, '发现 ${duplicates.length} 张重复图片，仍然上传？') &&
            mounted) {
          await submit(force: true);
        }
        return;
      }
      if (mounted) {
        Navigator.pop(context);
        toast(context, '上传成功，后台正在分析');
      }
    } catch (error) {
      if (mounted) toast(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String mime(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    initialChildSize: .84,
    maxChildSize: .96,
    expand: false,
    builder: (_, scroll) => Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(17, 12, 17, 28),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '上传并提取提示词',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : () => pick(false),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('选择图片'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: busy ? null : () => pick(true),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('拍摄'),
              ),
            ],
          ),
          if (files.isEmpty)
            const EmptyView(
              '尚未选择图片',
              '支持多选和 iOS 照片库',
              icon: Icons.add_photo_alternate_outlined,
            )
          else
            Card(
              child: Column(
                children: files
                    .asMap()
                    .entries
                    .map(
                      (entry) => ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            entry.value.bytes,
                            width: 46,
                            height: 46,
                            fit: BoxFit.cover,
                          ),
                        ),
                        title: Text(
                          entry.value.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          onPressed: () =>
                              setState(() => files.removeAt(entry.key)),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          DropdownButtonFormField<int>(
            initialValue: categoryId,
            decoration: const InputDecoration(labelText: '素材分类 *'),
            items: widget.controller.categories
                .map(
                  (item) => DropdownMenuItem(
                    value: asInt(item['id']),
                    child: Text(asString(item['name'])),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => categoryId = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: providerId,
            decoration: const InputDecoration(labelText: 'AI 服务（可选）'),
            items: widget.controller.providers
                .map(
                  (item) => DropdownMenuItem(
                    value: asInt(item['id']),
                    child: Text(asString(item['name'])),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() {
              providerId = value;
              model = null;
            }),
          ),
          if (providerId != null) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: model,
              decoration: const InputDecoration(labelText: '本次视觉模型 *'),
              items: models
                  .map(
                    (name) => DropdownMenuItem(value: name, child: Text(name)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => model = value),
            ),
          ],
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: profileId,
            decoration: const InputDecoration(labelText: '系统提示词模板（可选）'),
            items: widget.controller.profiles
                .map(
                  (item) => DropdownMenuItem(
                    value: asInt(item['id']),
                    child: Text(asString(item['name'])),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => profileId = value),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: busy ? null : submit,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_outlined),
              label: const Text('上传并开始分析'),
            ),
          ),
        ],
      ),
    ),
  );
}
