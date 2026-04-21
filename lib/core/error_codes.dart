// Owner: shared (Phase 1 SSoT). Reference: Doc 1 §A.3 + UI-Brand-decisions.md §6.
// DO NOT edit without an architecture amendment.
//
// Every Dart-side errorCode string MUST be one of these constants. The
// ErrorDialog chip (brand §5.3) reads whatever string lands in
// FixError.errorCode, so stringly-typed typos here propagate to the UI.

/// Canonical error-code constants.
///
/// These are strings (not an enum) so that cross-isolate messages and
/// MethodChannel PlatformException mappings remain dependency-free.
///
/// **`alreadySamsung` / `noMp4` are reserved identifiers** (brand §6) but
/// currently have NO Dart exception — they flow as `FixResult.kind` values
/// through the skipped-result sum type (Doc 1 §A.1 + §A.3).
abstract class ErrorCodes {
  static const jpegParse      = 'ERR_JPEG_PARSE';
  static const noMp4          = 'ERR_NO_MP4';
  static const alreadySamsung = 'ERR_ALREADY_SAMSUNG';
  static const fileTooLarge   = 'ERR_FILE_TOO_LARGE';
  static const sefWriteFail   = 'ERR_SEF_WRITE_FAIL';
  static const writeCorrupt   = 'ERR_WRITE_CORRUPT';
  static const app1Overflow   = 'ERR_APP1_OVERFLOW';
  static const permission     = 'ERR_PERMISSION';
  static const unknown        = 'ERR_UNKNOWN';

  // Note: ERR_VIDEO_TOO_LONG and ERR_WRITE are explicitly NOT on this list.
  //   >3s video is a soft warning (FixResult.videoTooLongWarning bool).
  //   WriteFailedException was retired; ERR_SEF_WRITE_FAIL covers it.
}
