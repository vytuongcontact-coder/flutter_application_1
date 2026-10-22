/// Một thông báo Firebase Cloud Messaging đã nhận, lưu trong bảng SQLite
/// `notifications` (lịch sử của tab Thông báo).
class AppNotification {
  const AppNotification({
    this.id,
    required this.messageId,
    required this.title,
    required this.body,
    required this.receivedAt,
    this.isRead = false,
  });

  /// Khóa chính nội bộ do SQLite cấp; null khi chưa lưu.
  final int? id;

  /// Khóa chống trùng (cột UNIQUE): FCM message ID, hoặc khóa thay thế khi
  /// tin không có message ID (xem `NotificationService.storageKey`).
  final String messageId;
  final String title;
  final String body;

  /// Thời điểm app ghi nhận tin lần đầu.
  final DateTime receivedAt;
  final bool isRead;

  /// Đọc một dòng của bảng SQLite `notifications`.
  ///
  /// `received_at` lưu số mili-giây (UTC) để sắp xếp đúng bằng ORDER BY.
  factory AppNotification.fromMap(Map<String, Object?> map) => AppNotification(
    id: map['id'] as int,
    messageId: map['message_id'] as String,
    title: map['title'] as String,
    body: map['body'] as String,
    receivedAt: DateTime.fromMillisecondsSinceEpoch(map['received_at'] as int),
    isRead: map['is_read'] == 1,
  );

  /// Dữ liệu để ghi vào bảng (không có `id`: SQLite tự cấp).
  Map<String, Object?> toMap() => {
    'message_id': messageId,
    'title': title,
    'body': body,
    'received_at': receivedAt.millisecondsSinceEpoch,
    'is_read': isRead ? 1 : 0,
  };
}
