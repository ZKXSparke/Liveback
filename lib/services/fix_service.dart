// Owner: T1 (binary-format teammate).
// Reference: Doc 1 §A.1 (SSoT — authoritative) + Doc 2 §6.
// DO NOT edit signatures without an architecture amendment to both docs.
//
// This is the single most important stub in the bootstrap: the Worker
// isolate (T3 owns worker plumbing) dispatches every task through this
// signature. Input/output are ALWAYS filesystem paths inside the Plan A
// copy-through sandbox (cache/liveback-io/). Content URIs never reach
// this layer.

import '../core/cancellation.dart';
import '../core/task_phase.dart';
import '../models/fix_result.dart';

class FixService {
  /// Single-file orchestration. Runs inside the Worker Isolate.
  ///
  /// Both [inputPath] and [outputPath] are filesystem paths inside the
  /// app's sandbox (populated by `MediaStoreChannel.copyInputToSandbox`
  /// before dispatch). The fix_service never sees content:// URIs.
  ///
  /// Progress: emits [TaskPhase] values via [onPhase] as the pipeline
  /// advances across parse / inject / write boundaries.
  ///
  /// Cancellation: [cancel] is polled at step boundaries (see Doc 2 §6.5).
  ///   Throws [OperationCancelledException] if cancel fires mid-process.
  ///
  /// Errors: throws a `LivebackException` subclass whose `.errorCode` is
  /// one of the `ErrorCodes.*` constants in `core/error_codes.dart`.
  Future<FixResult> fix({
    required String inputPath,
    required String outputPath,
    required CancellationToken cancel,
    void Function(TaskPhase phase)? onPhase,
    FixOptions options = const FixOptions(),
  }) {
    throw UnimplementedError('T1 — Doc 2 §6 (fix_service orchestrator)');
  }
}
