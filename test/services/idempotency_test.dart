// Exhaustive tests for the Doc 2 §8.1 idempotency rule.
//
// "Already Samsung format" requires ALL of:
//   (1) Make == 'samsung' (case-insensitive, null-terminator trimmed)
//   (2) Last 4 bytes == 'SEFT'
//   (3) SEFH magic at EOF - 8 - sef_size
//   (4) At least one record with type_code = 0x0000300A
//
// fix_service returns FixResult(kind: skippedAlreadySamsung) when all
// four hold; processes normally otherwise.

import 'dart:io';
import 'dart:typed_data';

import 'package:liveback/core/cancellation.dart';
import 'package:liveback/models/fix_result.dart';
import 'package:liveback/services/fix_service.dart';
import 'package:liveback/utils/bytes.dart';
import 'package:test/test.dart';

void main() {
  final djimimoPath = 'test/fixtures/samples/djimimo_baseline.jpg';

  late String outputPath;
  setUp(() {
    outputPath = '${Directory.systemTemp.path}/idemp_${DateTime.now().microsecondsSinceEpoch}.jpg';
  });
  tearDown(() {
    try { File(outputPath).deleteSync(); } catch (_) {}
    try { File('$outputPath.tmp').deleteSync(); } catch (_) {}
  });

  group('idempotency — rule (1): Make must equal "samsung"', () {
    test('Liveback output → second pass is skipped', () async {
      final r1 = await FixService().fix(
        inputPath: djimimoPath,
        outputPath: outputPath,
        cancel: CancellationToken(),
      );
      expect(r1.kind, FixResultKind.completed);

      final out2 = '${Directory.systemTemp.path}/idemp2_${DateTime.now().microsecondsSinceEpoch}.jpg';
      try {
        final r2 = await FixService().fix(
          inputPath: outputPath,
          outputPath: out2,
          cancel: CancellationToken(),
        );
        expect(r2.kind, FixResultKind.skippedAlreadySamsung);
      } finally {
        try { File(out2).deleteSync(); } catch (_) {}
      }
    });

    test('SEF trailer + different Make → NOT skipped', () async {
      // Build a file with valid SEF trailer + inline marker but Make="wrongbrand".
      final synth = await _buildFileWithTrailer(
        djimimoPath,
        makeStr: 'Nikon',
        includeSamsungRecord: true,
      );
      try {
        final r = await FixService().fix(
          inputPath: synth,
          outputPath: outputPath,
          cancel: CancellationToken(),
        );
        expect(r.kind, FixResultKind.completed);
      } finally {
        try { File(synth).deleteSync(); } catch (_) {}
      }
    });

    test('Make matches case-insensitively ("SAMSUNG" -> skipped)', () async {
      final synth = await _buildFileWithTrailer(
        djimimoPath,
        makeStr: 'SAMSUNG',
        includeSamsungRecord: true,
      );
      try {
        final r = await FixService().fix(
          inputPath: synth,
          outputPath: outputPath,
          cancel: CancellationToken(),
        );
        expect(r.kind, FixResultKind.skippedAlreadySamsung);
      } finally {
        try { File(synth).deleteSync(); } catch (_) {}
      }
    });
  });

  group('idempotency — rule (4): must have MotionPhoto_Data record', () {
    test('trailer has records but none of type 0x0000300A → NOT skipped', () async {
      // SEFH trailer + record with some OTHER type code. Must pass rule 1-3
      // but fail rule 4.
      final synth = await _buildFileWithTrailer(
        djimimoPath,
        makeStr: 'samsung',
        includeSamsungRecord: false, // type_code = 0x0A01 (bogus)
      );
      try {
        final r = await FixService().fix(
          inputPath: synth,
          outputPath: outputPath,
          cancel: CancellationToken(),
        );
        expect(r.kind, FixResultKind.completed);
      } finally {
        try { File(synth).deleteSync(); } catch (_) {}
      }
    });
  });

  group('idempotency — rule (2)/(3): SEFH/SEFT magic coherence', () {
    test('djimimo baseline (no SEF at all) → not skipped', () async {
      final r = await FixService().fix(
        inputPath: djimimoPath,
        outputPath: outputPath,
        cancel: CancellationToken(),
      );
      expect(r.kind, FixResultKind.completed);
    });

    test('file with stray SEFT bytes but no valid SEFH → not skipped', () async {
      final src = File(djimimoPath).readAsBytesSync();
      final tmp = '${Directory.systemTemp.path}/stray_seft_${DateTime.now().microsecondsSinceEpoch}.jpg';
      // Append bogus "SEFT" bytes at EOF without proper SEFH structure.
      final bogus = <int>[...src, 0x53, 0x45, 0x46, 0x54];
      File(tmp).writeAsBytesSync(bogus);
      try {
        final r = await FixService().fix(
          inputPath: tmp,
          outputPath: outputPath,
          cancel: CancellationToken(),
        );
        expect(r.kind, FixResultKind.completed);
      } finally {
        try { File(tmp).deleteSync(); } catch (_) {}
      }
    });
  });
}

/// Builds a synthetic file that mimics a Liveback output:
///   [djimimo prefix up to jpegEnd] + [inline marker 24 B] +
///   [mp4 range] + [SEF trailer 32 B]
///
/// But customizes the EXIF Make (inside the prefix) and optionally
/// suppresses the MotionPhoto_Data record type.
Future<String> _buildFileWithTrailer(
  String sourcePath, {
  required String makeStr,
  required bool includeSamsungRecord,
}) async {
  // Start from the Liveback output (which has all structure), then patch
  // the Make bytes inside the EXIF, and/or munge the record type_code.
  final outputPath = '${Directory.systemTemp.path}/built_${DateTime.now().microsecondsSinceEpoch}.jpg';
  // First produce a Liveback output.
  await FixService().fix(
    inputPath: sourcePath,
    outputPath: outputPath,
    cancel: CancellationToken(),
  );
  final bytes = File(outputPath).readAsBytesSync();

  // Patch EXIF Make. Liveback outputs lowercase "samsung\0" in 8 bytes.
  // Find it and overwrite in-place (padded to 8 bytes).
  final needle = Uint8List.fromList([0x73, 0x61, 0x6D, 0x73, 0x75, 0x6E, 0x67, 0x00]);
  final idx = findBytes(bytes, needle);
  if (idx > 0) {
    final patched = Uint8List.fromList(bytes);
    // Write makeStr padded with nulls to 8 bytes.
    for (var i = 0; i < 8; i++) {
      patched[idx + i] = i < makeStr.length ? makeStr.codeUnitAt(i) : 0;
    }
    File(outputPath).writeAsBytesSync(patched);
  }

  if (!includeSamsungRecord) {
    final patched2 = File(outputPath).readAsBytesSync();
    // Record type_code is at (EOF - 32 + 12) = EOF - 20 → 4 bytes.
    final p = patched2.length - 20;
    // Change type_code from 00 00 30 0A → 0A 01 00 00 (junk).
    patched2[p] = 0x0A;
    patched2[p + 1] = 0x01;
    patched2[p + 2] = 0x00;
    patched2[p + 3] = 0x00;
    File(outputPath).writeAsBytesSync(patched2);
  }

  return outputPath;
}
