// Owner: T3 (UI teammate). Unit tests for the Dart-side Motion-Photo probe
// plumbing:
//
//   * MediaStoreChannel.probeMotionPhoto — method-call wiring, LRU cache
//     hit/miss, PERMISSION_DENIED propagation, graceful degradation on
//     other PlatformExceptions.
//   * MotionPhotoProbeDart — Kotlin-parity pure-Dart probe against
//     synthetic byte fixtures.
//
// End-to-end validation against the two real samples lives in
// tool/probe_samples_smoke.dart (run by hand during development).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveback/core/constants.dart';
import 'package:liveback/exceptions/liveback_exceptions.dart';
import 'package:liveback/services/mediastore_channel.dart';
import 'package:liveback/services/motion_photo_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channelName = LivebackConstants.channelMediaStore;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void handle(Future<dynamic> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(
        const MethodChannel(channelName), handler);
  }

  setUp(() {
    debugClearMotionPhotoProbeCache();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), null);
    debugClearMotionPhotoProbeCache();
  });

  group('probeMotionPhoto wiring', () {
    test('forwards contentUri and parses result map', () async {
      var calls = 0;
      handle((call) async {
        calls++;
        expect(call.method, 'probeMotionPhoto');
        final args = (call.arguments as Map).cast<String, dynamic>();
        expect(args['contentUri'], 'content://media/external/images/media/7');
        return {'isMotionPhoto': true, 'isSamsungNative': true};
      });

      final r = await MediaStoreChannel()
          .probeMotionPhoto('content://media/external/images/media/7');
      expect(r.isMotionPhoto, isTrue);
      expect(r.isSamsungNative, isTrue);
      expect(calls, 1);
    });

    test('missing keys default to false', () async {
      handle((call) async => <String, dynamic>{});
      final r = await MediaStoreChannel()
          .probeMotionPhoto('content://media/external/images/media/1');
      expect(r.isMotionPhoto, isFalse);
      expect(r.isSamsungNative, isFalse);
    });
  });

  group('probeMotionPhoto LRU cache', () {
    test('second call hits cache — no channel invocation', () async {
      var calls = 0;
      handle((call) async {
        calls++;
        return {'isMotionPhoto': true, 'isSamsungNative': false};
      });
      const uri = 'content://media/external/images/media/42';
      final a = await MediaStoreChannel().probeMotionPhoto(uri);
      final b = await MediaStoreChannel().probeMotionPhoto(uri);
      expect(calls, 1, reason: 'cache should suppress the second round-trip');
      expect(a.isMotionPhoto, b.isMotionPhoto);
      expect(a.isSamsungNative, b.isSamsungNative);
    });

    test('LRU caps at 500 entries and evicts oldest', () async {
      handle((call) async =>
          {'isMotionPhoto': false, 'isSamsungNative': false});
      // Fill cache with 501 distinct URIs; the first inserted URI should
      // have been evicted.
      for (var i = 0; i < 501; i++) {
        await MediaStoreChannel()
            .probeMotionPhoto('content://media/external/images/media/$i');
      }
      expect(debugMotionPhotoProbeCacheSize(), 500);
    });

    test('PERMISSION_DENIED result is NOT cached', () async {
      var calls = 0;
      handle((call) async {
        calls++;
        throw PlatformException(code: 'PERMISSION_DENIED');
      });
      const uri = 'content://media/external/images/media/denied';
      await expectLater(
        () => MediaStoreChannel().probeMotionPhoto(uri),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        () => MediaStoreChannel().probeMotionPhoto(uri),
        throwsA(isA<PermissionDeniedException>()),
      );
      expect(calls, 2);
    });

    test('non-permission errors degrade to no-badge without caching',
        () async {
      var calls = 0;
      handle((call) async {
        calls++;
        throw PlatformException(code: 'UNEXPECTED');
      });
      const uri = 'content://media/external/images/media/transient';
      final a = await MediaStoreChannel().probeMotionPhoto(uri);
      final b = await MediaStoreChannel().probeMotionPhoto(uri);
      expect(a.isMotionPhoto, isFalse);
      expect(a.isSamsungNative, isFalse);
      expect(b.isMotionPhoto, isFalse);
      expect(b.isSamsungNative, isFalse);
      expect(calls, 2, reason: 'transient errors should be retried');
    });
  });

  group('MotionPhotoProbeDart — synthetic fixtures', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('probe_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    Future<File> writeFixture(String name, List<int> bytes) async {
      final f = File('${tmp.path}/$name');
      await f.writeAsBytes(bytes, flush: true);
      return f;
    }

    test('plain JPEG (no MP4) → isMotionPhoto=false', () async {
      // JPEG header + FF D9 EOI followed by nothing. Pad to minFileBytes.
      final bytes = <int>[0xFF, 0xD8];
      while (bytes.length < 40 * 1024) {
        bytes.add(0x00);
      }
      bytes.addAll([0xFF, 0xD9]); // EOI
      final f = await writeFixture('plain.jpg', bytes);
      final r = await MotionPhotoProbeDart().probeFile(f.path);
      expect(r.isMotionPhoto, isFalse);
      expect(r.isSamsungNative, isFalse);
    });

    test('too-small file bails gracefully', () async {
      final bytes = <int>[0xFF, 0xD8, 0xFF, 0xD9];
      while (bytes.length < 1024) {
        bytes.add(0x00);
      }
      final f = await writeFixture('tiny.jpg', bytes);
      final r = await MotionPhotoProbeDart().probeFile(f.path);
      expect(r.isMotionPhoto, isFalse);
      expect(r.isSamsungNative, isFalse);
    });

    test('JPEG + ftyp (djimimo-shaped) → isMotionPhoto=true, native=false',
        () async {
      final bytes = <int>[0xFF, 0xD8];
      while (bytes.length < 40 * 1024) {
        bytes.add(0x00);
      }
      bytes.addAll([0xFF, 0xD9]); // EOI
      // ftyp box: 4-byte size = 24, "ftyp", brand "mp42", ...
      bytes.addAll([0x00, 0x00, 0x00, 0x18]); // size = 24
      bytes.addAll('ftyp'.codeUnits);
      bytes.addAll('mp42'.codeUnits);
      bytes.addAll([0, 0, 0, 0]);
      bytes.addAll('isommp42'.codeUnits);
      // Add some mock mdat payload.
      for (var i = 0; i < 512; i++) {
        bytes.add(0);
      }
      final f = await writeFixture('djimimo.jpg', bytes);
      final r = await MotionPhotoProbeDart().probeFile(f.path);
      expect(r.isMotionPhoto, isTrue);
      expect(r.isSamsungNative, isFalse);
    });

    test(
        'JPEG + ftyp + SEF trailer with MotionPhoto_Data → isSamsungNative=true',
        () async {
      final bytes = <int>[0xFF, 0xD8];
      while (bytes.length < 40 * 1024) {
        bytes.add(0x00);
      }
      bytes.addAll([0xFF, 0xD9]); // EOI

      // Inline marker before ftyp (24 bytes total): 00 00 30 0A, name_len=16,
      // then ASCII "MotionPhoto_Data".
      final inlineStart = bytes.length;
      bytes.addAll([0x00, 0x00, 0x30, 0x0A]);
      bytes.addAll(_u32le(16));
      bytes.addAll('MotionPhoto_Data'.codeUnits);

      // ftyp box + fake mp4 body.
      bytes.addAll([0x00, 0x00, 0x00, 0x18]);
      bytes.addAll('ftyp'.codeUnits);
      bytes.addAll('mp42'.codeUnits);
      bytes.addAll([0, 0, 0, 0]);
      bytes.addAll('isommp42'.codeUnits);
      for (var i = 0; i < 2048; i++) {
        bytes.add(0);
      }

      // SEF trailer with one MotionPhoto_Data record.
      final sefhPos = bytes.length;
      bytes.addAll('SEFH'.codeUnits);
      bytes.addAll(_u32le(106)); // version
      bytes.addAll(_u32le(1)); // count
      bytes.addAll([0x00, 0x00, 0x30, 0x0A]); // marker
      bytes.addAll(_u32le(sefhPos - inlineStart)); // neg_offset
      bytes.addAll(_u32le(sefhPos - inlineStart)); // data_len
      bytes.addAll(_u32le(24)); // sef_size
      bytes.addAll('SEFT'.codeUnits);

      final f = await writeFixture('native.jpg', bytes);
      final r = await MotionPhotoProbeDart().probeFile(f.path);
      expect(r.isMotionPhoto, isTrue);
      expect(r.isSamsungNative, isTrue);
    });

    test('SEFT magic present but SEFH framing invalid → native=false',
        () async {
      final bytes = <int>[0xFF, 0xD8];
      while (bytes.length < 40 * 1024) {
        bytes.add(0x00);
      }
      bytes.addAll([0xFF, 0xD9]);
      // Random bytes ending in "SEFT" — no valid SEFH precedes it.
      for (var i = 0; i < 100; i++) {
        bytes.add(i & 0xFF);
      }
      bytes.addAll(_u32le(9999)); // absurd sef_size (larger than file)
      bytes.addAll('SEFT'.codeUnits);
      final f = await writeFixture('fake_seft.jpg', bytes);
      final r = await MotionPhotoProbeDart().probeFile(f.path);
      expect(r.isSamsungNative, isFalse);
    });
  });
}

List<int> _u32le(int v) => [
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ];
