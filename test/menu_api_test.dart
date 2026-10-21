import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_application_1/services/student_api.dart';

import 'menu_fixtures.dart';
import 'student_api_test.dart'
    show MemoryTokenStore, jsonResponse, tokens, profileJson;

Future<StudentApi> _loggedIn(MockClientHandler handler) async {
  final api = StudentApi(
    store: MemoryTokenStore()..value = jsonEncode(tokens()),
    client: MockClient(handler),
  );
  addTearDown(api.close);
  await api.restore();
  return api;
}

void main() {
  test('GET /api/menu gửi Bearer token và parse mảng 11 menu', () async {
    final api = await _loggedIn((request) async {
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.ngoisaoviet.info/api/menu');
      expect(request.headers['Authorization'], 'Bearer access-1');
      return jsonResponse(menuJson);
    });
    final menus = await api.menu();
    expect(menus, hasLength(11));
    expect(menus.map((m) => m.id), List.generate(11, (i) => i + 1));
    expect(menus.map((m) => m.ordering), List.generate(11, (i) => i));
    expect(menus.first.menuName, 'Tin tức UEH');
    expect(menus.first.menuUrl, 'https://ueh.edu.vn/tintucmobile');
    expect(menus.skip(1).every((m) => m.menuUrl.isEmpty), isTrue);
    expect(
      menus.map((m) => m.iconName),
      containsAll(['chartLine', 'faceSmile', 'fileLines', 'phone', 'circleCheck']),
    );
  });

  test('Mảng rỗng là kết quả hợp lệ, không phải lỗi', () async {
    final api = await _loggedIn((_) async => jsonResponse(<Object>[]));
    expect(await api.menu(), isEmpty);
  });

  test('Dữ liệu menu sai cấu trúc bị từ chối, phiên vẫn giữ', () async {
    final invalid = <Object>[
      {'id': 1}, // object thay vì array
      [
        {'id': 1, 'icon_name': 'leaf', 'menu_name': 'A', 'menu_url': ''},
      ], // thiếu ordering
      [
        {'id': '1', 'icon_name': 'leaf', 'menu_name': 'A', 'menu_url': '', 'ordering': 0},
      ], // id sai kiểu
      [
        {'id': 1, 'icon_name': 'leaf', 'menu_name': '', 'menu_url': '', 'ordering': 0},
      ], // tên rỗng
      [menuJson[0], menuJson[0]], // trùng id
      ['menu'], // phần tử không phải object
    ];
    for (final body in invalid) {
      final api = await _loggedIn((_) async => jsonResponse(body));
      await expectLater(api.menu(), throwsA(isA<ApiException>()));
      expect(api.hasSession, isTrue);
    }
    final html = await _loggedIn((_) async => http.Response('<html></html>', 200));
    await expectLater(html.menu(), throwsA(isA<ApiException>()));
  });

  test('Student info vẫn bắt buộc JSON object, không nhận array', () async {
    final api = await _loggedIn((_) async => jsonResponse(menuJson));
    await expectLater(api.studentInfo(), throwsA(isA<ApiException>()));
  });

  test('500, timeout và mất mạng: báo lỗi, không xóa phiên', () async {
    final failures = <MockClientHandler>[
      (_) async => jsonResponse({'message': 'Lỗi máy chủ.'}, 500),
      (_) async => throw TimeoutException('timeout'),
      (_) async => throw http.ClientException('offline'),
    ];
    final messages = <String>[];
    for (final handler in failures) {
      final api = await _loggedIn(handler);
      try {
        await api.menu();
        fail('Phải ném ApiException');
      } on ApiException catch (e) {
        messages.add(e.message);
      }
      expect(api.hasSession, isTrue);
    }
    expect(messages, [
      'Lỗi máy chủ.',
      'Kết nối quá thời gian chờ. Vui lòng kiểm tra mạng và thử lại.',
      'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng.',
    ]);
  });

  test('401 → refresh thành công → gọi lại Menu đúng một lần', () async {
    var menuCalls = 0;
    var refreshes = 0;
    final api = await _loggedIn((request) async {
      if (request.url.path == '/api/refresh-token') {
        refreshes++;
        expect(jsonDecode(request.body)['refresh_token'], 'refresh-1');
        return jsonResponse(tokens('2'));
      }
      menuCalls++;
      return request.headers['Authorization'] == 'Bearer access-1'
          ? http.Response('', 401)
          : jsonResponse(menuJson);
    });
    expect(await api.menu(), hasLength(11));
    expect(refreshes, 1);
    expect(menuCalls, 2);
  });

  test('401 → refresh thất bại → hết phiên, không thử lại vòng lặp', () async {
    var expired = 0;
    var menuCalls = 0;
    final api = await _loggedIn((request) async {
      if (request.url.path == '/api/refresh-token') return http.Response('', 401);
      menuCalls++;
      return http.Response('', 401);
    });
    api.onSessionExpired = () => expired++;
    await expectLater(
      api.menu(),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
    );
    expect(expired, 1);
    expect(menuCalls, 1);
    expect(api.hasSession, isFalse);
  });

  test('Menu và Student info cùng gặp 401 chỉ refresh một lần', () async {
    final gate = Completer<void>();
    var refreshes = 0;
    final api = await _loggedIn((request) async {
      if (request.url.path == '/api/refresh-token') {
        refreshes++;
        await gate.future;
        return jsonResponse(tokens('2'));
      }
      if (request.headers['Authorization'] == 'Bearer access-1') {
        return http.Response('', 401);
      }
      return request.url.path == '/api/menu'
          ? jsonResponse(menuJson)
          : jsonResponse(profileJson);
    });
    final both = Future.wait([api.menu(), api.studentInfo()]);
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    await both;
    expect(refreshes, 1);
  });
}
