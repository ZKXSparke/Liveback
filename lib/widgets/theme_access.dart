// Owner: T3 (UI teammate). Reference: Doc 1 §3 theme system (canonical
// `context.colors` shorthand).
//
// Lightweight accessor extension for the [LivebackColors] ThemeExtension.
// Lives here (not in core/theme.dart) because core/theme.dart is frozen
// SSoT maintained alongside the architecture spec. This extension is pure
// T3 syntactic sugar and stays in the widgets layer.

import 'package:flutter/material.dart';

import '../core/theme.dart';

export '../core/theme.dart' show LivebackColors, LivebackTheme;

extension LivebackThemeAccess on BuildContext {
  /// Read the palette; throws if no theme has been pumped (i.e. widget
  /// test without MaterialApp). Use [maybeColors] in those environments.
  LivebackColors get colors =>
      Theme.of(this).extension<LivebackColors>()!;

  /// Null-safe variant.
  LivebackColors? get maybeColors =>
      Theme.of(this).extension<LivebackColors>();
}
