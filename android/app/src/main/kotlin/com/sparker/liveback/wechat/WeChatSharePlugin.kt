// Owner: T2 (Android platform teammate). Reference: Doc 3 §5.
//
// Registers the com.sparker.liveback/wechat_share MethodChannel. Exposes a
// single method shareFiles(uris: List<String>) that:
//   1. Composes ACTION_SEND (1 URI) or ACTION_SEND_MULTIPLE (>1) with
//      setType("image/jpeg"), EXTRA_STREAM, and FLAG_GRANT_READ_URI_PERMISSION.
//   2. Primary: setPackage("com.tencent.mm"). If resolves, launch directly.
//   3. Fallback: strip setPackage, launch via Intent.createChooser.
//   4. ActivityNotFoundException → map to WECHAT_NOT_INSTALLED.
//
// Returns a map { "method": "direct" | "system_sheet" | "wechat_not_installed",
// "launched": bool }.

package com.sparker.liveback.wechat

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import com.sparker.liveback.util.PluginScope
import com.sparker.liveback.util.respondError
import com.sparker.liveback.util.respondSuccess
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.lang.ref.WeakReference

class WeChatSharePlugin(private val appContext: Context) :
    FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.sparker.liveback/wechat_share"
        private const val WECHAT_PACKAGE = "com.tencent.mm"
    }

    private var channel: MethodChannel? = null
    private val pluginScope = PluginScope()
    private var activityRef: WeakReference<Activity>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        pluginScope.onDetached()
    }

    // ActivityAware — track the current Activity so startActivity has a
    // foreground context.
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityRef = WeakReference(binding.activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityRef = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityRef = WeakReference(binding.activity)
    }

    override fun onDetachedFromActivity() {
        activityRef = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "shareFiles" -> pluginScope.launchIo {
                try {
                    shareFiles(call, result)
                } catch (ce: kotlinx.coroutines.CancellationException) {
                    throw ce
                } catch (t: Throwable) {
                    respondError(result, "LAUNCH_FAILED",
                        t.message ?: t::class.java.simpleName)
                }
            }
            else -> result.notImplemented()
        }
    }

    private suspend fun shareFiles(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val uris = call.argument<List<String>>("uris") ?: call.argument<List<Any?>>("uris")
            ?.mapNotNull { it?.toString() }
        if (uris.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "uris is required and non-empty")
            return
        }
        val text = call.argument<String>("text") ?: ""

        val activity = activityRef?.get()
        if (activity == null) {
            respondError(result, "NO_ACTIVITY", "no foreground activity to host share intent")
            return
        }

        val parsed = try {
            uris.map { Uri.parse(it) }
        } catch (e: Exception) {
            respondError(result, "INVALID_ARGUMENT", "malformed URI: ${e.message}")
            return
        }

        val baseIntent = if (parsed.size == 1) {
            Intent(Intent.ACTION_SEND).apply {
                type = "image/jpeg"
                putExtra(Intent.EXTRA_STREAM, parsed[0])
            }
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = "image/jpeg"
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(parsed))
            }
        }.apply {
            if (text.isNotEmpty()) putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        // All startActivity calls must happen on the UI thread.
        withContext(Dispatchers.Main) {
            // Phase 1 — try explicit com.tencent.mm.
            val direct = Intent(baseIntent).apply { setPackage(WECHAT_PACKAGE) }
            val directResolve = direct.resolveActivity(activity.packageManager)
            if (directResolve != null) {
                try {
                    activity.startActivity(direct)
                    respondSuccess(
                        result,
                        mapOf("method" to "direct", "launched" to true),
                    )
                    return@withContext
                } catch (_: ActivityNotFoundException) {
                    // WeChat vanished between resolve and launch — fall through
                    // to the chooser path below.
                } catch (e: SecurityException) {
                    respondError(result, "PERMISSION_DENIED", e.message)
                    return@withContext
                }
            }

            // Phase 2 — chooser fallback.
            try {
                val chooser = Intent.createChooser(Intent(baseIntent), "分享到")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                val chooserResolve = chooser.resolveActivity(activity.packageManager)
                if (chooserResolve != null) {
                    activity.startActivity(chooser)
                    respondSuccess(
                        result,
                        mapOf("method" to "system_sheet", "launched" to true),
                    )
                } else {
                    respondSuccess(
                        result,
                        mapOf("method" to "wechat_not_installed", "launched" to false),
                    )
                }
            } catch (_: ActivityNotFoundException) {
                respondSuccess(
                    result,
                    mapOf("method" to "wechat_not_installed", "launched" to false),
                )
            }
        }
    }
}
