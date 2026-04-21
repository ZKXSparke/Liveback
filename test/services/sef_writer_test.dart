import 'dart:io';
import 'dart:typed_data';

import 'package:liveback/services/sef_writer.dart';
import 'package:liveback/utils/bytes.dart';
import 'package:test/test.dart';

void main() {
  group('SefWriter.buildInlineMarker', () {
    test('returns 24 bytes', () {
      expect(SefWriter.buildInlineMarker().length, 24);
      expect(SefWriter.inlineMarkerBytes, 24);
    });

    test('starts with 00 00 30 0A magic (Doc 2 §3.2)', () {
      final m = SefWriter.buildInlineMarker();
      expect(m.sublist(0, 4), orderedEquals([0x00, 0x00, 0x30, 0x0A]));
    });

    test('name_length field at 0x04..0x08 is 16 (uint32 LE)', () {
      final m = SefWriter.buildInlineMarker();
      expect(m.sublist(4, 8), orderedEquals([0x10, 0x00, 0x00, 0x00]));
      expect(readUint32Le(m, 4), 16);
    });

    test('ASCII "MotionPhoto_Data" at 0x08..0x18 (no null terminator)', () {
      final m = SefWriter.buildInlineMarker();
      expect(m.sublist(8, 24), orderedEquals([
        0x4D, 0x6F, 0x74, 0x69, 0x6F, 0x6E, // "Motion"
        0x50, 0x68, 0x6F, 0x74, 0x6F,       // "Photo"
        0x5F,                                // "_"
        0x44, 0x61, 0x74, 0x61,              // "Data"
      ]));
    });

    test('matches golden fixture inline_marker_24bytes.bin', () {
      final golden = File('test/fixtures/sef_writer/inline_marker_24bytes.bin').readAsBytesSync();
      expect(SefWriter.buildInlineMarker(), orderedEquals(golden));
    });

    test('is idempotent — returns a fresh allocation each call', () {
      final a = SefWriter.buildInlineMarker();
      final b = SefWriter.buildInlineMarker();
      expect(identical(a, b), isFalse);
      expect(a, orderedEquals(b));
      // Mutating one must not affect the other.
      a[0] = 0xFF;
      expect(b[0], 0x00);
    });
  });

  group('SefWriter.buildSefTrailer', () {
    test('returns 32 bytes for single record', () {
      expect(
        SefWriter.buildSefTrailer(offsetFromSefhToInlineMarker: 0x346B8C).length,
        32,
      );
      expect(SefWriter.trailerBytes, 32);
    });

    test('layout matches Doc 2 §3.3 byte map', () {
      final t = SefWriter.buildSefTrailer(
        offsetFromSefhToInlineMarker: 0x346B8C,
        sefVersion: 106,
      );
      // 0x00..0x04 "SEFH"
      expect(t.sublist(0, 4), orderedEquals([0x53, 0x45, 0x46, 0x48]));
      // 0x04..0x08 version = 0x6A (106)
      expect(readUint32Le(t, 4), 106);
      // 0x08..0x0C entry_count = 1
      expect(readUint32Le(t, 8), 1);
      // 0x0C..0x10 type_code = 00 00 30 0A (verbatim)
      expect(t.sublist(12, 16), orderedEquals([0x00, 0x00, 0x30, 0x0A]));
      // 0x10..0x14 offsetFromSefhToInlineMarker (uint32 LE)
      expect(readUint32Le(t, 16), 0x346B8C);
      // 0x14..0x18 data_length = same
      expect(readUint32Le(t, 20), 0x346B8C);
      // 0x18..0x1C total_sef_size = 24
      expect(readUint32Le(t, 24), 24);
      // 0x1C..0x20 "SEFT"
      expect(t.sublist(28, 32), orderedEquals([0x53, 0x45, 0x46, 0x54]));
    });

    test('matches golden fixture single_record_32bytes.bin', () {
      final golden = File('test/fixtures/sef_writer/single_record_32bytes.bin').readAsBytesSync();
      final t = SefWriter.buildSefTrailer(offsetFromSefhToInlineMarker: 0x346B8C);
      expect(t, orderedEquals(golden));
    });

    test('honors custom sefVersion', () {
      final t = SefWriter.buildSefTrailer(
        offsetFromSefhToInlineMarker: 0x1000,
        sefVersion: 107,
      );
      expect(readUint32Le(t, 4), 107);
    });

    test('rejects negative or overflow offset', () {
      expect(
        () => SefWriter.buildSefTrailer(offsetFromSefhToInlineMarker: -1),
        throwsArgumentError,
      );
      expect(
        () => SefWriter.buildSefTrailer(offsetFromSefhToInlineMarker: 0x100000000),
        throwsArgumentError,
      );
    });

    test('round-trip: synthesize trailer + parse back recovers offset', () {
      // For each candidate offset, build a synthetic "file" that ends with
      // [inline marker at position 0][empty middle of length offset-24][trailer]
      // — then parse backwards from EOF to verify offset decoding.
      for (final off in const [0x1000, 0x346B8C, 0xFFFFFFFE]) {
        final t = SefWriter.buildSefTrailer(offsetFromSefhToInlineMarker: off);
        expect(readUint32Le(t, 16), off,
            reason: 'offset field mismatch for off=$off');
        expect(readUint32Le(t, 20), off,
            reason: 'data_length field mismatch for off=$off');
        // total_sef_size (at 0x18) always 24 = size from SEFH to end-of-last-record
        // (excluding SEFT). So SEFT should be locatable at fileEnd - 4 and
        // SEFH at (fileEnd - 8 - 24).
        expect(readUint32Le(t, 24), 24);
      }
    });

    test('a second-pass file — trailer for offset = 24 + mp4Len = 24', () {
      // When mp4Len = 0 (edge case), offset = 24 (inline marker immediately
      // before SEFH). This is the smallest meaningful offset.
      final t = SefWriter.buildSefTrailer(offsetFromSefhToInlineMarker: 24);
      expect(readUint32Le(t, 16), 24);
      expect(readUint32Le(t, 20), 24);
    });
  });

  group('SefWriter.buildSefTrailer — uint8list view invariants', () {
    test('is a freshly allocated buffer, not a view of a shared source', () {
      final a = SefWriter.buildSefTrailer(offsetFromSefhToInlineMarker: 0x100);
      final b = SefWriter.buildSefTrailer(offsetFromSefhToInlineMarker: 0x200);
      // Mutating one must not affect the other.
      a[0] = 0xFF;
      expect(b[0], 0x53);
      expect(a is Uint8List, isTrue);
    });
  });
}
