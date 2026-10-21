import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/controllers/menu_sync_controller.dart';
import 'package:flutter_application_1/services/student_api.dart';
import 'package:flutter_application_1/widgets/home_screen.dart';

import 'menu_fixtures.dart';
import 'student_api_test.dart'
    show MemoryTokenStore, jsonResponse, tokens, profileJson;

/// Dựng HomeScreen với AuthController và MenuSyncController dùng chung một StudentApi.
class _Harness {
  _Harness({
    required this.store,
    required Future<http.Response> Function() menuResponse,
    bool savedSession = false,
  }) {
    final api = StudentApi(
      store: MemoryTokenStore()
        ..value = savedSession ? jsonEncode(tokens()) : null,
      client: MockClient((request) async {
        switch (request.url.path) {
          case '/api/login':
            return jsonResponse(tokens());
          case '/api/menu':
            menuCalls++;
            // Ghi lại rồi kiểm tra sau: không gọi expect trong callback mạng.
            authHeaders.add(request.headers['Authorization']);
            return menuResponse();
          default:
            return jsonResponse(profileJson);
        }
      }),
    );
    auth = AuthController(api: api);
    menu = MenuSyncController(api: api, store: store);
  }

  final MemoryMenuStore store;
  late final AuthController auth;
  late final MenuSyncController menu;
  int menuCalls = 0;
  final authHeaders = <String?>[];

  Future<void> pump(WidgetTester tester) async {
    addTearDown(() {
      menu.dispose();
      auth.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(auth: auth, menu: menu)),
    );
  }

  Future<void> openDrawer(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Mở menu'));
    await tester.pumpAndSettle();
  }
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
  final linux = TargetPlatformVariant({TargetPlatform.linux});

  testWidgets('Khách chưa đăng nhập không gọi Menu API; đăng nhập xong đồng bộ ngay', (
    tester,
  ) async {
    final h = _Harness(
      store: MemoryMenuStore(),
      menuResponse: () async => jsonResponse(menuJson),
    );
    await h.pump(tester);
    await tester.pumpAndSettle();
    expect(h.menuCalls, 0);

    await h.auth.login('123456', 'mat-khau-gia');
    await tester.pumpAndSettle();
    expect(h.menuCalls, 1);
    expect(h.authHeaders, ['Bearer access-1']);
    expect(h.store.menus, apiMenus);

    await h.openDrawer(tester);
    expect(find.byType(ListTile), findsNWidgets(11));
    expect(_iconOf(tester, 'Xem điểm'), FontAwesomeIcons.chartLine.data);
    expect(tester.takeException(), isNull);
  }, variant: linux);

  testWidgets('Mở lại app có phiên: hiện cache trước, rồi đồng bộ từ API', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    final h = _Harness(
      store: MemoryMenuStore(seedMenus),
      menuResponse: () => gate.future,
      savedSession: true,
    );
    await h.pump(tester);
    await tester.pumpAndSettle();
    expect(h.menuCalls, 1); // khôi phục phiên xong là gọi Menu API
    await h.openDrawer(tester);
    expect(_iconOf(tester, 'Xem điểm'), FontAwesomeIcons.graduationCap.data);

    gate.complete(jsonResponse(menuJson));
    await tester.pumpAndSettle();
    expect(_iconOf(tester, 'Xem điểm'), FontAwesomeIcons.chartLine.data);
    expect(h.store.menus, apiMenus);
  }, variant: linux);

  testWidgets('Đăng xuất khi Menu API đang chạy: không cập nhật kết quả cũ', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    final h = _Harness(
      store: MemoryMenuStore(seedMenus),
      menuResponse: () => gate.future,
      savedSession: true,
    );
    await h.pump(tester);
    await tester.pumpAndSettle();
    expect(h.menuCalls, 1);

    await h.auth.logout();
    await tester.pump();
    gate.complete(jsonResponse(menuJson));
    await tester.pumpAndSettle();
    expect(h.store.writes, 0);
    expect(h.menu.menus, seedMenus); // cache vẫn giữ để dùng offline
    expect(h.menu.syncError, isNull);
    expect(tester.takeException(), isNull);
  }, variant: linux);

  testWidgets('Mở Drawer sau khi đồng bộ lỗi sẽ tự thử lại', (tester) async {
    var online = false;
    final h = _Harness(
      store: MemoryMenuStore(apiMenus),
      menuResponse: () async {
        if (!online) throw http.ClientException('offline');
        return jsonResponse(menuJson);
      },
      savedSession: true,
    );
    await h.pump(tester);
    await tester.pumpAndSettle();
    expect(h.menuCalls, 1);
    expect(h.menu.syncError, isNotNull);

    online = true;
    await h.openDrawer(tester);
    expect(h.menuCalls, 2);
    expect(h.menu.syncError, isNull);
    expect(find.byType(ListTile), findsNWidgets(11));
  }, variant: linux);
}
