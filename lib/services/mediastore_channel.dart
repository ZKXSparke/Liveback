// Owner: T2 (Android platform teammate). Reference: Doc 1 §A.6 + Doc 3 §2/§3.
// DO NOT edit signatures without an architecture amendment.
//
// Dart-facing facade over the `com.sparker.liveback/mediastore` MethodChannel.
// The lower-level Kotlin methods (createOutputUri, openOutputDescriptor,
// finalizePendingOutput, etc.) remain plugin-callable for Test Mode, but
// this wrapper exposes only the compressed Plan A surface from Doc 1 §A.6.
//
// _mapChannelError(PlatformException) is where Kotlin error codes
// (QUERY_FAILED / INSERT_FAILED / NO_SPACE / PERMISSION_DENIED / ...)
// get translated into LivebackException subclasses (Doc 1 §A.3 tail).

import 'dart:typed_data';

import '../models/gallery_item.dart';

class MediaStoreChannel {
  /// Lists JPEG images from MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
  /// sorted by DATE_TAKEN DESC. Paged via [offset] / [limit].
  Future<List<GalleryItem>> queryImages({
    int limit = 500,
    int offset = 0,
  }) {
    throw UnimplementedError('T2 — Kotlin MethodChannel not wired yet');
  }

  /// Returns a JPEG-encoded thumbnail for [contentUri], square of size
  /// [maxDim]. Null if the source URI has disappeared since the last
  /// queryImages snapshot (THUMB_LOAD_FAILED — UI should grey the cell).
  Future<Uint8List?> getThumbnail(String contentUri, {int maxDim = 256}) {
    throw UnimplementedError('T2 — Kotlin MethodChannel not wired yet');
  }

  /// Plan A: Kotlin copies the `contentUri` bytes to
  /// `cache/liveback-io/in-<taskId>.jpg` and returns that absolute path.
  /// TaskQueue (or direct caller) owns cleanup via [releaseSandbox].
  Future<String> copyInputToSandbox({
    required String contentUri,
    required String taskId,
  }) {
    throw UnimplementedError('T2 — Kotlin MethodChannel not wired yet');
  }

  /// Plan A: reserves `cache/liveback-io/out-<taskId>.jpg` and returns
  /// the absolute path. fix_service writes its output bytes to this
  /// path; caller then invokes [publishOutputToMediaStore] on success.
  Future<String> reserveOutputSandbox({required String taskId}) {
    throw UnimplementedError('T2 — Kotlin MethodChannel not wired yet');
  }

  /// Plan A: moves the bytes at [sandboxOutPath] into MediaStore
  /// `Pictures/Liveback/` via IS_PENDING=1 → copy → IS_PENDING=0
  /// two-phase publish. Returns the resulting content:// URI.
  ///
  /// [displayName] SHOULD be `LivebackConstants.outputFileName(dt)` where
  /// dt is constructed from [dateTakenEpochMs]; keeping filename and
  /// MediaStore DATE_TAKEN in sync (Doc 3 §2.5 ownership table).
  Future<String> publishOutputToMediaStore({
    required String sandboxOutPath,
    required String displayName,
    required int dateTakenEpochMs,
    required int originalMtimeEpochMs,
  }) {
    throw UnimplementedError('T2 — Kotlin MethodChannel not wired yet');
  }

  /// Deletes `in-<taskId>.jpg` and `out-<taskId>.jpg`. Tolerates missing
  /// files (skipped tasks produce no output — see Doc 3 §3).
  Future<void> releaseSandbox({required String taskId}) {
    throw UnimplementedError('T2 — Kotlin MethodChannel not wired yet');
  }
}
