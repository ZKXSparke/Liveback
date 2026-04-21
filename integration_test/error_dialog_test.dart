// T3 integration test — inject a failed task, open TaskListPage, tap the
// row, and verify the ErrorDialog renders with all glitch traits.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liveback/app.dart';
import 'package:liveback/models/fix_task.dart';
import 'package:liveback/services/task_queue.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('failed task row opens ErrorDialog with errorCode chip',
      (tester) async {
    // Seed a failed task before app boot — the TaskListPage reads the
    // queue's ValueNotifier, so the pre-populated state is visible.
    final queue = TaskQueue.instance;
    // Reset any residual state.
    for (final n in queue.tasks.value.toList()) {
      await queue.remove(n.value.id);
    }
    queue.tasks.value = [
      ValueNotifier(FixTask.pending(
        id: 'integ-test-fail',
        contentUri: 'content://example/fake',
        displayName: 'broken.jpg',
        sizeBytes: 1024,
      ).copyWith(
        status: TaskStatus.failed,
        errorCode: 'ERR_SEF_WRITE_FAIL',
        errorMessage: '写入失败，请检查存储空间',
      )),
    ];

    await tester.pumpWidget(const LivebackApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Navigate to /tasks via the app's Navigator.
    final ctx = tester.element(find.text('选择实况图'));
    // ignore: use_build_context_synchronously
    Navigator.of(ctx).pushNamed('/tasks');
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Tap the row.
    await tester.tap(find.text('broken.jpg'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // ErrorDialog opens with > ERR_SEF_WRITE_FAIL chip.
    expect(find.text('> ERR_SEF_WRITE_FAIL'), findsOneWidget);
    expect(find.text('修复失败'), findsWidgets);
  });
}
