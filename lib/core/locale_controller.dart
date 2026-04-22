// Global locale controller. Settings page writes, LivebackApp listens.
// Persisted to SharedPreferences so the choice survives restarts.
//
// Values:
//   null → follow system (MaterialApp.localeResolutionCallback picks zh if
//          the device locale is zh-anything, else falls back to English).
//   Locale('en') → explicit English
//   Locale('zh') → explicit Simplified Chinese
//
// Mirrors the shape of ThemeModeController so both controllers behave
// symmetrically in _bootstrap() and in the settings picker.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kLocaleKey = 'liveback.locale';

class LocaleController {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  /// `null` = follow system; non-null = user's explicit choice.
  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  bool _loaded = false;

  /// Reads the persisted choice. Call once at app startup before the first
  /// MaterialApp build.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      locale.value = _parse(p.getString(_kLocaleKey));
    } catch (_) {
      // Fall back to system; settings can correct later.
    }
  }

  /// Persists and broadcasts a new choice. Pass `null` for "follow system".
  Future<void> setLocale(Locale? l) async {
    locale.value = l;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLocaleKey, _encode(l));
    } catch (_) {}
  }

  static Locale? _parse(String? raw) => switch (raw) {
        'en' => const Locale('en'),
        'zh' => const Locale('zh'),
        'system' => null,
        _ => null,
      };

  static String _encode(Locale? l) => switch (l?.languageCode) {
        'en' => 'en',
        'zh' => 'zh',
        _ => 'system',
      };
}
