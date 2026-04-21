// Minimal end-to-end smoke test for fix_service.fix() against an
// external Motion Photo sample (NOT checked into the repo).
//
// Usage:
//   dart run tool/end_to_end_smoke.dart <input.jpg> [<output.jpg>]
//
// Default output path: <systemTemp>/liveback_smoke_out.jpg
//
// Prints:
//   - input size
//   - FixResult.kind / elapsedMs / outputSizeBytes / delta
//   - presence of "SEFT" at EOF
//   - a second-pass run — should return skippedAlreadySamsung

import 'dart:io';

import 'package:liveback/core/cancellation.dart';
import 'package:liveback/core/task_phase.dart';
import 'package:liveback/services/fix_service.dart';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln('usage: dart run tool/end_to_end_smoke.dart <input.jpg> [<output.jpg>]');
    exit(64);
  }
  final inputPath = argv[0];
  final outputPath = argv.length > 1
      ? argv[1]
      : '${Directory.systemTemp.path}/liveback_smoke_${DateTime.now().microsecondsSinceEpoch}.jpg';

  final inputSize = File(inputPath).lengthSync();
  stdout.writeln('input:  $inputPath (${_fmtSize(inputSize)})');
  stdout.writeln('output: $outputPath');

  final svc = FixService();
  final phases = <TaskPhase>[];
  final r1 = await svc.fix(
    inputPath: inputPath,
    outputPath: outputPath,
    cancel: CancellationToken(),
    onPhase: phases.add,
  );
  stdout.writeln('');
  stdout.writeln('pass 1:');
  stdout.writeln('  kind:                ${r1.kind.name}');
  stdout.writeln('  elapsedMs:           ${r1.elapsedMs}');
  stdout.writeln('  originalSizeBytes:   ${r1.originalSizeBytes}');
  stdout.writeln('  outputSizeBytes:     ${r1.outputSizeBytes}');
  stdout.writeln('  delta:               ${r1.outputSizeBytes - r1.originalSizeBytes}');
  stdout.writeln('  videoDurationSec:    ${r1.videoDurationSeconds}');
  stdout.writeln('  videoTooLongWarn:    ${r1.videoTooLongWarning}');
  stdout.writeln('  dateTakenMs:         ${r1.dateTakenMs}');
  stdout.writeln('  phases emitted:      ${phases.map((p) => p.name).join(" -> ")}');

  if (File(outputPath).existsSync()) {
    // Check last 4 bytes.
    final raf = File(outputPath).openSync();
    try {
      final fSize = raf.lengthSync();
      raf.setPositionSync(fSize - 4);
      final tail = raf.readSync(4);
      stdout.writeln('  EOF tail:            ${_hex(tail)}  ${String.fromCharCodes(tail)}');
    } finally {
      raf.closeSync();
    }

    // Second pass — should skip.
    final second = '${outputPath}_pass2.jpg';
    final r2 = await svc.fix(
      inputPath: outputPath,
      outputPath: second,
      cancel: CancellationToken(),
    );
    stdout.writeln('');
    stdout.writeln('pass 2 (over pass-1 output):');
    stdout.writeln('  kind:                ${r2.kind.name}');
    stdout.writeln('  output file exists:  ${File(second).existsSync()}');
    try { File(second).deleteSync(); } catch (_) {}
  }
}

String _fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
