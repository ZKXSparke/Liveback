// Owner: shared SSoT value type (authored in Phase 1).
// Reference: Doc 1 §A.1 (authoritative shape) + Doc 2 §1.1/§6.6.
// DO NOT edit without an architecture amendment.
//
// FixResult / FixResultKind / FixOptions are returned by FixService.fix and
// carried across the isolate boundary in TaskFinished worker events
// (Doc 1 §A.4). The shape is frozen.

/// Outcome kinds of a single-file fix invocation.
///
/// `skippedAlreadySamsung` and `skippedNotMotionPhoto` are NOT errors —
/// they flow through the success return path (no exception thrown) per
/// Doc 1 §A.3's result-vs-exception semantics.
enum FixResultKind {
  completed,
  skippedAlreadySamsung,
  skippedNotMotionPhoto,
}

/// Success return type from [FixService.fix]. Failure throws a
/// `LivebackException` subclass; cancellation throws
/// `OperationCancelledException`.
class FixResult {
  /// Which success path this result represents.
  final FixResultKind kind;

  /// Wall-clock duration of the fix pipeline in milliseconds.
  final int elapsedMs;

  /// Size of the source file on disk, in bytes.
  final int originalSizeBytes;

  /// Size of the produced output file. For `skipped*` kinds, equals
  /// [originalSizeBytes] — no output file was written.
  final int outputSizeBytes;

  /// MP4 video duration (seconds), parsed from mvhd. Null when the source
  /// has no MP4 segment (i.e. `kind == skippedNotMotionPhoto`).
  final double? videoDurationSeconds;

  /// Soft warning flag — true iff [videoDurationSeconds] > 3.0 (Doc 2 §7.1).
  /// Never triggers an exception; UI shows a non-blocking notice.
  final bool videoTooLongWarning;

  /// EXIF DateTimeOriginal → epoch ms. Falls back to
  /// `DateTime.now().millisecondsSinceEpoch` when absent (Doc 2 §6.2).
  /// Used by Doc 3 §2.5 as the MediaStore DATE_TAKEN column value AND by
  /// Doc 1 §A.10 `outputFileName` as the display-name timestamp.
  final int dateTakenMs;

  /// Source file's mtime at parse time (epoch ms). Forwarded to
  /// MediaStore DATE_MODIFIED.
  final int originalMtimeMs;

  const FixResult({
    required this.kind,
    required this.elapsedMs,
    required this.originalSizeBytes,
    required this.outputSizeBytes,
    required this.videoDurationSeconds,
    required this.videoTooLongWarning,
    required this.dateTakenMs,
    required this.originalMtimeMs,
  });
}

/// Compile-time-defaulted options controlling fix_service guard rails.
/// EXIF make/model are INTENTIONALLY not here — they are compile-time
/// constants in `LivebackConstants` (Doc 1 §A.10) to prevent per-call drift.
class FixOptions {
  /// Hard upper bound enforced in fix_service pre-flight. Default: 2 GiB.
  final int maxFileSizeBytes;

  /// Soft warning threshold in seconds. Default: 3.0 (brand §5.2 / v1.1).
  final double videoWarnThresholdSeconds;

  const FixOptions({
    this.maxFileSizeBytes = 2147483648,
    this.videoWarnThresholdSeconds = 3.0,
  });
}
