import 'package:flutter/material.dart';

import 'src/app_controller.dart';
import 'src/home_page.dart';
import 'src/login_page.dart';

void main() => runApp(const AiLibApp());

class AiLibApp extends StatefulWidget {
  const AiLibApp({super.key});

  @override
  State<AiLibApp> createState() => _AiLibAppState();
}

class _AiLibAppState extends State<AiLibApp> {
  final controller = AppController();

  @override
  void initState() {
    super.initState();
    controller.initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI-Lib',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6658d3)),
        scaffoldBackgroundColor: const Color(0xfff7f7fb),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      home: !controller.initialized
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : controller.loggedIn
          ? HomePage(controller: controller)
          : LoginPage(controller: controller),
    ),
  );
}
