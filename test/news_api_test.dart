import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:http/testing.dart';
import 'package:flutter_application_1/models/news.dart';
import 'package:flutter_application_1/services/news_api.dart';
import 'package:flutter_application_1/services/student_api.dart';

import 'news_fixtures.dart';
import 'student_api_test.dart' show MemoryTokenStore, jsonResponse, tokens;

final _samples = (jsonDecode(sampleItemsJson) as List)
    .cast<Map<String, dynamic>>();
Map<String, dynamic> _sample(int uid) => _samples.firstWhere((m) => m['uid'] == uid);

Map<String, dynamic> _page(
  List<Object?> items, {
  int total = 85,
  int limit = 20,
  int offset = 0,
}) => {'total': total, 'limit': limit, 'offset': offset, 'items': items};

/// NewsApi với MockClient; ghi lại mọi request để kiểm tra URL và header.
({NewsApi api, List<http.Request> requests}) _news(
  FutureOr<http.Response> Function(http.Request request) handler,
) {
  final requests = <http.Request>[];
  final api = NewsApi(
    client: MockClient((request) async {
      requests.add(request);
      return handler(request);
    }),
  );
  addTearDown(api.close);
  return (api: api, requests: requests);
}

http.Response _raw(String body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(body), status);

// Chỉ dùng khi chủ động bật UEH_LIVE_TEST; test mặc định chặn HTTP thật.
class _LiveHttpOverrides extends HttpOverrides {}

void main() {
  group('Featured', () {
    test('JSON thật: 4 tin (ít hơn 5), giữ thứ tự, tin đầu là tin nổi bật', () async {
      final n = _news((_) => _raw(featuredJson));
      final items = await n.api.featured();
      expect(items.map((i) => i.uid), [1, 101, 201, 266]);
      expect(items.map((i) => i.catUid), [219, 220, 221, 222]);
      expect(items.first.isFeatured, isTrue);
      expect(items.skip(1).every((i) => !i.isFeatured), isTrue);
      final request = n.requests.single;
      expect(request.method, 'GET');
      expect(request.url.toString(), 'https://api.ngoisaoviet.info/api/news/featured');
      expect(request.headers['Accept'], 'application/json');
    });

    test('Mảng rỗng là kết quả hợp lệ', () async {
      final n = _news((_) => jsonResponse(<Object>[]));
      expect(await n.api.featured(), isEmpty);
    });

    test('Response không phải mảng thì báo lỗi dữ liệu', () async {
      final n = _news((_) => jsonResponse({'items': []}));
      await expectLater(n.api.featured(), throwsA(isA<ApiException>()));
    });
  });

  group('Danh sách theo chuyên mục', () {
    test('Bốn chuyên mục 219-222 gửi đúng cat_uid và đọc đúng chuyên mục', () async {
      for (final category in NewsCategory.all) {
        final items = _samples.where((m) => m['cat_uid'] == category.uid).toList();
        final n = _news((_) => jsonResponse(_page(items)));
        final page = await n.api.category(category.uid);
        expect(n.requests.single.url.path, '/api/news');
        expect(n.requests.single.url.queryParameters, {
          'cat_uid': '${category.uid}',
          'limit': '20',
          'offset': '0',
        });
        expect(page.items, hasLength(items.length));
        expect(page.items.every((i) => i.catUid == category.uid), isTrue);
        expect(page.items.every((i) => i.categoryName == category.name), isTrue);
      }
    });

    test('limit và offset gửi đúng; offset là số tin bỏ qua, không phải số trang', () async {
      final n = _news((_) => jsonResponse(_page([_sample(1)], offset: 40)));
      final page = await n.api.category(219, limit: 20, offset: 40);
      expect(n.requests.single.url.queryParameters, {
        'cat_uid': '219',
        'limit': '20',
        'offset': '40',
      });
      expect(page.offset, 40);
      expect(page.nextOffset, 41);
    });

    test('Lazy load 45 tin với limit 20: offset 0 → 20 → 40, dừng khi đủ total', () async {
      Map<String, dynamic> copy(int uid) => {..._sample(1), 'uid': uid};
      final n = _news((request) {
        final offset = int.parse(request.url.queryParameters['offset']!);
        final count = (45 - offset).clamp(0, 20);
        return jsonResponse(
          _page([for (var i = 0; i < count; i++) copy(offset + i + 1)], total: 45, offset: offset),
        );
      });
      final offsets = <int>[];
      var offset = 0;
      var more = true;
      while (more) {
        offsets.add(offset);
        final page = await n.api.category(219, offset: offset);
        offset = page.nextOffset;
        more = page.hasMore;
      }
      expect(offsets, [0, 20, 40]);
      expect(offset, 45);
    });

    test('Trang rỗng (offset vượt total hoặc chuyên mục không có tin)', () async {
      for (final body in [
        _page([], total: 85, offset: 100000),
        _page([], total: 0),
      ]) {
        final n = _news((_) => jsonResponse(body));
        final page = await n.api.category(219, offset: body['offset'] as int);
        expect(page.items, isEmpty);
        expect(page.hasMore, isFalse);
      }
    });

    test('limit ngoài 1-100 hoặc offset âm: báo lỗi, không gửi request', () async {
      final n = _news((_) => jsonResponse(_page([])));
      expect(() => n.api.category(219, limit: 0), throwsArgumentError);
      expect(() => n.api.category(219, limit: 101), throwsArgumentError);
      expect(() => n.api.category(219, offset: -1), throwsArgumentError);
      expect(n.requests, isEmpty);
    });
  });

  group('Model NewsItem từ JSON thật', () {
    final byUid = {for (final m in _samples) m['uid'] as int: NewsItem.fromJson(m)};

    test('Tiêu đề và mô tả bỏ \\r\\n, khoảng trắng thừa', () {
      final item = byUid[1]!;
      expect(
        item.title,
        '[Photo Story | UEH Alumni Gratitude Campus Tour 2026] Cựu sinh viên Khoa KQM trở về UEH',
      );
      expect(item.shortDesc, endsWith('Where We Belong”.'));
      expect(byUid[201]!.shortDesc, endsWith('trong đào tạo.'));
      expect(byUid[6]!.shortDesc, isNull); // short_desc rỗng
    });

    test('short_desc chứa HTML được đổi thành chữ thuần', () {
      final desc = byUid[154]!.shortDesc!;
      expect(desc, startsWith('"Cuộc cạnh tranh của các quốc gia'));
      expect(desc, isNot(contains('<')));
      expect(desc, isNot(contains('&quot;')));
    });

    test('Ảnh null giữ null; URL bị ghép domain được sửa; URL đúng giữ nguyên', () {
      expect(byUid[201]!.backgroundImg, isNull);
      expect(byUid[201]!.thumbnailImg.toString(), startsWith('https://api.ngoisaoviet.info/images/upload/thumbnail/'));
      expect(byUid[154]!.backgroundImg, isNull);
      expect(byUid[154]!.thumbnailImg, isNull);
      expect(
        byUid[304]!.thumbnailImg.toString(),
        startsWith('https://iscm-api.ueh.edu.vn/public/static/images/open-admission/'),
      );
      expect(byUid[6]!.thumbnailImg.toString(), 'https://dsa.ueh.edu.vn/wp-content/uploads/2026/10/BAO_0699.webp');
      expect(
        byUid[1]!.backgroundImg.toString(),
        'https://api.ngoisaoviet.info/images/upload/img_background/ueh-background-639274789085988285.png',
      );
    });

    test('Quy tắc imageUrl', () {
      const cases = <Object?, String?>{
        null: null,
        '': null,
        '   ': null,
        42: null,
        '/images/a.png': null, // không tự nối base URL
        'ftp://ueh.edu.vn/a.png': null,
        'khong-phai-url': null,
        'https://ueh.edu.vn/a.png': 'https://ueh.edu.vn/a.png',
        ' https://ueh.edu.vn/a.png ': 'https://ueh.edu.vn/a.png',
        'http://ueh.edu.vn/a.png': 'http://ueh.edu.vn/a.png',
        'https://api.ngoisaoviet.infohttps://dsa.ueh.edu.vn/a.webp': 'https://dsa.ueh.edu.vn/a.webp',
        'https://api.ngoisaoviet.infohttp://x.ueh.edu.vn/b.png': 'http://x.ueh.edu.vn/b.png',
      };
      cases.forEach((input, expected) {
        expect(NewsItem.imageUrl(input)?.toString(), expected, reason: '$input');
      });
    });

    test('URL hợp lệ có "https://" ở query, đường dẫn hoặc fragment được giữ nguyên', () {
      const valid = [
        'https://ueh.edu.vn/image.php?src=https://cdn.ueh.edu.vn/a.png',
        'https://ueh.edu.vn/resize?url=https%3A%2F%2Fcdn.ueh.edu.vn%2Fa.png&w=300',
        'https://proxy.ueh.edu.vn/fetch/https://cdn.ueh.edu.vn/a.png',
        'http://ueh.edu.vn/a.png#https://ueh.edu.vn',
        'https://ueh.edu.vn:8443/a.png?next=http://x.vn',
      ];
      for (final url in valid) {
        expect(NewsItem.imageUrl(url)?.toString(), url, reason: url);
      }
      // Ghép lặp nhiều lần vẫn lấy đúng URL gốc, giữ cả query của URL gốc.
      expect(
        NewsItem.imageUrl(
          'https://api.ngoisaoviet.infohttps://api.ngoisaoviet.infohttps://dsa.ueh.edu.vn/a.webp?v=https://x.vn',
        )?.toString(),
        'https://dsa.ueh.edu.vn/a.webp?v=https://x.vn',
      );
    });

    test('SDG giữ đúng thứ tự server; bỏ số ngoài 1-17, trùng hoặc sai kiểu', () {
      expect(byUid[18]!.sdgs, [4, 3, 11]);
      final item = NewsItem.fromJson({..._sample(1), 'sdgs': [0, 4, 4, 18, '5', 9, 17]});
      expect(item.sdgs, [4, 9, 17]);
      expect(NewsItem.fromJson({..._sample(1), 'sdgs': '4'}).sdgs, isEmpty);
    });

    test('post_date đọc theo giờ server, không đổi múi giờ', () {
      final date = byUid[1]!.postDate!;
      expect(date, DateTime(2026, 10, 13, 8, 54));
      expect(date.isUtc, isFalse);
    });

    test('Trường không bắt buộc sai kiểu thì để trống, không làm lỗi tin', () {
      final item = NewsItem.fromJson({
        ..._sample(1),
        'post_date': 123,
        'is_featured': 'true',
        'background_img': 5,
        'short_desc': null,
      });
      expect(item.postDate, isNull);
      expect(item.isFeatured, isFalse);
      expect(item.backgroundImg, isNull);
      expect(item.shortDesc, isNull);
    });
  });

  group('Dữ liệu thiếu hoặc sai cấu trúc', () {
    test('Tin thiếu uid, uid sai kiểu hoặc tiêu đề rỗng bị bỏ qua, tin khác vẫn giữ', () async {
      final broken = [
        {..._sample(1)}..remove('uid'),
        {..._sample(18), 'uid': '18'},
        {..._sample(6), 'title': ' \r\n '},
        {..._sample(201)}..remove('cat_uid'),
        'không phải object',
        _sample(304),
      ];
      final n = _news((_) => jsonResponse(_page(broken, total: 6)));
      final page = await n.api.category(219);
      expect(page.items.map((i) => i.uid), [304]);
      expect(page.receivedCount, 6);
      expect(page.skippedCount, 5);
      expect(page.nextOffset, 6); // offset tính theo số tin server gửi
    });

    test('Trang thiếu items/total hoặc sai kiểu thì báo lỗi dữ liệu', () async {
      for (final body in <Object>[
        {'total': 1, 'limit': 20, 'offset': 0},
        {'total': 1, 'limit': 20, 'offset': 0, 'items': {}},
        {'limit': 20, 'offset': 0, 'items': []},
        {'total': '1', 'limit': 20, 'offset': 0, 'items': []},
        <Object>[],
      ]) {
        final n = _news((_) => jsonResponse(body));
        await expectLater(
          n.api.category(219),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Dữ liệu tin tức trả về không hợp lệ. Vui lòng thử lại.')),
        );
      }
    });

    test('Body rỗng hoặc không phải JSON với HTTP 200', () async {
      for (final body in ['', '<html>gateway</html>']) {
        final n = _news((_) => _raw(body));
        await expectLater(n.api.featured(), throwsA(isA<ApiException>()));
      }
    });
  });

  group('Chi tiết tin', () {
    test('GET /api/news/{uid}: giữ nguyên HTML trong content', () async {
      final n = _news((_) => _raw(detail304Json));
      final detail = await n.api.detail(304);
      expect(n.requests.single.url.path, '/api/news/304');
      expect(detail.item.uid, 304);
      expect(detail.content, (jsonDecode(detail304Json) as Map)['content']);
      expect(detail.content, startsWith('<p><img src="https://iscm-api.ueh.edu.vn/'));
      expect(detail.item.backgroundImg!.host, 'iscm-api.ueh.edu.vn');
    });

    test('Chi tiết thiếu content thì báo lỗi dữ liệu', () async {
      final n = _news((_) => jsonResponse(_sample(304)));
      await expectLater(n.api.detail(304), throwsA(isA<ApiException>()));
    });
  });

  group('Lỗi HTTP và mạng', () {
    test('4xx/5xx: dùng message của server nếu có, kèm status code', () async {
      final cases = <http.Response, (int, String)>{
        jsonResponse({'message': 'Không tìm thấy tin tức.'}, 404): (404, 'Không tìm thấy tin tức.'),
        jsonResponse({'message': 'Thiếu tham số cat_uid.'}, 400): (400, 'Thiếu tham số cat_uid.'),
        _raw('<html>502</html>', 502): (502, 'Máy chủ chưa tải được tin tức (502). Vui lòng thử lại.'),
        _raw('', 500): (500, 'Máy chủ chưa tải được tin tức (500). Vui lòng thử lại.'),
      };
      for (final MapEntry(key: response, value: (status, message)) in cases.entries) {
        final n = _news((_) => response);
        await expectLater(
          n.api.detail(1),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'status', status)
                .having((e) => e.message, 'message', message),
          ),
        );
      }
    });

    test('Timeout và mất mạng báo lỗi thân thiện, không crash', () async {
      final timeout = _news((_) => throw TimeoutException('timeout'));
      await expectLater(
        timeout.api.featured(),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Kết nối quá thời gian chờ. Vui lòng kiểm tra mạng và thử lại.')),
      );
      final offline = _news((_) => throw http.ClientException('offline'));
      await expectLater(
        offline.api.category(220),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Không thể kết nối máy chủ. Vui lòng kiểm tra mạng.')),
      );
    });
  });

  group('Không dùng token', () {
    test('Cả 3 endpoint không gửi Authorization, chỉ dùng GET', () async {
      final n = _news((request) => switch (request.url.path) {
        '/api/news/featured' => _raw(featuredJson),
        '/api/news' => jsonResponse(_page([_sample(1)])),
        _ => _raw(detail304Json),
      });
      await n.api.featured();
      await n.api.category(219);
      await n.api.detail(304);
      expect(n.requests, hasLength(3));
      for (final request in n.requests) {
        expect(request.method, 'GET');
        expect(
          request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')),
        );
      }
    });

    test('Tin tức trả 401 không gọi refresh token và không động tới phiên', () async {
      final session = MemoryTokenStore()..value = jsonEncode(tokens());
      final student = StudentApi(
        store: session,
        client: MockClient((_) async => fail('StudentApi không được gọi')),
      );
      addTearDown(student.close);
      await student.restore();

      final n = _news((_) => http.Response('', 401));
      await expectLater(
        n.api.featured(),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      expect(n.requests.map((r) => r.url.path), ['/api/news/featured']);
      expect(session.value, jsonEncode(tokens()));
      expect(student.hasSession, isTrue);
    });
  });

  test('API thật: featured, 4 chuyên mục, phân trang và chi tiết', () async {
    final api = NewsApi(client: IOClient(_LiveHttpOverrides().createHttpClient(null)));
    addTearDown(api.close);
    final featured = await api.featured();
    expect(featured.length, inInclusiveRange(1, 5));
    for (final category in NewsCategory.all) {
      final first = await api.category(category.uid, limit: 5);
      expect(first.items.every((i) => i.catUid == category.uid), isTrue);
      expect(first.items.every((i) => i.title == i.title.trim()), isTrue);
      if (first.hasMore) {
        final second = await api.category(category.uid, limit: 5, offset: first.nextOffset);
        expect(second.total, first.total);
        expect(
          second.items.map((i) => i.uid).toSet().intersection(first.items.map((i) => i.uid).toSet()),
          isEmpty,
        );
      }
    }
    final detail = await api.detail(featured.first.uid);
    expect(detail.item.uid, featured.first.uid);
    expect(detail.content, contains('<'));
  }, skip: !const bool.fromEnvironment('UEH_LIVE_TEST'));
}
