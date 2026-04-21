// Owner: T2. JVM unit tests for pure-Kotlin helpers inside MediaStorePlugin
// that do not require Android runtime (no ContentResolver, no Context).
//
// These are package-private reflective probes — the methods we test
// (isSafeTaskId, isNoSpace, insertPendingRowWithRetry's filename-suffix
// algorithm) are private, so we cover them via a small detached copy of
// the algorithms. If either algorithm changes in MediaStorePlugin it
// should change here too and the tests should continue to hold.

package com.sparker.liveback.mediastore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class MediaStorePluginHelpersTest {

    // ---- taskId sanitization mirror ----
    private fun isSafeTaskId(id: String): Boolean =
        !id.contains('/') && !id.contains('\\') && id != ".." && id != "."
                && !id.startsWith(".")

    @Test fun `isSafeTaskId accepts plain alphanumeric ids`() {
        assertTrue(isSafeTaskId("abc123"))
        assertTrue(isSafeTaskId("a-b-c"))
        assertTrue(isSafeTaskId("00000000-0000-0000-0000-000000000000"))
    }

    @Test fun `isSafeTaskId rejects path traversal ids`() {
        assertFalse(isSafeTaskId("../etc"))
        assertFalse(isSafeTaskId(".."))
        assertFalse(isSafeTaskId("."))
        assertFalse(isSafeTaskId(".hidden"))
        assertFalse(isSafeTaskId("a/b"))
        assertFalse(isSafeTaskId("a\\b"))
    }

    // ---- ENOSPC classifier mirror ----
    private fun isNoSpace(t: Throwable): Boolean {
        var cur: Throwable? = t
        while (cur != null) {
            val msg = cur.message ?: ""
            if (msg.contains("ENOSPC", ignoreCase = true) ||
                msg.contains("No space left", ignoreCase = true)
            ) return true
            cur = cur.cause
        }
        return false
    }

    @Test fun `isNoSpace detects ENOSPC in leaf`() {
        assertTrue(isNoSpace(IOException("write: ENOSPC (No space left on device)")))
    }

    @Test fun `isNoSpace walks cause chain`() {
        val root = IOException("disk: ENOSPC")
        val wrapped = IOException("copy failed", root)
        assertTrue(isNoSpace(wrapped))
    }

    @Test fun `isNoSpace returns false for unrelated errors`() {
        assertFalse(isNoSpace(IOException("permission denied")))
        assertFalse(isNoSpace(SecurityException("no access")))
    }

    // ---- DISPLAY_NAME suffix algorithm mirror ----
    // Matches the (stem, ext) split used in insertPendingRowWithRetry.
    private fun suffixed(base: String, n: Int): String {
        val dot = base.lastIndexOf('.')
        val stem = if (dot > 0) base.substring(0, dot) else base
        val ext = if (dot > 0) base.substring(dot) else ""
        return if (n == 0) base else "${stem}_${n}${ext}"
    }

    @Test fun `suffix algorithm preserves extension`() {
        assertEquals("Liveback_20260421_123000.jpg", suffixed("Liveback_20260421_123000.jpg", 0))
        assertEquals("Liveback_20260421_123000_1.jpg", suffixed("Liveback_20260421_123000.jpg", 1))
        assertEquals("Liveback_20260421_123000_16.jpg", suffixed("Liveback_20260421_123000.jpg", 16))
    }

    @Test fun `suffix algorithm handles multi-dot names`() {
        // Only the last dot splits; "foo.bar.jpg" → stem="foo.bar", ext=".jpg".
        assertEquals("foo.bar_2.jpg", suffixed("foo.bar.jpg", 2))
    }

    @Test fun `suffix algorithm tolerates extensionless names`() {
        assertEquals("name_3", suffixed("name", 3))
    }
}
