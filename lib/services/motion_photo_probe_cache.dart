// Owner: T3 (UI teammate). Reference: lib/widgets/thumbnail_cache.dart
// (concurrency-bounded pattern) + Doc 1 §A.6 (probe semantics preserved).
//
// Bounded-concurrency Motion-Photo probe cache with per-URI in-flight
// dedup. Sits between gallery tiles / eager page-level probes and the
// Kotlin MethodChannel so that a 2000-photo album does not fan-out 2000
// concurrent probe calls through a single-threaded channel.
//
// Semantics (unchanged from the previous module-private LRU in
// mediastore_channel.dart):
//   * LRU cap 500, keyed by contentUri.
//   * MotionPhotoProbe is the value type; callers get a Future that
//     resolves to the same value the Kotlin side would have returned.
//   * PERMISSION_DENIED propagates — it's the only error that should
//     prompt the user. Everything else (including transient IO failures)
//     degrades to {isMotionPhoto:false, isSamsungNative:false} and is
//     NOT cached (the next access can retry).
//
// Added over the old structure:
//   * Concurrency cap: [_maxConcurrent] = 8 parallel probe calls. Extra
//     requests queue. Matches thumbnail_cache.dart shape.
//   * In-flight dedup: if tile A and page-level eager scan both ask for
//     URI X while X is mid-probe, they share the pending Future.
//   * File-size pre-filter hook: callers can call [putSynthetic] to seed
//     the cache with a {false,false} result for a URI whose file is
//     tiny enough to almost certainly not be a Motion Photo. The next
//     real fetch hits that entry without a channel round-trip.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../exceptions/liveback_exceptions.dart';
import 'motion_photo_probe.dart';

/// Shape of the channel-probe function so tests (and the singleton) can
/// inject a fake without pulling MediaStoreChannel into the cache.
typedef ProbeCallFn = Future<MotionPhotoProbe> Function(String contentUri);

/// Module-level singleton managing Motion-Photo probe dispatch for the
/// whole app. Mirror of [ThumbnailCache.instance].
class MotionPhotoProbeCache {
  static final MotionPhotoProbeCache instance = MotionPhotoProbeCache._();
  MotionPhotoProbeCache._();

  /// Concurrency bound. 8 parallel probes keeps the MethodChannel from
  /// starving while still draining 1000 URIs in ~125 serialized batches.
  static const int _maxConcurrent = 8;

  /// LRU cap — same as the old module-private cache in
  /// mediastore_channel.dart. Typical gallery scroll sessions touch
  /// ~300 tiles so 500 is comfortable headroom.
  static const int _maxCacheEntries = 500;

  /// Installed by MediaStoreChannel at construction. Visible for testing
  /// so suites can swap in a fake without pulling the full channel class.
  ProbeCallFn? _probeCall;

  final LinkedHashMap<String, MotionPhotoProbe> _cache =
      LinkedHashMap<String, MotionPhotoProbe>();
  final Map<String, Future<MotionPhotoProbe>> _inFlight = {};
  final Queue<_Pending> _pending = Queue();
  int _active = 0;

  /// Wire the channel-probe implementation. Called once from
  /// MediaStoreChannel.probeMotionPhoto on first use. Tests override via
  /// [debugSetProbeCallFn].
  void _ensureCall(ProbeCallFn fn) {
    _probeCall ??= fn;
  }

  /// Returns the cached probe for [contentUri], or enqueues a new
  /// channel-probe. Concurrent callers for the same URI share the
  /// pending Future (dedup).
  ///
  /// PERMISSION_DENIED surfaces as [PermissionDeniedException]; any other
  /// failure returns a neutral {false,false} probe and is NOT cached.
  Future<MotionPhotoProbe> fetch(String contentUri, ProbeCallFn call) {
    _ensureCall(call);

    final cached = _cache.remove(contentUri);
    if (cached != null) {
      // Touch entry: move to tail (MRU position).
      _cache[contentUri] = cached;
      return Future.value(cached);
    }
    final existing = _inFlight[contentUri];
    if (existing != null) return existing;

    final completer = Completer<MotionPhotoProbe>();
    final future = completer.future;
    _inFlight[contentUri] = future;
    _pending.add(_Pending(contentUri, completer));
    _pump();
    return future;
  }

  /// Seeds a synthetic no-probe result into the cache (used by the
  /// file-size pre-filter). Skips channel round-trips for files that
  /// are too small to plausibly be Motion Photos.
  void putSynthetic(String contentUri, MotionPhotoProbe probe) {
    if (_cache.containsKey(contentUri)) {
      // Don't overwrite a real probe with a synthetic one.
      return;
    }
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[contentUri] = probe;
  }

  /// Peek without inserting / touching LRU. Used by callers that want to
  /// avoid racing an eager probe with a tile probe.
  MotionPhotoProbe? peek(String contentUri) => _cache[contentUri];

  void _pump() {
    while (_active < _maxConcurrent && _pending.isNotEmpty) {
      final p = _pending.removeFirst();
      _active++;
      unawaited(_runOne(p));
    }
  }

  Future<void> _runOne(_Pending p) async {
    final call = _probeCall;
    // Three outcomes drive whether/how we memoise:
    //   1. happy path → real probe result, MEMOISE.
    //   2. transient failure → degrade to {false,false}, DO NOT MEMOISE
    //      (next fetch retries).
    //   3. permission error → rethrow, DO NOT MEMOISE.
    MotionPhotoProbe? real;
    MotionPhotoProbe? degraded;
    Object? permissionError;
    try {
      if (call == null) {
        // Misconfigured — treat as transient, same contract as a channel
        // glitch. Should never happen in production because
        // MediaStoreChannel.probeMotionPhoto wires this on first use.
        degraded = const MotionPhotoProbe(
          isMotionPhoto: false,
          isSamsungNative: false,
        );
      } else {
        real = await call(p.contentUri);
      }
    } on PermissionDeniedException catch (e) {
      permissionError = e;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        permissionError = PermissionDeniedException();
      } else {
        degraded = const MotionPhotoProbe(
          isMotionPhoto: false,
          isSamsungNative: false,
        );
      }
    } catch (_) {
      degraded = const MotionPhotoProbe(
        isMotionPhoto: false,
        isSamsungNative: false,
      );
    }

    _inFlight.remove(p.contentUri);
    if (real != null) {
      if (_cache.length >= _maxCacheEntries &&
          !_cache.containsKey(p.contentUri)) {
        _cache.remove(_cache.keys.first);
      }
      _cache[p.contentUri] = real;
      if (!p.completer.isCompleted) p.completer.complete(real);
    } else if (degraded != null) {
      // Degraded — do NOT memoise. Caller gets {false,false}; the next
      // fetch will retry the channel.
      if (!p.completer.isCompleted) p.completer.complete(degraded);
    } else if (permissionError != null) {
      if (!p.completer.isCompleted) p.completer.completeError(permissionError);
    }

    _active--;
    _pump();
  }

  /// Clears the cache + pending queue + in-flight map. Primarily a test
  /// helper (also used by [debugClearMotionPhotoProbeCache] in
  /// mediastore_channel.dart), but not annotated @visibleForTesting
  /// because mediastore_channel needs to forward to it from production
  /// code paths (debug hook for UI suites).
  void clear() {
    _cache.clear();
    _pending.clear();
    _inFlight.clear();
    _active = 0;
  }

  /// Current cache size. Not annotated @visibleForTesting for the same
  /// reason as [clear] — forwarding surface for mediastore_channel.
  int get size => _cache.length;

  /// Visible for testing — pending queue length.
  @visibleForTesting
  int get debugPending => _pending.length;

  /// Visible for testing — active in-flight count.
  @visibleForTesting
  int get debugActive => _active;

  /// Visible for testing — inject a fake ProbeCallFn. Callers should
  /// debugClear() afterwards so state doesn't leak between tests.
  @visibleForTesting
  void debugSetProbeCallFn(ProbeCallFn? fn) {
    _probeCall = fn;
  }
}

class _Pending {
  final String contentUri;
  final Completer<MotionPhotoProbe> completer;
  _Pending(this.contentUri, this.completer);
}
