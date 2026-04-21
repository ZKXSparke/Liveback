// Owner: T3 (UI teammate). Reference: brand §5.3.3 ErrorDialog (GLITCH
// HACK-IN) + JSX design-v2/project/components/dialog.jsx#ErrorDialog.
//
// THE SHOWPIECE: cross-mode dark card with triangle ghost (cyan -2 /
// magenta +2 / white main), RGB-split title via 3-layer Stack, terminal-
// style error-code chip (magenta bg + JetBrains Mono + `>` prefix), grid
// + scanline overlay, dual outer glow (cyan + magenta), 320ms entrance
// animation with skew / hue-rotate / shake.

import 'package:flutter/material.dart';

import '../../core/theme.dart' show LivebackTheme;
import '../mono_text.dart';

/// User's response to the ErrorDialog.
enum ErrorDialogAction { back, retry }

Future<ErrorDialogAction> showErrorDialog(
  BuildContext context, {
  required String errorCode,
  required String title,
  required String body,
  String? technicalDetails,
  bool canRetry = false,
}) async {
  final result = await showGeneralDialog<ErrorDialogAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'ErrorDialog',
    barrierColor: const Color(0xB8000000),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, _, __) => _ErrorDialog(
      errorCode: errorCode,
      title: title,
      body: body,
      technicalDetails: technicalDetails,
      canRetry: canRetry,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      // Custom entrance: translate + scale + skew + hue-rotate + shake.
      return _ErrorDialogEntrance(animation: anim, child: child);
    },
  );
  return result ?? ErrorDialogAction.back;
}

class _ErrorDialog extends StatelessWidget {
  final String errorCode;
  final String title;
  final String body;
  final String? technicalDetails;
  final bool canRetry;

  static const _bg = Color(0xFF0B1013);
  static const _cream = Color(0xFFF4EEE2);
  static const _dim = Color(0xFF9A968A);
  static const _borderCol = Color(0xFF252A31);
  static const _strongBorder = Color(0xFF353B45);
  static const _cyan = Color(0xFF22D3EE);
  static const _magenta = Color(0xFFE11D74);

  const _ErrorDialog({
    required this.errorCode,
    required this.title,
    required this.body,
    required this.technicalDetails,
    required this.canRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: _bg,
                border: Border.all(color: _borderCol, width: 1),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  // Outer glow — cyan + magenta dual halo (brand §5.3.3).
                  BoxShadow(
                    color: _cyan.withValues(alpha: 0.13),
                    blurRadius: 40,
                  ),
                  BoxShadow(
                    color: _magenta.withValues(alpha: 0.13),
                    blurRadius: 40,
                  ),
                  const BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 60,
                    offset: Offset(0, 20),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Grid overlay.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GridOverlayPainter(_cyan),
                      ),
                    ),
                  ),
                  // Scanline noise overlay.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ScanlinePainter(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Triangle icon with 3-layer chromatic ghost.
                        SizedBox(
                          width: 52,
                          height: 46,
                          child: Stack(
                            children: [
                              Transform.translate(
                                offset: const Offset(-2, 0),
                                child: Opacity(
                                  opacity: 0.75,
                                  child: CustomPaint(
                                    painter: _TrianglePainter(_cyan),
                                    size: const Size(52, 46),
                                  ),
                                ),
                              ),
                              Transform.translate(
                                offset: const Offset(2, 0),
                                child: Opacity(
                                  opacity: 0.75,
                                  child: CustomPaint(
                                    painter: _TrianglePainter(_magenta),
                                    size: const Size(52, 46),
                                  ),
                                ),
                              ),
                              CustomPaint(
                                painter: _TrianglePainter(_cream),
                                size: const Size(52, 46),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Title — RGB-split via 3-layer Stack (Flutter has
                        // no CSS `text-shadow` equivalent; Stack + Transform
                        // is the documented port).
                        _ChromaticTitle(title: title),
                        const SizedBox(height: 10),
                        // Error code chip — magenta bg, `>` prefix.
                        Container(
                          padding: const EdgeInsets.fromLTRB(9, 4, 9, 3),
                          decoration: BoxDecoration(
                            color: _magenta,
                            borderRadius: BorderRadius.circular(3),
                            boxShadow: [
                              BoxShadow(
                                color: _cyan.withValues(alpha: 0.2),
                                offset: const Offset(1, 0),
                              ),
                              BoxShadow(
                                color: _cyan.withValues(alpha: 0.2),
                                offset: const Offset(-1, 0),
                              ),
                            ],
                          ),
                          child: MonoText(
                            '> $errorCode',
                            style: LivebackTheme.monoTextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.66,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          body,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: _dim,
                            height: 1.65,
                          ),
                        ),
                        if (technicalDetails != null) ...[
                          const SizedBox(height: 12),
                          MonoText(
                            technicalDetails!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: LivebackTheme.monoTextStyle(
                              color: _dim.withValues(alpha: 0.6),
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                        const SizedBox(height: 22),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _dim,
                                  side: const BorderSide(
                                    color: _strongBorder,
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                onPressed: () => Navigator.of(context)
                                    .pop(ErrorDialogAction.back),
                                child: const Text('返回'),
                              ),
                            ),
                            if (canRetry) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _cream,
                                    foregroundColor: _bg,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  onPressed: () => Navigator.of(context)
                                      .pop(ErrorDialogAction.retry),
                                  child: const Text('重试'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// RGB-split title — JSX `text-shadow: -1.5px 0 cyan, 1.5px 0 magenta`
/// reproduced as 3 stacked Text widgets with translation offsets. The
/// main-text layer sits on top so anti-aliasing reads cleanly.
class _ChromaticTitle extends StatelessWidget {
  final String title;
  const _ChromaticTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: _ErrorDialog._cream,
      letterSpacing: -0.2,
      height: 1.2,
    );
    return Stack(
      children: [
        Transform.translate(
          offset: const Offset(-1.5, 0),
          child: Text(title,
              style: style.copyWith(color: _ErrorDialog._cyan)),
        ),
        Transform.translate(
          offset: const Offset(1.5, 0),
          child: Text(title,
              style: style.copyWith(color: _ErrorDialog._magenta)),
        ),
        Text(title, style: style),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;
  _TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 52;
    final sy = size.height / 46;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final tri = Path()
      ..moveTo(26 * sx, 6 * sy)
      ..lineTo(46 * sx, 40 * sy)
      ..lineTo(6 * sx, 40 * sy)
      ..close();
    canvas.drawPath(tri, stroke);
    canvas.drawLine(
      Offset(26 * sx, 16 * sy),
      Offset(26 * sx, 26 * sy),
      stroke..strokeWidth = 2.4,
    );
    canvas.drawCircle(
      Offset(26 * sx, 32 * sy),
      1.6,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter old) => old.color != color;
}

class _GridOverlayPainter extends CustomPainter {
  final Color accent;
  _GridOverlayPainter(this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = accent.withValues(alpha: 0.05);
    const step = 14.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridOverlayPainter old) =>
      old.accent != accent;
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x05FFFFFF);
    for (double y = 2; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter old) => false;
}

/// Entrance choreography — 320ms, matches `errorDialogIn` keyframes from
/// dialog.jsx. Can't reproduce CSS `hue-rotate` exactly; we approximate
/// it with a brief ColorFiltered pass during the first 30% of the
/// animation.
class _ErrorDialogEntrance extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _ErrorDialogEntrance({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, _) {
        final t = animation.value;
        // Keyframes @ 0 / 0.3 / 0.45 / 0.65 / 1 per dialog.jsx.
        double skewX;
        double translateX;
        double scale;
        if (t < 0.3) {
          final k = t / 0.3;
          skewX = _lerp(-0.0349, 0.0175, k); // radians: -2deg → +1deg
          translateX = _lerp(0, 4, k);
          scale = _lerp(0.96, 1.01, k);
        } else if (t < 0.45) {
          final k = (t - 0.3) / 0.15;
          skewX = _lerp(0.0175, 0, k);
          translateX = _lerp(4, -3, k);
          scale = _lerp(1.01, 1.0, k);
        } else if (t < 0.65) {
          final k = (t - 0.45) / 0.2;
          skewX = 0;
          translateX = _lerp(-3, 2, k);
          scale = 1.0;
        } else {
          final k = (t - 0.65) / 0.35;
          skewX = 0;
          translateX = _lerp(2, 0, k);
          scale = 1.0;
        }

        final m = Matrix4.identity()
          ..translateByDouble(translateX, 0.0, 0.0, 1.0)
          ..scaleByDouble(scale, scale, 1.0, 1.0)
          ..setEntry(0, 1, skewX);
        Widget content = Transform(
          alignment: Alignment.center,
          transform: m,
          child: child,
        );

        // Approximated hue-rotate via ColorFiltered (cyan tint early,
        // magenta tint mid, none by 45%). Keeps the "electrical" feel.
        if (t < 0.45) {
          final tint = t < 0.3
              ? const Color(0xFF22D3EE)
              : const Color(0xFFE11D74);
          final strength = (t < 0.3 ? 0.08 : 0.05) * (1 - t / 0.45);
          content = ColorFiltered(
            colorFilter: ColorFilter.mode(
              tint.withValues(alpha: strength.clamp(0, 1).toDouble()),
              BlendMode.overlay,
            ),
            child: content,
          );
        }

        return Opacity(opacity: t.clamp(0, 1).toDouble(), child: content);
      },
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}

