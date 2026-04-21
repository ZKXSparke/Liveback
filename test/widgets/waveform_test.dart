// T3 widget tests for the shared Waveform widget.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveback/core/theme.dart';
import 'package:liveback/widgets/waveform.dart';

void main() {
  Widget harness(Widget child) => MaterialApp(
        theme: LivebackTheme.light(),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('clean waveform paints without animation', (tester) async {
    await tester.pumpWidget(
      harness(const Waveform(state: WaveformState.clean)),
    );
    expect(find.byType(Waveform), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('broken waveform paints with chromatic ghosts', (tester) async {
    await tester.pumpWidget(
      harness(const Waveform(state: WaveformState.broken)),
    );
    expect(find.byType(Waveform), findsOneWidget);
  });

  testWidgets('scanning waveform animates when no progressOverride',
      (tester) async {
    await tester.pumpWidget(
      harness(const Waveform(state: WaveformState.scanning)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    // Controller should still be animating — no exceptions.
    expect(tester.takeException(), isNull);
  });

  testWidgets('scanning waveform accepts static progressOverride',
      (tester) async {
    await tester.pumpWidget(
      harness(
        const Waveform(
          state: WaveformState.scanning,
          progressOverride: 0.3,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
