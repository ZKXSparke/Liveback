// Owner: T3 (UI teammate). Reference: Doc 1 §A.4 worker message payloads
// (post-review B5 lock) + §4.2 command protocol.
//
// Sealed hierarchy of cross-isolate messages. Every type here MUST be safe
// to send through SendPort — no Exception objects, no Uint8List of arbitrary
// size. Strings/ints/enums/records all survive structured clone.

import '../core/task_phase.dart';

/// Commands sent from main isolate → Worker isolate.
enum WorkerCommand { process, cancel, ping, shutdown }

/// Envelope sent from main → Worker. Always carries [command] and the
/// per-request id; [payload] fields are only populated for
/// [WorkerCommand.process].
class WorkerRequest {
  /// Task-scoped id. For `process` it's the [FixTask.id]; for `cancel` it
  /// is the id of the task to cancel (current in-flight); for `ping` /
  /// `shutdown` it can be any unique string — the caller just uses it to
  /// correlate [Pong] / (no ack for shutdown).
  final String requestId;

  final WorkerCommand command;

  /// Path to the sandbox input file. Populated only for `process`.
  final String? inputPath;

  /// Path to the sandbox output file. Populated only for `process`.
  final String? outputPath;

  /// Display name of the source image. Used for diagnostic messages from
  /// the Worker when errors include the file name.
  final String? displayName;

  /// Source size in bytes (for pre-flight check fast-path and progress UI).
  final int? sizeBytes;

  const WorkerRequest({
    required this.requestId,
    required this.command,
    this.inputPath,
    this.outputPath,
    this.displayName,
    this.sizeBytes,
  });

  factory WorkerRequest.process({
    required String taskId,
    required String inputPath,
    required String outputPath,
    required String displayName,
    required int sizeBytes,
  }) =>
      WorkerRequest(
        requestId: taskId,
        command: WorkerCommand.process,
        inputPath: inputPath,
        outputPath: outputPath,
        displayName: displayName,
        sizeBytes: sizeBytes,
      );

  factory WorkerRequest.cancel(String taskId) => WorkerRequest(
        requestId: taskId,
        command: WorkerCommand.cancel,
      );

  factory WorkerRequest.ping(String requestId) => WorkerRequest(
        requestId: requestId,
        command: WorkerCommand.ping,
      );

  factory WorkerRequest.shutdown() => const WorkerRequest(
        requestId: 'shutdown',
        command: WorkerCommand.shutdown,
      );
}

/// Root of the Worker → main event hierarchy. Sealed so exhaustive switch
/// is enforced at compile time.
sealed class WorkerEvent {
  const WorkerEvent();
}

/// Emitted once after worker spawn, signalling the worker is ready to
/// receive `process` commands.
class WorkerReady extends WorkerEvent {
  const WorkerReady();
}

/// Progress pulse from the running pipeline. Per Doc 1 §A.2 +
/// [FixService.fix.onPhase] callback surface.
class PhaseChanged extends WorkerEvent {
  final String taskId;
  final TaskPhase phase;
  const PhaseChanged({required this.taskId, required this.phase});
}

/// Terminal event for one task. [kind] discriminates success/skipped/fail/
/// cancelled; [result] is set for success/skipped; [error] is set for
/// failure; both null for cancelled.
class TaskFinished extends WorkerEvent {
  final String taskId;
  final TaskResultKind kind;
  final FixResultSummary? result;
  final FixError? error;

  const TaskFinished({
    required this.taskId,
    required this.kind,
    this.result,
    this.error,
  });
}

/// Ack for a `cancel` command — emitted once the Worker has reached a
/// cancellation boundary and is idle.
class CancelAcknowledged extends WorkerEvent {
  final String taskId;
  const CancelAcknowledged(this.taskId);
}

/// Ack for a `ping` command — used by integration tests / health checks.
class Pong extends WorkerEvent {
  final String requestId;
  const Pong(this.requestId);
}

/// Worker-side terminal kinds (post-review B5 — includes `cancelled`).
enum TaskResultKind {
  completed,
  failed,
  skippedAlreadySamsung,
  skippedNotMotionPhoto,
  cancelled,
}

/// Structured-clone-safe projection of `FixResult` for cross-isolate
/// transport. Scaler fields only — no objects.
class FixResultSummary {
  final int elapsedMs;
  final int originalSizeBytes;
  final int outputSizeBytes;
  final double? videoDurationSeconds;
  final bool videoTooLongWarning;
  final int dateTakenMs;
  final int originalMtimeMs;

  const FixResultSummary({
    required this.elapsedMs,
    required this.originalSizeBytes,
    required this.outputSizeBytes,
    required this.videoDurationSeconds,
    required this.videoTooLongWarning,
    required this.dateTakenMs,
    required this.originalMtimeMs,
  });
}

/// Worker-side serializable error. The raw Dart exception is NOT sent
/// across the port (SDK does not guarantee all Exception subclasses
/// survive structured clone — Doc 1 §4.7).
///
/// i18n refactor: [message] is gone. UI layers render localized copy via
/// `context.l10n.errorMessageFor(errorCode)`; [technicalDetails] stays as
/// an optional English diagnostic surfaced only in the debug build's
/// ErrorDialog chip.
class FixError {
  /// One of the `ErrorCodes.*` constants.
  final String errorCode;

  /// Optional technical detail (stack trace tail, root cause string).
  /// Intentionally NOT localized — developer-diagnostic only.
  final String? technicalDetails;

  const FixError({
    required this.errorCode,
    this.technicalDetails,
  });
}
