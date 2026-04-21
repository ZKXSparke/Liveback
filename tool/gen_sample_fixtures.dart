// Generates synthetic Motion Photo test fixtures for the binary-format
// library's end-to-end tests.
//
// Produces:
//   test/fixtures/samples/djimimo_baseline.jpg   — a small (~2 KB) synthetic
//     djimimo-style Motion Photo: SOI + minimal EXIF (4-entry IFD0, no
//     Make/Model, MM big-endian) + SOS+entropy+EOI + raw MP4 trailer
//     (ftyp + moov/mvhd with 0.5 s duration + mdat stub). No SEF trailer.
//     No Samsung Make. This is the primary input for fix_service tests.
//
//   test/fixtures/samples/invalid_no_soi.jpg     — 32 random bytes.
//   test/fixtures/samples/invalid_truncated.jpg  — valid SOI, a partial
//     APP0, then EOF in the middle of a segment.
//   test/fixtures/samples/no_mp4.jpg             — plain JPEG: SOI + APP0 +
//     SOS+entropy+EOI, no trailing MP4.
//
// Usage:  dart run tool/gen_sample_fixtures.dart

import 'dart:io';
import 'dart:typed_data';

void main() {
  final djimimo = _buildDjimimoBaseline();
  final noSoi = _buildNoSoi();
  final truncated = _buildTruncated();
  final noMp4 = _buildNoMp4();

  File('test/fixtures/samples/djimimo_baseline.jpg').writeAsBytesSync(djimimo);
  File('test/fixtures/samples/invalid_no_soi.jpg').writeAsBytesSync(noSoi);
  File('test/fixtures/samples/invalid_truncated.jpg').writeAsBytesSync(truncated);
  File('test/fixtures/samples/no_mp4.jpg').writeAsBytesSync(noMp4);

  stdout.writeln('wrote ${djimimo.length} B -> djimimo_baseline.jpg');
  stdout.writeln('wrote ${noSoi.length} B -> invalid_no_soi.jpg');
  stdout.writeln('wrote ${truncated.length} B -> invalid_truncated.jpg');
  stdout.writeln('wrote ${noMp4.length} B -> no_mp4.jpg');
}

Uint8List _buildDjimimoBaseline() {
  final b = BytesBuilder();
  // SOI
  b.add([0xFF, 0xD8]);
  // APP1 EXIF (MM big-endian) — 4 IFD0 entries, no Make/Model.
  b.add(_buildDjimimoExifApp1());
  // XMP APP1 to exercise XMP detection (small).
  b.add(_buildXmpApp1());
  // Minimal SOF0 + DHT + DQT so the scan looks vaguely JPEG-shaped.
  // These are not actually parsed by us (we only care about segment
  // boundaries), so bogus-but-well-formed lengths are fine.
  b.add(_buildAnySegment(0xDB, Uint8List(67))); // DQT, length 67+2
  b.add(_buildAnySegment(0xC0, Uint8List(15))); // SOF0
  b.add(_buildAnySegment(0xC4, Uint8List(30))); // DHT

  // SOS: header then entropy-coded data containing a stuffed FF 00
  // and a restart marker (FF D0) to exercise the scanner, then a real EOI.
  b.add([0xFF, 0xDA]);
  b.addByte(0);
  b.addByte(12); // SOS length (arbitrary)
  for (var i = 0; i < 10; i++) {
    b.addByte(0);
  }
  // Entropy data: real JPEG scan bytes, with byte-stuffing and a restart
  // marker inserted.
  b.addByte(0x00);
  b.addByte(0xFF); b.addByte(0x00);   // stuffed FF
  b.addByte(0x12); b.addByte(0x34);
  b.addByte(0xFF); b.addByte(0xD0);   // restart marker (not EOI)
  b.addByte(0x56); b.addByte(0x78);
  b.addByte(0xFF); b.addByte(0x00);
  // Real EOI.
  b.addByte(0xFF); b.addByte(0xD9);

  // Now the MP4 trailer (no inline SEF marker — this is djimimo style).
  b.add(_buildMinimalMp4(0.5));

  return b.toBytes();
}

Uint8List _buildDjimimoExifApp1() {
  // Build TIFF MM big-endian, 4 IFD0 entries.
  final tiff = BytesBuilder();
  tiff.add([0x4D, 0x4D, 0x00, 0x2A]); // MM + 0x002A
  _u32Be(tiff, 8); // IFD0 offset = 8
  _u16Be(tiff, 4); // entry count
  // 0x0100 ImageWidth SHORT[1] = 4000
  _u16Be(tiff, 0x0100); _u16Be(tiff, 3); _u32Be(tiff, 1); _u16Be(tiff, 4000); _u16Be(tiff, 0);
  // 0x0101 ImageLength SHORT[1] = 3000
  _u16Be(tiff, 0x0101); _u16Be(tiff, 3); _u32Be(tiff, 1); _u16Be(tiff, 3000); _u16Be(tiff, 0);
  // 0x0112 Orientation SHORT[1] = 1
  _u16Be(tiff, 0x0112); _u16Be(tiff, 3); _u32Be(tiff, 1); _u16Be(tiff, 1); _u16Be(tiff, 0);
  // 0x8769 ExifIFD LONG[1] = 62 (right after the dir + next_ifd)
  _u16Be(tiff, 0x8769); _u16Be(tiff, 4); _u32Be(tiff, 1); _u32Be(tiff, 62);
  _u32Be(tiff, 0); // next_ifd

  // ExifIFD at offset 62: 1 entry (ExifVersion UNDEFINED[4] "0232"), next=0.
  _u16Be(tiff, 1);
  _u16Be(tiff, 0x9000); _u16Be(tiff, 7); _u32Be(tiff, 4);
  tiff.add([0x30, 0x32, 0x33, 0x32]);
  _u32Be(tiff, 0); // next

  final tiffBytes = tiff.toBytes();
  final total = 2 + 6 + tiffBytes.length;
  final app1 = BytesBuilder();
  app1.add([0xFF, 0xE1]);
  app1.addByte((total >> 8) & 0xFF);
  app1.addByte(total & 0xFF);
  app1.add([0x45, 0x78, 0x69, 0x66, 0x00, 0x00]);
  app1.add(tiffBytes);
  return app1.toBytes();
}

Uint8List _buildXmpApp1() {
  final xmpBody = '<x:xmpmeta xmlns:GCamera="http://gcamera"><GCamera:MotionPhoto>1</GCamera:MotionPhoto></x:xmpmeta>';
  final ns = 'http://ns.adobe.com/xap/1.0/';
  // payload = ns\0 + xmp bytes
  final payload = BytesBuilder();
  payload.add(ns.codeUnits);
  payload.addByte(0);
  payload.add(xmpBody.codeUnits);
  final payloadBytes = payload.toBytes();
  final total = 2 + payloadBytes.length;
  final out = BytesBuilder();
  out.add([0xFF, 0xE1]);
  out.addByte((total >> 8) & 0xFF);
  out.addByte(total & 0xFF);
  out.add(payloadBytes);
  return out.toBytes();
}

Uint8List _buildAnySegment(int marker, Uint8List payload) {
  final total = 2 + payload.length;
  final out = BytesBuilder();
  out.addByte(0xFF);
  out.addByte(marker);
  out.addByte((total >> 8) & 0xFF);
  out.addByte(total & 0xFF);
  out.add(payload);
  return out.toBytes();
}

/// Minimal ISO BMFF: ftyp + moov{mvhd}.
Uint8List _buildMinimalMp4(double durationSeconds) {
  final b = BytesBuilder();
  // ftyp — 24 bytes
  _u32Be(b, 24);
  b.add(_ascii('ftyp'));
  b.add(_ascii('mp42'));
  _u32Be(b, 0);
  b.add(_ascii('isom'));
  b.add(_ascii('mp42'));

  // mvhd v0 — 108 bytes inside a moov
  const timescale = 1000;
  final durationUnits = (durationSeconds * timescale).round();
  final mvhd = BytesBuilder();
  _u32Be(mvhd, 108);
  mvhd.add(_ascii('mvhd'));
  mvhd.addByte(0); // version
  mvhd.add([0, 0, 0]); // flags
  _u32Be(mvhd, 0); // creation
  _u32Be(mvhd, 0); // modification
  _u32Be(mvhd, timescale);
  _u32Be(mvhd, durationUnits);
  for (var i = 0; i < 80; i++) {
    mvhd.addByte(0);
  }

  // moov = header + mvhd
  final moov = BytesBuilder();
  _u32Be(moov, 8 + mvhd.length);
  moov.add(_ascii('moov'));
  moov.add(mvhd.toBytes());

  b.add(moov.toBytes());

  // mdat stub (tiny) — helps simulate a non-trivial MP4.
  final mdatPayload = Uint8List.fromList(List.filled(32, 0x22));
  _u32Be(b, 8 + mdatPayload.length);
  b.add(_ascii('mdat'));
  b.add(mdatPayload);

  return b.toBytes();
}

Uint8List _buildNoSoi() {
  return Uint8List.fromList(List.generate(32, (i) => (i * 7) & 0xFF));
}

Uint8List _buildTruncated() {
  // SOI + APP0 marker + bogus long length, then EOF.
  return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0xFF]);
}

Uint8List _buildNoMp4() {
  final b = BytesBuilder();
  b.add([0xFF, 0xD8]);
  // APP0 JFIF
  b.add(_buildAnySegment(0xE0, Uint8List.fromList([
    0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00,
  ])));
  // SOS + entropy + EOI
  b.add([0xFF, 0xDA, 0x00, 0x0C]);
  for (var i = 0; i < 10; i++) {
    b.addByte(0);
  }
  b.addByte(0x42);
  b.addByte(0xFF); b.addByte(0x00);
  b.addByte(0x55);
  b.addByte(0xFF); b.addByte(0xD9);
  return b.toBytes();
}

Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);

void _u16Be(BytesBuilder b, int v) {
  b.addByte((v >> 8) & 0xFF);
  b.addByte(v & 0xFF);
}

void _u32Be(BytesBuilder b, int v) {
  b.addByte((v >> 24) & 0xFF);
  b.addByte((v >> 16) & 0xFF);
  b.addByte((v >> 8) & 0xFF);
  b.addByte(v & 0xFF);
}
