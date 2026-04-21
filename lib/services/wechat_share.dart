// Owner: T2 (Android platform teammate). Reference: Doc 1 §A.7 + Doc 3 §5.
// DO NOT edit signatures without an architecture amendment.

/// Outcome of a WeChat share attempt.
///
/// * [direct] — WeChat was installed and the explicit intent launched.
/// * [systemSheet] — we fell back to the ACTION_SEND chooser (WeChat not
///   declared in `<queries>` or explicit intent failed mid-resolve).
/// * [wechatNotInstalled] — the resolver reported no com.tencent.mm.
enum ShareResult { direct, systemSheet, wechatNotInstalled }

class WeChatShare {
  /// Triggers an Android share intent with the given JPEG content URIs.
  /// Returns a discriminated result — callers render a toast/banner
  /// based on [ShareResult].
  Future<ShareResult> shareFiles(List<String> contentUris) {
    throw UnimplementedError('T2 — Kotlin MethodChannel not wired yet');
  }
}
