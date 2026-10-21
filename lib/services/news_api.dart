import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/news.dart';
import 'student_api.dart' show ApiException;

/// Gọi 3 API tin tức công khai. Không gửi Bearer token, không dùng refresh
/// token: tách hẳn khỏi [StudentApi] nên lỗi tin tức không ảnh hưởng phiên.
class NewsApi {
  NewsApi({http.Client? client, Uri? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          Uri.parse(
            const String.fromEnvironment(
              'UEH_API_URL',
              defaultValue: 'https://api.ngoisaoviet.info',
            ),
          ) {
    if (_baseUrl.scheme != 'https' || !_baseUrl.hasAuthority) {
      throw ArgumentError('UEH_API_URL phải là HTTPS.');
    }
  }

  static const defaultLimit = 20;
  static const maxLimit = 100;
  static const timeout = Duration(seconds: 20);

  final http.Client _client;
  final Uri _baseUrl;

  /// GET /api/news/featured: tối đa 5 tin, có thể ít hơn.
  Future<List<NewsItem>> featured() async =>
      _parse(await _get('/api/news/featured'), NewsItem.listFromJson);

  /// GET /api/news?cat_uid=&limit=&offset=
  ///
  /// [offset] là số tin bỏ qua (0, 20, 40...), không phải số trang.
  Future<NewsPage> category(
    int catUid, {
    int limit = defaultLimit,
    int offset = 0,
  }) async {
    if (limit < 1 || limit > maxLimit) {
      throw ArgumentError.value(limit, 'limit', 'phải từ 1 đến $maxLimit');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'không được âm');
    }
    final json = await _get('/api/news', {
      'cat_uid': '$catUid',
      'limit': '$limit',
      'offset': '$offset',
    });
    return _parse(json, NewsPage.fromJson);
  }

  /// GET /api/news/{uid}: thêm `content` là HTML.
  Future<NewsDetail> detail(int uid) async =>
      _parse(await _get('/api/news/$uid'), NewsDetail.fromJson);

  T _parse<T>(Object? json, T Function(Object?) fromJson) {
    try {
      return fromJson(json);
    } on FormatException {
      throw const ApiException(
        'Dữ liệu tin tức trả về không hợp lệ. Vui lòng thử lại.',
      );
    }
  }

  Future<Object?> _get(String path, [Map<String, String>? query]) async {
    var uri = _baseUrl.resolve(path);
    if (query != null) uri = uri.replace(queryParameters: query);
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        'Kết nối quá thời gian chờ. Vui lòng kiểm tra mạng và thử lại.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng.',
      );
    }

    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      /* Body rỗng hoặc không phải JSON: xử lý bên dưới. */
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (json == null) {
        throw const ApiException('Máy chủ trả về dữ liệu tin tức không hợp lệ.');
      }
      return json;
    }
    final message = json is Map ? json['message'] : null;
    throw ApiException(
      message is String && message.isNotEmpty
          ? message
          : 'Máy chủ chưa tải được tin tức (${response.statusCode}). Vui lòng thử lại.',
      statusCode: response.statusCode,
    );
  }

  void close() => _client.close();
}
