// Owner: T3 (UI teammate). Unit tests for MotionPhotoProbeCache —
// concurrency bound, in-flight dedup, synthetic pre-filter.
//
// These exercise the cache in isolation (via debugSetProbeCallFn) so we
// can assert scheduling behaviour without needing a real MethodChannel.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveback/exceptions/liveback_exceptions.dart';
import 'package:liveback/services/mediastore_channel.dart';
import 'package:liveback/services/motion_photo_probe_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MotionPhotoProbeCache.instance.clear();
    MotionPhotoProbeCache.instance.debugSetProbeCallFn(null);
  });

  tearDown(() {
    MotionPhotoProbeCache.instance.clear();
    MotionPhotoProbeCache.instance.debugSetProbeCallFn(null);
  });

  group('concurrency bound', () {
    test('caps parallelism at 8 (rest queue)', () async {
      final cache = MotionPhotoProbeCache.instance;
      var peakActive = 0;
      var active = 0;
      final completers = <Completer<MotionPhotoProbe>>[];
      cache.debugSetProbeCallFn((uri) {
        active++;
        if (active > peakActive) peakActive = active;
        final c = Completer<MotionPhotoProbe>();
        completers.add(c);
        return c.future.whenComplete(() => active--);
      });

      // Enqueue 20 URIs before completing any. The ProbeCallFn passed to
      // fetch() is only used to wire the singleton on first use (via
      // _ensureCall) — since we already set it via debugSetProbeCallFn,
      // this lambda is never invoked. Pump the microtask queue so _pump
      // fires.
      Future<MotionPhotoProbe> unused(String _) async =>
          throw StateError('unused');
      final futures = <Future<MotionPhotoProbe>>[];
      for (var i = 0; i < 20; i++) {
        futures.add(cache.fetch('uri-$i', unused));
      }
      await Future<void>.delayed(Duration.zero);
      expect(peakActive, 8, reason: 'cap is 8 parallel probes');
      expect(cache.debugPending, 12,
          reason: '20 enqueued − 8 active = 12 pending');

      // Drain them all. Snapshot the list because completing a Future
      // triggers _pump which can append new Completers to the same list.
      var drained = 0;
      while (drained < 20) {
        final snapshot = List.of(completers);
        for (var i = drained; i < snapshot.length; i++) {
          snapshot[i].complete(const MotionPhotoProbe(
            isMotionPhoto: false,
            isSamsungNative: false,
          ));
          drained++;
        }
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(futures);
      expect(cache.debugActive, 0);
      expect(cache.debugPending, 0);
    });
  });

  group('in-flight dedup', () {
    test('two fetches for the same URI share one channel call', () async {
      final cache = MotionPhotoProbeCache.instance;
      var calls = 0;
      late Completer<MotionPhotoProbe> block;
      cache.debugSetProbeCallFn((uri) {
        calls++;
        block = Completer<MotionPhotoProbe>();
        return block.future;
      });

      final a = cache.fetch('same-uri', (_) async => throw StateError('unused'));
      final b = cache.fetch('same-uri', (_) async => throw StateError('unused'));

      await Future<void>.delayed(Duration.zero);
      expect(calls, 1, reason: 'second fetch should reuse the in-flight future');

      block.complete(const MotionPhotoProbe(
        isMotionPhoto: true,
        isSamsungNative: false,
      ));
      final ra = await a;
      final rb = await b;
      expect(ra.isMotionPhoto, isTrue);
      expect(rb.isMotionPhoto, isTrue);
    });
  });

  group('PERMISSION_DENIED', () {
    test('not memoised, surfaces on every call', () async {
      final cache = MotionPhotoProbeCache.instance;
      var calls = 0;
      cache.debugSetProbeCallFn((uri) async {
        calls++;
        throw PermissionDeniedException();
      });

      await expectLater(
        cache.fetch('locked', (_) async => throw StateError('unused')),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        cache.fetch('locked', (_) async => throw StateError('unused')),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(calls, 2);
      expect(cache.size, 0, reason: 'never memoise permission errors');
    });
  });

  group('transient failure degradation', () {
    test('returns {false,false}, does not memoise, retries next time',
        () async {
      final cache = MotionPhotoProbeCache.instance;
      var calls = 0;
      cache.debugSetProbeCallFn((uri) async {
        calls++;
        throw Exception('transient io blip');
      });

      final a = await cache.fetch('flaky', (_) async => throw StateError('unused'));
      final b = await cache.fetch('flaky', (_) async => throw StateError('unused'));
      expect(a.isMotionPhoto, isFalse);
      expect(a.isSamsungNative, isFalse);
      expect(b.isMotionPhoto, isFalse);
      expect(calls, 2, reason: 'retry on every call until something sticks');
      expect(cache.size, 0);
    });
  });

  group('synthetic seeding (file-size pre-filter path)', () {
    test('putSynthetic short-circuits later fetches', () async {
      final cache = MotionPhotoProbeCache.instance;
      var calls = 0;
      cache.debugSetProbeCallFn((uri) async {
        calls++;
        return const MotionPhotoProbe(
          isMotionPhoto: true,
          isSamsungNative: true,
        );
      });

      cache.putSynthetic(
        'small-file.jpg',
        const MotionPhotoProbe(
          isMotionPhoto: false,
          isSamsungNative: false,
        ),
      );
      final r = await cache.fetch('small-file.jpg',
          (_) async => throw StateError('unused'));
      expect(r.isMotionPhoto, isFalse);
      expect(calls, 0, reason: 'synthetic entry must suppress channel call');
    });

    test('putSynthetic does not overwrite an existing real result',
        () async {
      final cache = MotionPhotoProbeCache.instance;
      cache.debugSetProbeCallFn((uri) async => const MotionPhotoProbe(
            isMotionPhoto: true,
            isSamsungNative: false,
          ));
      final real = await cache.fetch(
          'real.jpg', (_) async => throw StateError('unused'));
      expect(real.isMotionPhoto, isTrue);
      // Attempted synthetic overwrite should be a no-op.
      cache.putSynthetic(
        'real.jpg',
        const MotionPhotoProbe(
          isMotionPhoto: false,
          isSamsungNative: false,
        ),
      );
      final peeked = cache.peek('real.jpg');
      expect(peeked?.isMotionPhoto, isTrue);
    });
  });

  group('MediaStoreChannel.probeMotionPhoto size prefilter', () {
    test('bytes below floor skip the channel entirely', () async {
      // Intentionally NO MethodChannel mock — if the pre-filter works,
      // we never dispatch. The cache is seeded synthetically so the
      // result must come back without a channel call throwing MissingPluginException.
      final channel = MediaStoreChannel();
      final r = await channel.probeMotionPhoto(
        'content://media/external/images/media/tiny',
        fileSizeBytes: kProbeSizeFloorBytes - 1,
      );
      expect(r.isMotionPhoto, isFalse);
      expect(r.isSamsungNative, isFalse);
      final seeded = MotionPhotoProbeCache.instance
          .peek('content://media/external/images/media/tiny');
      expect(seeded, isNotNull);
    });

    test('bytes at floor still dispatch a channel call', () async {
      final channel = MediaStoreChannel();
      MotionPhotoProbeCache.instance.debugSetProbeCallFn(
        (uri) async => const MotionPhotoProbe(
          isMotionPhoto: true,
          isSamsungNative: false,
        ),
      );
      final r = await channel.probeMotionPhoto(
        'content://media/external/images/media/biggy',
        fileSizeBytes: kProbeSizeFloorBytes,
      );
      expect(r.isMotionPhoto, isTrue);
    });

    test('no fileSizeBytes supplied → always dispatch (back-compat)',
        () async {
      MotionPhotoProbeCache.instance.debugSetProbeCallFn(
        (uri) async => const MotionPhotoProbe(
          isMotionPhoto: true,
          isSamsungNative: true,
        ),
      );
      final r = await MediaStoreChannel()
          .probeMotionPhoto('content://media/external/images/media/default');
      expect(r.isSamsungNative, isTrue);
    });
  });
}
