// T3 integration test — minimal smoke: app boots, HomePage tap pushes
// /gallery; gallery loads empty list (MediaStoreChannel stub throws
// UnimplementedError so the retry state shows). This establishes the
// app-shell bring-up works through the full MaterialApp routing path.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liveback/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots and renders HomePage masthead', (tester) async {
    await tester.pumpWidget(const LivebackApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Masthead title present (the `重新` span lives inside the big title).
    expect(find.text('选择实况图'), findsOneWidget);
    expect(find.text('Liveback'), findsOneWidget);
  });

  testWidgets('tap big button pushes /gallery', (tester) async {
    await tester.pumpWidget(const LivebackApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('选择实况图'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Gallery page header renders — we land on the "选择实况图 · N/100" title.
    expect(find.textContaining('选择实况图 ·'), findsOneWidget);
  });
}
