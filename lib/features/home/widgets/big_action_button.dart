// Owner: T3 (UI teammate). Reference: brand §5.1 primary CTA + §7 breathing
// animation (scale 1.0↔1.015, 3s period). JSX home.jsx#primary button.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../widgets/theme_access.dart';

class BigActionButton extends StatefulWidget {
  final String title;
  final String subtitle;
  final VoidCallback onPressed;

  const BigActionButton({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  @override
  State<BigActionButton> createState() => _BigActionButtonState();
}

class _BigActionButtonState extends State<BigActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _breath,
      builder: (ctx, _) {
        final t = _breath.value * 2 * math.pi;
        final scale = 1 + (0.015 / 2) * (1 - math.cos(t));
        return Transform.scale(
          scale: scale,
          child: Material(
            color: c.ink,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onPressed,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: c.bg,
                              letterSpacing: -0.255,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: c.bg.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _ArrowBadge(bg: c.bg, ink: c.ink),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

}

class _ArrowBadge extends StatelessWidget {
  final Color bg;
  final Color ink;
  const _ArrowBadge({required this.bg, required this.ink});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(Icons.arrow_forward, size: 18, color: ink),
    );
  }
}
