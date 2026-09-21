import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const imagePath = 'assets/images/nso-splash-landscape-1499x999.png';
  static const displayDuration = Duration(seconds: 2);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer = Timer(SplashScreen.displayDuration, () {
        if (mounted) context.go('/home');
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF005A68),
    body: SizedBox.expand(
      child: Image.asset(
        SplashScreen.imagePath,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        semanticLabel: 'UEH - Kỷ niệm 50 năm',
      ),
    ),
  );
}
