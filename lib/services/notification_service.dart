// Owner: T2 (Android platform teammate). Reference: Doc 1 §A.7 + Doc 3 §7.
// DO NOT edit signatures without an architecture amendment.
//
// Wraps `flutter_local_notifications`. Channel is created in [init] via
// AndroidFlutterLocalNotificationsPlugin.createNotificationChannel (Doc 3
// §7 — we chose Option B, Dart-side creation). postBatchComplete MUST
// consult AppLifecycle.isForeground and no-op when the app is resumed
// (v1.1 §3.1 F6 + review B8).

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/app_lifecycle.dart';

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
      const channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: 'Liveback 处理一批实况图后推送',
        importance: Importance.defaultImportance,
        enableVibration: true,
        playSound: true,
        showBadge: false,
      );
      await androidImpl.createNotificationChannel(channel);
    }

    _initialized = true;
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

    final body = _formatBody(success: success, failed: failed, skipped: skipped);

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Liveback 处理一批实况图后推送',
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

  String _formatBody({
    required int success,
    required int failed,
    required int skipped,
  }) {
    // Brand §5: "X 张已修复，Y 张失败，Z 张跳过". Omit zero categories to
    // keep the line short.
    final parts = <String>[];
    if (success > 0) parts.add('$success 张已修复');
    if (failed > 0) parts.add('$failed 张失败');
    if (skipped > 0) parts.add('$skipped 张跳过');
    if (parts.isEmpty) return '批次处理完成';
    return parts.join('，');
  }

  // Fixed notification id — we only post one batch-complete at a time.
  static const int _kBatchCompleteNotificationId = 1;

  /// Channel identifier — must match the one declared to
  /// flutter_local_notifications. Duplicated from
  /// `LivebackConstants.notificationChannelId` on purpose, so this class
  /// remains `LivebackConstants`-free at import time.
  static const channelId = 'liveback.batch_complete';
  static const channelName = '批次处理完成';
}
