// Owner: T1 (binary-format teammate). Reference: Doc 2 §4.
// DO NOT edit signatures without an architecture amendment.

import 'dart:typed_data';

/// Rewrites IFD0 Make/Model inside an APP1 EXIF segment, or builds a
/// fresh APP1 from scratch for inputs that lack EXIF entirely (djimimo
/// case, Doc 2 §4.5). Pure bytes-in / bytes-out.
///
/// Returns `List<Uint8List>` to leave room for multi-segment APP1 split
/// in future revisions (MVP always returns a single-element list or
/// throws [AppOneTooLargeException] per Doc 2 §4.4).
class ExifRewriter {
  /// Rewrites IFD0 Make (0x010F) and Model (0x0110) tags inside an
  /// existing APP1 EXIF segment. Returns fresh APP1 bytes including the
  /// FF E1 marker + 2-byte size prefix + "Exif\0\0" identifier + TIFF
  /// header + IFDs. Throws `AppOneTooLargeException` if the rewrite
  /// would push the segment above 64 KB.
  List<Uint8List> rewriteMakeModel({
    required Uint8List originalAppOne,
    required String make,
    required String model,
  }) {
    throw UnimplementedError('T1 — Doc 2 §4.3 / §4.4 (rewriteMakeModel)');
  }

  /// Builds a fresh APP1 EXIF block from scratch. Used when the source
  /// has no EXIF APP1 at all. [dateTimeOriginal] is optional; if null
  /// the output omits the DateTimeOriginal tag entirely (Doc 2 §4.5 —
  /// filename/mtime still drive the MediaStore DATE_TAKEN column).
  List<Uint8List> buildFreshExifAppOne({
    required String make,
    required String model,
    required int imageWidth,
    required int imageHeight,
    required int orientation,
    DateTime? dateTimeOriginal,
  }) {
    throw UnimplementedError('T1 — Doc 2 §4.5 (buildFreshExifAppOne)');
  }
}
