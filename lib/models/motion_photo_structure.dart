// Owner: T1 (binary-format teammate). Reference: Doc 2 §1.1 + §2.
// DO NOT edit signatures without an architecture amendment.
//
// Pure value types — no Flutter imports, no dart:ui. Returned by
// MotionPhotoParser.parse and consumed by sef_writer / exif_rewriter /
// fix_service. Fields that are null indicate "segment not present",
// NOT "parse failed" (parse failures throw InvalidFileFormatException).

/// Structural scan result of a candidate Motion Photo JPEG.
class MotionPhotoStructure {
  /// Total source file size in bytes.
  final int fileSize;

  /// Byte offset of the SOI (FF D8). Always 0 for a valid JPEG.
  final int jpegStart;

  /// Byte offset immediately AFTER the JPEG EOI (FF D9) — i.e.
  /// exclusive upper bound. `fileContents[jpegStart..jpegEnd]` is the
  /// full primary JPEG stream.
  final int jpegEnd;

  /// Byte offset of the MP4 'ftyp' box magic (within the trailing data
  /// after JPEG EOI), or null if no MP4 segment present.
  final int? mp4Start;

  /// Byte offset immediately after the MP4 payload (exclusive), or null
  /// if no MP4 segment.
  final int? mp4End;

  /// True iff the 24-byte '00 00 30 0A' inline marker already sits right
  /// before [mp4Start].
  final bool hasExistingSefInlineMarker;

  /// Byte offset of the existing inline marker (if any).
  final int? existingSefInlineMarkerOffset;

  /// Parsed SEFH..SEFT trailer at EOF, or null if none.
  final ExistingSefTrailer? existingSefTrailer;

  /// APP1 EXIF segment byte range + decoded Make/Model + parsed
  /// DateTimeOriginal. Null if the source has no EXIF APP1 at all.
  final ExifBlock? exifAppOne;

  /// Byte offset of the APP1 XMP segment (separate from EXIF APP1). We
  /// never rewrite XMP — recorded only for diagnostic dumps.
  final int? xmpSegmentOffset;

  /// Payload length of the XMP APP1, excluding the FF E1 marker + 2-byte
  /// size prefix. Null iff [xmpSegmentOffset] is null.
  final int? xmpLength;

  /// mvhd.duration (in timescale units). Null if no MP4 / mvhd.
  final int? mvhdDurationUnits;

  /// mvhd.timescale (units per second). Null if no MP4 / mvhd.
  final int? mvhdTimescale;

  const MotionPhotoStructure({
    required this.fileSize,
    required this.jpegStart,
    required this.jpegEnd,
    required this.mp4Start,
    required this.mp4End,
    required this.hasExistingSefInlineMarker,
    required this.existingSefInlineMarkerOffset,
    required this.existingSefTrailer,
    required this.exifAppOne,
    required this.xmpSegmentOffset,
    required this.xmpLength,
    required this.mvhdDurationUnits,
    required this.mvhdTimescale,
  });

  /// Convenience accessor. Null if either mvhd field is missing or
  /// timescale is 0.
  double? get videoDurationSeconds {
    final d = mvhdDurationUnits;
    final s = mvhdTimescale;
    if (d == null || s == null || s == 0) return null;
    return d / s;
  }
}

/// Parsed SEF trailer at EOF.
class ExistingSefTrailer {
  /// File position of the 'SEFH' magic.
  final int sefhFilePosition;
  final int version;
  final int recordCount;
  final List<SefRecord> records;

  /// Trailer byte length declared inside SEFT.
  final int declaredSefSize;

  const ExistingSefTrailer({
    required this.sefhFilePosition,
    required this.version,
    required this.recordCount,
    required this.records,
    required this.declaredSefSize,
  });
}

/// One record entry inside a SEFH..SEFT trailer.
class SefRecord {
  final int typeCode;
  final int offsetFromSefh;
  final int dataLength;

  const SefRecord({
    required this.typeCode,
    required this.offsetFromSefh,
    required this.dataLength,
  });
}

/// APP1 EXIF block description.
class ExifBlock {
  /// Byte offset of the FF E1 marker.
  final int segmentStart;

  /// Total segment length INCLUDING the FF E1 marker + 2-byte size field.
  final int segmentLength;

  /// IFD0 Make tag (0x010F), decoded as ASCII with null termination
  /// trimmed. Null iff tag absent.
  final String? make;

  /// IFD0 Model tag (0x0110), same decoding rule as [make].
  final String? model;

  /// EXIF DateTimeOriginal → epoch ms. Null if EXIF is missing OR the
  /// DateTimeOriginal tag is absent. Per review B7, enables fix_service
  /// to fall back to `DateTime.now()` for the output's DATE_TAKEN.
  final int? dateTimeOriginalMs;

  const ExifBlock({
    required this.segmentStart,
    required this.segmentLength,
    required this.make,
    required this.model,
    required this.dateTimeOriginalMs,
  });
}
