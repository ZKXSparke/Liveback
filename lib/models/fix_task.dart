// Owner: T3 (UI teammate). Reference: Doc 1 §1 directory layout + §2.1
// two-layer notifier model + §7.4 ErrorDialog + §A.9 retry semantics.
//
// FixTask is the UI-facing snapshot of one queued file. Mutated via
// [ValueNotifier<FixTask>] inside TaskQueue; each row widget binds to a
// single notifier with [ValueListenableBuilder] so only the changed row
// rebuilds on per-task progress.

import '../core/task_phase.dart';

/// UI-facing per-task status.
///
/// * [pending] — queued, awaiting Worker dispatch.
/// * [processing] — currently in the Worker pipeline.
/// * [completed] — Worker emitted `TaskResultKind.completed`.
/// * [failed] — Worker emitted `TaskResultKind.failed` with FixError.
/// * [cancelled] — Worker emitted `TaskResultKind.cancelled` (user cancel).
/// * [skippedAlreadySamsung] — already a Samsung-compatible Motion Photo.
/// * [skippedNotMotionPhoto] — file has no MP4 segment.
enum TaskStatus {
  pending,
  processing,
  completed,
  failed,
  cancelled,
  skippedAlreadySamsung,
  skippedNotMotionPhoto,
}

/// Immutable snapshot of one queued task.
///
/// Mutation happens by constructing a new [FixTask] via [copyWith] and
/// pushing it to the task's [ValueNotifier<FixTask>]. The id is stable
/// across the task's lifetime (used as sandbox key by MediaStoreChannel).
class FixTask {
  /// Stable id (uuid-v4 string). Used as sandbox key for in/out files
  /// (`cache/liveback-io/in-<id>.jpg` + `out-<id>.jpg`).
  final String id;

  /// MediaStore content URI of the source image. Preserved across retries
  /// per Doc 1 §A.9 — the sandbox file is released on failure, but the
  /// URI is re-copied on retry via [MediaStoreChannel.copyInputToSandbox].
  final String contentUri;

  /// DISPLAY_NAME column of the source image. Shown on the task row.
  final String displayName;

  /// SIZE column of the source image. Shown as monospaced size chip.
  final int sizeBytes;

  /// Current status (see [TaskStatus]).
  final TaskStatus status;

  /// Current pipeline phase; non-null only while [status] == processing.
  final TaskPhase? phase;

  /// ERR_* constant from core/error_codes.dart; non-null only when
  /// [status] == failed.
  final String? errorCode;

  /// User-facing zh-CN error message from the `FixError.message` emitted
  /// by the Worker (Doc 1 §A.4). Non-null only when [status] == failed.
  final String? errorMessage;

  /// Optional technical details (stack trace tail, etc.) — surfaced only
  /// in the ErrorDialog "more info" section when non-null.
  final String? errorTechnicalDetails;

  /// Published MediaStore URI of the produced output, once
  /// [publishOutputToMediaStore] has run. Non-null only when
  /// [status] == completed.
  final String? outputUri;

  /// Size of the produced output file in bytes. Non-null only when
  /// [status] == completed.
  final int? outputSizeBytes;

  /// Wall-clock duration from enqueue → completion, in milliseconds.
  /// Non-null for terminal kinds (completed / failed / cancelled /
  /// skipped*).
  final int? elapsedMs;

  /// Completion timestamp. Non-null for terminal kinds.
  final DateTime? completedAt;

  /// Soft warning flag — true iff MP4 duration > 3.0s (Doc 1 §A.1). The
  /// UI shows a non-blocking notice; never triggers a dialog.
  final bool videoTooLongWarning;

  /// Deterministic seed for per-task decorative waveform / thumbnail
  /// placeholder (brand §5.2). Derived from [id.hashCode] at construction
  /// so the visual identity stays stable across rebuilds and retries.
  final int seed;

  const FixTask({
    required this.id,
    required this.contentUri,
    required this.displayName,
    required this.sizeBytes,
    required this.status,
    this.phase,
    this.errorCode,
    this.errorMessage,
    this.errorTechnicalDetails,
    this.outputUri,
    this.outputSizeBytes,
    this.elapsedMs,
    this.completedAt,
    this.videoTooLongWarning = false,
    required this.seed,
  });

  /// Factory: new pending task from a gallery pick.
  factory FixTask.pending({
    required String id,
    required String contentUri,
    required String displayName,
    required int sizeBytes,
  }) =>
      FixTask(
        id: id,
        contentUri: contentUri,
        displayName: displayName,
        sizeBytes: sizeBytes,
        status: TaskStatus.pending,
        seed: id.hashCode & 0x7fffffff,
      );

  FixTask copyWith({
    TaskStatus? status,
    TaskPhase? phase,
    String? errorCode,
    String? errorMessage,
    String? errorTechnicalDetails,
    String? outputUri,
    int? outputSizeBytes,
    int? elapsedMs,
    DateTime? completedAt,
    bool? videoTooLongWarning,
    bool clearPhase = false,
    bool clearError = false,
    bool clearOutput = false,
  }) {
    return FixTask(
      id: id,
      contentUri: contentUri,
      displayName: displayName,
      sizeBytes: sizeBytes,
      status: status ?? this.status,
      phase: clearPhase ? null : (phase ?? this.phase),
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorTechnicalDetails:
          clearError ? null : (errorTechnicalDetails ?? this.errorTechnicalDetails),
      outputUri: clearOutput ? null : (outputUri ?? this.outputUri),
      outputSizeBytes:
          clearOutput ? null : (outputSizeBytes ?? this.outputSizeBytes),
      elapsedMs: elapsedMs ?? this.elapsedMs,
      completedAt: completedAt ?? this.completedAt,
      videoTooLongWarning: videoTooLongWarning ?? this.videoTooLongWarning,
      seed: seed,
    );
  }

  /// True iff the task is in a terminal state (no further Worker work).
  bool get isTerminal =>
      status != TaskStatus.pending && status != TaskStatus.processing;

  /// True iff the task is a "skipped" kind (intentional no-op).
  bool get isSkipped =>
      status == TaskStatus.skippedAlreadySamsung ||
      status == TaskStatus.skippedNotMotionPhoto;

  /// True iff the task is eligible for retry (failed/cancelled).
  bool get isRetryable =>
      status == TaskStatus.failed || status == TaskStatus.cancelled;
}
