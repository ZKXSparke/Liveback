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

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../exceptions/liveback_exceptions.dart';
import '../models/gallery_album.dart';
import '../models/gallery_item.dart';
import 'motion_photo_probe.dart' show MotionPhotoProbe;

export 'motion_photo_probe.dart' show MotionPhotoProbe;

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

  /// Cheap Motion-Photo classification for a single [contentUri]. Runs on
  /// Kotlin's IO dispatcher in a tail-probe + head-probe sequence (see
  /// `MediaStorePlugin.probeMotionPhoto`). Results are memoised per URI in
  /// an in-memory LRU so scrolling back through the gallery never
  /// re-probes.
  ///
  /// On PERMISSION_DENIED propagates [PermissionDeniedException]. All
  /// other Kotlin failures are caught inside the plugin and surface as
  /// `MotionPhotoProbe(isMotionPhoto:false, isSamsungNative:false)` so the
  /// gallery tile renders without a badge rather than throwing.
  Future<MotionPhotoProbe> probeMotionPhoto(String contentUri) async {
    final cached = _probeCache._get(contentUri);
    if (cached != null) return cached;
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>(
        'probeMotionPhoto',
        {'contentUri': contentUri},
      );
      final isMotionPhoto = (map?['isMotionPhoto'] as bool?) ?? false;
      final isSamsungNative = (map?['isSamsungNative'] as bool?) ?? false;
      final probe = MotionPhotoProbe(
        isMotionPhoto: isMotionPhoto,
        isSamsungNative: isSamsungNative,
      );
      _probeCache._put(contentUri, probe);
      return probe;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') throw _mapChannelError(e);
      // Any other error collapses to a no-badge result and is NOT cached —
      // the failure might be transient (e.g. URI being rewritten), so a
      // re-probe later is fine.
      return const MotionPhotoProbe(
        isMotionPhoto: false,
        isSamsungNative: false,
      );
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

/// Module-private LRU keyed by contentUri. Capped at 500 entries — typical
/// gallery scroll sessions touch ~300 tiles, so this fits comfortably.
const int _kProbeCacheCap = 500;

class _ProbeLruCache {
  final LinkedHashMap<String, MotionPhotoProbe> _map =
      LinkedHashMap<String, MotionPhotoProbe>();

  MotionPhotoProbe? _get(String key) {
    final v = _map.remove(key);
    if (v == null) return null;
    _map[key] = v; // re-insert at tail (MRU position)
    return v;
  }

  void _put(String key, MotionPhotoProbe probe) {
    if (_map.containsKey(key)) {
      _map.remove(key);
    } else if (_map.length >= _kProbeCacheCap) {
      // Evict oldest (head of insertion order).
      _map.remove(_map.keys.first);
    }
    _map[key] = probe;
  }

  /// Visible for testing — drops all entries.
  void _clear() => _map.clear();

  /// Visible for testing — current size.
  int get _size => _map.length;
}

final _ProbeLruCache _probeCache = _ProbeLruCache();

/// Visible for testing: clears the module-private probe cache so each test
/// runs from a clean slate.
@visibleForTesting
void debugClearMotionPhotoProbeCache() => _probeCache._clear();

/// Visible for testing: current cache size.
@visibleForTesting
int debugMotionPhotoProbeCacheSize() => _probeCache._size;
