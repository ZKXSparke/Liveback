// Owner: T3 (UI teammate). Reference: brand §6 bottom status chip.
//
// Home page "LOCAL·OFFLINE · READY" strip. Three variants:
//   READY   — success dot (brand §3: success == ink, editorial restraint)
//   SYNCING — chromaCyan dot (processing hint, brand rule §3.4)
//   ERROR   — chromaMagenta dot (rare, reserved)

import 'package:flutter/material.dart';

import '../l10n/l10n_ext.dart';
import 'mono_text.dart';
import 'theme_access.dart';

enum StatusChipKind { ready, syncing, error }

class StatusChip extends StatelessWidget {
  final StatusChipKind kind;

  const StatusChip({super.key, required this.kind});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = context.l10n;
    final (label, color) = switch (kind) {
      StatusChipKind.ready => (l.statusChipReady, c.success),
      StatusChipKind.syncing => (l.statusChipSyncing, c.chromaCyan),
      StatusChipKind.error => (l.statusChipError, c.chromaMagenta),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        MonoText(
          label,
          style: TextStyle(
            fontSize: 13,
            color: c.ink,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
