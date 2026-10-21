import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/models/news.dart';
import 'package:flutter_application_1/services/news_api.dart';
import 'package:flutter_application_1/widgets/all_news.dart';
import 'package:flutter_application_1/widgets/featured_news.dart';

/// Server giả cho GET /api/news?cat_uid=: mỗi chuyên mục một danh sách đã sắp
/// xếp mới nhất trước (như API thật), trả lát cắt theo limit/offset.
class _FakeServer {
  _FakeServer(this.data) {
    api = NewsApi(
      client: MockClient((request) async {
        if (request.url.path != '/api/news') {
          detailRequests.add(request.url.path);
          return http.Response('', 404);
        }
        final q = request.url.queryParameters;
        final cat = int.parse(q['cat_uid']!);
        final limit = int.parse(q['limit']!);
        final offset = int.parse(q['offset']!);
        requests.add((cat: cat, limit: limit, offset: offset));
        final gate = gates[(cat, offset)];
        if (gate != null) await gate.future;
        if (failures.remove((cat, offset))) return http.Response('', 500);
        if (throws.remove((cat, offset))) {
          throw const HandshakeException('Lỗi TLS giả lập');
        }
        final all = data[cat] ?? const [];
        final items = all.skip(offset).take(limit).toList();
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'total': all.length,
              'limit': limit,
              'offset': offset,
              'items': items,
            }),
          ),
          200,
        );
      }),
    );
    addTearDown(api.close);
  }

  final Map<int, List<Map<String, Object?>>> data;
  late final NewsApi api;
  final requests = <({int cat, int limit, int offset})>[];
  final detailRequests = <String>[];
  final gates = <(int, int), Completer<void>>{};
  final failures = <(int, int)>{};
  final throws = <(int, int)>{};

  List<int> offsetsOf(int cat) => [
    for (final r in requests)
      if (r.cat == cat) r.offset,
  ];

  /// Thứ tự đúng: toàn bộ dữ liệu sắp theo ngày đăng mới nhất trước.
  List<int> globalOrder() {
    final all = [for (final list in data.values) ...list]
      ..sort(
        (a, b) =>
            (b['post_date'] as String).compareTo(a['post_date'] as String),
      );
    final seen = <int>{};
    return [
      for (final item in all)
        if (seen.add(item['uid'] as int)) item['uid'] as int,
    ];
  }
}

Map<String, Object?> _item(
  int uid,
  int cat,
  DateTime date, {
  String? desc,
  String? thumb,
  List<int> sdgs = const [4],
}) => {
  'uid': uid,
  'cat_uid': cat,
  'category_name': NewsCategory.all.firstWhere((c) => c.uid == cat).name,
  'title': 'Tin $uid',
  'short_desc': desc ?? '',
  'post_date': date.toIso8601String(),
  'sdgs': sdgs,
  'is_featured': false,
  'background_img': null,
  'thumbnail_img': thumb,
};

/// [count] tin mỗi chuyên mục, mới nhất trước. Mục 219 đăng dày đặc (mỗi giờ),
/// các mục khác thưa hơn: tin mới nhất phần lớn thuộc 219.
Map<int, List<Map<String, Object?>>> _data({
  int count = 12,
  bool dense219 = true,
}) {
  final start = DateTime(2026, 10, 20, 12);
  return {
    for (final (i, category) in NewsCategory.all.indexed)
      category.uid: [
        for (var k = 0; k < count; k++)
          _item(
            category.uid * 1000 + k,
            category.uid,
            start.subtract(
              // Lệch thêm i phút theo chuyên mục: không có hai tin trùng giờ.
              Duration(
                hours: category.uid == 219 && dense219 ? k : k * 7 + i,
                minutes: i,
              ),
            ),
          ),
      ],
  };
}

Future<List<int>> _takeAll(MergedNewsLoader loader) async {
  final uids = <int>[];
  while (true) {
    final item = await loader.takeNext();
    if (item == null) return uids;
    uids.add(item.uid);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

AllNewsContentState _state(WidgetTester tester) =>
    tester.state<AllNewsContentState>(find.byType(AllNewsContent));

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -100000));
  await _settle(tester);
}

void main() {
  group('Ghép tin 4 chuyên mục (MergedNewsLoader)', () {
    test('Lượt đầu tải 5 tin của cả 4 chuyên mục, offset 0', () async {
      final server = _FakeServer(_data());
      final loader = MergedNewsLoader(server.api);
      final first = await loader.takeNext();
      expect(server.requests, hasLength(4));
      expect(server.requests.map((r) => r.cat).toSet(), {219, 220, 221, 222});
      expect(
        server.requests.every((r) => r.limit == 5 && r.offset == 0),
        isTrue,
      );
      expect(first?.uid, server.globalOrder().first);
    });

    test('Thứ tự ghép đúng toàn bộ dữ liệu; nguồn hết bộ đệm được tải thêm trước khi chọn', () async {
      final server = _FakeServer(_data(count: 12));
      final loader = MergedNewsLoader(server.api);
      final uids = await _takeAll(loader);
      expect(uids, server.globalOrder());
      expect(uids.toSet(), hasLength(48));
      // Mục 219 đăng dày: phải tải thêm offset 5, 10 theo NewsPage.nextOffset.
      expect(server.offsetsOf(219), [0, 5, 10]);
      expect(loader.hasMore, isFalse);
      // Hết tin: gọi takeNext() thêm lần nữa không gửi request mới.
      final requestCount = server.requests.length;
      expect(await loader.takeNext(), isNull);
      expect(server.requests.length, requestCount);
    });

    test('Lấy 10 tin đầu không tải hết dữ liệu', () async {
      final server = _FakeServer(_data(count: 40));
      final loader = MergedNewsLoader(server.api);
      for (var i = 0; i < 10; i++) {
        await loader.takeNext();
      }
      final total = server.requests.length;
      expect(total, lessThanOrEqualTo(6));
      expect(loader.hasMore, isTrue);
    });

    test('Tin lỗi bị bỏ qua: offset kế tiếp vẫn theo số tin server gửi (nextOffset)', () async {
      final data = _data(count: 12);
      data[219]![2] = {'title': 'thiếu uid'}; // model bỏ qua tin này
      final server = _FakeServer(data);
      final uids = await _takeAll(MergedNewsLoader(server.api));
      expect(server.offsetsOf(219), [0, 5, 10]);
      expect(uids, hasLength(47));
      expect(uids.toSet(), hasLength(47));
    });

    test('Uid trùng giữa các chuyên mục chỉ xuất hiện một lần', () async {
      final data = _data(count: 3, dense219: false);
      data[220]!.insert(0, {...data[219]!.first, 'cat_uid': 220});
      final server = _FakeServer(data);
      final uids = await _takeAll(MergedNewsLoader(server.api));
      expect(uids.toSet().length, uids.length);
      expect(uids, hasLength(12));
    });

    test('Một chuyên mục lỗi: ném lỗi, các mục khác giữ dữ liệu; gọi lại chỉ tải mục lỗi', () async {
      final server = _FakeServer(_data(count: 3))..failures.add((221, 0));
      final loader = MergedNewsLoader(server.api);
      await expectLater(loader.takeNext(), throwsA(isA<Exception>()));
      expect(server.requests, hasLength(4));
      final uids = await _takeAll(loader);
      expect(server.offsetsOf(219), [0]);
      expect(server.offsetsOf(221), [0, 0]); // chỉ mục 221 được gọi lại
      expect(uids, server.globalOrder());
    });

    test('Các mục rỗng: hết tin ngay, không lặp request', () async {
      final server = _FakeServer({});
      final loader = MergedNewsLoader(server.api);
      expect(await loader.takeNext(), isNull);
      expect(server.requests, hasLength(4));
      expect(loader.hasMore, isFalse);
    });
  });

  group('Màn hình Trang chủ › Tin tức nổi bật', () {
    Widget app(NewsApi api, {ValueChanged<NewsItem>? onSelected}) =>
        MaterialApp(
          home: Scaffold(
            body: AllNewsContent(api: api, onSelected: onSelected),
          ),
        );

    testWidgets(
      'Breadcrumb và đợt đầu 10 tin từ 4 chuyên mục, không gọi API chi tiết',
      (tester) async {
        final server = _FakeServer(_data(count: 40, dense219: false));
        await tester.pumpWidget(app(server.api));
        await _settle(tester);
        expect(find.text('Trang chủ'), findsOneWidget);
        expect(find.text('Tin tức nổi bật'), findsOneWidget);
        final items = _state(tester).items;
        expect(items, hasLength(10));
        expect(items.map((i) => i.catUid).toSet(), {219, 220, 221, 222});
        expect(server.detailRequests, isEmpty);
        expect(_state(tester).hasMore, isTrue);
      },
    );

    testWidgets(
      'Cuộn gần cuối: đợt sau nối thêm, không đổi thứ tự tin đã hiện, không trùng',
      (tester) async {
        final server = _FakeServer(_data(count: 12));
        await tester.pumpWidget(app(server.api));
        await _settle(tester);
        final first = [for (final i in _state(tester).items) i.uid];
        expect(first, hasLength(10));
        await _scrollToEnd(tester);
        final second = [for (final i in _state(tester).items) i.uid];
        expect(second, hasLength(20));
        expect(second.take(10), first); // tin đã hiện giữ nguyên vị trí
        for (var i = 0; i < 6 && _state(tester).hasMore; i++) {
          await _scrollToEnd(tester);
        }
        final all = [for (final i in _state(tester).items) i.uid];
        expect(all, server.globalOrder());
        expect(_state(tester).hasMore, isFalse);
        final requests = server.requests.length;
        await _scrollToEnd(tester); // đợt cuối nối thêm tin: cuộn tới dòng cuối
        expect(find.text('Đã hiển thị hết tin.'), findsOneWidget);
        expect(server.requests, hasLength(requests)); // hết tin: không gọi thêm
      },
    );

    testWidgets('Cuộn liên tục khi đang tải: không gửi request trùng', (
      tester,
    ) async {
      final server = _FakeServer(_data(count: 30));
      await tester.pumpWidget(app(server.api));
      await _settle(tester);
      // Đợt 2 cần tải thêm mục 219 (offset 5 hoặc 10): giữ request đó lại.
      final next219 = server.offsetsOf(219).last + 5;
      server.gates[(219, next219)] = Completer<void>();
      for (var i = 0; i < 5; i++) {
        await _scrollToEnd(tester);
      }
      expect(
        server.requests.where((r) => r.cat == 219 && r.offset == next219),
        hasLength(1),
      );
      expect(_state(tester).loading, isTrue);
      server.gates[(219, next219)]!.complete();
      await _settle(tester);
      expect(_state(tester).items, hasLength(20));
    });

    testWidgets(
      'Đợt sau lỗi (kể cả lỗi TLS): giữ tin cũ, dừng vòng xoay, Thử lại tải tiếp',
      (tester) async {
        final server = _FakeServer(_data(count: 30));
        await tester.pumpWidget(app(server.api));
        await _settle(tester);
        final next219 = server.offsetsOf(219).last + 5;
        server.throws.add((219, next219));
        await _scrollToEnd(tester);
        expect(
          _state(tester).error,
          'Không thể tải tin tức. Vui lòng thử lại.',
        );
        expect(_state(tester).loading, isFalse);
        expect(_state(tester).items.length, greaterThanOrEqualTo(10));
        final requests = server.requests.length;
        // Tin lấy được trước khi lỗi đã nối thêm: cuộn tới dòng cuối để thấy lỗi.
        await _scrollToEnd(tester);
        expect(server.requests, hasLength(requests)); // lỗi: không tự gọi lại
        expect(find.text('Thử lại'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);

        server.failures.add((219, next219)); // lần 2: lỗi 500 (ApiException)
        await tester.tap(find.text('Thử lại'));
        await _settle(tester);
        expect(_state(tester).error, isNotNull);
        await _scrollToEnd(tester);

        await tester.tap(find.text('Thử lại'));
        await _settle(tester);
        expect(_state(tester).error, isNull);
        final uids = [for (final i in _state(tester).items) i.uid];
        expect(uids, server.globalOrder().take(uids.length));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Rời màn hình khi đang tải: không lỗi setState sau dispose', (
      tester,
    ) async {
      final server = _FakeServer(_data(count: 5))
        ..gates[(219, 0)] = Completer<void>();
      await tester.pumpWidget(app(server.api));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      server.gates[(219, 0)]!.complete();
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Chạm thẻ gọi onSelected đúng tin; chưa có tin thì báo rỗng', (
      tester,
    ) async {
      final server = _FakeServer(_data(count: 3, dense219: false));
      NewsItem? selected;
      await tester.pumpWidget(
        app(server.api, onSelected: (item) => selected = item),
      );
      await _settle(tester);
      final card = find.byType(NewsPreviewCard).first;
      final uid = tester.widget<NewsPreviewCard>(card).item.uid;
      await tester.tap(card);
      expect(selected?.uid, uid);

      final empty = _FakeServer({});
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(empty.api));
      await _settle(tester);
      expect(find.text('Hiện chưa có tin tức.'), findsOneWidget);
    });
  });

  group('Thẻ xem trước bài báo', () {
    Future<void> pumpCard(
      WidgetTester tester,
      NewsItem item, {
      double width = 400,
    }) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: NewsPreviewCard(item: item)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String shownIntro(WidgetTester tester) => tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.style == NewsPreviewCard.introStyle)
        .map((t) => t.data)
        .join(' ');

    final longDesc = List.filled(30, 'Đoạn giới thiệu bài viết').join(' ');

    testWidgets(
      'Có ảnh: chuyên mục, tiêu đề, ảnh, SDG; giới thiệu bên phải ảnh rồi nối xuống dưới, đủ chữ',
      (tester) async {
        final item = NewsItem.fromJson(
          _item(
            1,
            220,
            DateTime(2026, 10, 16),
            desc: longDesc,
            thumb: 'https://ueh.edu.vn/anh.png',
            sdgs: [4, 17],
          ),
        );
        await pumpCard(tester, item);
        expect(find.text('KHOA HỌC - GÓC NHÌN CHUYÊN GIA'), findsOneWidget);
        expect(find.text('Tin 1'), findsOneWidget);
        expect(find.byType(NewsImage), findsOneWidget);
        expect(find.byType(SdgIcons), findsOneWidget);
        final intros = tester
            .widgetList<Text>(find.byType(Text))
            .where((t) => t.style == NewsPreviewCard.introStyle)
            .toList();
        expect(intros, hasLength(2)); // phần bên phải ảnh + phần nối xuống dưới
        expect(shownIntro(tester), longDesc); // không mất, không lặp chữ
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Không có ảnh: SDG và giới thiệu chiếm cả chiều rộng', (
      tester,
    ) async {
      final item = NewsItem.fromJson(
        _item(2, 219, DateTime(2026, 10, 16), desc: 'Mô tả ngắn'),
      );
      await pumpCard(tester, item);
      expect(find.byType(NewsImage), findsNothing);
      expect(find.text('Mô tả ngắn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Màn hình hẹp, tiêu đề và mô tả rất dài: không tràn layout', (
      tester,
    ) async {
      final item = NewsItem.fromJson({
        ..._item(
          3,
          221,
          DateTime(2026, 10, 16),
          desc: longDesc,
          thumb: 'https://ueh.edu.vn/anh.png',
          sdgs: [1, 2, 3],
        ),
        'title': List.filled(20, 'Tiêu đề rất dài').join(' '),
      });
      await pumpCard(tester, item, width: 280);
      expect(tester.takeException(), isNull);
      expect(shownIntro(tester), longDesc);
    });
  });

  testWidgets(
    'Trang chủ: nút Xem thêm chỉ hiện khi có onMore và gọi đúng callback',
    (tester) async {
      final api = NewsApi(
        client: MockClient(
          (request) async => http.Response.bytes(
            utf8.encode(
              request.url.path == '/api/news/featured'
                  ? jsonEncode([
                      for (var i = 0; i < 5; i++)
                        _item(90 + i, 219 + (i % 4), DateTime(2026, 10, 1)),
                    ])
                  : '{"total":0,"limit":5,"offset":0,"items":[]}',
            ),
            200,
          ),
        ),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeaturedNewsContent(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Xem thêm'), findsNothing);

      var more = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeaturedNewsContent(api: api, onMore: () => more++),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FeaturedNewsCard), findsOneWidget);
      expect(find.byType(NewsTile), findsNWidgets(4));
      await tester.ensureVisible(find.text('Xem thêm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem thêm'));
      expect(more, 1);
    },
  );
}
