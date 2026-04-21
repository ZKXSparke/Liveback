// Owner: T2. WeChat share wrapper tests — verify discriminated ShareResult
// parsing and safe fallback on PlatformException.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liveback/core/constants.dart';
import 'package:liveback/services/wechat_share.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channelName = LivebackConstants.channelWeChatShare;
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void handle(Future<dynamic> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), handler);
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel(channelName), null);
  });

  test('empty uri list short-circuits to wechatNotInstalled', () async {
    final r = await WeChatShare().shareFiles(const []);
    expect(r, ShareResult.wechatNotInstalled);
  });

  test('"direct" method maps to ShareResult.direct', () async {
    handle((call) async {
      expect(call.method, 'shareFiles');
      // Note: after codec encoding the List element type is erased to
      // `List<Object?>` — we assert only the length + content here.
      final args = (call.arguments as Map).cast<String, dynamic>();
      final uris = (args['uris'] as List).cast<String>();
      expect(uris, ['content://x/1']);
      return {'method': 'direct', 'launched': true};
    });
    final r = await WeChatShare().shareFiles(const ['content://x/1']);
    expect(r, ShareResult.direct);
  });

  test('"system_sheet" method maps to ShareResult.systemSheet', () async {
    handle((call) async => {'method': 'system_sheet', 'launched': true});
    final r = await WeChatShare().shareFiles(const ['content://x/1']);
    expect(r, ShareResult.systemSheet);
  });

  test('"wechat_not_installed" maps to ShareResult.wechatNotInstalled', () async {
    handle((call) async => {'method': 'wechat_not_installed', 'launched': false});
    final r = await WeChatShare().shareFiles(const ['content://x/1']);
    expect(r, ShareResult.wechatNotInstalled);
  });

  test('LAUNCH_FAILED PlatformException collapses to wechatNotInstalled', () async {
    handle((call) async {
      throw PlatformException(code: 'LAUNCH_FAILED');
    });
    final r = await WeChatShare().shareFiles(const ['content://x/1']);
    expect(r, ShareResult.wechatNotInstalled);
  });

  test('NO_ACTIVITY PlatformException collapses to wechatNotInstalled', () async {
    handle((call) async {
      throw PlatformException(code: 'NO_ACTIVITY');
    });
    final r = await WeChatShare().shareFiles(const ['content://x/1']);
    expect(r, ShareResult.wechatNotInstalled);
  });
}
