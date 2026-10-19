import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../helpers/DBUtils.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({
    super.key,
    required this.onSelected,
    this.loadMenus = DBUtils.getMenus,
  });

  final ValueChanged<MenuNav> onSelected;
  final Future<List<MenuNav>> Function() loadMenus;

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  late Future<List<MenuNav>> _menus;

  static const _icons = {
    'newspaper': FontAwesomeIcons.newspaper,
    'calendarDays': FontAwesomeIcons.calendarDays,
    'graduationCap': FontAwesomeIcons.graduationCap,
    'idBadge': FontAwesomeIcons.idBadge,
    'calendarWeek': FontAwesomeIcons.calendarWeek,
    'filePen': FontAwesomeIcons.filePen,
    'heartPulse': FontAwesomeIcons.heartPulse,
    'leaf': FontAwesomeIcons.leaf,
    'headset': FontAwesomeIcons.headset,
    'coins': FontAwesomeIcons.coins,
    'clipboardCheck': FontAwesomeIcons.clipboardCheck,
  };

  @override
  void initState() {
    super.initState();
    _menus = widget.loadMenus();
  }

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
            FutureBuilder<List<MenuNav>>(
              future: _menus,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Không thể tải menu. Vui lòng thử lại.'),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _menus = widget.loadMenus();
                        }),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    for (final menu in snapshot.data!)
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
                              _icons[menu.iconName] ??
                                  FontAwesomeIcons.circleQuestion,
                              size: 22,
                              color: const Color(0xFF005A68),
                            ),
                          ),
                        ),
                        title: Text(
                          menu.menuName,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                          ),
                        ),
                        onTap: () {
                          Scaffold.of(context).closeDrawer();
                          widget.onSelected(menu);
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
