// Owner: T1 (binary-format teammate). Reference: Doc 2 §3.
// DO NOT edit signatures without an architecture amendment.

import 'dart:typed_data';

/// Builds the SEF inline marker (24 B) and SEFH/SEFT trailer (32 B for
/// single-record case). Pure-function surface — no file IO, no state.
///
/// The byte layouts are fully specified in Doc 2 §3.2 / §3.3; this class
/// is deterministic and idempotent.
class SefWriter {
  /// Size of the 24-byte inline marker that precedes the MP4 payload.
  static const int inlineMarkerBytes = 24;

  /// Size of the SEFH+body+SEFT trailer for the single-record case.
  static const int trailerBytes = 32;

  /// Emits the 24-byte inline marker sequence (`00 00 30 0A` + padding
  /// per Doc 2 §3.2). The returned buffer is freshly allocated.
  static Uint8List buildInlineMarker() {
    throw UnimplementedError('T1 — Doc 2 §3.2 (inline marker)');
  }

  /// Emits the SEFH..SEFT trailer for a single-record file.
  ///
  /// [offsetFromSefhToInlineMarker] is the negative offset (as stored
  /// by Samsung) from SEFH file position back to the inline marker
  /// position. See Doc 2 §3.3 / §3.4.
  ///
  /// [sefVersion] defaults to 106 (doodspav reference implementation).
  static Uint8List buildSefTrailer({
    required int offsetFromSefhToInlineMarker,
    int sefVersion = 106,
  }) {
    throw UnimplementedError('T1 — Doc 2 §3.3 (SEF trailer)');
  }
}
