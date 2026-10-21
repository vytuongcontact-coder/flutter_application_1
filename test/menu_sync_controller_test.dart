import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_application_1/controllers/menu_sync_controller.dart';
import 'package:flutter_application_1/models/menu_nav.dart';
import 'package:flutter_application_1/services/student_api.dart';

import 'menu_fixtures.dart';
import 'student_api_test.dart' show MemoryTokenStore, jsonResponse, tokens;

Future<StudentApi> _api(MockClientHandler handler, {bool loggedIn = true}) async {
  final api = StudentApi(
    store: MemoryTokenStore()..value = loggedIn ? jsonEncode(tokens()) : null,
    client: MockClient(handler),
  );
  addTearDown(api.close);
  await api.restore();
  return api;
}

MenuSyncController _controller(
  StudentApi api,
  MemoryMenuStore store, {
  DateTime Function()? clock,
}) {
  final controller = MenuSyncController(api: api, store: store, clock: clock);
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  test('Cache hiển thị trước, sau đó thay bằng dữ liệu API và lưu SQLite', () async {
    final gate = Completer<http.Response>();
    final store = MemoryMenuStore(seedMenus);
    final controller = _controller(await _api((_) => gate.future), store);
    final syncing = controller.sync();
    await Future<void>.delayed(Duration.zero);
    expect(controller.menus, seedMenus); // đang chờ mạng vẫn có cache
    expect(controller.syncing, isTrue);
    expect(controller.hasSynced, isFalse);
    gate.complete(jsonResponse(menuJson));
    await syncing;
    expect(controller.menus, apiMenus);
    expect(controller.hasSynced, isTrue);
    expect(controller.lastSyncChanged, isTrue);
    expect(store.menus, apiMenus);
    expect(store.writes, 1);
  });

  test('Mất mạng: giữ cache, báo lỗi, không ghi đè SQLite', () async {
    final store = MemoryMenuStore(apiMenus, DateTime(2026, 10, 20));
    final controller = _controller(
      await _api((_) async => throw http.ClientException('offline')),
      store,
    );
    await controller.sync();
    expect(controller.menus, apiMenus);
    expect(controller.syncError, 'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng.');
    expect(store.writes, 0);
    expect(store.menus, apiMenus);
  });

  test('Server 500 hoặc dữ liệu sai: giữ cache', () async {
    for (final response in [
      jsonResponse({'message': 'Lỗi máy chủ.'}, 500),
      jsonResponse({'items': menuJson}),
    ]) {
      final store = MemoryMenuStore(apiMenus);
      final controller = _controller(await _api((_) async => response), store);
      await controller.sync();
      expect(controller.menus, apiMenus);
      expect(controller.syncError, isNotNull);
      expect(store.writes, 0);
    }
  });

  test('API trả mảng rỗng: đồng bộ thành công với danh sách rỗng', () async {
    final store = MemoryMenuStore(apiMenus);
    final controller = _controller(
      await _api((_) async => jsonResponse(<Object>[])),
      store,
    );
    await controller.sync();
    expect(controller.menus, isEmpty);
    expect(controller.hasSynced, isTrue);
    expect(controller.syncError, isNull);
    expect(store.menus, isEmpty);
  });

  test('Chưa đăng nhập: không gọi API với token rỗng', () async {
    var calls = 0;
    final controller = _controller(
      await _api((_) async {
        calls++;
        return jsonResponse(menuJson);
      }, loggedIn: false),
      MemoryMenuStore(),
    );
    await controller.sync();
    expect(calls, 0);
    expect(controller.canSync, isFalse);
  });

  test('Gọi sync nhiều lần cùng lúc chỉ gửi một request', () async {
    var calls = 0;
    final gate = Completer<http.Response>();
    final controller = _controller(
      await _api((_) {
        calls++;
        return gate.future;
      }),
      MemoryMenuStore(),
    );
    final all = Future.wait([controller.sync(), controller.sync(), controller.syncIfStale()]);
    await Future<void>.delayed(Duration.zero);
    gate.complete(jsonResponse(menuJson));
    await all;
    expect(calls, 1);
  });

  test('Đăng xuất khi request đang chạy: bỏ kết quả, không ghi SQLite', () async {
    final gate = Completer<http.Response>();
    final store = MemoryMenuStore(seedMenus);
    final controller = _controller(await _api((_) => gate.future), store);
    final syncing = controller.sync();
    await Future<void>.delayed(Duration.zero);
    controller.cancelSync();
    gate.complete(jsonResponse(menuJson));
    await syncing;
    expect(controller.menus, seedMenus);
    expect(controller.syncing, isFalse);
    expect(store.writes, 0);
  });

  test('Token hết hạn và refresh thất bại: hết phiên nhưng giữ cache', () async {
    final store = MemoryMenuStore(apiMenus, DateTime(2026, 10, 20));
    final api = await _api((_) async => http.Response('', 401));
    final controller = _controller(api, store);
    var expired = 0;
    api.onSessionExpired = () {
      expired++;
      controller.cancelSync(); // HomeScreen làm việc này qua AuthController
    };
    await controller.sync();
    expect(expired, 1);
    expect(api.hasSession, isFalse);
    expect(controller.menus, apiMenus);
    expect(store.menus, apiMenus);
    expect(store.writes, 0);
  });

  test('Lưu SQLite lỗi: không cập nhật UI, báo lỗi', () async {
    final store = MemoryMenuStore(seedMenus)..writeError = StateError('disk');
    final controller = _controller(
      await _api((_) async => jsonResponse(menuJson)),
      store,
    );
    await controller.sync();
    expect(controller.menus, seedMenus);
    expect(controller.hasSynced, isFalse);
    expect(controller.syncError, 'Không thể lưu menu vào máy. Vui lòng thử lại.');
  });

  group('Đăng xuất trong lúc đang ghi SQLite', () {
    // Phiên B nhận menu khác phiên A để biết dữ liệu cuối cùng thuộc phiên nào.
    final menuJsonB = [
      for (final m in menuJson)
        m['id'] == 3 ? {...m, 'menu_name': 'Xem điểm (phiên B)'} : m,
    ];
    final menusB = menuJsonB.map(MenuNav.fromJson).toList();

    // Phiên A dùng access-1; đăng nhập lại (phiên B) nhận access-2.
    Future<StudentApi> twoSessions() => _api((request) async {
      if (request.url.path == '/api/login') return jsonResponse(tokens('2'));
      return request.headers['Authorization'] == 'Bearer access-2'
          ? jsonResponse(menuJsonB)
          : jsonResponse(menuJson);
    });

    test('Lần ghi muộn của phiên A không đè cache của phiên B', () async {
      final api = await twoSessions();
      final gateA = Completer<void>();
      var writesStarted = 0;
      final store = MemoryMenuStore(seedMenus)
        ..beforeWrite = () => ++writesStarted == 1 ? gateA.future : Future.value();
      final controller = _controller(api, store);

      final syncA = controller.sync();
      await pumpEventQueue();
      expect(writesStarted, 1); // phiên A đang ghi dở

      await api.logout();
      controller.cancelSync();
      await api.login('sinh-vien-b', 'mat-khau-gia');
      final syncB = controller.sync();
      await pumpEventQueue();

      gateA.complete(); // lần ghi của phiên A xong sau cùng
      await Future.wait([syncA, syncB]);
      expect(store.menus, menusB);
      expect(controller.menus, menusB);
      expect(controller.syncError, isNull);
    });

    test('Lượt ghi đang chờ của phiên đã đăng xuất bị bỏ qua', () async {
      final api = await twoSessions();
      final gateA = Completer<void>();
      var writesStarted = 0;
      final store = MemoryMenuStore(seedMenus)
        ..beforeWrite = () => ++writesStarted == 1 ? gateA.future : Future.value();
      final controller = _controller(api, store);

      final syncA = controller.sync();
      await pumpEventQueue();
      await api.logout();
      controller.cancelSync();
      await api.login('sinh-vien-b', 'mat-khau-gia');
      final syncB = controller.sync();
      await pumpEventQueue();
      // Phiên B cũng đăng xuất trước khi tới lượt ghi của mình.
      await api.logout();
      controller.cancelSync();

      gateA.complete();
      await Future.wait([syncA, syncB]);
      expect(writesStarted, 1); // lượt ghi của phiên B không chạy
      expect(store.menus, apiMenus); // chỉ lần ghi đã bắt đầu của A hoàn tất
      expect(controller.menus, seedMenus); // UI không nhận kết quả phiên cũ
      expect(controller.syncing, isFalse);
    });

    test('Một lần ghi lỗi không làm kẹt hàng đợi; phiên mới vẫn ghi được', () async {
      final api = await twoSessions();
      final store = MemoryMenuStore(seedMenus)..writeError = StateError('disk');
      final controller = _controller(api, store);

      await controller.sync(); // phiên A: ghi lỗi
      expect(controller.syncError, 'Không thể lưu menu vào máy. Vui lòng thử lại.');
      expect(store.menus, seedMenus);

      store.writeError = null;
      await api.logout();
      controller.cancelSync();
      await api.login('sinh-vien-b', 'mat-khau-gia');
      await controller.sync(); // phiên B: hàng đợi vẫn chạy tiếp
      expect(store.menus, menusB);
      expect(controller.menus, menusB);
      expect(controller.syncError, isNull);
    });
  });

  test('Lỗi lạ khi gọi API: báo lỗi đồng bộ, không nhầm thành lỗi lưu trữ', () async {
    final store = MemoryMenuStore(apiMenus);
    final controller = _controller(
      await _api((_) async => throw StateError('lỗi lạ')),
      store,
    );
    await controller.sync();
    expect(controller.syncError, 'Không thể đồng bộ menu. Vui lòng thử lại.');
    expect(controller.menus, apiMenus);
    expect(store.writes, 0);
  });

  test('syncIfStale: chỉ gọi lại API khi đã cũ hơn 5 phút hoặc lần trước lỗi', () async {
    var now = DateTime(2026, 10, 21, 9);
    var calls = 0;
    var online = true;
    final controller = _controller(
      await _api((_) async {
        calls++;
        if (!online) throw http.ClientException('offline');
        return jsonResponse(menuJson);
      }),
      MemoryMenuStore(),
      clock: () => now,
    );
    await controller.syncIfStale(); // chưa từng đồng bộ
    expect(calls, 1);
    now = now.add(const Duration(minutes: 4));
    await controller.syncIfStale();
    expect(calls, 1);
    now = now.add(const Duration(minutes: 2));
    online = false;
    await controller.syncIfStale(); // đã cũ → gọi, nhưng lỗi
    expect(calls, 2);
    online = true;
    await controller.syncIfStale(); // lần trước lỗi → thử lại ngay
    expect(calls, 3);
    expect(controller.syncError, isNull);
  });

  test('Đọc cache lỗi thì cho phép đọc lại', () async {
    final store = MemoryMenuStore(apiMenus)..readError = StateError('db');
    final controller = _controller(await _api((_) async => jsonResponse(menuJson), loggedIn: false), store);
    await controller.loadCache();
    expect(controller.cacheError, isNotNull);
    expect(controller.menus, isEmpty);
    store.readError = null;
    await controller.loadCache();
    expect(controller.cacheError, isNull);
    expect(controller.menus, apiMenus);
  });
}
