// Owner: T1 (binary-format teammate). Reference: Doc 2 §5.
// DO NOT edit signatures without an architecture amendment.

import 'dart:io';
import 'dart:typed_data';

import '../utils/bytes.dart';

/// Reads `mvhd.duration` / `mvhd.timescale` from an MP4 moov. Does NOT
/// read mdat — only seeks through ftyp → moov → mvhd.
///
/// See Doc 2 §5.2 for the box-walk algorithm and §5.3 for version-0 vs
/// version-1 mvhd handling.
class Mp4DurationProbe {
  static const int _maxBoxDepth = 8;

  /// Probes the MP4 that starts at [ftypOffset] inside the random-access
  /// file [raf]. [fileEnd] is the exclusive upper bound (usually the
  /// physical file size). Returns null if mvhd is absent or malformed
  /// (caller treats null as "no video" and returns
  /// `FixResult(kind: skippedNotMotionPhoto)` per Doc 2 §6.2).
  Future<Mp4Duration?> probe(
    RandomAccessFile raf,
    int ftypOffset,
    int fileEnd,
  ) async {
    if (ftypOffset < 0 || fileEnd <= ftypOffset) return null;

    // Walk top-level boxes from ftypOffset looking for `moov`.
    var pos = ftypOffset;
    while (pos + 8 <= fileEnd) {
      final hdr = await _readBoxHeader(raf, pos, fileEnd);
      if (hdr == null) return null;
      if (hdr.type == _moov) {
        return _scanMoovForMvhd(raf, pos + hdr.headerSize, pos + hdr.size);
      }
      // Defensive: boxes must advance.
      if (hdr.size <= 0) return null;
      pos += hdr.size;
    }
    return null;
  }

  Future<Mp4Duration?> _scanMoovForMvhd(
    RandomAccessFile raf,
    int start,
    int end,
  ) async {
    var p = start;
    while (p + 8 <= end) {
      final hdr = await _readBoxHeader(raf, p, end);
      if (hdr == null) return null;
      if (hdr.type == _mvhd) {
        return _readMvhd(raf, p, hdr);
      }
      if (hdr.size <= 0) return null;
      p += hdr.size;
    }
    return null;
  }

  Future<Mp4Duration?> _readMvhd(
    RandomAccessFile raf,
    int boxStart,
    _BoxHeader hdr,
  ) async {
    // mvhd v0 = header(8) + version(1) + flags(3) + creation(4) + modification(4)
    //           + timescale(4) + duration(4) → 28 bytes total
    // mvhd v1 = header(8) + version(1) + flags(3) + creation(8) + modification(8)
    //           + timescale(4) + duration(8) → 40 bytes total
    // (Both may have size==1 extended-size header, contributing +8 at front;
    //  headerSize accounts for that.)
    final minVal = hdr.headerSize + 20; // version+flags+rest for v0
    if (hdr.size < minVal) return null;

    // Read version byte.
    await raf.setPosition(boxStart + hdr.headerSize);
    final vf = await raf.read(4);
    if (vf.length < 4) return null;
    final version = vf[0];

    if (version == 0) {
      // v0: skip version(1) + flags(3) + creation(4) + modification(4) = 12
      // Need timescale(4) + duration(4) = 8 more.
      if (hdr.size < hdr.headerSize + 20) return null;
      await raf.setPosition(boxStart + hdr.headerSize + 12);
      final payload = await raf.read(8);
      if (payload.length < 8) return null;
      final buf = Uint8List.fromList(payload);
      final timescale = readUint32Be(buf, 0);
      final duration = readUint32Be(buf, 4);
      if (timescale == 0) return null;
      return Mp4Duration(durationUnits: duration, timescale: timescale);
    } else if (version == 1) {
      // v1: skip version(1) + flags(3) + creation(8) + modification(8) = 20
      // Need timescale(4) + duration(8) = 12 more.
      if (hdr.size < hdr.headerSize + 32) return null;
      await raf.setPosition(boxStart + hdr.headerSize + 20);
      final payload = await raf.read(12);
      if (payload.length < 12) return null;
      final buf = Uint8List.fromList(payload);
      final timescale = readUint32Be(buf, 0);
      final durationHi = readUint32Be(buf, 4);
      final durationLo = readUint32Be(buf, 8);
      final duration = (durationHi << 32) | durationLo;
      if (timescale == 0) return null;
      return Mp4Duration(durationUnits: duration, timescale: timescale);
    } else {
      // Unknown version — treat as corrupt.
      return null;
    }
  }

  /// Reads an ISO BMFF box header. Returns null on EOF / malformed.
  ///
  /// Handles the size == 1 "large size" extension (8-byte size follows).
  /// If size == 0 the box extends to the file end — we return size =
  /// `fileEnd - pos` for compatibility, but Motion Photos won't have this.
  Future<_BoxHeader?> _readBoxHeader(
    RandomAccessFile raf,
    int pos,
    int fileEnd,
  ) async {
    if (pos + 8 > fileEnd) return null;
    await raf.setPosition(pos);
    final hdr = await raf.read(8);
    if (hdr.length < 8) return null;
    final buf = Uint8List.fromList(hdr);
    final size32 = readUint32Be(buf, 0);
    final type = readUint32Be(buf, 4);

    if (size32 == 1) {
      // size == 1 → 64-bit size in next 8 bytes.
      if (pos + 16 > fileEnd) return null;
      final ext = await raf.read(8);
      if (ext.length < 8) return null;
      final extBuf = Uint8List.fromList(ext);
      final hi = readUint32Be(extBuf, 0);
      final lo = readUint32Be(extBuf, 4);
      final size64 = (hi << 32) | lo;
      if (size64 < 16 || pos + size64 > fileEnd) return null;
      return _BoxHeader(size: size64, type: type, headerSize: 16);
    } else if (size32 == 0) {
      // Box extends to the end of file.
      final size = fileEnd - pos;
      if (size < 8) return null;
      return _BoxHeader(size: size, type: type, headerSize: 8);
    } else {
      if (size32 < 8 || pos + size32 > fileEnd) return null;
      return _BoxHeader(size: size32, type: type, headerSize: 8);
    }
  }

  // Big-endian 4-char codes.
  static const int _moov = 0x6D6F6F76; // 'moov'
  static const int _mvhd = 0x6D766864; // 'mvhd'
}

class _BoxHeader {
  final int size; // total bytes from start of box (including header)
  final int type; // 4-byte type as big-endian uint32
  final int headerSize; // 8 or 16 bytes
  _BoxHeader({required this.size, required this.type, required this.headerSize});
}

/// Value carrier for mvhd fields. Duration in mvhd-native units.
class Mp4Duration {
  final int durationUnits;
  final int timescale;

  const Mp4Duration({
    required this.durationUnits,
    required this.timescale,
  });

  /// Seconds = durationUnits / timescale. timescale == 0 is a parse
  /// failure and will not reach this constructor.
  double get seconds => durationUnits / timescale;
}
