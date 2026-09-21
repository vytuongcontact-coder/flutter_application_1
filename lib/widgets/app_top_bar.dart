import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({super.key, required this.title, this.leading, this.actions});

  final String title;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    title: Text(title),
    backgroundColor: const Color(0xFF005A68),
    foregroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    leading: leading,
    actions: actions,
  );
}
