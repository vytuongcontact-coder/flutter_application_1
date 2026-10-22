import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/news.dart';
import '../services/news_api.dart';
import '../services/student_api.dart' show ApiException;
import 'app_top_bar.dart';
import 'featured_news.dart' show SdgIcons, formatNewsDate;
import 'news_preview.dart' show NewsBreadcrumb;

const _bodyStyle = TextStyle(fontSize: 17, height: 1.5, color: Colors.black87);

/// Trang chi tiết: GET /api/news/{uid}, nội dung HTML hiển thị bằng widget
/// Flutter (không dùng WebView).
class NewsDetailContent extends StatefulWidget {
  const NewsDetailContent({
    super.key,
    required this.api,
    required this.item,
    this.onHome,
  });

  final NewsApi api;

  /// Tin được chọn ở danh sách; chỉ dùng [NewsItem.uid] để gọi API.
  final NewsItem item;

  /// Chạm "Trang chủ" ở breadcrumb.
  final VoidCallback? onHome;

  @override
  State<NewsDetailContent> createState() => _NewsDetailContentState();
}

class _NewsDetailContentState extends State<NewsDetailContent> {
  late Future<NewsDetail> _detail;

  @override
  void initState() {
    super.initState();
    _detail = widget.api.detail(widget.item.uid);
  }

  @override
  void didUpdateWidget(NewsDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Đổi bài: Future mới; FutureBuilder bỏ kết quả của bài cũ.
    if (oldWidget.item.uid != widget.item.uid) {
      _detail = widget.api.detail(widget.item.uid);
    }
  }

  void _retry() {
    final future = widget.api.detail(widget.item.uid);
    // FutureBuilder chỉ lắng nghe ở lần build sau; nếu request lỗi trước đó,
    // Dart coi là lỗi chưa xử lý. ignore() đánh dấu đã xử lý, FutureBuilder
    // vẫn nhận lỗi để hiện "Thử lại".
    future.ignore();
    setState(() {
      _detail = future;
    });
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white,
    child: FutureBuilder<NewsDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          // Cả ApiException lẫn lỗi bất ngờ (ví dụ HandshakeException) đều về đây.
          final error = snapshot.error;
          return _Retry(
            text: error is ApiException
                ? error.message
                : 'Không thể tải tin tức. Vui lòng thử lại.',
            onRetry: _retry,
          );
        }
        final detail = snapshot.data!;
        final item = detail.item;
        final date = item.postDate;
        final blocks = buildHtmlBlocks(detail.content);
        return ListView(
          key: PageStorageKey('ueh-news-detail-${item.uid}'),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
          children: [
            // "Trang chủ › chuyên mục" theo category_name của API chi tiết;
            // đã có tên chuyên mục ở đây nên không lặp lại dòng in hoa.
            NewsBreadcrumb(current: item.categoryName, onHome: widget.onHome),
            Text(
              item.title,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 23,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            if (date != null) ...[
              const SizedBox(height: 8),
              Text(
                formatNewsDate(date),
                style: const TextStyle(color: Color(0xFF808080), fontSize: 14),
              ),
            ],
            if (item.sdgs.isNotEmpty) ...[
              const SizedBox(height: 12),
              SdgIcons(item.sdgs),
            ],
            const Divider(height: 32),
            if (blocks.isEmpty)
              const Text(
                'Bài viết chưa có nội dung.',
                style: TextStyle(color: Color(0xFF808080)),
              ),
            for (final block in blocks)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: block),
          ],
        );
      },
    ),
  );
}

/// Chuyển nội dung HTML của bài viết thành danh sách widget khối (đoạn văn,
/// tiêu đề, danh sách, ảnh...). HTML rỗng trả về danh sách rỗng.
///
/// Chỉ hỗ trợ các thẻ có trong dữ liệu UEH: p, div, br, strong/b, em/i, u,
/// h1-h6, ul/ol/li, a, img, span, figure/figcaption, table/tr/td, hr.
/// script, style, iframe, video... bị bỏ qua.
List<Widget> buildHtmlBlocks(String html) {
  try {
    final builder = _HtmlBlockBuilder();
    builder.visitAll(html_parser.parseFragment(html).nodes, _bodyStyle);
    builder.flush();
    return builder.blocks;
  } catch (_) {
    // Không để HTML lạ làm hỏng trang: hiển thị chữ thuần.
    final text = html.replaceAll(RegExp(r'<[^>]*>'), ' ').trim();
    return text.isEmpty ? const [] : [Text(text, style: _bodyStyle)];
  }
}

/// Duyệt cây HTML: chữ và thẻ inline gom thành [TextSpan] của đoạn hiện tại;
/// gặp thẻ khối thì kết thúc đoạn (flush) và thêm widget khối.
class _HtmlBlockBuilder {
  final blocks = <Widget>[];
  final _spans = <InlineSpan>[];
  bool _hasText = false;
  bool _endsWithSpace = true;
  TextAlign _align = TextAlign.start;

  static const _skipped = {
    'script', 'style', 'iframe', 'video', 'audio', 'object', 'embed', //
    'noscript', 'svg', 'canvas', 'form', 'input', 'button', 'select',
    'textarea', 'head', 'title', 'meta', 'link',
  };
  static const _blocks = {
    'p',
    'div',
    'section',
    'article',
    'header',
    'footer',
    'main',
    'center',
    'blockquote',
    'figure',
    'figcaption',
    'table',
    'tbody',
    'thead',
    'tfoot',
    'li',
    'dl',
    'dt',
    'dd',
    'pre',
    'address',
  };
  static const _headingSizes = {
    'h1': 22.0,
    'h2': 21.0,
    'h3': 20.0,
    'h4': 19.0,
    'h5': 18.0,
    'h6': 17.0,
  };

  /// Kết thúc đoạn hiện tại thành một [Text.rich] (bỏ đoạn chỉ có khoảng trắng).
  void flush() {
    if (_hasText) {
      blocks.add(
        Text.rich(TextSpan(children: List.of(_spans)), textAlign: _align),
      );
    }
    _spans.clear();
    _hasText = false;
    _endsWithSpace = true;
  }

  void visitAll(List<dom.Node> nodes, TextStyle style) {
    for (final node in nodes) {
      _visit(node, style);
    }
  }

  void _visit(dom.Node node, TextStyle style) {
    if (node is dom.Text) return _addText(node.text, style);
    if (node is! dom.Element) return; // bỏ comment
    final tag = node.localName ?? '';
    if (_skipped.contains(tag)) return;
    final css = _Css.parse(node.attributes['style']);
    final inline = css.apply(style);

    switch (tag) {
      case 'br':
        _spans.add(const TextSpan(text: '\n'));
        _endsWithSpace = true;
      case 'strong' || 'b':
        visitAll(node.nodes, inline.copyWith(fontWeight: FontWeight.w700));
      case 'em' || 'i':
        visitAll(node.nodes, inline.copyWith(fontStyle: FontStyle.italic));
      case 'u':
        visitAll(node.nodes, _underline(inline));
      case 'a':
        // Hiển thị chữ của liên kết (màu xanh, gạch chân); không mở trình duyệt.
        visitAll(
          node.nodes,
          _underline(inline.copyWith(color: AppTopBar.uehBlue)),
        );
      case 'img':
        _addImage(node);
      case 'hr':
        flush();
        blocks.add(const Divider());
      case 'ul' || 'ol':
        flush();
        blocks.add(_list(node, ordered: tag == 'ol', style: style));
      case 'tr':
        _block(css, () {
          var first = true;
          for (final cell in node.children) {
            if (!first) _addText(' | ', style);
            first = false;
            final cellCss = _Css.parse(cell.attributes['style']);
            visitAll(cell.nodes, cellCss.apply(style));
          }
        });
      case _ when _headingSizes.containsKey(tag):
        _block(css, () {
          visitAll(
            node.nodes,
            inline.copyWith(
              fontSize: _headingSizes[tag],
              fontWeight: FontWeight.w700,
              color: Colors.black,
              height: 1.35,
            ),
          );
        });
      case 'figcaption':
        _block(css, () {
          visitAll(
            node.nodes,
            inline.copyWith(fontSize: 14, fontStyle: FontStyle.italic),
          );
        });
      case _ when _blocks.contains(tag):
        _block(css, () => visitAll(node.nodes, inline));
      default:
        // span, font, sup, sub, small, thẻ lạ: giữ chữ, áp dụng style cơ bản.
        visitAll(node.nodes, inline);
    }
  }

  // Thẻ khối: kết thúc đoạn trước, đọc text-align, dựng nội dung rồi kết thúc.
  void _block(_Css css, void Function() visitChildren) {
    flush();
    final previous = _align;
    _align = css.align ?? _align;
    visitChildren();
    flush();
    _align = previous;
  }

  void _addText(String text, TextStyle style) {
    // Gộp khoảng trắng như trình duyệt; giữ nguyên &nbsp; ( ).
    var value = text.replaceAll(RegExp('[ \t\n\r\f]+'), ' ');
    if (_endsWithSpace && value.startsWith(' ')) value = value.substring(1);
    if (value.isEmpty) return;
    _spans.add(TextSpan(text: value, style: style));
    _endsWithSpace = value.endsWith(' ');
    if (value.trim().isNotEmpty) _hasText = true;
  }

  void _addImage(dom.Element node) {
    // Chỉ nhận URL tuyệt đối http/https (sửa URL bị ghép lặp domain như ảnh
    // của danh sách). Không có src hoặc src tương đối thì bỏ qua.
    final url = NewsItem.imageUrl(node.attributes['src']);
    if (url == null) return;
    final align = _align;
    flush();
    blocks.add(NewsHtmlImage(url: url, alt: node.attributes['alt']));
    _align = align;
  }

  Widget _list(
    dom.Element node, {
    required bool ordered,
    required TextStyle style,
  }) {
    final items = <Widget>[];
    var number = 0;
    for (final child in node.children) {
      final sub = _HtmlBlockBuilder();
      if (child.localName == 'li') {
        sub.visitAll(child.nodes, style);
      } else {
        sub._visit(child, style);
      }
      sub.flush();
      if (sub.blocks.isEmpty) continue;
      number++;
      items.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(ordered ? '$number.' : '•', style: style),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in sub.blocks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: block,
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items,
    );
  }

  static TextStyle _underline(TextStyle style) =>
      style.copyWith(decoration: TextDecoration.underline);
}

/// Vài thuộc tính CSS inline có trong dữ liệu UEH: text-align, font-weight,
/// font-style, text-decoration. Các thuộc tính khác bị bỏ qua.
class _Css {
  const _Css({this.align, this.weight, this.italic, this.underline = false});

  final TextAlign? align;
  final FontWeight? weight;
  final bool? italic;
  final bool underline;

  static _Css parse(String? style) {
    if (style == null || style.trim().isEmpty) return const _Css();
    TextAlign? align;
    FontWeight? weight;
    bool? italic;
    var underline = false;
    for (final declaration in style.split(';')) {
      final parts = declaration.split(':');
      if (parts.length != 2) continue;
      final name = parts[0].trim().toLowerCase();
      final value = parts[1].trim().toLowerCase();
      switch (name) {
        case 'text-align':
          align = switch (value) {
            'center' => TextAlign.center,
            'right' => TextAlign.right,
            'justify' => TextAlign.justify,
            'left' => TextAlign.left,
            _ => null,
          };
        case 'font-weight':
          final number = int.tryParse(value);
          if (value == 'bold' || (number != null && number >= 600)) {
            weight = FontWeight.w700;
          } else if (value == 'normal' || (number != null && number < 600)) {
            weight = FontWeight.w400;
          }
        case 'font-style':
          italic = value == 'italic';
        case 'text-decoration' || 'text-decoration-line':
          underline = value.contains('underline');
      }
    }
    return _Css(
      align: align,
      weight: weight,
      italic: italic,
      underline: underline,
    );
  }

  TextStyle apply(TextStyle style) {
    var result = style;
    if (weight != null) result = result.copyWith(fontWeight: weight);
    if (italic != null) {
      result = result.copyWith(
        fontStyle: italic! ? FontStyle.italic : FontStyle.normal,
      );
    }
    if (underline) {
      result = result.copyWith(decoration: TextDecoration.underline);
    }
    return result;
  }
}

/// Ảnh trong bài: rộng bằng nội dung, giữ tỉ lệ; tải lỗi thì hiện khung thay thế.
class NewsHtmlImage extends StatelessWidget {
  const NewsHtmlImage({super.key, required this.url, this.alt});

  final Uri url;
  final String? alt;

  @override
  Widget build(BuildContext context) => Image.network(
    url.toString(),
    width: double.infinity,
    fit: BoxFit.fitWidth,
    // Giới hạn kích thước giải mã: ảnh bài viết có thể rất lớn.
    cacheWidth: 1080,
    semanticLabel: alt,
    errorBuilder: (_, error, stackTrace) => Container(
      height: 120,
      color: const Color(0xFFE1EFF0),
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, color: AppTopBar.uehBlue),
    ),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off, color: AppTopBar.uehBlue, size: 32),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    ),
  );
}
