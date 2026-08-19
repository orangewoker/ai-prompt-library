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
        scaffoldBackgroundColor: const Color(0xfff4f2fb),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white.withValues(alpha: .60),
          surfaceTintColor: Colors.white.withValues(alpha: .22),
          shadowColor: const Color(0x226658d3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: Colors.white.withValues(alpha: .72)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white.withValues(alpha: .56),
          surfaceTintColor: Colors.transparent,
          indicatorColor: Colors.white.withValues(alpha: .85),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: .72),
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
