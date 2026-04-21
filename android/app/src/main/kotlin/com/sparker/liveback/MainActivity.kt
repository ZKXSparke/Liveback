// Owner: T2 (Android platform teammate). Reference: Doc 3 §1.
//
// Hosts the Flutter engine and registers T2's two MethodChannels
// (com.sparker.liveback/mediastore and com.sparker.liveback/wechat_share).
//
// Base class is FlutterFragmentActivity (not FlutterActivity) so future UI
// work can host AndroidX DialogFragments / nav components; this was the
// handoff decision recorded in the teammate brief.

package com.sparker.liveback

import com.sparker.liveback.mediastore.MediaStorePlugin
import com.sparker.liveback.wechat.WeChatSharePlugin
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Manually register T2-owned plugins. They are NOT Pub-discoverable
        // plugins (live in :app, not :plugins), so GeneratedPluginRegistrant
        // does not pick them up.
        flutterEngine.plugins.add(MediaStorePlugin(applicationContext))
        flutterEngine.plugins.add(WeChatSharePlugin(applicationContext))
    }
}
