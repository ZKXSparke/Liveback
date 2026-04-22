// Smoke test for LocaleController round-trip through SharedPreferences.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveback/core/locale_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults to null (system-follow) when no key persisted', () async {
    final c = LocaleController.instance;
    // Reset the singleton's internal loaded flag by writing directly.
    c.locale.value = null;
    await c.load();
    expect(c.locale.value, isNull);
  });

  test('setLocale(en) persists and broadcasts', () async {
    final c = LocaleController.instance;
    await c.setLocale(const Locale('en'));
    expect(c.locale.value, const Locale('en'));
    final p = await SharedPreferences.getInstance();
    expect(p.getString('liveback.locale'), 'en');
  });

  test('setLocale(zh) persists and broadcasts', () async {
    final c = LocaleController.instance;
    await c.setLocale(const Locale('zh'));
    expect(c.locale.value, const Locale('zh'));
    final p = await SharedPreferences.getInstance();
    expect(p.getString('liveback.locale'), 'zh');
  });

  test('setLocale(null) encodes system', () async {
    final c = LocaleController.instance;
    await c.setLocale(null);
    expect(c.locale.value, isNull);
    final p = await SharedPreferences.getInstance();
    expect(p.getString('liveback.locale'), 'system');
  });
}
