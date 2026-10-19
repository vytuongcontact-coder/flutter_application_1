// Giữ tên file DBUtils.dart theo yêu cầu của dự án.
// ignore_for_file: file_names

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class DBUtils {
  DBUtils._();

  static const databaseName = 'student_app.db';
  static const menuTable = 'menu_nav';
  static const newsUrl = String.fromEnvironment(
    'UEH_URL',
    defaultValue: 'https://ueh.edu.vn/tintucmobile',
  );

  static Future<Database>? _database;

  static Future<Database> get database => _database ??= _openDatabase();

  static Future<Database> _openDatabase() async {
    try {
      return await openDatabase(
        path.join(await getDatabasesPath(), databaseName),
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

          // onCreate chạy trong transaction; chỉ thêm menu khi tạo DB lần đầu.
          final batch = db.batch();
          for (final menu in _initialMenus) {
            batch.insert(menuTable, menu.toMap());
          }
          await batch.commit(noResult: true);
        },
      );
    } catch (_) {
      // Cho phép thử mở lại khi lần khởi tạo trước thất bại.
      _database = null;
      rethrow;
    }
  }

  static Future<List<MenuNav>> getMenus() async {
    final db = await database;
    final rows = await db.query(menuTable, orderBy: 'oredering ASC, id ASC');
    return rows.map(MenuNav.fromMap).toList();
  }

  static const _initialMenus = [
    MenuNav(
      iconName: 'newspaper',
      menuName: 'Tin tức UEH',
      menuUrl: newsUrl,
      oredering: 1,
    ),
    MenuNav(
      iconName: 'calendarDays',
      menuName: 'Sự kiện UEH',
      menuUrl: '',
      oredering: 2,
    ),
    MenuNav(
      iconName: 'graduationCap',
      menuName: 'Xem điểm',
      menuUrl: '',
      oredering: 3,
    ),
    MenuNav(
      iconName: 'idBadge',
      menuName: 'Định danh khuôn mặt',
      menuUrl: '',
      oredering: 4,
    ),
    MenuNav(
      iconName: 'calendarWeek',
      menuName: 'Thời khóa biểu',
      menuUrl: '',
      oredering: 5,
    ),
    MenuNav(
      iconName: 'filePen',
      menuName: 'Lịch thi',
      menuUrl: '',
      oredering: 6,
    ),
    MenuNav(
      iconName: 'heartPulse',
      menuName: 'Chăm sóc sức khỏe',
      menuUrl: '',
      oredering: 7,
    ),
    MenuNav(
      iconName: 'leaf',
      menuName: 'UEH Go Green Station',
      menuUrl: '',
      oredering: 8,
    ),
    MenuNav(
      iconName: 'headset',
      menuName: 'Liên hệ trực tiếp UEH',
      menuUrl: '',
      oredering: 9,
    ),
    MenuNav(
      iconName: 'coins',
      menuName: 'UEH Green Coin',
      menuUrl: '',
      oredering: 10,
    ),
    MenuNav(
      iconName: 'clipboardCheck',
      menuName: 'Đã điểm danh',
      menuUrl: '',
      oredering: 11,
    ),
  ];
}

class MenuNav {
  const MenuNav({
    this.id,
    required this.iconName,
    required this.menuName,
    required this.menuUrl,
    required this.oredering,
  });

  final int? id;
  final String iconName;
  final String menuName;
  final String menuUrl;
  final int oredering;

  factory MenuNav.fromMap(Map<String, Object?> map) => MenuNav(
    id: map['id'] as int,
    iconName: map['icon_name'] as String,
    menuName: map['menu_name'] as String,
    menuUrl: map['menu_url'] as String,
    oredering: map['oredering'] as int,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'icon_name': iconName,
    'menu_name': menuName,
    'menu_url': menuUrl,
    'oredering': oredering,
  };
}
