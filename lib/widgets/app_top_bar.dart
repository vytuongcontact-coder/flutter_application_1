import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.leading,
    this.actions,
    this.centerTitle,
  });

  static const uehBlue = Color(0xFF005A68);

  final String title;
  final Widget? leading;
  final List<Widget>? actions;

  /// Mặc định căn giữa tiêu đề như giao diện UEH Student gốc.
  final bool? centerTitle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    title: Text(title),
    centerTitle: centerTitle ?? true,
    backgroundColor: uehBlue,
    foregroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    leading: leading,
    actions: actions,
  );
}
