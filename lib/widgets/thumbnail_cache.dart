// Gallery thumbnail cache with bounded concurrency and per-URI Future
// dedup. Reduces MethodChannel contention (multiple tiles asking for the
// same thumbnail in flight collapse to one request) and avoids MediaStore
// thrashing (cap of `_maxConcurrent` in-flight platform calls).
//
// Bytes are cached by contentUri in an LRU up to `_maxCacheEntries` items.
// Tiles read through `fetch(uri, maxDim)`; a single shared Future is
// returned per URI while in flight.

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../services/mediastore_channel.dart';

/// Bounded-concurrency thumbnail fetcher.
///
/// * Concurrency cap: 6 simultaneous platform calls (MediaStore fan-out
///   thrashes the disk and stalls the main channel above this).
/// * Dedup: tiles asking for the same URI while one is in flight share
///   the pending Future.
/// * LRU: last 500 URIs retained in bytes; evicts oldest on overflow.
class ThumbnailCache {
  static final ThumbnailCache instance = ThumbnailCache._();
  ThumbnailCache._();

  static const int _maxConcurrent = 6;
  static const int _maxCacheEntries = 500;

  final _MediaStore _channel = _MediaStore();
  final LinkedHashMap<String, Uint8List?> _bytes =
      LinkedHashMap<String, Uint8List?>();
  final Map<String, Future<Uint8List?>> _inFlight = {};
  final Queue<_PendingFetch> _pending = Queue();
  int _active = 0;

  /// Returns the cached bytes for [contentUri], or starts / joins an
  /// in-flight fetch. Resolves to null if MediaStore returned null
  /// (e.g., URI disappeared, thumbnail decode failed).
  Future<Uint8List?> fetch(String contentUri, {int maxDim = 512}) {
    if (_bytes.containsKey(contentUri)) {
      // Touch entry to mark recent-use for LRU.
      final v = _bytes.remove(contentUri);
      _bytes[contentUri] = v;
      return Future.value(v);
    }
    final existing = _inFlight[contentUri];
    if (existing != null) return existing;

    final completer = Completer<Uint8List?>();
    final future = completer.future;
    _inFlight[contentUri] = future;
    _pending.add(_PendingFetch(contentUri, maxDim, completer));
    _pump();
    return future;
  }

  void _pump() {
    while (_active < _maxConcurrent && _pending.isNotEmpty) {
      final p = _pending.removeFirst();
      _active++;
      unawaited(_runOne(p));
    }
  }

  Future<void> _runOne(_PendingFetch p) async {
    Uint8List? result;
    try {
      result = await _channel
          .getThumbnail(p.contentUri, maxDim: p.maxDim);
    } catch (_) {
      result = null;
    }
    _inFlight.remove(p.contentUri);
    _bytes[p.contentUri] = result;
    if (_bytes.length > _maxCacheEntries) {
      _bytes.remove(_bytes.keys.first);
    }
    if (!p.completer.isCompleted) p.completer.complete(result);
    _active--;
    _pump();
  }

  /// Drops the cache and pending queue. Primarily for tests.
  void clear() {
    _bytes.clear();
    _pending.clear();
  }
}

class _PendingFetch {
  final String contentUri;
  final int maxDim;
  final Completer<Uint8List?> completer;
  _PendingFetch(this.contentUri, this.maxDim, this.completer);
}

// Thin seam so tests can swap in a fake channel without importing the
// full MediaStoreChannel surface.
class _MediaStore {
  final MediaStoreChannel _channel = MediaStoreChannel();
  Future<Uint8List?> getThumbnail(String uri, {int maxDim = 512}) =>
      _channel.getThumbnail(uri, maxDim: maxDim);
}
