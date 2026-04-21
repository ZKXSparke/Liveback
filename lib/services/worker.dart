// Owner: T3 (UI teammate). Reference: Doc 1 §4 (Isolate worker architecture),
// §A.4 command protocol, §A.5 cancellation, §A.1 FixService signature.
//
// Long-lived Worker isolate. Spawned once at app start via
// [LivebackWorker.spawn]; disposed once at app exit via [shutdown]. Tasks
// flow through serially; between tasks the isolate idles on a StreamIterator.
//
// Cancellation is cooperative — the isolate polls a local [CancellationToken]
// at phase boundaries (Doc 1 §4.4). Cancel commands mutate the token; the
// currently-running pipeline step sees the flag at its next check.

import 'dart:async';
import 'dart:isolate';

import '../core/cancellation.dart';
import '../core/task_phase.dart';
import '../exceptions/liveback_exceptions.dart';
import '../models/fix_result.dart';
import '../models/worker_messages.dart';
import 'fix_service.dart';

/// Main-side facade for the worker isolate. Owns the [Isolate], the
/// outgoing [SendPort], and the incoming [ReceivePort]. Exposes a single
/// stream of [WorkerEvent]s and a `send(WorkerRequest)` API.
///
/// This class is main-isolate-only. The worker entrypoint is the top-level
/// function [workerEntry] below.
class LivebackWorker {
  Isolate? _isolate;
  SendPort? _toWorker;
  late final ReceivePort _fromWorker;
  final _eventController = StreamController<WorkerEvent>.broadcast();
  bool _readyFired = false;

  /// Broadcast stream of every event the worker sends. Subscribe once per
  /// consumer — late subscribers miss earlier events but that's fine for
  /// TaskQueue (it cares about events that follow its `process` dispatch).
  Stream<WorkerEvent> get events => _eventController.stream;

  /// Spawns the worker and awaits [WorkerReady]. Must be called before
  /// any [send]; subsequent calls are no-ops.
  Future<void> spawn() async {
    if (_isolate != null) return;
    _fromWorker = ReceivePort('LivebackWorker.fromWorker');
    final ready = Completer<void>();

    _fromWorker.listen((message) {
      if (message is SendPort) {
        _toWorker = message;
      } else if (message is WorkerEvent) {
        if (message is WorkerReady && !_readyFired) {
          _readyFired = true;
          if (!ready.isCompleted) ready.complete();
        }
        _eventController.add(message);
      }
    });

    _isolate = await Isolate.spawn<SendPort>(
      workerEntry,
      _fromWorker.sendPort,
      errorsAreFatal: false,
      debugName: 'LivebackWorker',
    );

    // Wait for both the SendPort handshake and the first WorkerReady.
    // If the worker crashes during bootstrap we give up after 5 seconds.
    await ready.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () =>
          throw StateError('LivebackWorker failed to emit WorkerReady'),
    );
  }

  /// Forwards a request to the worker. Spawn MUST have completed first.
  void send(WorkerRequest request) {
    final port = _toWorker;
    if (port == null) {
      throw StateError('LivebackWorker.send() called before spawn() completed');
    }
    port.send(request);
  }

  /// Graceful shutdown. Sends [WorkerCommand.shutdown], awaits a short
  /// grace window, then forcibly kills the isolate.
  Future<void> shutdown() async {
    final iso = _isolate;
    if (iso == null) return;
    try {
      _toWorker?.send(WorkerRequest.shutdown());
    } catch (_) {
      // Worker already dead — ignore.
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    iso.kill(priority: Isolate.immediate);
    _isolate = null;
    _toWorker = null;
    _fromWorker.close();
    await _eventController.close();
  }
}

/// Worker-isolate entrypoint. The parent passes its [ReceivePort.sendPort]
/// so we can emit events back; we create our own [ReceivePort] and hand its
/// [SendPort] back as the very first message (the SendPort handshake).
///
/// Kept at top level so [Isolate.spawn] can obtain a Send-Port-capable
/// reference to it.
Future<void> workerEntry(SendPort toMain) async {
  final fromMain = ReceivePort('LivebackWorker.fromMain');
  toMain.send(fromMain.sendPort);
  toMain.send(const WorkerReady());

  final service = FixService();
  CancellationToken? currentToken;
  String? currentTaskId;

  Future<void> handleProcess(WorkerRequest req) async {
    final taskId = req.requestId;
    final token = CancellationToken();
    currentToken = token;
    currentTaskId = taskId;

    try {
      final result = await service.fix(
        inputPath: req.inputPath!,
        outputPath: req.outputPath!,
        cancel: token,
        onPhase: (TaskPhase phase) {
          toMain.send(PhaseChanged(taskId: taskId, phase: phase));
        },
      );
      final summary = FixResultSummary(
        elapsedMs: result.elapsedMs,
        originalSizeBytes: result.originalSizeBytes,
        outputSizeBytes: result.outputSizeBytes,
        videoDurationSeconds: result.videoDurationSeconds,
        videoTooLongWarning: result.videoTooLongWarning,
        dateTakenMs: result.dateTakenMs,
        originalMtimeMs: result.originalMtimeMs,
      );
      final kind = switch (result.kind) {
        FixResultKind.completed => TaskResultKind.completed,
        FixResultKind.skippedAlreadySamsung =>
          TaskResultKind.skippedAlreadySamsung,
        FixResultKind.skippedNotMotionPhoto =>
          TaskResultKind.skippedNotMotionPhoto,
      };
      toMain.send(TaskFinished(taskId: taskId, kind: kind, result: summary));
    } on OperationCancelledException {
      // Cancellation is NOT an error — emit cancelled, no FixError.
      toMain.send(
        TaskFinished(taskId: taskId, kind: TaskResultKind.cancelled),
      );
    } on LivebackException catch (e, st) {
      toMain.send(
        TaskFinished(
          taskId: taskId,
          kind: TaskResultKind.failed,
          error: FixError(
            errorCode: e.errorCode,
            message: e.message,
            technicalDetails: _summarizeStack(st, e.cause),
          ),
        ),
      );
    } catch (e, st) {
      // Fallback bucket (Doc 1 §A.4 step 3).
      toMain.send(
        TaskFinished(
          taskId: taskId,
          kind: TaskResultKind.failed,
          error: FixError(
            errorCode: 'ERR_UNKNOWN',
            message: '处理失败，请稍后重试',
            technicalDetails: '${e.runtimeType}: $e\n${_summarizeStack(st)}',
          ),
        ),
      );
    } finally {
      if (identical(currentToken, token)) {
        currentToken = null;
        currentTaskId = null;
      }
    }
  }

  await for (final msg in fromMain) {
    if (msg is! WorkerRequest) continue;
    switch (msg.command) {
      case WorkerCommand.process:
        await handleProcess(msg);
        break;
      case WorkerCommand.cancel:
        final token = currentToken;
        if (token != null) token.cancel();
        toMain.send(CancelAcknowledged(currentTaskId ?? msg.requestId));
        break;
      case WorkerCommand.ping:
        toMain.send(Pong(msg.requestId));
        break;
      case WorkerCommand.shutdown:
        fromMain.close();
        return;
    }
  }
}

/// Truncates a stack trace for cross-isolate transport. Keeps top 4
/// frames — enough to diagnose in the ErrorDialog "more info" section
/// without exploding the message size.
String _summarizeStack(StackTrace st, [Object? cause]) {
  final lines = st.toString().split('\n').take(4).join('\n');
  if (cause != null) {
    return 'cause=$cause\n$lines';
  }
  return lines;
}
