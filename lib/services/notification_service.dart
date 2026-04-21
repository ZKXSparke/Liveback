// Owner: T2 (Android platform teammate). Reference: Doc 1 §A.7 + Doc 3 §7.
// DO NOT edit signatures without an architecture amendment.
//
// Wraps `flutter_local_notifications`. Channel is created in [init] via
// AndroidFlutterLocalNotificationsPlugin.createNotificationChannel (Doc 3
// §7 — we chose Option B, Dart-side creation). postBatchComplete MUST
// consult AppLifecycle.isForeground and no-op when the app is resumed
// (v1.1 §3.1 F6 + review B8).

class NotificationService {
  /// Creates the batch-complete channel. Idempotent — safe to call on
  /// every cold start.
  Future<void> init() {
    throw UnimplementedError('T2 — Doc 3 §7 (NotificationService.init)');
  }

  /// Returns true iff the user has granted POST_NOTIFICATIONS (Android
  /// 13+) OR we are on <= API 32 where the permission is implicit.
  /// Prompts the user on first denial.
  Future<bool> ensurePermission() {
    throw UnimplementedError('T2 — Doc 3 §6 (ensurePermission)');
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
  }) {
    throw UnimplementedError('T2 — Doc 3 §7 (postBatchComplete)');
  }

  /// Channel identifier — must match the one declared to
  /// flutter_local_notifications. Duplicated from
  /// `LivebackConstants.notificationChannelId` on purpose, so this class
  /// remains `LivebackConstants`-free at import time.
  static const channelId = 'liveback.batch_complete';
  static const channelName = '批次处理完成';
}
