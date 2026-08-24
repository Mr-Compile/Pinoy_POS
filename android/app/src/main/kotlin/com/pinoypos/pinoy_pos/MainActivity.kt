package com.pinoypos.pinoy_pos

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.ByteArrayOutputStream
import java.io.File

private const val CHANNEL = "com.pinoypos.pinoy_pos/backup_storage"
private const val TAG = "BackupStorage"

class MainActivity : FlutterActivity() {

    private lateinit var openDocumentTreeLauncher: ActivityResultLauncher<Uri?>
    private var pendingOpenTreeResult: Result? = null

    private lateinit var openDocumentLauncher: ActivityResultLauncher<Array<String>>
    private var pendingOpenDocumentResult: Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        openDocumentTreeLauncher = registerForActivityResult(
            ActivityResultContracts.OpenDocumentTree()
        ) { uri ->
            val result = pendingOpenTreeResult
            pendingOpenTreeResult = null
            if (result == null) return@registerForActivityResult

            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }

            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            try {
                contentResolver.takePersistableUriPermission(uri, takeFlags)
            } catch (e: Exception) {
                Log.w(TAG, "Could not take persistable permission for $uri", e)
            }

            result.success(
                mapOf(
                    "uri" to uri.toString(),
                    "displayName" to (getDisplayName(uri) ?: "Selected folder"),
                )
            )
        }

        openDocumentLauncher = registerForActivityResult(
            ActivityResultContracts.OpenDocument()
        ) { uri ->
            val result = pendingOpenDocumentResult
            pendingOpenDocumentResult = null
            if (result == null) return@registerForActivityResult

            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }

            Thread {
                try {
                    contentResolver.openInputStream(uri)?.use { input ->
                        val bytes = input.readBytes()
                        val displayName = getDisplayName(uri) ?: "backup.db"
                        runOnUiThread {
                            result.success(
                                mapOf(
                                    "uri" to uri.toString(),
                                    "displayName" to displayName,
                                    "size" to bytes.size,
                                    "bytes" to bytes,
                                )
                            )
                        }
                    } ?: runOnUiThread {
                        result.error("READ_ERROR", "Could not open the selected file", null)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to read picked document", e)
                    runOnUiThread {
                        result.error("READ_ERROR", e.message, null)
                    }
                }
            }.start()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openDocumentTree" -> openDocumentTree(call, result)
                "createDocument" -> createDocument(call, result)
                "readDocument" -> readDocument(call, result)
                "isUriValid" -> isUriValid(call, result)
                "getDisplayName" -> getDisplayName(call, result)
                "openDocument" -> openDocument(call, result)
                "deleteDocument" -> deleteDocument(call, result)
                "releaseUri" -> releaseUri(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun openDocumentTree(call: MethodCall, result: Result) {
        val initialUri = call.argument<String>("initialUri")?.let { Uri.parse(it) }
        pendingOpenTreeResult = result
        try {
            openDocumentTreeLauncher.launch(initialUri)
        } catch (e: Exception) {
            pendingOpenTreeResult = null
            result.error("LAUNCH_ERROR", e.message, null)
        }
    }

    private fun openDocument(call: MethodCall, result: Result) {
        val mimeTypes = call.argument<List<String>>("mimeTypes")
            ?.toTypedArray()
            ?: arrayOf("*/*")
        pendingOpenDocumentResult = result
        try {
            openDocumentLauncher.launch(mimeTypes)
        } catch (e: Exception) {
            pendingOpenDocumentResult = null
            result.error("LAUNCH_ERROR", e.message, null)
        }
    }

    private fun createDocument(call: MethodCall, result: Result) {
        val treeUriString = call.argument<String>("treeUri")
        val displayName = call.argument<String>("displayName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        val bytes = call.argument<ByteArray>("bytes")

        if (treeUriString == null || displayName == null || bytes == null) {
            result.error("INVALID_ARGS", "Missing treeUri, displayName, or bytes", null)
            return
        }

        val treeUri = Uri.parse(treeUriString)

        Thread {
            try {
                val docUri = DocumentsContract.createDocument(
                    contentResolver,
                    treeUri,
                    mimeType,
                    displayName,
                )

                if (docUri == null) {
                    runOnUiThread {
                        result.error("CREATE_FAILED", "Could not create document in selected folder", null)
                    }
                    return@Thread
                }

                contentResolver.openOutputStream(docUri, "rwt")?.use { output ->
                    output.write(bytes)
                    output.flush()
                } ?: runOnUiThread {
                    result.error("WRITE_FAILED", "Could not open output stream", null)
                    return@Thread
                }

                val finalName = getDisplayName(docUri) ?: displayName
                runOnUiThread {
                    result.success(
                        mapOf(
                            "uri" to docUri.toString(),
                            "displayName" to finalName,
                            "size" to bytes.size,
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to create backup document", e)
                runOnUiThread {
                    result.error("WRITE_FAILED", e.message, null)
                }
            }
        }.start()
    }

    private fun readDocument(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: run {
            result.error("INVALID_ARGS", "Missing uri", null)
            return
        }
        val uri = Uri.parse(uriString)

        Thread {
            try {
                contentResolver.openInputStream(uri)?.use { input ->
                    val bytes = input.readBytes()
                    val displayName = getDisplayName(uri) ?: "backup.db"
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "uri" to uri.toString(),
                                "displayName" to displayName,
                                "size" to bytes.size,
                                "bytes" to bytes,
                            )
                        )
                    }
                } ?: runOnUiThread {
                    result.error("READ_ERROR", "Could not open the backup file", null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to read backup document", e)
                runOnUiThread {
                    result.error("READ_ERROR", e.message, null)
                }
            }
        }.start()
    }

    private fun isUriValid(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: run {
            result.error("INVALID_ARGS", "Missing uri", null)
            return
        }
        val uri = Uri.parse(uriString)

        Thread {
            try {
                val hasPermission = contentResolver.persistedUriPermissions.any {
                    it.uri == uri && it.isWritePermission
                }

                if (!hasPermission) {
                    runOnUiThread { result.success(false) }
                    return@Thread
                }

                val canQuery = canReadUri(uri)
                runOnUiThread { result.success(canQuery) }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to validate URI", e)
                runOnUiThread { result.success(false) }
            }
        }.start()
    }

    private fun deleteDocument(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: run {
            result.error("INVALID_ARGS", "Missing uri", null)
            return
        }
        val uri = Uri.parse(uriString)

        Thread {
            try {
                val deleted = DocumentsContract.deleteDocument(contentResolver, uri)
                runOnUiThread { result.success(deleted) }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to delete document", e)
                runOnUiThread { result.success(false) }
            }
        }.start()
    }

    private fun releaseUri(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: run {
            result.error("INVALID_ARGS", "Missing uri", null)
            return
        }
        val uri = Uri.parse(uriString)

        try {
            contentResolver.releasePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            result.success(null)
        } catch (e: Exception) {
            Log.w(TAG, "Failed to release URI", e)
            result.success(null)
        }
    }

    private fun getDisplayName(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: run {
            result.error("INVALID_ARGS", "Missing uri", null)
            return
        }
        val uri = Uri.parse(uriString)
        result.success(getDisplayName(uri) ?: uri.lastPathSegment ?: "Selected item")
    }

    private fun getDisplayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) cursor.getString(index) else null
                } else {
                    null
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not query display name", e)
            null
        }
    }

    private fun canReadUri(uri: Uri): Boolean {
        return try {
            contentResolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use { cursor ->
                cursor.moveToFirst()
            } ?: false
        } catch (e: Exception) {
            false
        }
    }
}

private fun java.io.InputStream.readBytes(): ByteArray {
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    var read: Int
    while (this.read(buffer).also { read = it } != -1) {
        output.write(buffer, 0, read)
    }
    return output.toByteArray()
}
