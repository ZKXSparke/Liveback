// Owner: T3 (UI teammate). Reference: Doc 1 §5.3.3 TaskListPage + brand
// §5.2 state/waveform mapping + JSX tasklist.jsx.
//
// Top progress bar, per-row Waveform + phase text, swipe-reveal retry
// button on failed rows, "cancel-all" top action (guarded by
// ConfirmDialog destructive), WillPopScope suppression while any task is
// processing.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/task_phase.dart';
import '../../models/fix_task.dart';
import '../../services/task_queue.dart';
import '../../widgets/dialog/confirm_dialog.dart';
import '../../widgets/dialog/error_dialog.dart';
import '../../widgets/mono_text.dart';
import '../../widgets/retry_button.dart';
import '../../widgets/theme_access.dart';
import '../../widgets/waveform.dart';

class TaskListPage extends StatelessWidget {
  const TaskListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder<BatchProgress>(
      valueListenable: TaskQueue.instance.progress,
      builder: (ctx, progress, _) {
        return PopScope(
          canPop: !progress.hasActiveTasks,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && progress.hasActiveTasks) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(
                  content: Text('处理中，请耐心等待'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          child: Scaffold(
            backgroundColor: c.bg,
            body: SafeArea(
              child: Column(
                children: [
                  _TopBar(progress: progress),
                  _ProgressHeader(progress: progress),
                  const Expanded(child: _TaskList()),
                  _BottomActionBar(progress: progress),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  final BatchProgress progress;
  const _TopBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = progress.hasActiveTasks ? '处理中' : '已完成';
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_ios_new, color: c.ink, size: 20),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.ink,
                letterSpacing: -0.17,
              ),
            ),
          ),
          if (progress.hasActiveTasks)
            IconButton(
              onPressed: () => _confirmCancelAll(context),
              icon: Icon(Icons.more_horiz, color: c.inkDim, size: 22),
              tooltip: '取消全部任务',
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Future<void> _confirmCancelAll(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '取消全部任务？',
      body: '已处理完成的文件会保留，未开始的会被丢弃。',
      cancelText: '继续处理',
      confirmText: '确认取消',
      destructive: true,
    );
    if (confirmed) {
      TaskQueue.instance.cancelAll();
    }
  }
}

class _ProgressHeader extends StatelessWidget {
  final BatchProgress progress;
  const _ProgressHeader({required this.progress});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 10),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '${progress.processed} / ${progress.total}',
                style: TextStyle(fontSize: 13, color: c.inkDim),
              ),
              const Spacer(),
              MonoText(
                '${(progress.fraction * 100).round()}%',
                style: TextStyle(
                  fontSize: 13,
                  color: c.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 4,
              color: c.panel,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress.fraction.clamp(0, 1).toDouble(),
                child: Container(color: c.accent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ValueNotifier<FixTask>>>(
      valueListenable: TaskQueue.instance.tasks,
      builder: (ctx, list, _) {
        if (list.isEmpty) {
          return Center(
            child: MonoText(
              '暂无任务',
              style: TextStyle(color: context.colors.inkFaint, fontSize: 12),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          itemCount: list.length,
          itemBuilder: (ctx, i) => TaskRow(notifier: list[i]),
        );
      },
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  final BatchProgress progress;
  const _BottomActionBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (progress.hasActiveTasks) {
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border, width: 1)),
        ),
        alignment: Alignment.center,
        child: Text(
          '请保持应用打开直至完成',
          style: TextStyle(fontSize: 12, color: c.inkFaint),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                TaskQueue.instance.clearFinished();
                Navigator.of(context)
                    .popUntil((route) => route.isFirst);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: c.ink,
                side: BorderSide(color: c.borderStrong, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('再来一批'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: progress.completed == 0
                  ? null
                  : () => _shareAll(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.share_outlined, size: 15),
                  const SizedBox(width: 6),
                  Text('分享全部 (${progress.completed})'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _shareAll(BuildContext context) {
    final completedUris = <String>[];
    for (final n in TaskQueue.instance.tasks.value) {
      if (n.value.status == TaskStatus.completed &&
          n.value.outputUri != null) {
        completedUris.add(n.value.outputUri!);
      }
    }
    if (completedUris.isEmpty) return;
    Navigator.of(context).pushNamed('/result', arguments: {
      'bulkShare': true,
      'uris': completedUris,
    });
  }
}

/// One row in the task list. Bound to a single [ValueNotifier<FixTask>] so
/// only the changed row rebuilds per Doc 1 §2.1.
class TaskRow extends StatefulWidget {
  final ValueNotifier<FixTask> notifier;
  const TaskRow({super.key, required this.notifier});

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow>
    with SingleTickerProviderStateMixin {
  double _swipeX = 0;
  double? _dragStart;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder<FixTask>(
      valueListenable: widget.notifier,
      builder: (ctx, task, _) {
        final mapping = _RowState.from(task, c);
        final isFail = task.status == TaskStatus.failed;
        final isProcessing = task.status == TaskStatus.processing;
        final showLongVideoWarn = task.videoTooLongWarning &&
            (task.status == TaskStatus.pending || isProcessing);

        return Stack(
          children: [
            if (isFail)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 12, 6),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: RetryButton(
                      onPressed: () {
                        setState(() => _swipeX = 0);
                        TaskQueue.instance.retry(task.id);
                      },
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: GestureDetector(
                onTap: () => _onTap(ctx, task),
                onHorizontalDragStart: isFail
                    ? (d) => _dragStart = d.localPosition.dx - _swipeX
                    : null,
                onHorizontalDragUpdate: isFail
                    ? (d) {
                        if (_dragStart == null) return;
                        setState(() {
                          _swipeX = (d.localPosition.dx - _dragStart!)
                              .clamp(-96.0, 0.0);
                        });
                      }
                    : null,
                onHorizontalDragEnd: isFail
                    ? (_) {
                        setState(() {
                          _swipeX = _swipeX < -48 ? -96 : 0;
                          _dragStart = null;
                        });
                      }
                    : null,
                child: Transform.translate(
                  offset: Offset(_swipeX, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.card,
                      border: Border.all(color: c.border, width: 1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        _TaskThumb(task: task),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  if (showLongVideoWarn) ...[
                                    Icon(
                                      Icons.warning_amber_rounded,
                                      size: 12,
                                      color: c.warn,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Expanded(
                                    child: MonoText(
                                      task.displayName,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: c.ink,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  MonoText(
                                    _formatSize(task.sizeBytes),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.inkFaint,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _StatusIcon(task: task),
                                ],
                              ),
                              if (showLongVideoWarn)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '视频较长，可能识别失败',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: c.warn,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 6),
                              Waveform(
                                width: 280,
                                height: 22,
                                seed: task.seed,
                                state: mapping.waveState,
                                color: mapping.color,
                                dim: c.inkFaint,
                                showGrid: false,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mapping.statusText,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: mapping.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onTap(BuildContext context, FixTask task) async {
    if (task.status == TaskStatus.failed) {
      final action = await showErrorDialog(
        context,
        errorCode: task.errorCode ?? 'ERR_UNKNOWN',
        title: '修复失败',
        body: task.errorMessage ?? '处理失败，请稍后重试',
        technicalDetails: kDebugMode ? task.errorTechnicalDetails : null,
        canRetry: true,
      );
      if (action == ErrorDialogAction.retry) {
        TaskQueue.instance.retry(task.id);
      }
    } else if (task.status == TaskStatus.completed ||
        task.isSkipped) {
      Navigator.of(context).pushNamed('/result', arguments: task.id);
    }
  }
}

class _RowState {
  final Color color;
  final WaveformState waveState;
  final String statusText;

  _RowState({
    required this.color,
    required this.waveState,
    required this.statusText,
  });

  factory _RowState.from(FixTask task, LivebackColors c) {
    switch (task.status) {
      case TaskStatus.pending:
        return _RowState(
          color: c.inkFaint,
          waveState: WaveformState.broken,
          statusText: '等待中',
        );
      case TaskStatus.processing:
        return _RowState(
          color: c.inkDim,
          waveState: WaveformState.scanning,
          statusText: task.phase?.zh ?? '处理中…',
        );
      case TaskStatus.completed:
        final elapsed = _formatMs(task.elapsedMs);
        return _RowState(
          color: c.accent,
          waveState: WaveformState.clean,
          statusText: '修复完成 · $elapsed',
        );
      case TaskStatus.failed:
        return _RowState(
          color: c.danger,
          waveState: WaveformState.broken,
          statusText: task.errorCode != null
              ? '修复失败 · ${task.errorCode}'
              : '修复失败',
        );
      case TaskStatus.cancelled:
        return _RowState(
          color: c.inkFaint,
          waveState: WaveformState.broken,
          statusText: '已取消',
        );
      case TaskStatus.skippedAlreadySamsung:
        return _RowState(
          color: c.inkFaint,
          waveState: WaveformState.clean,
          statusText: '已是三星格式，无需修复',
        );
      case TaskStatus.skippedNotMotionPhoto:
        return _RowState(
          color: c.inkFaint,
          waveState: WaveformState.broken,
          statusText: '不是实况图，已跳过',
        );
    }
  }
}

class _StatusIcon extends StatelessWidget {
  final FixTask task;
  const _StatusIcon({required this.task});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    switch (task.status) {
      case TaskStatus.completed:
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Icon(Icons.check, color: Colors.white, size: 11),
        );
      case TaskStatus.failed:
        return Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Icon(Icons.close, color: Colors.white, size: 10),
        );
      case TaskStatus.cancelled:
        return Icon(Icons.block, size: 14, color: c.inkFaint);
      case TaskStatus.skippedAlreadySamsung:
        return Icon(Icons.info_outline, size: 16, color: c.info);
      case TaskStatus.skippedNotMotionPhoto:
        return Icon(Icons.warning_amber_outlined, size: 15, color: c.warn);
      case TaskStatus.pending:
      case TaskStatus.processing:
        return const SizedBox(width: 18, height: 18);
    }
  }
}

class _TaskThumb extends StatelessWidget {
  final FixTask task;
  const _TaskThumb({required this.task});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hue = (task.seed * 37) % 360;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border, width: 1),
        gradient: RadialGradient(
          colors: [
            HSLColor.fromAHSL(
              0.9,
              hue.toDouble(),
              0.25,
              isDark ? 0.55 : 0.82,
            ).toColor(),
            Colors.transparent,
          ],
          stops: const [0, 0.7],
        ),
      ),
    );
  }
}

String _formatSize(int bytes) {
  if (bytes >= 1 << 20) {
    return '${(bytes / (1 << 20)).toStringAsFixed(2)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '$bytes B';
}

String _formatMs(int? ms) {
  if (ms == null) return '—';
  if (ms >= 1000) return '${(ms / 1000).toStringAsFixed(2)}s';
  return '${ms}ms';
}
