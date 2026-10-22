import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/news.dart';
import 'package:flutter_application_1/widgets/featured_news.dart';
import 'package:flutter_application_1/widgets/news_preview.dart';

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

void main() {
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
      'Có ảnh: tiêu đề, ảnh, SDG, không lặp tên chuyên mục; giới thiệu bên phải ảnh rồi nối xuống dưới, đủ chữ',
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
        // Breadcrumb của danh sách đã ghi tên chuyên mục: thẻ không lặp lại.
        expect(find.text('KHOA HỌC - GÓC NHÌN CHUYÊN GIA'), findsNothing);
        expect(find.text('Khoa học - Góc nhìn chuyên gia'), findsNothing);
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

    testWidgets('Chạm thẻ gọi onTap; không truyền onTap thì không nhận chạm', (
      tester,
    ) async {
      final item = NewsItem.fromJson(
        _item(4, 222, DateTime(2026, 10, 16), desc: 'Mô tả'),
      );
      await pumpCard(tester, item);
      expect(find.byType(InkWell), findsNothing);

      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NewsPreviewCard(item: item, onTap: () => taps++),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Tin 4'));
      expect(taps, 1);
    });
  });

}
