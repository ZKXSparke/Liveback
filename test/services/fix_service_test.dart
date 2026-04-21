import 'dart:io';
import 'dart:typed_data';

import 'package:liveback/core/cancellation.dart';
import 'package:liveback/core/task_phase.dart';
import 'package:liveback/exceptions/liveback_exceptions.dart';
import 'package:liveback/models/fix_result.dart';
import 'package:liveback/services/fix_service.dart';
import 'package:liveback/services/motion_photo_parser.dart';
import 'package:liveback/utils/bytes.dart';
import 'package:test/test.dart';

void main() {
  final djimimoPath = 'test/fixtures/samples/djimimo_baseline.jpg';
  final noMp4Path = 'test/fixtures/samples/no_mp4.jpg';

  group('FixService.fix — end-to-end on djimimo baseline', () {
    late String outputPath;

    setUp(() {
      outputPath = '${Directory.systemTemp.path}/liveback_out_${DateTime.now().microsecondsSinceEpoch}.jpg';
    });

    tearDown(() {
      try { File(outputPath).deleteSync(); } catch (_) {}
      try { File('$outputPath.tmp').deleteSync(); } catch (_) {}
    });

    test('1. kind == completed on first pass', () async {
      final phases = <TaskPhase>[];
      final r = await FixService().fix(
        inputPath: djimimoPath,
        outputPath: outputPath,
        cancel: CancellationToken(),
        onPhase: phases.add,
      );
      expect(r.kind, FixResultKind.completed);
      expect(phases, containsAllInOrder([TaskPhase.parsing, TaskPhase.injectingSef, TaskPhase.writing]));
    });

    test('2. outputSize − originalSize ≥ 56 and < 1024', () async {
      final r = await FixService().fix(
        inputPath: djimimoPath,
        outputPath: outputPath,
        cancel: CancellationToken(),
      );
      final delta = r.outputSizeBytes - r.originalSizeBytes;
      expect(delta, greaterThanOrEqualTo(56)); // inline 24 + trailer 32
      expect(delta, lessThan(1024)); // bounded EXIF delta
    });

    test('3. JPEG SOS..EOI pixel bytes remain byte-identical', () async {
      await FixService().fix(
        inputPath: djimimoPath,
        outputPath: outputPath,
        cancel: CancellationToken(),
      );
      final src = File(djimimoPath).readAsBytesSync();
      final out = File(outputPath).readAsBytesSync();

      // Find SOS (FF DA) in both files. Then compare from SOS onwards
      // up to (in src) the EOI. The output's EOI is at a different file
      // position due to the prepended EXIF shift — but the EOI-terminated
      // stream itself is identical.
      final sosIdxSrc = findBytes(src, Uint8List.fromList([0xFF, 0xDA]));
      final sosIdxOut = findBytes(out, Uint8List.fromList([0xFF, 0xDA]));
      expect(sosIdxSrc, greaterThan(-1));
      expect(sosIdxOut, greaterThan(-1));

      // Find each file's EOI after SOS (search forward).
      final eoiInSrc = _findEoi(src, sosIdxSrc);
      final eoiInOut = _findEoi(out, sosIdxOut);
      expect(eoiInSrc, greaterThan(sosIdxSrc));
      expect(eoiInOut, greaterThan(sosIdxOut));

      final srcLen = eoiInSrc + 2 - sosIdxSrc;
      final outLen = eoiInOut + 2 - sosIdxOut;
      expect(srcLen, outLen);
      for (var i = 0; i < srcLen; i++) {
        expect(out[sosIdxOut + i], src[sosIdxSrc + i],
            reason: 'pixel byte $i differs');
      }
    });

    test('4. Last 4 bytes == "SEFT"; trailer parses back; type_code = 0x0000300A', () async {
      await FixService().fix(
        inputPath: djimimoPath,
        outputPath: outputPath,
        cancel: CancellationToken(),
      );
      final s = await MotionPhotoParser().parse(outputPath);
      expect(s.existingSefTrailer, isNotNull);
      expect(s.existingSefTrailer!.recordCount, 1);
      expect(s.existingSefTrailer!.records[0].typeCode, 0x0000300A);
    });

    test('5. existingSefInlineMarker at jpegEnd (after EXIF rewrite)', () async {
      await FixService().fix(
        inputPath: djimimoPath,
        outputPath: outputPath,
        cancel: CancellationToken(),
      );
      final s = await MotionPhotoParser().parse(outputPath);
      expect(s.hasExistingSefInlineMarker, isTrue);
      expect(s.existingSefInlineMarkerOffset, s.jpegEnd);
    });

    test('6. EXIF Make == "samsung" (lowercase), Model == "Galaxy S23 Ultra"', () async {
      await FixService().fix(
        inputPath: djimimoPath,
        outputPath: outputPath,
        cancel: CancellationToken(),
      );
      final s = await MotionPhotoParser().parse(outputPath);
      expect(s.exifAppOne, isNotNull);
      expect(s.exifAppOne!.make, 'samsung');
      expect(s.exifAppOne!.model, 'Galaxy S23 Ultra');
    });

    test('7. Re-invoking fix() on the output returns skippedAlreadySamsung (NOT throws)', () async {
      // First pass.
      await FixService().fix(
        inputPath: djimimoPath,
        outputPath: outputPath,
        cancel: CancellationToken(),
      );
      // Second pass over the output — must return the skipped kind.
      final secondOut = '${Directory.systemTemp.path}/liveback_second_${DateTime.now().microsecondsSinceEpoch}.jpg';
      try {
        final r = await FixService().fix(
          inputPath: outputPath,
          outputPath: secondOut,
          cancel: CancellationToken(),
        );
        expect(r.kind, FixResultKind.skippedAlreadySamsung);
        // No output file should have been written.
        expect(File(secondOut).existsSync(), isFalse);
        expect(r.outputSizeBytes, r.originalSizeBytes);
      } finally {
        try { File(secondOut).deleteSync(); } catch (_) {}
      }
    });

    test('8. MP4 range in output byte-matches source MP4', () async {
      await FixService().fix(
        inputPath: djimimoPath,
        outputPath: outputPath,
        cancel: CancellationToken(),
      );
      final sSrc = await MotionPhotoParser().parse(djimimoPath);
      final sOut = await MotionPhotoParser().parse(outputPath);
      final srcMp4 = File(djimimoPath).readAsBytesSync()
          .sublist(sSrc.mp4Start!, sSrc.mp4End!);
      final outMp4 = File(outputPath).readAsBytesSync()
          .sublist(sOut.mp4Start!, sOut.mp4End!);
      expect(outMp4.length, srcMp4.length);
      for (var i = 0; i < srcMp4.length; i++) {
        expect(outMp4[i], srcMp4[i], reason: 'MP4 byte $i differs');
      }
    });

    test('9. fix() on a no-MP4 source returns skippedNotMotionPhoto (NOT throws)', () async {
      final r = await FixService().fix(
        inputPath: noMp4Path,
        outputPath: outputPath,
        cancel: CancellationToken(),
      );
      expect(r.kind, FixResultKind.skippedNotMotionPhoto);
      expect(File(outputPath).existsSync(), isFalse);
      expect(r.outputSizeBytes, r.originalSizeBytes);
    });
  });

  group('FixService.fix — failure / cancel paths', () {
    test('throws FileTooLargeException when source > maxFileSizeBytes', () async {
      final r = FixService().fix(
        inputPath: 'test/fixtures/samples/djimimo_baseline.jpg',
        outputPath: '${Directory.systemTemp.path}/unused.jpg',
        cancel: CancellationToken(),
        options: const FixOptions(maxFileSizeBytes: 100),
      );
      expect(r, throwsA(isA<FileTooLargeException>()));
    });

    test('throws OperationCancelledException when cancel is pre-set', () async {
      final tok = CancellationToken()..cancel();
      expect(
        () => FixService().fix(
          inputPath: 'test/fixtures/samples/djimimo_baseline.jpg',
          outputPath: '${Directory.systemTemp.path}/unused.jpg',
          cancel: tok,
        ),
        throwsA(isA<OperationCancelledException>()),
      );
    });
  });

  group('FixService.fix — dateTakenMs fallback (review B7)', () {
    test('uses DateTime.now() when EXIF has no DateTimeOriginal', () async {
      final outputPath = '${Directory.systemTemp.path}/dte_${DateTime.now().microsecondsSinceEpoch}.jpg';
      try {
        final before = DateTime.now().millisecondsSinceEpoch;
        final r = await FixService().fix(
          inputPath: 'test/fixtures/samples/djimimo_baseline.jpg',
          outputPath: outputPath,
          cancel: CancellationToken(),
        );
        final after = DateTime.now().millisecondsSinceEpoch;
        // dateTakenMs is set regardless of kind.
        expect(r.dateTakenMs, greaterThanOrEqualTo(before));
        expect(r.dateTakenMs, lessThanOrEqualTo(after));
      } finally {
        try { File(outputPath).deleteSync(); } catch (_) {}
      }
    });
  });
}

/// Finds an EOI (`FF D9`) from [start], respecting JPEG byte stuffing
/// (a literal `FF 00` inside entropy data is not an EOI).
int _findEoi(List<int> bytes, int start) {
  var i = start;
  while (i + 1 < bytes.length) {
    if (bytes[i] == 0xFF) {
      final n = bytes[i + 1];
      if (n == 0x00) { i += 2; continue; }
      if (n >= 0xD0 && n <= 0xD7) { i += 2; continue; }
      if (n == 0xD9) return i;
    }
    i += 1;
  }
  return -1;
}
