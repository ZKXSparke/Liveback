// Smoke test for the gallery-tile preview MP4-extraction path.
//
// Runs MotionPhotoParser against a real JPEG path, then — if the parser
// reports a Motion Photo — streams the MP4 byte range (mp4Start..mp4End)
// into ./extracted.mp4 using the same extractMp4Range helper the runtime
// PreviewPage uses.
//
// Usage:
//   dart run tool/extract_mp4_smoke.dart <input.jpg> [<output.mp4>]
//
// Default output path: ./extracted.mp4 (cwd-relative).
//
// Prints:
//   - input size
//   - parser result: isMotionPhoto / mp4Start / mp4End / expected span
//   - extracted file byte count
//   - EOF of the extracted file (last 4 bytes hex) — useful to eyeball
//     that the MP4 ends mid-box (no SEF trailer leakage into the MP4).

import 'dart:io';

import 'package:liveback/features/preview/extract_mp4_range.dart';
import 'package:liveback/services/motion_photo_parser.dart';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln(
        'usage: dart run tool/extract_mp4_smoke.dart <input.jpg> [<output.mp4>]');
    exit(64);
  }
  final inputPath = argv[0];
  final outputPath = argv.length > 1 ? argv[1] : 'extracted.mp4';

  final input = File(inputPath);
  if (!input.existsSync()) {
    stderr.writeln('input not found: $inputPath');
    exit(66);
  }
  final inputSize = input.lengthSync();
  stdout.writeln('input:  $inputPath (${_fmtSize(inputSize)})');
  stdout.writeln('output: $outputPath');

  final structure = await MotionPhotoParser().parse(inputPath);
  final start = structure.mp4Start;
  final end = structure.mp4End;
  final isMotionPhoto = start != null && end != null && end > start;
  stdout.writeln('');
  stdout.writeln('parser:');
  stdout.writeln('  fileSize:      ${structure.fileSize}');
  stdout.writeln('  jpegEnd:       ${structure.jpegEnd}');
  stdout.writeln('  mp4Start:      $start');
  stdout.writeln('  mp4End:        $end');
  stdout.writeln('  isMotionPhoto: $isMotionPhoto');

  if (!isMotionPhoto) {
    stderr.writeln('not a Motion Photo — nothing to extract.');
    exit(1);
  }

  final written = await extractMp4Range(
    srcPath: inputPath,
    mp4Start: start,
    mp4End: end,
    dstPath: outputPath,
  );
  stdout.writeln('');
  stdout.writeln('extracted:');
  stdout.writeln('  bytes written: $written (${_fmtSize(written)})');
  stdout.writeln('  expected span: ${end - start}');

  // Peek at last 4 bytes of the extracted MP4 — for manual sanity only.
  final raf = File(outputPath).openSync();
  try {
    final size = raf.lengthSync();
    raf.setPositionSync(size < 4 ? 0 : size - 4);
    final tail = raf.readSync(4);
    stdout.writeln('  tail(4):       ${_hex(tail)}');
  } finally {
    raf.closeSync();
  }
}

String _fmtSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ');
