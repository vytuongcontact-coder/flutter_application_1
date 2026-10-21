import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/helpers/DBUtils.dart';
import 'package:flutter_application_1/widgets/app_bottom_bar.dart';
import 'package:flutter_application_1/widgets/app_drawer.dart';
import 'package:flutter_application_1/widgets/app_top_bar.dart';
import 'package:flutter_application_1/widgets/home_screen.dart';
import 'package:flutter_application_1/widgets/splash_screen.dart';

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
}

class _FakeWebViewPlatform extends WebViewPlatform {
  late _FakeWebViewController controller;
  late _FakeNavigationDelegate delegate;
  int createdControllers = 0;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    createdControllers++;
    return controller = _FakeWebViewController(params);
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

  @override
  Future<bool> canGoBack() async => false;

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
