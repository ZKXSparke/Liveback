// Owner: T3 (UI teammate). Reference: Doc 1 §2.1 (two-layer notifier),
// §4 (isolate worker architecture), §A.9 retry semantics, §A.4 message
// payloads.
//
// Singleton that owns the UI's view of the per-batch task pipeline. Two
// layers of ValueNotifier:
//   - outer  ValueNotifier<List<ValueNotifier<FixTask>>>  — fires on
//            add / remove / reorder only.
//   - inner  ValueNotifier<FixTask>                        — fires on per-
//            task status / phase / error transitions.
// The TaskListPage row widget binds a ValueListenableBuilder<FixTask> to
// the inner notifier, so only the changed row rebuilds.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/fix_task.dart';
import '../models/worker_messages.dart';
import 'mediastore_channel.dart';
import 'worker.dart';

/// Aggregate batch counters. Fires whenever the task list changes.
class BatchProgress {
  final int total;
  final int completed;
  final int failed;
  final int cancelled;
  final int skipped;

  const BatchProgress({
    required this.total,
    required this.completed,
    required this.failed,
    required this.cancelled,
    required this.skipped,
  });

  static const empty = BatchProgress(
    total: 0,
    completed: 0,
    failed: 0,
    cancelled: 0,
    skipped: 0,
  );

  /// Number of tasks reaching a terminal state (any non-pending,
  /// non-processing kind).
  int get processed => completed + failed + cancelled + skipped;

  /// True iff one or more tasks are still pending / processing.
  bool get hasActiveTasks => processed < total;

  /// Ratio 0.0..1.0 of processed to total. Returns 0.0 when [total] == 0.
  double get fraction => total == 0 ? 0.0 : processed / total;
}

/// Persistent "FIXED" counter key. Incremented after each completed task.
const _kFixedCountKey = 'liveback.fixed_count';

/// Central enqueue/dispatch/cancel/retry hub.
class TaskQueue {
  TaskQueue._();

  /// Process-wide singleton — the task list must outlive every page
  /// (review R10).
  static final TaskQueue instance = TaskQueue._();

  /// Outer notifier fires on add/remove/reorder only.
  final ValueNotifier<List<ValueNotifier<FixTask>>> tasks =
      ValueNotifier(const []);

  /// Aggregate counters for the progress bar + batch summary.
  final ValueNotifier<BatchProgress> progress =
      ValueNotifier(BatchProgress.empty);

  /// Persistent count of successfully-fixed files shown on the Home page's
  /// FIXED counter. Loaded once at init; updated in lockstep with the
  /// `liveback.fixed_count` SharedPreferences key.
  final ValueNotifier<int> fixedCount = ValueNotifier(0);

  final LivebackWorker _worker = LivebackWorker();
  final MediaStoreChannel _mediaStore = MediaStoreChannel();

  /// Optional override for tests (so widget tests can inject a fake
  /// MediaStoreChannel without having the real MethodChannel bound).
  MediaStoreChannel? _mediaStoreOverride;

  StreamSubscription<WorkerEvent>? _eventSub;

  /// The taskId currently being executed by the worker. Needed so that
  /// `cancelAll` knows whether there's an in-flight job whose current
  /// boundary to trip.
  String? _inFlightId;

  /// Start timestamps per task (for elapsedMs computation on completion).
  final Map<String, DateTime> _startedAt = {};

  /// Sandbox output path per in-flight task (returned by
  /// [MediaStoreChannel.reserveOutputSandbox]). We keep this so that when
  /// Worker emits [TaskFinished] we can feed the same absolute path to
  /// [MediaStoreChannel.publishOutputToMediaStore] without reconstructing it.
  final Map<String, String> _outputPaths = {};

  /// The queue of pending task ids, dispatched serially (one at a time).
  final List<String> _pending = [];

  bool _initialized = false;
  bool _disposed = false;

  MediaStoreChannel get _mediaStoreApi => _mediaStoreOverride ?? _mediaStore;

  /// Override for tests — inject a fake MediaStoreChannel. Callers that
  /// go through this path must also avoid calling [init] (or use
  /// [initWithoutWorker] if they wire a fake worker).
  @visibleForTesting
  void debugSetMediaStore(MediaStoreChannel channel) {
    _mediaStoreOverride = channel;
  }

  /// Spawn the worker, load persisted state, wire up the event listener.
  /// Idempotent; safe to call from [State.initState] on every cold start.
  Future<void> init() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    await _loadFixedCount();
    await _worker.spawn();
    _eventSub = _worker.events.listen(_onWorkerEvent);
  }

  /// Test-only init that skips the worker spawn. Integration tests wire
  /// their own fake worker via [debugDispatch].
  @visibleForTesting
  Future<void> initForTest() async {
    if (_initialized || _disposed) return;
    _initialized = true;
    await _loadFixedCount();
  }

  Future<void> _loadFixedCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      fixedCount.value = prefs.getInt(_kFixedCountKey) ?? 0;
    } catch (e) {
      // SharedPreferences backend not available in some unit-test contexts.
      debugPrint('TaskQueue: failed to load fixed count: $e');
    }
  }

  Future<void> _saveFixedCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kFixedCountKey, fixedCount.value);
    } catch (e) {
      debugPrint('TaskQueue: failed to persist fixed count: $e');
    }
  }

  /// Enqueues a batch of gallery picks. Tasks start in `pending`; the
  /// first one dispatches immediately, the rest sit in [_pending] and
  /// are dispatched on each [TaskFinished].
  Future<void> enqueueAll(List<TaskQueueInput> inputs) async {
    final existing = List<ValueNotifier<FixTask>>.from(tasks.value);
    final newNotifiers = <ValueNotifier<FixTask>>[];
    for (final input in inputs) {
      final task = FixTask.pending(
        id: input.id,
        contentUri: input.contentUri,
        displayName: input.displayName,
        sizeBytes: input.sizeBytes,
      );
      final notifier = ValueNotifier<FixTask>(task);
      newNotifiers.add(notifier);
      _pending.add(task.id);
    }
    tasks.value = [...existing, ...newNotifiers];
    _recomputeProgress();
    _pumpNext();
  }

  /// Convenience overload so the Gallery page doesn't need to know
  /// about [TaskQueueInput].
  Future<void> enqueueFromGallery({
    required String id,
    required String contentUri,
    required String displayName,
    required int sizeBytes,
  }) =>
      enqueueAll([
        TaskQueueInput(
          id: id,
          contentUri: contentUri,
          displayName: displayName,
          sizeBytes: sizeBytes,
        ),
      ]);

  /// User-initiated cancel-all. Drops pending ids, trips cancel on the
  /// in-flight one (if any). Tasks that finish cancel re-emit
  /// [TaskResultKind.cancelled] which we then forward to the UI.
  void cancelAll() {
    // Drain queue: mark pending as cancelled immediately.
    final pendingIds = List<String>.from(_pending);
    _pending.clear();
    for (final id in pendingIds) {
      final n = _findNotifier(id);
      if (n == null) continue;
      if (n.value.status == TaskStatus.pending) {
        n.value = n.value.copyWith(
          status: TaskStatus.cancelled,
          elapsedMs: 0,
          completedAt: DateTime.now(),
          clearPhase: true,
        );
      }
    }
    // Trip the in-flight cancel.
    final inFlight = _inFlightId;
    if (inFlight != null) {
      try {
        _worker.send(WorkerRequest.cancel(inFlight));
      } catch (e) {
        debugPrint('TaskQueue: cancel send failed: $e');
      }
    }
    _recomputeProgress();
  }

  /// Retry a failed/cancelled task. Per §A.9 the sandbox input must be
  /// re-materialized because the prior sandbox was released.
  Future<void> retry(String taskId) async {
    final notifier = _findNotifier(taskId);
    if (notifier == null) return;
    final task = notifier.value;
    if (!task.isRetryable) return;
    notifier.value = task.copyWith(
      status: TaskStatus.pending,
      clearPhase: true,
      clearError: true,
      clearOutput: true,
    );
    _pending.add(taskId);
    _recomputeProgress();
    _pumpNext();
  }

  /// Remove a task (left-swipe delete or UI clean-up). Sandbox release
  /// is a no-op if the task never got one.
  Future<void> remove(String taskId) async {
    final list = List<ValueNotifier<FixTask>>.from(tasks.value);
    list.removeWhere((n) => n.value.id == taskId);
    _pending.remove(taskId);
    tasks.value = list;
    try {
      await _mediaStoreApi.releaseSandbox(taskId: taskId);
    } catch (_) {
      // Tolerate missing files.
    }
    _recomputeProgress();
  }

  /// Clear all completed+skipped+cancelled rows (keeps active ones).
  void clearFinished() {
    final list = List<ValueNotifier<FixTask>>.from(tasks.value);
    list.removeWhere((n) => n.value.isTerminal);
    tasks.value = list;
    _recomputeProgress();
  }

  /// Dispatch the next pending task if the worker is idle.
  Future<void> _pumpNext() async {
    if (_inFlightId != null) return;
    if (_pending.isEmpty) return;
    final taskId = _pending.removeAt(0);
    final notifier = _findNotifier(taskId);
    if (notifier == null) return;
    _inFlightId = taskId;
    _startedAt[taskId] = DateTime.now();
    notifier.value = notifier.value.copyWith(
      status: TaskStatus.processing,
      clearError: true,
      clearOutput: true,
    );
    _recomputeProgress();

    final task = notifier.value;
    String inputPath;
    String outputPath;
    try {
      inputPath = await _mediaStoreApi.copyInputToSandbox(
        contentUri: task.contentUri,
        taskId: task.id,
      );
      outputPath =
          await _mediaStoreApi.reserveOutputSandbox(taskId: task.id);
      _outputPaths[task.id] = outputPath;
    } catch (e) {
      notifier.value = task.copyWith(
        status: TaskStatus.failed,
        elapsedMs: DateTime.now().difference(_startedAt[taskId]!).inMilliseconds,
        completedAt: DateTime.now(),
        errorCode: 'ERR_PERMISSION',
        errorMessage: '未获得存储或通知权限',
        errorTechnicalDetails: '$e',
      );
      _inFlightId = null;
      _startedAt.remove(taskId);
      _recomputeProgress();
      unawaited(_pumpNext());
      return;
    }

    try {
      _worker.send(
        WorkerRequest.process(
          taskId: task.id,
          inputPath: inputPath,
          outputPath: outputPath,
          displayName: task.displayName,
          sizeBytes: task.sizeBytes,
        ),
      );
    } catch (e) {
      notifier.value = task.copyWith(
        status: TaskStatus.failed,
        errorCode: 'ERR_UNKNOWN',
        errorMessage: '处理失败，请稍后重试',
        errorTechnicalDetails: 'worker send failed: $e',
        elapsedMs:
            DateTime.now().difference(_startedAt[taskId]!).inMilliseconds,
        completedAt: DateTime.now(),
      );
      _inFlightId = null;
      _startedAt.remove(taskId);
      _recomputeProgress();
      unawaited(_pumpNext());
    }
  }

  void _onWorkerEvent(WorkerEvent event) {
    if (event is PhaseChanged) {
      final n = _findNotifier(event.taskId);
      if (n != null) {
        n.value = n.value.copyWith(phase: event.phase);
      }
    } else if (event is TaskFinished) {
      _handleFinished(event);
    }
    // WorkerReady / CancelAcknowledged / Pong are informational — no
    // UI state transition is needed beyond what cancelAll already did.
  }

  Future<void> _handleFinished(TaskFinished event) async {
    final n = _findNotifier(event.taskId);
    final started = _startedAt.remove(event.taskId);
    if (_inFlightId == event.taskId) _inFlightId = null;
    if (n == null) {
      unawaited(_pumpNext());
      return;
    }
    final task = n.value;
    final elapsed = started == null
        ? (event.result?.elapsedMs ?? 0)
        : DateTime.now().difference(started).inMilliseconds;

    switch (event.kind) {
      case TaskResultKind.completed:
        String? publishedUri;
        try {
          final r = event.result!;
          final outPath = _outputPaths[task.id];
          if (outPath == null) {
            throw StateError('missing sandbox out path for ${task.id}');
          }
          publishedUri = await _mediaStoreApi.publishOutputToMediaStore(
            sandboxOutPath: outPath,
            displayName: LivebackConstants.outputFileName(
              DateTime.fromMillisecondsSinceEpoch(r.dateTakenMs),
            ),
            dateTakenEpochMs: r.dateTakenMs,
            originalMtimeEpochMs: r.originalMtimeMs,
          );
        } catch (e) {
          debugPrint('TaskQueue: publishOutputToMediaStore failed: $e');
          // Publish failure surfaces as ERR_WRITE_CORRUPT — the bytes
          // were written but the gallery entry didn't materialize.
          n.value = task.copyWith(
            status: TaskStatus.failed,
            elapsedMs: elapsed,
            completedAt: DateTime.now(),
            errorCode: 'ERR_WRITE_CORRUPT',
            errorMessage: '写入中断，输出文件不完整',
            errorTechnicalDetails: '$e',
          );
          break;
        }
        n.value = task.copyWith(
          status: TaskStatus.completed,
          phase: null,
          clearPhase: true,
          clearError: true,
          outputUri: publishedUri,
          outputSizeBytes: event.result?.outputSizeBytes,
          elapsedMs: elapsed,
          completedAt: DateTime.now(),
          videoTooLongWarning: event.result?.videoTooLongWarning ?? false,
        );
        fixedCount.value = fixedCount.value + 1;
        unawaited(_saveFixedCount());
        break;
      case TaskResultKind.failed:
        // errorMessage is no longer populated from the worker (i18n
        // refactor): UI resolves localized copy via errorCode. The field
        // on FixTask is retained but left null — removing it was out of
        // scope for this branch.
        n.value = task.copyWith(
          status: TaskStatus.failed,
          clearPhase: true,
          elapsedMs: elapsed,
          completedAt: DateTime.now(),
          errorCode: event.error?.errorCode ?? 'ERR_UNKNOWN',
          errorTechnicalDetails: event.error?.technicalDetails,
        );
        break;
      case TaskResultKind.cancelled:
        n.value = task.copyWith(
          status: TaskStatus.cancelled,
          clearPhase: true,
          clearError: true,
          elapsedMs: elapsed,
          completedAt: DateTime.now(),
        );
        break;
      case TaskResultKind.skippedAlreadySamsung:
        n.value = task.copyWith(
          status: TaskStatus.skippedAlreadySamsung,
          clearPhase: true,
          clearError: true,
          elapsedMs: elapsed,
          completedAt: DateTime.now(),
          videoTooLongWarning: event.result?.videoTooLongWarning ?? false,
        );
        break;
      case TaskResultKind.skippedNotMotionPhoto:
        n.value = task.copyWith(
          status: TaskStatus.skippedNotMotionPhoto,
          clearPhase: true,
          clearError: true,
          elapsedMs: elapsed,
          completedAt: DateTime.now(),
        );
        break;
    }

    // Release sandbox regardless of outcome.
    _outputPaths.remove(task.id);
    try {
      await _mediaStoreApi.releaseSandbox(taskId: task.id);
    } catch (_) {
      // Tolerate missing files.
    }

    _recomputeProgress();
    unawaited(_pumpNext());
  }

  /// Debug-only dispatch shim used by integration tests that inject a
  /// fake worker by listening to this event stream and pushing events back.
  @visibleForTesting
  void debugDispatchEvent(WorkerEvent event) => _onWorkerEvent(event);

  /// Debug-only input entrypoint used by integration tests.
  @visibleForTesting
  Future<void> debugEnqueue(List<TaskQueueInput> inputs) => enqueueAll(inputs);

  ValueNotifier<FixTask>? _findNotifier(String taskId) {
    for (final n in tasks.value) {
      if (n.value.id == taskId) return n;
    }
    return null;
  }

  void _recomputeProgress() {
    final list = tasks.value;
    int completed = 0;
    int failed = 0;
    int cancelled = 0;
    int skipped = 0;
    for (final n in list) {
      switch (n.value.status) {
        case TaskStatus.completed:
          completed++;
          break;
        case TaskStatus.failed:
          failed++;
          break;
        case TaskStatus.cancelled:
          cancelled++;
          break;
        case TaskStatus.skippedAlreadySamsung:
        case TaskStatus.skippedNotMotionPhoto:
          skipped++;
          break;
        case TaskStatus.pending:
        case TaskStatus.processing:
          break;
      }
    }
    progress.value = BatchProgress(
      total: list.length,
      completed: completed,
      failed: failed,
      cancelled: cancelled,
      skipped: skipped,
    );
  }

  /// Tear down — called from `LivebackApp` dispose path or on process exit.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventSub?.cancel();
    _eventSub = null;
    await _worker.shutdown();
  }
}

/// Public value-type for enqueue inputs. Gallery / TestMode construct
/// these from gallery picks or synthetic samples.
class TaskQueueInput {
  final String id;
  final String contentUri;
  final String displayName;
  final int sizeBytes;
  const TaskQueueInput({
    required this.id,
    required this.contentUri,
    required this.displayName,
    required this.sizeBytes,
  });
}
