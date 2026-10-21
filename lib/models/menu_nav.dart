/// Một mục menu của Drawer.
///
/// Cùng một dữ liệu có ba cách đặt tên:
/// - API JSON (GET /api/menu): snake_case, ví dụ `icon_name`.
/// - Dart: camelCase, ví dụ [iconName].
/// - SQLite (bảng `menu_nav`): snake_case giống API, ví dụ cột `icon_name`.
class MenuNav {
  const MenuNav({
    required this.id,
    required this.iconName,
    required this.menuName,
    required this.menuUrl,
    required this.ordering,
  });

  /// Id do server cấp; dùng làm khóa chính trong SQLite.
  final int id;

  /// Tên icon Font Awesome, ví dụ `newspaper`, `chartLine`.
  final String iconName;
  final String menuName;

  /// URL của mục menu; chuỗi rỗng nếu chức năng chưa có.
  final String menuUrl;

  /// Thứ tự hiển thị tăng dần, có thể bắt đầu từ 0.
  final int ordering;

  /// Đọc một phần tử của mảng JSON từ GET /api/menu.
  ///
  /// Trường quan trọng thiếu hoặc sai kiểu thì ném [FormatException],
  /// không tự gán giá trị giả.
  factory MenuNav.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Mục menu phải là JSON object.');
    }
    final id = json['id'];
    final iconName = json['icon_name'];
    final menuName = json['menu_name'];
    final menuUrl = json['menu_url'];
    final ordering = json['ordering'];
    if (id is! int ||
        iconName is! String ||
        menuName is! String ||
        menuName.trim().isEmpty ||
        menuUrl is! String ||
        ordering is! int) {
      throw const FormatException('Mục menu thiếu trường hoặc sai kiểu.');
    }
    return MenuNav(
      id: id,
      iconName: iconName.trim(),
      menuName: menuName.trim(),
      menuUrl: menuUrl.trim(),
      ordering: ordering,
    );
  }

  /// Đọc một dòng của bảng SQLite `menu_nav`.
  factory MenuNav.fromMap(Map<String, Object?> map) => MenuNav(
    id: map['id'] as int,
    iconName: map['icon_name'] as String,
    menuName: map['menu_name'] as String,
    menuUrl: map['menu_url'] as String,
    ordering: map['ordering'] as int,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'icon_name': iconName,
    'menu_name': menuName,
    'menu_url': menuUrl,
    'ordering': ordering,
  };

  /// Thứ tự hiển thị: `ordering` tăng dần, trùng `ordering` thì theo `id`.
  static int compare(MenuNav a, MenuNav b) {
    final byOrdering = a.ordering.compareTo(b.ordering);
    return byOrdering != 0 ? byOrdering : a.id.compareTo(b.id);
  }

  // So sánh theo đủ 5 trường để biết menu từ server có thay đổi hay không.
  @override
  bool operator ==(Object other) =>
      other is MenuNav &&
      other.id == id &&
      other.iconName == iconName &&
      other.menuName == menuName &&
      other.menuUrl == menuUrl &&
      other.ordering == ordering;

  @override
  int get hashCode => Object.hash(id, iconName, menuName, menuUrl, ordering);
}
