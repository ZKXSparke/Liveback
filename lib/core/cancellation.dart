// Owner: shared (Phase 1 SSoT). Reference: Doc 1 §A.5 + Doc 2 §6.5.
// DO NOT edit without an architecture amendment.
//
// CancellationToken is passed from the main isolate to the Worker as part of
// the WorkerRequest payload (Doc 1 §A.4). The Worker polls .isCancelled at
// step boundaries (Doc 2 §6.5). OperationCancelledException is deliberately
// OUTSIDE the LivebackException hierarchy — cancellation is not a user-
// visible failure; the Worker catches it separately and emits
// TaskFinished(kind: cancelled) with no errorCode and no error dialog.

/// Thrown by fix_service (or any sub-module) when a [CancellationToken]
/// trips mid-pipeline. NOT a [LivebackException] subclass — see header.
class OperationCancelledException implements Exception {
  final String taskId;
  OperationCancelledException(this.taskId);

  @override
  String toString() => 'OperationCancelledException($taskId)';
}

/// Cooperative cancellation handle. Main isolate calls [cancel]; worker-side
/// code polls [isCancelled] and calls [throwIfCancelled] at phase boundaries.
///
/// Implementation note (Doc 2 §6.5): cancellation is polled, not interrupted.
/// A cancel that arrives during a long fread/fwrite does not unblock syscalls
/// — it fires at the next boundary check. That is intentional; abrupt
/// interruption would corrupt partial writes.
class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Convenience sugar so pipeline steps can say
/// `cancel.throwIfCancelled(taskId)` instead of an if/throw block.
extension CancellationTokenCheck on CancellationToken {
  void throwIfCancelled(String taskId) {
    if (_cancelled) {
      throw OperationCancelledException(taskId);
    }
  }
}
