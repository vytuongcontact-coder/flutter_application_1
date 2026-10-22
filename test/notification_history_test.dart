import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_application_1/helpers/DBUtils.dart';
import 'package:flutter_application_1/models/app_notification.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/notification_store.dart';

import 'menu_fixtures.dart';
import 'notification_fakes.dart';

// Database version 1 như bản app cũ (commit 500a7d7): cột `oredering`.
Future<void> _createVersion1(String file) async {
  final db = await databaseFactoryFfi.openDatabase(
    file,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE menu_nav (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            icon_name TEXT,
            menu_name TEXT,
            menu_url TEXT,
            oredering INTEGER
          )
        ''');
        for (final menu in seedMenus) {
          await db.insert('menu_nav', {
            'icon_name': menu.iconName,
            'menu_name': menu.menuName,
            'menu_url': menu.menuUrl,
            'oredering': menu.ordering,
          });
        }
      },
    ),
  );
  await db.close();
}

// Database version 2 như commit 6ecc5fd: menu đã đồng bộ từ API và mốc đồng bộ.
Future<void> _createVersion2(String file, DateTime syncedAt) async {
  final db = await databaseFactoryFfi.openDatabase(
    file,
    options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE menu_nav (
            id INTEGER PRIMARY KEY,
            icon_name TEXT NOT NULL,
            menu_name TEXT NOT NULL,
            menu_url TEXT NOT NULL,
            ordering INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE app_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        for (final menu in apiMenus) {
          await db.insert('menu_nav', menu.toMap());
        }
        await db.insert('app_meta', {
          'key': 'menu_synced_at',
          'value': syncedAt.toIso8601String(),
        });
      },
    ),
  );
  await db.close();
}

RemoteMessage _message(
  String? id, {
  String? title = 'UEH Student - Firebase Test',
  String? body = 'Kiểm tra thông báo Firebase Cloud Messaging',
  DateTime? sentTime,
}) => RemoteMessage(
  messageId: id,
  sentTime: sentTime,
  notification: RemoteNotification(title: title, body: body),
);

AppNotification _note(String id, DateTime at, {String title = 'Tiêu đề'}) =>
    AppNotification(
      messageId: id,
      title: title,
      body: 'Nội dung',
      receivedAt: at,
    );

/// Store lỗi: mọi thao tác đều ném lỗi như khi SQLite hỏng.
class _BrokenStore implements NotificationStore {
  @override
  Future<bool> save(AppNotification notification) =>
      Future.error(StateError('SQLite lỗi giả lập'));
  @override
  Future<List<AppNotification>> read() =>
      Future.error(StateError('SQLite lỗi giả lập'));
  @override
  Future<bool> markRead(String messageId) =>
      Future.error(StateError('SQLite lỗi giả lập'));
}

void main() {
  late Directory dir;
  const store = SqliteNotificationStore();
  final t0 = DateTime(2026, 10, 22, 21);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ueh_notification_test');
    DBUtils.debugDatabasePath = path.join(dir.path, DBUtils.databaseName);
  });

  tearDown(() async {
    await DBUtils.close();
    DBUtils.debugDatabasePath = null;
    await dir.delete(recursive: true);
  });

  Future<List<String>> tables() async => [
    for (final row in await (await DBUtils.database).rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ))
      row['name'] as String,
  ];

  group('Database version 3 và migration', () {
    test(
      'Cài mới: tạo đủ menu_nav, app_meta, notifications (version 3)',
      () async {
        final db = await DBUtils.database;
        expect(await db.getVersion(), 3);
        expect(await tables(), ['app_meta', 'menu_nav', 'notifications']);
        final columns = [
          for (final c in await db.rawQuery('PRAGMA table_info(notifications)'))
            c['name'],
        ];
        expect(columns, [
          'id',
          'message_id',
          'title',
          'body',
          'received_at',
          'is_read',
        ]);
        expect(await DBUtils.getMenus(), isEmpty);
        expect(await store.read(), isEmpty);
      },
    );

    test('Version 1 → 3: chạy bước 1→2 rồi 2→3, giữ nguyên menu', () async {
      await _createVersion1(DBUtils.debugDatabasePath!);
      expect(await DBUtils.getMenus(), seedMenus);
      expect(await (await DBUtils.database).getVersion(), 3);
      expect(await tables(), ['app_meta', 'menu_nav', 'notifications']);
      // Menu mẫu bản cũ vẫn chưa được coi là đã đồng bộ từ server.
      expect(await DBUtils.getMenuSyncedAt(), isNull);
      expect(await store.read(), isEmpty);
    });

    test('Version 2 → 3: giữ menu đã đồng bộ và mốc đồng bộ', () async {
      await _createVersion2(DBUtils.debugDatabasePath!, t0);
      expect(await DBUtils.getMenus(), apiMenus);
      expect(await DBUtils.getMenuSyncedAt(), t0);
      expect(await (await DBUtils.database).getVersion(), 3);
      expect(await tables(), ['app_meta', 'menu_nav', 'notifications']);
      expect(await store.read(), isEmpty);
      // Menu API offline vẫn dùng bảng cũ như trước.
      await DBUtils.replaceMenus(apiMenus, syncedAt: t0);
      expect(await DBUtils.getMenus(), apiMenus);
    });
  });

  group('Lưu lịch sử thông báo', () {
    test('Đọc mới nhất trước theo thời điểm nhận', () async {
      await store.save(_note('a', t0));
      await store.save(_note('c', t0.add(const Duration(minutes: 2))));
      await store.save(_note('b', t0.add(const Duration(minutes: 1))));
      final saved = await store.read();
      expect(saved.map((n) => n.messageId), ['c', 'b', 'a']);
      expect(saved.first.receivedAt, t0.add(const Duration(minutes: 2)));
      expect(saved.first.title, 'Tiêu đề');
      expect(saved.first.body, 'Nội dung');
      expect(saved.first.isRead, isFalse);
      expect(saved.first.id, isNotNull);
    });

    test('Hai tin khác nhau cùng tiêu đề và nội dung: hai dòng', () async {
      expect(await store.save(_note('m1', t0)), isTrue);
      expect(await store.save(_note('m2', t0)), isTrue);
      expect(await store.read(), hasLength(2));
    });

    test('Cùng message ID: chỉ một dòng, không ghi đè bản đã lưu', () async {
      expect(await store.save(_note('m1', t0, title: 'Bản đầu')), isTrue);
      await store.markRead('m1');
      expect(
        await store.save(
          _note('m1', t0.add(const Duration(hours: 1)), title: 'Bản sau'),
        ),
        isFalse,
      );
      final saved = await store.read();
      expect(saved, hasLength(1));
      expect(saved.single.title, 'Bản đầu');
      expect(saved.single.receivedAt, t0);
      expect(saved.single.isRead, isTrue);
    });

    test('Ghi cùng lúc nhiều lần: mỗi message ID một dòng', () async {
      await DBUtils.database;
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) store.save(_note('m1', t0)),
        for (var i = 0; i < 3; i++) store.save(_note('m2', t0)),
      ]);
      expect(results.where((saved) => saved), hasLength(2));
      expect((await store.read()).map((n) => n.messageId).toSet(), {
        'm1',
        'm2',
      });
      expect(await store.read(), hasLength(2));
    });

    test('Đóng và mở lại database: lịch sử còn nguyên', () async {
      await store.save(_note('m1', t0));
      await store.markRead('m1');
      await DBUtils.close();
      final saved = await store.read();
      expect(saved.single.messageId, 'm1');
      expect(saved.single.isRead, isTrue);
    });

    test('Đánh dấu đã đọc', () async {
      await store.save(_note('m1', t0));
      await store.save(_note('m2', t0));
      expect(await store.markRead('m2'), isTrue);
      expect(await store.markRead('khong-co'), isFalse);
      final read = {for (final n in await store.read()) n.messageId: n.isRead};
      expect(read, {'m1': false, 'm2': true});
    });
  });

  group('Nối với các callback FCM', () {
    late FakeMessaging messaging;
    late FakeLocal local;

    setUp(() {
      messaging = FakeMessaging();
      local = FakeLocal();
    });

    NotificationService service({NotificationStore saveTo = store}) {
      final s = NotificationService(
        messaging: messaging,
        local: local,
        store: saveTo,
        showWhenForeground: true,
      );
      addTearDown(s.dispose);
      return s;
    }

    Future<void> flush() async {
      // Tin phát qua stream được xử lý ở microtask sau; SQLite cần thêm vài lượt.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test(
      'Foreground: lưu SQLite và vẫn hiện thông báo; chạm lại không thêm dòng',
      () async {
        await service().start();
        messaging.messages
          ..add(_message('fg-1'))
          ..add(_message('fg-1')); // FCM giao lại cùng tin
        await flush();
        expect(local.shown, hasLength(1));
        local.tap!('fg-1');
        await flush();
        final saved = await store.read();
        expect(saved.map((n) => n.messageId), ['fg-1']);
        expect(saved.single.title, 'UEH Student - Firebase Test');
        expect(
          saved.single.body,
          'Kiểm tra thông báo Firebase Cloud Messaging',
        );
      },
    );

    test('Background handler lưu; chạm thông báo (onMessageOpenedApp) không tạo dòng thứ hai', () async {
      await firebaseMessagingBackgroundHandler(_message('bg-1'));
      expect((await store.read()).map((n) => n.messageId), ['bg-1']);
      await service().start();
      messaging.opened.add(_message('bg-1'));
      await flush();
      expect((await store.read()).map((n) => n.messageId), ['bg-1']);
      expect(local.shown, isEmpty); // hệ thống đã hiện, app không hiện thêm
    });

    test(
      'Mở app từ thông báo khi app đã đóng: getInitialMessage lưu nếu chưa có',
      () async {
        // Background handler không chạy (ví dụ app bị buộc dừng): vẫn lưu khi chạm.
        messaging.initial = _message('closed-1');
        await service().start();
        expect((await store.read()).map((n) => n.messageId), ['closed-1']);
        // Cùng tin đến lại qua onMessageOpenedApp: không thêm dòng.
        messaging.opened.add(_message('closed-1'));
        await flush();
        expect(await store.read(), hasLength(1));
      },
    );

    test('Background và chạm thông báo cùng lúc: một dòng', () async {
      await service().start();
      await Future.wait([
        firebaseMessagingBackgroundHandler(_message('race-1')),
        Future(() => messaging.opened.add(_message('race-1'))),
      ]);
      await flush();
      expect(await store.read(), hasLength(1));
    });

    test('SQLite lỗi: vẫn hiện thông báo, không ném lỗi ra ngoài', () async {
      await service(saveTo: _BrokenStore()).start();
      messaging.messages.add(_message('err-1'));
      messaging.opened.add(_message('err-2'));
      await flush();
      expect(local.shown.map((n) => n.payload), ['err-1']);
      expect(
        await saveMessage(_BrokenStore(), _message('err-3'), source: 'test'),
        isFalse,
      );
    });

    test(
      'Tin chỉ có data không có nội dung: không lưu; data có title/body: lưu',
      () async {
        final empty = RemoteMessage(
          messageId: 'd-1',
          data: const {'loai': 'x'},
        );
        expect(await saveMessage(store, empty, source: 'test'), isFalse);
        final withText = RemoteMessage(
          messageId: 'd-2',
          data: const {'title': 'Tiêu đề data', 'body': 'Nội dung data'},
        );
        expect(await saveMessage(store, withText, source: 'test'), isTrue);
        final saved = await store.read();
        expect(saved.single.messageId, 'd-2');
        expect(saved.single.title, 'Tiêu đề data');
      },
    );

    test('Không có message ID: có sentTime thì chống trùng, không có thì không mất tin', () async {
      final sent = DateTime.utc(2026, 10, 22, 14, 35);
      expect(
        await saveMessage(store, _message(null, sentTime: sent), source: 'a'),
        isTrue,
      );
      expect(
        await saveMessage(store, _message(null, sentTime: sent), source: 'b'),
        isFalse,
      );
      // Không có message ID lẫn sentTime: mỗi lần là một dòng mới (không mất tin).
      expect(await saveMessage(store, _message(null), source: 'c'), isTrue);
      expect(await saveMessage(store, _message(null), source: 'd'), isTrue);
      expect(await store.read(), hasLength(3));
    });
  });
}
