// Owner: T3 (UI teammate). Reference: brand §5.3.2 ConfirmDialog + JSX
// design-v2/project/components/dialog.jsx#ConfirmDialog.
//
// Amber triangle icon, two buttons (secondary outlined + primary filled).
// `destructive` flag → primary button uses chromaMagenta (danger palette).
// Used for "取消全部任务？" confirmation.

import 'package:flutter/material.dart';

import '../theme_access.dart';
import 'overlay.dart';

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  String cancelText = '取消',
  String confirmText = '确认',
  bool destructive = true,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'ConfirmDialog',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => _ConfirmDialog(
      title: title,
      body: body,
      cancelText: cancelText,
      confirmText: confirmText,
      destructive: destructive,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: anim,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * 12),
          child: child,
        ),
      );
    },
  );
  return result ?? false;
}

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String body;
  final String cancelText;
  final String confirmText;
  final bool destructive;

  const _ConfirmDialog({
    required this.title,
    required this.body,
    required this.cancelText,
    required this.confirmText,
    required this.destructive,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LivebackDialogOverlay(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: CustomPaint(
              size: const Size(38, 38),
              painter: _WarnTrianglePainter(c.warn),
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.ink,
              letterSpacing: -0.085,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: TextStyle(
              fontSize: 13.5,
              color: c.inkDim,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.inkDim,
                    side: BorderSide(color: c.borderStrong, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(cancelText),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        destructive ? c.chromaMagenta : c.ink,
                    foregroundColor:
                        destructive ? Colors.white : c.bg,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(confirmText),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WarnTrianglePainter extends CustomPainter {
  final Color color;
  _WarnTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Scale 40x40 reference viewbox into size.
    final sx = size.width / 40;
    final sy = size.height / 40;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fill = Paint()..color = color;

    final tri = Path()
      ..moveTo(20 * sx, 5 * sy)
      ..lineTo(37 * sx, 34 * sy)
      ..lineTo(3 * sx, 34 * sy)
      ..close();
    canvas.drawPath(tri, stroke);
    canvas.drawLine(
      Offset(20 * sx, 15 * sy),
      Offset(20 * sx, 23 * sy),
      stroke..strokeWidth = 2.4,
    );
    canvas.drawCircle(Offset(20 * sx, 28 * sy), 1.4, fill);
  }

  @override
  bool shouldRepaint(covariant _WarnTrianglePainter old) => old.color != color;
}
