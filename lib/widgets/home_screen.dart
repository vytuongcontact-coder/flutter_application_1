import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';

import '../helpers/DBUtils.dart';
import '../controllers/auth_controller.dart';
import '../controllers/menu_sync_controller.dart';
import '../models/news.dart';
import '../services/news_api.dart';
import 'all_news.dart';
import 'category_news.dart';
import 'featured_news.dart';
import 'news_detail.dart';
import 'login_screen.dart';
import 'app_drawer.dart';
import 'app_bottom_bar.dart';
import 'app_top_bar.dart';
import 'attendance_screen.dart';
import 'account_screen.dart';

const _newsOrange = Color(0xFFFF6F00);

// Bản tin cũ: tải HTML website rồi phân tích. Không còn dùng làm nội dung
// Trang chủ (Trang chủ dùng FeaturedNewsContent + News REST API); giữ lại cho
// tới khi được phép dọn cùng các test của nó.
class NewsArticle {
  const NewsArticle({
    required this.title,
    required this.url,
    required this.category,
    this.imageUrl,
  });

  final String title;
  final Uri url;
  final String category;
  final Uri? imageUrl;
}

class NewsFeed {
  const NewsFeed({
    required this.title,
    required this.subtitle,
    required this.articles,
  });

  final String title;
  final String subtitle;
  final List<NewsArticle> articles;
}

class NewsService {
  NewsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  static String _text(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static Uri? _resolve(Uri base, String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final uri = base.resolve(value.trim());
    return uri.hasAuthority && (uri.scheme == 'https' || uri.scheme == 'http')
        ? uri
        : null;
  }

  Future<dom.Document> _fetch(Uri uri) async {
    if (_resolve(uri, uri.toString()) == null) {
      throw const FormatException('URL tin tức không hợp lệ.');
    }
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw http.ClientException(
        'Không thể tải tin (${response.statusCode}).',
        uri,
      );
    }
    return html.parse(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

  Future<NewsFeed> fetchFeed(Uri uri) async {
    final document = await _fetch(uri);
    final articles = <NewsArticle>[];
    final seen = <Uri>{};
    for (final item in document.querySelectorAll('.grid-container article')) {
      final category = item.querySelector('.news-title-view');
      final link =
          item.querySelector('.content h3:last-child a') ??
          item.querySelector('p a[href]');
      final url = _resolve(uri, link?.attributes['href']);
      final title = _text(link?.text ?? '');
      if (url == null || title.isEmpty || !seen.add(url)) continue;
      articles.add(
        NewsArticle(
          title: title,
          url: url,
          category: _text(category?.text ?? 'Tin tức UEH'),
          imageUrl: _resolve(uri, item.querySelector('img')?.attributes['src']),
        ),
      );
    }
    if (articles.isEmpty) {
      throw const FormatException('Không tìm thấy danh sách tin UEH.');
    }
    return NewsFeed(
      title: _text(
        document.querySelector('.ueh-block-title')?.text ?? 'Tin tức',
      ),
      subtitle: _text(
        document.querySelector('section > header > p')?.text ?? '',
      ),
      articles: articles,
    );
  }
}

class NewsListContent extends StatefulWidget {
  const NewsListContent({
    super.key,
    required this.uri,
    required this.service,
    required this.onSelected,
  });

  final Uri uri;
  final NewsService service;
  final ValueChanged<NewsArticle> onSelected;

  @override
  State<NewsListContent> createState() => _NewsListContentState();
}

class _NewsListContentState extends State<NewsListContent> {
  late Future<NewsFeed> _feed;

  @override
  void initState() {
    super.initState();
    _feed = widget.service.fetchFeed(widget.uri);
  }

  Future<void> _reload() async {
    final future = widget.service.fetchFeed(widget.uri);
    setState(() => _feed = future);
    try {
      await future;
    } catch (_) {
      /* FutureBuilder hiển thị lỗi. */
    }
  }

  Widget _card({required Widget child, required NewsArticle article}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: () => widget.onSelected(article), child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    child: FutureBuilder<NewsFeed>(
      future: _feed,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _NewsLoadError(onRetry: _reload);
        }
        final feed = snapshot.data!;
        final featured = feed.articles.first;
        return RefreshIndicator(
          onRefresh: _reload,
          child: SingleChildScrollView(
            key: const PageStorageKey('ueh-news-list'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  feed.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _newsOrange,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  feed.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                _card(
                  article: featured,
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 2.5,
                          child: featured.imageUrl == null
                              ? const ColoredBox(
                                  color: Color(0xFFF4F4F4),
                                  child: Icon(
                                    Icons.image_outlined,
                                    color: AppTopBar.uehBlue,
                                  ),
                                )
                              : Image.network(
                                  featured.imageUrl.toString(),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, error, stackTrace) =>
                                      const Center(
                                        child: Icon(
                                          Icons.image_outlined,
                                          color: AppTopBar.uehBlue,
                                        ),
                                      ),
                                ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(
                            top: constraints.maxWidth / 2.5,
                          ),
                          child: Container(
                            width: double.infinity,
                            color: AppTopBar.uehBlue,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                            child: Column(
                              children: [
                                const Text(
                                  'TIN TỨC NỔI BẬT',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 25,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  featured.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final article in feed.articles.skip(1))
                  _card(
                    article: article,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            article.category.toUpperCase(),
                            style: const TextStyle(
                              color: _newsOrange,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            article.title,
                            textAlign: TextAlign.justify,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                              fontSize: 19,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _NewsLoadError extends StatelessWidget {
  const _NewsLoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, color: AppTopBar.uehBlue, size: 32),
          const SizedBox(height: 12),
          const Text(
            'Không thể tải tin tức. Vui lòng thử lại.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.auth, this.menu, this.newsApi});

  final AuthController? auth;

  /// Truyền vào khi test; mặc định tạo controller đọc SQLite thật.
  final MenuSyncController? menu;

  /// Truyền vào khi test; mặc định gọi News REST API thật.
  final NewsApi? newsApi;

  // Đổi URL tại đây hoặc dùng flutter run --dart-define=UEH_URL=https://...
  static const websiteUrl = DBUtils.newsUrl;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final AuthController _auth;
  late final MenuSyncController _menu;
  BottomMenu? _afterLogin;
  bool _wasLoggedIn = false;
  WebViewController? _controller;
  int _progress = 0;
  bool _canGoBack = false;
  String? _error;
  String _pageTitle = BottomMenu.home.title;
  BottomMenu _selectedMenu = BottomMenu.home;
  late final NewsApi _newsApi;
  // Tăng để FeaturedNewsContent tải lại (nút Tải lại).
  int _featuredRevision = 0;
  // Trang web của mục menu có URL ngoài; null là đang ở Trang chủ (tin tức native).
  Uri? _webUri;
  // Đã bấm "Xem thêm": đang ở danh sách tin tổng hợp (Trang chủ › Tin tức nổi bật).
  bool _showMore = false;
  int _moreRevision = 0;
  // Chuyên mục đang mở (chạm tên chuyên mục trên thẻ của danh sách tổng hợp).
  NewsCategory? _category;
  int _categoryRevision = 0;
  // Bài đang xem chi tiết; null là đang ở danh sách (Trang chủ hoặc chuyên mục).
  NewsItem? _article;
  int _articleRevision = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  // Cập nhật qua Scaffold.onDrawerChanged (mở/đóng bằng nút, vùng tối, kéo, chọn menu).
  bool _drawerOpen = false;

  bool get _supportsWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _newsApi = widget.newsApi ?? NewsApi();
    _auth = widget.auth ?? AuthController();
    // Menu dùng chung StudentApi (và token) của AuthController.
    _menu = widget.menu ?? MenuSyncController(api: _auth.api);
    _wasLoggedIn = _auth.isLoggedIn;
    _auth.addListener(_onAuthChanged);
    // Cache-then-network: hiển thị menu đã lưu ngay khi mở app.
    _menu.loadCache();
    if (_auth.isLoggedIn) _menu.sync();
    if (_auth.initializing) _auth.initialize();
  }

  // WebView chỉ tạo khi mở mục menu có URL ngoài; Trang chủ không dùng WebView.
  WebViewController? _ensureWebController() {
    if (_controller != null || !_supportsWebView) return _controller;
    return _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null &&
                    (uri.scheme == 'https' || uri.scheme == 'http')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onProgress: (progress) {
            if (mounted) setState(() => _progress = progress);
          },
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _error = null;
              _progress = 0;
            });
          },
          onPageFinished: (_) => _updateHistory(),
          onWebResourceError: (error) {
            // Lỗi tài nguyên phụ không làm ẩn cả trang web.
            if (!mounted || error.isForMainFrame != true) return;
            setState(() {
              _error =
                  'Không thể tải trang web. Vui lòng kiểm tra kết nối mạng.';
              _progress = 100;
            });
          },
        ),
      );
  }

  void _onAuthChanged() {
    if (!mounted) return;
    final loggedIn = _auth.isLoggedIn;
    // Vừa đăng nhập hoặc khôi phục phiên: đồng bộ menu.
    // Vừa đăng xuất hoặc hết phiên: bỏ kết quả của request menu đang chạy.
    if (loggedIn != _wasLoggedIn) {
      loggedIn ? _menu.sync() : _menu.cancelSync();
    }
    setState(() {
      if (_wasLoggedIn && !_auth.isLoggedIn) {
        _selectedMenu = BottomMenu.account;
        _afterLogin = null;
      } else if (!_wasLoggedIn && _auth.isLoggedIn && _afterLogin != null) {
        _selectedMenu = _afterLogin!;
        _afterLogin = null;
      }
      _wasLoggedIn = _auth.isLoggedIn;
    });
  }

  void _onMenuSelected(MenuNav menu) {
    final uri = Uri.tryParse(menu.menuUrl);
    final hasUrl =
        uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'https' || uri.scheme == 'http');
    // "Tin tức UEH": về giao diện tin tức native, không mở website trong WebView.
    if (hasUrl &&
        (menu.iconName == 'newspaper' ||
            uri.path == Uri.parse(HomeScreen.websiteUrl).path)) {
      setState(() {
        _selectedMenu = BottomMenu.home;
        _pageTitle = menu.menuName;
        _webUri = null;
        _showMore = false;
        _category = null;
        _article = null;
        _canGoBack = false;
      });
      return;
    }
    final controller = hasUrl ? _ensureWebController() : null;
    if (controller != null && uri != null) {
      setState(() {
        _selectedMenu = BottomMenu.home;
        _pageTitle = menu.menuName;
        _webUri = uri;
        _showMore = false;
        _category = null;
        _article = null;
        _canGoBack = false;
      });
      _load(() => controller.loadRequest(uri));
      return;
    }

    // Những chức năng chưa có URL vẫn hiển thị thông báo như trước.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            hasUrl
                ? 'Vui lòng mở ứng dụng trên Android, iOS hoặc macOS để xem nội dung.'
                : '${menu.menuName}: chức năng hiện chưa khả dụng.',
          ),
        ),
      );
  }

  void _onBottomMenuSelected(BottomMenu menu) {
    if (menu == BottomMenu.attendance || menu == BottomMenu.account) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      setState(() {
        if (menu == BottomMenu.attendance && !_auth.isLoggedIn) {
          _afterLogin = menu;
          _selectedMenu = BottomMenu.account;
        } else {
          _afterLogin = null;
          _selectedMenu = menu;
        }
      });
      return;
    }
    if (menu == BottomMenu.home) {
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      setState(() {
        _selectedMenu = menu;
        _pageTitle = menu.title;
        _webUri = null;
        _showMore = false;
        _category = null;
        _article = null;
        _canGoBack = false;
      });
      return;
    }

    // Gắn route khi các màn hình này được triển khai.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('${menu.title}: chức năng hiện chưa khả dụng.')),
      );
  }

  Future<void> _load(Future<void> Function() action) async {
    setState(() {
      _error = null;
      _progress = 0;
    });
    try {
      await action();
      await _updateHistory();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Không thể tải trang web. Vui lòng thử lại.';
        _progress = 100;
      });
    }
  }

  Future<void> _updateHistory() async {
    final canGoBack = await _controller!.canGoBack();
    if (!mounted) return;
    setState(() {
      _canGoBack = canGoBack;
    });
  }

  // Cử chỉ vuốt Back (predictive back, Android 16+) bắt đầu khi Drawer đang mở:
  // HomeScreen giữ cử chỉ này và chỉ đóng Drawer. Các chạm đầu của cú vuốt có
  // thể lọt vào Drawer làm nó tự đóng trước khi Back được xác nhận; nếu để Back
  // đi tiếp qua PopScope thì sẽ đổi tab (Tài khoản/Điểm danh → Trang chủ).
  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) => _drawerOpen;

  @override
  void handleCommitBackGesture() => _scaffoldKey.currentState?.closeDrawer();

  void _openMore() => setState(() => _showMore = true);

  void _openCategory(NewsCategory category) =>
      setState(() => _category = category);

  // Chạm một tin ở Trang chủ hoặc chuyên mục: mở trang chi tiết. Màn hình
  // nguồn vẫn nằm trong IndexedStack nên Back quay về đúng chỗ cũ.
  void _openArticle(NewsItem item) => setState(() => _article = item);

  Future<void> _retryWebPage() => _load(() => _controller!.loadRequest(_webUri!));

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_onAuthChanged);
    if (widget.menu == null) _menu.dispose();
    if (widget.auth == null) _auth.dispose();
    if (widget.newsApi == null) _newsApi.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isAttendance = _selectedMenu == BottomMenu.attendance;
    final isAccount = _selectedMenu == BottomMenu.account;
    final isStudentScreen = isAttendance || isAccount;
    return PopScope(
      // Drawer mở thì chặn pop: canPop đổi giá trị nên Flutter báo lại cho
      // Android rằng app tự xử lý Back (predictive back, Android 16+).
      canPop:
          !_drawerOpen &&
          !isStudentScreen &&
          _webUri == null &&
          _category == null &&
          _article == null &&
          !_showMore,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Một lần Back khi Drawer mở chỉ đóng Drawer, không đổi tab/tin/WebView.
        if (_drawerOpen) {
          _scaffoldKey.currentState?.closeDrawer();
          return;
        }
        if (isStudentScreen) {
          _onBottomMenuSelected(BottomMenu.home);
        } else if (_article != null) {
          // Chi tiết tin: về màn hình nguồn (chuyên mục nếu mở từ chuyên mục).
          setState(() => _article = null);
        } else if (_category != null) {
          // Danh sách chuyên mục: về màn hình trước (danh sách tổng hợp).
          setState(() => _category = null);
        } else if (_showMore) {
          // Danh sách tổng hợp: về Trang chủ (giữ nguyên tin đã tải).
          setState(() => _showMore = false);
        } else if (_webUri != null) {
          // Trang web ngoài: lùi trong WebView nếu có lịch sử, hết thì về Trang chủ.
          _canGoBack && controller != null
              ? _load(controller.goBack)
              : _onBottomMenuSelected(BottomMenu.home);
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawer: AppDrawer(menu: _menu, onSelected: _onMenuSelected),
        onDrawerChanged: (open) {
          if (open != _drawerOpen) setState(() => _drawerOpen = open);
          // Mở Drawer: thử đồng bộ lại nếu lần trước lỗi hoặc dữ liệu đã cũ.
          if (open) _menu.syncIfStale();
        },
        appBar: AppTopBar(
          title: isStudentScreen
              ? _selectedMenu.title
              : _article?.categoryName ?? _category?.name ?? _pageTitle,
          centerTitle: isStudentScreen ? true : null,
          leading: Builder(
            builder: (context) => IconButton(
              tooltip: 'Mở menu',
              icon: const FaIcon(FontAwesomeIcons.bars, size: 22),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          actions: isAccount && _auth.isLoggedIn
              ? [
                  IconButton(
                    tooltip: 'Đăng xuất',
                    icon: const Icon(Icons.logout, size: 26),
                    onPressed: _auth.busy ? null : _auth.logout,
                  ),
                ]
              : isAttendance || isAccount
              ? []
              : [
                  IconButton(
                    tooltip: 'Tải lại',
                    onPressed: _article != null
                        ? () => setState(() => _articleRevision++)
                        : _category != null
                        ? () => setState(() => _categoryRevision++)
                        : _showMore
                        ? () => setState(() => _moreRevision++)
                        : _webUri == null
                        ? () => setState(() => _featuredRevision++)
                        : controller == null
                        ? null
                        : () => _load(controller.reload),
                    icon: const FaIcon(FontAwesomeIcons.rotateRight, size: 20),
                  ),
                ],
        ),
        body: SafeArea(
          child: isAttendance
              ? AttendanceScreen(api: _auth.api)
              : isAccount
              ? _buildAccount()
              : _webUri != null
              ? _buildWebContent(controller)
              // Tin tức: 0 = Trang chủ, 1 = danh sách tổng hợp (Xem thêm),
              // 2 = danh sách chuyên mục, 3 = chi tiết.
              // IndexedStack giữ màn hình nguồn (tin đã tải, vị trí cuộn) khi
              // đang xem chi tiết; mỗi màn hình luôn ở đúng vị trí của nó.
              : IndexedStack(
                  index: _article != null
                      ? 3
                      : _category != null
                      ? 2
                      : _showMore
                      ? 1
                      : 0,
                  children: [
                    FeaturedNewsContent(
                      key: ValueKey(_featuredRevision),
                      api: _newsApi,
                      onSelected: _openArticle,
                      onMore: _openMore,
                    ),
                    !_showMore
                        ? const SizedBox.shrink()
                        : AllNewsContent(
                            key: ValueKey(_moreRevision),
                            api: _newsApi,
                            onSelected: _openArticle,
                            onCategorySelected: _openCategory,
                            onHome: () =>
                                _onBottomMenuSelected(BottomMenu.home),
                          ),
                    _category == null
                        ? const SizedBox.shrink()
                        : CategoryNewsContent(
                            key: ValueKey(
                              '${_category!.uid}/$_categoryRevision',
                            ),
                            api: _newsApi,
                            category: _category!,
                            onSelected: _openArticle,
                          ),
                    _article == null
                        ? const SizedBox.shrink()
                        : NewsDetailContent(
                            key: ValueKey(
                              '${_article!.uid}/$_articleRevision',
                            ),
                            api: _newsApi,
                            item: _article!,
                          ),
                  ],
                ),
        ),
        bottomNavigationBar: AppBottomBar(
          selectedMenu: _selectedMenu,
          onSelected: _onBottomMenuSelected,
        ),
      ),
    );
  }

  Widget _buildAccount() {
    if (_auth.initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_auth.isLoggedIn) return LoginScreen(auth: _auth);
    if (_auth.profile == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_auth.busy)
                const CircularProgressIndicator()
              else ...[
                Text(
                  _auth.error ?? 'Chưa tải được thông tin sinh viên.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _auth.reloadProfile,
                  child: const Text('Thử lại'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return AccountScreen(profile: _auth.profile!);
  }

  Widget _buildWebContent(WebViewController? controller) => controller == null
      ? const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Vui lòng chạy ứng dụng trên Android, iOS hoặc macOS để xem website.',
              textAlign: TextAlign.center,
            ),
          ),
        )
      : Stack(
          children: [
            Positioned.fill(child: WebViewWidget(controller: controller)),
            if (_error != null)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FaIcon(
                            FontAwesomeIcons.triangleExclamation,
                            size: 36,
                          ),
                          const SizedBox(height: 16),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _retryWebPage,
                            icon: const FaIcon(
                              FontAwesomeIcons.rotateRight,
                              size: 16,
                            ),
                            label: const Text('Thử lại'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_progress < 100 && _error == null)
              LinearProgressIndicator(value: _progress / 100),
          ],
        );
}
