// Owner: T3 (UI teammate). Unit tests for the gallery's filter predicate.
//
// The filter enum + predicate are private to lib/features/gallery/gallery_page.dart;
// debugGalleryTilePasses is a @visibleForTesting bridge that exposes the
// pure function without leaking the private widget state or private enum.

import 'package:flutter_test/flutter_test.dart';
import 'package:liveback/features/gallery/gallery_page.dart';
import 'package:liveback/services/mediastore_channel.dart';

void main() {
  group('gallery filter predicate', () {
    const motionFix = MotionPhotoProbe(
      isMotionPhoto: true,
      isSamsungNative: false,
    );
    const motionNative = MotionPhotoProbe(
      isMotionPhoto: true,
      isSamsungNative: true,
    );
    const notMotion = MotionPhotoProbe(
      isMotionPhoto: false,
      isSamsungNative: false,
    );

    test('"all" passes every tile including unresolved probes', () {
      expect(debugGalleryTilePasses('all', null), isTrue);
      expect(debugGalleryTilePasses('all', motionFix), isTrue);
      expect(debugGalleryTilePasses('all', motionNative), isTrue);
      expect(debugGalleryTilePasses('all', notMotion), isTrue);
    });

    test('"motionOnly" hides non-Motion-Photo tiles, keeps unresolved', () {
      expect(debugGalleryTilePasses('motionOnly', notMotion), isFalse);
      expect(debugGalleryTilePasses('motionOnly', motionFix), isTrue);
      expect(debugGalleryTilePasses('motionOnly', motionNative), isTrue);
      // Unresolved probes must stay visible to avoid mid-scroll flicker.
      expect(debugGalleryTilePasses('motionOnly', null), isTrue);
    });

    test('"needsFix" hides Samsung-native tiles too', () {
      expect(debugGalleryTilePasses('needsFix', notMotion), isFalse);
      expect(debugGalleryTilePasses('needsFix', motionFix), isTrue);
      expect(debugGalleryTilePasses('needsFix', motionNative), isFalse);
      expect(debugGalleryTilePasses('needsFix', null), isTrue);
    });

    test('unknown filter name throws', () {
      expect(
        () => debugGalleryTilePasses('nope', motionFix),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('gallery default filter', () {
    test('page opens on "仅显示实况图"', () {
      // Constant exposed via @visibleForTesting — changing it means every
      // first-launch gallery session will pre-filter to motion photos.
      expect(debugGalleryDefaultFilterName, 'motionOnly');
    });
  });
}
