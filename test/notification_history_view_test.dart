import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_application_1/helpers/DBUtils.dart';
import 'package:flutter_application_1/models/app_notification.dart';
import 'package:flutter_application_1/services/notification_store.dart';
import 'package:flutter_application_1/widgets/notification_history.dart';

import 'notification_fakes.dart';

AppNotification _note(
  String id,
  DateTime at, {
  String? title,
  String body = 'Nội dung',
  bool isRead = false,
}) => AppNotification(
  messageId: id,
  title: title ?? 'Tin $id',
  body: body,
  receivedAt: at,
  isRead: isRead,
);

Future<void> _pump(WidgetTester tester, NotificationHistory history) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: NotificationHistoryView(history: history)),
    ),
  );
  await tester.pumpAndSettle();
}

// Thứ tự các tiêu đề trên màn hình, từ trên xuống.
List<String> _shownTitles(WidgetTester tester) {
  final tiles = tester.widgetList<NotificationTile>(
    find.byType(NotificationTile),
  );
  final titles = [for (final t in tiles) t.item.title];
  final tops = {for (final t in titles) t: tester.getTopLeft(find.text(t)).dy};
  return titles..sort((a, b) => tops[a]!.compareTo(tops[b]!));
}

void main() {
  late MemoryNotificationStore store;
  late NotificationHistory history;
  final t0 = DateTime(2026, 10, 22, 21, 54, 32);

  setUp(() {
    store = MemoryNotificationStore();
    history = NotificationHistory(store);
    addTearDown(history.dispose);
  });

  test('Thời điểm nhận dạng HH:mm · dd/mm/yyyy theo giờ máy', () {
    expect(
      formatReceivedAt(DateTime(2026, 10, 22, 9, 5)),
      '09:05 · 22/10/2026',
    );
    final utc = DateTime.utc(2026, 10, 22, 14, 55);
    expect(formatReceivedAt(utc), formatReceivedAt(utc.toLocal()));
  });

  testWidgets('Đang đọc SQLite: hiện vòng xoay, đọc xong hiện danh sách', (
    tester,
  ) async {
    await store.save(_note('m1', t0));
    store.gate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NotificationHistoryView(history: history)),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    store.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Tin m1'), findsOneWidget);
  });

  testWidgets('Chưa có thông báo: hiện trạng thái rỗng', (tester) async {
    await _pump(tester, history);
    expect(find.text('Chưa có thông báo.'), findsOneWidget);
    expect(find.byType(NotificationTile), findsNothing);
  });

  testWidgets(
    'Có dữ liệu: tiêu đề, nội dung, thời điểm nhận; mới nhất ở trên',
    (tester) async {
      await store.save(
        _note(
          'fg',
          t0,
          title: 'UEH Student - SQLite Foreground',
          body: 'Luu lich su khi ung dung dang mo',
        ),
      );
      await store.save(
        _note(
          'bg',
          t0.add(const Duration(minutes: 1, seconds: 7)),
          title: 'UEH Student - SQLite Background',
          body: 'Luu lich su khi ung dung chay nen',
        ),
      );
      await _pump(tester, history);
      expect(_shownTitles(tester), [
        'UEH Student - SQLite Background',
        'UEH Student - SQLite Foreground',
      ]);
      expect(find.text('Luu lich su khi ung dung chay nen'), findsOneWidget);
      expect(find.text('Luu lich su khi ung dung dang mo'), findsOneWidget);
      expect(find.text('21:55 · 22/10/2026'), findsOneWidget);
      expect(find.text('21:54 · 22/10/2026'), findsOneWidget);
      expect(find.text('Chưa có thông báo.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Đọc SQLite lỗi: báo lỗi và Thử lại đọc được', (tester) async {
    await store.save(_note('m1', t0));
    store.readError = StateError('SQLite lỗi giả lập');
    await _pump(tester, history);
    expect(find.text('Không đọc được lịch sử thông báo.'), findsOneWidget);
    expect(find.byType(NotificationTile), findsNothing);

    store.readError = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Không đọc được lịch sử thông báo.'), findsNothing);
    expect(find.text('Tin m1'), findsOneWidget);
  });

  testWidgets('Tin mới lưu qua NotificationHistory: danh sách cập nhật ngay', (
    tester,
  ) async {
    await _pump(tester, history);
    expect(find.text('Chưa có thông báo.'), findsOneWidget);
    await history.save(_note('m1', t0));
    await tester.pumpAndSettle();
    expect(find.text('Tin m1'), findsOneWidget);
    // Lưu trùng message ID: không báo thay đổi, không đọc lại.
    final reads = store.reads;
    await history.save(_note('m1', t0));
    await tester.pumpAndSettle();
    expect(store.reads, reads);
    expect(find.byType(NotificationTile), findsOneWidget);
  });

  testWidgets('App trở lại foreground: đọc lại tin do background handler lưu', (
    tester,
  ) async {
    await _pump(tester, history);
    // Isolate nền ghi thẳng SQLite, không báo qua NotificationHistory.
    await store.save(_note('bg', t0));
    await tester.pumpAndSettle();
    expect(find.text('Tin bg'), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Tin bg'), findsOneWidget);
  });

  testWidgets(
    'Mở tab không tự đánh dấu đã đọc; chạm một tin: lưu đã đọc và xem đầy đủ',
    (tester) async {
      await store.save(
        _note('m1', t0, body: 'Nội dung đầy đủ của thông báo thử nghiệm'),
      );
      await store.save(_note('m2', t0.add(const Duration(minutes: 1))));
      await _pump(tester, history);
      expect(store.rows.where((r) => r.isRead), isEmpty);
      expect(find.bySemanticsLabel(RegExp('^Chưa đọc')), findsNWidgets(2));

      await tester.tap(find.text('Tin m1'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Nội dung đầy đủ của thông báo thử nghiệm'),
        ),
        findsOneWidget,
      );
      expect(
        {for (final r in store.rows) r.messageId: r.isRead},
        {'m1': true, 'm2': false},
      );

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('^Chưa đọc')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Đã đọc')), findsOneWidget);
      // Tiêu đề, nội dung giữ nguyên sau khi đánh dấu đã đọc.
      expect(find.text('Tin m1'), findsOneWidget);
      expect(store.rows, hasLength(2));
    },
  );

  group('SQLite thật (bảng notifications)', () {
    late Directory dir;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ueh_history_view_test');
      DBUtils.debugDatabasePath = path.join(dir.path, DBUtils.databaseName);
    });

    tearDown(() async {
      await DBUtils.close();
      DBUtils.debugDatabasePath = null;
      await dir.delete(recursive: true);
    });

    testWidgets('Mới nhất ở trên; trùng thời điểm thì tin lưu sau ở trên', (
      tester,
    ) async {
      final sqlite = NotificationHistory(const SqliteNotificationStore());
      addTearDown(sqlite.dispose);
      await tester.runAsync(() async {
        await sqlite.save(_note('a', t0));
        await sqlite.save(_note('c', t0.add(const Duration(minutes: 2))));
        await sqlite.save(_note('b', t0.add(const Duration(minutes: 1))));
        await sqlite.save(_note('d', t0.add(const Duration(minutes: 1))));
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NotificationHistoryView(history: sqlite)),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(_shownTitles(tester), ['Tin c', 'Tin d', 'Tin b', 'Tin a']);
    });
  });
}
