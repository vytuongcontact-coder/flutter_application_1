import 'dart:collection';

import 'package:html/parser.dart' as html;

/// Một chuyên mục tin: `cat_uid` trên API và tên hiển thị.
class NewsCategory {
  const NewsCategory(this.uid, this.name);

  final int uid;
  final String name;

  /// Bốn chuyên mục của bài giữa kỳ (tên khớp `category_name` server trả về).
  static const all = [
    NewsCategory(219, 'Cuộc sống UEH'),
    NewsCategory(220, 'Khoa học - Góc nhìn chuyên gia'),
    NewsCategory(221, 'Báo chí nói về UEH'),
    NewsCategory(222, 'Tuyển sinh & Hướng nghiệp'),
  ];
}

/// Một tin trong danh sách (GET /api/news/featured, GET /api/news).
///
/// JSON dùng snake_case (`cat_uid`), Dart dùng camelCase ([catUid]).
class NewsItem {
  const NewsItem({
    required this.uid,
    required this.catUid,
    required this.categoryName,
    required this.title,
    this.shortDesc,
    this.postDate,
    this.sdgs = const [],
    this.isFeatured = false,
    this.backgroundImg,
    this.thumbnailImg,
  });

  /// Định danh bài viết; dùng để gọi GET /api/news/{uid}.
  final int uid;
  final int catUid;
  final String categoryName;

  /// Đã bỏ khoảng trắng và xuống dòng thừa (server có tiêu đề kết thúc `\r\n`).
  final String title;

  /// Mô tả ngắn dạng chữ thuần; null nếu rỗng. Một số bài server trả kèm thẻ HTML.
  final String? shortDesc;

  /// Ngày đăng theo giờ server (không kèm múi giờ); null nếu không đọc được.
  final DateTime? postDate;

  /// Số SDG từ 1 đến 17, giữ đúng thứ tự server trả về.
  final List<int> sdgs;
  final bool isFeatured;

  /// Ảnh nền và ảnh thu nhỏ; mỗi ảnh có thể null độc lập.
  final Uri? backgroundImg;
  final Uri? thumbnailImg;

  /// Đọc một tin. Thiếu `uid`, `cat_uid`, `category_name` hoặc `title` thì
  /// ném [FormatException]; các trường còn lại sai kiểu thì để trống.
  factory NewsItem.fromJson(Object? json) {
    final map = _object(json);
    return NewsItem(
      uid: _requiredInt(map, 'uid'),
      catUid: _requiredInt(map, 'cat_uid'),
      categoryName: _requiredText(map, 'category_name'),
      title: _requiredText(map, 'title'),
      shortDesc: _plainText(map['short_desc']),
      postDate: map['post_date'] is String
          ? DateTime.tryParse(map['post_date'] as String)
          : null,
      sdgs: _sdgs(map['sdgs']),
      isFeatured: map['is_featured'] == true,
      backgroundImg: imageUrl(map['background_img']),
      thumbnailImg: imageUrl(map['thumbnail_img']),
    );
  }

  /// Đọc mảng tin (featured). Bài lỗi bị bỏ qua, không làm hỏng cả danh sách.
  static List<NewsItem> listFromJson(Object? json) {
    if (json is! List) {
      throw const FormatException('Danh sách tin phải là JSON array.');
    }
    return _parseItems(json);
  }

  /// Chuẩn hóa URL ảnh.
  ///
  /// - null, rỗng, không phải chuỗi: null.
  /// - Server đôi khi ghép domain vào URL đã đầy đủ, ví dụ
  ///   `https://api.ngoisaoviet.infohttps://dsa.ueh.edu.vn/a.webp`:
  ///   bỏ phần `scheme://tên-miền` đứng liền trước `http(s)://` khác.
  ///   `https://` nằm sau `/`, `?` hoặc `#` (query, đường dẫn) được giữ nguyên.
  /// - Chỉ nhận URL tuyệt đối http/https, không tự nối base URL.
  static Uri? imageUrl(Object? value) {
    if (value is! String) return null;
    final text = value.trim().replaceFirst(_duplicatedOrigin, '');
    final uri = Uri.tryParse(text);
    final valid =
        uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'https' || uri.scheme == 'http');
    return valid ? uri : null;
  }

  // Một hoặc nhiều `http(s)://tên-miền` (không chứa / ? #) đứng liền trước
  // `http(s)://` khác ở đầu chuỗi.
  static final _duplicatedOrigin = RegExp(
    r'^(?:https?://[^/?#\s]*?(?=https?://))+',
  );
}

/// Chi tiết một tin (GET /api/news/{uid}): thông tin tin + nội dung HTML.
class NewsDetail {
  const NewsDetail({required this.item, required this.content});

  final NewsItem item;

  /// HTML gốc của bài viết, giữ nguyên để render ở bước sau.
  final String content;

  factory NewsDetail.fromJson(Object? json) {
    final map = _object(json);
    final content = map['content'];
    if (content is! String) {
      throw const FormatException('Chi tiết tin thiếu content.');
    }
    return NewsDetail(item: NewsItem.fromJson(map), content: content);
  }
}

/// Một trang tin theo chuyên mục: `{total, limit, offset, items}`.
class NewsPage {
  const NewsPage({
    required this.total,
    required this.limit,
    required this.offset,
    required this.items,
    required this.receivedCount,
  });

  /// Tổng số tin của chuyên mục (không phụ thuộc limit, offset).
  final int total;
  final int limit;

  /// Số tin đã bỏ qua trước trang này (không phải số trang).
  final int offset;
  final List<NewsItem> items;

  /// Số phần tử server gửi trong `items`, kể cả phần tử lỗi bị bỏ qua.
  final int receivedCount;

  int get skippedCount => receivedCount - items.length;

  /// Offset cho lần tải kế tiếp: cộng số tin server đã gửi.
  int get nextOffset => offset + receivedCount;

  /// Còn tin để tải khi offset + số tin đã nhận < total.
  bool get hasMore => receivedCount > 0 && nextOffset < total;

  factory NewsPage.fromJson(Object? json) {
    final map = _object(json);
    final items = map['items'];
    if (items is! List) {
      throw const FormatException('Trang tin thiếu items.');
    }
    return NewsPage(
      total: _requiredInt(map, 'total'),
      limit: _requiredInt(map, 'limit'),
      offset: _requiredInt(map, 'offset'),
      items: _parseItems(items),
      receivedCount: items.length,
    );
  }
}

List<NewsItem> _parseItems(List<dynamic> json) {
  final items = <NewsItem>[];
  for (final value in json) {
    try {
      items.add(NewsItem.fromJson(value));
    } on FormatException {
      // Bỏ qua tin thiếu trường định danh; các tin khác vẫn hiển thị.
    }
  }
  return List.unmodifiable(items);
}

Map<String, dynamic> _object(Object? json) {
  if (json is Map<String, dynamic>) return json;
  throw const FormatException('Tin tức phải là JSON object.');
}

int _requiredInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  throw FormatException('Thiếu hoặc sai kiểu trường $key.');
}

String _requiredText(Map<String, dynamic> map, String key) {
  final value = map[key];
  final text = value is String ? _collapse(value) : '';
  if (text.isNotEmpty) return text;
  throw FormatException('Thiếu trường $key.');
}

// Gộp mọi khoảng trắng, \r\n, tab thành một dấu cách và bỏ ở hai đầu.
String _collapse(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

// Bỏ thẻ HTML và giải mã entity (&quot;...) rồi gộp khoảng trắng.
String? _plainText(Object? value) {
  if (value is! String) return null;
  final text = _collapse(html.parseFragment(value).text ?? '');
  return text.isEmpty ? null : text;
}

// Chỉ giữ số nguyên 1-17, bỏ trùng, giữ thứ tự server.
List<int> _sdgs(Object? value) {
  if (value is! List) return const [];
  final sdgs = LinkedHashSet<int>.of(
    value.whereType<int>().where((sdg) => sdg >= 1 && sdg <= 17),
  );
  return List.unmodifiable(sdgs);
}
