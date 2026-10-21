import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_application_1/models/news.dart';
import 'package:flutter_application_1/services/news_api.dart';
import 'package:flutter_application_1/widgets/app_top_bar.dart';
import 'package:flutter_application_1/widgets/news_detail.dart';

import 'news_fixtures.dart';

Future<void> _pumpHtml(WidgetTester tester, String html) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ListView(children: buildHtmlBlocks(html))),
    ),
  );
  await tester.pumpAndSettle();
}

/// Chữ của từng đoạn (RichText) theo thứ tự trên màn hình, bỏ RichText của Icon.
List<String> _texts(WidgetTester tester) {
  final icons = tester
      .widgetList<RichText>(
        find.descendant(of: find.byType(Icon), matching: find.byType(RichText)),
      )
      .toSet();
  return [
    for (final rich in tester.widgetList<RichText>(find.byType(RichText)))
      if (!icons.contains(rich)) rich.text.toPlainText(),
  ];
}

/// Style của đoạn chữ [text] (mỗi TextSpan mang style đầy đủ).
TextStyle? _styleOf(WidgetTester tester, String text) {
  TextStyle? found;
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text == text) {
        found = span.style;
        return false;
      }
      return true;
    });
  }
  return found;
}

Map<String, Object?> _detail(int uid, String content) => {
  'uid': uid,
  'cat_uid': 220,
  'category_name': 'Khoa học - Góc nhìn chuyên gia',
  'title': 'Bài $uid',
  'short_desc': '',
  'post_date': '2026-10-12T10:00:00',
  'sdgs': [4, 13],
  'is_featured': false,
  'background_img': null,
  'thumbnail_img': null,
  'content': content,
};

NewsItem _listItem(int uid) => NewsItem(
  uid: uid,
  catUid: 220,
  categoryName: 'Khoa học - Góc nhìn chuyên gia',
  title: 'Tin $uid ở danh sách',
);

Widget _detailApp(NewsApi api, int uid) => MaterialApp(
  home: Scaffold(
    body: NewsDetailContent(api: api, item: _listItem(uid)),
  ),
);

void main() {
  group('Chuyển HTML thành widget Flutter', () {
    testWidgets(
      'Đoạn văn, đậm, nghiêng, gạch chân, tiêu đề phụ, liên kết, br, span đúng thứ tự',
      (tester) async {
        await _pumpHtml(
          tester,
          '<h4>Tiêu đề phụ</h4>'
          '<p>Mở đầu <strong>đậm</strong>, <em>nghiêng</em>, <u>gạch</u> và '
          '<a href="https://ueh.edu.vn">liên kết</a>.<br>Dòng hai</p>'
          '<div><span style="font-weight: 700;">span đậm</span> '
          '<b><span style="font-weight: 400;">không đậm</span></b> <i>nghiêng 2</i></div>',
        );
        expect(_texts(tester), [
          'Tiêu đề phụ',
          'Mở đầu đậm, nghiêng, gạch và liên kết.\nDòng hai',
          'span đậm không đậm nghiêng 2',
        ]);
        expect(_styleOf(tester, 'Tiêu đề phụ')?.fontWeight, FontWeight.w700);
        expect(_styleOf(tester, 'Tiêu đề phụ')?.fontSize, 19);
        expect(_styleOf(tester, 'đậm')?.fontWeight, FontWeight.w700);
        expect(_styleOf(tester, 'nghiêng')?.fontStyle, FontStyle.italic);
        expect(_styleOf(tester, 'gạch')?.decoration, TextDecoration.underline);
        expect(_styleOf(tester, 'liên kết')?.color, AppTopBar.uehBlue);
        expect(
          _styleOf(tester, 'liên kết')?.decoration,
          TextDecoration.underline,
        );
        expect(_styleOf(tester, 'span đậm')?.fontWeight, FontWeight.w700);
        expect(_styleOf(tester, 'không đậm')?.fontWeight, FontWeight.w400);
        expect(_styleOf(tester, 'nghiêng 2')?.fontStyle, FontStyle.italic);
      },
    );

    testWidgets('Danh sách ul/ol/li giữ thứ tự, có dấu chấm và số thứ tự', (
      tester,
    ) async {
      await _pumpHtml(
        tester,
        '<ul><li>Một</li><li>Hai <b>đậm</b></li></ul>'
        '<ol><li>A</li><li><p>B</p></li><li>C</li></ol>',
      );
      expect(_texts(tester), [
        '•', 'Một', '•', 'Hai đậm', //
        '1.', 'A', '2.', 'B', '3.', 'C',
      ]);
    });

    testWidgets(
      'Ảnh hợp lệ hiển thị; ảnh thiếu src hoặc src tương đối bị bỏ; ảnh lỗi có khung thay thế',
      (tester) async {
        const html =
            '<p>Trước<img src="https://ueh.edu.vn/a.jpg" alt="Ảnh A">Sau</p>'
            '<img src="/tuong-doi.png"><img>'
            '<img src="https://api.ngoisaoviet.infohttps://dsa.ueh.edu.vn/b.webp">'
            '<figure><img src="https://ueh.edu.vn/c.png"><figcaption>Chú thích</figcaption></figure>';
        final images = buildHtmlBlocks(html).whereType<NewsHtmlImage>();
        expect(images.map((image) => image.url.toString()), [
          'https://ueh.edu.vn/a.jpg',
          'https://dsa.ueh.edu.vn/b.webp', // sửa URL bị ghép lặp domain
          'https://ueh.edu.vn/c.png',
        ]);
        await _pumpHtml(tester, html);
        expect(_texts(tester), ['Trước', 'Sau', 'Chú thích']);
        // Widget test không có mạng: cả 3 ảnh tải lỗi và hiện khung thay thế.
        expect(find.byIcon(Icons.broken_image_outlined), findsNWidgets(3));
        expect(_styleOf(tester, 'Chú thích')?.fontStyle, FontStyle.italic);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Bảng: mỗi hàng một dòng, ô cách nhau bằng |', (tester) async {
      await _pumpHtml(
        tester,
        '<table><tbody><tr><td><b>Thời hạn</b></td><td>Doanh nghiệp</td></tr>'
        '<tr><td>05/10/2026</td><td><a href="https://x.vn">ABC</a></td></tr>'
        '</tbody></table>',
      );
      expect(_texts(tester), ['Thời hạn | Doanh nghiệp', '05/10/2026 | ABC']);
    });

    testWidgets('Bỏ qua script, style, iframe', (tester) async {
      await _pumpHtml(
        tester,
        '<p>Hiện</p><script>alert(1)</script><style>p{color:red}</style>'
        '<iframe src="https://x.vn">khung</iframe><p>Cuối</p>',
      );
      expect(_texts(tester), ['Hiện', 'Cuối']);
    });

    testWidgets('HTML rỗng hoặc sai định dạng không gây lỗi', (tester) async {
      for (final html in ['', '   ', '<p></p><br><span> </span>']) {
        expect(buildHtmlBlocks(html), isEmpty, reason: html);
      }
      await _pumpHtml(tester, '<p><b>chưa đóng <i>thẻ</p><div><<>>');
      expect(_texts(tester).join(' '), contains('chưa đóng thẻ'));
      expect(tester.takeException(), isNull);
    });
  });

  group('Trang chi tiết tin tức', () {
    testWidgets(
      'JSON thật uid 304: gọi đúng API, tiêu đề, chuyên mục, ngày, SDG và nội dung HTML',
      (tester) async {
        final requests = <http.Request>[];
        final api = NewsApi(
          client: MockClient((request) async {
            requests.add(request);
            return http.Response.bytes(utf8.encode(detail304Json), 200);
          }),
        );
        addTearDown(api.close);
        await tester.pumpWidget(_detailApp(api, 304));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.pumpAndSettle();

        expect(requests.single.url.path, '/api/news/304');
        expect(requests.single.headers.containsKey('Authorization'), isFalse);
        final detail = NewsDetail.fromJson(jsonDecode(detail304Json));
        expect(find.text(detail.item.title), findsOneWidget); // tiêu đề từ API
        expect(find.text('Tin 304 ở danh sách'), findsNothing);
        expect(find.text('TUYỂN SINH & HƯỚNG NGHIỆP'), findsOneWidget);
        expect(find.text('01/04/2026'), findsOneWidget);
        final sdgAssets = tester
            .widgetList<Image>(find.byType(Image))
            .map((image) => image.image)
            .whereType<AssetImage>()
            .map((asset) => asset.assetName);
        expect(sdgAssets, [
          'assets/images/sdg-4.png',
          'assets/images/sdg-11.png',
        ]);

        // Nội dung HTML thật: có tiêu đề phụ h4, đoạn văn, danh sách; ảnh tuyệt đối.
        final blocks = buildHtmlBlocks(detail.content);
        expect(blocks.length, greaterThan(10));
        expect(blocks.whereType<NewsHtmlImage>(), isNotEmpty);
        expect(find.byType(NewsHtmlImage), findsWidgets);
        await tester.scrollUntilVisible(
          find.textContaining('0000 000 001', findRichText: true),
          500,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'API lỗi: thông báo và Thử lại; lỗi ngoài ApiException không quay mãi',
      (tester) async {
        var calls = 0;
        final api = NewsApi(
          client: MockClient((request) async {
            calls++;
            if (calls == 1) {
              return http.Response.bytes(
                utf8.encode('{"message":"Không tìm thấy tin tức."}'),
                404,
              );
            }
            if (calls == 2) throw const HandshakeException('Lỗi TLS giả lập');
            return http.Response.bytes(
              utf8.encode(jsonEncode(_detail(7, '<p>Đã tải</p>'))),
              200,
            );
          }),
        );
        addTearDown(api.close);
        await tester.pumpWidget(_detailApp(api, 7));
        await tester.pumpAndSettle();
        expect(find.text('Không tìm thấy tin tức.'), findsOneWidget);

        await tester.tap(find.text('Thử lại'));
        await tester.pumpAndSettle();
        expect(
          find.text('Không thể tải tin tức. Vui lòng thử lại.'),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);

        await tester.tap(find.text('Thử lại'));
        await tester.pumpAndSettle();
        expect(find.text('Đã tải'), findsOneWidget);
        expect(calls, 3);
      },
    );

    testWidgets('Nội dung rỗng: thông báo bài viết chưa có nội dung', (
      tester,
    ) async {
      final api = NewsApi(
        client: MockClient(
          (_) async => http.Response.bytes(
            utf8.encode(jsonEncode(_detail(8, '  '))),
            200,
          ),
        ),
      );
      addTearDown(api.close);
      await tester.pumpWidget(_detailApp(api, 8));
      await tester.pumpAndSettle();
      expect(find.text('Bài 8'), findsOneWidget);
      expect(find.text('Bài viết chưa có nội dung.'), findsOneWidget);
    });

    testWidgets('Đổi bài khi request cũ chưa xong: không lẫn nội dung', (
      tester,
    ) async {
      final gateA = Completer<void>();
      final api = NewsApi(
        client: MockClient((request) async {
          final uid = int.parse(request.url.pathSegments.last);
          if (uid == 1) await gateA.future;
          return http.Response.bytes(
            utf8.encode(jsonEncode(_detail(uid, '<p>Nội dung $uid</p>'))),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(_detailApp(api, 1)); // bài A đang tải
      await tester.pump();
      await tester.pumpWidget(_detailApp(api, 2)); // chuyển sang bài B
      await tester.pumpAndSettle();
      expect(find.text('Nội dung 2'), findsOneWidget);

      gateA.complete(); // bài A xong muộn
      await tester.pumpAndSettle();
      expect(find.text('Nội dung 2'), findsOneWidget);
      expect(find.text('Nội dung 1'), findsNothing);
    });

    testWidgets('Rời trang khi bài đang tải: không lỗi setState sau dispose', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = NewsApi(
        client: MockClient((request) async {
          await gate.future;
          return http.Response.bytes(
            utf8.encode(jsonEncode(_detail(9, '<p>x</p>'))),
            200,
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(_detailApp(api, 9));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
