// Owner: T3 (UI teammate). Reference: brand §6 "FIXED 0247" counter +
// Doc 1 §2.4 persistence (liveback.fixed_count key in SharedPreferences).
//
// Reads from [TaskQueue.instance.fixedCount] — that singleton owns the
// SharedPreferences I/O and increments on every completed task. This
// widget just formats the number as 4-digit zero-padded mono glyph.

import 'package:flutter/material.dart';

import '../services/task_queue.dart';
import 'mono_text.dart';
import 'theme_access.dart';

class FixedCounter extends StatelessWidget {
  const FixedCounter({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ValueListenableBuilder<int>(
      valueListenable: TaskQueue.instance.fixedCount,
      builder: (ctx, count, _) {
        final padded = count.toString().padLeft(4, '0');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MonoText(
              'FIXED',
              style: TextStyle(
                fontSize: 10,
                color: c.inkFaint,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 2),
            MonoText(
              padded,
              style: TextStyle(
                fontSize: 22,
                color: c.ink,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.44,
              ),
            ),
          ],
        );
      },
    );
  }
}
