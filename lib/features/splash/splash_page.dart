// Splash route. Sits between the Android 12+ system splash (which shows
// a solid brand-colored background seamlessly) and the Home page.
//
// Animation timeline (2200 ms total). Start is deferred to the first
// post-frame callback so the animation begins AFTER the system splash
// has actually handed off to Flutter — otherwise Android 12+'s cold-start
// hold eats the intro and early scan phases, and the user only sees the
// tail end of the sweep.
//
//   0–400 ms  : fade in, wordmark fully broken (scan held at x = 0,
//               heavy chromatic).
//   400–1600  : scan head sweeps left → right, repairing as it goes.
//   1600–1900 : hold on clean wordmark.
//   1900–2200 : fade + 8 px upward slide → HomePage via
//               Navigator.pushReplacement.
//
// The splash is always-dark (editorial): background is the ink slate
// #0B1013 regardless of system dark-mode setting, so the glitch repair
// reads as a product-native motion. HomePage's AnnotatedRegion re-applies
// themed status bar chrome on mount.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'widgets/glitch_wordmark.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  // Phase boundaries as fractions of the 2200 ms timeline.
  static const _introEnd = 400 / 2200;
  static const _scanEnd = 1600 / 2200;
  static const _holdEnd = 1900 / 2200;
  // total = 1.0

  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && !_navigated) {
          _navigated = true;
          Navigator.of(context).pushReplacementNamed('/home');
        }
      });
    // Start the animation on the next frame boundary, not in initState.
    // initState runs while the engine is still completing its first
    // layout pass — and on cold launch the Android 12+ system splash
    // continues to cover the Flutter surface for several hundred
    // milliseconds after that. Kicking the controller off from the
    // post-frame callback guarantees the intro phase is actually on
    // screen when it advances.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Force-dark chrome during splash regardless of system dark-mode.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF0B1013),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF0B1013),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarDividerColor: Color(0xFF0B1013),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1013),
        body: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final t = _c.value;

            // Intro fade-in opacity (0 → 1 across 0-200ms).
            final introOpacity =
                (t / _introEnd).clamp(0.0, 1.0);

            // Scan progress: broken-held before intro ends, then sweeps
            // through scan phase, then clean-held.
            double scanProgress;
            if (t <= _introEnd) {
              scanProgress = 0.0;
            } else if (t <= _scanEnd) {
              final phaseT = (t - _introEnd) / (_scanEnd - _introEnd);
              scanProgress = Curves.easeInOutCubic.transform(phaseT);
            } else {
              scanProgress = 1.0;
            }

            // Outro: slide up + fade out between holdEnd and 1.0.
            double outOpacity;
            double slideDy;
            if (t <= _holdEnd) {
              outOpacity = 1.0;
              slideDy = 0.0;
            } else {
              final phaseT = (t - _holdEnd) / (1.0 - _holdEnd);
              outOpacity = 1.0 - Curves.easeInCubic.transform(phaseT);
              slideDy = -8.0 * Curves.easeInCubic.transform(phaseT);
            }

            return Opacity(
              opacity: introOpacity * outOpacity,
              child: Transform.translate(
                offset: Offset(0, slideDy),
                child: Center(
                  child: GlitchWordmark(
                    progress: scanProgress,
                    text: 'Liveback',
                    fontSize: 84,
                    maxChromaOffset: 5,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
