// Owner: T2 (Android platform teammate). Reference: Doc 3 §2 / §3.
//
// Registers the com.sparker.liveback/mediastore MethodChannel. Exposes:
//  • Doc 3 §2.1–§2.9 low-level MediaStore operations (queryImages,
//    getThumbnail, openInputDescriptor, closeDescriptor, createOutputUri,
//    openOutputDescriptor, finalizePendingOutput, deletePendingOutput,
//    updateMetadata). These stay reachable for Test Mode and diagnostics.
//  • Doc 3 §3 sandbox plumbing (copyInputToSandbox, reserveOutputSandbox,
//    copySandboxToOutput, deleteSandboxFiles, sweepSandbox).
//  • The `publishOutputToMediaStore` facade that chains createOutputUri →
//    copy → finalizePendingOutput with rollback on any internal failure
//    (Doc 3 §3 call sequence — "On any internal failure after createOutputUri
//    succeeded, Kotlin MUST contentResolver.delete(uri) to roll back").

package com.sparker.liveback.mediastore

import android.annotation.SuppressLint
import android.content.ContentResolver
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.provider.MediaStore
import android.util.Size
import com.sparker.liveback.util.PluginScope
import com.sparker.liveback.util.respondError
import com.sparker.liveback.util.respondSuccess
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.ensureActive
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

class MediaStorePlugin(private val appContext: Context) :
    FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.sparker.liveback/mediastore"

        // Sandbox subdir (mirrors LivebackConstants.sandboxSubdir — hardcoded
        // here because Kotlin cannot import Dart. Any change MUST be kept in
        // sync with `lib/core/constants.dart`).
        private const val SANDBOX_SUBDIR = "liveback-io"

        // DISPLAY_NAME collision retry cap (Doc 3 §2.5).
        private const val DISPLAY_NAME_RETRY_MAX = 16

        // Year-2000 sanity threshold for DATE_TAKEN validation (Doc 3 §2.5).
        private const val MIN_DATE_TAKEN_MS = 946_684_800_000L

        // sweepSandbox age threshold.
        private const val SWEEP_MAX_AGE_MS = 60L * 60L * 1000L  // 1 hour

        // Input copy buffer size (Doc 3 §3).
        private const val COPY_BUFFER_BYTES = 64 * 1024
    }

    private var channel: MethodChannel? = null
    private val pluginScope = PluginScope()
    private val contentResolver: ContentResolver
        get() = appContext.contentResolver

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

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // Every dispatch hops to IO. result.success / result.error are driven
        // back through respondSuccess / respondError (which re-enter Main).
        pluginScope.launchIo {
            try {
                when (call.method) {
                    "queryImages" -> queryImages(call, result)
                    "getThumbnail" -> getThumbnail(call, result)
                    "openInputDescriptor" -> openInputDescriptor(call, result)
                    "closeDescriptor" -> closeDescriptor(call, result)
                    "createOutputUri" -> createOutputUri(call, result)
                    "openOutputDescriptor" -> openOutputDescriptor(call, result)
                    "finalizePendingOutput" -> finalizePendingOutput(call, result)
                    "deletePendingOutput" -> deletePendingOutput(call, result)
                    "updateMetadata" -> updateMetadata(call, result)

                    "copyInputToSandbox" -> copyInputToSandbox(call, result)
                    "reserveOutputSandbox" -> reserveOutputSandbox(call, result)
                    "copySandboxToOutput" -> copySandboxToOutput(call, result)
                    "deleteSandboxFiles" -> deleteSandboxFiles(call, result)
                    "sweepSandbox" -> sweepSandbox(result)

                    "publishOutputToMediaStore" -> publishOutputToMediaStore(call, result)

                    else -> respondError(result, "METHOD_NOT_IMPLEMENTED",
                        "Unknown method: ${call.method}")
                }
            } catch (ce: kotlinx.coroutines.CancellationException) {
                // Scope cancelled (engine detach). Do not try to call result —
                // the engine is tearing down.
                throw ce
            } catch (t: Throwable) {
                respondError(result, "UNEXPECTED",
                    t.message ?: t::class.java.simpleName)
            }
        }
    }

    // ---------------------------------------------------------------------
    // §2.1 queryImages
    // ---------------------------------------------------------------------

    @SuppressLint("InlinedApi")
    private suspend fun queryImages(call: MethodCall, result: MethodChannel.Result) {
        val limit = (call.argument<Int>("limit") ?: 500).coerceAtLeast(1)
        val offset = (call.argument<Int>("offset") ?: 0).coerceAtLeast(0)
        val mimeFilter = call.argument<String>("mimeTypeFilter") ?: "image/jpeg"
        // sortBy / sortOrder accepted for forward-compat; we always sort by
        // DATE_TAKEN DESC per Doc 3 §2.1 performance note.
        val sortBy = call.argument<String>("sortBy") ?: "date_taken"

        val projection = arrayOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.SIZE,
            MediaStore.Images.Media.DATE_TAKEN,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.WIDTH,
            MediaStore.Images.Media.HEIGHT,
            MediaStore.Images.Media.MIME_TYPE,
        )

        // Bundle-form query (API 26+; we're minSdk 29). Avoids relying on the
        // MediaProvider's SQL LIMIT/OFFSET leak behaviour.
        val args = Bundle().apply {
            putString(ContentResolver.QUERY_ARG_SQL_SELECTION, "${MediaStore.Images.Media.MIME_TYPE} = ?")
            putStringArray(
                ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, arrayOf(mimeFilter)
            )
            val sortCol = if (sortBy == "date_added") {
                MediaStore.Images.Media.DATE_ADDED
            } else {
                MediaStore.Images.Media.DATE_TAKEN
            }
            putStringArray(ContentResolver.QUERY_ARG_SORT_COLUMNS, arrayOf(sortCol))
            putInt(
                ContentResolver.QUERY_ARG_SORT_DIRECTION,
                ContentResolver.QUERY_SORT_DIRECTION_DESCENDING,
            )
            putInt(ContentResolver.QUERY_ARG_LIMIT, limit)
            putInt(ContentResolver.QUERY_ARG_OFFSET, offset)
        }

        val items = ArrayList<Map<String, Any?>>(limit)
        try {
            contentResolver.query(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                projection,
                args,
                null,
            )?.use { cursor ->
                mapCursorToMediaItems(cursor, items)
            }
        } catch (se: SecurityException) {
            respondError(result, "PERMISSION_DENIED",
                "READ_MEDIA_IMAGES / READ_EXTERNAL_STORAGE not granted")
            return
        } catch (e: Exception) {
            respondError(result, "QUERY_FAILED", e.message ?: "query failed")
            return
        }
        respondSuccess(result, items)
    }

    private fun mapCursorToMediaItems(
        cursor: Cursor,
        out: ArrayList<Map<String, Any?>>,
    ) {
        val idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
        val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
        val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
        val dtCol = cursor.getColumnIndex(MediaStore.Images.Media.DATE_TAKEN)
        val daCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_ADDED)
        val wCol = cursor.getColumnIndex(MediaStore.Images.Media.WIDTH)
        val hCol = cursor.getColumnIndex(MediaStore.Images.Media.HEIGHT)
        val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE)

        while (cursor.moveToNext()) {
            val id = cursor.getLong(idCol)
            val uri = ContentUris.withAppendedId(
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id,
            ).toString()

            // DATE_TAKEN is nullable per Doc 3 §2.1; many MediaStore rows lack it.
            val dateTakenMs: Long? = if (dtCol >= 0 && !cursor.isNull(dtCol)) {
                cursor.getLong(dtCol)
            } else null
            // DATE_ADDED is in seconds (MediaStore column semantics), convert to ms.
            val dateAddedMs = cursor.getLong(daCol) * 1000L

            val width: Int? = if (wCol >= 0 && !cursor.isNull(wCol)) cursor.getInt(wCol) else null
            val height: Int? = if (hCol >= 0 && !cursor.isNull(hCol)) cursor.getInt(hCol) else null

            out.add(
                mapOf(
                    "id" to id,
                    "uri" to uri,
                    "displayName" to cursor.getString(nameCol),
                    "size" to cursor.getLong(sizeCol),
                    "dateTakenMs" to dateTakenMs,
                    "dateAddedMs" to dateAddedMs,
                    "width" to width,
                    "height" to height,
                    "mimeType" to cursor.getString(mimeCol),
                )
            )
        }
    }

    // ---------------------------------------------------------------------
    // §2.2 getThumbnail
    // ---------------------------------------------------------------------

    private suspend fun getThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val contentUri = call.argument<String>("contentUri")
        val size = (call.argument<Int>("size") ?: 200).coerceAtLeast(32)
        if (contentUri.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "contentUri is required")
            return
        }
        val uri = try {
            Uri.parse(contentUri)
        } catch (e: Exception) {
            respondError(result, "INVALID_ARGUMENT", "malformed URI")
            return
        }

        var bitmap: Bitmap? = null
        try {
            bitmap = contentResolver.loadThumbnail(uri, Size(size, size), null)
            ByteArrayOutputStream(20 * 1024).use { baos ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 80, baos)
                respondSuccess(result, baos.toByteArray())
            }
        } catch (e: SecurityException) {
            respondError(result, "PERMISSION_DENIED", e.message ?: "no access to URI")
        } catch (e: IOException) {
            respondError(result, "THUMB_LOAD_FAILED", e.message ?: "loadThumbnail failed")
        } catch (e: Exception) {
            respondError(result, "THUMB_LOAD_FAILED", e.message ?: "thumbnail failed")
        } finally {
            bitmap?.recycle()
        }
    }

    // ---------------------------------------------------------------------
    // §2.3 openInputDescriptor
    // ---------------------------------------------------------------------

    private suspend fun openInputDescriptor(call: MethodCall, result: MethodChannel.Result) {
        val contentUri = call.argument<String>("contentUri")
        if (contentUri.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "contentUri is required")
            return
        }
        try {
            val pfd = contentResolver.openFileDescriptor(Uri.parse(contentUri), "r")
                ?: run {
                    respondError(result, "OPEN_FAILED", "openFileDescriptor returned null")
                    return
                }
            val handle = FdRegistry.register(pfd)
            respondSuccess(
                result, mapOf(
                    "handle" to handle,
                    "fd" to pfd.fd,
                    "size" to pfd.statSize,
                )
            )
        } catch (e: SecurityException) {
            respondError(result, "PERMISSION_DENIED", e.message)
        } catch (e: Exception) {
            respondError(result, "OPEN_FAILED", e.message ?: "open failed")
        }
    }

    // ---------------------------------------------------------------------
    // §2.4 closeDescriptor
    // ---------------------------------------------------------------------

    private suspend fun closeDescriptor(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<String>("handle")
        if (handle.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "handle is required")
            return
        }
        FdRegistry.close(handle)
        respondSuccess(result, null)
    }

    // ---------------------------------------------------------------------
    // §2.5 createOutputUri
    // ---------------------------------------------------------------------

    private suspend fun createOutputUri(call: MethodCall, result: MethodChannel.Result) {
        val displayName = call.argument<String>("displayName")
        val relativePath = call.argument<String>("relativePath") ?: "Pictures/Liveback/"
        val mimeType = call.argument<String>("mimeType") ?: "image/jpeg"
        val dateTakenMs = call.argument<Number>("dateTakenMs")?.toLong()
        val dateModifiedSec = call.argument<Number>("dateModifiedSec")?.toLong()
        if (displayName.isNullOrEmpty() || dateTakenMs == null) {
            respondError(result, "INVALID_ARGUMENT",
                "displayName + dateTakenMs are required")
            return
        }
        if (dateTakenMs <= 0L || dateTakenMs < MIN_DATE_TAKEN_MS) {
            respondError(result, "INVALID_DATE_TAKEN",
                "dateTakenMs=$dateTakenMs is before year-2000 sanity floor")
            return
        }

        val (uri, finalName) = try {
            insertPendingRowWithRetry(displayName, relativePath, mimeType,
                dateTakenMs, dateModifiedSec)
        } catch (e: IOException) {
            val code = if (e.message?.contains("ENOSPC", ignoreCase = true) == true
                || e.cause?.message?.contains("ENOSPC", ignoreCase = true) == true
            ) "NO_SPACE" else "INSERT_FAILED"
            respondError(result, code, e.message ?: "insert failed")
            return
        } catch (e: Exception) {
            respondError(result, "INSERT_FAILED", e.message ?: "insert failed")
            return
        }

        try {
            val pfd = contentResolver.openFileDescriptor(uri, "w")
                ?: throw IOException("openFileDescriptor(w) returned null")
            val handle = FdRegistry.register(pfd)
            respondSuccess(
                result, mapOf(
                    "uri" to uri.toString(),
                    "handle" to handle,
                    "fd" to pfd.fd,
                    "displayName" to finalName,
                )
            )
        } catch (e: Exception) {
            // Roll back the pending row — otherwise IS_PENDING=1 leaks
            // (see Doc 3 §3 gotcha).
            runCatching { contentResolver.delete(uri, null, null) }
            respondError(result, "OPEN_FAILED", e.message ?: "output open failed")
        }
    }

    /** Inserts a pending MediaStore row with the given displayName. On
     *  UNIQUE-constraint collision (Doc 3 §2.5), retries with `_N` suffix up
     *  to [DISPLAY_NAME_RETRY_MAX] times. */
    private fun insertPendingRowWithRetry(
        baseDisplayName: String,
        relativePath: String,
        mimeType: String,
        dateTakenMs: Long,
        dateModifiedSec: Long?,
    ): Pair<Uri, String> {
        val dot = baseDisplayName.lastIndexOf('.')
        val stem = if (dot > 0) baseDisplayName.substring(0, dot) else baseDisplayName
        val ext = if (dot > 0) baseDisplayName.substring(dot) else ""

        var attempt = 0
        while (attempt <= DISPLAY_NAME_RETRY_MAX) {
            val name = if (attempt == 0) baseDisplayName else "${stem}_${attempt}${ext}"
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                put(MediaStore.Images.Media.RELATIVE_PATH, relativePath)
                put(MediaStore.Images.Media.DATE_TAKEN, dateTakenMs)
                dateModifiedSec?.let {
                    put(MediaStore.Images.Media.DATE_MODIFIED, it)
                }
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            try {
                val uri = contentResolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values,
                )
                if (uri != null) return uri to name
                // null insert is usually UNIQUE collision; try next suffix.
            } catch (e: IllegalStateException) {
                // Certain OEMs throw on UNIQUE violation; treat as retry.
            } catch (e: IllegalArgumentException) {
                // Bad arguments surface immediately — no retry.
                throw IOException("insert rejected: ${e.message}", e)
            }
            attempt++
        }
        throw IOException("insert failed after $DISPLAY_NAME_RETRY_MAX retries (collision?)")
    }

    // ---------------------------------------------------------------------
    // §2.6 openOutputDescriptor  (re-open path)
    // ---------------------------------------------------------------------

    private suspend fun openOutputDescriptor(call: MethodCall, result: MethodChannel.Result) {
        val handle = call.argument<String>("handle")
        if (handle.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "handle is required")
            return
        }
        val pfd = FdRegistry.get(handle)
        if (pfd == null) {
            respondError(result, "HANDLE_NOT_FOUND", "no pfd for handle=$handle")
            return
        }
        respondSuccess(result, mapOf("fd" to pfd.fd))
    }

    // ---------------------------------------------------------------------
    // §2.7 finalizePendingOutput
    // ---------------------------------------------------------------------

    private suspend fun finalizePendingOutput(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        val handle = call.argument<String>("handle")
        if (uriStr.isNullOrEmpty() || handle.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "uri + handle required")
            return
        }
        try {
            FdRegistry.close(handle)  // flush + release before clearing IS_PENDING
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }
            val rows = contentResolver.update(Uri.parse(uriStr), values, null, null)
            if (rows == 0) {
                respondError(result, "FINALIZE_FAILED",
                    "update returned 0 rows (pending row missing)")
                return
            }
            respondSuccess(result, null)
        } catch (e: Exception) {
            respondError(result, "FINALIZE_FAILED", e.message ?: "finalize failed")
        }
    }

    // ---------------------------------------------------------------------
    // §2.8 deletePendingOutput
    // ---------------------------------------------------------------------

    private suspend fun deletePendingOutput(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        val handle = call.argument<String>("handle")
        if (uriStr.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "uri is required")
            return
        }
        // Idempotent: both handle close and delete tolerate unknown / missing.
        handle?.let { FdRegistry.close(it) }
        try {
            contentResolver.delete(Uri.parse(uriStr), null, null)
        } catch (_: Exception) {
            // Swallow per Doc 3 §2.8 idempotency.
        }
        respondSuccess(result, null)
    }

    // ---------------------------------------------------------------------
    // §2.9 updateMetadata
    // ---------------------------------------------------------------------

    private suspend fun updateMetadata(call: MethodCall, result: MethodChannel.Result) {
        val uriStr = call.argument<String>("uri")
        if (uriStr.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "uri is required")
            return
        }
        val values = ContentValues()
        call.argument<Number>("dateTakenMs")?.let {
            values.put(MediaStore.Images.Media.DATE_TAKEN, it.toLong())
        }
        call.argument<Number>("dateModifiedSec")?.let {
            values.put(MediaStore.Images.Media.DATE_MODIFIED, it.toLong())
        }
        call.argument<String>("displayName")?.let {
            values.put(MediaStore.Images.Media.DISPLAY_NAME, it)
        }
        try {
            contentResolver.update(Uri.parse(uriStr), values, null, null)
            respondSuccess(result, null)
        } catch (e: Exception) {
            respondError(result, "UPDATE_FAILED", e.message ?: "update failed")
        }
    }

    // ---------------------------------------------------------------------
    // §3 sandbox operations
    // ---------------------------------------------------------------------

    private fun sandboxDir(): File =
        File(appContext.cacheDir, SANDBOX_SUBDIR).apply { if (!exists()) mkdirs() }

    private fun sandboxInputFile(taskId: String) =
        File(sandboxDir(), "in-$taskId.jpg")

    private fun sandboxOutputFile(taskId: String) =
        File(sandboxDir(), "out-$taskId.jpg")

    private suspend fun copyInputToSandbox(call: MethodCall, result: MethodChannel.Result) {
        val contentUri = call.argument<String>("contentUri")
        val taskId = call.argument<String>("taskId")
        if (contentUri.isNullOrEmpty() || taskId.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "contentUri + taskId required")
            return
        }
        if (!isSafeTaskId(taskId)) {
            respondError(result, "INVALID_ARGUMENT", "taskId contains path separators")
            return
        }
        val target = sandboxInputFile(taskId)
        try {
            contentResolver.openFileDescriptor(Uri.parse(contentUri), "r")?.use { pfd ->
                FileInputStream(pfd.fileDescriptor).use { inStream ->
                    FileOutputStream(target).use { outStream ->
                        inStream.copyTo(outStream, COPY_BUFFER_BYTES)
                        outStream.fd.sync()
                    }
                }
            } ?: run {
                respondError(result, "OPEN_FAILED", "openFileDescriptor returned null")
                return
            }
            respondSuccess(
                result, mapOf("path" to target.absolutePath, "size" to target.length()),
            )
        } catch (e: SecurityException) {
            runCatching { target.delete() }
            respondError(result, "PERMISSION_DENIED", e.message ?: "permission denied")
        } catch (e: IOException) {
            runCatching { target.delete() }
            val code = if (isNoSpace(e)) "NO_SPACE" else "COPY_FAILED"
            respondError(result, code, e.message ?: "copy failed")
        } catch (e: Exception) {
            runCatching { target.delete() }
            respondError(result, "COPY_FAILED", e.message ?: "copy failed")
        }
    }

    private suspend fun reserveOutputSandbox(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.argument<String>("taskId")
        if (taskId.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "taskId required")
            return
        }
        if (!isSafeTaskId(taskId)) {
            respondError(result, "INVALID_ARGUMENT", "taskId contains path separators")
            return
        }
        val target = sandboxOutputFile(taskId)
        // Remove any stale file left behind by a previous run; fix_service
        // expects the path to be writable but does not require it to exist
        // (per Doc 2 atomic-rename contract).
        runCatching { if (target.exists()) target.delete() }
        sandboxDir()  // ensure parent
        respondSuccess(result, mapOf("path" to target.absolutePath))
    }

    /** Copies the sandbox file at [sandboxPath] into the pending MediaStore
     *  row opened earlier via [createOutputUri]. Does NOT close the pfd —
     *  the caller (publishOutputToMediaStore facade or Dart test-mode path)
     *  owns finalize/delete. */
    private suspend fun copySandboxToOutput(call: MethodCall, result: MethodChannel.Result) {
        val sandboxPath = call.argument<String>("sandboxPath")
        val handle = call.argument<String>("handle")
        if (sandboxPath.isNullOrEmpty() || handle.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "sandboxPath + handle required")
            return
        }
        val pfd = FdRegistry.get(handle)
        if (pfd == null) {
            respondError(result, "HANDLE_NOT_FOUND", "no pfd for handle=$handle")
            return
        }
        try {
            copySandboxToPfd(sandboxPath, pfd)
            respondSuccess(result, null)
        } catch (e: IOException) {
            val code = if (isNoSpace(e)) "NO_SPACE" else "COPY_FAILED"
            respondError(result, code, e.message ?: "copy failed")
        } catch (e: Exception) {
            respondError(result, "COPY_FAILED", e.message ?: "copy failed")
        }
    }

    private fun copySandboxToPfd(sandboxPath: String, pfd: android.os.ParcelFileDescriptor) {
        FileInputStream(sandboxPath).use { inStream ->
            FileOutputStream(pfd.fileDescriptor).use { outStream ->
                inStream.copyTo(outStream, COPY_BUFFER_BYTES)
                // Do NOT call outStream.fd.sync() here — the underlying fd is
                // owned by the pfd and will be flushed on pfd.close() inside
                // finalizePendingOutput.
            }
        }
    }

    private suspend fun deleteSandboxFiles(call: MethodCall, result: MethodChannel.Result) {
        val taskId = call.argument<String>("taskId")
        if (taskId.isNullOrEmpty()) {
            respondError(result, "INVALID_ARGUMENT", "taskId required")
            return
        }
        if (!isSafeTaskId(taskId)) {
            respondError(result, "INVALID_ARGUMENT", "taskId contains path separators")
            return
        }
        // Skipped kinds never create out-<taskId>.jpg — missing files are
        // NOT an error (Doc 3 §3 + review B2). Any real IO problem (permission,
        // directory unreadable) surfaces as DELETE_FAILED.
        val input = sandboxInputFile(taskId)
        val output = sandboxOutputFile(taskId)
        try {
            if (input.exists() && !input.delete()) {
                throw IOException("failed to delete ${input.name}")
            }
            if (output.exists() && !output.delete()) {
                throw IOException("failed to delete ${output.name}")
            }
            respondSuccess(result, null)
        } catch (e: Exception) {
            respondError(result, "DELETE_FAILED", e.message ?: "delete failed")
        }
    }

    private suspend fun sweepSandbox(result: MethodChannel.Result) {
        var deleted = 0
        val cutoff = System.currentTimeMillis() - SWEEP_MAX_AGE_MS
        try {
            sandboxDir().listFiles()?.forEach { f ->
                if (f.isFile && f.lastModified() < cutoff) {
                    if (f.delete()) deleted++
                }
            }
            respondSuccess(result, mapOf("deletedCount" to deleted))
        } catch (e: Exception) {
            respondError(result, "SWEEP_FAILED", e.message ?: "sweep failed")
        }
    }

    // ---------------------------------------------------------------------
    // publishOutputToMediaStore facade (Doc 3 §3 call sequence)
    // ---------------------------------------------------------------------

    private suspend fun publishOutputToMediaStore(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val sandboxOutPath = call.argument<String>("sandboxOutPath")
        val displayName = call.argument<String>("displayName")
        val dateTakenMs = call.argument<Number>("dateTakenEpochMs")?.toLong()
        val originalMtimeMs = call.argument<Number>("originalMtimeEpochMs")?.toLong()
        val relativePath = call.argument<String>("relativePath") ?: "Pictures/Liveback/"

        if (sandboxOutPath.isNullOrEmpty() || displayName.isNullOrEmpty()
            || dateTakenMs == null
        ) {
            respondError(result, "INVALID_ARGUMENT",
                "sandboxOutPath + displayName + dateTakenEpochMs required")
            return
        }
        val sandboxFile = File(sandboxOutPath)
        if (!sandboxFile.exists() || !sandboxFile.isFile) {
            respondError(result, "SANDBOX_MISSING",
                "sandbox output does not exist: $sandboxOutPath")
            return
        }
        if (dateTakenMs <= 0L || dateTakenMs < MIN_DATE_TAKEN_MS) {
            respondError(result, "INVALID_DATE_TAKEN",
                "dateTakenMs=$dateTakenMs before year-2000 floor")
            return
        }

        // Phase 1: insert pending row.
        val (uri, _) = try {
            insertPendingRowWithRetry(
                baseDisplayName = displayName,
                relativePath = relativePath,
                mimeType = "image/jpeg",
                dateTakenMs = dateTakenMs,
                dateModifiedSec = originalMtimeMs?.let { it / 1000L },
            )
        } catch (e: IOException) {
            val code = if (isNoSpace(e)) "NO_SPACE" else "INSERT_FAILED"
            respondError(result, code, e.message ?: "insert failed")
            return
        }

        // Phase 2: open pfd, stream sandbox → pfd, close pfd. Any failure
        // triggers the rollback path below.
        var rolledBack = false
        try {
            val pfd = contentResolver.openFileDescriptor(uri, "w")
                ?: throw IOException("openFileDescriptor(w) returned null")
            try {
                copySandboxToPfd(sandboxOutPath, pfd)
            } finally {
                runCatching { pfd.close() }
            }

            // Phase 3: finalize (IS_PENDING=0).
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }
            val rows = contentResolver.update(uri, values, null, null)
            if (rows == 0) throw IOException("finalize update returned 0 rows")

            respondSuccess(result, uri.toString())
            return
        } catch (e: Throwable) {
            // Rollback pending row (Doc 3 §3 gotcha).
            rolledBack = true
            runCatching { contentResolver.delete(uri, null, null) }
            val code = when {
                e is SecurityException -> "PERMISSION_DENIED"
                isNoSpace(e) -> "NO_SPACE"
                e is IOException -> "PUBLISH_FAILED"
                else -> "PUBLISH_FAILED"
            }
            respondError(result, code, e.message ?: "publish failed")
        } finally {
            if (!rolledBack) {
                // success path — nothing to clean up.
            }
        }
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    private fun isSafeTaskId(id: String): Boolean =
        !id.contains('/') && !id.contains('\\') && id != ".." && id != "."
                && !id.startsWith(".")

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
}
