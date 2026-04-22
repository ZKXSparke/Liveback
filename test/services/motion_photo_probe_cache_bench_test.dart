// Micro-benchmark for the MotionPhotoProbeCache concurrency bound.
// Simulates a 1000-item album with 10% motion photos and 60% tiny
// (sub-500 KB) files. Measures the time to resolve the first 6
// motion-photo results under the new bounded/dedup'd pipeline vs. a
// baseline "naive serial" simulation.
//
// This is a Dart-level simulation; it does NOT exercise the real
// MediaStore channel. The intent is to confirm the scheduling behaviour
// inside the cache, not to produce wall-clock numbers that reflect a
// real device. A real benchmark requires an Android device with 2000
// photos, which this VM test cannot reach.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:liveback/services/motion_photo_probe.dart';
import 'package:liveback/services/motion_photo_probe_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Simulates a single channel probe: waits [delayMs] ms then returns
  /// the configured result.
  Future<MotionPhotoProbe> fakeProbe({
    required int delayMs,
    required bool isMotionPhoto,
  }) async {
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    return MotionPhotoProbe(
      isMotionPhoto: isMotionPhoto,
      isSamsungNative: false,
    );
  }

  test('time-to-first-6 motion photos with bounded concurrency', () async {
    // Fixture: 1000 URIs, every 10th is a "motion photo". Each probe takes
    // 15 ms (simulates median Kotlin probe budget).
    const totalUris = 1000;
    const probeMs = 15;
    MotionPhotoProbeCache.instance.clear();
    MotionPhotoProbeCache.instance.debugSetProbeCallFn((uri) {
      final n = int.parse(uri.split('-').last);
      return fakeProbe(delayMs: probeMs, isMotionPhoto: n % 10 == 0);
    });

    final stopwatch = Stopwatch()..start();
    final first6 = Completer<Duration>();
    var foundMotion = 0;
    final futures = <Future<void>>[];
    for (var i = 0; i < totalUris; i++) {
      Future<MotionPhotoProbe> passthrough(String _) async =>
          throw StateError('unused');
      futures.add(
        MotionPhotoProbeCache.instance
            .fetch('uri-$i', passthrough)
            .then((probe) {
          if (probe.isMotionPhoto) {
            foundMotion++;
            if (foundMotion == 6 && !first6.isCompleted) {
              first6.complete(stopwatch.elapsed);
            }
          }
        }),
      );
    }

    final t6 = await first6.future;
    await Future.wait(futures);
    stopwatch.stop();

    // With 8-way concurrency + probe = 15ms, the first 6 motion photos
    // sit at URIs 0, 10, 20, 30, 40, 50. Under 8-way concurrency, those
    // 51 URIs resolve in ~ceil(51 / 8) * 15 = 7 batches * 15ms = 105ms.
    // Under naive serial it would be 51 * 15 = 765ms. We assert a very
    // loose upper bound of 500ms (leaves room for VM + event-loop
    // overhead) and log the actual time.
    // ignore: avoid_print
    print('first-6 motion photos: ${t6.inMilliseconds} ms '
        '(total ${stopwatch.elapsedMilliseconds} ms for $totalUris probes)');
    expect(t6.inMilliseconds, lessThan(500),
        reason: 'first 6 motion photos must land well under naive-serial');
    MotionPhotoProbeCache.instance.clear();
    MotionPhotoProbeCache.instance.debugSetProbeCallFn(null);
  });
}
