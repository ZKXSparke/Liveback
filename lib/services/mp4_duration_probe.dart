// Owner: T1 (binary-format teammate). Reference: Doc 2 §5.
// DO NOT edit signatures without an architecture amendment.

import 'dart:io';

/// Reads `mvhd.duration` / `mvhd.timescale` from an MP4 moov. Does NOT
/// read mdat — only seeks through ftyp → moov → mvhd.
///
/// See Doc 2 §5.2 for the box-walk algorithm and §5.3 for version-0 vs
/// version-1 mvhd handling.
class Mp4DurationProbe {
  /// Probes the MP4 that starts at [ftypOffset] inside the random-access
  /// file [raf]. [fileEnd] is the exclusive upper bound (usually the
  /// physical file size). Returns null if mvhd is absent or malformed
  /// (caller treats null as "no video" and returns
  /// `FixResult(kind: skippedNotMotionPhoto)` per Doc 2 §6.2).
  Future<Mp4Duration?> probe(
    RandomAccessFile raf,
    int ftypOffset,
    int fileEnd,
  ) {
    throw UnimplementedError('T1 — Doc 2 §5.4 (Mp4DurationProbe.probe)');
  }
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
