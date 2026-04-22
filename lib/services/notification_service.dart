// Owner: T2 (Android platform teammate). Reference: Doc 1 §A.7 + Doc 3 §7.
// DO NOT edit signatures without an architecture amendment.
//
// Wraps `flutter_local_notifications`. Channel is created in [init] via
// AndroidFlutterLocalNotificationsPlugin.createNotificationChannel (Doc 3
// §7 — we chose Option B, Dart-side creation). postBatchComplete MUST
// consult AppLifecycle.isForeground and no-op when the app is resumed
// (v1.1 §3.1 F6 + review B8).
//
// i18n: channel display name / description and the batch-complete body
// are localized. Because this service has no BuildContext, it resolves
// copy against the APP's current locale (derived from the persisted
// LocaleController) and the system fallback when no explicit choice is
// set. Use `AppL10n.delegate.load(locale)` to materialize a localized
// table on demand — see [_loadL10n] below.

import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/app_lifecycle.dart';
import '../core/locale_controller.dart';
import '../l10n/generated/app_localizations.dart';

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  /// Creates the batch-complete channel. Idempotent — safe to call on
  /// every cold start.
  ///
  /// Channel attributes (Doc 3 §7):
  ///   importance        = defaultImportance
  ///   enableVibration   = true
  ///   vibrationPattern  = [0, 200]
  ///   enableLights      = false
  ///   setShowBadge      = false
  Future<void> init() async {
    if (_initialized) return;

    // Use the app launcher as the notification small icon. Adding a
    // dedicated monochrome notification icon is a T3 asset task (brand §5).
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final l = await _loadL10n();
      final channel = AndroidNotificationChannel(
        channelId,
        l.notificationChannelName,
        description: l.notificationChannelDescription,
        importance: Importance.defaultImportance,
        enableVibration: true,
        playSound: true,
        showBadge: false,
      );
      await androidImpl.createNotificationChannel(channel);
    }

    _initialized = true;
  }

  /// Picks the locale that best reflects the user's current preference:
  ///   * LocaleController.instance.locale (non-null ⇒ explicit choice)
  ///   * else PlatformDispatcher.instance.locale (system default)
  ///     mapped through the same zh-else-en policy MaterialApp uses.
  Future<AppL10n> _loadL10n() async {
    final explicit = LocaleController.instance.locale.value;
    final Locale target;
    if (explicit != null) {
      target = explicit;
    } else {
      final system = PlatformDispatcher.instance.locale;
      target = system.languageCode == 'zh'
          ? const Locale('zh')
          : const Locale('en');
    }
    return AppL10n.delegate.load(target);
  }

  /// Returns true iff the user has granted POST_NOTIFICATIONS (Android
  /// 13+) OR we are on <= API 32 where the permission is implicit.
  /// Prompts the user on first denial.
  Future<bool> ensurePermission() async {
    await init();
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl == null) return false;

    // `areNotificationsEnabled` checks the system-level state (both the
    // runtime permission on 13+ AND the channel-level "block"). Short-
    // circuit if we already have it.
    final alreadyEnabled = await androidImpl.areNotificationsEnabled() ?? false;
    if (alreadyEnabled) return true;

    // Request on Android 13+. No-op / returns null on earlier APIs where
    // POST_NOTIFICATIONS is an implicit grant.
    final granted = await androidImpl.requestNotificationsPermission();
    return granted ?? false;
  }

  /// Posts the batch-complete notification.
  ///
  /// No-op iff [AppLifecycle.isForeground] is true at call time (the
  /// UI is already showing the result, so the notification would be
  /// duplicative — v1.1 F6 + review B8).
  Future<void> postBatchComplete({
    required int success,
    required int failed,
    required int skipped,
  }) async {
    if (AppLifecycle.isForeground) return;
    await init();

    final l = await _loadL10n();
    final body = _formatBody(
      l,
      success: success,
      failed: failed,
      skipped: skipped,
    );

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        l.notificationChannelName,
        channelDescription: l.notificationChannelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        enableVibration: true,
        playSound: true,
        // vibrationPattern is a Int64List; omit here and let the channel-
        // level config drive it (simpler and avoids per-post allocation).
      ),
    );

    await _plugin.show(
      _kBatchCompleteNotificationId,
      'Liveback',
      body,
      details,
    );
  }

  String _formatBody(
    AppL10n l, {
    required int success,
    required int failed,
    required int skipped,
  }) {
    // Brand §5: join non-zero categories. Locale decides the separator
    // via intl's Intl.message / list formatting — for MVP we join with
    // a comma (localized punctuation; en uses ", " and zh uses "，").
    final parts = <String>[];
    if (success > 0) parts.add(l.notificationBatchFragmentSuccess(success));
    if (failed > 0) parts.add(l.notificationBatchFragmentFailed(failed));
    if (skipped > 0) parts.add(l.notificationBatchFragmentSkipped(skipped));
    if (parts.isEmpty) return l.notificationBatchDefault;
    // Use locale-aware separator: zh uses fullwidth comma, en uses
    // ascii comma + space.
    final sep = l.localeName.startsWith('zh') ? '，' : ', ';
    return parts.join(sep);
  }

  // Fixed notification id — we only post one batch-complete at a time.
  static const int _kBatchCompleteNotificationId = 1;

  /// Channel identifier — must match the one declared to
  /// flutter_local_notifications. Duplicated from
  /// `LivebackConstants.notificationChannelId` on purpose, so this class
  /// remains `LivebackConstants`-free at import time.
  static const channelId = 'liveback.batch_complete';
}
