// Owner: T3 (UI teammate). Reference: brand §5.2 failed-task row swipe
// reveal — "重试" button. Also used by ResultPage on failure states.

import 'package:flutter/material.dart';

import 'theme_access.dart';

class RetryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double verticalPadding;
  final double fontSize;

  const RetryButton({
    super.key,
    required this.onPressed,
    this.verticalPadding = 10,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.accent,
        side: BorderSide(color: c.accent, width: 1),
        backgroundColor: c.bg,
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: verticalPadding,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      onPressed: onPressed,
      child: const Text('重试'),
    );
  }
}
