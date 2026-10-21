import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

enum BottomMenu {
  home('Trang chủ', FontAwesomeIcons.house),
  notifications('Thông báo', FontAwesomeIcons.bell),
  attendance('Điểm danh', FontAwesomeIcons.clipboardCheck),
  account('Tài khoản', FontAwesomeIcons.user);

  const BottomMenu(this.title, this.icon);

  final String title;
  final FaIconData icon;
}

class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.onSelected,
    this.selectedMenu = BottomMenu.home,
  });

  final ValueChanged<BottomMenu> onSelected;
  final BottomMenu selectedMenu;

  // Tông xanh UEH, cùng màu thanh trên (AppTopBar.uehBlue).
  static const selectedColor = Color(0xFF005A68);
  static const unselectedColor = Color(0xFF8DB4BA);

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: selectedColor,
      unselectedItemColor: unselectedColor,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      showUnselectedLabels: true,
      currentIndex: selectedMenu.index,
      onTap: (index) => onSelected(BottomMenu.values[index]),
      items: [
        for (final menu in BottomMenu.values)
          BottomNavigationBarItem(
            icon: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: FaIcon(menu.icon, size: 22),
            ),
            label: menu.title,
            tooltip: menu.title,
          ),
      ],
    );
  }
}
