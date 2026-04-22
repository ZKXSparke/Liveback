// Global theme-mode controller. Settings page writes, LivebackApp listens.
// Persisted to SharedPreferences so the choice survives restarts.
//
// Values: system (default — follow OS) / light / dark.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kThemeModeKey = 'liveback.theme_mode';

class ThemeModeController {
  ThemeModeController._();
  static final ThemeModeController instance = ThemeModeController._();

  final ValueNotifier<ThemeMode> mode =
      ValueNotifier<ThemeMode>(ThemeMode.system);

  bool _loaded = false;

  /// Reads the persisted choice. Call once at app startup.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kThemeModeKey);
      mode.value = _parse(raw) ?? ThemeMode.system;
    } catch (_) {
      // Fall back to system; settings can correct later.
    }
  }

  /// Persists and broadcasts a new choice.
  Future<void> setMode(ThemeMode m) async {
    mode.value = m;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kThemeModeKey, _encode(m));
    } catch (_) {}
  }

  static ThemeMode? _parse(String? raw) => switch (raw) {
        'system' => ThemeMode.system,
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => null,
      };

  static String _encode(ThemeMode m) => switch (m) {
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
      };
}
