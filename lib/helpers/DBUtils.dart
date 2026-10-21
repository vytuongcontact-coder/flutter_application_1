// Giữ tên file DBUtils.dart theo yêu cầu của dự án.
// ignore_for_file: file_names

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/menu_nav.dart';

// Giữ import cũ `helpers/DBUtils.dart` vẫn dùng được MenuNav.
export '../models/menu_nav.dart';

class DBUtils {
  DBUtils._();

  static const databaseName = 'student_app.db';

  /// Version 1: bảng menu_nav dùng cột `oredering` (sai chính tả) và 11 menu mẫu.
  /// Version 2: cột `ordering`, id lấy từ server, thêm bảng app_meta.
  static const databaseVersion = 2;
  static const menuTable = 'menu_nav';
  static const metaTable = 'app_meta';
  static const menuSyncedAtKey = 'menu_synced_at';
  static const newsUrl = String.fromEnvironment(
    'UEH_URL',
    defaultValue: 'https://ueh.edu.vn/tintucmobile',
  );

  /// Chỉ dùng trong test: trỏ tới file database tạm thay cho database thật.
  @visibleForTesting
  static String? debugDatabasePath;

  static Future<Database>? _database;

  static Future<Database> get database => _database ??= _openDatabase();

  static Future<Database> _openDatabase() async {
    try {
      return await openDatabase(
        debugDatabasePath ??
            path.join(await getDatabasesPath(), databaseName),
        version: databaseVersion,
        // Cài mới không còn chèn menu mẫu: menu chỉ đến từ GET /api/menu.
        onCreate: (db, version) async {
          await _createMenuTable(db, menuTable);
          await _createMetaTable(db);
        },
        onUpgrade: _upgrade,
      );
    } catch (_) {
      // Cho phép thử mở lại khi lần khởi tạo trước thất bại.
      _database = null;
      rethrow;
    }
  }

  static Future<void> _createMenuTable(DatabaseExecutor db, String table) =>
      db.execute('''
        CREATE TABLE $table (
          id INTEGER PRIMARY KEY,
          icon_name TEXT NOT NULL,
          menu_name TEXT NOT NULL,
          menu_url TEXT NOT NULL,
          ordering INTEGER NOT NULL
        )
      ''');

  static Future<void> _createMetaTable(DatabaseExecutor db) => db.execute('''
        CREATE TABLE $metaTable (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');

  // sqflite đã chạy onUpgrade trong một transaction: lỗi ở bất kỳ bước nào thì
  // rollback toàn bộ và database giữ nguyên version cũ. Không mở transaction lồng.
  static Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Không dùng RENAME COLUMN (cần SQLite 3.25+, một số máy Android cũ chưa có):
      // tạo bảng mới, chép dữ liệu, xóa bảng cũ rồi đổi tên bảng mới.
      await _createMenuTable(db, 'menu_nav_v2');
      await db.execute('''
        INSERT INTO menu_nav_v2 (id, icon_name, menu_name, menu_url, ordering)
        SELECT id, IFNULL(icon_name, ''), IFNULL(menu_name, ''),
               IFNULL(menu_url, ''), IFNULL(oredering, 0)
        FROM menu_nav
      ''');
      await db.execute('DROP TABLE menu_nav');
      await db.execute('ALTER TABLE menu_nav_v2 RENAME TO menu_nav');
      // Chưa ghi menu_synced_at: menu chuyển sang chỉ là menu mẫu của bản cũ,
      // chưa phải dữ liệu đã đồng bộ từ server.
      await _createMetaTable(db);
    }
    // Version sau: thêm `if (oldVersion < 3) { ... }` ở đây, không sửa bước cũ.
  }

  static Future<List<MenuNav>> getMenus() async {
    final db = await database;
    final rows = await db.query(menuTable, orderBy: 'ordering ASC, id ASC');
    return rows.map(MenuNav.fromMap).toList();
  }

  /// Lần đồng bộ Menu API thành công gần nhất; null nếu chưa từng đồng bộ.
  static Future<DateTime?> getMenuSyncedAt() async {
    final db = await database;
    final rows = await db.query(
      metaTable,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [menuSyncedAtKey],
    );
    return rows.isEmpty ? null : DateTime.tryParse(rows.single['value'] as String);
  }

  /// Thay toàn bộ menu bằng danh sách từ server trong một transaction.
  ///
  /// Trả về true nếu dữ liệu khác với cache. Lỗi giữa chừng (ví dụ trùng id)
  /// thì rollback: cache cũ và thời điểm đồng bộ cũ được giữ nguyên.
  static Future<bool> replaceMenus(
    List<MenuNav> menus, {
    required DateTime syncedAt,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final current = (await txn.query(
        menuTable,
        orderBy: 'ordering ASC, id ASC',
      )).map(MenuNav.fromMap).toList();
      final incoming = [...menus]..sort(MenuNav.compare);
      final changed = !listEquals(current, incoming);
      if (changed) {
        await txn.delete(menuTable);
        final batch = txn.batch();
        for (final menu in incoming) {
          batch.insert(menuTable, menu.toMap());
        }
        await batch.commit(noResult: true);
      }
      await txn.insert(metaTable, {
        'key': menuSyncedAtKey,
        'value': syncedAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return changed;
    });
  }

  /// Đóng database; lần gọi [database] sau sẽ mở lại từ file.
  @visibleForTesting
  static Future<void> close() async {
    final opening = _database;
    _database = null;
    if (opening == null) return;
    try {
      await (await opening).close();
    } catch (_) {
      /* Database chưa mở được thì không cần đóng. */
    }
  }
}
