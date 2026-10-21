import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/controllers/auth_controller.dart';
import 'package:flutter_application_1/controllers/menu_sync_controller.dart';
import 'package:flutter_application_1/helpers/DBUtils.dart';
import 'package:flutter_application_1/services/student_api.dart';
import 'package:flutter_application_1/widgets/account_screen.dart';
import 'package:flutter_application_1/widgets/attendance_screen.dart';
import 'package:flutter_application_1/widgets/app_bottom_bar.dart';
import 'package:flutter_application_1/widgets/app_drawer.dart';
import 'package:flutter_application_1/widgets/app_top_bar.dart';
import 'package:flutter_application_1/widgets/home_screen.dart';
import 'package:flutter_application_1/widgets/splash_screen.dart';

import 'menu_fixtures.dart';
import 'student_api_test.dart'
    show MemoryTokenStore, jsonResponse, tokens, profileJson;

// Chỉ dùng khi chủ động bật UEH_LIVE_TEST; widget test mặc định chặn HTTP thật.
class _LiveHttpOverrides extends HttpOverrides {}

const _feedHtml = '''
<section><header><h2 class="ueh-block-title">Tin tức</h2>
<p>Thông tin mới nhất và kiến thức hữu ích từ UEH</p></header>
<div class="grid-container">
<article><figure><img src="/featured.png"></figure>
<p><a href="/featured?app=true">Bài nổi bật &amp; UEH</a></p></article>
<article><div class="content"><h3><a class="news-title-view">CUỘC SỐNG UEH</a></h3>
<h3><a href="/article?app=true">Bài viết cuộc sống UEH</a></h3></div></article>
</div></section>
''';

NewsService _service() => NewsService(
  client: MockClient(
    (request) async => http.Response.bytes(utf8.encode(_feedHtml), 200),
  ),
);

void main() {
  testWidgets(
    'Menu mở bài bằng WebView của Home, reload/retry đúng URL và Back về danh sách',
    (tester) async {
      final previousPlatform = WebViewPlatform.instance;
      final platform = _FakeWebViewPlatform();
      WebViewPlatform.instance = platform;
      addTearDown(() {
        WebViewPlatform.instance = previousPlatform ?? _FakeWebViewPlatform();
      });
      await tester.pumpWidget(const MyApp());
      await tester.pump(SplashScreen.displayDuration);
      await tester.pumpAndSettle();
      final homeState = tester.state(find.byType(HomeScreen));
      final homeController = tester
          .widget<WebViewWidget>(find.byType(WebViewWidget))
          .platform
          .params
          .controller;
      expect(
        platform.controller.loads.single.toString(),
        HomeScreen.websiteUrl,
      );
      expect(platform.controller.javaScriptMode, JavaScriptMode.unrestricted);

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      (scaffold.drawer! as AppDrawer).onSelected(
        const MenuNav(
          id: 1,
          iconName: 'newspaper',
          menuName: 'Tin tức UEH',
          menuUrl: HomeScreen.websiteUrl,
          ordering: 0,
        ),
      );
      await tester.pumpAndSettle();
      final article = NewsArticle(
        title: 'Tin UEH',
        url: Uri.parse('https://ueh.edu.vn/article?app=true'),
        category: 'Cuộc sống UEH',
      );
      tester
          .widget<NewsListContent>(find.byType(NewsListContent))
          .onSelected(article);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<WebViewWidget>(find.byType(WebViewWidget))
            .platform
            .params
            .controller,
        same(homeController),
      );
      expect(platform.controller.loads.last, article.url);
      expect(platform.createdControllers, 1);
      expect(
        find.text('Tin UEH'),
        findsNothing,
      ); // Nội dung do website hiển thị.

      await tester.tap(find.byTooltip('Tải lại'));
      await tester.pumpAndSettle();
      expect(platform.controller.reloads, 1);
      platform.delegate.onError!(
        const WebResourceError(
          errorCode: -2,
          description: 'Mất kết nối',
          isForMainFrame: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thử lại'));
      await tester.pumpAndSettle();
      expect(platform.controller.loads.last, article.url);

      await tester.binding.handlePopRoute();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(NewsListContent), findsOneWidget);
      expect(find.byType(WebViewWidget), findsNothing);
      expect(
        tester.widget<AppTopBar>(find.byType(AppTopBar)).title,
        'Tin tức UEH',
      );

      tester
          .widget<NewsListContent>(find.byType(NewsListContent))
          .onSelected(article);
      await tester.pumpAndSettle();
      tester
          .widget<AppBottomBar>(find.byType(AppBottomBar))
          .onSelected(BottomMenu.home);
      await tester.pumpAndSettle();
      expect(platform.controller.loads.last.toString(), HomeScreen.websiteUrl);
      expect(tester.state(find.byType(HomeScreen)), same(homeState));
      expect(
        tester
            .widget<WebViewWidget>(find.byType(WebViewWidget))
            .platform
            .params
            .controller,
        same(homeController),
      );
      expect(
        tester.widget<AppTopBar>(find.byType(AppTopBar)).title,
        'Trang chủ',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant({TargetPlatform.android}),
  );

  test('Đọc danh sách tin: tiêu đề, category và URL bài gốc', () async {
    final service = _service();
    addTearDown(service.close);
    final feed = await service.fetchFeed(
      Uri.parse('https://ueh.edu.vn/tintucmobile'),
    );
    expect(feed.articles.length, 2);
    expect(feed.articles.first.title, 'Bài nổi bật & UEH');
    expect(
      feed.articles.first.imageUrl.toString(),
      'https://ueh.edu.vn/featured.png',
    );
    expect(feed.articles.last.category, 'CUỘC SỐNG UEH');
    expect(
      feed.articles.last.url.toString(),
      'https://ueh.edu.vn/article?app=true',
    );
  });

  test('Nguồn UEH thật trả về URL bài viết', () async {
    final service = NewsService(
      client: IOClient(_LiveHttpOverrides().createHttpClient(null)),
    );
    addTearDown(service.close);
    final feed = await service.fetchFeed(Uri.parse(HomeScreen.websiteUrl));
    expect(feed.articles.length, greaterThan(1));
    for (final article in feed.articles) {
      expect(article.title, isNotEmpty);
      expect(article.url.scheme, 'https');
      expect(article.url.queryParameters['app'], 'true');
    }
  }, skip: !const bool.fromEnvironment('UEH_LIVE_TEST'));

  testWidgets('Tin nổi bật dùng Stack và nhấn mở đúng bài', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _service();
    addTearDown(service.close);
    NewsArticle? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NewsListContent(
            uri: Uri.parse('https://ueh.edu.vn/tintucmobile'),
            service: service,
            onSelected: (article) => selected = article,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final title = find.text('TIN TỨC NỔI BẬT');
    expect(
      find.ancestor(of: title, matching: find.byType(Stack)),
      findsWidgets,
    );
    await tester.tap(title);
    expect(selected?.url.path, '/featured');
    await tester.ensureVisible(find.text('Bài viết cuộc sống UEH'));
    await tester.tap(find.text('Bài viết cuộc sống UEH'));
    expect(selected?.url.path, '/article');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Bottom Trang chủ trả về Home hiện có và giữ nguyên màu thanh điều hướng',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      final homeState = tester.state(find.byType(HomeScreen));
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      (scaffold.drawer! as AppDrawer).onSelected(
        const MenuNav(
          id: 1,
          iconName: 'newspaper',
          menuName: 'Tin tức UEH',
          menuUrl: HomeScreen.websiteUrl,
          ordering: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NewsListContent), findsOneWidget);
      expect(
        tester.widget<AppTopBar>(find.byType(AppTopBar)).title,
        'Tin tức UEH',
      );
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .selectedItemColor,
        AppTopBar.uehBlue,
      );
      tester
          .widget<AppBottomBar>(find.byType(AppBottomBar))
          .onSelected(BottomMenu.home);
      await tester.pumpAndSettle();
      expect(find.byType(NewsListContent), findsNothing);
      expect(tester.state(find.byType(HomeScreen)), same(homeState));
      expect(
        tester.widget<AppTopBar>(find.byType(AppTopBar)).title,
        'Trang chủ',
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({TargetPlatform.linux}),
  );

  testWidgets('Splash chuyển sang home và không còn trong lịch sử', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    await tester.pump(SplashScreen.displayDuration);
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsNothing);
    final appBarTitle = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Trang chủ'),
    );
    expect(appBarTitle, findsOneWidget);
    expect(find.byTooltip('Trang chủ'), findsOneWidget);
    final context = tester.element(appBarTitle);
    expect(GoRouter.of(context).canPop(), isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant({TargetPlatform.linux}));

  testWidgets('Đóng splash sớm không gây điều hướng sau dispose', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(SplashScreen.displayDuration);
    expect(tester.takeException(), isNull);
  });

  group('Back khi Drawer đang mở (Android, predictive back)', () {
    final android = TargetPlatformVariant({TargetPlatform.android});
    late _FakeWebViewPlatform platform;
    late List<Object?> frameworkHandlesBack; // tín hiệu Flutter gửi Android
    late int exitRequests; // số lần Flutter yêu cầu thoát app

    setUp(() {
      final previous = WebViewPlatform.instance;
      platform = _FakeWebViewPlatform();
      WebViewPlatform.instance = platform;
      addTearDown(
        () => WebViewPlatform.instance = previous ?? _FakeWebViewPlatform(),
      );
    });

    // Dựng HomeScreen qua GoRouter như app thật, chỉ thay mạng và SQLite.
    Future<AuthController> pumpHome(
      WidgetTester tester, {
      bool loggedIn = false,
    }) async {
      frameworkHandlesBack = [];
      exitRequests = 0;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          frameworkHandlesBack.add(call.arguments);
        }
        if (call.method == 'SystemNavigator.pop') exitRequests++;
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      final api = StudentApi(
        store: MemoryTokenStore()
          ..value = loggedIn ? jsonEncode(tokens()) : null,
        client: MockClient(
          (request) async => request.url.path == '/api/menu'
              ? jsonResponse(menuJson)
              : jsonResponse(profileJson),
        ),
      );
      final auth = AuthController(api: api);
      final menu = MenuSyncController(api: api, store: MemoryMenuStore(apiMenus));
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => HomeScreen(auth: auth, menu: menu),
          ),
        ],
      );
      addTearDown(() {
        router.dispose();
        menu.dispose();
        auth.dispose();
      });
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return auth;
    }

    bool drawerOpen(WidgetTester tester) =>
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen;
    bool canPop(WidgetTester tester) => tester
        .widget<PopScope<Object?>>(find.byWidgetPredicate((w) => w is PopScope))
        .canPop;
    String title(WidgetTester tester) =>
        tester.widget<AppTopBar>(find.byType(AppTopBar)).title;
    void select(WidgetTester tester, BottomMenu menu) =>
        tester.widget<AppBottomBar>(find.byType(AppBottomBar)).onSelected(menu);
    Future<void> openDrawer(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Mở menu'));
      await tester.pumpAndSettle();
    }

    // Back của hệ thống: WidgetsBinding → GoRouter.popRoute → Navigator.maybePop.
    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    // Cử chỉ vuốt Back (predictive back) Android gửi qua kênh flutter/backgesture.
    Future<void> backGesture(WidgetTester tester, String method) async {
      final args = method == 'startBackGesture'
          ? <String, Object?>{
              'touchOffset': <double>[790, 300],
              'progress': 0.0,
              'swipeEdge': 1, // cạnh phải
            }
          : null;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.backGesture.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Trang chủ: Back chỉ đóng Drawer; Android được báo Flutter tự xử lý Back', (
      tester,
    ) async {
      await pumpHome(tester);
      final loads = platform.controller.loads.length;
      expect(canPop(tester), isTrue);

      await openDrawer(tester);
      expect(drawerOpen(tester), isTrue);
      expect(canPop(tester), isFalse);
      expect(frameworkHandlesBack.last, isTrue);

      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(exitRequests, 0);
      expect(title(tester), 'Trang chủ');
      expect(platform.controller.loads.length, loads); // WebView không tải lại
      expect(platform.controller.reloads, 0);
      expect(canPop(tester), isTrue);
      expect(frameworkHandlesBack.last, isFalse);

      await back(tester); // Drawer đã đóng: giữ hành vi cũ ở Trang chủ
      expect(exitRequests, 1);
      expect(tester.takeException(), isNull);
    }, variant: android);

    testWidgets('Điểm danh: Back lần 1 chỉ đóng Drawer, lần 2 về Trang chủ', (
      tester,
    ) async {
      await pumpHome(tester, loggedIn: true);
      select(tester, BottomMenu.attendance);
      await tester.pumpAndSettle();
      expect(find.byType(AttendanceScreen), findsOneWidget);

      await openDrawer(tester);
      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(find.byType(AttendanceScreen), findsOneWidget);
      expect(title(tester), 'Điểm danh');

      await back(tester);
      expect(find.byType(AttendanceScreen), findsNothing);
      expect(title(tester), 'Trang chủ');
      expect(exitRequests, 0);
      expect(tester.takeException(), isNull);
    }, variant: android);

    testWidgets('Tài khoản: Back khi Drawer mở không đăng xuất, không đổi tab', (
      tester,
    ) async {
      final auth = await pumpHome(tester, loggedIn: true);
      select(tester, BottomMenu.account);
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);

      await openDrawer(tester);
      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(title(tester), 'Tài khoản');
      expect(auth.isLoggedIn, isTrue);

      await back(tester);
      expect(find.byType(AccountScreen), findsNothing);
      expect(title(tester), 'Trang chủ');
      expect(auth.isLoggedIn, isTrue);
      expect(exitRequests, 0);
    }, variant: android);

    testWidgets('Danh sách tin: Back khi Drawer mở giữ nguyên danh sách', (
      tester,
    ) async {
      await pumpHome(tester);
      await openDrawer(tester);
      await tester.tap(find.text('Tin tức UEH'));
      await tester.pumpAndSettle();
      expect(drawerOpen(tester), isFalse);
      expect(find.byType(NewsListContent), findsOneWidget);

      await openDrawer(tester);
      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(find.byType(NewsListContent), findsOneWidget);
      expect(title(tester), 'Tin tức UEH');

      await back(tester);
      expect(find.byType(NewsListContent), findsNothing);
      expect(title(tester), 'Trang chủ');
      expect(exitRequests, 0);
    }, variant: android);

    testWidgets('WebView có lịch sử: Back khi Drawer mở không gọi goBack', (
      tester,
    ) async {
      platform.hasHistory = true;
      await pumpHome(tester);
      expect(canPop(tester), isFalse);

      await openDrawer(tester);
      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(platform.controller.goBacks, 0);

      await back(tester);
      expect(platform.controller.goBacks, 1);
      expect(exitRequests, 0);
    }, variant: android);

    testWidgets('Đóng Drawer bằng vùng tối, kéo và chọn menu vẫn đồng bộ trạng thái', (
      tester,
    ) async {
      await pumpHome(tester);

      await openDrawer(tester);
      await tester.tapAt(const Offset(780, 300)); // vùng tối bên phải Drawer
      await tester.pumpAndSettle();
      expect(drawerOpen(tester), isFalse);
      expect(canPop(tester), isTrue);
      expect(frameworkHandlesBack.last, isFalse);

      await openDrawer(tester);
      await tester.fling(find.byType(Drawer), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(drawerOpen(tester), isFalse);
      expect(canPop(tester), isTrue);

      await openDrawer(tester);
      await tester.tap(find.text('Sự kiện UEH'));
      await tester.pumpAndSettle();
      expect(drawerOpen(tester), isFalse);
      expect(canPop(tester), isTrue);
      expect(
        find.text('Sự kiện UEH: chức năng hiện chưa khả dụng.'),
        findsOneWidget,
      );

      await back(tester); // không bị kẹt ở trạng thái "Drawer mở"
      expect(exitRequests, 1);
      expect(tester.takeException(), isNull);
    }, variant: android);

    testWidgets('Vuốt Back khi Drawer mở: Drawer tự đóng giữa chừng vẫn không đổi tab', (
      tester,
    ) async {
      await pumpHome(tester, loggedIn: true);
      select(tester, BottomMenu.account);
      await tester.pumpAndSettle();
      await openDrawer(tester);

      await backGesture(tester, 'startBackGesture');
      // Tái hiện điều quan sát trên Android 17: các chạm đầu của cú vuốt làm
      // Drawer tự đóng trước khi Back được xác nhận.
      tester.state<ScaffoldState>(find.byType(Scaffold).first).closeDrawer();
      await tester.pumpAndSettle();
      await backGesture(tester, 'commitBackGesture');

      expect(drawerOpen(tester), isFalse);
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(title(tester), 'Tài khoản');
      expect(exitRequests, 0);

      // Trang chủ: vuốt Back khi Drawer mở chỉ đóng Drawer, không thoát app.
      select(tester, BottomMenu.home);
      await tester.pumpAndSettle();
      await openDrawer(tester);
      await backGesture(tester, 'startBackGesture');
      await backGesture(tester, 'commitBackGesture');
      expect(drawerOpen(tester), isFalse);
      expect(title(tester), 'Trang chủ');
      expect(exitRequests, 0);
    }, variant: android);

    testWidgets('Vuốt Back rồi huỷ: Drawer vẫn mở, các lần Back sau vẫn đúng', (
      tester,
    ) async {
      await pumpHome(tester, loggedIn: true);
      select(tester, BottomMenu.attendance);
      await tester.pumpAndSettle();
      await openDrawer(tester);

      await backGesture(tester, 'startBackGesture');
      await backGesture(tester, 'cancelBackGesture');
      expect(drawerOpen(tester), isTrue);
      expect(find.byType(AttendanceScreen), findsOneWidget);

      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(find.byType(AttendanceScreen), findsOneWidget);
      await back(tester);
      expect(title(tester), 'Trang chủ');
      expect(exitRequests, 0);
    }, variant: android);

    testWidgets('Vuốt Back khi Drawer đóng: giữ hành vi cũ (Điểm danh → Trang chủ)', (
      tester,
    ) async {
      await pumpHome(tester, loggedIn: true);
      select(tester, BottomMenu.attendance);
      await tester.pumpAndSettle();

      await backGesture(tester, 'startBackGesture');
      await backGesture(tester, 'commitBackGesture');
      expect(find.byType(AttendanceScreen), findsNothing);
      expect(title(tester), 'Trang chủ');
      expect(exitRequests, 0);
    }, variant: android);
  });
}

class _FakeWebViewPlatform extends WebViewPlatform {
  late _FakeWebViewController controller;
  late _FakeNavigationDelegate delegate;
  int createdControllers = 0;
  bool hasHistory = false;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    createdControllers++;
    return controller = _FakeWebViewController(params)..hasHistory = hasHistory;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate = _FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);
}

class _FakeWebViewController extends PlatformWebViewController {
  _FakeWebViewController(super.params) : super.implementation();
  final loads = <Uri>[];
  int reloads = 0;
  JavaScriptMode? javaScriptMode;
  _FakeNavigationDelegate? delegate;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async =>
      javaScriptMode = mode;

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate value,
  ) async {
    delegate = value as _FakeNavigationDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loads.add(params.uri);
    delegate?.onProgress?.call(100);
  }

  /// Giả lập WebView đã có trang trước trong lịch sử.
  bool hasHistory = false;
  int goBacks = 0;

  @override
  Future<bool> canGoBack() async => hasHistory;

  @override
  Future<void> goBack() async {
    goBacks++;
    delegate?.onProgress?.call(100);
  }

  @override
  Future<void> reload() async {
    reloads++;
    delegate?.onProgress?.call(100);
  }
}

class _FakeNavigationDelegate extends PlatformNavigationDelegate {
  _FakeNavigationDelegate(super.params) : super.implementation();
  ProgressCallback? onProgress;
  WebResourceErrorCallback? onError;

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {}
  @override
  Future<void> setOnProgress(ProgressCallback callback) async =>
      onProgress = callback;
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async =>
      onError = callback;
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
