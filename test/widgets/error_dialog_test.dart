// T3 widget test — ErrorDialog renders with glitch traits (error code
// chip with `>` prefix + terminal-style mono + dark-mode card regardless
// of theme mode).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveback/core/theme.dart';
import 'package:liveback/widgets/dialog/error_dialog.dart';

void main() {
  testWidgets('ErrorDialog renders errorCode chip with > prefix',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LivebackTheme.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showErrorDialog(
                  ctx,
                  errorCode: 'ERR_SEF_WRITE_FAIL',
                  title: '修复失败',
                  body: '写入 SEF trailer 失败',
                  canRetry: true,
                ),
                child: const Text('trigger'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    // Terminal-style chip with `>` prefix.
    expect(find.text('> ERR_SEF_WRITE_FAIL'), findsOneWidget);
    // Title shows up three times (cyan ghost + magenta ghost + main).
    expect(find.text('修复失败'), findsNWidgets(3));
    // Body + buttons present.
    expect(find.text('写入 SEF trailer 失败'), findsOneWidget);
    expect(find.text('返回'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
