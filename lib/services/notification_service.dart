import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification.dart';
import 'notification_store.dart';

/// Kênh thông báo Android của app. Thông báo FCM do Android tự hiển thị khi app
/// chạy nền cũng dùng kênh này (meta-data default_notification_channel_id
/// trong AndroidManifest.xml).
const notificationChannel = AndroidNotificationChannel(
  'ueh_student_notifications',
  'Thông báo UEH Student',
  description: 'Thông báo gửi từ Firebase Cloud Messaging',
  importance: Importance.high,
);

/// Nhận tin FCM khi app chạy nền hoặc đã đóng và lưu vào lịch sử SQLite.
/// Chạy trong isolate riêng: không có BuildContext, không gọi setState; DBUtils
/// mở kết nối riêng của isolate này tới cùng file student_app.db.
///
/// Tin có phần `notification` (gửi từ Firebase Console) được Android tự hiển
/// thị trên khay thông báo, nên ở đây không tạo thêm local notification (tránh
/// hiện hai lần). Tin chỉ có `data` thì Android không hiển thị gì.
/// Android có thể không gọi hàm này (app bị buộc dừng, tiết kiệm pin...), nên
/// tin còn được lưu lại khi người dùng chạm thông báo (xem [NotificationService]).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await saveMessage(
    const SqliteNotificationStore(),
    message,
    source: 'background',
  );
}

var _fallbackKeys = 0;

/// Khóa chống trùng của một tin: FCM message ID.
///
/// Tin không có message ID (hiếm, FCM luôn gửi kèm): dùng thời điểm gửi
/// `sentTime` cùng tiêu đề và nội dung, nên cùng một tin đến qua nhiều callback
/// vẫn một khóa. Không có cả `sentTime` thì mỗi lần nhận là một khóa mới: không
/// mất tin, nhưng cùng tin đến qua hai callback sẽ thành hai dòng.
String storageKey(
  RemoteMessage message,
  String title,
  String body,
  DateTime now,
) {
  final id = message.messageId;
  if (id != null && id.isNotEmpty) return id;
  final sent = message.sentTime;
  if (sent != null) return 'sent:${sent.millisecondsSinceEpoch}:$title:$body';
  return 'local:${now.microsecondsSinceEpoch}:${_fallbackKeys++}';
}

/// Bản ghi lịch sử của một tin; null nếu không có tiêu đề lẫn nội dung (tin chỉ
/// có data, không có gì để hiển thị trong tab Thông báo).
AppNotification? notificationFromMessage(RemoteMessage message, DateTime now) {
  String text(String? fromNotification, String key) {
    final fromData = message.data[key];
    return (fromNotification ?? (fromData is String ? fromData : '')).trim();
  }

  final title = text(message.notification?.title, 'title');
  final body = text(message.notification?.body, 'body');
  if (title.isEmpty && body.isEmpty) return null;
  return AppNotification(
    messageId: storageKey(message, title, body, now),
    title: title,
    body: body,
    receivedAt: now,
  );
}

/// Lưu tin vào lịch sử; trả về true nếu ghi mới. Message ID đã có thì bỏ qua.
/// Lỗi SQLite chỉ ghi log, không ném ra (không làm hỏng việc hiện thông báo).
///
/// Bản debug in nguồn callback và message ID (không in nội dung, token) để
/// kiểm chứng callback nào đã chạy; bản release không in.
Future<bool> saveMessage(
  NotificationStore store,
  RemoteMessage message, {
  required String source,
  DateTime? now,
}) async {
  final notification = notificationFromMessage(message, now ?? DateTime.now());
  if (notification == null) {
    if (kDebugMode) {
      debugPrint(
        'FCM $source: ${message.messageId} (bỏ qua: không có nội dung)',
      );
    }
    return false;
  }
  try {
    final saved = await store.save(notification);
    if (kDebugMode) {
      debugPrint(
        'FCM $source: ${notification.messageId} (${saved ? 'đã lưu' : 'đã có'})',
      );
    }
    return saved;
  } catch (error) {
    if (kDebugMode) {
      debugPrint('FCM $source: ${notification.messageId} (lỗi lưu: $error)');
    }
    return false;
  }
}

/// Phần Firebase Messaging mà [NotificationService] dùng; tách ra để test thay
/// bằng bản giả, không cần Firebase thật.
abstract class MessagingGateway {
  Stream<RemoteMessage> get onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp;
  Future<RemoteMessage?> getInitialMessage();
  Future<AuthorizationStatus> permissionStatus();
  Future<AuthorizationStatus> requestPermission();
  Future<String?> getToken();

  /// Cấu hình riêng nền tảng trước khi nhận tin (iOS: cách hiện tin khi app mở).
  Future<void> setUp();
}

class FirebaseMessagingGateway implements MessagingGateway {
  FirebaseMessagingGateway([FirebaseMessaging? messaging])
    : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();

  @override
  Future<AuthorizationStatus> permissionStatus() async =>
      (await _messaging.getNotificationSettings()).authorizationStatus;

  @override
  Future<AuthorizationStatus> requestPermission() async =>
      (await _messaging.requestPermission()).authorizationStatus;

  // Firebase Console ("Send test message") gửi tới FCM registration token nên
  // vẫn dùng getToken(); register()/onRegistered (bản 17) trả về Firebase
  // Installation ID cho việc gửi trực tiếp từ backend, app không dùng.
  @override
  // ignore: deprecated_member_use
  Future<String?> getToken() => _messaging.getToken();

  // iOS tự hiện banner khi app đang mở (app không tự hiện thêm). Android bỏ qua.
  @override
  Future<void> setUp() =>
      _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
}

/// Hiển thị thông báo cục bộ (flutter_local_notifications).
abstract class LocalNotifier {
  /// [onTap] nhận payload (message ID) khi người dùng chạm thông báo đã hiện.
  Future<void> init({required void Function(String? payload) onTap});

  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
  });
}

class FlutterLocalNotifier implements LocalNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();

  @override
  Future<void> init({required void Function(String? payload) onTap}) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Quyền thông báo xin qua FirebaseMessaging, không xin lúc khởi tạo.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) => onTap(response.payload),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(notificationChannel);
  }

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    payload: payload,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        notificationChannel.id,
        notificationChannel.name,
        channelDescription: notificationChannel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

/// Nhận thông báo Firebase Cloud Messaging, hiển thị khi app đang mở và lưu
/// lịch sử vào [store] (SQLite).
///
/// - App đang mở (foreground): FCM không tự hiện thông báo trên Android, nên
///   service hiện bằng flutter_local_notifications (mỗi message ID một lần).
///   iOS tự hiện (xem [FirebaseMessagingGateway.setUp]), service không hiện thêm.
/// - App chạy nền/đã đóng: Android tự hiện; xem
///   [firebaseMessagingBackgroundHandler].
/// - Chạm thông báo: [FirebaseMessaging.onMessageOpenedApp] (app đang nền),
///   [FirebaseMessaging.getInitialMessage] (app đã đóng) hoặc chạm thông báo do
///   service hiện; mỗi message ID chỉ báo [onOpened] một lần. Tin cũng được lưu
///   nếu chưa có (ví dụ background handler không chạy).
///
/// Mọi đường đều lưu qua [saveMessage]: cùng message ID chỉ có một dòng.
class NotificationService {
  NotificationService({
    required this.messaging,
    required this.local,
    this.store,
    bool? showWhenForeground,
    this.onReceived,
    this.onOpened,
    DateTime Function()? clock,
  }) : _showWhenForeground =
           showWhenForeground ??
           defaultTargetPlatform == TargetPlatform.android,
       _nextLocalId =
           (clock ?? DateTime.now)().millisecondsSinceEpoch % _localIdLimit;

  factory NotificationService.firebase({
    void Function(RemoteMessage message)? onReceived,
    void Function(RemoteMessage message)? onOpened,
  }) => NotificationService(
    messaging: FirebaseMessagingGateway(),
    local: FlutterLocalNotifier(),
    store: notificationHistory,
    onReceived: onReceived,
    onOpened: onOpened,
  );

  final MessagingGateway messaging;
  final LocalNotifier local;

  /// Nơi lưu lịch sử; null thì chỉ hiển thị, không lưu.
  final NotificationStore? store;
  final bool _showWhenForeground;

  /// Tin nhận được khi app đang mở (mỗi message ID một lần).
  final void Function(RemoteMessage message)? onReceived;

  /// Người dùng chạm thông báo để mở app (mỗi message ID một lần).
  final void Function(RemoteMessage message)? onOpened;

  final _subscriptions = <StreamSubscription<RemoteMessage>>[];
  final _receivedIds = <String>{};
  final _openedIds = <String>{};
  // Tin đã hiện bằng local notification, để biết tin nào khi người dùng chạm.
  final _shown = <String, RemoteMessage>{};
  // ID của local notification (Android cần số nguyên 32 bit, không âm ở đây).
  // Bắt đầu từ mili-giây hiện tại (chia lấy dư 2^31 - 1) rồi tăng dần, nên sau
  // khi app khởi động lại không quay về 0 và đè lên thông báo cũ còn trên khay.
  // Chỉ trùng khi lần khởi động sau bắt đầu trong khoảng ID lần trước đã dùng:
  // phải mở lại app trong vài mili-giây sau khi hiện từng ấy tin, hoặc đúng chu
  // kỳ ~24,8 ngày (2^31 ms) — gần như không xảy ra.
  static const _localIdLimit = 0x7fffffff;
  int _nextLocalId;
  Future<void>? _starting;

  /// Đăng ký lắng nghe FCM. Gọi nhiều lần vẫn chỉ đăng ký một lần.
  Future<void> start() => _starting ??= _start();

  Future<void> _start() async {
    await messaging.setUp();
    await local.init(onTap: _onLocalTap);
    _subscriptions
      ..add(messaging.onMessage.listen(_onForeground))
      ..add(
        messaging.onMessageOpenedApp.listen(
          (message) => _onOpenedMessage(message, 'onMessageOpenedApp'),
        ),
      );
    // App được mở từ trạng thái đã đóng bằng cách chạm thông báo.
    final initial = await messaging.getInitialMessage();
    if (initial != null) await _onOpenedMessage(initial, 'getInitialMessage');
  }

  /// Xin quyền thông báo (Android 13+, iOS) đúng một lần: chỉ hỏi khi chưa hỏi
  /// bao giờ. Đã cho phép hoặc đã từ chối thì không hỏi lại; người dùng có thể
  /// bật lại trong Cài đặt.
  Future<AuthorizationStatus> requestPermissionIfNeeded() async {
    final status = await messaging.permissionStatus();
    if (status != AuthorizationStatus.notDetermined) return status;
    return messaging.requestPermission();
  }

  /// FCM registration token của máy, dùng gửi thử từ Firebase Console.
  Future<String?> token() => messaging.getToken();

  Future<void> _onForeground(RemoteMessage message) async {
    final id = message.messageId;
    if (id != null && !_receivedIds.add(id)) return; // đã xử lý tin này
    onReceived?.call(message);
    // Lưu song song với việc hiện thông báo: SQLite lỗi hay chậm không chặn hiển thị.
    final saving = _save(message, 'onMessage');
    final notification = message.notification;
    // Tin chỉ có data: không có tiêu đề/nội dung để hiển thị.
    if (_showWhenForeground && notification != null) {
      if (id != null) _shown[id] = message;
      final localId = _nextLocalId;
      _nextLocalId = (_nextLocalId + 1) % _localIdLimit;
      await local.show(
        id: localId,
        title: notification.title,
        body: notification.body,
        payload: id,
      );
    }
    await saving;
  }

  Future<void> _onOpenedMessage(RemoteMessage message, String source) async {
    final id = message.messageId;
    if (id != null && !_openedIds.add(id)) return;
    onOpened?.call(message);
    await _save(message, source);
  }

  // Chỉ nhận chạm khi app còn chạy. Chạm local notification lúc app đã đóng hẳn
  // (getNotificationAppLaunchDetails) chưa xử lý: giới hạn đã biết, chưa kiểm thử.
  void _onLocalTap(String? payload) {
    final message = _shown[payload];
    if (message != null) _onOpenedMessage(message, 'local_notification');
  }

  Future<void> _save(RemoteMessage message, String source) async {
    final store = this.store;
    if (store != null) await saveMessage(store, message, source: source);
  }

  /// Huỷ lắng nghe (dùng trong test hoặc khi đóng app).
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}
