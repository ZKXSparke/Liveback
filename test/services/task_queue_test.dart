// T3 unit test — TaskQueue's batch-progress accounting on synthetic
// task notifiers. We don't spin up the real Worker isolate here
// (that's covered by integration_test/); we just assert that direct
// mutation of the list keeps progress counters aligned.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveback/models/fix_task.dart';
import 'package:liveback/services/task_queue.dart';

void main() {
  test('TaskQueue progress counters reflect per-status counts', () async {
    final queue = TaskQueue.instance;
    // Reset any residual state from previous tests.
    for (final n in queue.tasks.value.toList()) {
      await queue.remove(n.value.id);
    }

    // Inject notifiers directly to avoid requiring the worker.
    final list = <ValueNotifier<FixTask>>[
      ValueNotifier(FixTask.pending(
        id: 't1',
        contentUri: 'x',
        displayName: 'a.jpg',
        sizeBytes: 1,
      ).copyWith(status: TaskStatus.completed)),
      ValueNotifier(FixTask.pending(
        id: 't2',
        contentUri: 'x',
        displayName: 'b.jpg',
        sizeBytes: 1,
      ).copyWith(status: TaskStatus.failed, errorCode: 'ERR_UNKNOWN')),
      ValueNotifier(FixTask.pending(
        id: 't3',
        contentUri: 'x',
        displayName: 'c.jpg',
        sizeBytes: 1,
      ).copyWith(status: TaskStatus.skippedAlreadySamsung)),
      ValueNotifier(FixTask.pending(
        id: 't4',
        contentUri: 'x',
        displayName: 'd.jpg',
        sizeBytes: 1,
      )),
    ];
    queue.tasks.value = list;
    // Force internal recompute via a no-op removal of non-existent id.
    await queue.remove('nope');

    final progress = queue.progress.value;
    expect(progress.total, 4);
    expect(progress.completed, 1);
    expect(progress.failed, 1);
    expect(progress.skipped, 1);
    expect(progress.hasActiveTasks, true);
  });
}
