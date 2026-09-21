import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

enum DrawerMenu {
  news('Tin tức UEH', FontAwesomeIcons.newspaper),
  events('Sự kiện UEH', FontAwesomeIcons.calendarDays),
  grades('Xem điểm', FontAwesomeIcons.graduationCap),
  faceIdentification('Định danh khuôn mặt', FontAwesomeIcons.idBadge),
  schedule('Thời khóa biểu', FontAwesomeIcons.calendarWeek),
  examSchedule('Lịch thi', FontAwesomeIcons.filePen),
  healthCare('Chăm sóc sức khỏe', FontAwesomeIcons.heartPulse),
  greenStation('UEH Go Green Station', FontAwesomeIcons.leaf),
  contact('Liên hệ trực tiếp UEH', FontAwesomeIcons.headset),
  greenCoin('UEH Green Coin', FontAwesomeIcons.coins),
  attendance('Đã điểm danh', FontAwesomeIcons.clipboardCheck);

  const DrawerMenu(this.title, this.icon);

  final String title;
  final FaIconData icon;
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.onSelected});

  final ValueChanged<DrawerMenu> onSelected;

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
            for (final menu in DrawerMenu.values)
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
                      menu.icon,
                      size: 22,
                      color: const Color(0xFF005A68),
                    ),
                  ),
                ),
                title: Text(
                  menu.title,
                  style: const TextStyle(color: Colors.black87, fontSize: 16),
                ),
                onTap: () {
                  Scaffold.of(context).closeDrawer();
                  onSelected(menu);
                },
              ),
          ],
        ),
      ),
    );
  }
}
