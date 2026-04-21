// Splash wordmark. A single "live" glyph renders with a scanning repair
// sweep: pixels to the right of the scan head carry full RGB chromatic
// ghosts (broken); pixels to the left read as flat cream (repaired). The
// scan head itself is a 3-color split vertical line preceded by a cyan
// fade band, mirroring the Waveform scanning-state vocabulary.

import 'package:flutter/material.dart';

import '../../../widgets/theme_access.dart';

class GlitchWordmark extends StatelessWidget {
  /// 0.0 = fully broken (scan head not started);
  /// progress rises as the scan sweeps left → right;
  /// 1.0 = fully repaired (no chromatic ghosts).
  final double progress;

  /// Wordmark text. Caller usually passes the app name.
  final String text;

  /// Font size of the text. Caller owns layout sizing; the widget
  /// claims a SizedBox exactly large enough to hold the painted stack.
  final double fontSize;

  /// Maximum chromatic offset in logical pixels (applied to the broken
  /// half only). Default 4.
  final double maxChromaOffset;

  const GlitchWordmark({
    super.key,
    required this.progress,
    this.text = 'Liveback',
    this.fontSize = 84,
    this.maxChromaOffset = 4,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cream = colors.bg; // light: paper, dark: cream — stays cream against dark ink
    // Splash is always-dark (editorial): force cream = #F4EEE2 regardless of
    // theme so the wordmark stays in brand. Note: we rely on app scaffold
    // bg to be #0B1013 during splash (see SplashPage background).
    const creamLiteral = Color(0xFFF4EEE2);
    final chromaCyan = colors.chromaCyan;
    final chromaMagenta = colors.chromaMagenta;

    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: -fontSize * 0.04,
      height: 1.0,
      // Force explicit color per layer via TextStyle(color:) on each copy.
    );

    return SizedBox(
      height: fontSize * 1.1,
      child: LayoutBuilder(
        builder: (_, c) {
          final w = c.maxWidth;
          final scanX = progress.clamp(0.0, 1.0) * w;
          return Stack(
            alignment: Alignment.center,
            children: [
              // 1. Broken half — right of scan head. Three text layers
              //    offset by ±maxChromaOffset; visible only where x >= scanX.
              Positioned.fill(
                child: ClipRect(
                  clipper: _RightOfX(scanX),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(-maxChromaOffset, 0),
                        child: Opacity(
                          opacity: 0.85,
                          child: Text(
                            text,
                            textAlign: TextAlign.center,
                            style: style.copyWith(color: chromaCyan),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(maxChromaOffset, 0),
                        child: Opacity(
                          opacity: 0.85,
                          child: Text(
                            text,
                            textAlign: TextAlign.center,
                            style: style.copyWith(color: chromaMagenta),
                          ),
                        ),
                      ),
                      Text(
                        text,
                        textAlign: TextAlign.center,
                        style: style.copyWith(color: creamLiteral),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. Repaired half — left of scan head. Single cream copy,
              //    no chromatic.
              Positioned.fill(
                child: ClipRect(
                  clipper: _LeftOfX(scanX),
                  child: Center(
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: style.copyWith(color: creamLiteral),
                    ),
                  ),
                ),
              ),

              // 3. Scan head — fade band + tri-color split line.
              //    Hidden at progress == 0 (broken-frozen intro) and
              //    progress == 1 (fully repaired outro).
              if (progress > 0.0 && progress < 1.0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ScanHeadPainter(
                        progress: progress,
                        cyan: chromaCyan,
                        magenta: chromaMagenta,
                        cream: creamLiteral,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RightOfX extends CustomClipper<Rect> {
  final double x;
  const _RightOfX(this.x);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(x, 0, size.width - x, size.height);

  @override
  bool shouldReclip(covariant _RightOfX old) => old.x != x;
}

class _LeftOfX extends CustomClipper<Rect> {
  final double x;
  const _LeftOfX(this.x);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, x, size.height);

  @override
  bool shouldReclip(covariant _LeftOfX old) => old.x != x;
}

class _ScanHeadPainter extends CustomPainter {
  final double progress;
  final Color cyan;
  final Color magenta;
  final Color cream;

  _ScanHeadPainter({
    required this.progress,
    required this.cyan,
    required this.magenta,
    required this.cream,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final scanX = progress * size.width;
    final h = size.height;

    // Cyan fade band preceding the head, 48px wide, 0 → 0.35 opacity.
    const bandWidth = 48.0;
    final bandRect = Rect.fromLTWH(
      (scanX - bandWidth).clamp(0.0, size.width),
      0,
      bandWidth.clamp(0.0, scanX),
      h,
    );
    if (bandRect.width > 0) {
      final gradient = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          cyan.withValues(alpha: 0.0),
          cyan.withValues(alpha: 0.14),
          cyan.withValues(alpha: 0.35),
        ],
        stops: const [0.0, 0.7, 1.0],
      );
      final bandPaint = Paint()..shader = gradient.createShader(bandRect);
      canvas.drawRect(bandRect, bandPaint);
    }

    // Tri-color split vertical line (cyan −2 / cream 0 / magenta +2).
    final linePaint = Paint()
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(scanX - 2, 4),
      Offset(scanX - 2, h - 4),
      linePaint..color = cyan.withValues(alpha: 0.9),
    );
    canvas.drawLine(
      Offset(scanX + 2, 4),
      Offset(scanX + 2, h - 4),
      linePaint..color = magenta.withValues(alpha: 0.9),
    );
    canvas.drawLine(
      Offset(scanX, 0),
      Offset(scanX, h),
      linePaint
        ..color = cream
        ..strokeWidth = 2.2,
    );
    // Head dot.
    canvas.drawCircle(
      Offset(scanX, h / 2),
      2.6,
      Paint()..color = cream,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanHeadPainter old) =>
      old.progress != progress ||
      old.cyan != cyan ||
      old.magenta != magenta ||
      old.cream != cream;
}
