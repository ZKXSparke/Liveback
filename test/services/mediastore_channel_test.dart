// Owner: T2. Exercises MediaStoreChannel's Dart wrapper against a mock
// MethodChannel. We don't test the Kotlin side here (that's Gradle-side
// JUnit). We verify:
//   1. Method-call argument wiring
//   2. PlatformException → LivebackException mapping
//   3. GalleryItem JSON decoding (nullable dateTakenMs, nullable w/h)
//   4. getThumbnail THUMB_LOAD_FAILED → null
//   5. releaseSandbox swallows non-permission errors
//
// Uses the built-in MethodChannel mock binding exposed by
// TestDefaultBinaryMessengerBinding — no mocktail mock of MethodChannel
// needed for this simple boundary.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveback/core/constants.dart';
import 'package:liveback/exceptions/liveback_exceptions.dart';
import 'package:liveback/services/mediastore_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channelName = LivebackConstants.channelMediaStore;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void handle(Future<dynamic> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), handler);
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), null);
  });

  group('queryImages', () {
    test('omits bucketId arg when null (preserves Doc 1 §A.6 surface)', () async {
      handle((call) async {
        expect(call.method, 'queryImages');
        final args = (call.arguments as Map).cast<String, dynamic>();
        expect(args.containsKey('bucketId'), isFalse);
        return const <Map<String, dynamic>>[];
      });
      await MediaStoreChannel().queryImages();
    });

    test('forwards bucketId when supplied', () async {
      handle((call) async {
        expect(call.method, 'queryImages');
        final args = (call.arguments as Map).cast<String, dynamic>();
        expect(args['bucketId'], 123456789);
        return const <Map<String, dynamic>>[];
      });
      await MediaStoreChannel().queryImages(bucketId: 123456789);
    });

    test('parses rows with full + partial projection', () async {
      handle((call) async {
        expect(call.method, 'queryImages');
        expect(call.arguments, {'limit': 500, 'offset': 0});
        return <Map<String, dynamic>>[
          {
            'id': 1,
            'uri': 'content://media/external/images/media/1',
            'displayName': 'IMG_1.jpg',
            'size': 1024,
            'dateTakenMs': 1700000000000,
            'dateAddedMs': 1700000001000,
            'width': 4000,
            'height': 3000,
            'mimeType': 'image/jpeg',
          },
          {
            'id': 2,
            'uri': 'content://media/external/images/media/2',
            'displayName': 'IMG_2.jpg',
            'size': 2048,
            'dateTakenMs': null, // DATE_TAKEN NULL row
            'dateAddedMs': 1700000002000,
            'width': null,
            'height': null,
            'mimeType': 'image/jpeg',
          },
        ];
      });

      final items = await MediaStoreChannel().queryImages();
      expect(items, hasLength(2));
      expect(items[0].dateTakenMs, 1700000000000);
      expect(items[0].width, 4000);
      expect(items[1].dateTakenMs, isNull);
      expect(items[1].width, isNull);
    });

    test('PERMISSION_DENIED maps to PermissionDeniedException', () async {
      handle((call) async {
        throw PlatformException(code: 'PERMISSION_DENIED');
      });
      expect(
        () => MediaStoreChannel().queryImages(),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('QUERY_FAILED maps to SefWriteFailedException', () async {
      handle((call) async {
        throw PlatformException(code: 'QUERY_FAILED');
      });
      expect(
        () => MediaStoreChannel().queryImages(),
        throwsA(isA<SefWriteFailedException>()),
      );
    });
  });

  group('queryAlbums', () {
    test('parses bucket rows', () async {
      handle((call) async {
        expect(call.method, 'queryAlbums');
        return <Map<String, dynamic>>[
          {
            'bucketId': 111,
            'displayName': 'Camera',
            'coverContentUri': 'content://media/external/images/media/1001',
            'count': 42,
          },
          {
            'bucketId': 222,
            'displayName': 'Screenshots',
            'coverContentUri': 'content://media/external/images/media/1002',
            'count': 9,
          },
        ];
      });
      final albums = await MediaStoreChannel().queryAlbums();
      expect(albums, hasLength(2));
      expect(albums[0].displayName, 'Camera');
      expect(albums[0].bucketId, 111);
      expect(albums[0].count, 42);
      expect(albums[1].bucketId, 222);
    });

    test('null displayName falls back to "(未命名)"', () async {
      handle((call) async => <Map<String, dynamic>>[
            {
              'bucketId': 333,
              'displayName': null,
              'coverContentUri': 'content://media/external/images/media/9',
              'count': 1,
            }
          ]);
      final albums = await MediaStoreChannel().queryAlbums();
      expect(albums, hasLength(1));
      expect(albums[0].displayName, '(未命名)');
    });

    test('PERMISSION_DENIED maps to PermissionDeniedException', () async {
      handle((call) async {
        throw PlatformException(code: 'PERMISSION_DENIED');
      });
      expect(
        () => MediaStoreChannel().queryAlbums(),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('getThumbnail', () {
    test('THUMB_LOAD_FAILED returns null (graceful)', () async {
      handle((call) async {
        throw PlatformException(code: 'THUMB_LOAD_FAILED');
      });
      final bytes = await MediaStoreChannel()
          .getThumbnail('content://media/external/images/media/99');
      expect(bytes, isNull);
    });
  });

  group('publishOutputToMediaStore', () {
    test('returns final URI on success', () async {
      handle((call) async {
        expect(call.method, 'publishOutputToMediaStore');
        final args = (call.arguments as Map).cast<String, dynamic>();
        expect(args['sandboxOutPath'], '/tmp/out-x.jpg');
        expect(args['relativePath'], LivebackConstants.publicOutputFolder);
        return 'content://media/external/images/media/42';
      });
      final uri = await MediaStoreChannel().publishOutputToMediaStore(
        sandboxOutPath: '/tmp/out-x.jpg',
        displayName: 'Liveback_20260421_123456.jpg',
        dateTakenEpochMs: 1700000000000,
        originalMtimeEpochMs: 1700000000000,
      );
      expect(uri, 'content://media/external/images/media/42');
    });

    test('NO_SPACE maps to WriteCorruptException', () async {
      handle((call) async {
        throw PlatformException(code: 'NO_SPACE');
      });
      expect(
        () => MediaStoreChannel().publishOutputToMediaStore(
          sandboxOutPath: '/tmp/out-x.jpg',
          displayName: 'Liveback_x.jpg',
          dateTakenEpochMs: 1700000000000,
          originalMtimeEpochMs: 1700000000000,
        ),
        throwsA(isA<WriteCorruptException>()),
      );
    });

    test('INVALID_DATE_TAKEN maps to WriteCorruptException', () async {
      handle((call) async {
        throw PlatformException(code: 'INVALID_DATE_TAKEN');
      });
      expect(
        () => MediaStoreChannel().publishOutputToMediaStore(
          sandboxOutPath: '/tmp/out-x.jpg',
          displayName: 'Liveback_x.jpg',
          dateTakenEpochMs: 0,
          originalMtimeEpochMs: 0,
        ),
        throwsA(isA<WriteCorruptException>()),
      );
    });

    test('unknown PlatformException code falls back to SefWriteFailedException', () async {
      handle((call) async {
        throw PlatformException(code: 'SOME_NEW_ERROR');
      });
      expect(
        () => MediaStoreChannel().publishOutputToMediaStore(
          sandboxOutPath: '/tmp/out-x.jpg',
          displayName: 'Liveback_x.jpg',
          dateTakenEpochMs: 1700000000000,
          originalMtimeEpochMs: 1700000000000,
        ),
        throwsA(isA<SefWriteFailedException>()),
      );
    });
  });

  group('releaseSandbox', () {
    test('swallows COPY_FAILED / DELETE_FAILED errors (best-effort cleanup)', () async {
      handle((call) async {
        throw PlatformException(code: 'DELETE_FAILED');
      });
      // Should NOT throw.
      await MediaStoreChannel().releaseSandbox(taskId: 'abc');
    });

    test('propagates PERMISSION_DENIED', () async {
      handle((call) async {
        throw PlatformException(code: 'PERMISSION_DENIED');
      });
      expect(
        () => MediaStoreChannel().releaseSandbox(taskId: 'abc'),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('copyInputToSandbox', () {
    test('returns path from plugin result map', () async {
      handle((call) async {
        expect(call.method, 'copyInputToSandbox');
        return {'path': '/data/cache/liveback-io/in-abc.jpg', 'size': 1024};
      });
      final path = await MediaStoreChannel().copyInputToSandbox(
        contentUri: 'content://media/external/images/media/1',
        taskId: 'abc',
      );
      expect(path, '/data/cache/liveback-io/in-abc.jpg');
    });
  });
}
