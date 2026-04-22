// Owner: T3 (UI teammate). Reference: Doc 1 §5.3.4 ResultPage + JSX
// result.jsx. Renders the 4 outcome states (completed / failed /
// skippedAlreadySamsung / skippedNotMotionPhoto) with before/after
// waveforms, size delta, and WeChat share CTA.

import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import '../../models/fix_task.dart';
import '../../services/task_queue.dart';
import '../../services/wechat_share.dart';
import '../../widgets/mono_text.dart';
import '../../widgets/theme_access.dart';
import '../../widgets/waveform.dart';

class ResultPage extends StatefulWidget {
  final String taskId;
  const ResultPage({super.key, required this.taskId});

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  ValueNotifier<FixTask>? _find() {
    for (final n in TaskQueue.instance.tasks.value) {
      if (n.value.id == widget.taskId) return n;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final notifier = _find();
    if (notifier == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(child: Text(context.l10n.resultNotFound)),
      );
    }
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ValueListenableBuilder<FixTask>(
          valueListenable: notifier,
          builder: (ctx, task, _) => Column(
            children: [
              _header(ctx),
              Expanded(child: _body(ctx, task)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_ios_new, color: c.ink, size: 20),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, FixTask task) {
    final c = context.colors;
    final config = _Config.from(task, c, context.l10n);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: config.color,
                ),
                alignment: Alignment.center,
                child: Icon(config.icon, color: c.bg, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.title,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                        letterSpacing: -0.33,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      config.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: c.inkDim,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _fileCard(context, task, ok: task.status == TaskStatus.completed),
          if (task.status == TaskStatus.completed) ...[
            const SizedBox(height: 16),
            _outputBanner(context),
          ],
          if (task.videoTooLongWarning &&
              task.status == TaskStatus.completed) ...[
            const SizedBox(height: 12),
            _longVideoBanner(context),
          ],
          const SizedBox(height: 20),
          _actions(context, task),
        ],
      ),
    );
  }

  Widget _fileCard(BuildContext context, FixTask task, {required bool ok}) {
    final c = context.colors;
    final hue = (task.seed * 37) % 360;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border, width: 1),
                  gradient: RadialGradient(
                    colors: [
                      HSLColor.fromAHSL(0.85, hue.toDouble(), 0.25, 0.82)
                          .toColor(),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.7],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MonoText(
                      ok
                          ? task.displayName.replaceAll('.jpg', '_fixed.jpg')
                          : task.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.ink),
                    ),
                    const SizedBox(height: 3),
                    MonoText(
                      ok
                          ? '${_formatSize(task.sizeBytes)} → ${_formatSize(task.outputSizeBytes ?? task.sizeBytes)}'
                          : _formatSize(task.sizeBytes),
                      style: TextStyle(fontSize: 11, color: c.inkFaint),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (ok) ...[
            const SizedBox(height: 16),
            _WaveCompare(
              label: context.l10n.resultWaveBefore,
              state: WaveformState.broken,
              seed: task.seed,
              color: c.inkFaint,
            ),
            const SizedBox(height: 12),
            _WaveCompare(
              label: context.l10n.resultWaveAfter,
              state: WaveformState.clean,
              seed: task.seed,
              color: c.accent,
            ),
          ],
        ],
      ),
    );
  }

  Widget _outputBanner(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: MonoText(
        context.l10n.resultOutputPath,
        style: TextStyle(fontSize: 12, color: c.inkDim, height: 1.5),
      ),
    );
  }

  Widget _longVideoBanner(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.warn.withValues(alpha: 0.1),
        border: Border.all(color: c.warn.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: c.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.l10n.resultLongVideoWarn,
              style: TextStyle(fontSize: 12.5, color: c.warn),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, FixTask task) {
    final c = context.colors;
    final l = context.l10n;
    if (task.status == TaskStatus.completed) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.ink,
                side: BorderSide(color: c.borderStrong, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(l.resultBackToList),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => _shareSingle(context, task),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.accent,
                foregroundColor: c.bg,
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
                  Text(l.resultShareWeChat),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).maybePop(),
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.borderStrong, width: 1),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(l.resultBackToList),
      ),
    );
  }

  Future<void> _shareSingle(BuildContext context, FixTask task) async {
    final uri = task.outputUri;
    if (uri == null) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await WeChatShare().shareFiles([uri]);
      if (!mounted) return;
      if (result == ShareResult.wechatNotInstalled) {
        messenger.showSnackBar(
          SnackBar(content: Text(l.shareNoWeChat)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l.shareFailed('$e'))),
      );
    }
  }
}

class _Config {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  _Config({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  factory _Config.from(FixTask task, LivebackColors c, AppL10n l) {
    switch (task.status) {
      case TaskStatus.completed:
        return _Config(
          icon: Icons.check,
          color: c.accent,
          title: l.resultTitleCompleted,
          subtitle: l.resultSubtitleCompleted,
        );
      case TaskStatus.failed:
        return _Config(
          icon: Icons.close,
          color: c.danger,
          title: l.resultTitleFailed,
          // Look up localized copy via errorCode, falling through to a
          // generic "try again" message when the code is unknown.
          subtitle: l.errorMessageFor(task.errorCode),
        );
      case TaskStatus.cancelled:
        return _Config(
          icon: Icons.block,
          color: c.inkDim,
          title: l.resultTitleCancelled,
          subtitle: l.resultSubtitleCancelled,
        );
      case TaskStatus.skippedAlreadySamsung:
        return _Config(
          icon: Icons.info_outline,
          color: c.info,
          title: l.resultTitleSkippedAlreadySamsung,
          subtitle: l.resultSubtitleSkippedAlreadySamsung,
        );
      case TaskStatus.skippedNotMotionPhoto:
        return _Config(
          icon: Icons.warning_amber_outlined,
          color: c.warn,
          title: l.resultTitleSkippedNotMotionPhoto,
          subtitle: l.resultSubtitleSkippedNotMotionPhoto,
        );
      case TaskStatus.pending:
      case TaskStatus.processing:
        return _Config(
          icon: Icons.hourglass_empty,
          color: c.inkDim,
          title: l.resultTitleProcessing,
          subtitle: '',
        );
    }
  }
}

class _WaveCompare extends StatelessWidget {
  final String label;
  final WaveformState state;
  final int seed;
  final Color color;
  const _WaveCompare({
    required this.label,
    required this.state,
    required this.seed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: c.inkDim),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: c.panel,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Waveform(
            width: 280,
            height: 30,
            seed: seed,
            state: state,
            color: color,
            dim: c.inkFaint,
            showGrid: true,
          ),
        ),
      ],
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
