import 'package:flutter/material.dart';

import '../models/news.dart';
import '../services/news_api.dart';
import '../services/student_api.dart' show ApiException;
import 'app_top_bar.dart';
import 'featured_news.dart' show NewsTile;

/// Danh sách tin của một chuyên mục, tải dần (lazy load) khi cuộn gần cuối.
///
/// Mỗi lần gọi GET /api/news?cat_uid=&limit=20&offset=, offset bắt đầu từ 0
/// và tăng theo [NewsPage.nextOffset]; ngừng khi [NewsPage.hasMore] là false.
class CategoryNewsContent extends StatefulWidget {
  const CategoryNewsContent({
    super.key,
    required this.api,
    required this.category,
    this.onSelected,
  });

  static const pageSize = 20;

  /// Còn cách cuối danh sách ít hơn khoảng này (pixel) thì tải trang kế tiếp.
  static const loadMoreThreshold = 400.0;

  final NewsApi api;
  final NewsCategory category;

  /// Chạm vào một tin. null thì thẻ tin không nhận chạm (chưa có trang chi tiết).
  final ValueChanged<NewsItem>? onSelected;

  @override
  State<CategoryNewsContent> createState() => CategoryNewsContentState();
}

class CategoryNewsContentState extends State<CategoryNewsContent> {
  final _scroll = ScrollController();
  final _items = <NewsItem>[];
  final _seenUids = <int>{};
  int _nextOffset = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  // Tăng khi đổi chuyên mục: kết quả của request cũ bị bỏ qua.
  int _generation = 0;

  /// Các tin đã tải, không trùng uid, theo thứ tự server trả về.
  List<NewsItem> get items => List.unmodifiable(_items);
  int get nextOffset => _nextOffset;
  bool get hasMore => _hasMore;
  bool get loading => _loading;
  String? get error => _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void didUpdateWidget(CategoryNewsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category.uid != widget.category.uid ||
        oldWidget.api != widget.api) {
      _reset();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Bắt đầu lại từ offset 0 (đổi chuyên mục hoặc kéo để làm mới).
  Future<void> _reset() {
    _generation++;
    setState(() {
      _items.clear();
      _seenUids.clear();
      _nextOffset = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    return _loadMore();
  }

  void _onScroll() {
    final position = _scroll.position;
    if (position.extentAfter < CategoryNewsContent.loadMoreThreshold) {
      _loadMore();
    }
  }

  /// Tải trang kế tiếp. Đang tải, đang lỗi hoặc đã hết tin thì không gọi API.
  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _error != null) return;
    final generation = _generation;
    final offset = _nextOffset;
    setState(() => _loading = true);
    try {
      final page = await widget.api.category(
        widget.category.uid,
        limit: CategoryNewsContent.pageSize,
        offset: offset,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        for (final item in page.items) {
          if (_seenUids.add(item.uid)) _items.add(item);
        }
        // Offset tiếp theo cộng số tin server đã gửi (kể cả tin lỗi bị bỏ qua),
        // không phải số tin hiển thị và không phải số trang.
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loading = false;
      });
      _fillViewport();
    } on ApiException catch (e) {
      if (!mounted || generation != _generation) return;
      // Giữ các tin đã tải; người dùng bấm Thử lại để tải lại trang lỗi.
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      // Lỗi ngoài ApiException (ví dụ lỗi TLS mà package http không bọc lại):
      // vẫn phải dừng vòng xoay và cho Thử lại, nếu không _loading kẹt ở true.
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = 'Không thể tải tin tức. Vui lòng thử lại.';
        _loading = false;
      });
    }
  }

  // Màn hình cao hơn danh sách (không cuộn được) thì tự tải thêm một trang.
  void _fillViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0) _loadMore();
    });
  }

  void _retry() {
    setState(() => _error = null);
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    // Lần tải đầu chưa có tin: hiện trạng thái toàn màn hình.
    if (_items.isEmpty) {
      if (_error != null) {
        return _CenterMessage(
          icon: Icons.wifi_off,
          text: _error!,
          onRetry: _retry,
        );
      }
      if (_loading || _hasMore) {
        return const Center(child: CircularProgressIndicator());
      }
      return _CenterMessage(
        icon: Icons.article_outlined,
        text: 'Chuyên mục chưa có tin.',
        onRetry: _reset,
      );
    }
    return ColoredBox(
      color: Colors.white,
      child: RefreshIndicator(
        onRefresh: _reset,
        child: ListView.separated(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          // Thêm 1 dòng cuối: vòng tải, lỗi kèm Thử lại, hoặc báo đã hết tin.
          itemCount: _items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 20),
          itemBuilder: (context, index) {
            if (index == _items.length) return _footer();
            final item = _items[index];
            final onSelected = widget.onSelected;
            return NewsTile(
              item: item,
              onTap: onSelected == null ? null : () => onSelected(item),
            );
          },
        ),
      ),
    );
  }

  Widget _footer() {
    if (_error != null) {
      return Column(
        children: [
          Text(_error!, textAlign: TextAlign.center),
          TextButton(onPressed: _retry, child: const Text('Thử lại')),
        ],
      );
    }
    if (_hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Đã hiển thị hết tin của chuyên mục.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF808080)),
      ),
    );
  }
}

class _CenterMessage extends StatelessWidget {
  const _CenterMessage({
    required this.icon,
    required this.text,
    required this.onRetry,
  });

  final IconData icon;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTopBar.uehBlue, size: 32),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    ),
  );
}
