// Owner: shared (Phase 1 SSoT). Reference: Doc 1 §A.10.
// DO NOT edit without an architecture amendment.
//
// All cross-module compile-time constants live here. Teams MUST NOT hardcode
// any of these values in their own modules — read them from LivebackConstants.

/// Compile-time constants shared across services, platform wrappers, and UI.
abstract class LivebackConstants {
  // ---- Filesystem ----

  /// Subdirectory under the app's cache dir that holds the Plan A
  /// copy-through sandbox (`cache/liveback-io/in-<taskId>.jpg` +
  /// `out-<taskId>.jpg`). See Doc 3 §3 for the sandbox protocol.
  static const String sandboxSubdir = 'liveback-io';

  /// MediaStore `RELATIVE_PATH` where successfully-fixed outputs are
  /// published. Doc 3 §2.5 writes this into
  /// `MediaStore.Images.Media.RELATIVE_PATH`.
  static const String publicOutputFolder = 'Pictures/Liveback/';

  // ---- Filename template ----

  /// Output file display name, e.g. `Liveback_20260421_150530.jpg`.
  /// [dt] MUST be the timestamp carried on `FixResult.dateTakenMs`
  /// (Doc 1 §A.1): EXIF DateTimeOriginal, or `DateTime.now()` as fallback.
  ///
  /// See Doc 3 §2.5's ownership table — this display name and the
  /// MediaStore DATE_TAKEN column share the same source-of-truth timestamp.
  static String outputFileName(DateTime dt) =>
      'Liveback_${_pad(dt.year, 4)}${_pad(dt.month)}${_pad(dt.day)}_'
      '${_pad(dt.hour)}${_pad(dt.minute)}${_pad(dt.second)}.jpg';

  static String _pad(int n, [int w = 2]) => n.toString().padLeft(w, '0');

  // ---- EXIF fake (binary-format review correction) ----

  /// Lowercase per binary-format review — MediaStore + WeChat both
  /// case-insensitive-compare the Make tag, but our idempotency check
  /// (Doc 2 §8.1) reads back the exact bytes we wrote.
  static const String fakedExifMake = 'samsung';

  /// Display name (NOT the SKU SM-S918B). Doc 2 §4.3.
  static const String fakedExifModel = 'Galaxy S23 Ultra';

  // ---- Limits ----

  /// Hard upper bound enforced by fix_service pre-flight (Doc 2 §6.2).
  static const int maxFileSizeBytes = 2 * 1024 * 1024 * 1024; // 2 GB

  /// Soft warning threshold — video longer than this produces a
  /// FixResult.videoTooLongWarning flag but never throws (Doc 2 §7.1).
  static const double videoWarnThresholdSec = 3.0;

  // ---- Notification (Doc 3 §7) ----

  static const String notificationChannelId   = 'liveback.batch_complete';
  static const String notificationChannelName = '批次处理完成';

  // ---- MethodChannel names (Doc 3 §2 + §5) ----

  static const String channelMediaStore  = 'com.sparker.liveback/mediastore';
  static const String channelWeChatShare = 'com.sparker.liveback/wechat_share';
}
