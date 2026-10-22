import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/services/notification_service.dart';

import 'notification_fakes.dart';

RemoteMessage _message(String? id, {String? title, String? body}) =>
    RemoteMessage(
      messageId: id,
      notification: title == null && body == null
          ? null
          : RemoteNotification(title: title, body: body),
      data: title == null && body == null ? const {'loai': 'data'} : const {},
    );

void main() {
  late FakeMessaging messaging;
  late FakeLocal local;
  late List<RemoteMessage> received;
  late List<RemoteMessage> opened;

  NotificationService service({bool showWhenForeground = true}) {
    final s = NotificationService(
      messaging: messaging,
      local: local,
      showWhenForeground: showWhenForeground,
      onReceived: received.add,
      onOpened: opened.add,
    );
    addTearDown(s.dispose);
    return s;
  }

  // Tin phát qua broadcast stream được xử lý ở microtask kế tiếp.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    messaging = FakeMessaging();
    local = FakeLocal();
    received = [];
    opened = [];
  });

  test(
    'Gọi start nhiều lần: chỉ đăng ký lắng nghe và khởi tạo một lần',
    () async {
      final s = service();
      await Future.wait([s.start(), s.start()]);
      await s.start();
      expect(messaging.listens, 2); // onMessage + onMessageOpenedApp
      expect(local.inits, 1);
      expect(messaging.setUps, 1);
    },
  );

  test(
    'Tin có notification khi app đang mở: hiện một local notification',
    () async {
      await service().start();
      messaging.messages.add(
        _message(
          'm1',
          title: 'UEH Student - Firebase Test',
          body: 'Kiểm tra thông báo Firebase Cloud Messaging',
        ),
      );
      await flush();
      expect(local.shown, hasLength(1));
      expect(local.shown.single.title, 'UEH Student - Firebase Test');
      expect(
        local.shown.single.body,
        'Kiểm tra thông báo Firebase Cloud Messaging',
      );
      expect(local.shown.single.payload, 'm1');
      expect(received.map((m) => m.messageId), ['m1']);
    },
  );

  test('Cùng message ID đến hai lần: không hiện và không báo trùng', () async {
    await service().start();
    messaging.messages
      ..add(_message('m1', title: 'A', body: 'a'))
      ..add(_message('m1', title: 'A', body: 'a'))
      ..add(_message('m2', title: 'B', body: 'b'));
    await flush();
    expect(local.shown.map((n) => n.payload), ['m1', 'm2']);
    expect(local.shown.map((n) => n.id).toSet(), hasLength(2));
    expect(received.map((m) => m.messageId), ['m1', 'm2']);
  });

  test('Tin chỉ có data: báo đã nhận nhưng không hiện thông báo', () async {
    await service().start();
    messaging.messages.add(_message('d1'));
    await flush();
    expect(local.shown, isEmpty);
    expect(received.map((m) => m.messageId), ['d1']);
  });

  test('iOS (hệ thống tự hiện khi app mở): service không hiện thêm', () async {
    await service(showWhenForeground: false).start();
    messaging.messages.add(_message('m1', title: 'A', body: 'a'));
    await flush();
    expect(local.shown, isEmpty);
    expect(received, hasLength(1));
  });

  test('Mở app từ thông báo khi app đã đóng: báo onOpened một lần', () async {
    messaging.initial = _message('m9', title: 'A', body: 'a');
    await service().start();
    // Cùng tin đến lại qua onMessageOpenedApp: không báo trùng.
    messaging.opened.add(_message('m9', title: 'A', body: 'a'));
    await flush();
    expect(opened.map((m) => m.messageId), ['m9']);
    expect(local.shown, isEmpty); // hệ thống đã hiện, app không hiện thêm
  });

  test('Chạm thông báo khi app chạy nền: báo onOpened cho từng tin', () async {
    await service().start();
    messaging.opened
      ..add(_message('m1', title: 'A', body: 'a'))
      ..add(_message('m2', title: 'B', body: 'b'))
      ..add(_message('m1', title: 'A', body: 'a'));
    await flush();
    expect(opened.map((m) => m.messageId), ['m1', 'm2']);
  });

  test(
    'Chạm local notification đã hiện: báo đúng tin, chạm lại không trùng',
    () async {
      await service().start();
      messaging.messages.add(_message('m1', title: 'A', body: 'a'));
      await flush();
      local.tap!('m1');
      local.tap!('m1');
      local.tap!('khong-co');
      expect(opened.map((m) => m.messageId), ['m1']);
    },
  );

  group('Quyền thông báo', () {
    test('Chưa hỏi bao giờ: xin quyền một lần', () async {
      final s = service();
      expect(
        await s.requestPermissionIfNeeded(),
        AuthorizationStatus.authorized,
      );
      expect(
        await s.requestPermissionIfNeeded(),
        AuthorizationStatus.authorized,
      );
      expect(messaging.permissionRequests, 1);
    });

    test('Đã từ chối hoặc đã cho phép: không hỏi lại', () async {
      for (final status in [
        AuthorizationStatus.denied,
        AuthorizationStatus.authorized,
      ]) {
        messaging.status = status;
        expect(await service().requestPermissionIfNeeded(), status);
      }
      expect(messaging.permissionRequests, 0);
    });
  });

  test('Khởi động lại app: local notification ID của service mới không trùng tin cũ còn trên khay', () async {
    final t0 = DateTime(2026, 10, 22, 23, 18, 16);
    final first = NotificationService(
      messaging: messaging,
      local: local,
      showWhenForeground: true,
      clock: () => t0,
    );
    await first.start();
    messaging.messages.add(_message('A', title: 'Tin A', body: 'a'));
    await flush();
    await first.dispose();

    // App khởi động lại: service và Firebase mới; khay thông báo vẫn giữ tin A.
    final restarted = FakeMessaging();
    final second = NotificationService(
      messaging: restarted,
      local: local,
      showWhenForeground: true,
      clock: () => t0.add(const Duration(seconds: 30)),
    );
    addTearDown(second.dispose);
    await second.start();
    restarted.messages.add(_message('B', title: 'Tin B', body: 'b'));
    await flush();

    expect(local.shown.map((n) => n.payload), ['A', 'B']);
    expect(local.shown[0].id, isNot(local.shown[1].id));
  });

  test('Local notification ID luôn là số nguyên 32 bit không âm, quay vòng ở 2^31 - 1', () async {
    const limit = 0x7fffffff;
    // Mốc thời gian để ID khởi đầu đúng bằng limit - 1.
    final start = DateTime.fromMillisecondsSinceEpoch(limit * 1000 + limit - 1);
    final s = NotificationService(
      messaging: messaging,
      local: local,
      showWhenForeground: true,
      clock: () => start,
    );
    addTearDown(s.dispose);
    await s.start();
    for (final id in ['m1', 'm2', 'm3']) {
      messaging.messages.add(_message(id, title: id, body: id));
    }
    await flush();
    expect(local.shown.map((n) => n.id), [limit - 1, 0, 1]);
  });

  test('dispose: không nhận tin nữa', () async {
    final s = service();
    await s.start();
    await s.dispose();
    messaging.messages.add(_message('m1', title: 'A', body: 'a'));
    await flush();
    expect(local.shown, isEmpty);
    expect(received, isEmpty);
  });
}
