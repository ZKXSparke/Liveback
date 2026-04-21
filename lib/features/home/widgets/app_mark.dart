// Owner: T3 (UI teammate). Reference: brand §2 + JSX mark.jsx.
//
// Renders the Editorial Glitch app icon (assets/branding/app-icon.png)
// clipped to a rounded rectangle. Used by Home masthead (22 px) and
// Settings/Test Mode sections (64 px).

import 'package:flutter/material.dart';

class AppMark extends StatelessWidget {
  final double size;
  const AppMark({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/branding/app-icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

class AppIconTile extends StatelessWidget {
  final double size;
  const AppIconTile({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) => AppMark(size: size);
}
