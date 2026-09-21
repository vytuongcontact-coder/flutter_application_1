import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_drawer.dart';
import 'app_bottom_bar.dart';
import 'app_top_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  // Đổi URL tại đây hoặc dùng flutter run --dart-define=UEH_URL=https://...
  static const websiteUrl = String.fromEnvironment(
    'UEH_URL',
    defaultValue: 'https://ueh.edu.vn/tintucmobile',
  );

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  WebViewController? _controller;
  int _progress = 0;
  bool _canGoBack = false;
  String? _error;
  String _pageTitle = BottomMenu.home.title;

  bool get _supportsWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    if (!_supportsWebView) return;
    _controller = WebViewController()
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
    _openHome();
  }

  void _onMenuSelected(DrawerMenu menu) {
    if (menu == DrawerMenu.news && _controller != null) {
      setState(() => _pageTitle = menu.title);
      _openHome();
      return;
    }

    // Gắn URL hoặc route của các chức năng còn lại tại đây.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            menu == DrawerMenu.news
                ? 'Vui lòng mở ứng dụng trên Android, iOS hoặc macOS để xem tin tức.'
                : '${menu.title}: chức năng hiện chưa khả dụng.',
          ),
        ),
      );
  }

  void _onBottomMenuSelected(BottomMenu menu) {
    if (menu == BottomMenu.home) {
      setState(() => _pageTitle = menu.title);
      if (_controller != null) _openHome();
      return;
    }

    // Gắn route khi các màn hình này được triển khai.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('${menu.title}: chức năng hiện chưa khả dụng.')),
      );
  }

  Future<void> _openHome() async {
    final uri = Uri.tryParse(HomeScreen.websiteUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      setState(() => _error = 'URL website không hợp lệ.');
      return;
    }
    await _load(() => _controller!.loadRequest(uri));
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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _canGoBack && controller != null) {
          _load(controller.goBack);
        }
      },
      child: Scaffold(
        drawer: AppDrawer(onSelected: _onMenuSelected),
        appBar: AppTopBar(
          title: _pageTitle,
          leading: Builder(
            builder: (context) => IconButton(
              tooltip: 'Mở menu',
              icon: const FaIcon(FontAwesomeIcons.bars, size: 22),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Tải lại',
              onPressed: controller == null
                  ? null
                  : () => _load(controller.reload),
              icon: const FaIcon(FontAwesomeIcons.rotateRight, size: 20),
            ),
          ],
        ),
        body: SafeArea(
          child: controller == null
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
                    Positioned.fill(
                      child: WebViewWidget(controller: controller),
                    ),
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
                                    onPressed: _openHome,
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
                ),
        ),
        bottomNavigationBar: AppBottomBar(onSelected: _onBottomMenuSelected),
      ),
    );
  }
}
