package com.pinoypos.pinoy_pos

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException

/**
 * Android Storage Access Framework (SAF) bridge for Pinoy POS backup/restore.
 *
 * This bridge is intentionally separate from [MainActivity] so the storage logic
 * can be tested and maintained independently of the Flutter activity lifecycle.
 *
 * Responsibilities:
 * - Read/write documents under a persisted SAF tree URI without loading the
 *   whole file into RAM (streams between a local temp file and the provider).
 * - Validate that persisted URIs are still accessible and that permissions have
 *   not been revoked.
 * - Provide human-readable display names for content:// URIs.
 */
class StorageBridge(private val activity: Activity) {

    companion object {
        private const val TAG = "StorageBridge"
        private const val COPY_BUFFER_SIZE = 8192
    }

    // ----------------------------------------------------------------------
    // Public bridge operations
    // ----------------------------------------------------------------------

    /**
     * Checks whether [uri] is still accessible and the permission has not been
     * revoked. For tree URIs this verifies the persisted write grant; for
     * document URIs it verifies the read grant and that the document can be
     * queried.
     */
    fun isUriValid(uri: Uri): Boolean {
        return try {
            val permissions = activity.contentResolver.persistedUriPermissions
            val hasPermission = if (DocumentsContract.isTreeUri(uri)) {
                permissions.any { it.uri == uri && it.isWritePermission }
            } else {
                permissions.any { it.uri == uri && it.isReadPermission }
            }

            if (!hasPermission) {
                Log.w(TAG, "Persisted permission missing for $uri")
                return false
            }

            if (DocumentsContract.isTreeUri(uri)) {
                // Querying the tree document directly can fail on some providers.
                // Build a document URI for the tree root and try a minimal query.
                val docUri = buildDocumentUriForTree(uri)
                canQuery(docUri)
            } else {
                canQuery(uri)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to validate $uri", e)
            false
        }
    }

    /**
     * Returns a user-facing display name for [uri], or null if it cannot be
     * resolved. Tree URIs are resolved to their root document display name.
     */
    fun getDisplayName(uri: Uri): String? {
        return try {
            val queryUri = if (DocumentsContract.isTreeUri(uri)) {
                buildDocumentUriForTree(uri)
            } else {
                uri
            }
            activity.contentResolver.query(queryUri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        .takeIf { it >= 0 }
                        ?: cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                            .takeIf { it >= 0 }
                        ?: -1
                    if (index >= 0) cursor.getString(index) else null
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not query display name for $uri", e)
            null
        }
    }

    /**
     * Creates a new document under [treeUri] with [displayName] and streams the
     * contents of [sourceFile] into it.
     *
     * Returns a map containing the document URI, display name and size, or
     * calls [result].error if the write could not be completed.
     */
    fun writeDocument(
        treeUri: Uri,
        sourceFile: File,
        displayName: String,
        mimeType: String,
        result: MethodChannel.Result,
    ) {
        if (!DocumentsContract.isTreeUri(treeUri)) {
            result.error(
                "INVALID_ARGS",
                "The backup location is not a valid Storage Access Framework folder.",
                null,
            )
            return
        }

        if (!sourceFile.exists() || sourceFile.length() == 0L) {
            result.error("WRITE_FAILED", "The backup file is empty or missing.", null)
            return
        }

        Thread {
            try {
                // 1. Pick/create the target document.
                val targetFile = findOrCreateDocument(treeUri, displayName, mimeType)
                    ?: throw IOException("Could not create the backup document in the selected folder.")

                // 2. Stream the source file into the provider.
                val written = copyFileToUri(sourceFile, targetFile.uri)
                if (written != sourceFile.length()) {
                    throw IOException("The backup file size does not match the expected size.")
                }

                // 3. Verify the provider persisted the bytes.
                val finalName = getDisplayName(targetFile.uri) ?: displayName
                val actualSize = queryDocumentSize(targetFile.uri)
                if (actualSize >= 0L && actualSize != written) {
                    throw IOException("The backup file size does not match the expected size.")
                }

                runOnUiThread {
                    result.success(
                        mapOf(
                            "uri" to targetFile.uri.toString(),
                            "displayName" to finalName,
                            "size" to if (actualSize >= 0L) actualSize else written,
                        )
                    )
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "Permission denied writing backup document", e)
                runOnUiThread {
                    result.error(
                        "WRITE_FAILED",
                        "Not allowed to write to the selected folder. " +
                            "Choose a different location or grant write access.",
                        null,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to write backup document", e)
                runOnUiThread {
                    result.error("WRITE_FAILED", e.message, null)
                }
            }
        }.start()
    }

    /**
     * Copies the contents of [uri] into a local temp file inside [targetDir].
     *
     * Returns a map with the temp file path, display name and size, or calls
     * [result].error.
     */
    fun copyUriToTempFile(
        uri: Uri,
        targetDir: File,
        result: MethodChannel.Result,
    ) {
        if (!targetDir.exists()) {
            targetDir.mkdirs()
        }

        Thread {
            try {
                val displayName = getDisplayName(uri) ?: uri.lastPathSegment ?: "backup.db"
                val safeName = displayName.replace("/", "_").replace("\\", "_")
                val tempFile = File(targetDir, "pinoy_pos_import_${System.currentTimeMillis()}_$safeName")

                val written = copyUriToFile(uri, tempFile)
                if (written == 0L) {
                    throw IOException("The selected backup file is empty.")
                }

                runOnUiThread {
                    result.success(
                        mapOf(
                            "uri" to uri.toString(),
                            "displayName" to displayName,
                            "size" to written,
                            "filePath" to tempFile.absolutePath,
                        )
                    )
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "Permission denied reading document", e)
                runOnUiThread {
                    result.error(
                        "READ_ERROR",
                        "Not allowed to read the selected backup. " +
                            "Choose the file again and grant read access.",
                        null,
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to read document", e)
                runOnUiThread {
                    result.error("READ_ERROR", e.message, null)
                }
            }
        }.start()
    }

    /**
     * Deletes the document at [uri].
     */
    fun deleteDocument(uri: Uri): Boolean {
        return try {
            when {
                DocumentsContract.isTreeUri(uri) -> {
                    DocumentFile.fromTreeUri(activity, uri)?.delete() == true
                }
                DocumentsContract.isDocumentUri(activity, uri) -> {
                    DocumentFile.fromSingleUri(activity, uri)?.delete() == true
                }
                else -> false
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to delete document", e)
            false
        }
    }

    /**
     * Releases the persisted URI permission for [uri].
     */
    fun releaseUri(uri: Uri) {
        try {
            activity.contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to release URI permission", e)
        }
    }

    // ----------------------------------------------------------------------
    // Internal helpers
    // ----------------------------------------------------------------------

    /**
     * Finds or creates a document with [displayName] under [treeUri].
     *
     * First tries [DocumentFile.createFile], which is the recommended high-level
     * API. If that returns null (some providers create the file but report
     * failure, or fail to match the MIME type) it falls back to
     * [DocumentsContract.createDocument] using the tree root as the parent.
     */
    private fun findOrCreateDocument(
        treeUri: Uri,
        displayName: String,
        mimeType: String,
    ): DocumentFile? {
        val tree = DocumentFile.fromTreeUri(activity, treeUri)
        if (tree != null) {
            val created = tree.createFile(mimeType, displayName)
            if (created != null) {
                return created
            }
            // Some providers create the file but return null. Try to find it.
            val found = tree.findFile(displayName)
            if (found != null) {
                return found
            }
        }

        // Fallback: use DocumentsContract directly with the tree root document.
        val parentUri = buildDocumentUriForTree(treeUri)
        val docUri = try {
            DocumentsContract.createDocument(
                activity.contentResolver,
                parentUri,
                mimeType,
                displayName,
            )
        } catch (e: Exception) {
            Log.w(TAG, "DocumentsContract.createDocument failed", e)
            null
        }

        return docUri?.let { DocumentFile.fromSingleUri(activity, it) }
    }

    /**
     * Builds a document URI for the root of [treeUri].
     *
     * This uses the tree's own document ID as the parent document. The tree
     * document ID is extracted by taking the second raw path segment and
     * decoding it, which correctly preserves encoded slashes that may appear
     * inside the document ID (e.g. `primary:Documents/Quiz`).
     */
    private fun buildDocumentUriForTree(treeUri: Uri): Uri {
        val path = treeUri.encodedPath ?: throw IllegalArgumentException("Tree URI has no path: $treeUri")
        val segments = path.split('/').drop(1)
        if (segments.size < 2 || segments[0] != "tree") {
            throw IllegalArgumentException("Not a tree URI: $treeUri")
        }
        // The second path segment is the encoded tree document ID.
        val treeDocId = Uri.decode(segments[1])
        return Uri.Builder()
            .scheme("content")
            .authority(treeUri.authority)
            .appendPath("tree")
            .appendPath(treeDocId)
            .appendPath("document")
            .appendPath(treeDocId)
            .build()
    }

    private fun copyFileToUri(sourceFile: File, targetUri: Uri): Long {
        var written = 0L
        activity.contentResolver.openOutputStream(targetUri, "w")?.use { output ->
            FileInputStream(sourceFile).use { input ->
                val buffer = ByteArray(COPY_BUFFER_SIZE)
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    output.write(buffer, 0, read)
                    written += read
                }
                output.flush()
            }
        } ?: throw IOException("Could not open output stream for $targetUri")
        return written
    }

    private fun copyUriToFile(sourceUri: Uri, targetFile: File): Long {
        var written = 0L
        activity.contentResolver.openInputStream(sourceUri)?.use { input ->
            FileOutputStream(targetFile).use { output ->
                val buffer = ByteArray(COPY_BUFFER_SIZE)
                var read: Int
                while (input.read(buffer).also { read = it } != -1) {
                    output.write(buffer, 0, read)
                    written += read
                }
                output.flush()
            }
        } ?: throw IOException("Could not open input stream for $sourceUri")
        return written
    }

    private fun queryDocumentSize(uri: Uri): Long {
        return try {
            activity.contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
                return@use pfd.statSize
            } ?: activity.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.SIZE)
                        .takeIf { it >= 0 }
                        ?: cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                            .takeIf { it >= 0 }
                        ?: -1
                    if (index >= 0) cursor.getLong(index) else -1L
                } else {
                    -1L
                }
            } ?: -1L
        } catch (e: Exception) {
            -1L
        }
    }

    private fun canQuery(uri: Uri): Boolean {
        return try {
            activity.contentResolver.query(
                uri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )?.use { cursor ->
                cursor.moveToFirst()
            } ?: false
        } catch (e: Exception) {
            false
        }
    }

    private fun runOnUiThread(action: () -> Unit) {
        activity.runOnUiThread { action() }
    }
}
