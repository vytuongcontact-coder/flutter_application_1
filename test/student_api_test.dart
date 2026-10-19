import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_application_1/services/student_api.dart';
import 'package:flutter_application_1/services/token_store.dart';

class MemoryTokenStore implements TokenStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async => this.value = value;
  @override
  Future<void> clear() async => value = null;
}

const profileJson = {
  'mssv': '123456',
  'hoVaTen': 'Sinh Viên Test',
  'ngaySinh': '2006-10-12T00:00:00',
  'gioiTinh': false,
  'nienKhoa': 'DHCQK50',
  'noiSinh': 'TP. Hồ Chí Minh',
  'heDaoTao': 'ĐHCQ',
  'nienHoc': '2024 - 2027',
};
http.Response jsonResponse(Object data, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), status);
Map<String, String> tokens([String suffix = '1']) => {
  'token': 'access-$suffix',
  'refresh_token': 'refresh-$suffix',
};

void main() {
  test(
    'Login sends documented fields, stores only tokens, restores and logs out',
    () async {
      final store = MemoryTokenStore();
      final client = MockClient((request) async {
        if (request.url.path == '/api/login') {
          expect(jsonDecode(request.body), {
            'mssv': '123456',
            'mat_khau': ' demo password ',
          });
          expect(request.headers['Content-Type'], 'application/json');
          return jsonResponse(tokens());
        }
        expect(request.headers['Authorization'], 'Bearer access-1');
        return jsonResponse(profileJson);
      });
      final api = StudentApi(client: client, store: store);
      addTearDown(api.close);
      await api.login(' 123456 ', ' demo password ');
      expect(store.value, isNot(contains('password')));
      expect(store.value, isNot(contains('123456')));
      final profile = await api.studentInfo();
      expect(profile.birthDate, '12/10/2006');
      expect(profile.gender, 'Nữ');
      final restored = StudentApi(client: client, store: store);
      await restored.restore();
      expect(restored.hasSession, isTrue);
      await restored.logout();
      expect(restored.hasSession, isFalse);
      expect(store.value, isNull);
    },
  );

  test(
    'Concurrent 401s refresh once, persist rotated pair before retry',
    () async {
      final store = MemoryTokenStore()..value = jsonEncode(tokens());
      final gate = Completer<void>();
      var refreshes = 0;
      var oldCalls = 0;
      final api = StudentApi(
        store: store,
        client: MockClient((request) async {
          if (request.url.path == '/api/refresh-token') {
            refreshes++;
            expect(jsonDecode(request.body)['refresh_token'], 'refresh-1');
            await gate.future;
            return jsonResponse(tokens('2'));
          }
          if (request.headers['Authorization'] == 'Bearer access-1') {
            oldCalls++;
            return http.Response('', 401);
          }
          expect(jsonDecode(store.value!)['refresh_token'], 'refresh-2');
          return jsonResponse(profileJson);
        }),
      );
      addTearDown(api.close);
      await api.restore();
      final requests = Future.wait([api.studentInfo(), api.studentInfo()]);
      await Future<void>.delayed(Duration.zero);
      expect(oldCalls, 2);
      expect(refreshes, 1);
      gate.complete();
      expect((await requests).length, 2);
      expect(refreshes, 1);
    },
  );

  for (final refreshStatus in [401, 500]) {
    test(
      'Refresh failure $refreshStatus clears one-use token and expires session',
      () async {
        final store = MemoryTokenStore()..value = jsonEncode(tokens());
        var expired = 0;
        final api = StudentApi(
          store: store,
          client: MockClient(
            (request) async => http.Response(
              '',
              request.url.path == '/api/refresh-token' ? refreshStatus : 401,
            ),
          ),
        );
        api.onSessionExpired = () => expired++;
        addTearDown(api.close);
        await api.restore();
        await expectLater(api.studentInfo(), throwsA(isA<ApiException>()));
        expect(expired, 1);
        expect(store.value, isNull);
        expect(api.hasSession, isFalse);
      },
    );
  }

  test('Retry 401 does not loop', () async {
    final store = MemoryTokenStore()..value = jsonEncode(tokens());
    var refreshes = 0;
    var profileCalls = 0;
    final api = StudentApi(
      store: store,
      client: MockClient((request) async {
        if (request.url.path == '/api/refresh-token') {
          refreshes++;
          return jsonResponse(tokens('2'));
        }
        profileCalls++;
        return http.Response('', 401);
      }),
    );
    addTearDown(api.close);
    await api.restore();
    await expectLater(api.studentInfo(), throwsA(isA<ApiException>()));
    expect(refreshes, 1);
    expect(profileCalls, 2);
    expect(store.value, isNull);
  });

  test('Logout during refresh cannot resurrect the session', () async {
    final store = MemoryTokenStore()..value = jsonEncode(tokens());
    final gate = Completer<http.Response>();
    final api = StudentApi(
      store: store,
      client: MockClient(
        (request) async => request.url.path == '/api/refresh-token'
            ? gate.future
            : http.Response('', 401),
      ),
    );
    addTearDown(api.close);
    await api.restore();
    final check = expectLater(api.studentInfo(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);
    await api.logout();
    gate.complete(jsonResponse(tokens('2')));
    await check;
    expect(store.value, isNull);
    expect(api.hasSession, isFalse);
  });

  test(
    'Offline profile does not discard session; corrupt storage does',
    () async {
      final store = MemoryTokenStore()..value = jsonEncode(tokens());
      final api = StudentApi(
        store: store,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      addTearDown(api.close);
      await api.restore();
      await expectLater(api.studentInfo(), throwsA(isA<ApiException>()));
      expect(api.hasSession, isTrue);
      store.value = 'invalid';
      await api.restore();
      expect(api.hasSession, isFalse);
      expect(store.value, isNull);
    },
  );

  test('Attendance normalizes code, passes coordinates and preserves business errors', () async {
    final store = MemoryTokenStore()..value = jsonEncode(tokens());
    final api = StudentApi(
      store: store,
      client: MockClient((request) async {
        expect(request.url.path, '/api/attendance');
        expect(jsonDecode(request.body), {
          'code': 'ABC123',
          'latitude': 10.5,
          'longitude': 106.5,
        });
        return jsonResponse({
          'message': 'Bạn đã điểm danh bằng mã này rồi.',
        }, 409);
      }),
    );
    addTearDown(api.close);
    await api.restore();
    await expectLater(
      api.attend(' abc123 ', latitude: 10.5, longitude: 106.5),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'status', 409)
            .having(
              (e) => e.message,
              'message',
              'Bạn đã điểm danh bằng mã này rồi.',
            ),
      ),
    );
    expect(api.hasSession, isTrue);
  });

  test('Bad credentials and validation failures leave no session', () async {
    for (final response in [
      jsonResponse({'message': 'MSSV hoặc mật khẩu không đúng.'}, 401),
      jsonResponse({
        'errors': {
          'MSSV': ['Required'],
        },
      }, 400),
      http.Response('<html>gateway error</html>', 502),
    ]) {
      final store = MemoryTokenStore();
      final api = StudentApi(
        store: store,
        client: MockClient((_) async => response),
      );
      await expectLater(
        api.login('123456', 'wrong'),
        throwsA(isA<ApiException>()),
      );
      expect(store.value, isNull);
      expect(api.hasSession, isFalse);
      api.close();
    }
  });
}
