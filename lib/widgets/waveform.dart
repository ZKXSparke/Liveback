// Owner: T3 (UI teammate). Reference: brand §5.4 + JSX
// design-v2/project/components/waveform.jsx (VERBATIM behavior port).
//
// Three states: clean | broken | scanning. Scanning state is the brand
// centerpiece — "无序 → 错误 → 正常" narrative encoded in a 1800ms
// left-to-right chromatic scanhead. Per brand §3 chromaCyan/chromaMagenta
// only appear on: broken state, scanning state, ErrorDialog, app icon.
//
// Algorithm match with JSX:
//  - 64 base samples via seeded RNG (see [_makeWave]), layered sine waves
//    + small noise jitter, amplitude 0.85.
//  - broken variant: ~12% null gap, ~10% large spike, rest 0.6-1.0 scale.
//  - toPath: pen-up across null gaps.
//  - scanning: right-of-head = broken × {cyan -1.8px, magenta +1.8px,
//    dim main}; left-of-head = clean cream line; head = cyan -1.5 + main
//    + magenta +1.5 tri-split + 2px dot + 32px cyan fade band in front.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Render states for the Liveback waveform.
enum WaveformState { clean, broken, scanning }

/// A custom-painted waveform with three brand states (see [WaveformState]).
///
/// [color] is the primary stroke color (cream on dark, ink on light), [dim]
/// is the muted-line color used for dashed midline / unrepaired body. The
/// chroma defaults come from the ambient [LivebackColors] extension; pass
/// explicit values only when the parent owns its own palette (e.g. the
/// ErrorDialog which is cross-mode dark).
///
/// When [state] == [WaveformState.scanning] the widget drives its own
/// [AnimationController] at 1800ms linear period. Parents don't need to
/// feed progress externally; they can override via [progressOverride] to
/// force a static frame (useful in widget tests).
class Waveform extends StatefulWidget {
  final double width;
  final double height;
  final int seed;
  final WaveformState state;
  final Color? color;
  final Color? dim;
  final Color? chromaCyan;
  final Color? chromaMagenta;
  final bool showGrid;

  /// Optional static scan progress (0..1). When null in scanning state the
  /// widget animates internally. Unused in clean/broken states.
  final double? progressOverride;

  const Waveform({
    super.key,
    this.width = 280,
    this.height = 38,
    this.seed = 1001,
    this.state = WaveformState.clean,
    this.color,
    this.dim,
    this.chromaCyan,
    this.chromaMagenta,
    this.showGrid = true,
    this.progressOverride,
  });

  @override
  State<Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan;

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.state == WaveformState.scanning &&
        widget.progressOverride == null) {
      _scan.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant Waveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == WaveformState.scanning &&
        widget.progressOverride == null) {
      if (!_scan.isAnimating) _scan.repeat();
    } else {
      _scan.stop();
    }
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<LivebackColors>();
    final color = widget.color ?? palette?.ink ?? const Color(0xFF0B1013);
    final dim = widget.dim ?? palette?.inkFaint ?? const Color(0xFF8F8B80);
    final cyan = widget.chromaCyan ??
        palette?.chromaCyan ??
        const Color(0xFF22D3EE);
    final magenta = widget.chromaMagenta ??
        palette?.chromaMagenta ??
        const Color(0xFFE11D74);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _scan,
        builder: (context, _) {
          final p = widget.progressOverride ?? _scan.value;
          return CustomPaint(
            size: Size(widget.width, widget.height),
            painter: _WaveformPainter(
              seed: widget.seed,
              state: widget.state,
              color: color,
              dim: dim,
              chromaCyan: cyan,
              chromaMagenta: magenta,
              showGrid: widget.showGrid,
              progress: p,
            ),
          );
        },
      ),
    );
  }
}


class _WaveformPainter extends CustomPainter {
  static const int _n = 64;

  final int seed;
  final WaveformState state;
  final Color color;
  final Color dim;
  final Color chromaCyan;
  final Color chromaMagenta;
  final bool showGrid;
  final double progress;

  late final List<double> _base;
  late final List<double?> _broken;
  late final List<int> _gapDots;

  _WaveformPainter({
    required this.seed,
    required this.state,
    required this.color,
    required this.dim,
    required this.chromaCyan,
    required this.chromaMagenta,
    required this.showGrid,
    required this.progress,
  }) {
    _base = _makeWave(seed, _n, 0.85);
    _broken = _breakWave(_base, seed);
    _gapDots = [
      for (int i = 0; i < _broken.length; i++)
        if (_broken[i] == null) i,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final step = size.width / (_n - 1);

    Path pathOf(List<double?> arr) {
      final path = Path();
      bool penUp = true;
      for (int i = 0; i < arr.length; i++) {
        final v = arr[i];
        if (v == null) {
          penUp = true;
          continue;
        }
        final x = i * step;
        final y = mid - v * (size.height * 0.42);
        if (penUp) {
          path.moveTo(x, y);
          penUp = false;
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    final cleanPath = pathOf(_base.map<double?>((v) => v).toList());
    final brokenPath = pathOf(_broken);
    final scanX = progress * size.width;

    if (showGrid) {
      _drawDashedMid(canvas, size, mid, dim);
    }

    if (state == WaveformState.clean) {
      canvas.drawPath(
        cleanPath,
        Paint()
          ..color = color
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      return;
    }

    if (state == WaveformState.broken) {
      // cyan ghost (-1px, 0.35 opacity)
      canvas.save();
      canvas.translate(-1, 0);
      canvas.drawPath(
        brokenPath,
        Paint()
          ..color = chromaCyan.withValues(alpha: 0.35)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
      // magenta ghost (+1px, 0.35 opacity)
      canvas.save();
      canvas.translate(1, 0);
      canvas.drawPath(
        brokenPath,
        Paint()
          ..color = chromaMagenta.withValues(alpha: 0.35)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
      // main body
      canvas.drawPath(
        brokenPath,
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..strokeWidth = 1.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      for (final i in _gapDots) {
        canvas.drawCircle(
          Offset(i * step, mid),
          1,
          Paint()..color = color.withValues(alpha: 0.45),
        );
      }
      return;
    }

    // scanning state
    // Right-of-head unrepaired region: clip right half, draw broken ×3.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(
      scanX.clamp(0, size.width),
      0,
      size.width,
      size.height,
    ));
    // cyan ghost (-1.8px, 0.75 opacity)
    canvas.save();
    canvas.translate(-1.8, 0);
    canvas.drawPath(
      brokenPath,
      Paint()
        ..color = chromaCyan.withValues(alpha: 0.75)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final i in _gapDots) {
      canvas.drawCircle(
        Offset(i * step, mid),
        1,
        Paint()..color = chromaCyan.withValues(alpha: 0.6),
      );
    }
    canvas.restore();
    // magenta ghost (+1.8px, 0.75 opacity)
    canvas.save();
    canvas.translate(1.8, 0);
    canvas.drawPath(
      brokenPath,
      Paint()
        ..color = chromaMagenta.withValues(alpha: 0.75)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final i in _gapDots) {
      canvas.drawCircle(
        Offset(i * step, mid),
        1,
        Paint()..color = chromaMagenta.withValues(alpha: 0.6),
      );
    }
    canvas.restore();
    // dim main body
    canvas.drawPath(
      brokenPath,
      Paint()
        ..color = dim.withValues(alpha: 0.65)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    for (final i in _gapDots) {
      canvas.drawCircle(
        Offset(i * step, mid),
        1,
        Paint()..color = dim.withValues(alpha: 0.55),
      );
    }
    canvas.restore();

    // Left-of-head repaired region: clip left half, draw clean cream line.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, scanX.clamp(0, size.width), size.height));
    canvas.drawPath(
      cleanPath,
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    // 32px cyan fade band preceding the scan head.
    final bandStart = math.max(0.0, scanX - 32);
    final bandEnd = scanX.clamp(0.0, size.width);
    if (bandEnd > bandStart) {
      final bandRect = Rect.fromLTWH(
        bandStart,
        0,
        bandEnd - bandStart,
        size.height,
      );
      final fade = LinearGradient(
        colors: [
          chromaCyan.withValues(alpha: 0),
          chromaCyan.withValues(alpha: 0.12),
          chromaCyan.withValues(alpha: 0.32),
        ],
        stops: const [0, 0.7, 1],
      ).createShader(bandRect);
      canvas.drawRect(bandRect, Paint()..shader = fade);
    }

    // Tri-split scan head: cyan -1.5, main, magenta +1.5 + dot.
    final headCyanPaint = Paint()
      ..color = chromaCyan.withValues(alpha: 0.85)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final headMagentaPaint = Paint()
      ..color = chromaMagenta.withValues(alpha: 0.85)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    final headMainPaint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(scanX - 1.5, 1),
      Offset(scanX - 1.5, size.height - 1),
      headCyanPaint,
    );
    canvas.drawLine(
      Offset(scanX + 1.5, 1),
      Offset(scanX + 1.5, size.height - 1),
      headMagentaPaint,
    );
    canvas.drawLine(
      Offset(scanX, 0),
      Offset(scanX, size.height),
      headMainPaint,
    );
    canvas.drawCircle(Offset(scanX, mid), 2, Paint()..color = color);
  }

  void _drawDashedMid(Canvas canvas, Size size, double mid, Color c) {
    final paint = Paint()
      ..color = c.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    const dash = 1.5;
    const gap = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, mid), Offset(x + dash, mid), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress ||
      old.state != state ||
      old.seed != seed ||
      old.color != color ||
      old.dim != dim ||
      old.chromaCyan != chromaCyan ||
      old.chromaMagenta != chromaMagenta;
}

/// Seeded RNG: matches theme.jsx `seeded(seed)` port — LCG with the
/// same 1664525 / 1013904223 constants for cross-prototype parity.
class _SeededRng {
  int _s;
  _SeededRng(int seed) : _s = seed >>> 0;
  double next() {
    _s = (_s * 1664525 + 1013904223) & 0xffffffff;
    return (_s & 0xffffff) / 0xffffff;
  }
}

List<double> _makeWave(int seed, int n, double amp) {
  final rng = _SeededRng(seed);
  final f1 = 0.08 + rng.next() * 0.05;
  final f2 = 0.22 + rng.next() * 0.08;
  final f3 = 0.4 + rng.next() * 0.1;
  final p1 = rng.next() * 6.28;
  final p2 = rng.next() * 6.28;
  final p3 = rng.next() * 6.28;
  final out = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    final v = math.sin(i * f1 + p1) * 0.55 +
        math.sin(i * f2 + p2) * 0.28 +
        math.sin(i * f3 + p3) * 0.14 +
        (rng.next() - 0.5) * 0.08;
    out[i] = (v * amp).clamp(-1, 1);
  }
  return out;
}

List<double?> _breakWave(List<double> wave, int seed) {
  final rng = _SeededRng(seed + 1);
  return [
    for (final v in wave)
      () {
        final r = rng.next();
        if (r < 0.12) return null;
        if (r < 0.22) return (rng.next() - 0.5) * 1.6;
        return v * (0.6 + rng.next() * 0.4);
      }()
  ];
}
