import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:flutter_application_1/models/app_notification.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/notification_store.dart';

/// Firebase Messaging giả: phát tin bằng StreamController, đếm số lần lắng nghe.
class FakeMessaging implements MessagingGateway {
  var listens = 0;
  late final messages = StreamController<RemoteMessage>.broadcast(
    onListen: () => listens++,
  );
  late final opened = StreamController<RemoteMessage>.broadcast(
    onListen: () => listens++,
  );
  RemoteMessage? initial;
  var status = AuthorizationStatus.notDetermined;
  var permissionRequests = 0;
  var setUps = 0;

  @override
  Stream<RemoteMessage> get onMessage => messages.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => opened.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initial;

  @override
  Future<AuthorizationStatus> permissionStatus() async => status;

  @override
  Future<AuthorizationStatus> requestPermission() async {
    permissionRequests++;
    return status = AuthorizationStatus.authorized;
  }

  @override
  Future<String?> getToken() async => 'token-gia';

  @override
  Future<void> setUp() async => setUps++;
}

/// Local notification giả: ghi lại các thông báo đã hiện.
class FakeLocal implements LocalNotifier {
  final shown = <({int id, String? title, String? body, String? payload})>[];
  void Function(String? payload)? tap;
  var inits = 0;

  @override
  Future<void> init({required void Function(String? payload) onTap}) async {
    inits++;
    tap = onTap;
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
  }) async => shown.add((id: id, title: title, body: body, payload: payload));
}

/// Lịch sử thông báo trong bộ nhớ, sắp xếp như SQLite (received_at giảm dần,
/// rồi id giảm dần). [readError] làm lần đọc kế tiếp ném lỗi; [gate] giữ lần
/// đọc lại cho tới khi được complete.
class MemoryNotificationStore implements NotificationStore {
  final rows = <AppNotification>[];
  Object? readError;
  Completer<void>? gate;
  var reads = 0;

  @override
  Future<bool> save(AppNotification n) async {
    if (rows.any((r) => r.messageId == n.messageId)) return false;
    rows.add(
      AppNotification(
        id: rows.length + 1,
        messageId: n.messageId,
        title: n.title,
        body: n.body,
        receivedAt: n.receivedAt,
        isRead: n.isRead,
      ),
    );
    return true;
  }

  @override
  Future<List<AppNotification>> read() async {
    reads++;
    final wait = gate;
    if (wait != null) await wait.future;
    final error = readError;
    if (error != null) throw error;
    return [...rows]..sort((a, b) {
      final byTime = b.receivedAt.compareTo(a.receivedAt);
      return byTime != 0 ? byTime : b.id!.compareTo(a.id!);
    });
  }

  @override
  Future<bool> markRead(String messageId) async {
    final i = rows.indexWhere((r) => r.messageId == messageId);
    if (i < 0) return false;
    final r = rows[i];
    rows[i] = AppNotification(
      id: r.id,
      messageId: r.messageId,
      title: r.title,
      body: r.body,
      receivedAt: r.receivedAt,
      isRead: true,
    );
    return true;
  }
}
