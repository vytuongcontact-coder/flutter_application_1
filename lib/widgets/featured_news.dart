import 'package:flutter/material.dart';

import '../models/news.dart';
import '../services/news_api.dart';
import '../services/student_api.dart' show ApiException;
import 'app_top_bar.dart';

// Màu lấy theo giao diện UEH Student gốc.
const _newsOrange = Color(0xFFE5680C);
const _featuredBlue = Color(0xFF2C656C);
const _categoryBlue = Color(0xFF11443F);

/// Kết quả đã chọn để hiển thị: 1 tin lớn và tối đa 4 tin nhỏ.
class FeaturedNews {
  const FeaturedNews({required this.main, required this.others});

  final NewsItem? main;
  final List<NewsItem> others;

  bool get isEmpty => main == null;
}

/// Tải tin nổi bật từ GET /api/news/featured rồi chọn 1 tin lớn, 4 tin nhỏ.
///
/// - Tin lớn: tin đầu tiên có `is_featured = true`; không có thì tin đầu tiên.
/// - Tin nhỏ: các tin còn lại, không trùng uid.
/// - Chưa đủ 4 tin nhỏ: với mỗi chuyên mục (219 → 222) chưa có tin nhỏ, lấy
///   tin mới nhất khác uid đã dùng từ GET /api/news?cat_uid=. Chỉ gọi khi thiếu;
///   gọi lỗi thì bỏ qua và hiển thị số tin đang có.
Future<FeaturedNews> loadFeaturedNews(NewsApi api, {int smallCount = 4}) async {
  final items = await api.featured();
  final used = <int>{};
  final unique = [
    for (final item in items)
      if (used.add(item.uid)) item,
  ];
  if (unique.isEmpty) return const FeaturedNews(main: null, others: []);

  final main = unique.firstWhere(
    (item) => item.isFeatured,
    orElse: () => unique.first,
  );
  final others = [
    for (final item in unique)
      if (item.uid != main.uid) item,
  ].take(smallCount).toList();

  for (final category in NewsCategory.all) {
    if (others.length >= smallCount) break;
    if (others.any((item) => item.catUid == category.uid)) continue;
    try {
      final page = await api.category(category.uid, limit: 5);
      final extra = page.items.where((item) => !used.contains(item.uid));
      if (extra.isEmpty) continue;
      others.add(extra.first);
      used.add(extra.first.uid);
    } on ApiException {
      // Tin bổ sung không bắt buộc: lỗi thì vẫn hiển thị các tin đã có.
    }
  }
  // Giữ thứ tự chuyên mục 219 → 222 như API featured; chuyên mục khác để cuối.
  final known = {for (final category in NewsCategory.all) category.uid};
  final ordered = [
    for (final category in NewsCategory.all)
      ...others.where((item) => item.catUid == category.uid),
    ...others.where((item) => !known.contains(item.catUid)),
  ];
  return FeaturedNews(main: main, others: ordered);
}

/// Trang chủ: tin nổi bật lấy từ News REST API, hiển thị bằng widget Flutter.
class FeaturedNewsContent extends StatefulWidget {
  const FeaturedNewsContent({super.key, required this.api, this.onSelected});

  final NewsApi api;

  /// Chạm vào một tin. null thì thẻ tin không nhận chạm (chưa có trang chi tiết).
  final ValueChanged<NewsItem>? onSelected;

  @override
  State<FeaturedNewsContent> createState() => _FeaturedNewsContentState();
}

class _FeaturedNewsContentState extends State<FeaturedNewsContent> {
  late Future<FeaturedNews> _news;

  @override
  void initState() {
    super.initState();
    _news = loadFeaturedNews(widget.api);
  }

  Future<void> _reload() async {
    final future = loadFeaturedNews(widget.api);
    setState(() {
      _news = future;
    });
    try {
      await future;
    } catch (_) {
      /* FutureBuilder hiển thị lỗi. */
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: FutureBuilder<FeaturedNews>(
      future: _news,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          return _Message(
            icon: Icons.wifi_off,
            text: error is ApiException
                ? error.message
                : 'Không thể tải tin tức. Vui lòng thử lại.',
            onRetry: _reload,
          );
        }
        final news = snapshot.data!;
        if (news.isEmpty) {
          return _Message(
            icon: Icons.article_outlined,
            text: 'Hiện chưa có tin nổi bật.',
            onRetry: _reload,
          );
        }
        // Tối đa 5 tin nên dựng hết trong một Column cuộn được.
        return RefreshIndicator(
          onRefresh: _reload,
          child: SingleChildScrollView(
            key: const PageStorageKey('ueh-featured-news'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Tin tức',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _newsOrange,
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Thông tin mới nhất và kiến thức hữu ích từ UEH',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF808080),
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                FeaturedNewsCard(item: news.main!, onTap: _tap(news.main!)),
                for (final item in news.others) ...[
                  const SizedBox(height: 20),
                  NewsTile(item: item, onTap: _tap(item)),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    ),
  );

  VoidCallback? _tap(NewsItem item) {
    final onSelected = widget.onSelected;
    return onSelected == null ? null : () => onSelected(item);
  }
}

/// Tin lớn: ảnh phía trên; khối xanh bên dưới gồm "TIN TỨC NỔI BẬT",
/// hàng icon SDG và tiêu đề, tất cả căn giữa.
class FeaturedNewsCard extends StatelessWidget {
  const FeaturedNewsCard({super.key, required this.item, this.onTap});

  final NewsItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _Card(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 2.5,
          // Ảnh nền; thiếu thì dùng ảnh thu nhỏ; thiếu cả hai thì placeholder.
          child: NewsImage(
            url: item.backgroundImg ?? item.thumbnailImg,
            cacheWidth: 1080,
          ),
        ),
        Container(
          color: _featuredBlue,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            children: [
              const Text(
                'TIN TỨC NỔI BẬT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              if (item.sdgs.isNotEmpty) ...[
                const SizedBox(height: 10),
                SdgIcons(item.sdgs, alignment: WrapAlignment.center),
              ],
              const SizedBox(height: 10),
              Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Tin nhỏ: thẻ trắng xếp dọc gồm tên chuyên mục, hàng icon SDG và tiêu đề.
class NewsTile extends StatelessWidget {
  const NewsTile({super.key, required this.item, this.onTap});

  final NewsItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => _Card(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.categoryName.toUpperCase(),
            style: const TextStyle(
              color: _categoryBlue,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
          if (item.sdgs.isNotEmpty) ...[
            const SizedBox(height: 8),
            SdgIcons(item.sdgs),
          ],
          const SizedBox(height: 8),
          Text(
            item.title,
            textAlign: TextAlign.justify,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 18,
              height: 1.35,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Ảnh từ mạng; URL null hoặc tải lỗi thì hiện placeholder, không báo lỗi.
class NewsImage extends StatelessWidget {
  const NewsImage({super.key, required this.url, this.cacheWidth});

  final Uri? url;

  /// Giới hạn kích thước giải mã: ảnh của server nặng 0,7-1,5 MB.
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    const placeholder = ColoredBox(
      color: Color(0xFFE1EFF0),
      child: Center(
        child: Icon(Icons.image_outlined, color: AppTopBar.uehBlue, size: 32),
      ),
    );
    final url = this.url;
    if (url == null) return placeholder;
    return Image.network(
      url.toString(),
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      errorBuilder: (_, error, stackTrace) => placeholder,
    );
  }
}

/// Hàng icon SDG theo `NewsItem.sdgs`, ảnh lấy từ assets/images/sdg-N.png.
class SdgIcons extends StatelessWidget {
  const SdgIcons(
    this.sdgs, {
    super.key,
    this.size = 30,
    this.alignment = WrapAlignment.start,
  });

  final List<int> sdgs;
  final double size;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: alignment,
    spacing: 4,
    runSpacing: 4,
    children: [
      for (final sdg in sdgs)
        Image.asset(
          'assets/images/sdg-$sdg.png',
          width: size,
          height: size,
          semanticLabel: 'SDG $sdg',
          errorBuilder: (_, error, stackTrace) =>
              SizedBox.square(dimension: size),
        ),
    ],
  );
}

/// Ngày đăng dạng dd/mm/yyyy.
String formatNewsDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year}';
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  // Thẻ góc vuông, đổ bóng nhẹ như giao diện gốc.
  @override
  Widget build(BuildContext context) => DecoratedBox(
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
      child: onTap == null ? child : InkWell(onTap: onTap, child: child),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
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
