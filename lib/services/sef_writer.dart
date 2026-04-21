// Owner: T1 (binary-format teammate). Reference: Doc 2 §3.
// DO NOT edit signatures without an architecture amendment.

import 'dart:typed_data';

import '_sef_constants.dart';

/// Builds the SEF inline marker (24 B) and SEFH/SEFT trailer (32 B for
/// single-record case). Pure-function surface — no file IO, no state.
///
/// The byte layouts are fully specified in Doc 2 §3.2 / §3.3; this class
/// is deterministic and idempotent.
class SefWriter {
  /// Size of the 24-byte inline marker that precedes the MP4 payload.
  static const int inlineMarkerBytes = kInlineMarkerTotalBytes;

  /// Size of the SEFH+body+SEFT trailer for the single-record case.
  static const int trailerBytes = kSefTrailerTotalBytes;

  /// Emits the 24-byte inline marker sequence: 4 bytes of magic
  /// (`00 00 30 0A`, stored verbatim big-endian-looking), 4 bytes of
  /// name-length (= 16, uint32 LE), 16 bytes of ASCII "MotionPhoto_Data"
  /// (no null terminator). See Doc 2 §3.2. The returned buffer is freshly
  /// allocated.
  static Uint8List buildInlineMarker() {
    final out = Uint8List(kInlineMarkerTotalBytes);
    final bd = ByteData.view(out.buffer);

    // 0x00..0x04 — marker magic (big-endian-looking, stored verbatim).
    out.setRange(0, 4, kInlineMarkerMagic);

    // 0x04..0x08 — name_length = 16 (uint32 LE).
    bd.setUint32(4, kInlineMarkerNameLength, Endian.little);

    // 0x08..0x18 — 16-byte ASCII "MotionPhoto_Data".
    out.setRange(8, 24, kMotionPhotoDataName);

    return out;
  }

  /// Emits the SEFH..SEFT trailer for a single-record file. The layout
  /// matches Doc 2 §3.3 exactly:
  ///
  /// ```
  ///   0x00..0x04  "SEFH"
  ///   0x04..0x08  version (uint32 LE)
  ///   0x08..0x0C  entry_count = 1 (uint32 LE)
  ///   0x0C..0x10  record type_code = 00 00 30 0A (verbatim, big-endian-looking)
  ///   0x10..0x14  offsetFromSefhToInlineMarker (uint32 LE)
  ///   0x14..0x18  data_length = same as offset (uint32 LE)
  ///   0x18..0x1C  total_sef_size = 24 (uint32 LE)
  ///   0x1C..0x20  "SEFT"
  /// ```
  ///
  /// [offsetFromSefhToInlineMarker] is the positive backward distance
  /// from SEFH file position to the inline marker file position (v1.0's
  /// "negative from SEFT" phrasing was wrong).
  ///
  /// [sefVersion] defaults to 106 (doodspav reference implementation).
  static Uint8List buildSefTrailer({
    required int offsetFromSefhToInlineMarker,
    int sefVersion = kSefVersion,
  }) {
    if (offsetFromSefhToInlineMarker < 0 || offsetFromSefhToInlineMarker > 0xFFFFFFFF) {
      throw ArgumentError(
        'offsetFromSefhToInlineMarker out of uint32 range: $offsetFromSefhToInlineMarker',
      );
    }
    if (sefVersion < 0 || sefVersion > 0xFFFFFFFF) {
      throw ArgumentError('sefVersion out of uint32 range: $sefVersion');
    }

    final out = Uint8List(kSefTrailerTotalBytes);
    final bd = ByteData.view(out.buffer);

    // 0x00..0x04  "SEFH".
    out.setRange(0, 4, kSefhMagic);
    // 0x04..0x08  version (uint32 LE).
    bd.setUint32(4, sefVersion, Endian.little);
    // 0x08..0x0C  entry_count = 1 (uint32 LE).
    bd.setUint32(8, 1, Endian.little);
    // 0x0C..0x10  record type_code (verbatim bytes).
    out.setRange(12, 16, kInlineMarkerMagic);
    // 0x10..0x14  offsetFromSefhToInlineMarker (uint32 LE).
    bd.setUint32(16, offsetFromSefhToInlineMarker, Endian.little);
    // 0x14..0x18  data_length = same as offset (uint32 LE).
    bd.setUint32(20, offsetFromSefhToInlineMarker, Endian.little);
    // 0x18..0x1C  total_sef_size = 24 (uint32 LE).
    bd.setUint32(24, 24, Endian.little);
    // 0x1C..0x20  "SEFT".
    out.setRange(28, 32, kSeftMagic);

    return out;
  }
}
