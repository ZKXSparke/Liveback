// Owner: T3 (UI teammate). Reference: brand §4 (font stack) + Doc 1 §3.
//
// Thin wrapper over [Text] that applies the JetBrains Mono family via
// [LivebackTheme.monoTextStyle]. Used wherever brand §4 requires mono:
// file sizes, elapsed ms, hex dumps, error-code chips, FIXED counter.

import 'package:flutter/material.dart';

import '../core/theme.dart';

class MonoText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;

  const MonoText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final base = LivebackTheme.monoTextStyle();
    return Text(
      text,
      style: base.merge(style),
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
    );
  }
}
