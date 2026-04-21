// Owner: T3 (UI teammate). Reference: Doc 2 §2 + architecture/02-binary-format-lib.md §8.
//
// Pure-Dart mirror of MediaStorePlugin.probeMotionPhoto. The on-device
// detection path used by the gallery is the Kotlin one (tail-probe + head-
// probe against a MediaStore URI). This Dart implementation is kept in sync
// for two use-cases that can't cross the MethodChannel:
//
//   1. `tool/probe_samples_smoke.dart` — CLI validation against local files
//      during development. See `Report back` §4 of the MP-detect task brief.
//   2. Future Test Mode integration: hand a fresh djimimo sample to
//      fix_service and inspect both before/after states without requiring a
//      physical Android device.
//
// Algorithm must stay byte-for-byte equivalent to the Kotlin side so the
// two probes cannot disagree.

import 'dart:io';
import 'dart:typed_data';

import '../utils/bytes.dart';
import '_sef_constants.dart';

/// Result of a Motion-Photo probe against a single file or URI. Immutable
/// value object shared by both the Kotlin-backed channel probe
/// (MediaStoreChannel.probeMotionPhoto) and the pure-Dart mirror below.
class MotionPhotoProbe {
  /// True if the file contains an MP4 stream after the JPEG EOI — i.e.
  /// either a djimimo-exported Motion Photo OR a Samsung-native one.
  final bool isMotionPhoto;

  /// True only when a valid SEFH/SEFT trailer with a MotionPhoto_Data
  /// record is present. Implies [isMotionPhoto] is true too.
  final bool isSamsungNative;

  const MotionPhotoProbe({
    required this.isMotionPhoto,
    required this.isSamsungNative,
  });

  @override
  String toString() =>
      'MotionPhotoProbe(isMotionPhoto=$isMotionPhoto, isSamsungNative=$isSamsungNative)';
}

/// Pure-Dart port of the Kotlin probe in [MediaStorePlugin.probeMotionPhoto].
///
/// - Tail probe: reads last 64 bytes, looks for SEFT magic at EOF-4, walks
///   the SEFH record directory for the MotionPhoto_Data type code
///   (00 00 30 0A).
/// - Head probe: sliding-scans the first 8 MB for JPEG EOI (FF D9), then
///   checks the next 64 bytes for the ASCII 'ftyp' box type.
///
/// Budget: ≤ 50 ms on a mid-range phone. Any unexpected IO error collapses
/// to `MotionPhotoProbe(false, false)` — same graceful-degrade contract as
/// the Kotlin side.
class MotionPhotoProbeDart {
  /// Tail-probe window in bytes.
  static const int tailBytes = 64;

  /// How much of the file head to scan for JPEG EOI before giving up.
  static const int headMaxBytes = 8 * 1024 * 1024;

  /// Bytes past EOI to scan for 'ftyp'.
  static const int ftypWindowBytes = 64;

  /// Below this size, bail out with a no-badge result (MediaStore stub row
  /// or a tiny thumbnail).
  static const int minFileBytes = 32 * 1024;

  /// Max SEF records to walk in the tail directory before giving up — same
  /// cap as Kotlin + the full parser.
  static const int maxSefRecords = 32;

  Future<MotionPhotoProbe> probeFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const MotionPhotoProbe(
        isMotionPhoto: false,
        isSamsungNative: false,
      );
    }
    final raf = await file.open();
    try {
      final size = await raf.length();
      if (size < minFileBytes) {
        return const MotionPhotoProbe(
          isMotionPhoto: false,
          isSamsungNative: false,
        );
      }
      final isSamsungNative = await _probeSefTail(raf, size);
      final isMotionPhoto =
          isSamsungNative ? true : await _probeFtypHead(raf, size);
      return MotionPhotoProbe(
        isMotionPhoto: isMotionPhoto,
        isSamsungNative: isSamsungNative,
      );
    } catch (_) {
      return const MotionPhotoProbe(
        isMotionPhoto: false,
        isSamsungNative: false,
      );
    } finally {
      await raf.close();
    }
  }

  Future<bool> _probeSefTail(RandomAccessFile raf, int size) async {
    if (size < 32) return false;
    final tailLen = size < tailBytes ? size : tailBytes;
    final tailStart = size - tailLen;
    await raf.setPosition(tailStart);
    final tailList = await raf.read(tailLen);
    if (tailList.length != tailLen) return false;
    final tailArr = Uint8List.fromList(tailList);

    // SEFT at EOF-4.
    final seftOff = tailLen - 4;
    if (seftOff < 4) return false;
    if (!bytesEqual(tailArr, seftOff, kSeftMagic, 0, 4)) return false;

    // sef_size at EOF-8 (uint32 LE).
    final sefSize = readUint32Le(tailArr, seftOff - 4);
    if (sefSize < 24 || sefSize > size - 8) return false;
    final sefhPos = size - 8 - sefSize;
    if (sefhPos < 0) return false;

    // Re-read SEFH + records.
    const hdrCap = 12 + maxSefRecords * 12;
    final readLen = sefSize < hdrCap ? sefSize : hdrCap;
    if (readLen < 12) return false;
    await raf.setPosition(sefhPos);
    final hdrList = await raf.read(readLen);
    if (hdrList.length != readLen) return false;
    final hdr = Uint8List.fromList(hdrList);

    // SEFH magic.
    if (!bytesEqual(hdr, 0, kSefhMagic, 0, 4)) return false;

    // Record count at offset 8 (uint32 LE).
    final recordCount = readUint32Le(hdr, 8);
    if (recordCount == 0 || recordCount > maxSefRecords) return false;

    final recsToScan =
        recordCount < (readLen - 12) ~/ 12 ? recordCount : (readLen - 12) ~/ 12;

    for (var i = 0; i < recsToScan; i++) {
      final off = 12 + i * 12;
      // MotionPhoto_Data type code: 00 00 30 0A (stored verbatim, compared
      // as a 4-byte literal — NOT as uint32 LE).
      if (hdr[off] == kInlineMarkerMagic[0] &&
          hdr[off + 1] == kInlineMarkerMagic[1] &&
          hdr[off + 2] == kInlineMarkerMagic[2] &&
          hdr[off + 3] == kInlineMarkerMagic[3]) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _probeFtypHead(RandomAccessFile raf, int size) async {
    final scanLen = size < headMaxBytes ? size : headMaxBytes;
    if (scanLen < 4) return false;
    const bufSize = 64 * 1024;
    var pos = 0;
    int? prevByte;
    while (pos < scanLen) {
      final remaining = scanLen - pos;
      final readLen = remaining < bufSize ? remaining : bufSize;
      await raf.setPosition(pos);
      final chunk = await raf.read(readLen);
      if (chunk.isEmpty) return false;

      // Cross-chunk-boundary check for FF D9.
      if (prevByte == 0xFF && chunk[0] == 0xD9) {
        return _lookForFtyp(raf, pos + 1, size);
      }
      for (var i = 0; i < chunk.length - 1; i++) {
        if (chunk[i] == 0xFF && chunk[i + 1] == 0xD9) {
          return _lookForFtyp(raf, pos + i + 2, size);
        }
      }
      if (chunk.isNotEmpty) prevByte = chunk[chunk.length - 1];
      pos += chunk.length;
    }
    return false;
  }

  Future<bool> _lookForFtyp(
      RandomAccessFile raf, int afterEoi, int size) async {
    final remaining = size - afterEoi;
    final window = remaining < ftypWindowBytes ? remaining : ftypWindowBytes;
    if (window < 8) return false;
    await raf.setPosition(afterEoi);
    final buf = await raf.read(window);
    if (buf.length < 8) return false;
    final arr = Uint8List.fromList(buf);
    final idx = findBytes(arr, kFtypMagic);
    return idx >= 0;
  }
}
