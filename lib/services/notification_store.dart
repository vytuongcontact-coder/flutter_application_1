import 'package:flutter/foundation.dart';

import '../helpers/DBUtils.dart';
import '../models/app_notification.dart';

/// Nơi lưu lịch sử thông báo. Tách interface để test thay SQLite bằng bản giả.
abstract interface class NotificationStore {
  /// Lưu thông báo; trả về false nếu message ID đã có (không ghi đè, không trùng).
  Future<bool> save(AppNotification notification);

  /// Lịch sử thông báo, mới nhất trước.
  Future<List<AppNotification>> read();

  /// Đánh dấu đã đọc; trả về false nếu không có thông báo này.
  Future<bool> markRead(String messageId);
}

class SqliteNotificationStore implements NotificationStore {
  const SqliteNotificationStore();

  @override
  Future<bool> save(AppNotification notification) =>
      DBUtils.insertNotification(notification);
  @override
  Future<List<AppNotification>> read() => DBUtils.getNotifications();
  @override
  Future<bool> markRead(String messageId) =>
      DBUtils.markNotificationRead(messageId);
}

/// Lịch sử thông báo của isolate chính: ghi/đọc qua [store] và báo cho giao
/// diện (tab Thông báo) sau mỗi lần ghi mới hoặc đánh dấu đã đọc thành công.
///
/// Background handler chạy ở isolate khác, ghi thẳng SQLite nên không báo được
/// tới đây; tab Thông báo đọc lại khi app trở lại foreground.
class NotificationHistory extends ChangeNotifier implements NotificationStore {
  NotificationHistory(this.store);

  final NotificationStore store;

  @override
  Future<bool> save(AppNotification notification) async {
    final saved = await store.save(notification);
    if (saved) notifyListeners();
    return saved;
  }

  @override
  Future<List<AppNotification>> read() => store.read();

  @override
  Future<bool> markRead(String messageId) async {
    final changed = await store.markRead(messageId);
    if (changed) notifyListeners();
    return changed;
  }
}

/// Dùng chung giữa NotificationService (ghi) và tab Thông báo (đọc).
final notificationHistory = NotificationHistory(
  const SqliteNotificationStore(),
);
