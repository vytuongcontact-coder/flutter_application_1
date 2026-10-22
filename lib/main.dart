import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'routers/app_router.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifications = await _initNotifications();
  runApp(const MyApp());
  if (notifications != null) unawaited(_afterLaunch(notifications));
}

/// Khởi tạo Firebase và nhận thông báo. Lỗi thì app vẫn chạy, chỉ không có
/// thông báo (Login, Tin tức, Menu, Điểm danh không phụ thuộc Firebase).
Future<NotificationService?> _initNotifications() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Phải đăng ký trước runApp để tin đến khi app chạy nền được xử lý.
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    final service = NotificationService.firebase();
    await service.start();
    return service;
  } catch (error) {
    debugPrint('Không khởi tạo được Firebase Messaging: $error');
    return null;
  }
}

// In FCM token ra log của máy chỉ khi cần gửi thử từ Firebase Console:
// flutter run --dart-define=PRINT_FCM_TOKEN=true (chỉ bản debug).
const _printFcmToken = bool.fromEnvironment('PRINT_FCM_TOKEN');

// Sau khi app đã hiện: xin quyền thông báo (chỉ lần đầu).
Future<void> _afterLaunch(NotificationService notifications) async {
  try {
    final status = await notifications.requestPermissionIfNeeded();
    debugPrint('Quyền thông báo: ${status.name}');
    if (kDebugMode && _printFcmToken) {
      debugPrint('FCM token: ${await notifications.token()}');
    }
  } catch (error) {
    debugPrint('Không xin được quyền thông báo hoặc FCM token: $error');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router = createAppRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'UEH Student',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF005A68)),
      useMaterial3: true,
    ),
    routerConfig: _router,
  );
}
