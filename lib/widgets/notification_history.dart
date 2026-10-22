import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../services/notification_store.dart';
import 'app_top_bar.dart';
import 'featured_news.dart' show formatNewsDate;

/// Thời điểm nhận theo giờ máy, dạng `HH:mm · dd/mm/yyyy`.
String formatReceivedAt(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)} · ${formatNewsDate(local)}';
}

/// Tab Thông báo: lịch sử Firebase Cloud Messaging đọc từ SQLite (bảng
/// `notifications`), mới nhất trước. Không gọi mạng nên xem được khi offline.
///
/// Đọc lại khi [history] báo có thay đổi (tin mới khi app đang mở, đánh dấu đã
/// đọc) và khi app trở lại foreground (tin do background handler lưu).
class NotificationHistoryView extends StatefulWidget {
  const NotificationHistoryView({super.key, required this.history});

  final NotificationHistory history;

  @override
  State<NotificationHistoryView> createState() =>
      _NotificationHistoryViewState();
}

class _NotificationHistoryViewState extends State<NotificationHistoryView>
    with WidgetsBindingObserver {
  List<AppNotification>? _items;
  bool _failed = false;
  // Tăng mỗi lần đọc: bỏ kết quả của lần đọc cũ về muộn hơn lần đọc mới.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.history.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(NotificationHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.history != widget.history) {
      oldWidget.history.removeListener(_reload);
      widget.history.addListener(_reload);
      _reload();
    }
  }

  @override
  void dispose() {
    widget.history.removeListener(_reload);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  /// Đọc lại lịch sử; danh sách đang hiện được giữ trong lúc đọc.
  Future<void> _reload() async {
    final generation = ++_generation;
    try {
      final items = await widget.history.read();
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = items;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _reload();
  }

  // Chạm một thông báo: đánh dấu đã đọc (lưu SQLite) rồi xem đầy đủ nội dung.
  Future<void> _open(AppNotification item) async {
    if (!item.isRead) {
      try {
        await widget.history.markRead(item.messageId);
      } catch (_) {
        /* Không lưu được trạng thái đã đọc: vẫn cho xem nội dung. */
      }
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title.isEmpty ? 'Thông báo' : item.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.body.isNotEmpty) Text(item.body),
              const SizedBox(height: 12),
              Text(
                formatReceivedAt(item.receivedAt),
                style: const TextStyle(color: Color(0xFF808080)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final Widget child;
    if (_failed) {
      child = _Message(
        icon: Icons.error_outline,
        text: 'Không đọc được lịch sử thông báo.',
        onRetry: _retry,
      );
    } else if (items == null) {
      child = const Center(child: CircularProgressIndicator());
    } else if (items.isEmpty) {
      // Vẫn kéo xuống để tải lại được khi danh sách rỗng.
      child = RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(Icons.notifications_none, color: AppTopBar.uehBlue, size: 40),
            SizedBox(height: 12),
            Text('Chưa có thông báo.', textAlign: TextAlign.center),
          ],
        ),
      );
    } else {
      child = RefreshIndicator(
        onRefresh: _reload,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => NotificationTile(
            item: items[index],
            onTap: () => _open(items[index]),
          ),
        ),
      );
    }
    return ColoredBox(color: Colors.white, child: child);
  }
}

/// Một dòng lịch sử: tiêu đề, nội dung (tối đa 3 dòng), thời điểm nhận; tin
/// chưa đọc có chấm xanh và tiêu đề đậm.
class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.item, this.onTap});

  final AppNotification item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 12),
            child: Semantics(
              label: item.isRead ? 'Đã đọc' : 'Chưa đọc',
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: item.isRead ? Colors.transparent : AppTopBar.uehBlue,
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title.isEmpty ? 'Thông báo' : item.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w800,
                    color: Colors.black,
                  ),
                ),
                if (item.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: Colors.black87,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  formatReceivedAt(item.receivedAt),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF808080),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    required this.onRetry,
  });

  final IconData icon;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTopBar.uehBlue, size: 32),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    ),
  );
}
