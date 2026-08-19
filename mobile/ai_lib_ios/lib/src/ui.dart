import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_controller.dart';
import 'models.dart';

void toast(BuildContext context, Object value) {
  final text = value is ApiException ? value.message : value.toString();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
  );
}

Future<bool> confirm(BuildContext context, String text) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('请确认'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    ) ??
    false;

String statusText(Object? value) =>
    const {
      'pending': '待分析',
      'processing': '分析中',
      'completed': '已完成',
      'failed': '失败',
    }[value] ??
    asString(value, '未知');

Color statusColor(Object? value) =>
    const {
      'pending': Colors.orange,
      'processing': Colors.blue,
      'completed': Colors.green,
      'failed': Colors.red,
    }[value] ??
    Colors.grey;

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final Object? status;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: statusColor(status),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      statusText(status),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class NetworkImageView extends StatelessWidget {
  const NetworkImageView({
    required this.controller,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    super.key,
  });
  final AppController controller;
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: const Icon(Icons.image_not_supported_outlined),
      );
    }
    return Image.network(
      controller.api!.mediaUri(path).toString(),
      headers: controller.api!.headers,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView(
    this.title,
    this.subtitle, {
    this.icon = Icons.inbox_outlined,
    super.key,
  });
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 24),
    child: Column(
      children: [
        Icon(icon, size: 52, color: Colors.grey.shade400),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600),
        ),
      ],
    ),
  );
}
