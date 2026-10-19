import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:flutter_application_1/helpers/DBUtils.dart';
import 'package:flutter_application_1/widgets/app_drawer.dart';

void main() {
  const menu = MenuNav(
    id: 42,
    iconName: 'newspaper',
    menuName: 'Tin tức từ database',
    menuUrl: 'https://ueh.edu.vn/tintucmobile',
    oredering: 1,
  );

  testWidgets('Drawer chờ dữ liệu và trả về menu đã đọc khi chọn', (
    tester,
  ) async {
    final menus = Completer<List<MenuNav>>();
    final scaffoldKey = GlobalKey<ScaffoldState>();
    MenuNav? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: scaffoldKey,
          drawer: AppDrawer(
            loadMenus: () => menus.future,
            onSelected: (value) => selected = value,
          ),
        ),
      ),
    );
    scaffoldKey.currentState!.openDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    menus.complete([menu]);
    await tester.pumpAndSettle();
    expect(find.text(menu.menuName), findsOneWidget);
    expect(
      tester.widget<FaIcon>(find.byType(FaIcon)).icon,
      FontAwesomeIcons.newspaper.data,
    );

    await tester.tap(find.text(menu.menuName));
    await tester.pumpAndSettle();
    expect(selected, same(menu));
    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
  });

  testWidgets('Drawer cho phép tải lại khi đọc database thất bại', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppDrawer(
            loadMenus: () async {
              if (++attempts == 1) throw StateError('Database unavailable');
              return [menu];
            },
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Không thể tải menu. Vui lòng thử lại.'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text(menu.menuName), findsOneWidget);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
