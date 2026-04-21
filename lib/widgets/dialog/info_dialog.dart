// Owner: T3 (UI teammate). Reference: brand §5.3.1 InfoDialog + JSX
// design-v2/project/components/dialog.jsx#InfoDialog.
//
// Thin-circle "i" icon, single "知道了" CTA, optional "不再提醒" checkbox.
// Used for first-run "保持应用打开直至完成" notice (brand §6 · 首次处理警告).

import 'package:flutter/material.dart';

import '../mono_text.dart';
import '../theme_access.dart';
import 'overlay.dart';

/// Outcome of an [InfoDialog] — tuple of (acknowledged, dontAskAgain).
class InfoDialogResult {
  /// Always true when the dialog is resolved by tapping the CTA — the
  /// InfoDialog has a single button, so dismissal without it returns
  /// [InfoDialogResult.dismissed] (checkbox preserved in case).
  final bool acknowledged;
  final bool dontAskAgain;
  const InfoDialogResult({
    required this.acknowledged,
    required this.dontAskAgain,
  });
  static const dismissed = InfoDialogResult(
    acknowledged: false,
    dontAskAgain: false,
  );
}

/// Shows a dialog and awaits the user's CTA. Returns
/// [InfoDialogResult.dismissed] if the user presses back / system gesture.
Future<InfoDialogResult> showInfoDialog(
  BuildContext context, {
  required String title,
  required String body,
  String? checkboxLabel,
  String confirmText = '知道了',
}) async {
  final result = await showGeneralDialog<InfoDialogResult>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'InfoDialog',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, __) => _InfoDialog(
      title: title,
      body: body,
      checkboxLabel: checkboxLabel,
      confirmText: confirmText,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final curve = CurvedAnimation(
        parent: anim,
        curve: const Cubic(0.2, 0.9, 0.3, 1),
      );
      return FadeTransition(
        opacity: anim,
        child: Transform.translate(
          offset: Offset(0, (1 - curve.value) * 12),
          child: Transform.scale(scale: 0.98 + 0.02 * curve.value, child: child),
        ),
      );
    },
  );
  return result ?? InfoDialogResult.dismissed;
}

class _InfoDialog extends StatefulWidget {
  final String title;
  final String body;
  final String? checkboxLabel;
  final String confirmText;

  const _InfoDialog({
    required this.title,
    required this.body,
    required this.checkboxLabel,
    required this.confirmText,
  });

  @override
  State<_InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<_InfoDialog> {
  bool _dontAskAgain = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LivebackDialogOverlay(
      maxWidth: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thin-circle "i" icon.
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.inkDim, width: 1.8),
            ),
            alignment: Alignment.center,
            child: MonoText(
              'i',
              style: LivebackTheme.monoTextStyle(
                color: c.inkDim,
                fontSize: 22,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: c.ink,
              letterSpacing: -0.085,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.body,
            style: TextStyle(
              fontSize: 13.5,
              color: c.inkDim,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 18),
          if (widget.checkboxLabel != null) ...[
            _Checkbox(
              label: widget.checkboxLabel!,
              checked: _dontAskAgain,
              onChanged: (v) => setState(() => _dontAskAgain = v),
            ),
            const SizedBox(height: 18),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.ink,
                foregroundColor: c.bg,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: () => Navigator.of(context).pop(
                InfoDialogResult(
                  acknowledged: true,
                  dontAskAgain: _dontAskAgain,
                ),
              ),
              child: Text(widget.confirmText),
            ),
          ),
        ],
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  final String label;
  final bool checked;
  final ValueChanged<bool> onChanged;

  const _Checkbox({
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () => onChanged(!checked),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: checked ? c.ink : Colors.transparent,
              border: Border.all(
                color: checked ? c.ink : c.borderStrong,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: checked
                ? Icon(Icons.check, color: c.bg, size: 12)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontSize: 12.5, color: c.inkDim),
          ),
        ],
      ),
    );
  }
}
