import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/news.dart';
import '../services/news_api.dart';
import '../services/student_api.dart' show ApiException;
import 'app_top_bar.dart';
import 'featured_news.dart' show NewsImage, SdgIcons;

const _newsOrange = Color(0xFFE5680C);

/// Một nguồn tin của danh sách tổng hợp: một chuyên mục với offset và bộ đệm
/// riêng (các tin đã tải từ API nhưng chưa đưa ra danh sách).
class _Source {
  _Source(this.category);

  final NewsCategory category;
  final buffer = <NewsItem>[];
  int nextOffset = 0;
  bool hasMore = true;
}

/// Ghép tin của 4 chuyên mục (219-222) thành một danh sách mới nhất trước.
///
/// API không có danh sách tổng hợp (thiếu cat_uid trả 400), nên mỗi chuyên mục
/// được tải riêng bằng [NewsApi.category] theo từng nhóm nhỏ. Mỗi lần
/// [takeNext] chọn tin mới nhất trong số các tin đứng đầu bộ đệm của các nguồn.
/// Nguồn nào hết bộ đệm mà server còn tin thì phải tải thêm trước khi chọn, vì
/// tin kế tiếp của nguồn đó có thể mới hơn tin của các nguồn khác.
///
/// Mỗi chuyên mục trên server đã sắp xếp mới nhất trước, nên thứ tự ghép đúng
/// trên toàn bộ dữ liệu (không chỉ phần đã tải).
class MergedNewsLoader {
  MergedNewsLoader(
    this.api, {
    List<NewsCategory> categories = NewsCategory.all,
    this.pageSize = 5,
  }) : _sources = [for (final category in categories) _Source(category)];

  final NewsApi api;

  /// Số tin tải mỗi lần cho một chuyên mục.
  final int pageSize;
  final List<_Source> _sources;
  final _seenUids = <int>{};

  /// Còn tin: một nguồn còn tin trên server hoặc còn tin trong bộ đệm.
  bool get hasMore =>
      _sources.any((source) => source.hasMore || source.buffer.isNotEmpty);

  /// Offset kế tiếp của từng chuyên mục (để kiểm tra và giải thích).
  Map<int, int> get nextOffsets => {
    for (final source in _sources) source.category.uid: source.nextOffset,
  };

  /// Tin kế tiếp theo ngày đăng mới nhất; null khi đã hết tin.
  ///
  /// Lỗi mạng ném ra trước khi lấy tin khỏi bộ đệm, nên gọi lại (Thử lại) sẽ
  /// tiếp tục đúng chỗ; nguồn đã tải thành công không bị tải lại.
  Future<NewsItem?> takeNext() async {
    while (true) {
      final empty = _sources
          .where((source) => source.buffer.isEmpty && source.hasMore)
          .toList();
      if (empty.isNotEmpty) await _fillAll(empty);

      _Source? newest;
      for (final source in _sources) {
        if (source.buffer.isEmpty) continue;
        if (newest == null ||
            _isNewer(source.buffer.first, newest.buffer.first)) {
          newest = source;
        }
      }
      if (newest == null) return null;
      final item = newest.buffer.removeAt(0);
      if (_seenUids.add(item.uid)) return item; // trùng uid thì lấy tin sau
    }
  }

  // Tin a mới hơn b? Không có ngày thì xếp sau; cùng ngày thì giữ thứ tự nguồn.
  static bool _isNewer(NewsItem a, NewsItem b) {
    final da = a.postDate, db = b.postDate;
    if (da == null) return false;
    if (db == null) return true;
    return da.isAfter(db);
  }

  // Tải song song các nguồn rỗng; nguồn tải xong vẫn giữ dữ liệu dù nguồn
  // khác lỗi. Có lỗi thì ném lỗi đầu tiên sau khi tất cả đã xong.
  Future<void> _fillAll(List<_Source> sources) async {
    Object? firstError;
    StackTrace? firstStack;
    await Future.wait([
      for (final source in sources)
        _fill(source).catchError((Object error, StackTrace stack) {
          firstError ??= error;
          firstStack ??= stack;
        }),
    ]);
    if (firstError != null) Error.throwWithStackTrace(firstError!, firstStack!);
  }

  Future<void> _fill(_Source source) async {
    final page = await api.category(
      source.category.uid,
      limit: pageSize,
      offset: source.nextOffset,
    );
    source.buffer.addAll(page.items);
    // Theo số tin server đã gửi (kể cả tin lỗi bị bỏ qua), không phải số trang.
    source.nextOffset = page.nextOffset;
    source.hasMore = page.hasMore;
  }
}

/// Màn hình "Trang chủ › Tin tức nổi bật" sau khi bấm "Xem thêm": tin của 4
/// chuyên mục, mới nhất trước, tải dần khi cuộn gần cuối.
class AllNewsContent extends StatefulWidget {
  const AllNewsContent({
    super.key,
    required this.api,
    this.onSelected,
    this.onCategorySelected,
    this.onHome,
  });

  /// Số tin thêm vào danh sách mỗi đợt.
  static const batchSize = 10;
  static const loadMoreThreshold = 400.0;

  final NewsApi api;
  final ValueChanged<NewsItem>? onSelected;

  /// Chạm tên chuyên mục trên thẻ: mở danh sách của chuyên mục đó.
  final ValueChanged<NewsCategory>? onCategorySelected;

  /// Chạm "Trang chủ" ở breadcrumb.
  final VoidCallback? onHome;

  @override
  State<AllNewsContent> createState() => AllNewsContentState();
}

class AllNewsContentState extends State<AllNewsContent> {
  final _scroll = ScrollController();
  final _items = <NewsItem>[];
  late MergedNewsLoader _loader;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  // Tăng khi làm mới: kết quả của lượt tải cũ bị bỏ qua.
  int _generation = 0;

  List<NewsItem> get items => List.unmodifiable(_items);
  bool get hasMore => _hasMore;
  bool get loading => _loading;
  String? get error => _error;
  MergedNewsLoader get loader => _loader;

  @override
  void initState() {
    super.initState();
    _loader = MergedNewsLoader(widget.api);
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _reset() {
    _generation++;
    setState(() {
      _loader = MergedNewsLoader(widget.api);
      _items.clear();
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    return _loadMore();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < AllNewsContent.loadMoreThreshold) {
      _loadMore();
    }
  }

  /// Thêm một đợt tin. Đang tải, đang lỗi hoặc đã hết tin thì không gọi API.
  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _error != null) return;
    final generation = _generation;
    final loader = _loader;
    final batch = <NewsItem>[];
    setState(() => _loading = true);
    String? error;
    try {
      while (batch.length < AllNewsContent.batchSize) {
        final item = await loader.takeNext();
        if (!mounted || generation != _generation) return;
        if (item == null) break;
        batch.add(item);
      }
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      // Lỗi ngoài ApiException (ví dụ lỗi TLS) cũng phải dừng vòng xoay.
      error = 'Không thể tải tin tức. Vui lòng thử lại.';
    }
    if (!mounted || generation != _generation) return;
    // Tin đã lấy trước khi lỗi vẫn được hiển thị; Thử lại tải tiếp từ đó.
    setState(() {
      _items.addAll(batch);
      _hasMore = loader.hasMore;
      _loading = false;
      _error = error;
    });
    if (error == null) _fillViewport();
  }

  // Danh sách thấp hơn màn hình (chưa cuộn được) thì tự tải thêm một đợt.
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
    final onSelected = widget.onSelected;
    final onCategory = widget.onCategorySelected;
    return ColoredBox(
      color: Colors.white,
      child: RefreshIndicator(
        onRefresh: _reset,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          // Dòng đầu: breadcrumb; dòng cuối: vòng tải, lỗi, hoặc báo hết tin.
          itemCount: _items.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) return _Breadcrumb(onHome: widget.onHome);
            if (index == _items.length + 1) return _footer();
            final item = _items[index - 1];
            final category = NewsCategory.all
                .where((c) => c.uid == item.catUid)
                .firstOrNull;
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: NewsPreviewCard(
                item: item,
                onTap: onSelected == null ? null : () => onSelected(item),
                onCategoryTap: onCategory == null || category == null
                    ? null
                    : () => onCategory(category),
              ),
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
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        _items.isEmpty ? 'Hiện chưa có tin tức.' : 'Đã hiển thị hết tin.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF808080)),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({this.onHome});

  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        GestureDetector(
          onTap: onHome,
          child: const Text(
            'Trang chủ',
            style: TextStyle(color: Colors.black87, fontSize: 18),
          ),
        ),
        const Icon(Icons.chevron_right, color: Color(0xFFBDBDBD), size: 20),
        const Text(
          'Tin tức nổi bật',
          style: TextStyle(color: AppTopBar.uehBlue, fontSize: 18),
        ),
      ],
    ),
  );
}

/// Thẻ xem trước một bài: chuyên mục (cam), tiêu đề (xanh đậm), ảnh bên trái,
/// SDG và đoạn giới thiệu bên phải ảnh; phần giới thiệu còn lại nối xuống dưới.
class NewsPreviewCard extends StatelessWidget {
  const NewsPreviewCard({
    super.key,
    required this.item,
    this.onTap,
    this.onCategoryTap,
  });

  final NewsItem item;
  final VoidCallback? onTap;
  final VoidCallback? onCategoryTap;

  static const introStyle = TextStyle(
    fontSize: 17,
    height: 1.45,
    color: Colors.black87,
  );

  @override
  Widget build(BuildContext context) {
    final category = Text(
      item.categoryName.toUpperCase(),
      style: const TextStyle(
        color: _newsOrange,
        fontSize: 16,
        fontWeight: FontWeight.w800,
      ),
    );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: onCategoryTap == null
                ? category
                : InkWell(onTap: onCategoryTap, child: category),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: const TextStyle(
              color: AppTopBar.uehBlue,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          _ImageAndIntro(item: item),
        ],
      ),
    );
    return DecoratedBox(
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
        child: onTap == null ? body : InkWell(onTap: onTap, child: body),
      ),
    );
  }
}

/// Ảnh bên trái; bên phải là SDG và phần đầu đoạn giới thiệu, phần còn lại
/// tiếp tục bên dưới (gần giống CSS float: left).
///
/// Dùng [TextPainter] đo xem bao nhiêu dòng giới thiệu vừa chiều cao ảnh, rồi
/// cắt đoạn văn tại đầu dòng kế tiếp.
class _ImageAndIntro extends StatelessWidget {
  const _ImageAndIntro({required this.item});

  final NewsItem item;

  static const _gap = 14.0;
  static const _sdgSize = 30.0;

  @override
  Widget build(BuildContext context) {
    final image = item.thumbnailImg ?? item.backgroundImg;
    final intro = item.shortDesc;
    final sdgs = item.sdgs.isEmpty ? null : SdgIcons(item.sdgs, size: _sdgSize);
    if (image == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?sdgs,
          if (intro != null) ...[
            if (sdgs != null) const SizedBox(height: 10),
            _intro(intro),
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageWidth = constraints.maxWidth * 0.46;
        final imageHeight = imageWidth * 2 / 3;
        final sideWidth = constraints.maxWidth - imageWidth - _gap;
        final sideTextHeight = imageHeight - (sdgs == null ? 0 : _sdgSize + 8);
        final (side, rest) = intro == null
            ? (null, null)
            : _split(context, intro, sideWidth, sideTextHeight);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: imageWidth,
                  height: imageHeight,
                  child: NewsImage(url: image, cacheWidth: 600),
                ),
                const SizedBox(width: _gap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (sdgs != null) ...[sdgs, const SizedBox(height: 8)],
                      // Cột hẹp: căn trái để không có khoảng trắng lớn giữa chữ.
                      if (side != null) _intro(side, align: TextAlign.start),
                    ],
                  ),
                ),
              ],
            ),
            if (rest != null) _intro(rest),
          ],
        );
      },
    );
  }

  Widget _intro(String text, {TextAlign align = TextAlign.justify}) =>
      Text(text, textAlign: align, style: NewsPreviewCard.introStyle);

  // Chia đoạn giới thiệu: phần vừa trong [maxHeight] bên phải ảnh và phần còn lại.
  static (String?, String?) _split(
    BuildContext context,
    String text,
    double width,
    double maxHeight,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: NewsPreviewCard.introStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(width, 1));
    final int cut;
    try {
      final lines = painter.computeLineMetrics();
      var fit = 0;
      var height = 0.0;
      for (final line in lines) {
        if (height + line.height > maxHeight) break;
        height += line.height;
        fit++;
      }
      if (fit == 0) return (null, text);
      if (fit >= lines.length) return (text, null);
      // Vị trí ký tự đầu tiên của dòng không còn vừa bên phải ảnh.
      cut = painter
          .getPositionForOffset(Offset(0, height + lines[fit].height / 2))
          .offset;
    } finally {
      painter.dispose();
    }
    final side = text.substring(0, cut).trimRight();
    final rest = text.substring(cut).trimLeft();
    if (side.isEmpty) return (null, text);
    return (side, rest.isEmpty ? null : rest);
  }
}
