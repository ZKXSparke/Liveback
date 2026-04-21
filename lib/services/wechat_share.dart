// Owner: T2 (Android platform teammate). Reference: Doc 1 §A.7 + Doc 3 §5.
// DO NOT edit signatures without an architecture amendment.

import 'package:flutter/services.dart';

import '../core/constants.dart';

/// Outcome of a WeChat share attempt.
///
/// * [direct] — WeChat was installed and the explicit intent launched.
/// * [systemSheet] — we fell back to the ACTION_SEND chooser (WeChat not
///   declared in `<queries>` or explicit intent failed mid-resolve).
/// * [wechatNotInstalled] — the resolver reported no com.tencent.mm.
enum ShareResult { direct, systemSheet, wechatNotInstalled }

class WeChatShare {
  WeChatShare({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(LivebackConstants.channelWeChatShare);

  final MethodChannel _channel;

  /// Triggers an Android share intent with the given JPEG content URIs.
  /// Returns a discriminated result — callers render a toast/banner
  /// based on [ShareResult].
  ///
  /// [contentUris] MUST be finalized (`IS_PENDING=0`) — pending rows throw
  /// FileNotFoundException inside WeChat's content resolver reader per
  /// Doc 3 §5.
  Future<ShareResult> shareFiles(List<String> contentUris) async {
    if (contentUris.isEmpty) return ShareResult.wechatNotInstalled;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'shareFiles',
        {'uris': contentUris},
      );
      final method = res?['method'] as String?;
      switch (method) {
        case 'direct':
          return ShareResult.direct;
        case 'system_sheet':
          return ShareResult.systemSheet;
        case 'wechat_not_installed':
        default:
          return ShareResult.wechatNotInstalled;
      }
    } on PlatformException catch (e) {
      // WECHAT_NOT_INSTALLED / ACTIVITY_NOT_FOUND / LAUNCH_FAILED all
      // collapse to wechatNotInstalled at the UI (Doc 3 §5 error table).
      if (e.code == 'NO_ACTIVITY' || e.code == 'LAUNCH_FAILED') {
        return ShareResult.wechatNotInstalled;
      }
      return ShareResult.wechatNotInstalled;
    }
  }
}
