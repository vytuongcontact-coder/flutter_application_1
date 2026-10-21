import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../controllers/menu_sync_controller.dart';
import '../models/menu_nav.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.menu, required this.onSelected});

  /// Nguồn dữ liệu: cache SQLite và kết quả đồng bộ GET /api/menu.
  final MenuSyncController menu;
  final ValueChanged<MenuNav> onSelected;

  // icon_name từ API → icon Font Awesome. Giữ cả tên cũ của menu mẫu version 1.
  static const _icons = {
    'newspaper': FontAwesomeIcons.newspaper,
    'calendarDays': FontAwesomeIcons.calendarDays,
    'chartLine': FontAwesomeIcons.chartLine,
    'faceSmile': FontAwesomeIcons.faceSmile,
    'calendarWeek': FontAwesomeIcons.calendarWeek,
    'fileLines': FontAwesomeIcons.fileLines,
    'heartPulse': FontAwesomeIcons.heartPulse,
    'leaf': FontAwesomeIcons.leaf,
    'phone': FontAwesomeIcons.phone,
    'coins': FontAwesomeIcons.coins,
    'circleCheck': FontAwesomeIcons.circleCheck,
    'graduationCap': FontAwesomeIcons.graduationCap,
    'idBadge': FontAwesomeIcons.idBadge,
    'filePen': FontAwesomeIcons.filePen,
    'headset': FontAwesomeIcons.headset,
    'clipboardCheck': FontAwesomeIcons.clipboardCheck,
  };

  /// Icon chưa hỗ trợ thì dùng dấu hỏi thay vì báo lỗi.
  static FaIconData iconFor(String iconName) =>
      _icons[iconName] ?? FontAwesomeIcons.circleQuestion;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        // DrawerHeader tự chừa vùng status bar và tô nền xanh cho vùng này.
        top: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              margin: EdgeInsets.zero,
              decoration: const BoxDecoration(color: Color(0xFF005A68)),
              child: Center(
                child: Image.asset(
                  'assets/images/logo-header.png',
                  fit: BoxFit.contain,
                  semanticLabel: 'Logo UEH',
                ),
              ),
            ),
            ListenableBuilder(
              listenable: menu,
              builder: (context, _) => _buildMenus(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenus(BuildContext context) {
    final items = menu.menus;
    if (items.isEmpty) {
      final waiting =
          (!menu.cacheLoaded && menu.cacheError == null) || menu.syncing;
      if (waiting) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        );
      }
      if (menu.cacheError != null && !menu.cacheLoaded) {
        return _message(menu.cacheError!, onRetry: menu.loadCache);
      }
      return _message(
        menu.syncError ??
            (menu.hasSynced
                ? 'Hiện chưa có mục menu nào.'
                : menu.canSync
                ? 'Chưa có dữ liệu menu.'
                : 'Chưa có dữ liệu menu. Vui lòng kết nối Internet và đăng nhập để đồng bộ.'),
        onRetry: menu.canSync ? menu.sync : null,
      );
    }
    return Column(
      children: [
        for (final item in items)
          ListTile(
            tileColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 4,
            ),
            leading: SizedBox(
              width: 28,
              child: Center(
                child: FaIcon(
                  iconFor(item.iconName),
                  size: 22,
                  color: const Color(0xFF005A68),
                ),
              ),
            ),
            title: Text(
              item.menuName,
              style: const TextStyle(color: Colors.black87, fontSize: 16),
            ),
            onTap: () {
              Scaffold.of(context).closeDrawer();
              onSelected(item);
            },
          ),
        // Có cache nhưng đồng bộ lỗi (mất mạng, server tạm ngừng...).
        if (menu.syncError != null && menu.canSync)
          _message(
            'Chưa đồng bộ được menu. Đang hiển thị dữ liệu đã lưu.',
            onRetry: menu.sync,
            small: true,
          ),
      ],
    );
  }

  Widget _message(String text, {VoidCallback? onRetry, bool small = false}) =>
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: small
                  ? TextStyle(fontSize: 13, color: Colors.grey.shade700)
                  : null,
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      );
}
