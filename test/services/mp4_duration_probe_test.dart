import 'dart:io';
import 'dart:typed_data';

import 'package:liveback/services/mp4_duration_probe.dart';
import 'package:test/test.dart';

/// Builds a synthetic ISO BMFF byte stream:
///
///   ftyp (minimal 24 B) + moov (8 B header + mvhd(...) + optional udta padding)
///
/// Returned bytes are written to a temp file and probed.
Uint8List _synthesizeFtypPlusMoov(Uint8List moovContents) {
  // ftyp: 24 B → size(4) + 'ftyp' + 'mp42' + minor_version(4) + 'isom' + 'mp42'
  final ftyp = BytesBuilder();
  _putBe32(ftyp, 24);
  ftyp.add(_ascii('ftyp'));
  ftyp.add(_ascii('mp42'));
  _putBe32(ftyp, 0);
  ftyp.add(_ascii('isom'));
  ftyp.add(_ascii('mp42'));

  // moov: header + mvhd payload
  final moov = BytesBuilder();
  _putBe32(moov, 8 + moovContents.length);
  moov.add(_ascii('moov'));
  moov.add(moovContents);

  final combined = BytesBuilder();
  combined.add(ftyp.toBytes());
  combined.add(moov.toBytes());
  return combined.toBytes();
}

Uint8List _mvhdV0({required int timescale, required int duration}) {
  // mvhd v0 payload (inside the box): version(1)=0 + flags(3)=0
  //   + creation(4) + modification(4) + timescale(4) + duration(4)
  //   + rate(4) + volume(2) + reserved(10) + matrix(36) + pre_defined(24)
  //   + next_track_ID(4) — total 100 bytes after version/flags = 100 + 4 = 104
  // We can shorten: the probe only reads up through duration. But we include
  // the real length for safety.
  final mvhd = BytesBuilder();
  _putBe32(mvhd, 108); // box size = 8 (header) + 100 (payload) = 108
  mvhd.add(_ascii('mvhd'));
  mvhd.addByte(0); // version = 0
  mvhd.add([0, 0, 0]); // flags
  _putBe32(mvhd, 0); // creation_time
  _putBe32(mvhd, 0); // modification_time
  _putBe32(mvhd, timescale);
  _putBe32(mvhd, duration);
  // rate/volume/reserved/matrix/pre_defined/next_track_ID — 100 - 20 = 80 bytes
  for (var i = 0; i < 80; i++) {
    mvhd.addByte(0);
  }
  return mvhd.toBytes();
}

Uint8List _mvhdV1({required int timescale, required int duration}) {
  final mvhd = BytesBuilder();
  _putBe32(mvhd, 120); // box size = 8 header + 112 payload = 120
  mvhd.add(_ascii('mvhd'));
  mvhd.addByte(1); // version = 1
  mvhd.add([0, 0, 0]); // flags
  _putBe64(mvhd, 0); // creation_time
  _putBe64(mvhd, 0); // modification_time
  _putBe32(mvhd, timescale);
  _putBe64(mvhd, duration);
  // remaining 80 bytes
  for (var i = 0; i < 80; i++) {
    mvhd.addByte(0);
  }
  return mvhd.toBytes();
}

Uint8List _ascii(String s) => Uint8List.fromList(s.codeUnits);

void _putBe32(BytesBuilder b, int v) {
  b.addByte((v >> 24) & 0xFF);
  b.addByte((v >> 16) & 0xFF);
  b.addByte((v >> 8) & 0xFF);
  b.addByte(v & 0xFF);
}

void _putBe64(BytesBuilder b, int v) {
  b.addByte((v >> 56) & 0xFF);
  b.addByte((v >> 48) & 0xFF);
  b.addByte((v >> 40) & 0xFF);
  b.addByte((v >> 32) & 0xFF);
  b.addByte((v >> 24) & 0xFF);
  b.addByte((v >> 16) & 0xFF);
  b.addByte((v >> 8) & 0xFF);
  b.addByte(v & 0xFF);
}

Future<File> _tempFile(List<int> bytes) async {
  final tmp = await File('${Directory.systemTemp.path}/mp4probe_${DateTime.now().microsecondsSinceEpoch}.bin')
      .create();
  await tmp.writeAsBytes(bytes, flush: true);
  return tmp;
}

void main() {
  group('Mp4DurationProbe.probe', () {
    late Mp4DurationProbe probe;

    setUp(() {
      probe = Mp4DurationProbe();
    });

    test('reads mvhd version 0', () async {
      final bytes = _synthesizeFtypPlusMoov(_mvhdV0(timescale: 30000, duration: 90000));
      final f = await _tempFile(bytes);
      final raf = await f.open();
      try {
        final d = await probe.probe(raf, 0, bytes.length);
        expect(d, isNotNull);
        expect(d!.timescale, 30000);
        expect(d.durationUnits, 90000);
        expect(d.seconds, closeTo(3.0, 1e-9));
      } finally {
        await raf.close();
        await f.delete();
      }
    });

    test('reads mvhd version 1 (64-bit duration)', () async {
      final bytes = _synthesizeFtypPlusMoov(_mvhdV1(timescale: 90000, duration: 0x1FFFFFFFF));
      final f = await _tempFile(bytes);
      final raf = await f.open();
      try {
        final d = await probe.probe(raf, 0, bytes.length);
        expect(d, isNotNull);
        expect(d!.timescale, 90000);
        expect(d.durationUnits, 0x1FFFFFFFF);
      } finally {
        await raf.close();
        await f.delete();
      }
    });

    test('returns null when moov is absent', () async {
      // ftyp-only file (24 B).
      final bytes = BytesBuilder();
      _putBe32(bytes, 24);
      bytes.add(_ascii('ftyp'));
      bytes.add(_ascii('mp42'));
      _putBe32(bytes, 0);
      bytes.add(_ascii('isom'));
      bytes.add(_ascii('mp42'));
      final f = await _tempFile(bytes.toBytes());
      final raf = await f.open();
      try {
        final d = await probe.probe(raf, 0, bytes.length);
        expect(d, isNull);
      } finally {
        await raf.close();
        await f.delete();
      }
    });

    test('returns null on truncated moov', () async {
      // moov header declares size 500 but file only has 8 bytes of moov.
      final buf = BytesBuilder();
      _putBe32(buf, 24);
      buf.add(_ascii('ftyp'));
      buf.add(_ascii('mp42'));
      _putBe32(buf, 0);
      buf.add(_ascii('isom'));
      buf.add(_ascii('mp42'));
      // moov with bogus size (claims 500 but nothing after).
      _putBe32(buf, 500);
      buf.add(_ascii('moov'));
      final bytes = buf.toBytes();
      final f = await _tempFile(bytes);
      final raf = await f.open();
      try {
        final d = await probe.probe(raf, 0, bytes.length);
        expect(d, isNull);
      } finally {
        await raf.close();
        await f.delete();
      }
    });

    test('returns null when timescale is 0', () async {
      final bytes = _synthesizeFtypPlusMoov(_mvhdV0(timescale: 0, duration: 90000));
      final f = await _tempFile(bytes);
      final raf = await f.open();
      try {
        final d = await probe.probe(raf, 0, bytes.length);
        expect(d, isNull);
      } finally {
        await raf.close();
        await f.delete();
      }
    });

    test('returns null on unsupported mvhd version', () async {
      // Craft a v=2 mvhd header.
      final mvhd = BytesBuilder();
      _putBe32(mvhd, 108);
      mvhd.add(_ascii('mvhd'));
      mvhd.addByte(2); // bad version
      mvhd.add([0, 0, 0]);
      for (var i = 0; i < 100; i++) {
        mvhd.addByte(0);
      }
      final bytes = _synthesizeFtypPlusMoov(mvhd.toBytes());
      final f = await _tempFile(bytes);
      final raf = await f.open();
      try {
        final d = await probe.probe(raf, 0, bytes.length);
        expect(d, isNull);
      } finally {
        await raf.close();
        await f.delete();
      }
    });

    test('returns null when ftypOffset is past fileEnd', () async {
      final bytes = _synthesizeFtypPlusMoov(_mvhdV0(timescale: 1, duration: 1));
      final f = await _tempFile(bytes);
      final raf = await f.open();
      try {
        final d = await probe.probe(raf, 9999, bytes.length);
        expect(d, isNull);
      } finally {
        await raf.close();
        await f.delete();
      }
    });
  });
}
