// Runs MotionPhotoProbeDart against the two real-world samples that live
// at the top of the main repo (D:\repos\livephoto\). Validates the
// probe's Motion-Photo / Samsung-native classification matches our
// expectations before the Kotlin version is exercised on-device.
//
// Usage:
//   dart run tool/probe_samples_smoke.dart
//
// Exit 0 on success (both samples match expectations). Exit 1 on any
// mismatch.

import 'dart:io';

import 'package:liveback/services/motion_photo_probe.dart';

Future<void> main() async {
  // Samples sit at the top of the SIBLING main repo per the brief.
  // Path is intentionally hardcoded — this tool is a local dev utility,
  // not a general-purpose CLI.
  const samsungPath = r'D:\repos\livephoto\20260420_140350.jpg';
  const djimimoPath = r'D:\repos\livephoto\dji_export_photo_20260420141649266.jpg';

  final cases = <_ProbeCase>[
    _ProbeCase(
      label: 'Samsung S23 native Motion Photo',
      path: samsungPath,
      expectIsMotionPhoto: true,
      expectIsSamsungNative: true,
    ),
    _ProbeCase(
      label: 'djimimo-exported Motion Photo',
      path: djimimoPath,
      expectIsMotionPhoto: true,
      expectIsSamsungNative: false,
    ),
  ];

  final probe = MotionPhotoProbeDart();
  var ok = true;

  for (final c in cases) {
    final file = File(c.path);
    if (!await file.exists()) {
      stderr.writeln('MISSING  ${c.path}');
      stderr.writeln('  (expected sample not found; skipping case)');
      ok = false;
      continue;
    }
    final sw = Stopwatch()..start();
    final r = await probe.probeFile(c.path);
    sw.stop();
    final size = await file.length();
    final matches = r.isMotionPhoto == c.expectIsMotionPhoto &&
        r.isSamsungNative == c.expectIsSamsungNative;
    stdout.writeln('[${matches ? 'OK ' : 'FAIL'}] ${c.label}');
    stdout.writeln('       path:             ${c.path}');
    stdout.writeln('       size:             $size bytes');
    stdout.writeln('       elapsed:          ${sw.elapsedMicroseconds / 1000.0} ms');
    stdout.writeln('       isMotionPhoto:    ${r.isMotionPhoto}  '
        '(expected ${c.expectIsMotionPhoto})');
    stdout.writeln('       isSamsungNative:  ${r.isSamsungNative}  '
        '(expected ${c.expectIsSamsungNative})');
    stdout.writeln('');
    if (!matches) ok = false;
  }

  if (!ok) {
    stderr.writeln('smoke: one or more samples disagreed with expectations');
    exit(1);
  }
  stdout.writeln('smoke: all samples matched expectations');
}

class _ProbeCase {
  final String label;
  final String path;
  final bool expectIsMotionPhoto;
  final bool expectIsSamsungNative;
  _ProbeCase({
    required this.label,
    required this.path,
    required this.expectIsMotionPhoto,
    required this.expectIsSamsungNative,
  });
}
