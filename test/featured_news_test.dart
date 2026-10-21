import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/models/news.dart';
import 'package:flutter_application_1/services/news_api.dart';
import 'package:flutter_application_1/widgets/featured_news.dart';

import 'news_fixtures.dart';

/// NewsApi giả: trả JSON đã cho và ghi lại mọi request.
class _FakeNews {
  _FakeNews({required this.featured, this.categories = const {}}) {
    api = NewsApi(
      client: MockClient((request) async {
        requests.add(request);
        if (featuredError != null) throw featuredError!;
        if (request.url.path == '/api/news/featured') {
          return _json(featured);
        }
        final cat = int.parse(request.url.queryParameters['cat_uid']!);
        if (categoryStatus != 200) return http.Response('', categoryStatus);
        return _json(categories[cat] ?? _page([]));
      }),
    );
    addTearDown(api.close);
  }

  final Object? featured;
  final Map<int, Object?> categories;
  late final NewsApi api;
  final requests = <http.Request>[];
  Object? featuredError;
  int categoryStatus = 200;

  List<http.Request> get categoryRequests =>
      requests.where((r) => r.url.path == '/api/news').toList();
}

http.Response _json(Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _page(List<Object?> items) => {
  'total': items.length,
  'limit': 5,
  'offset': 0,
  'items': items,
};

Map<String, Object?> _item(
  int uid,
  int cat, {
  bool featured = false,
  String? title,
  Object? bg = 'https://api.ngoisaoviet.info/images/bg.png',
  Object? thumb = 'https://api.ngoisaoviet.info/images/thumb.png',
  List<int> sdgs = const [4],
}) => {
  'uid': uid,
  'cat_uid': cat,
  'category_name': 'Mục $cat',
  'title': title ?? 'Tin $uid',
  'short_desc': '',
  'post_date': '2026-10-13T08:54:00',
  'sdgs': sdgs,
  'is_featured': featured,
  'background_img': bg,
  'thumbnail_img': thumb,
};

final _featuredReal = jsonDecode(featuredJson) as List<dynamic>;
final _samples = jsonDecode(sampleItemsJson) as List<dynamic>;
// Tin mục 219 trong mẫu thật, theo ngày đăng mới nhất trước: uid 1, 6, 18.
final _page219Real = _page([
  for (final uid in [1, 6, 18]) _samples.firstWhere((e) => e['uid'] == uid),
]);

Future<void> _pump(WidgetTester tester, NewsApi api, {Size? size}) async {
  if (size != null) {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: FeaturedNewsContent(api: api)),
    ),
  );
  await tester.pumpAndSettle();
}

List<int> _shownUids(WidgetTester tester) => [
  ...tester
      .widgetList<FeaturedNewsCard>(find.byType(FeaturedNewsCard))
      .map((w) => w.item.uid),
  ...tester.widgetList<NewsTile>(find.byType(NewsTile)).map((w) => w.item.uid),
];

void main() {
  group('Chọn 1 tin lớn và 4 tin nhỏ', () {
    test(
      'Featured trả 5 tin: dùng đúng 5 tin, không gọi thêm API chuyên mục',
      () async {
        final news = _FakeNews(
          featured: [
            _item(10, 219, featured: true),
            _item(11, 219),
            _item(12, 220),
            _item(13, 221),
            _item(14, 222),
          ],
        );
        final result = await loadFeaturedNews(news.api);
        expect(result.main!.uid, 10);
        expect(result.others.map((i) => i.uid), [11, 12, 13, 14]);
        expect(news.categoryRequests, isEmpty);
      },
    );

    test(
      'JSON thật trả 4 tin: bổ sung 1 tin mục 219 khác uid tin lớn',
      () async {
        final news = _FakeNews(
          featured: _featuredReal,
          categories: {219: _page219Real},
        );
        final result = await loadFeaturedNews(news.api);
        expect(result.main!.uid, 1);
        expect(result.main!.isFeatured, isTrue);
        // uid 1 vừa là tin nổi bật vừa là tin mới nhất mục 219: bỏ qua, lấy uid 6.
        expect(result.others.map((i) => i.uid), [6, 101, 201, 266]);
        expect(result.others.map((i) => i.catUid), [219, 220, 221, 222]);
        expect(news.categoryRequests, hasLength(1));
        expect(news.categoryRequests.single.url.queryParameters, {
          'cat_uid': '219',
          'limit': '5',
          'offset': '0',
        });
      },
    );

    test(
      'Không có tin is_featured: lấy tin đầu làm tin lớn, vẫn đủ 4 tin nhỏ',
      () async {
        final news = _FakeNews(
          featured: [
            _item(20, 219),
            _item(21, 220),
            _item(22, 221),
            _item(23, 222),
          ],
          categories: {
            219: _page([_item(20, 219), _item(24, 219)]),
          },
        );
        final result = await loadFeaturedNews(news.api);
        expect(result.main!.uid, 20);
        expect(result.others.map((i) => i.uid), [24, 21, 22, 23]);
      },
    );

    test(
      'Không nhân bản tin: uid trùng trong featured hoặc tin bổ sung bị bỏ',
      () async {
        final news = _FakeNews(
          featured: [
            _item(30, 219, featured: true),
            _item(31, 220),
            _item(31, 220),
            _item(30, 219),
          ],
          // Mục 219 chỉ có tin đã dùng; mục 221 có tin mới; mục 222 trống.
          categories: {
            219: _page([_item(30, 219)]),
            221: _page([_item(31, 220), _item(32, 221)]),
          },
        );
        final result = await loadFeaturedNews(news.api);
        final uids = [result.main!.uid, ...result.others.map((i) => i.uid)];
        expect(uids, [30, 31, 32]);
        expect(uids.toSet().length, uids.length);
        expect(
          news.categoryRequests.map((r) => r.url.queryParameters['cat_uid']),
          ['219', '221', '222'],
        );
      },
    );

    test('Gọi API chuyên mục lỗi: vẫn trả các tin đang có', () async {
      final news = _FakeNews(featured: _featuredReal)..categoryStatus = 500;
      final result = await loadFeaturedNews(news.api);
      expect(result.main!.uid, 1);
      expect(result.others.map((i) => i.uid), [101, 201, 266]);
    });

    test('Featured rỗng: không có tin lớn, không gọi API chuyên mục', () async {
      final news = _FakeNews(featured: <Object>[]);
      final result = await loadFeaturedNews(news.api);
      expect(result.isEmpty, isTrue);
      expect(news.categoryRequests, isEmpty);
    });
  });

  group('Giao diện tin nổi bật', () {
    testWidgets('JSON thật: 1 thẻ lớn, 4 thẻ nhỏ, đúng icon SDG từng tin', (
      tester,
    ) async {
      final news = _FakeNews(
        featured: _featuredReal,
        categories: {219: _page219Real},
      );
      await _pump(tester, news.api);
      expect(find.byType(FeaturedNewsCard), findsOneWidget);
      expect(find.byType(NewsTile), findsNWidgets(4));
      expect(_shownUids(tester), [1, 6, 101, 201, 266]);

      List<String> sdgAssets(Finder card) => tester
          .widgetList<Image>(
            find.descendant(of: card, matching: find.byType(Image)),
          )
          .map((image) => image.image)
          .whereType<AssetImage>()
          .map((asset) => asset.assetName)
          .toList();
      final main = NewsItem.fromJson(_featuredReal.first);
      expect(sdgAssets(find.byType(FeaturedNewsCard)), [
        for (final sdg in main.sdgs) 'assets/images/sdg-$sdg.png',
      ]);
      for (final tile in tester.widgetList<NewsTile>(find.byType(NewsTile))) {
        expect(sdgAssets(find.byWidget(tile)), [
          for (final sdg in tile.item.sdgs) 'assets/images/sdg-$sdg.png',
        ], reason: 'uid ${tile.item.uid}');
      }
      expect(find.text('13/10/2026'), findsWidgets); // ngày đăng dd/mm/yyyy
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'Ảnh null, URL lỗi hoặc tải ảnh thất bại: hiện placeholder, không crash',
      (tester) async {
        final news = _FakeNews(
          featured: [
            _item(40, 219, featured: true, bg: null, thumb: null),
            _item(41, 220, bg: null, thumb: 'khong-phai-url'),
            _item(42, 221, bg: 123, thumb: ''),
            // URL hợp lệ nhưng widget test không có mạng: Image.network báo lỗi.
            _item(43, 222, bg: null, thumb: 'https://ueh.edu.vn/khong-co.png'),
          ],
        );
        await _pump(tester, news.api);
        expect(find.byType(FeaturedNewsCard), findsOneWidget);
        expect(find.byType(NewsTile), findsNWidgets(3));
        expect(find.byIcon(Icons.image_outlined), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Tiêu đề rất dài trên màn hình hẹp không tràn layout', (
      tester,
    ) async {
      final longTitle = List.filled(40, 'Tiêu đề rất dài').join(' ');
      final news = _FakeNews(
        featured: [
          _item(50, 219, featured: true, title: longTitle, sdgs: [1, 2, 3]),
          for (var i = 0; i < 4; i++)
            _item(51 + i, 219 + i, title: longTitle, sdgs: [4, 13, 17]),
        ],
      );
      await _pump(tester, news.api, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      // Cuộn được tới tin nhỏ cuối cùng.
      await tester.scrollUntilVisible(
        find.byWidgetPredicate((w) => w is NewsTile && w.item.uid == 54),
        300,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Featured rỗng: thông báo chưa có tin và nút Thử lại', (
      tester,
    ) async {
      final news = _FakeNews(featured: <Object>[]);
      await _pump(tester, news.api);
      expect(find.text('Hiện chưa có tin nổi bật.'), findsOneWidget);
      expect(find.text('Thử lại'), findsOneWidget);
      expect(find.byType(FeaturedNewsCard), findsNothing);
    });

    testWidgets(
      'Đang tải hiện vòng xoay; mất mạng hiện lỗi; Thử lại tải được',
      (tester) async {
        final gate = Completer<http.Response>();
        var calls = 0;
        var online = false;
        final api = NewsApi(
          client: MockClient((request) {
            calls++;
            if (calls == 1) return gate.future;
            if (!online) throw http.ClientException('offline');
            return Future.value(
              _json(
                request.url.path == '/api/news/featured'
                    ? [for (var i = 0; i < 5; i++) _item(60 + i, 219 + (i % 4))]
                    : _page([]),
              ),
            );
          }),
        );
        addTearDown(api.close);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: FeaturedNewsContent(api: api)),
          ),
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        gate.completeError(http.ClientException('offline'));
        await tester.pumpAndSettle();
        expect(
          find.text('Không thể kết nối máy chủ. Vui lòng kiểm tra mạng.'),
          findsOneWidget,
        );

        online = true;
        await tester.tap(find.text('Thử lại'));
        await tester.pumpAndSettle();
        expect(find.byType(FeaturedNewsCard), findsOneWidget);
        expect(find.byType(NewsTile), findsNWidgets(4));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Chưa có trang chi tiết: thẻ tin không nhận chạm khi không truyền onSelected',
      (tester) async {
        final news = _FakeNews(
          featured: [for (var i = 0; i < 5; i++) _item(70 + i, 219 + (i % 4))],
        );
        await _pump(tester, news.api);
        expect(find.byType(InkWell), findsNothing);

        NewsItem? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FeaturedNewsContent(
                api: news.api,
                onSelected: (item) => selected = item,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(FeaturedNewsCard));
        expect(selected?.uid, 70);
      },
    );
  });

  test('Ngày đăng hiển thị dd/mm/yyyy', () {
    expect(formatNewsDate(DateTime(2026, 4, 1, 7)), '01/04/2026');
    expect(formatNewsDate(DateTime(2026, 10, 13)), '13/10/2026');
  });
}
