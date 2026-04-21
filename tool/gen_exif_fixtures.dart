// Generates the EXIF test fixtures.
//
// Writes:
//   test/fixtures/exif_rewriter/empty_exif_ifd0.bin      — djimimo-style
//   test/fixtures/exif_rewriter/full_exif_ifd0.bin       — S23U-style
//   test/fixtures/exif_rewriter/rewritten_golden.bin     — expected bytes
//                                                           after rewriting
//                                                           full_exif_ifd0.bin

import 'dart:io';
import 'dart:typed_data';

import 'package:liveback/services/exif_rewriter.dart';

void main() {
  final djimimo = _buildDjimimoStyleAppOne();
  final full = _buildFullExifAppOne();

  // Rewrite full with Make=samsung / Model=Galaxy S23 Ultra. The source is
  // hand-crafted to already contain matching-length Make/Model so the
  // fast-path applies (stable golden bytes).
  final rewritten = ExifRewriter().rewriteMakeModel(
    originalAppOne: full,
    make: 'samsung',
    model: 'Galaxy S23 Ultra',
  );

  File('test/fixtures/exif_rewriter/empty_exif_ifd0.bin').writeAsBytesSync(djimimo);
  File('test/fixtures/exif_rewriter/full_exif_ifd0.bin').writeAsBytesSync(full);
  File('test/fixtures/exif_rewriter/rewritten_golden.bin').writeAsBytesSync(rewritten.single);

  stdout.writeln('wrote ${djimimo.length} B -> empty_exif_ifd0.bin');
  stdout.writeln('wrote ${full.length} B -> full_exif_ifd0.bin');
  stdout.writeln('wrote ${rewritten.single.length} B -> rewritten_golden.bin');
}

/// djimimo-style APP1 EXIF: 4 IFD0 entries: ImageWidth, ImageLength,
/// ExifIFD pointer, Orientation. NO Make, NO Model. Little-endian TIFF.
Uint8List _buildDjimimoStyleAppOne() {
  final tiff = BytesBuilder();
  tiff.add([0x49, 0x49, 0x2A, 0x00]); // "II" + 0x002A
  _putU32Le(tiff, 8); // IFD0 offset

  final ifdStart = tiff.length; // = 8
  // entry_count = 4
  _putU16Le(tiff, 4);
  // 0x0100 ImageWidth SHORT[1] = 4000
  _writeShortEntry(tiff, 0x0100, 4000);
  // 0x0101 ImageLength SHORT[1] = 3000
  _writeShortEntry(tiff, 0x0101, 3000);
  // 0x0112 Orientation SHORT[1] = 1
  _writeShortEntry(tiff, 0x0112, 1);
  // 0x8769 ExifIFD LONG[1] = (offset of ExifIFD subdirectory)
  // We'll compute: dir size = 2 + 4*12 + 4 = 54 bytes, so sub-IFD starts at 8 + 54 = 62.
  _putU16Le(tiff, 0x8769);
  _putU16Le(tiff, 4); // LONG
  _putU32Le(tiff, 1); // count
  _putU32Le(tiff, 62); // offset

  // next_ifd_offset = 0
  _putU32Le(tiff, 0);
  assert(tiff.length - ifdStart == 2 + 4 * 12 + 4);

  // Exif sub-IFD at offset 62. Minimal: 1 entry + next = 0.
  //   entry: 0x9000 ExifVersion UNDEFINED[4] = "0232"
  _putU16Le(tiff, 1);
  _putU16Le(tiff, 0x9000);
  _putU16Le(tiff, 7); // UNDEFINED
  _putU32Le(tiff, 4);
  tiff.add([0x30, 0x32, 0x33, 0x32]); // "0232"
  _putU32Le(tiff, 0); // next

  return _wrapAppOne(tiff.toBytes());
}

/// S23U-style APP1 EXIF with Make/Model present, both at the target
/// ASCII lengths (so the fast path applies). 4 IFD0 entries.
Uint8List _buildFullExifAppOne() {
  final tiff = BytesBuilder();
  tiff.add([0x49, 0x49, 0x2A, 0x00]);
  _putU32Le(tiff, 8);

  // Plan layout: IFD0 has 4 entries (Make, Model, Orientation, ExifIFD).
  //   entry_count(2) + 4*12 + next(4) = 54
  //   valuePool starts at 8 + 54 = 62
  //   Make ASCII[8] "samsung\0" → pool offset 62, length 8  (ends at 70)
  //   Model ASCII[17] "Galaxy S23 Ultra\0" → pool offset 70, length 17 (ends at 87)
  //   (pad to even: 88)
  //   ExifIFD @ 88 — just the minimal sub-IFD used above.

  _putU16Le(tiff, 4);

  // 0x010F Make ASCII[8] @ 62
  _putU16Le(tiff, 0x010F);
  _putU16Le(tiff, 2); // ASCII
  _putU32Le(tiff, 8); // count
  _putU32Le(tiff, 62); // offset

  // 0x0110 Model ASCII[17] @ 70
  _putU16Le(tiff, 0x0110);
  _putU16Le(tiff, 2);
  _putU32Le(tiff, 17);
  _putU32Le(tiff, 70);

  // 0x0112 Orientation SHORT[1] = 1 inline
  _writeShortEntry(tiff, 0x0112, 1);

  // 0x8769 ExifIFD LONG[1] = 88
  _putU16Le(tiff, 0x8769);
  _putU16Le(tiff, 4);
  _putU32Le(tiff, 1);
  _putU32Le(tiff, 88);

  _putU32Le(tiff, 0); // next_ifd

  // Value pool: Make@62, Model@70.
  _putAsciiZ(tiff, 'samsung', 8); // 8 bytes
  _putAsciiZ(tiff, 'Galaxy S23 Ultra', 17); // 17 bytes
  // Pad to even 88 (currently at 87).
  tiff.addByte(0);

  // Exif sub-IFD at 88.
  _putU16Le(tiff, 1);
  _putU16Le(tiff, 0x9000);
  _putU16Le(tiff, 7);
  _putU32Le(tiff, 4);
  tiff.add([0x30, 0x32, 0x33, 0x32]);
  _putU32Le(tiff, 0);

  return _wrapAppOne(tiff.toBytes());
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

void _writeShortEntry(BytesBuilder b, int tag, int v) {
  _putU16Le(b, tag);
  _putU16Le(b, 3); // SHORT
  _putU32Le(b, 1); // count
  _putU16Le(b, v);
  _putU16Le(b, 0); // pad to 4
}

void _putU16Le(BytesBuilder b, int v) {
  b.addByte(v & 0xFF);
  b.addByte((v >> 8) & 0xFF);
}

void _putU32Le(BytesBuilder b, int v) {
  b.addByte(v & 0xFF);
  b.addByte((v >> 8) & 0xFF);
  b.addByte((v >> 16) & 0xFF);
  b.addByte((v >> 24) & 0xFF);
}

void _putAsciiZ(BytesBuilder b, String s, int totalLenIncludingNull) {
  final codes = s.codeUnits;
  if (codes.length + 1 > totalLenIncludingNull) {
    throw ArgumentError('string too long for slot');
  }
  for (final c in codes) {
    b.addByte(c);
  }
  for (var i = codes.length; i < totalLenIncludingNull; i++) {
    b.addByte(0);
  }
}
