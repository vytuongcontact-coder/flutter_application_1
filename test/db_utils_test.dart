import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_application_1/helpers/DBUtils.dart';

import 'menu_fixtures.dart';

// Tạo đúng database version 1 như bản app cũ (commit 500a7d7).
Future<void> _createVersion1(String file) async {
  final db = await databaseFactoryFfi.openDatabase(
    file,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
            CREATE TABLE menu_nav (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              icon_name TEXT,
              menu_name TEXT,
              menu_url TEXT,
              oredering INTEGER
            )
          ''');
        for (final menu in seedMenus) {
          await db.insert('menu_nav', {
            'icon_name': menu.iconName,
            'menu_name': menu.menuName,
            'menu_url': menu.menuUrl,
            'oredering': menu.ordering,
          });
        }
      },
    ),
  );
  await db.close();
}

void main() {
  late Directory dir;
  final t0 = DateTime(2026, 10, 21, 9);

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ueh_db_test');
    DBUtils.debugDatabasePath = path.join(dir.path, DBUtils.databaseName);
  });

  tearDown(() async {
    await DBUtils.close();
    DBUtils.debugDatabasePath = null;
    await dir.delete(recursive: true);
  });

  test('Migration v1 → v2: giữ dữ liệu cũ, oredering → ordering', () async {
    await _createVersion1(DBUtils.debugDatabasePath!);
    final menus = await DBUtils.getMenus();
    expect(menus, seedMenus);
    final db = await DBUtils.database;
    expect(await db.getVersion(), 2);
    final columns = (await db.rawQuery('PRAGMA table_info(menu_nav)'))
        .map((c) => c['name'])
        .toList();
    expect(columns, ['id', 'icon_name', 'menu_name', 'menu_url', 'ordering']);
    // Menu mẫu chuyển sang không được coi là đã đồng bộ từ server.
    expect(await DBUtils.getMenuSyncedAt(), isNull);
  });

  test('Cài mới: không chèn menu mẫu, chưa có mốc đồng bộ', () async {
    expect(await DBUtils.getMenus(), isEmpty);
    expect(await DBUtils.getMenuSyncedAt(), isNull);
    expect(await (await DBUtils.database).getVersion(), 2);
  });

  test('Đồng bộ lần đầu thay menu mẫu bằng 11 menu server theo id', () async {
    await _createVersion1(DBUtils.debugDatabasePath!);
    expect(await DBUtils.replaceMenus(apiMenus, syncedAt: t0), isTrue);
    final menus = await DBUtils.getMenus();
    expect(menus, apiMenus);
    expect(menus.map((m) => m.ordering), List.generate(11, (i) => i));
    expect(menus.map((m) => m.iconName), isNot(contains('graduationCap')));
    expect(await DBUtils.getMenuSyncedAt(), t0);
    // Đồng bộ lại cùng dữ liệu: không ghi lại, không nhân đôi.
    expect(await DBUtils.replaceMenus(apiMenus, syncedAt: t0), isFalse);
    expect(await DBUtils.getMenus(), hasLength(11));
  });

  test('Server thêm, đổi tên, icon, URL, ordering và xóa mục', () async {
    await DBUtils.replaceMenus(apiMenus, syncedAt: t0);
    final next = [
      for (final m in apiMenus)
        if (m.id != 11) // server xóa mục 11
          switch (m.id) {
            2 => MenuNav(id: 2, iconName: m.iconName, menuName: 'Sự kiện', menuUrl: m.menuUrl, ordering: m.ordering),
            3 => MenuNav(id: 3, iconName: 'graduationCap', menuName: m.menuName, menuUrl: m.menuUrl, ordering: m.ordering),
            4 => MenuNav(id: 4, iconName: m.iconName, menuName: m.menuName, menuUrl: 'https://ueh.edu.vn/face', ordering: m.ordering),
            5 => MenuNav(id: 5, iconName: m.iconName, menuName: m.menuName, menuUrl: m.menuUrl, ordering: 99),
            _ => m,
          },
      const MenuNav(id: 12, iconName: 'star', menuName: 'Mục mới', menuUrl: '', ordering: 1),
    ];
    final t1 = t0.add(const Duration(hours: 1));
    expect(await DBUtils.replaceMenus(next, syncedAt: t1), isTrue);
    final saved = await DBUtils.getMenus();
    expect(saved.map((m) => m.id), [1, 2, 12, 3, 4, 6, 7, 8, 9, 10, 5]);
    expect(saved.firstWhere((m) => m.id == 2).menuName, 'Sự kiện');
    expect(saved.firstWhere((m) => m.id == 3).iconName, 'graduationCap');
    expect(saved.firstWhere((m) => m.id == 4).menuUrl, 'https://ueh.edu.vn/face');
    expect(saved.last.ordering, 99);
    expect(saved.any((m) => m.id == 11), isFalse);
    expect(await DBUtils.getMenuSyncedAt(), t1);
  });

  test('Server trả mảng rỗng: đồng bộ thành công, bảng menu rỗng', () async {
    await DBUtils.replaceMenus(apiMenus, syncedAt: t0);
    final t1 = t0.add(const Duration(minutes: 1));
    await DBUtils.replaceMenus(const [], syncedAt: t1);
    expect(await DBUtils.getMenus(), isEmpty);
    expect(await DBUtils.getMenuSyncedAt(), t1);
  });

  test('Lỗi giữa transaction: rollback, giữ menu và mốc đồng bộ cũ', () async {
    await DBUtils.replaceMenus(apiMenus, syncedAt: t0);
    final broken = [
      apiMenus[0],
      const MenuNav(id: 2, iconName: 'leaf', menuName: 'A', menuUrl: '', ordering: 1),
      const MenuNav(id: 2, iconName: 'leaf', menuName: 'B', menuUrl: '', ordering: 2),
    ];
    await expectLater(
      DBUtils.replaceMenus(broken, syncedAt: t0.add(const Duration(hours: 1))),
      throwsA(isA<DatabaseException>()),
    );
    expect(await DBUtils.getMenus(), apiMenus);
    expect(await DBUtils.getMenuSyncedAt(), t0);
  });

  test('Đóng và mở lại database vẫn đọc được menu đã lưu', () async {
    await DBUtils.replaceMenus(apiMenus, syncedAt: t0);
    await DBUtils.close();
    expect(await DBUtils.getMenus(), apiMenus);
    expect(await DBUtils.getMenuSyncedAt(), t0);
  });

  test('Hai lần ghi chồng nhau được SQLite thực hiện đúng thứ tự gọi', () async {
    await DBUtils.database;
    // Không await lần ghi đầu: mô phỏng phiên cũ đang ghi thì phiên mới ghi tiếp.
    final older = DBUtils.replaceMenus(seedMenus, syncedAt: t0);
    final newer = DBUtils.replaceMenus(
      apiMenus,
      syncedAt: t0.add(const Duration(minutes: 1)),
    );
    expect(await Future.wait([older, newer]), [true, true]);
    expect(await DBUtils.getMenus(), apiMenus);
    expect(await DBUtils.getMenuSyncedAt(), t0.add(const Duration(minutes: 1)));
  });

  test('Trùng ordering thì sắp tiếp theo id', () async {
    await DBUtils.replaceMenus(const [
      MenuNav(id: 3, iconName: 'leaf', menuName: 'C', menuUrl: '', ordering: 0),
      MenuNav(id: 1, iconName: 'leaf', menuName: 'A', menuUrl: '', ordering: 0),
      MenuNav(id: 2, iconName: 'leaf', menuName: 'B', menuUrl: '', ordering: -1),
    ], syncedAt: t0);
    expect((await DBUtils.getMenus()).map((m) => m.id), [2, 1, 3]);
  });
}
