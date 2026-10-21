import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/models/menu_nav.dart';
import 'package:flutter_application_1/services/menu_store.dart';

/// 11 mục đúng như GET /api/menu thật trả về (người làm bài kiểm chứng bằng
/// Postman ngày 21/10/2026). Không chứa dữ liệu cá nhân.
const menuJson = [
  {'id': 1, 'icon_name': 'newspaper', 'menu_name': 'Tin tức UEH', 'menu_url': 'https://ueh.edu.vn/tintucmobile', 'ordering': 0},
  {'id': 2, 'icon_name': 'calendarDays', 'menu_name': 'Sự kiện UEH', 'menu_url': '', 'ordering': 1},
  {'id': 3, 'icon_name': 'chartLine', 'menu_name': 'Xem điểm', 'menu_url': '', 'ordering': 2},
  {'id': 4, 'icon_name': 'faceSmile', 'menu_name': 'Định danh khuôn mặt', 'menu_url': '', 'ordering': 3},
  {'id': 5, 'icon_name': 'calendarWeek', 'menu_name': 'Thời khóa biểu', 'menu_url': '', 'ordering': 4},
  {'id': 6, 'icon_name': 'fileLines', 'menu_name': 'Lịch thi', 'menu_url': '', 'ordering': 5},
  {'id': 7, 'icon_name': 'heartPulse', 'menu_name': 'Chăm sóc sức khỏe', 'menu_url': '', 'ordering': 6},
  {'id': 8, 'icon_name': 'leaf', 'menu_name': 'UEH Go Green Station', 'menu_url': '', 'ordering': 7},
  {'id': 9, 'icon_name': 'phone', 'menu_name': 'Liên hệ trực tiếp UEH', 'menu_url': '', 'ordering': 8},
  {'id': 10, 'icon_name': 'coins', 'menu_name': 'UEH Green Coin', 'menu_url': '', 'ordering': 9},
  {'id': 11, 'icon_name': 'circleCheck', 'menu_name': 'Đã điểm danh', 'menu_url': '', 'ordering': 10},
];

List<MenuNav> get apiMenus => menuJson.map(MenuNav.fromJson).toList();

/// 11 menu mẫu của database version 1 (icon cũ, ordering 1-11) sau migration.
const seedMenus = [
  MenuNav(id: 1, iconName: 'newspaper', menuName: 'Tin tức UEH', menuUrl: 'https://ueh.edu.vn/tintucmobile', ordering: 1),
  MenuNav(id: 2, iconName: 'calendarDays', menuName: 'Sự kiện UEH', menuUrl: '', ordering: 2),
  MenuNav(id: 3, iconName: 'graduationCap', menuName: 'Xem điểm', menuUrl: '', ordering: 3),
  MenuNav(id: 4, iconName: 'idBadge', menuName: 'Định danh khuôn mặt', menuUrl: '', ordering: 4),
  MenuNav(id: 5, iconName: 'calendarWeek', menuName: 'Thời khóa biểu', menuUrl: '', ordering: 5),
  MenuNav(id: 6, iconName: 'filePen', menuName: 'Lịch thi', menuUrl: '', ordering: 6),
  MenuNav(id: 7, iconName: 'heartPulse', menuName: 'Chăm sóc sức khỏe', menuUrl: '', ordering: 7),
  MenuNav(id: 8, iconName: 'leaf', menuName: 'UEH Go Green Station', menuUrl: '', ordering: 8),
  MenuNav(id: 9, iconName: 'headset', menuName: 'Liên hệ trực tiếp UEH', menuUrl: '', ordering: 9),
  MenuNav(id: 10, iconName: 'coins', menuName: 'UEH Green Coin', menuUrl: '', ordering: 10),
  MenuNav(id: 11, iconName: 'clipboardCheck', menuName: 'Đã điểm danh', menuUrl: '', ordering: 11),
];

/// MenuStore trong RAM thay cho SQLite trong widget/unit test.
class MemoryMenuStore implements MenuStore {
  MemoryMenuStore([List<MenuNav> menus = const [], this.savedAt])
    : menus = [...menus];

  List<MenuNav> menus;
  DateTime? savedAt;
  int reads = 0;
  int writes = 0;
  Object? readError;
  Object? writeError;
  Completer<void>? readGate;

  @override
  Future<List<MenuNav>> read() async {
    reads++;
    if (readGate != null) await readGate!.future;
    if (readError != null) throw readError!;
    return [...menus]..sort(MenuNav.compare);
  }

  @override
  Future<DateTime?> syncedAt() async => savedAt;

  @override
  Future<bool> replace(List<MenuNav> next, {required DateTime syncedAt}) async {
    if (writeError != null) throw writeError!;
    writes++;
    final sorted = [...next]..sort(MenuNav.compare);
    final changed = !listEquals(menus, sorted);
    menus = sorted;
    savedAt = syncedAt;
    return changed;
  }
}
