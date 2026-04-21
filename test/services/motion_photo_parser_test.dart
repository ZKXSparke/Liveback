import 'dart:io';

import 'package:liveback/core/cancellation.dart';
import 'package:liveback/exceptions/liveback_exceptions.dart';
import 'package:liveback/services/motion_photo_parser.dart';
import 'package:test/test.dart';

void main() {
  final djimimoPath = 'test/fixtures/samples/djimimo_baseline.jpg';
  final noSoiPath = 'test/fixtures/samples/invalid_no_soi.jpg';
  final truncatedPath = 'test/fixtures/samples/invalid_truncated.jpg';
  final noMp4Path = 'test/fixtures/samples/no_mp4.jpg';

  group('MotionPhotoParser.parse — happy path (djimimo)', () {
    test('returns a populated structure', () async {
      final s = await MotionPhotoParser().parse(djimimoPath);
      final fileSize = File(djimimoPath).lengthSync();
      expect(s.fileSize, fileSize);
      expect(s.jpegStart, 0);
      expect(s.jpegEnd, greaterThan(100));
      expect(s.jpegEnd, lessThan(fileSize));
    });

    test('parses EXIF block (no Make/Model on djimimo)', () async {
      final s = await MotionPhotoParser().parse(djimimoPath);
      expect(s.exifAppOne, isNotNull);
      expect(s.exifAppOne!.segmentStart, 2); // right after SOI
      // djimimo source has no Make/Model.
      expect(s.exifAppOne!.make, anyOf(isNull, equals('')));
      expect(s.exifAppOne!.model, anyOf(isNull, equals('')));
    });

    test('detects XMP segment offset', () async {
      final s = await MotionPhotoParser().parse(djimimoPath);
      expect(s.xmpSegmentOffset, isNotNull);
      expect(s.xmpSegmentOffset, greaterThan(2));
    });

    test('locates ftyp / MP4 start + end', () async {
      final s = await MotionPhotoParser().parse(djimimoPath);
      expect(s.mp4Start, isNotNull);
      expect(s.mp4End, isNotNull);
      expect(s.mp4End! > s.mp4Start!, isTrue);
      // Read 4 bytes at mp4Start + 4 and expect "ftyp".
      final raf = await File(djimimoPath).open();
      try {
        await raf.setPosition(s.mp4Start! + 4);
        final bytes = await raf.read(4);
        expect(String.fromCharCodes(bytes), 'ftyp');
      } finally {
        await raf.close();
      }
    });

    test('probes mvhd duration (0.5 s)', () async {
      final s = await MotionPhotoParser().parse(djimimoPath);
      expect(s.videoDurationSeconds, isNotNull);
      expect(s.videoDurationSeconds, closeTo(0.5, 1e-6));
    });

    test('detects no SEF trailer (djimimo is un-repaired)', () async {
      final s = await MotionPhotoParser().parse(djimimoPath);
      expect(s.existingSefTrailer, isNull);
      expect(s.hasExistingSefInlineMarker, isFalse);
    });
  });

  group('MotionPhotoParser.parse — degenerate inputs', () {
    test('throws InvalidFileFormatException on missing SOI', () async {
      expect(
        () => MotionPhotoParser().parse(noSoiPath),
        throwsA(isA<InvalidFileFormatException>()),
      );
    });

    test('throws InvalidFileFormatException on truncated JPEG', () async {
      expect(
        () => MotionPhotoParser().parse(truncatedPath),
        throwsA(isA<InvalidFileFormatException>()),
      );
    });

    test('returns structure with mp4Start == null when no MP4 present', () async {
      final s = await MotionPhotoParser().parse(noMp4Path);
      expect(s.mp4Start, isNull);
      expect(s.mp4End, isNull);
      expect(s.videoDurationSeconds, isNull);
    });

    test('throws InvalidFileFormatException on empty/tiny file', () async {
      final tmp = File('${Directory.systemTemp.path}/tiny_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes([0xFF]);
      try {
        await expectLater(
          MotionPhotoParser().parse(tmp.path),
          throwsA(isA<InvalidFileFormatException>()),
        );
      } finally {
        try { await tmp.delete(); } catch (_) { /* windows file-lock race, non-fatal */ }
      }
    });
  });

  group('MotionPhotoParser — cancellation', () {
    test('throws OperationCancelledException when cancel is pre-set', () async {
      final token = CancellationToken()..cancel();
      expect(
        () => MotionPhotoParser().parse(djimimoPath, cancel: token, taskId: 'tx1'),
        throwsA(isA<OperationCancelledException>()),
      );
    });
  });

  group('MotionPhotoParser — Samsung-style input (after fix)', () {
    test('detects SEF trailer + inline marker on a synthetic Liveback output', () async {
      // Build a synthetic "already fixed" file: djimimo_baseline with
      // inline marker + SEF trailer appended in the proper layout.
      final dji = File(djimimoPath).readAsBytesSync();
      final parser = MotionPhotoParser();

      // First, parse to find the natural mp4Start/mp4End.
      final raw = await parser.parse(djimimoPath);
      expect(raw.mp4Start, isNotNull);
      final mp4Start = raw.mp4Start!;
      final mp4End = raw.mp4End!;

      // Assemble [0..jpegEnd] + inline(24) + [mp4Start..mp4End] + trailer(32).
      final jpegEnd = raw.jpegEnd;
      final inline = [
        0x00, 0x00, 0x30, 0x0A,
        0x10, 0x00, 0x00, 0x00,
        0x4D, 0x6F, 0x74, 0x69, 0x6F, 0x6E, 0x50, 0x68,
        0x6F, 0x74, 0x6F, 0x5F, 0x44, 0x61, 0x74, 0x61,
      ];
      final mp4Len = mp4End - mp4Start;
      final off = 24 + mp4Len;
      // Build trailer (32 B) per Doc 2 §3.3.
      final trailer = <int>[]
        ..addAll([0x53, 0x45, 0x46, 0x48])            // SEFH
        ..addAll([0x6A, 0x00, 0x00, 0x00])            // ver 106 LE
        ..addAll([0x01, 0x00, 0x00, 0x00])            // count 1
        ..addAll([0x00, 0x00, 0x30, 0x0A])            // type
        ..addAll([off & 0xFF, (off >> 8) & 0xFF, (off >> 16) & 0xFF, (off >> 24) & 0xFF])
        ..addAll([off & 0xFF, (off >> 8) & 0xFF, (off >> 16) & 0xFF, (off >> 24) & 0xFF])
        ..addAll([0x18, 0x00, 0x00, 0x00])            // total_sef_size 24
        ..addAll([0x53, 0x45, 0x46, 0x54]);           // SEFT
      final out = <int>[]
        ..addAll(dji.sublist(0, jpegEnd))
        ..addAll(inline)
        ..addAll(dji.sublist(mp4Start, mp4End))
        ..addAll(trailer);
      final tmp = File('${Directory.systemTemp.path}/fake_fixed_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await tmp.writeAsBytes(out, flush: true);
      try {
        final s = await parser.parse(tmp.path);
        expect(s.hasExistingSefInlineMarker, isTrue);
        expect(s.existingSefInlineMarkerOffset, jpegEnd);
        expect(s.existingSefTrailer, isNotNull);
        expect(s.existingSefTrailer!.recordCount, 1);
        expect(s.existingSefTrailer!.records[0].typeCode, 0x0000300A);
        expect(s.existingSefTrailer!.records[0].offsetFromSefh, off);
      } finally {
        await tmp.delete();
      }
    });
  });
}
