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
import 'package:flutter_application_1/models/news.dart';
import 'package:flutter_application_1/services/student_api.dart';
import 'package:flutter_application_1/widgets/account_screen.dart';
import 'package:flutter_application_1/widgets/attendance_screen.dart';
import 'package:flutter_application_1/widgets/app_bottom_bar.dart';
import 'package:flutter_application_1/widgets/app_drawer.dart';
import 'package:flutter_application_1/widgets/all_news.dart';
import 'package:flutter_application_1/widgets/app_top_bar.dart';
import 'package:flutter_application_1/widgets/category_news.dart';
import 'package:flutter_application_1/widgets/featured_news.dart';
import 'package:flutter_application_1/widgets/home_screen.dart';
import 'package:flutter_application_1/widgets/news_detail.dart';
import 'package:flutter_application_1/services/news_api.dart';
import 'package:flutter_application_1/widgets/splash_screen.dart';

import 'menu_fixtures.dart';
import 'news_fixtures.dart';
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

/// Một tin giả của chuyên mục [cat] (uid = cat * 1000 + vị trí). Tin càng sau
/// càng cũ; cùng vị trí thì mục 222 mới nhất, để 4 mục xen kẽ khi ghép.
Map<String, Object?> _categoryItem(int uid) => {
  'uid': uid,
  'cat_uid': uid ~/ 1000,
  'category_name': 'Mục ${uid ~/ 1000}',
  'title': 'Tin $uid',
  'short_desc': '',
  'post_date': DateTime(2026, 10, 13, 8)
      .subtract(Duration(hours: uid % 1000))
      .add(Duration(minutes: uid ~/ 1000 - 219))
      .toIso8601String(),
  'sdgs': [4],
  'is_featured': false,
  'background_img': null,
  'thumbnail_img': null,
};

/// NewsApi giả cho Trang chủ: featured trả JSON thật; API chuyên mục trả
/// [categoryTotal] tin theo limit/offset (mặc định trang rỗng); chi tiết
/// /api/news/{uid} trả tin đó kèm content HTML. [log] ghi lại URL mọi request.
NewsApi _newsApi([List<Uri>? log, int categoryTotal = 0]) {
  final featured = jsonDecode(featuredJson) as List<dynamic>;
  final api = NewsApi(
    client: MockClient((request) async {
      log?.add(request.url);
      final path = request.url.path;
      Object? body;
      if (path == '/api/news/featured') {
        body = featured;
      } else if (path == '/api/news') {
        final q = request.url.queryParameters;
        final cat = int.parse(q['cat_uid']!);
        final limit = int.parse(q['limit']!);
        final offset = int.parse(q['offset']!);
        body = {
          'total': categoryTotal,
          'limit': limit,
          'offset': offset,
          'items': [
            for (var i = offset; i < offset + limit && i < categoryTotal; i++)
              _categoryItem(cat * 1000 + i),
          ],
        };
      } else {
        final uid = int.parse(request.url.pathSegments.last);
        final item = featured.firstWhere(
          (e) => e['uid'] == uid,
          orElse: () => _categoryItem(uid),
        );
        body = {...item as Map, 'content': '<p>Nội dung bài $uid</p>'};
      }
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
    }),
  );
  addTearDown(api.close);
  return api;
}

const _externalMenu = MenuNav(
  id: 99,
  iconName: 'globe',
  menuName: 'Trang ngoài',
  menuUrl: 'https://ueh.edu.vn/trang-khac',
  ordering: 99,
);

NewsService _service() => NewsService(
  client: MockClient(
    (request) async => http.Response.bytes(utf8.encode(_feedHtml), 200),
  ),
);

void main() {
  testWidgets(
    'Trang chủ không dùng WebView; menu có URL ngoài mở WebView, reload/retry đúng URL, Back về Trang chủ',
    (tester) async {
      final previousPlatform = WebViewPlatform.instance;
      final platform = _FakeWebViewPlatform();
      WebViewPlatform.instance = platform;
      addTearDown(() {
        WebViewPlatform.instance = previousPlatform ?? _FakeWebViewPlatform();
      });
      final newsLog = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(newsApi: _newsApi(newsLog))),
      );
      await tester.pumpAndSettle();
      final homeState = tester.state(find.byType(HomeScreen));
      // Trang chủ: tin nổi bật native từ News REST API, không tạo WebView.
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(find.byType(WebViewWidget), findsNothing);
      expect(platform.createdControllers, 0);
      expect(newsLog.first.path, '/api/news/featured');

      // "Tin tức UEH" về giao diện tin tức native, không mở website.
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      final drawer = scaffold.drawer! as AppDrawer;
      drawer.onSelected(
        const MenuNav(
          id: 1,
          iconName: 'newspaper',
          menuName: 'Tin tức UEH',
          menuUrl: HomeScreen.websiteUrl,
          ordering: 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(platform.createdControllers, 0);
      expect(
        tester.widget<AppTopBar>(find.byType(AppTopBar)).title,
        'Tin tức UEH',
      );

      // Menu có URL ngoài: mới tạo WebView và tải đúng URL đó.
      drawer.onSelected(_externalMenu);
      await tester.pumpAndSettle();
      expect(platform.createdControllers, 1);
      expect(platform.controller.loads.single.toString(), _externalMenu.menuUrl);
      expect(platform.controller.javaScriptMode, JavaScriptMode.unrestricted);
      expect(find.byType(FeaturedNewsContent), findsNothing);

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
      expect(platform.controller.loads.last.toString(), _externalMenu.menuUrl);

      // Không có lịch sử web: Back về Trang chủ (tin tức native).
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(WebViewWidget), findsNothing);
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(
        tester.widget<AppTopBar>(find.byType(AppTopBar)).title,
        'Trang chủ',
      );
      expect(tester.state(find.byType(HomeScreen)), same(homeState));
      expect(platform.createdControllers, 1);
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
    'Bottom Trang chủ trả về Home hiện có và dùng màu xanh của thanh điều hướng',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(newsApi: _newsApi())),
      );
      await tester.pumpAndSettle();
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
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(find.byType(NewsListContent), findsNothing);
      expect(
        tester.widget<AppTopBar>(find.byType(AppTopBar)).title,
        'Tin tức UEH',
      );
      expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .selectedItemColor,
        AppBottomBar.selectedColor,
      );
      tester
          .widget<AppBottomBar>(find.byType(AppBottomBar))
          .onSelected(BottomMenu.home);
      await tester.pumpAndSettle();
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
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
    // Sau Splash, Trang chủ là giao diện tin tức native (không phải WebView).
    expect(find.byType(FeaturedNewsContent), findsOneWidget);
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
    late List<Uri> newsRequests; // request tới News REST API

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
      int categoryTotal = 0,
    }) async {
      frameworkHandlesBack = [];
      exitRequests = 0;
      newsRequests = [];
      final news = _newsApi(newsRequests, categoryTotal);
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
            builder: (_, _) => HomeScreen(auth: auth, menu: menu, newsApi: news),
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
      final requests = newsRequests.length;
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(canPop(tester), isTrue);

      await openDrawer(tester);
      expect(drawerOpen(tester), isTrue);
      expect(canPop(tester), isFalse);
      expect(frameworkHandlesBack.last, isTrue);

      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(exitRequests, 0);
      expect(title(tester), 'Trang chủ');
      expect(newsRequests.length, requests); // tin tức không tải lại
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
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

    testWidgets('Tin tức UEH (Drawer): Back khi Drawer mở giữ nguyên trang tin', (
      tester,
    ) async {
      await pumpHome(tester);
      await openDrawer(tester);
      await tester.tap(find.text('Tin tức UEH'));
      await tester.pumpAndSettle();
      expect(drawerOpen(tester), isFalse);
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(title(tester), 'Tin tức UEH');

      await openDrawer(tester);
      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(title(tester), 'Tin tức UEH');
      expect(exitRequests, 0);

      // Trang tin chính là Trang chủ (không phải màn hình con): Drawer đóng thì
      // Back giữ hành vi ở Trang chủ.
      await back(tester);
      expect(exitRequests, 1);
      expect(platform.createdControllers, 0);
    }, variant: android);

    Future<void> openMore(WidgetTester tester) async {
      final more = find.text('Xem thêm');
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
    }

    // Trang chủ → Xem thêm → chạm tên chuyên mục trên thẻ của danh sách tổng hợp.
    Future<void> openCategory(WidgetTester tester, int catUid) async {
      await openMore(tester);
      final label = find
          .descendant(
            of: find.byType(AllNewsContent),
            matching: find.text('MỤC $catUid'),
          )
          .first;
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      await tester.tap(label);
      await tester.pumpAndSettle();
    }

    testWidgets('Chuyên mục (từ danh sách tổng hợp): Back về danh sách, rồi về Trang chủ, không thoát app', (
      tester,
    ) async {
      await pumpHome(tester, categoryTotal: 2);
      final featuredRequests = newsRequests
          .where((u) => u.path == '/api/news/featured')
          .length;
      await openCategory(tester, 220);
      expect(find.byType(CategoryNewsContent), findsOneWidget);
      expect(title(tester), 'Khoa học - Góc nhìn chuyên gia');
      expect(newsRequests.last.queryParameters['cat_uid'], '220');
      expect(canPop(tester), isFalse);
      expect(frameworkHandlesBack.last, isTrue);

      await back(tester);
      expect(find.byType(CategoryNewsContent), findsNothing);
      expect(find.byType(AllNewsContent), findsOneWidget);
      expect(title(tester), 'Trang chủ');
      expect(canPop(tester), isFalse);

      await back(tester);
      expect(find.byType(AllNewsContent), findsNothing);
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(title(tester), 'Trang chủ');
      expect(exitRequests, 0);
      // Trang chủ được giữ nguyên, không tải lại tin nổi bật.
      expect(
        newsRequests.where((u) => u.path == '/api/news/featured').length,
        featuredRequests,
      );
      expect(canPop(tester), isTrue);
    }, variant: android);

    testWidgets('Chuyên mục: Drawer mở + Back chỉ đóng Drawer; tab Trang chủ về Trang chủ', (
      tester,
    ) async {
      await pumpHome(tester, categoryTotal: 2);
      await openCategory(tester, 221);
      await openDrawer(tester);
      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(find.byType(CategoryNewsContent), findsOneWidget);
      expect(title(tester), 'Báo chí nói về UEH');

      select(tester, BottomMenu.home);
      await tester.pumpAndSettle();
      expect(find.byType(CategoryNewsContent), findsNothing);
      expect(title(tester), 'Trang chủ');
      expect(exitRequests, 0);
    }, variant: android);

    // Danh sách còn tin thì có vòng xoay cuối trang: không dùng pumpAndSettle.
    Future<void> frames(WidgetTester tester) async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('Chi tiết: chạm tin lớn gọi đúng uid; Back về Trang chủ', (
      tester,
    ) async {
      await pumpHome(tester);
      await tester.tap(find.byType(FeaturedNewsCard));
      await tester.pumpAndSettle();
      expect(newsRequests.last.path, '/api/news/1');
      expect(find.byType(NewsDetailContent), findsOneWidget);
      expect(find.text('Nội dung bài 1'), findsOneWidget);
      expect(title(tester), 'Cuộc sống UEH');
      expect(canPop(tester), isFalse);
      expect(frameworkHandlesBack.last, isTrue);

      await back(tester);
      expect(find.byType(NewsDetailContent), findsNothing);
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(title(tester), 'Trang chủ');
      expect(exitRequests, 0);
      expect(platform.createdControllers, 0); // không dùng WebView
    }, variant: android);

    // Thẻ tin nhỏ ở Trang chủ thuộc chuyên mục [catUid].
    Finder homeTile(int catUid) => find.descendant(
      of: find.byType(FeaturedNewsContent),
      matching: find.byWidgetPredicate(
        (w) => w is NewsTile && w.item.catUid == catUid,
      ),
    );

    testWidgets('Trang chủ: mỗi thẻ tin nhỏ mở đúng danh sách chuyên mục 219-222, không mở bài; Back về Trang chủ', (
      tester,
    ) async {
      await pumpHome(tester, categoryTotal: 2);
      final featuredRequests = newsRequests
          .where((u) => u.path == '/api/news/featured')
          .length;
      for (final category in NewsCategory.all) {
        final before = newsRequests.length;
        final tile = homeTile(category.uid);
        expect(tile, findsOneWidget);
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(tile);
        await tester.pumpAndSettle();
        expect(find.byType(CategoryNewsContent), findsOneWidget);
        expect(find.byType(NewsDetailContent), findsNothing);
        expect(title(tester), category.name);
        final opened = newsRequests.skip(before).toList();
        expect(opened, hasLength(1));
        expect(opened.single.path, '/api/news');
        expect(opened.single.queryParameters['cat_uid'], '${category.uid}');

        await back(tester);
        expect(find.byType(CategoryNewsContent), findsNothing);
        expect(find.byType(AllNewsContent), findsNothing);
        expect(find.byType(FeaturedNewsContent), findsOneWidget);
        expect(title(tester), 'Trang chủ');
        expect(canPop(tester), isTrue);
      }
      expect(exitRequests, 0);
      // Trang chủ được giữ nguyên, không tải lại tin nổi bật.
      expect(
        newsRequests.where((u) => u.path == '/api/news/featured').length,
        featuredRequests,
      );
    }, variant: android);

    testWidgets('Trang chủ → Cuộc sống UEH: chỉ gọi cat_uid=219, lazy load offset 20, 40; chạm bài mới gọi chi tiết; Back giữ tin và vị trí cuộn', (
      tester,
    ) async {
      await pumpHome(tester, categoryTotal: 45);
      final before = newsRequests.length;
      final tile = homeTile(219);
      await tester.ensureVisible(tile);
      await frames(tester);
      await tester.tap(tile);
      await frames(tester);
      expect(title(tester), 'Cuộc sống UEH');
      final category = find.byType(CategoryNewsContent);
      expect(
        find.descendant(of: category, matching: find.text('Trang chủ')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: category, matching: find.text('Cuộc sống UEH')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: category, matching: find.byType(NewsPreviewCard)),
        findsWidgets,
      );
      List<String> calls() => [
        for (final u in newsRequests.skip(before))
          u.path == '/api/news'
              ? '${u.queryParameters['cat_uid']}@${u.queryParameters['offset']}'
              : u.path,
      ];
      // Chỉ mục 219, trang đầu offset 0; chưa gọi API chi tiết.
      expect(calls(), ['219@0']);

      final list = find.descendant(
        of: category,
        matching: find.byType(Scrollable),
      );
      CategoryNewsContentState state() =>
          tester.state<CategoryNewsContentState>(category);
      await tester.drag(list, const Offset(0, -100000));
      await frames(tester);
      expect(calls(), ['219@0', '219@20']);
      await tester.drag(list, const Offset(0, -100000));
      await frames(tester);
      expect(calls(), ['219@0', '219@20', '219@40']);
      expect(state().items, hasLength(45));
      expect(state().hasMore, isFalse);
      expect({for (final item in state().items) item.catUid}, {219});
      await tester.drag(list, const Offset(0, 1500)); // lùi lên một đoạn
      await frames(tester);
      final pixels = tester.state<ScrollableState>(list).position.pixels;

      final card = find
          .descendant(of: category, matching: find.byType(NewsPreviewCard))
          .hitTestable()
          .first;
      final uid = tester.widget<NewsPreviewCard>(card).item.uid;
      await tester.tap(card);
      await frames(tester);
      expect(calls().last, '/api/news/$uid');
      expect(find.text('Nội dung bài $uid'), findsOneWidget);
      final afterDetail = calls().length;

      await back(tester);
      await frames(tester);
      expect(find.byType(NewsDetailContent), findsNothing);
      expect(title(tester), 'Cuộc sống UEH');
      expect(state().items, hasLength(45)); // không tải lại từ offset 0
      expect(tester.state<ScrollableState>(list).position.pixels, pixels);
      expect(calls(), hasLength(afterDetail));

      await back(tester);
      expect(find.byType(CategoryNewsContent), findsNothing);
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(title(tester), 'Trang chủ');
      expect(exitRequests, 0);
    }, variant: android);

    testWidgets('Chi tiết từ chuyên mục: Back về đúng chuyên mục, giữ tin đã tải và vị trí cuộn', (
      tester,
    ) async {
      await pumpHome(tester, categoryTotal: 45);
      final more = find.text('Xem thêm');
      await tester.ensureVisible(more);
      await frames(tester);
      await tester.tap(more);
      await frames(tester);
      final label = find
          .descendant(
            of: find.byType(AllNewsContent),
            matching: find.text('MỤC 220'),
          )
          .first;
      await tester.ensureVisible(label);
      await frames(tester);
      await tester.tap(label);
      await frames(tester);
      final list = find.descendant(
        of: find.byType(CategoryNewsContent),
        matching: find.byType(Scrollable),
      );
      await tester.drag(list, const Offset(0, -100000)); // tải trang 2
      await frames(tester);
      await tester.drag(list, const Offset(0, 900)); // lùi lên một đoạn
      await frames(tester);
      CategoryNewsContentState category() => tester
          .state<CategoryNewsContentState>(find.byType(CategoryNewsContent));
      expect(category().items, hasLength(40));
      final pixels = tester.state<ScrollableState>(list).position.pixels;
      final categoryRequests = newsRequests
          .where((u) => u.path == '/api/news')
          .length;

      final tile = find
          .descendant(
            of: find.byType(CategoryNewsContent),
            matching: find.byType(NewsPreviewCard),
          )
          .hitTestable()
          .first;
      final uid = tester.widget<NewsPreviewCard>(tile).item.uid;
      expect(uid ~/ 1000, 220);
      await tester.tap(tile);
      await frames(tester);
      expect(newsRequests.last.path, '/api/news/$uid');
      expect(find.text('Nội dung bài $uid'), findsOneWidget);

      await back(tester);
      await frames(tester);
      expect(find.byType(NewsDetailContent), findsNothing);
      expect(title(tester), 'Khoa học - Góc nhìn chuyên gia');
      expect(category().items, hasLength(40)); // không tải lại từ offset 0
      expect(tester.state<ScrollableState>(list).position.pixels, pixels);
      expect(
        newsRequests.where((u) => u.path == '/api/news').length,
        categoryRequests,
      );
      expect(exitRequests, 0);
    }, variant: android);

    testWidgets('Xem thêm: Trang chủ không còn 4 ô danh mục; mở danh sách tổng hợp, không gọi API chi tiết; Back về Trang chủ', (
      tester,
    ) async {
      await pumpHome(tester, categoryTotal: 2);
      expect(find.text('Danh mục tin tức'), findsNothing);
      expect(find.byType(FeaturedNewsCard), findsOneWidget);
      expect(find.byType(NewsTile), findsNWidgets(4));
      final before = newsRequests.length;
      final featuredRequests = newsRequests
          .where((u) => u.path == '/api/news/featured')
          .length;

      await openMore(tester);
      expect(find.byType(AllNewsContent), findsOneWidget);
      expect(find.text('Tin tức nổi bật'), findsOneWidget);
      expect(title(tester), 'Trang chủ');
      final opened = newsRequests.skip(before).toList();
      // Chỉ gọi danh sách theo 4 chuyên mục, không gọi /api/news/{uid}.
      expect(opened.every((u) => u.path == '/api/news'), isTrue);
      expect(
        opened.map((u) => u.queryParameters['cat_uid']).toSet(),
        {'219', '220', '221', '222'},
      );
      expect(find.byType(NewsDetailContent), findsNothing);
      expect(
        tester.state<AllNewsContentState>(find.byType(AllNewsContent)).items,
        hasLength(8),
      );
      expect(canPop(tester), isFalse);

      await openDrawer(tester); // Drawer mở + Back chỉ đóng Drawer
      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(find.byType(AllNewsContent), findsOneWidget);

      await back(tester);
      expect(find.byType(AllNewsContent), findsNothing);
      expect(find.byType(FeaturedNewsContent), findsOneWidget);
      expect(exitRequests, 0);
      expect(
        newsRequests.where((u) => u.path == '/api/news/featured').length,
        featuredRequests, // Trang chủ không tải lại
      );
    }, variant: android);

    testWidgets('Danh sách tổng hợp: lazy load, mở chi tiết, Back giữ tin đã tải và vị trí cuộn', (
      tester,
    ) async {
      await pumpHome(tester, categoryTotal: 45);
      final more = find.text('Xem thêm');
      await tester.ensureVisible(more);
      await frames(tester);
      await tester.tap(more);
      await frames(tester);
      AllNewsContentState feed() =>
          tester.state<AllNewsContentState>(find.byType(AllNewsContent));
      expect(feed().items, hasLength(10));
      final list = find.descendant(
        of: find.byType(AllNewsContent),
        matching: find.byType(Scrollable),
      );
      await tester.drag(list, const Offset(0, -100000)); // đợt 2
      await frames(tester);
      expect(feed().items, hasLength(20));
      await tester.drag(list, const Offset(0, 900));
      await frames(tester);
      final pixels = tester.state<ScrollableState>(list).position.pixels;
      final listRequests = newsRequests
          .where((u) => u.path == '/api/news')
          .length;

      final card = find
          .descendant(
            of: find.byType(AllNewsContent),
            matching: find.byType(NewsPreviewCard),
          )
          .hitTestable()
          .first;
      final uid = tester.widget<NewsPreviewCard>(card).item.uid;
      await tester.tap(card);
      await frames(tester);
      expect(newsRequests.last.path, '/api/news/$uid');
      expect(find.text('Nội dung bài $uid'), findsOneWidget);

      await back(tester);
      await frames(tester);
      expect(find.byType(NewsDetailContent), findsNothing);
      expect(feed().items, hasLength(20));
      expect(tester.state<ScrollableState>(list).position.pixels, pixels);
      expect(
        newsRequests.where((u) => u.path == '/api/news').length,
        listRequests,
      );
      expect(exitRequests, 0);
    }, variant: android);

    testWidgets('Chi tiết: Drawer mở + Back chỉ đóng Drawer; tab không hiện nhầm chi tiết', (
      tester,
    ) async {
      await pumpHome(tester, loggedIn: true);
      await tester.tap(find.byType(FeaturedNewsCard));
      await tester.pumpAndSettle();
      await openDrawer(tester);
      await back(tester);
      expect(drawerOpen(tester), isFalse);
      expect(find.byType(NewsDetailContent), findsOneWidget);
      expect(title(tester), 'Cuộc sống UEH');

      select(tester, BottomMenu.attendance);
      await tester.pumpAndSettle();
      expect(find.byType(AttendanceScreen), findsOneWidget);
      expect(find.byType(NewsDetailContent), findsNothing);
      select(tester, BottomMenu.home);
      await tester.pumpAndSettle();
      expect(find.byType(NewsDetailContent), findsNothing);
      expect(title(tester), 'Trang chủ');

      await tester.tap(find.byType(FeaturedNewsCard));
      await tester.pumpAndSettle();
      select(tester, BottomMenu.home); // tab Trang chủ khi đang xem chi tiết
      await tester.pumpAndSettle();
      expect(find.byType(NewsDetailContent), findsNothing);
      expect(title(tester), 'Trang chủ');
      expect(exitRequests, 0);
    }, variant: android);

    testWidgets('WebView có lịch sử: Back khi Drawer mở không gọi goBack', (
      tester,
    ) async {
      platform.hasHistory = true;
      await pumpHome(tester);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      (scaffold.drawer! as AppDrawer).onSelected(_externalMenu);
      await tester.pumpAndSettle();
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
