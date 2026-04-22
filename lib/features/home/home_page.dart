// Owner: T3 (UI teammate). Reference: Doc 1 §5.3.1 HomePage + brand §5.1
// masthead + JSX design-v2/project/components/home.jsx.
//
// Editorial masthead with large two-line title, centered decorative
// waveform (clean scanning demo), FIXED counter, status chip, and
// breathing primary action button.

import 'package:flutter/material.dart';

import '../../l10n/l10n_ext.dart';
import '../../widgets/fixed_counter.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/theme_access.dart';
import '../../widgets/waveform.dart';
import 'widgets/app_mark.dart';
import 'widgets/big_action_button.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              onSettings: () =>
                  Navigator.of(context).pushNamed('/settings'),
            ),
            const SizedBox(height: 14),
            const _Masthead(),
            Expanded(child: _CenteredWaveform()),
            const _StatsStrip(),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: BigActionButton(
                title: context.l10n.homePrimaryCta,
                subtitle: context.l10n.homePrimaryCtaSubtitle,
                onPressed: () =>
                    Navigator.of(context).pushNamed('/gallery'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onSettings;
  const _TopBar({required this.onSettings});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Row(
        children: [
          const AppMark(size: 22),
          const SizedBox(width: 8),
          Text(
            'Liveback',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: c.ink,
              letterSpacing: -0.07,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onSettings,
            icon: Icon(Icons.settings_outlined, color: c.inkDim, size: 22),
            splashRadius: 22,
          ),
        ],
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.4,
              height: 1.18,
              color: c.ink,
            ),
            children: [
              TextSpan(text: l.homeMastheadLine1),
              TextSpan(
                text: l.homeMastheadEmphasis,
                style: TextStyle(color: c.inkDim),
              ),
              TextSpan(text: l.homeMastheadTail),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredWaveform extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final width =
            (constraints.maxWidth - 56).clamp(240.0, 380.0).toDouble();
        return Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // top rule
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(height: 1, color: c.borderStrong),
              ),
              // bottom rule
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(height: 1, color: c.borderStrong),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Waveform(
                  width: width,
                  height: 72,
                  seed: 73,
                  state: WaveformState.scanning,
                  color: c.accent,
                  dim: c.border,
                  showGrid: false,
                ),
              ),
              ..._cornerMarks(c.ink),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _cornerMarks(Color ink) {
    Widget corner(double left, double right, double top, double bottom,
        {required bool l, required bool t}) {
      return Positioned(
        left: l ? left : null,
        right: l ? null : right,
        top: t ? top : null,
        bottom: t ? null : bottom,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            border: Border(
              top: t ? BorderSide(color: ink, width: 1) : BorderSide.none,
              bottom:
                  !t ? BorderSide(color: ink, width: 1) : BorderSide.none,
              left: l ? BorderSide(color: ink, width: 1) : BorderSide.none,
              right:
                  !l ? BorderSide(color: ink, width: 1) : BorderSide.none,
            ),
          ),
        ),
      );
    }

    return [
      corner(-4, -4, -4, -4, l: true, t: true),
      corner(-4, -4, -4, -4, l: false, t: true),
      corner(-4, -4, -4, -4, l: true, t: false),
      corner(-4, -4, -4, -4, l: false, t: false),
    ];
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FixedCounter(),
          Spacer(),
          _LocalOfflineBlock(),
        ],
      ),
    );
  }
}

class _LocalOfflineBlock extends StatelessWidget {
  const _LocalOfflineBlock();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          context.l10n.localOfflineLabel,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            color: c.inkFaint,
          ),
        ),
        const SizedBox(height: 2),
        const StatusChip(kind: StatusChipKind.ready),
      ],
    );
  }
}
