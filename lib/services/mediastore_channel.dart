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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../exceptions/liveback_exceptions.dart';
import '../models/gallery_album.dart';
import '../models/gallery_item.dart';
import 'motion_photo_probe.dart' show MotionPhotoProbe;
import 'motion_photo_probe_cache.dart';

export 'motion_photo_probe.dart' show MotionPhotoProbe;

/// File-size floor (bytes) below which [MediaStoreChannel.probeMotionPhoto]
/// refuses to dispatch a real probe and instead records a synthetic
/// {isMotionPhoto:false, isSamsungNative:false} in the cache.
///
/// Heuristic justification (see §3c of kk/autoplay-filter-probe-perf
/// brief): Samsung S23 Motion Photos run 4–10 MB, djimimo 5–25 MB, camera
/// stills 1.5–4 MB, screenshots + downloaded images <500 KB. Shaving 500 KB
/// off the probe workload eliminates most of the long tail on 2000-photo
/// albums.
///
/// Known false-negative risk: if a Motion Photo somehow ships with
/// < 500 KB total bytes, it'll be filtered out. No such file has been
/// observed in the wild across the fixture corpus, so the risk is
/// accepted. Tune this constant (or set to 0) if that assumption breaks.
const int kProbeSizeFloorBytes = 500 * 1024;

class MediaStoreChannel {
  MediaStoreChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(LivebackConstants.channelMediaStore);

  final MethodChannel _channel;

  /// Lists JPEG images from MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
  /// sorted by DATE_TAKEN DESC. Paged via [offset] / [limit].
  ///
  /// [bucketId], when non-null, restricts the result to rows whose
  /// MediaStore BUCKET_ID matches — i.e. a single album/folder. Additive
  /// to Doc 1 §A.6; default `null` preserves the all-albums behaviour.
  Future<List<GalleryItem>> queryImages({
    int limit = 500,
    int offset = 0,
    int? bucketId,
  }) async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('queryImages', {
        'limit': limit,
        'offset': offset,
        if (bucketId != null) 'bucketId': bucketId,
      });
      if (raw == null) return const <GalleryItem>[];
      return raw
          .whereType<Map>()
          .map((m) => _parseGalleryItem(m.cast<String, dynamic>()))
          .toList(growable: false);
    } on PlatformException catch (e) {
      throw _mapChannelError(e);
    }
  }

  /// Returns the list of JPEG-containing MediaStore buckets (albums /
  /// folders), sorted by most-recently-taken photo. Capped at 100 albums.
  /// Empty list if the device has no JPEGs indexed — never null.
  Future<List<GalleryAlbum>> queryAlbums() async {
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('queryAlbums');
      if (raw == null) return const <GalleryAlbum>[];
      return raw
          .whereType<Map>()
          .map((m) => _parseGalleryAlbum(m.cast<String, dynamic>()))
          .toList(growable: false);
    } on PlatformException catch (e) {
      throw _mapChannelError(e);
    }
  }

  /// Cheap Motion-Photo classification for a single [contentUri]. Dispatches
  /// through [MotionPhotoProbeCache] which bounds concurrency (8 parallel
  /// probe calls) and dedups per-URI in-flight Futures, so thousands of
  /// tiles asking in parallel collapse to a sane serial workload over the
  /// single-threaded MethodChannel.
  ///
  /// Results are memoised in the cache's LRU so scrolling back never
  /// re-probes. On PERMISSION_DENIED propagates
  /// [PermissionDeniedException]. All other Kotlin failures degrade to
  /// `MotionPhotoProbe(false, false)` per Doc 1 §A.6.
  ///
  /// [fileSizeBytes], when supplied, enables the file-size pre-filter
  /// (see [kProbeSizeFloorBytes]): bytes below the floor short-circuit
  /// to a synthetic {false, false} without a channel round-trip.
  Future<MotionPhotoProbe> probeMotionPhoto(
    String contentUri, {
    int? fileSizeBytes,
  }) {
    if (fileSizeBytes != null && fileSizeBytes < kProbeSizeFloorBytes) {
      const synthetic = MotionPhotoProbe(
        isMotionPhoto: false,
        isSamsungNative: false,
      );
      MotionPhotoProbeCache.instance.putSynthetic(contentUri, synthetic);
      return Future.value(synthetic);
    }
    return MotionPhotoProbeCache.instance.fetch(contentUri, _channelProbe);
  }

  /// Raw channel probe, used as the dispatch target by the cache. Kept
  /// private so callers always go through [probeMotionPhoto] (which gives
  /// them dedup, bounded concurrency, and the size pre-filter).
  ///
  /// Error handling contract with [MotionPhotoProbeCache]:
  ///   * PERMISSION_DENIED → throw PermissionDeniedException. Cache
  ///     surfaces it to the caller and does NOT memoise.
  ///   * Any other PlatformException → re-thrown as-is. Cache catches it,
  ///     returns a degraded {false,false} probe to the caller, and does
  ///     NOT memoise (transient errors must be retriable).
  ///   * Happy path → returns the parsed probe. Cache memoises.
  Future<MotionPhotoProbe> _channelProbe(String contentUri) async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'probeMotionPhoto',
        {'contentUri': contentUri},
      );
      final isMotionPhoto = (map?['isMotionPhoto'] as bool?) ?? false;
      final isSamsungNative = (map?['isSamsungNative'] as bool?) ?? false;
      return MotionPhotoProbe(
        isMotionPhoto: isMotionPhoto,
        isSamsungNative: isSamsungNative,
      );
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') throw _mapChannelError(e);
      // Re-throw so the cache treats this as a transient failure
      // (degrades to no-badge but does NOT memoise). Retrying later is
      // the right call — the underlying URI may be being rewritten.
      rethrow;
    }
  }

  /// Returns a JPEG-encoded thumbnail for [contentUri], square of size
  /// [maxDim]. Null if the source URI has disappeared since the last
  /// queryImages snapshot (THUMB_LOAD_FAILED — UI should grey the cell).
  Future<Uint8List?> getThumbnail(String contentUri, {int maxDim = 256}) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('getThumbnail', {
        'contentUri': contentUri,
        'size': maxDim,
      });
      return bytes;
    } on PlatformException catch (e) {
      if (e.code == 'THUMB_LOAD_FAILED') return null;
      throw _mapChannelError(e);
    }
  }

  /// Plan A: Kotlin copies the `contentUri` bytes to
  /// `cache/liveback-io/in-<taskId>.jpg` and returns that absolute path.
  /// TaskQueue (or direct caller) owns cleanup via [releaseSandbox].
  Future<String> copyInputToSandbox({
    required String contentUri,
    required String taskId,
  }) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'copyInputToSandbox',
        {'contentUri': contentUri, 'taskId': taskId},
      );
      final path = res?['path'] as String?;
      if (path == null) {
        throw SefWriteFailedException(StateError('copyInputToSandbox returned no path'));
      }
      return path;
    } on PlatformException catch (e) {
      throw _mapChannelError(e);
    }
  }

  /// Plan A: reserves `cache/liveback-io/out-<taskId>.jpg` and returns
  /// the absolute path. fix_service writes its output bytes to this
  /// path; caller then invokes [publishOutputToMediaStore] on success.
  Future<String> reserveOutputSandbox({required String taskId}) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'reserveOutputSandbox',
        {'taskId': taskId},
      );
      final path = res?['path'] as String?;
      if (path == null) {
        throw SefWriteFailedException(StateError('reserveOutputSandbox returned no path'));
      }
      return path;
    } on PlatformException catch (e) {
      throw _mapChannelError(e);
    }
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
  }) async {
    try {
      final uri = await _channel.invokeMethod<String>(
        'publishOutputToMediaStore',
        {
          'sandboxOutPath': sandboxOutPath,
          'displayName': displayName,
          'dateTakenEpochMs': dateTakenEpochMs,
          'originalMtimeEpochMs': originalMtimeEpochMs,
          'relativePath': LivebackConstants.publicOutputFolder,
        },
      );
      if (uri == null || uri.isEmpty) {
        throw SefWriteFailedException(
            StateError('publishOutputToMediaStore returned null'));
      }
      return uri;
    } on PlatformException catch (e) {
      throw _mapChannelError(e);
    }
  }

  /// Deletes `in-<taskId>.jpg` and `out-<taskId>.jpg`. Tolerates missing
  /// files (skipped tasks produce no output — see Doc 3 §3).
  Future<void> releaseSandbox({required String taskId}) async {
    try {
      await _channel.invokeMethod<void>('deleteSandboxFiles', {'taskId': taskId});
    } on PlatformException catch (e) {
      // releaseSandbox is best-effort — swallow channel errors so a failed
      // cleanup never masks the real task outcome. The startup sweep will
      // reclaim anything left behind.
      assert(() {
        // ignore: avoid_print
        // In debug builds, surface the code so regressions are visible.
        // No print in production path.
        return true;
      }());
      // Let the caller see PERMISSION_DENIED — everything else is swallowed.
      if (e.code == 'PERMISSION_DENIED') throw _mapChannelError(e);
    }
  }

  /// Diagnostic / startup helper. Invokes `sweepSandbox`; returns the number
  /// of files removed. Safe to call on cold start. Does not map errors to
  /// LivebackException — returns 0 on any failure.
  Future<int> sweepSandbox() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('sweepSandbox');
      return (res?['deletedCount'] as int?) ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  // -------------------------------------------------------------------------
  // Parsing + error mapping
  // -------------------------------------------------------------------------

  GalleryAlbum _parseGalleryAlbum(Map<String, dynamic> m) {
    return GalleryAlbum(
      bucketId: (m['bucketId'] as num).toInt(),
      displayName: (m['displayName'] as String?) ?? '(未命名)',
      coverContentUri: m['coverContentUri'] as String,
      count: (m['count'] as num).toInt(),
    );
  }

  GalleryItem _parseGalleryItem(Map<String, dynamic> m) {
    // DATE_TAKEN may be absent — fall back to dateAddedMs for sort keying
    // per Doc 3 §2.1 ("may fall back to dateAddedMs"). The fallback applies
    // ONLY to sorting; we still expose nullable dateTakenMs so UI/metadata
    // paths can tell real-timestamp rows from fallbacks.
    final dateAddedMs = (m['dateAddedMs'] as num).toInt();
    final dateTakenRaw = m['dateTakenMs'];
    final dateTakenMs = dateTakenRaw is num ? dateTakenRaw.toInt() : null;

    return GalleryItem(
      id: (m['id'] as num).toInt(),
      contentUri: m['uri'] as String,
      displayName: m['displayName'] as String,
      size: (m['size'] as num).toInt(),
      dateTakenMs: dateTakenMs,
      dateAddedMs: dateAddedMs,
      width: (m['width'] as num?)?.toInt(),
      height: (m['height'] as num?)?.toInt(),
      mimeType: m['mimeType'] as String,
    );
  }

  /// Translates Kotlin [PlatformException.code] into a Dart-side
  /// [LivebackException] per Doc 1 §A.3 (Kotlin channel errors row).
  ///
  /// Categories (post-B2 lock):
  ///   PERMISSION_DENIED       → PermissionDeniedException (ERR_PERMISSION)
  ///   NO_SPACE                → WriteCorruptException     (ERR_WRITE_CORRUPT)
  ///   INVALID_DATE_TAKEN      → WriteCorruptException     (metadata-time invariant broken)
  ///   INSERT_FAILED /
  ///     FINALIZE_FAILED /
  ///     PUBLISH_FAILED /
  ///     COPY_FAILED /
  ///     UPDATE_FAILED /
  ///     DELETE_FAILED /
  ///     OPEN_FAILED /
  ///     SWEEP_FAILED            → SefWriteFailedException (ERR_SEF_WRITE_FAIL)
  ///   QUERY_FAILED            → SefWriteFailedException
  ///   THUMB_LOAD_FAILED       → caller swallows (see getThumbnail)
  ///   HANDLE_NOT_FOUND        → SefWriteFailedException
  ///   SANDBOX_MISSING         → SefWriteFailedException
  ///   INVALID_ARGUMENT        → SefWriteFailedException (defensive — a caller contract bug)
  ///   any other               → SefWriteFailedException
  ///
  /// Rationale: the binary writer's ERR_JPEG_PARSE / ERR_APP1_OVERFLOW
  /// errors are thrown in Dart (T1 scope) and never travel through this
  /// channel. Every Kotlin-origin error is either a permission boundary
  /// failure, a disk failure, or a programmer-error contract breach. The
  /// first maps to ERR_PERMISSION, the rest all map to ERR_SEF_WRITE_FAIL /
  /// ERR_WRITE_CORRUPT (storage-side failure buckets).
  LivebackException _mapChannelError(PlatformException e) {
    switch (e.code) {
      case 'PERMISSION_DENIED':
        return PermissionDeniedException();
      case 'NO_SPACE':
      case 'INVALID_DATE_TAKEN':
        return WriteCorruptException(e);
      default:
        return SefWriteFailedException(e);
    }
  }
}

/// Visible for testing: clears the shared MotionPhotoProbeCache so each
/// test runs from a clean slate. Retained at this path for back-compat
/// with existing suites that imported it before the cache was promoted
/// out of this file.
@visibleForTesting
void debugClearMotionPhotoProbeCache() =>
    MotionPhotoProbeCache.instance.clear();

/// Visible for testing: current cache size. Delegates to the shared
/// MotionPhotoProbeCache.
@visibleForTesting
int debugMotionPhotoProbeCacheSize() => MotionPhotoProbeCache.instance.size;
