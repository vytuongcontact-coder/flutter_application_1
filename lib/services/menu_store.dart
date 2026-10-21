import '../helpers/DBUtils.dart';

/// Nơi lưu menu bền vững. Tách interface để test thay SQLite bằng bộ nhớ RAM.
abstract interface class MenuStore {
  /// Menu đã lưu, sắp theo `ordering` rồi `id`.
  Future<List<MenuNav>> read();

  /// Lần đồng bộ server thành công gần nhất; null nếu chưa từng đồng bộ.
  Future<DateTime?> syncedAt();

  /// Ghi đè toàn bộ menu trong một transaction; trả về true nếu dữ liệu thay đổi.
  Future<bool> replace(List<MenuNav> menus, {required DateTime syncedAt});
}

class SqliteMenuStore implements MenuStore {
  const SqliteMenuStore();

  @override
  Future<List<MenuNav>> read() => DBUtils.getMenus();
  @override
  Future<DateTime?> syncedAt() => DBUtils.getMenuSyncedAt();
  @override
  Future<bool> replace(List<MenuNav> menus, {required DateTime syncedAt}) =>
      DBUtils.replaceMenus(menus, syncedAt: syncedAt);
}
