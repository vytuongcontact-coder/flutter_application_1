import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/services/student_api.dart';
import 'package:flutter_application_1/services/attendance_location.dart';
import 'package:flutter_application_1/widgets/home_screen.dart';
import 'package:flutter_application_1/widgets/login_screen.dart';
import 'package:flutter_application_1/widgets/account_screen.dart';
import 'package:flutter_application_1/widgets/app_bottom_bar.dart';
import 'package:flutter_application_1/widgets/attendance_screen.dart';

import 'student_api_test.dart'
    show MemoryTokenStore, jsonResponse, tokens, profileJson;

class FakeLocation extends AttendanceLocation {
  int calls = 0;
  bool denied = false;
  @override
  Future<Position> current() async {
    calls++;
    if (denied) {
      throw const ApiException('Cần quyền vị trí để điểm danh đợt này.');
    }
    return Position(
      longitude: 106.5,
      latitude: 10.5,
      timestamp: DateTime(2026),
      accuracy: 10,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

void main() {
  testWidgets(
    'Guest attendance → login → attendance; logout removes profile and guards again',
    (tester) async {
      final store = MemoryTokenStore();
      var loginCalls = 0;
      final auth = AuthController(
        api: StudentApi(
          store: store,
          client: MockClient((request) async {
            if (request.url.path == '/api/login') {
              loginCalls++;
              return jsonResponse(tokens());
            }
            return jsonResponse(profileJson);
          }),
        ),
      );
      addTearDown(auth.dispose);
      await tester.pumpWidget(MaterialApp(home: HomeScreen(auth: auth)));
      await tester.pumpAndSettle();
      void select(BottomMenu menu) => tester
          .widget<AppBottomBar>(find.byType(AppBottomBar))
          .onSelected(menu);
      select(BottomMenu.attendance);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(AccountScreen), findsNothing);
      await tester.ensureVisible(find.text('ĐĂNG NHẬP'));
      await tester.tap(find.text('ĐĂNG NHẬP'));
      await tester.pumpAndSettle();
      expect(loginCalls, 0);
      expect(find.text('Vui lòng nhập mã số sinh viên.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '123456');
      await tester.enterText(find.byType(TextFormField).last, 'demo-password');
      await tester.ensureVisible(find.text('ĐĂNG NHẬP'));
      await tester.tap(find.text('ĐĂNG NHẬP'));
      await tester.pumpAndSettle();
      expect(loginCalls, 1);
      expect(find.byType(AttendanceScreen), findsOneWidget);
      select(BottomMenu.account);
      await tester.pumpAndSettle();
      expect(find.text('Sinh Viên Test'), findsOneWidget);
      await tester.tap(find.byTooltip('Đăng xuất'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sinh Viên Test'), findsNothing);
      expect(store.value, isNull);
      select(BottomMenu.attendance);
      await tester.pumpAndSettle();
      expect(find.byType(AttendanceScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets(
    'Small login screen scrolls with keyboard, masks password and shows API error',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final gate = Completer<http.Response>();
      var calls = 0;
      final auth = AuthController(
        api: StudentApi(
          store: MemoryTokenStore(),
          client: MockClient((_) {
            calls++;
            return gate.future;
          }),
        ),
      );
      addTearDown(auth.dispose);
      await auth.initialize();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: LoginScreen(auth: auth)),
        ),
      );
      await tester.enterText(find.byType(TextFormField).first, '123456');
      await tester.enterText(find.byType(TextFormField).last, 'wrong');
      expect(
        tester.widgetList<TextField>(find.byType(TextField)).last.obscureText,
        isTrue,
      );
      await tester.ensureVisible(find.byTooltip('Hiện mật khẩu'));
      await tester.tap(find.byTooltip('Hiện mật khẩu'));
      await tester.pump();
      expect(
        tester.widgetList<TextField>(find.byType(TextField)).last.obscureText,
        isFalse,
      );
      await tester.ensureVisible(find.text('ĐĂNG NHẬP'));
      await tester.tap(find.text('ĐĂNG NHẬP'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      gate.complete(
        jsonResponse({'message': 'MSSV hoặc mật khẩu không đúng.'}, 401),
      );
      await tester.pumpAndSettle();
      expect(find.text('MSSV hoặc mật khẩu không đúng.'), findsOneWidget);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final requiresLocation in [false, true]) {
    testWidgets(
      'Attendance requests GPS only when required: $requiresLocation',
      (tester) async {
        final store = MemoryTokenStore()..value = jsonEncode(tokens());
        final location = FakeLocation();
        var calls = 0;
        final api = StudentApi(
          store: store,
          client: MockClient((request) async {
            calls++;
            final body = jsonDecode(request.body) as Map;
            expect(body['code'], 'ABC123');
            if (requiresLocation && !body.containsKey('latitude')) {
              return jsonResponse({
                'message':
                    'Đợt điểm danh này yêu cầu vị trí (latitude, longitude).',
              }, 400);
            }
            if (requiresLocation) expect(body['latitude'], 10.5);
            return jsonResponse({
              'message': 'Điểm danh thành công.',
              'sessionName': 'Buổi test',
              'checkedInAt': '2026-09-30T09:15:32.1234567',
              'distanceMeters': requiresLocation ? 12.4 : null,
            });
          }),
        );
        addTearDown(api.close);
        await api.restore();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AttendanceScreen(api: api, location: location),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), 'abc123');
        await tester.ensureVisible(find.text('Điểm danh'));
        await tester.tap(find.text('Điểm danh'));
        await tester.pumpAndSettle();
        expect(find.text('Điểm danh thành công.'), findsOneWidget);
        expect(find.text('Giờ Việt Nam: 2026-09-30 09:15:32'), findsOneWidget);
        expect(location.calls, requiresLocation ? 1 : 0);
        expect(calls, requiresLocation ? 2 : 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('Denied GPS shows reason without resubmitting attendance', (
    tester,
  ) async {
    final store = MemoryTokenStore()..value = jsonEncode(tokens());
    final location = FakeLocation()..denied = true;
    var calls = 0;
    final api = StudentApi(
      store: store,
      client: MockClient((_) async {
        calls++;
        return jsonResponse({
          'message': 'Đợt điểm danh này yêu cầu vị trí (latitude, longitude).',
        }, 400);
      }),
    );
    addTearDown(api.close);
    await api.restore();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttendanceScreen(api: api, location: location),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'abc123');
    await tester.ensureVisible(find.text('Điểm danh'));
    await tester.tap(find.text('Điểm danh'));
    await tester.pumpAndSettle();
    expect(find.text('Cần quyền vị trí để điểm danh đợt này.'), findsOneWidget);
    expect(calls, 1);
  });
}
