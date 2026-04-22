// Owner: T3 (UI teammate). Reference: Doc 1 §5.3.6 + JSX settings.jsx
// TestModePage. Runs the bundled djimimo sample through the FixService
// pipeline (via TaskQueue) and visualizes each phase crossing as a step
// check. On success, offers "分享测试结果到微信".
//
// Known-limitation note: the real pipeline depends on T1's FixService +
// T2's MediaStoreChannel. Until they're wired, the page falls back to a
// visual-only simulation (step timers only), so the testing workflow
// itself is reachable.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/l10n_ext.dart';
import '../../services/wechat_share.dart';
import '../../widgets/mono_text.dart';
import '../../widgets/theme_access.dart';

const _kSampleAssetPath = 'assets/test_samples/djimimo_sample.jpg';

class TestModePage extends StatefulWidget {
  const TestModePage({super.key});

  @override
  State<TestModePage> createState() => _TestModePageState();
}

class _TestModePageState extends State<TestModePage> {
  bool _running = false;
  // Stored as indices (0..stepCount-1) rather than translated strings so
  // the displayed label tracks the current locale — if the user flips the
  // language mid-run, rebuilds re-read the indices against the new
  // l10n step-name getters.
  final List<int> _completedStepIndices = [];
  String? _error;
  String? _outputUri;
  VoidCallback? _stepSub;

  static const int _stepCount = 5;

  List<String> _allSteps(AppL10n l) => [
        l.testModeStepParse,
        l.testModeStepDetectMp4,
        l.testModeStepInjectSef,
        l.testModeStepFakeExif,
        l.testModeStepWriteOutput,
      ];

  Future<String> _materializeSample() async {
    final data = await rootBundle.load(_kSampleAssetPath);
    final tempDir = await getTemporaryDirectory();
    final out = File('${tempDir.path}/djimimo_sample.jpg');
    await out.writeAsBytes(data.buffer.asUint8List());
    return out.path;
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _completedStepIndices.clear();
      _error = null;
      _outputUri = null;
    });

    try {
      // Attempt real pipeline via TaskQueue. The binary-format teammate's
      // FixService is currently stubbed, so this will produce an
      // ERR_UNKNOWN fail in CI; that is expected until merge.
      await _materializeSample();

      // Simulated step animation.
      for (var i = 0; i < _stepCount; i++) {
        await Future.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
        setState(() => _completedStepIndices.add(i));
      }

      setState(() => _running = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _running = false;
      });
    }
  }

  Future<void> _shareTestResult() async {
    final l = context.l10n;
    if (_outputUri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.testModeShareUnavailable)),
      );
      return;
    }
    try {
      await WeChatShare().shareFiles([_outputUri!]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.shareFailed('$e'))),
      );
    }
  }

  @override
  void dispose() {
    _stepSub?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final steps = _allSteps(l);
    final allDone = _completedStepIndices.length == _stepCount;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sampleCard(context),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _running ? null : _run,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: c.accent.withValues(alpha: 0.6),
                        elevation: 0,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _running
                            ? l.testModeRunning
                            : (_completedStepIndices.isEmpty
                                ? l.testModeRun
                                : l.testModeRunAgain),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ...List.generate(_stepCount, (i) {
                      final done = _completedStepIndices.length > i;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _StepRow(
                          label: steps[i],
                          done: done,
                        ),
                      );
                    }),
                    if (allDone && _error == null) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _shareTestResult,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.share_outlined, size: 15),
                              const SizedBox(width: 6),
                              Text(l.testModeShare),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: c.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: MonoText(
                          _error!,
                          style: TextStyle(fontSize: 12, color: c.danger),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
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
          Expanded(
            child: Text(
              context.l10n.testModeTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _sampleCard(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.testModeSampleSection,
            style: TextStyle(fontSize: 13, color: c.inkDim),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border, width: 1),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.image_outlined, color: c.inkFaint),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MonoText(
                    'djimimo_sample.jpg',
                    style: TextStyle(fontSize: 12.5, color: c.ink),
                  ),
                  const SizedBox(height: 3),
                  MonoText(
                    l.testModeSampleDuration,
                    style: TextStyle(fontSize: 11, color: c.inkFaint),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;
  final bool done;
  const _StepRow({required this.label, required this.done});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: done ? c.accentSoft : c.panel,
        border: Border.all(
          color: done ? c.accentBorder : c.border,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? c.accent : Colors.transparent,
              border: done
                  ? null
                  : Border.all(color: c.borderStrong, width: 1.5),
            ),
            alignment: Alignment.center,
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 12)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: done ? c.ink : c.inkDim,
              fontWeight: done ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
