// Owner: T3 (UI teammate). Reference: brand §5.3 dialog shell + JSX
// design-v2/project/components/dialog.jsx#Overlay.
//
// Shared dialog container used by InfoDialog and ConfirmDialog. ErrorDialog
// rolls its own shell because brand §5.3.3 requires ALWAYS-dark colors and
// extra overlay effects (grid + scanlines) that this generic shell doesn't
// carry.

import 'package:flutter/material.dart';

import '../theme_access.dart';

/// Standard editorial dialog card (white/dark card, 18px radius, subtle
/// drop shadow). Pumps its content into a fixed max-width container
/// centered on the screen.
class LivebackDialogOverlay extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const LivebackDialogOverlay({
    super.key,
    required this.child,
    this.maxWidth = 340,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.border, width: 1),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 60,
                    offset: Offset(0, 20),
                    color: Color(0x40000000),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
