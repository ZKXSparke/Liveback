// Owner: T2 (Android platform teammate). Reference: Doc 3 §2.6, §3.
//
// Process-wide registry for ParcelFileDescriptor handles that cross the
// MethodChannel boundary. Currently used internally by the publish facade
// (createOutputUri → finalize) — Dart-facing Plan A does not expose handles,
// but the Test Mode surface (§9) and the lower-level createOutputUri /
// openOutputDescriptor methods still route through this registry so their
// pfds survive between calls.
//
// Thread-safety: all methods synchronized; calls are rare (a handful per task).

package com.sparker.liveback.mediastore

import android.os.ParcelFileDescriptor
import java.util.UUID

object FdRegistry {
    private val entries = HashMap<String, ParcelFileDescriptor>()

    /** Registers [pfd] and returns an opaque handle. */
    @Synchronized
    fun register(pfd: ParcelFileDescriptor): String {
        val handle = UUID.randomUUID().toString()
        entries[handle] = pfd
        return handle
    }

    /** Returns the pfd or null if the handle is unknown. */
    @Synchronized
    fun get(handle: String): ParcelFileDescriptor? = entries[handle]

    /** Removes [handle] and returns the pfd if present. Caller is
     *  responsible for closing. */
    @Synchronized
    fun remove(handle: String): ParcelFileDescriptor? = entries.remove(handle)

    /** Closes and removes [handle]. Idempotent — unknown handles are silently
     *  ignored per Doc 3 §2.4 closeDescriptor contract. */
    @Synchronized
    fun close(handle: String) {
        val pfd = entries.remove(handle)
        try {
            pfd?.close()
        } catch (_: Throwable) {
            // swallow — idempotent
        }
    }
}
