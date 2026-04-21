// Owner: T3 (UI teammate). Reference: brand §2 + JSX mark.jsx.
//
// Mark = the Liveback app icon rendered at N×N px, clipped to a rounded
// rectangle. AppIcon = same, larger (used in Settings masthead). The
// actual PNG lives under android/app/src/main/res/mipmap-* (T2 owns the
// adaptive-icon split). For in-app rendering we fall back to a solid-color
// placeholder: the raw PNG is not currently a pubspec asset (bundled as
// native mipmap only), so widget-side rendering uses a painted glyph.

import 'package:flutter/material.dart';

import '../../../widgets/theme_access.dart';

class AppMark extends StatelessWidget {
  final double size;
  const AppMark({super.key, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.ink,
        borderRadius: BorderRadius.circular(size * 0.18),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: Size(size, size),
        painter: _MarkGlyphPainter(
          bg: c.ink,
          cream: c.bg,
          cyan: c.chromaCyan,
          magenta: c.chromaMagenta,
        ),
      ),
    );
  }
}

class AppIconTile extends StatelessWidget {
  final double size;
  const AppIconTile({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return AppMark(size: size);
  }
}

/// Minimal painted "live" glyph matching brand §2 narrative: cream-colored
/// "live" letters with RGB chromatic split on the `l`. Not a 1:1 match of
/// the generated Editorial Glitch PNG — it's a readable proxy for in-app
/// renderings until the PNG is bundled as a Flutter asset (currently native
/// mipmap only).
class _MarkGlyphPainter extends CustomPainter {
  final Color bg;
  final Color cream;
  final Color cyan;
  final Color magenta;

  _MarkGlyphPainter({
    required this.bg,
    required this.cream,
    required this.cyan,
    required this.magenta,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final creamPaint = Paint()
      ..color = cream
      ..style = PaintingStyle.fill;
    // l bar — slightly offset cyan ghost + magenta ghost + cream main
    final lWidth = size.width * 0.12;
    final lLeft = size.width * 0.14;
    final lTop = size.height * 0.22;
    final lBottom = size.height * 0.78;
    final lRect = Rect.fromLTRB(lLeft, lTop, lLeft + lWidth, lBottom);
    canvas.drawRect(
      lRect.translate(-1.5, 0),
      Paint()..color = cyan.withValues(alpha: 0.85),
    );
    canvas.drawRect(
      lRect.translate(1.5, 0),
      Paint()..color = magenta.withValues(alpha: 0.85),
    );
    canvas.drawRect(lRect, creamPaint);

    // ive — three rounded caps to the right of the l
    final iveLeft = lLeft + lWidth + size.width * 0.04;
    final iveBar = size.height * 0.42;
    final iveWidth = size.width * 0.14;
    for (int i = 0; i < 3; i++) {
      final x = iveLeft + i * (iveWidth + size.width * 0.03);
      canvas.drawRRect(
        RRect.fromLTRBR(
          x,
          iveBar,
          x + iveWidth,
          lBottom,
          Radius.circular(size.width * 0.03),
        ),
        creamPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MarkGlyphPainter old) =>
      old.bg != bg ||
      old.cream != cream ||
      old.cyan != cyan ||
      old.magenta != magenta;
}
