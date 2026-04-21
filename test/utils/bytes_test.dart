import 'dart:typed_data';

import 'package:liveback/utils/bytes.dart';
import 'package:test/test.dart';

void main() {
  group('readUint32Le', () {
    test('reads a little-endian uint32', () {
      final src = Uint8List.fromList([0x78, 0x56, 0x34, 0x12]);
      expect(readUint32Le(src, 0), 0x12345678);
    });

    test('reads with offset', () {
      final src = Uint8List.fromList([0xAA, 0x78, 0x56, 0x34, 0x12, 0xBB]);
      expect(readUint32Le(src, 1), 0x12345678);
    });

    test('handles 0xFFFFFFFF boundary', () {
      final src = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
      expect(readUint32Le(src, 0), 0xFFFFFFFF);
    });

    test('throws on out-of-range offset', () {
      final src = Uint8List.fromList([0x00, 0x01]);
      expect(() => readUint32Le(src, 0), throwsRangeError);
      expect(() => readUint32Le(src, -1), throwsRangeError);
    });
  });

  group('readUint32Be', () {
    test('reads a big-endian uint32', () {
      final src = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]);
      expect(readUint32Be(src, 0), 0x12345678);
    });

    test('decodes the MotionPhoto_Data type code', () {
      // 00 00 30 0A stored verbatim → decoded as BE uint32 = 0x0000300A.
      final src = Uint8List.fromList([0x00, 0x00, 0x30, 0x0A]);
      expect(readUint32Be(src, 0), 0x0000300A);
    });

    test('throws on out-of-range offset', () {
      final src = Uint8List.fromList([0x00, 0x01, 0x02]);
      expect(() => readUint32Be(src, 0), throwsRangeError);
    });
  });

  group('readUint16Be', () {
    test('reads a big-endian uint16', () {
      final src = Uint8List.fromList([0xFF, 0xD8]);
      expect(readUint16Be(src, 0), 0xFFD8);
    });

    test('reads APP1 size field', () {
      // APP1 size field `CC 05` = 0xCC05 = 52229 (Sample A EXIF size).
      final src = Uint8List.fromList([0xCC, 0x05]);
      expect(readUint16Be(src, 0), 0xCC05);
    });

    test('throws on out-of-range offset', () {
      final src = Uint8List.fromList([0x00]);
      expect(() => readUint16Be(src, 0), throwsRangeError);
    });
  });

  group('writeUint32Le', () {
    test('writes a little-endian uint32', () {
      final out = Uint8List(4);
      final bd = ByteData.view(out.buffer);
      writeUint32Le(bd, 0, 0x12345678);
      expect(out, orderedEquals([0x78, 0x56, 0x34, 0x12]));
    });
  });

  group('concatBytes', () {
    test('concatenates three parts', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([4, 5]);
      final c = Uint8List.fromList([6]);
      expect(concatBytes([a, b, c]), orderedEquals([1, 2, 3, 4, 5, 6]));
    });

    test('empty list returns empty Uint8List', () {
      expect(concatBytes([]).length, 0);
    });

    test('preserves zero-length parts', () {
      final a = Uint8List(0);
      final b = Uint8List.fromList([7, 8]);
      expect(concatBytes([a, b, a]), orderedEquals([7, 8]));
    });
  });

  group('bytesEqual', () {
    test('returns true on equal ranges', () {
      final a = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b = Uint8List.fromList([0, 0, 3, 4, 5]);
      expect(bytesEqual(a, 2, b, 2, 3), isTrue);
    });

    test('returns false on unequal ranges', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([1, 2, 4]);
      expect(bytesEqual(a, 0, b, 0, 3), isFalse);
    });

    test('returns true for length 0', () {
      expect(bytesEqual(Uint8List(0), 0, Uint8List(0), 0, 0), isTrue);
    });

    test('returns false for out-of-range ranges', () {
      final a = Uint8List.fromList([1, 2]);
      final b = Uint8List.fromList([1, 2]);
      expect(bytesEqual(a, 0, b, 0, 5), isFalse);
      expect(bytesEqual(a, -1, b, 0, 1), isFalse);
    });
  });

  group('findBytes', () {
    test('finds needle at start', () {
      final hay = Uint8List.fromList([0x53, 0x45, 0x46, 0x48, 0xAA]);
      final needle = Uint8List.fromList([0x53, 0x45, 0x46, 0x48]);
      expect(findBytes(hay, needle), 0);
    });

    test('finds needle in the middle', () {
      final hay = Uint8List.fromList([0x00, 0x11, 0x22, 0x33]);
      final needle = Uint8List.fromList([0x22, 0x33]);
      expect(findBytes(hay, needle), 2);
    });

    test('returns -1 when not found', () {
      final hay = Uint8List.fromList([0x00, 0x01]);
      final needle = Uint8List.fromList([0xFF, 0xFF]);
      expect(findBytes(hay, needle), -1);
    });

    test('respects start', () {
      final hay = Uint8List.fromList([0xAA, 0xBB, 0xAA, 0xBB]);
      final needle = Uint8List.fromList([0xAA, 0xBB]);
      expect(findBytes(hay, needle, start: 1), 2);
    });

    test('respects end', () {
      final hay = Uint8List.fromList([0xAA, 0xBB, 0xAA, 0xBB]);
      final needle = Uint8List.fromList([0xAA, 0xBB]);
      expect(findBytes(hay, needle, start: 0, end: 2), 0);
      expect(findBytes(hay, needle, start: 1, end: 3), -1);
    });

    test('empty needle returns start', () {
      final hay = Uint8List.fromList([1, 2, 3]);
      expect(findBytes(hay, Uint8List(0), start: 1), 1);
    });
  });
}
