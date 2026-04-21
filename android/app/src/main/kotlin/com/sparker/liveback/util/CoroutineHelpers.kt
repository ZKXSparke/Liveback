// Owner: T2 (Android platform teammate). Reference: Doc 3 §2 threading contract.
//
// Shared IO scope for plugin handlers. Each plugin owns its own instance and
// cancels it in onDetachedFromEngine (Doc 3 §2). SupervisorJob ensures one
// failing handler does not tear the whole scope down — that would otherwise
// cause the next handler to throw CancellationException spuriously.

package com.sparker.liveback.util

import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** IO scope owned by a plugin. Lifecycle: create in constructor, cancel in
 *  [onDetached]. SupervisorJob isolates per-call failures. */
class PluginScope {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** Launch [block] on IO. Result dispatches happen inside the block
     *  via [respondOnMain] so the main-thread contract for
     *  MethodChannel.Result is honoured. */
    fun launchIo(block: suspend CoroutineScope.() -> Unit) {
        scope.launch(block = block)
    }

    fun onDetached() {
        scope.cancel()
    }
}

/** Invokes [result.success] on the main thread.
 *  MethodChannel.Result contract requires all callbacks to fire on the
 *  platform thread. */
suspend fun respondSuccess(result: MethodChannel.Result, value: Any?) {
    withContext(Dispatchers.Main) { result.success(value) }
}

/** Invokes [result.error] on the main thread. */
suspend fun respondError(
    result: MethodChannel.Result,
    code: String,
    message: String?,
    details: Any? = null,
) {
    withContext(Dispatchers.Main) { result.error(code, message, details) }
}
