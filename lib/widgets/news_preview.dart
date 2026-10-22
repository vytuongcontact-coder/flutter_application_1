import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/news.dart';
import 'app_top_bar.dart';
import 'featured_news.dart' show NewsImage, SdgIcons;

/// Đường dẫn "Trang chủ › [current]" ở đầu danh sách tin.
class NewsBreadcrumb extends StatelessWidget {
  const NewsBreadcrumb({super.key, required this.current, this.onHome});

  final String current;
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
        Flexible(
          child: Text(
            current,
            style: const TextStyle(color: AppTopBar.uehBlue, fontSize: 18),
          ),
        ),
      ],
    ),
  );
}

/// Thẻ xem trước một bài trong danh sách chuyên mục: tiêu đề (xanh đậm), ảnh
/// bên trái, SDG và đoạn giới thiệu bên phải ảnh; phần giới thiệu còn lại nối
/// xuống dưới. Tên chuyên mục đã có ở breadcrumb nên thẻ không lặp lại.
class NewsPreviewCard extends StatelessWidget {
  const NewsPreviewCard({super.key, required this.item, this.onTap});

  final NewsItem item;
  final VoidCallback? onTap;

  static const introStyle = TextStyle(
    fontSize: 17,
    height: 1.45,
    color: Colors.black87,
  );

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
