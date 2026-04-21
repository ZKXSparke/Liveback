// Owner: T1 (binary-format teammate). Reference: Doc 2 §7 + Doc 1 §A.3.
// DO NOT edit without an architecture amendment.
//
// Every .errorCode below MUST equal one of the ErrorCodes.* constants in
// core/error_codes.dart. OperationCancelledException is intentionally NOT
// a LivebackException — see core/cancellation.dart.

import '../core/error_codes.dart';

/// Root of the recoverable-failure tree. The Worker's catch tree
/// (Doc 1 §A.4 step 2) catches this and produces FixError(...).
abstract class LivebackException implements Exception {
  /// One of [ErrorCodes].* constants.
  final String errorCode;

  /// User-facing zh-CN text (v1.1 §5.8).
  final String message;

  /// Optional wrapped root cause (e.g., IOException from File IO).
  final Object? cause;

  const LivebackException(this.errorCode, this.message, [this.cause]);

  @override
  String toString() => '[$errorCode] $message';
}

/// Source file is not a parseable JPEG (SOI/EOI missing, segment length
/// mismatch, etc.). Throw site: motion_photo_parser (Doc 2 §2).
class InvalidFileFormatException extends LivebackException {
  InvalidFileFormatException([String detail = ''])
      : super(
          ErrorCodes.jpegParse,
          detail.isEmpty
              ? '文件格式错误，可能不是有效的 JPEG'
              : '文件格式错误，可能不是有效的 JPEG（$detail）',
        );
}

/// File size exceeds [LivebackConstants.maxFileSizeBytes]. Throw site:
/// fix_service pre-flight (Doc 2 §6.2).
class FileTooLargeException extends LivebackException {
  final int size;
  FileTooLargeException({required this.size})
      : super(ErrorCodes.fileTooLarge, '文件太大（>2GB），请先裁剪视频');
}

/// EXIF APP1 segment would exceed the 64 KB single-segment limit after
/// rewrite. Throw site: exif_rewriter (Doc 2 §4.4).
class AppOneTooLargeException extends LivebackException {
  AppOneTooLargeException()
      : super(ErrorCodes.app1Overflow, '文件元数据过大，无法安全重写');
}

/// Streaming write to the sandbox output file failed. Throw site:
/// fix_service write phase (Doc 2 §9).
class SefWriteFailedException extends LivebackException {
  SefWriteFailedException([Object? cause])
      : super(ErrorCodes.sefWriteFail, '写入失败，请检查存储空间', cause);
}

/// Atomic rename interrupted or output file length mismatch. Throw site:
/// fix_service atomic-rename phase (Doc 2 §9).
class WriteCorruptException extends LivebackException {
  WriteCorruptException([Object? cause])
      : super(ErrorCodes.writeCorrupt, '写入中断，输出文件不完整', cause);
}

/// Media/notification permission absent or revoked at operation boundary.
/// Throw site: MediaStoreChannel boundary (Doc 1 §A.3 table).
class PermissionDeniedException extends LivebackException {
  PermissionDeniedException()
      : super(ErrorCodes.permission, '未获得存储或通知权限');
}
