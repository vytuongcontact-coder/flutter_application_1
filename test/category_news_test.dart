import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/models/news.dart';
import 'package:flutter_application_1/services/news_api.dart';
import 'package:flutter_application_1/widgets/category_news.dart';
import 'package:flutter_application_1/widgets/news_preview.dart';

/// Server giả cho GET /api/news: mỗi chuyên mục có [total] tin, uid =
/// cat_uid * 1000 + vị trí. Trả đúng lát cắt theo limit/offset như API thật.
class _FakeServer {
  _FakeServer({this.total = 45}) {
    api = NewsApi(
      client: MockClient((request) async {
        final q = request.url.queryParameters;
        final cat = int.parse(q['cat_uid']!);
        final limit = int.parse(q['limit']!);
        final offset = int.parse(q['offset']!);
        requests.add((cat: cat, limit: limit, offset: offset));
        final gate = gates[offset];
        if (gate != null) await gate.future;
        if (failOffsets.remove(offset)) return http.Response('', 500);
        if (throwOffsets.remove(offset)) {
          throw const HandshakeException('Lỗi TLS giả lập');
        }
        final items = [
          for (var i = offset; i < offset + limit && i < total; i++)
            _item(cat * 1000 + i, cat),
        ];
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'total': total,
              'limit': limit,
              'offset': offset,
              'items': edit?.call(offset, items) ?? items,
            }),
          ),
          200,
        );
      }),
    );
    addTearDown(api.close);
  }

  int total;
  late final NewsApi api;
  final requests = <({int cat, int limit, int offset})>[];
  final gates = <int, Completer<void>>{};
  final failOffsets = <int>{};

  /// Offset ném lỗi không phải ApiException (một lần).
  final throwOffsets = <int>{};

  /// Sửa trang trả về (thêm tin trùng, tin lỗi...).
  List<Object?> Function(int offset, List<Object?> items)? edit;

  List<int> get offsets => [for (final r in requests) r.offset];
}

Map<String, Object?> _item(int uid, int cat) => {
  'uid': uid,
  'cat_uid': cat,
  'category_name': 'Mục $cat',
  'title': 'Tin $uid',
  'short_desc': '',
  'post_date': '2026-10-13T08:54:00',
  'sdgs': [4],
  'is_featured': false,
  'background_img': null,
  'thumbnail_img': null,
};

final _life = NewsCategory.all.first; // 219 Cuộc sống UEH

Widget _app(NewsApi api, NewsCategory category) => MaterialApp(
  home: Scaffold(
    body: CategoryNewsContent(api: api, category: category),
  ),
);

// Danh sách có vòng xoay cuối trang khi còn tin nên không dùng pumpAndSettle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

CategoryNewsContentState _state(WidgetTester tester) =>
    tester.state<CategoryNewsContentState>(find.byType(CategoryNewsContent));

// Kéo tới cuối danh sách hiện có (gần cuối thì lazy load chạy).
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -100000));
  await _settle(tester);
}

void main() {
  testWidgets('Mở chuyên mục: chỉ tải 20 tin đầu với offset 0', (tester) async {
    final server = _FakeServer(total: 85);
    await tester.pumpWidget(_app(server.api, _life));
    await _settle(tester);
    expect(server.requests.single, (cat: 219, limit: 20, offset: 0));
    expect(_state(tester).items, hasLength(20));
    expect(_state(tester).hasMore, isTrue);
    expect(find.byType(NewsPreviewCard), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cuộn gần cuối: offset 20, 40 rồi dừng đúng total 45', (
    tester,
  ) async {
    final server = _FakeServer(total: 45);
    await tester.pumpWidget(_app(server.api, _life));
    await _settle(tester);
    await _scrollToEnd(tester);
    expect(server.offsets, [0, 20]);
    expect(_state(tester).items, hasLength(40));
    await _scrollToEnd(tester);
    expect(server.offsets, [0, 20, 40]);
    expect(_state(tester).items, hasLength(45));
    expect(_state(tester).hasMore, isFalse);

    // Hết tin: cuộn thêm không gọi API.
    await _scrollToEnd(tester);
    await _scrollToEnd(tester);
    expect(server.offsets, [0, 20, 40]);
    expect(find.text('Đã hiển thị hết tin của chuyên mục.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('85 tin (như mục 219 thật): offset 0, 20, 40, 60, 80 rồi dừng', (
    tester,
  ) async {
    final server = _FakeServer(total: 85);
    await tester.pumpWidget(_app(server.api, _life));
    await _settle(tester);
    for (var i = 0; i < 8 && _state(tester).hasMore; i++) {
      await _scrollToEnd(tester);
    }
    expect(server.offsets, [0, 20, 40, 60, 80]);
    final uids = [for (final item in _state(tester).items) item.uid];
    expect(uids, hasLength(85));
    expect(uids.toSet(), hasLength(85));
  });

  testWidgets('Cuộn liên tục khi trang đang tải: mỗi offset chỉ một request', (
    tester,
  ) async {
    final server = _FakeServer(total: 85)..gates[20] = Completer<void>();
    await tester.pumpWidget(_app(server.api, _life));
    await _settle(tester);
    for (var i = 0; i < 5; i++) {
      await _scrollToEnd(tester);
    }
    expect(server.offsets, [0, 20]);
    expect(_state(tester).loading, isTrue);

    server.gates[20]!.complete();
    await _settle(tester);
    expect(_state(tester).items, hasLength(40));
    expect(server.offsets, [0, 20]);
  });

  testWidgets('Tin trùng uid giữa các trang chỉ hiện một lần', (tester) async {
    final server = _FakeServer(total: 45)
      // Trang 2 gửi lại 2 tin của trang 1 ở đầu.
      ..edit = (offset, items) => offset == 20
          ? [_item(219000, 219), _item(219001, 219), ...items.skip(2)]
          : items;
    await tester.pumpWidget(_app(server.api, _life));
    await _settle(tester);
    await _scrollToEnd(tester);
    final uids = [for (final item in _state(tester).items) item.uid];
    expect(uids.toSet().length, uids.length);
    expect(uids, hasLength(38));
    expect(_state(tester).nextOffset, 40);
  });

  testWidgets('Tin lỗi bị bỏ qua: offset kế tiếp vẫn theo số tin server gửi', (
    tester,
  ) async {
    final server = _FakeServer(total: 45)
      ..edit = (offset, items) => offset == 0
          ? [
              {'title': 'thiếu uid'},
              ...items.skip(1),
            ]
          : items;
    await tester.pumpWidget(_app(server.api, _life));
    await _settle(tester);
    expect(_state(tester).items, hasLength(19));
    expect(_state(tester).nextOffset, 20);
    await _scrollToEnd(tester);
    expect(server.offsets, [0, 20]);
  });

  testWidgets(
    'Trang sau lỗi: giữ tin đã tải, không tự gọi lại, Thử lại tải được',
    (tester) async {
      final server = _FakeServer(total: 45)..failOffsets.add(20);
      await tester.pumpWidget(_app(server.api, _life));
      await _settle(tester);
      await _scrollToEnd(tester);
      expect(server.offsets, [0, 20]);
      expect(_state(tester).items, hasLength(20));
      expect(_state(tester).error, isNotNull);

      await _scrollToEnd(tester);
      expect(server.offsets, [0, 20]); // lỗi thì không tự lặp request

      await tester.tap(find.text('Thử lại'));
      await _settle(tester);
      expect(server.offsets, [0, 20, 20]);
      expect(_state(tester).items, hasLength(40));
      expect(_state(tester).error, isNull);
    },
  );

  testWidgets(
    'Trang sau ném lỗi ngoài ApiException (HandshakeException): giữ tin cũ, '
    'dừng vòng xoay, Thử lại đúng offset',
    (tester) async {
      final server = _FakeServer(total: 45)..throwOffsets.add(20);
      await tester.pumpWidget(_app(server.api, _life));
      await _settle(tester);
      expect(_state(tester).items, hasLength(20));

      await _scrollToEnd(tester);
      expect(server.offsets, [0, 20]);
      final state = _state(tester);
      expect(state.items, hasLength(20)); // tin cũ vẫn còn
      expect(state.loading, isFalse); // không kẹt
      expect(state.nextOffset, 20); // chưa tăng offset
      expect(state.hasMore, isTrue);
      expect(state.error, 'Không thể tải tin tức. Vui lòng thử lại.');
      // Thẻ tin cao: kéo tiếp tới dòng cuối để dòng lỗi được dựng (đang lỗi
      // nên cuộn không gọi API).
      await _scrollToEnd(tester);
      expect(server.offsets, [0, 20]);
      expect(
        find.text('Không thể tải tin tức. Vui lòng thử lại.'),
        findsOneWidget,
      );
      expect(find.text('Thử lại'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);

      await _scrollToEnd(tester);
      expect(server.offsets, [0, 20]); // lỗi thì không tự gọi lại

      await tester.tap(find.text('Thử lại'));
      await _settle(tester);
      expect(server.offsets, [0, 20, 20]); // tải lại đúng trang lỗi
      final uids = [for (final item in _state(tester).items) item.uid];
      expect(uids, hasLength(40));
      expect(uids.toSet(), hasLength(40));
      expect(_state(tester).error, isNull);
    },
  );

  testWidgets('Lần tải đầu lỗi: thông báo và Thử lại', (tester) async {
    final server = _FakeServer(total: 45)..failOffsets.add(0);
    await tester.pumpWidget(_app(server.api, _life));
    await _settle(tester);
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.byType(NewsPreviewCard), findsNothing);
    await tester.tap(find.text('Thử lại'));
    await _settle(tester);
    expect(_state(tester).items, hasLength(20));
  });

  testWidgets('Chuyên mục rỗng: thông báo, không gọi lại API', (tester) async {
    final server = _FakeServer(total: 0);
    await tester.pumpWidget(_app(server.api, _life));
    await _settle(tester);
    expect(find.text('Chuyên mục chưa có tin.'), findsOneWidget);
    expect(server.offsets, [0]);
  });

  testWidgets('total lớn nhưng items rỗng: dừng, không lặp request vô hạn', (
    tester,
  ) async {
    final server = _FakeServer(total: 100)..edit = (offset, items) => [];
    await tester.pumpWidget(_app(server.api, _life));
    await _settle(tester);
    await _settle(tester);
    expect(server.offsets, [0]);
    expect(_state(tester).hasMore, isFalse);
  });

  testWidgets('Đổi chuyên mục khi request cũ đang chạy: không lẫn dữ liệu', (
    tester,
  ) async {
    final gate219 = Completer<void>();
    final server = _FakeServer(total: 45)..gates[0] = gate219;
    await tester.pumpWidget(_app(server.api, _life)); // 219, đang chờ
    await tester.pump();
    server.gates.remove(0); // request 220 trả ngay
    final science = NewsCategory.all[1]; // 220
    await tester.pumpWidget(_app(server.api, science));
    await _settle(tester);
    expect(_state(tester).items.map((i) => i.catUid).toSet(), {220});

    // Request 219 xong muộn: bị bỏ qua.
    gate219.complete();
    await _settle(tester);
    expect(_state(tester).items.map((i) => i.catUid).toSet(), {220});
    expect(_state(tester).items, hasLength(20));
    expect(server.requests.map((r) => r.cat), [219, 220]);
  });

  testWidgets('Mỗi chuyên mục 219-222 gửi đúng cat_uid', (tester) async {
    final server = _FakeServer(total: 5);
    for (final category in NewsCategory.all) {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(server.api, category));
      await _settle(tester);
      expect(server.requests.last.cat, category.uid);
      expect(_state(tester).items.first.catUid, category.uid);
    }
    expect(server.requests.map((r) => r.cat), [219, 220, 221, 222]);
  });

  testWidgets('Rời màn hình khi đang tải: không setState sau dispose', (
    tester,
  ) async {
    final server = _FakeServer(total: 45)..gates[0] = Completer<void>();
    await tester.pumpWidget(_app(server.api, _life));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    server.gates[0]!.complete();
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });
}
