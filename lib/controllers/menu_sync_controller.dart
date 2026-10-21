import 'package:flutter/foundation.dart';

import '../models/menu_nav.dart';
import '../services/menu_store.dart';
import '../services/student_api.dart';

/// Menu Drawer theo kiểu cache-then-network:
/// đọc SQLite để hiển thị ngay, rồi gọi GET /api/menu khi có phiên đăng nhập,
/// lưu kết quả vào SQLite và báo Drawer vẽ lại.
class MenuSyncController extends ChangeNotifier {
  MenuSyncController({
    required this.api,
    MenuStore? store,
    DateTime Function()? clock,
  }) : store = store ?? const SqliteMenuStore(),
       _now = clock ?? DateTime.now;

  /// Mở Drawer sau khoảng này kể từ lần đồng bộ thành công thì kiểm tra lại server.
  static const staleAfter = Duration(minutes: 5);

  final StudentApi api;
  final MenuStore store;
  final DateTime Function() _now;

  /// Danh sách đang hiển thị, đã sắp theo `ordering`.
  List<MenuNav> menus = const [];

  /// Đã đọc xong SQLite (thành công) ít nhất một lần.
  bool cacheLoaded = false;
  String? cacheError;

  /// Lần đồng bộ server thành công gần nhất; null là chưa từng đồng bộ
  /// (menu nếu có chỉ là menu mẫu chuyển từ database version 1).
  DateTime? syncedAt;
  bool syncing = false;
  String? syncError;

  /// Lần đồng bộ gần nhất có làm dữ liệu thay đổi không.
  bool? lastSyncChanged;

  Future<void>? _loadingCache;
  Future<void>? _syncing;
  // Tăng khi phiên đăng nhập kết thúc: kết quả của request cũ bị bỏ qua.
  int _epoch = 0;
  // Tăng khi menu lấy từ server: kết quả đọc cache cũ hơn không được ghi đè.
  int _revision = 0;
  bool _disposed = false;

  bool get hasSynced => syncedAt != null;

  /// Chỉ gọi Menu API khi có token; không gửi request với token rỗng.
  bool get canSync => api.hasSession;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Đọc menu đã lưu. Gọi nhiều lần cùng lúc chỉ đọc một lần.
  Future<void> loadCache() => _loadingCache ??= _loadCache();

  Future<void> _loadCache() async {
    final revision = _revision;
    if (cacheError != null) {
      cacheError = null;
      _notify();
    }
    try {
      final cached = await store.read();
      final at = await store.syncedAt();
      if (revision == _revision) {
        menus = List.unmodifiable(cached);
        syncedAt = at;
      }
      cacheLoaded = true;
    } catch (_) {
      cacheError = 'Không thể tải menu. Vui lòng thử lại.';
      _loadingCache = null; // Cho phép bấm "Thử lại".
    } finally {
      _notify();
    }
  }

  /// Đồng bộ với GET /api/menu. Đang có request thì dùng chung request đó.
  Future<void> sync() {
    if (!canSync) return Future.value();
    final pending = _syncing;
    if (pending != null) return pending;
    final future = _sync(_epoch);
    _syncing = future;
    future.whenComplete(() {
      if (identical(_syncing, future)) _syncing = null;
    });
    return future;
  }

  /// Dùng khi mở Drawer: đồng bộ lại nếu chưa từng đồng bộ, lần trước lỗi,
  /// hoặc lần đồng bộ thành công đã cũ hơn [staleAfter].
  Future<void> syncIfStale() {
    final at = syncedAt;
    final fresh =
        syncError == null && at != null && _now().difference(at) < staleAfter;
    return fresh ? Future.value() : sync();
  }

  Future<void> _sync(int epoch) async {
    syncing = true;
    syncError = null;
    _notify();
    try {
      // Cache hiển thị trước, sau đó mới tới dữ liệu mạng.
      await loadCache();
      final remote = await api.menu();
      if (epoch != _epoch) return;
      final at = _now();
      // Ghi SQLite trước; chỉ cập nhật UI khi lưu thành công.
      final bool changed;
      try {
        changed = await store.replace(remote, syncedAt: at);
      } catch (_) {
        if (epoch == _epoch) {
          syncError = 'Không thể lưu menu vào máy. Vui lòng thử lại.';
        }
        return;
      }
      if (epoch != _epoch) return;
      _revision++;
      menus = List.unmodifiable(<MenuNav>[...remote]..sort(MenuNav.compare));
      syncedAt = at;
      lastSyncChanged = changed;
      cacheLoaded = true;
    } on ApiException catch (e) {
      // Lỗi mạng, timeout, 5xx, dữ liệu sai: giữ nguyên menu đang có.
      if (epoch == _epoch) syncError = e.message;
    } catch (_) {
      if (epoch == _epoch) {
        syncError = 'Không thể đồng bộ menu. Vui lòng thử lại.';
      }
    } finally {
      if (epoch == _epoch) {
        syncing = false;
        _notify();
      }
    }
  }

  /// Gọi khi phiên đăng nhập kết thúc (đăng xuất hoặc hết hạn).
  ///
  /// Request đang chạy sẽ không được cập nhật UI hay SQLite nữa.
  /// Menu đã lưu vẫn giữ để dùng khi offline; menu không chứa dữ liệu cá nhân.
  void cancelSync() {
    _epoch++;
    _syncing = null;
    if (syncing || syncError != null) {
      syncing = false;
      syncError = null;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    super.dispose();
  }
}
