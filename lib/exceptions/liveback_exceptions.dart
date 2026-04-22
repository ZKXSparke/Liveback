// Owner: T1 (binary-format teammate). Reference: Doc 2 §7 + Doc 1 §A.3.
// DO NOT edit without an architecture amendment.
//
// Every .errorCode below MUST equal one of the ErrorCodes.* constants in
// core/error_codes.dart. OperationCancelledException is intentionally NOT
// a LivebackException — see core/cancellation.dart.
//
// i18n refactor (kk/i18n-en-zh): LivebackException no longer carries a
// user-facing message string. The errorCode is now the only stable
// identifier; UI code looks up localized copy via
// `context.l10n.errorMessageFor(errorCode, detail: ...)` at render time.
// Optional `technicalDetail` stays English (developer diagnostic, piped
// to the ErrorDialog's hidden chip in debug builds).

import '../core/error_codes.dart';

/// Root of the recoverable-failure tree. The Worker's catch tree
/// (Doc 1 §A.4 step 2) catches this and produces FixError(...).
abstract class LivebackException implements Exception {
  /// One of [ErrorCodes].* constants.
  final String errorCode;

  /// Developer-facing English detail (e.g., "APP1 segment too short").
  /// Never shown to end users; surfaced only inside ErrorDialog's debug
  /// chip. Intentionally NOT localized.
  final String? technicalDetail;

  /// Optional wrapped root cause (e.g., IOException from File IO).
  final Object? cause;

  const LivebackException({
    required this.errorCode,
    this.technicalDetail,
    this.cause,
  });

  @override
  String toString() =>
      '[$errorCode]${technicalDetail == null ? '' : ' ($technicalDetail)'}';
}

/// Source file is not a parseable JPEG (SOI/EOI missing, segment length
/// mismatch, etc.). Throw site: motion_photo_parser (Doc 2 §2).
class InvalidFileFormatException extends LivebackException {
  InvalidFileFormatException([String? detail])
      : super(errorCode: ErrorCodes.jpegParse, technicalDetail: detail);
}

/// File size exceeds [LivebackConstants.maxFileSizeBytes]. Throw site:
/// fix_service pre-flight (Doc 2 §6.2).
class FileTooLargeException extends LivebackException {
  final int size;
  FileTooLargeException({required this.size})
      : super(
          errorCode: ErrorCodes.fileTooLarge,
          technicalDetail: 'size=$size',
        );
}

/// EXIF APP1 segment would exceed the 64 KB single-segment limit after
/// rewrite. Throw site: exif_rewriter (Doc 2 §4.4).
class AppOneTooLargeException extends LivebackException {
  AppOneTooLargeException() : super(errorCode: ErrorCodes.app1Overflow);
}

/// Streaming write to the sandbox output file failed. Throw site:
/// fix_service write phase (Doc 2 §9).
class SefWriteFailedException extends LivebackException {
  SefWriteFailedException([Object? cause])
      : super(
          errorCode: ErrorCodes.sefWriteFail,
          technicalDetail: cause?.toString(),
          cause: cause,
        );
}

/// Atomic rename interrupted or output file length mismatch. Throw site:
/// fix_service atomic-rename phase (Doc 2 §9).
class WriteCorruptException extends LivebackException {
  WriteCorruptException([Object? cause])
      : super(
          errorCode: ErrorCodes.writeCorrupt,
          technicalDetail: cause?.toString(),
          cause: cause,
        );
}

/// Media/notification permission absent or revoked at operation boundary.
/// Throw site: MediaStoreChannel boundary (Doc 1 §A.3 table).
class PermissionDeniedException extends LivebackException {
  PermissionDeniedException() : super(errorCode: ErrorCodes.permission);
}
