import 'dart:io';
import 'dart:typed_data';

import 'package:liveback/exceptions/liveback_exceptions.dart';
import 'package:liveback/services/exif_rewriter.dart';
import 'package:liveback/utils/bytes.dart';
import 'package:test/test.dart';

void main() {
  group('ExifRewriter.rewriteMakeModel — fast path', () {
    test('in-place overwrite produces golden bytes', () {
      final full = File('test/fixtures/exif_rewriter/full_exif_ifd0.bin').readAsBytesSync();
      final golden = File('test/fixtures/exif_rewriter/rewritten_golden.bin').readAsBytesSync();
      final out = ExifRewriter().rewriteMakeModel(
        originalAppOne: full,
        make: 'samsung',
        model: 'Galaxy S23 Ultra',
      );
      expect(out.length, 1);
      expect(out.single, orderedEquals(golden));
      // Fast path should keep the total length identical.
      expect(out.single.length, full.length);
    });

    test('non-destructive: other IFD0 entries remain byte-identical', () {
      final full = File('test/fixtures/exif_rewriter/full_exif_ifd0.bin').readAsBytesSync();
      final out = ExifRewriter()
          .rewriteMakeModel(
            originalAppOne: full,
            make: 'samsung',
            model: 'Galaxy S23 Ultra',
          )
          .single;
      // Orientation inline value (@entry 0x012 in our synthesized layout) is
      // at IFD0 +2 + 2*12 + 8 = 34 from TIFF start, i.e. 34 + 10 = 44 from
      // APP1 start. Value bytes should be [1, 0, 0, 0] (SHORT inline).
      // But it's easier to just check that bytes OUTSIDE the pool regions
      // for Make (62..70) and Model (70..87) are identical.
      for (var i = 0; i < full.length; i++) {
        final makeStart = 10 + 62;
        final makeEnd = makeStart + 8;
        final modelStart = 10 + 70;
        final modelEnd = modelStart + 17;
        if (i >= makeStart && i < makeEnd) continue;
        if (i >= modelStart && i < modelEnd) continue;
        expect(out[i], full[i], reason: 'byte $i changed unexpectedly');
      }
    });

    test('lowercase samsung is preserved', () {
      final full = File('test/fixtures/exif_rewriter/full_exif_ifd0.bin').readAsBytesSync();
      final out = ExifRewriter()
          .rewriteMakeModel(
            originalAppOne: full,
            make: 'samsung',
            model: 'Galaxy S23 Ultra',
          )
          .single;
      // Make slot at TIFF offset 62 → APP1 offset 72.
      final makeAscii = String.fromCharCodes(out.sublist(72, 79));
      expect(makeAscii, 'samsung');
      expect(out[79], 0x00); // null terminator
    });
  });

  group('ExifRewriter.rewriteMakeModel — slow path (full rebuild)', () {
    test('rewrites a djimimo-style APP1 (no Make/Model) without throwing', () {
      final empty = File('test/fixtures/exif_rewriter/empty_exif_ifd0.bin').readAsBytesSync();
      final out = ExifRewriter()
          .rewriteMakeModel(
            originalAppOne: empty,
            make: 'samsung',
            model: 'Galaxy S23 Ultra',
          )
          .single;
      expect(out[0], 0xFF);
      expect(out[1], 0xE1);
      // "Exif\0\0" at offset 4.
      expect(out.sublist(4, 10), orderedEquals([0x45, 0x78, 0x69, 0x66, 0x00, 0x00]));
      // TIFF header at offset 10.
      expect(out.sublist(10, 14), orderedEquals([0x49, 0x49, 0x2A, 0x00]));
      // Post-rebuild size > original size because we inserted Make + Model.
      expect(out.length, greaterThan(empty.length));
    });

    test('rebuilt APP1 contains the new Make and Model ASCII', () {
      final empty = File('test/fixtures/exif_rewriter/empty_exif_ifd0.bin').readAsBytesSync();
      final out = ExifRewriter()
          .rewriteMakeModel(
            originalAppOne: empty,
            make: 'samsung',
            model: 'Galaxy S23 Ultra',
          )
          .single;
      // Find "samsung\0" and "Galaxy S23 Ultra\0" ASCII substrings.
      final needleMake = Uint8List.fromList([
        0x73, 0x61, 0x6D, 0x73, 0x75, 0x6E, 0x67, 0x00,
      ]);
      final needleModel = Uint8List.fromList([
        0x47, 0x61, 0x6C, 0x61, 0x78, 0x79, 0x20, 0x53, 0x32, 0x33,
        0x20, 0x55, 0x6C, 0x74, 0x72, 0x61, 0x00,
      ]);
      expect(findBytes(out, needleMake), greaterThan(0));
      expect(findBytes(out, needleModel), greaterThan(0));
    });

    test('throws AppOneTooLargeException if APP1 would exceed 64 KB', () {
      // Build a source APP1 near the 64 KB limit: one big ASCII Artist
      // entry (tag 0x013B) that, when combined with inserted Make+Model,
      // pushes the rebuilt TIFF past 65533 bytes.
      //
      // Target: final APP1 length > 65535. APP1 overhead = FFE1(2) +
      // size(2) + "Exif\0\0"(6) + TIFF header(8) = 18 bytes. So the
      // TIFF body (IFD0 dir + value pool) must be > 65517 bytes.
      //
      // Rebuilt IFD0 count = 3 (Artist + Make + Model), dir size =
      // 2 + 3*12 + 4 = 42 bytes. Make/Model pool = 8 + 17 = 25 bytes.
      // So Artist ASCII must be ≥ 65517 - 42 - 25 = 65450 bytes. Use 65500.
      final dummyBig = Uint8List(65500);
      for (var i = 0; i < dummyBig.length; i++) {
        dummyBig[i] = 0x41;
      }
      dummyBig[dummyBig.length - 1] = 0;

      final tiff = BytesBuilder();
      tiff.add([0x49, 0x49, 0x2A, 0x00]);
      _u32Le(tiff, 8);
      _u16Le(tiff, 1); // entry count
      _u16Le(tiff, 0x013B); // Artist
      _u16Le(tiff, 2); // ASCII
      _u32Le(tiff, dummyBig.length);
      _u32Le(tiff, 8 + 2 + 12 + 4); // Artist value pool offset
      _u32Le(tiff, 0); // next_ifd
      tiff.add(dummyBig);
      final tiffBytes = tiff.toBytes();

      // Source APP1 itself might be > 64 KB (we exceed 2-byte size field).
      // To test the REWRITE path cleanly, we need the source to be valid.
      // 65500 + 26 = 65526 + 8 (TIFF header) + 8 ("Exif..." + size) = 65542,
      // minus size field 2 = payload for size field: 65540. 2-byte max is
      // 0xFFFF = 65535 → source itself overflows. Size field will wrap.
      // We accept this: the REWRITER's _wrapInAppOne is the check point.
      //
      // Skip the wrap-source check by writing a size of 0xFFFF (max valid)
      // — source LOOKS valid to the rewriter's parse; the rebuilt output
      // blows past the cap.
      final payloadLen = 2 + 6 + tiffBytes.length;
      // Ensure the source size field can hold (if not, truncate claim).
      final claimedSize = payloadLen > 0xFFFF ? 0xFFFF : payloadLen;
      final app1 = Uint8List(2 + payloadLen);
      app1[0] = 0xFF;
      app1[1] = 0xE1;
      app1[2] = (claimedSize >> 8) & 0xFF;
      app1[3] = claimedSize & 0xFF;
      app1.setRange(4, 10, [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]);
      app1.setRange(10, 10 + tiffBytes.length, tiffBytes);

      expect(
        () => ExifRewriter().rewriteMakeModel(
          originalAppOne: app1,
          make: 'samsung',
          model: 'Galaxy S23 Ultra',
        ),
        throwsA(isA<AppOneTooLargeException>()),
      );
    });

    test('throws InvalidFileFormatException on garbage input', () {
      final garbage = Uint8List.fromList([0xFF, 0xE1, 0, 10, 1, 2, 3, 4, 5, 6, 7, 8]);
      expect(
        () => ExifRewriter().rewriteMakeModel(
          originalAppOne: garbage,
          make: 'samsung',
          model: 'Galaxy S23 Ultra',
        ),
        throwsA(isA<InvalidFileFormatException>()),
      );
    });

    test('throws InvalidFileFormatException on wrong APP marker', () {
      final notApp1 = Uint8List.fromList([
        0xFF, 0xE0, 0, 12, // APP0 not APP1
        0x45, 0x78, 0x69, 0x66, 0x00, 0x00,
        0x49, 0x49, 0x2A, 0x00,
      ]);
      expect(
        () => ExifRewriter().rewriteMakeModel(
          originalAppOne: notApp1,
          make: 'samsung',
          model: 'Galaxy S23 Ultra',
        ),
        throwsA(isA<InvalidFileFormatException>()),
      );
    });
  });

  group('ExifRewriter.buildFreshExifAppOne', () {
    test('produces a valid APP1 EXIF segment', () {
      final out = ExifRewriter().buildFreshExifAppOne(
        make: 'samsung',
        model: 'Galaxy S23 Ultra',
        imageWidth: 4000,
        imageHeight: 3000,
        orientation: 1,
      ).single;
      expect(out[0], 0xFF);
      expect(out[1], 0xE1);
      expect(out.sublist(4, 10), orderedEquals([0x45, 0x78, 0x69, 0x66, 0x00, 0x00]));
      expect(out.sublist(10, 14), orderedEquals([0x49, 0x49, 0x2A, 0x00]));
      // IFD0 offset = 8 (LE).
      expect(out.sublist(14, 18), orderedEquals([8, 0, 0, 0]));
    });

    test('includes Make and Model strings', () {
      final out = ExifRewriter().buildFreshExifAppOne(
        make: 'samsung',
        model: 'Galaxy S23 Ultra',
        imageWidth: 4000,
        imageHeight: 3000,
        orientation: 1,
      ).single;
      final m1 = Uint8List.fromList([
        0x73, 0x61, 0x6D, 0x73, 0x75, 0x6E, 0x67, 0x00,
      ]);
      final m2 = Uint8List.fromList([
        0x47, 0x61, 0x6C, 0x61, 0x78, 0x79, 0x20, 0x53, 0x32, 0x33,
        0x20, 0x55, 0x6C, 0x74, 0x72, 0x61, 0x00,
      ]);
      expect(findBytes(out, m1), greaterThan(0));
      expect(findBytes(out, m2), greaterThan(0));
    });

    test('includes DateTime tag when dateTimeOriginal is provided', () {
      final dt = DateTime.utc(2026, 4, 21, 15, 30, 45);
      final out = ExifRewriter().buildFreshExifAppOne(
        make: 'samsung',
        model: 'Galaxy S23 Ultra',
        imageWidth: 100,
        imageHeight: 100,
        orientation: 1,
        dateTimeOriginal: dt,
      ).single;
      // Look for "2026:04:21 15:30:45\0" ASCII.
      final expectedDt = Uint8List.fromList(
        ('2026:04:21 15:30:45\u0000').codeUnits,
      );
      expect(findBytes(out, expectedDt), greaterThan(0));
    });

    test('omits DateTime tag when not provided', () {
      final out = ExifRewriter().buildFreshExifAppOne(
        make: 'samsung',
        model: 'Galaxy S23 Ultra',
        imageWidth: 100,
        imageHeight: 100,
        orientation: 1,
      ).single;
      // Ensure no ':' byte in the IFD directory area (first 100 B or so).
      // This is a soft sanity check.
      final colon = 0x3A;
      var colonCount = 0;
      for (final b in out) {
        if (b == colon) colonCount += 1;
      }
      expect(colonCount, lessThan(2));
    });

    test('entry count in IFD0 is 5 when no DateTime, 6 with', () {
      final noDt = ExifRewriter().buildFreshExifAppOne(
        make: 'samsung',
        model: 'Galaxy S23 Ultra',
        imageWidth: 100,
        imageHeight: 100,
        orientation: 1,
      ).single;
      // IFD0 at TIFF offset 8 → APP1 offset 18. entry_count (LE uint16).
      final nCountNo = readUint32Le(noDt, 18) & 0xFFFF;
      expect(nCountNo, 5); // ImageWidth, ImageLength, Make, Model, Orientation

      final withDt = ExifRewriter().buildFreshExifAppOne(
        make: 'samsung',
        model: 'Galaxy S23 Ultra',
        imageWidth: 100,
        imageHeight: 100,
        orientation: 1,
        dateTimeOriginal: DateTime(2026),
      ).single;
      final nCountWith = readUint32Le(withDt, 18) & 0xFFFF;
      expect(nCountWith, 6);
    });
  });
}

Uint8List _wrapAppOne(Uint8List tiffBytes) {
  final total = 2 + 6 + tiffBytes.length;
  final out = Uint8List(2 + total);
  out[0] = 0xFF;
  out[1] = 0xE1;
  out[2] = (total >> 8) & 0xFF;
  out[3] = total & 0xFF;
  out.setRange(4, 10, [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]);
  out.setRange(10, 10 + tiffBytes.length, tiffBytes);
  return out;
}

void _u16Le(BytesBuilder b, int v) {
  b.addByte(v & 0xFF);
  b.addByte((v >> 8) & 0xFF);
}

void _u32Le(BytesBuilder b, int v) {
  b.addByte(v & 0xFF);
  b.addByte((v >> 8) & 0xFF);
  b.addByte((v >> 16) & 0xFF);
  b.addByte((v >> 24) & 0xFF);
}
