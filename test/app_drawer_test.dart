import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/controllers/menu_sync_controller.dart';
import 'package:flutter_application_1/helpers/DBUtils.dart';
import 'package:flutter_application_1/services/student_api.dart';
import 'package:flutter_application_1/widgets/app_drawer.dart';

import 'menu_fixtures.dart';
import 'student_api_test.dart' show MemoryTokenStore, jsonResponse, tokens;

Future<MenuSyncController> _menu(
  MemoryMenuStore store, {
  MockClientHandler? handler,
}) async {
  final api = StudentApi(
    store: MemoryTokenStore()
      ..value = handler == null ? null : jsonEncode(tokens()),
    client: MockClient(handler ?? (_) async => http.Response('', 401)),
  );
  await api.restore();
  final controller = MenuSyncController(api: api, store: store);
  addTearDown(() {
    controller.dispose();
    api.close();
  });
  return controller;
}

Future<GlobalKey<ScaffoldState>> _pumpOpenDrawer(
  WidgetTester tester,
  MenuSyncController menu, {
  ValueChanged<MenuNav>? onSelected,
}) async {
  final key = GlobalKey<ScaffoldState>();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        key: key,
        drawer: AppDrawer(menu: menu, onSelected: onSelected ?? (_) {}),
      ),
    ),
  );
  key.currentState!.openDrawer();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return key;
}

IconData _iconOf(WidgetTester tester, String menuName) => tester
    .widget<FaIcon>(
      find.descendant(
        of: find.ancestor(of: find.text(menuName), matching: find.byType(ListTile)),
        matching: find.byType(FaIcon),
      ),
    )
    .icon!;

void main() {
  const menu = MenuNav(
    id: 42,
    iconName: 'newspaper',
    menuName: 'Tin tức từ database',
    menuUrl: 'https://ueh.edu.vn/tintucmobile',
    ordering: 0,
  );

  testWidgets('Drawer chờ dữ liệu và trả về menu đã đọc khi chọn', (
    tester,
  ) async {
    final store = MemoryMenuStore([menu])..readGate = Completer<void>();
    final controller = await _menu(store);
    MenuNav? selected;
    final key = await _pumpOpenDrawer(
      tester,
      controller,
      onSelected: (value) => selected = value,
    );
    controller.loadCache();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    store.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text(menu.menuName), findsOneWidget);
    expect(
      tester.widget<FaIcon>(find.byType(FaIcon)).icon,
      FontAwesomeIcons.newspaper.data,
    );

    await tester.tap(find.text(menu.menuName));
    await tester.pumpAndSettle();
    expect(selected, same(menu));
    expect(key.currentState!.isDrawerOpen, isFalse);
  });

  testWidgets('Drawer cho phép tải lại khi đọc database thất bại', (
    tester,
  ) async {
    final store = MemoryMenuStore([menu])..readError = StateError('db');
    final controller = await _menu(store);
    await _pumpOpenDrawer(tester, controller);
    await controller.loadCache();
    await tester.pumpAndSettle();
    expect(find.text('Không thể tải menu. Vui lòng thử lại.'), findsOneWidget);
    store.readError = null;
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text(menu.menuName), findsOneWidget);
    expect(store.reads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('11 menu từ API đúng thứ tự và đúng 5 icon mới', (tester) async {
    final controller = await _menu(MemoryMenuStore(apiMenus));
    await controller.loadCache();
    await _pumpOpenDrawer(tester, controller);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title! as Text).data)
        .toList();
    expect(titles, menuJson.map((m) => m['menu_name']).toList());
    expect(_iconOf(tester, 'Xem điểm'), FontAwesomeIcons.chartLine.data);
    expect(_iconOf(tester, 'Định danh khuôn mặt'), FontAwesomeIcons.faceSmile.data);
    expect(_iconOf(tester, 'Lịch thi'), FontAwesomeIcons.fileLines.data);
    expect(_iconOf(tester, 'Liên hệ trực tiếp UEH'), FontAwesomeIcons.phone.data);
    expect(_iconOf(tester, 'Đã điểm danh'), FontAwesomeIcons.circleCheck.data);
  });

  testWidgets('Icon chưa hỗ trợ dùng fallback, không crash', (tester) async {
    final controller = await _menu(
      MemoryMenuStore(const [
        MenuNav(id: 1, iconName: 'khongTonTai', menuName: 'Mục lạ', menuUrl: '', ordering: 0),
      ]),
    );
    await controller.loadCache();
    await _pumpOpenDrawer(tester, controller);
    expect(_iconOf(tester, 'Mục lạ'), FontAwesomeIcons.circleQuestion.data);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Đang đồng bộ vẫn hiện cache; xong thì cập nhật khi Drawer đang mở', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    final controller = await _menu(
      MemoryMenuStore(seedMenus),
      handler: (_) => gate.future,
    );
    await controller.loadCache();
    await _pumpOpenDrawer(tester, controller);
    controller.sync();
    await tester.pump();
    expect(find.text('Xem điểm'), findsOneWidget);
    expect(_iconOf(tester, 'Xem điểm'), FontAwesomeIcons.graduationCap.data);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete(jsonResponse(menuJson));
    await tester.pumpAndSettle();
    expect(_iconOf(tester, 'Xem điểm'), FontAwesomeIcons.chartLine.data);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Không có cache và chưa đăng nhập: hướng dẫn đồng bộ', (
    tester,
  ) async {
    final controller = await _menu(MemoryMenuStore());
    await controller.loadCache();
    await _pumpOpenDrawer(tester, controller);
    expect(
      find.text('Chưa có dữ liệu menu. Vui lòng kết nối Internet và đăng nhập để đồng bộ.'),
      findsOneWidget,
    );
    expect(find.text('Thử lại'), findsNothing);
  });

  testWidgets('Mất mạng: vẫn hiện cache kèm thông báo và nút thử lại', (
    tester,
  ) async {
    var online = false;
    final controller = await _menu(
      MemoryMenuStore(apiMenus),
      handler: (_) async {
        if (!online) throw http.ClientException('offline');
        return jsonResponse(menuJson);
      },
    );
    await controller.sync();
    await _pumpOpenDrawer(tester, controller);
    expect(find.byType(ListTile), findsNWidgets(11));
    final notice = find.text(
      'Chưa đồng bộ được menu. Đang hiển thị dữ liệu đã lưu.',
    );
    expect(notice, findsOneWidget);
    online = true;
    // Nút nằm dưới 11 mục menu: cuộn Drawer xuống rồi chờ một frame.
    await tester.ensureVisible(find.text('Thử lại'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);
    expect(controller.hasSynced, isTrue);
  });

  testWidgets('Server trả mảng rỗng: hiện trạng thái rỗng, không dùng lại menu cũ', (
    tester,
  ) async {
    final controller = await _menu(
      MemoryMenuStore(apiMenus),
      handler: (_) async => jsonResponse(<Object>[]),
    );
    await controller.sync();
    await _pumpOpenDrawer(tester, controller);
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Hiện chưa có mục menu nào.'), findsOneWidget);
  });
}
