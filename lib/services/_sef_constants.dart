// Owner: T1 (binary-format teammate). Reference: Doc 2 Appendix A.
// Binary-format-library-local constants only.
//
// App-wide constants (EXIF make/model, sandbox path, public output folder,
// filename template, channel names) live in `core/constants.dart` under
// `LivebackConstants` — see Doc 1 §A.10. Import those from there rather
// than re-declaring.

import 'dart:typed_data';

/// Logical type code for the `MotionPhoto_Data` SEF record. Stored on
/// disk as the four bytes 00 00 30 0A (big-endian-looking), and compared
/// with a big-endian uint32 read.
const int kMotionPhotoDataTypeCode = 0x0000300A;

/// SEF directory version. doodspav default; samples observed 103–107.
const int kSefVersion = 106;

/// Total bytes of the inline marker that sits between JPEG EOI and ftyp.
const int kInlineMarkerTotalBytes = 24;

/// Total bytes of the SEF trailer for a single-record file.
const int kSefTrailerTotalBytes = 32;

/// Upper bound of a single APP1 segment payload (64 KiB minus 2 for the
/// size field itself). FF E1 + `len_BE` where `len_BE` includes its own
/// two bytes — so the actual payload cap is `0xFFFF − 2 = 0xFFFD`.
const int kJpegMaxAppOneSize = 0xFFFD;

/// Magic bytes for inline marker (= kMotionPhotoDataTypeCode big-endian).
final Uint8List kInlineMarkerMagic = Uint8List.fromList([0x00, 0x00, 0x30, 0x0A]);

/// ASCII "SEFH".
final Uint8List kSefhMagic = Uint8List.fromList([0x53, 0x45, 0x46, 0x48]);

/// ASCII "SEFT".
final Uint8List kSeftMagic = Uint8List.fromList([0x53, 0x45, 0x46, 0x54]);

/// ASCII "ftyp".
final Uint8List kFtypMagic = Uint8List.fromList([0x66, 0x74, 0x79, 0x70]);

/// ASCII "MotionPhoto_Data" — the 16-byte name embedded in the inline
/// marker (Doc 2 §3.2).
final Uint8List kMotionPhotoDataName = Uint8List.fromList(
  [0x4D, 0x6F, 0x74, 0x69, 0x6F, 0x6E, 0x50, 0x68, 0x6F, 0x74, 0x6F, 0x5F, 0x44, 0x61, 0x74, 0x61],
);

/// Name length field (= 16, uint32 LE) embedded in the inline marker.
const int kInlineMarkerNameLength = 16;
