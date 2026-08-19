import 'dart:ui' as ui;

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

class LiquidBackground extends StatelessWidget {
  const LiquidBackground({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xfff0edff), Color(0xfff9f9ff), Color(0xffeef7ff)],
          ),
        ),
      ),
      Positioned(
        top: -80,
        left: -50,
        child: _GlowOrb(color: const Color(0x996d5ce7), size: 220),
      ),
      Positioned(
        top: 220,
        right: -85,
        child: _GlowOrb(color: const Color(0x6687d8ff), size: 230),
      ),
      Positioned(
        bottom: 100,
        left: 80,
        child: _GlowOrb(color: const Color(0x55ec9ffb), size: 180),
      ),
      Positioned.fill(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 35, sigmaY: 35),
          child: Container(color: Colors.white.withValues(alpha: .18)),
        ),
      ),
      child,
    ],
  );
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      boxShadow: [BoxShadow(color: color, blurRadius: 60, spreadRadius: 20)],
    ),
  );
}

class GlassCard extends StatelessWidget {
  const GlassCard({required this.child, this.padding, super.key});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: .75)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x146658d3),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    ),
  );
}
