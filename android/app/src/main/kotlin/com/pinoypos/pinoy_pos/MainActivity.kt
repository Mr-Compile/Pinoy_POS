package com.pinoypos.pinoy_pos

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

private const val CHANNEL = "com.pinoypos.pinoy_pos/backup_storage"
private const val TAG = "MainActivity"

/**
 * Main entry point for the Flutter UI.
 *
 * SAF (Storage Access Framework) storage logic is delegated to [StorageBridge]
 * so this activity only owns the activity-launchers required for picker
 * intents and the method-channel dispatch table.
 */
class MainActivity : FlutterFragmentActivity() {

    private lateinit var storageBridge: StorageBridge

    private lateinit var openDocumentTreeLauncher: ActivityResultLauncher<Uri?>
    private var pendingOpenTreeResult: Result? = null

    private lateinit var openDocumentLauncher: ActivityResultLauncher<Array<String>>
    private var pendingOpenDocumentResult: Result? = null
    private var pendingOpenDocumentTargetDir: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        storageBridge = StorageBridge(this)

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
                result.error(
                    "PERMISSION_DENIED",
                    "Could not take persistable permission for the selected folder.",
                    null,
                )
                return@registerForActivityResult
            }

            val hasWrite = contentResolver.persistedUriPermissions.any {
                it.uri == uri && it.isWritePermission
            }
            if (!hasWrite) {
                result.error(
                    "PERMISSION_DENIED",
                    "Write permission was not granted for the selected folder.",
                    null,
                )
                return@registerForActivityResult
            }

            result.success(
                mapOf(
                    "uri" to uri.toString(),
                    "displayName" to (storageBridge.getDisplayName(uri) ?: "Selected folder"),
                )
            )
        }

        openDocumentLauncher = registerForActivityResult(
            ActivityResultContracts.OpenDocument()
        ) { uri ->
            val result = pendingOpenDocumentResult
            val targetDir = pendingOpenDocumentTargetDir
            pendingOpenDocumentResult = null
            pendingOpenDocumentTargetDir = null
            if (result == null) return@registerForActivityResult

            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }

            val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION
            try {
                contentResolver.takePersistableUriPermission(uri, takeFlags)
            } catch (e: Exception) {
                Log.w(TAG, "Could not take persistable permission for $uri", e)
            }

            if (targetDir == null) {
                result.error("INVALID_ARGS", "Missing targetDir for import", null)
                return@registerForActivityResult
            }

            storageBridge.copyUriToTempFile(uri, File(targetDir), result)
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
                "writeBackup" -> writeBackup(call, result)
                "readBackup" -> readBackup(call, result)
                "openDocument" -> openDocument(call, result)
                "isUriValid" -> isUriValid(call, result)
                "getDisplayName" -> getDisplayName(call, result)
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
        val targetDir = call.argument<String>("targetDir")
        if (targetDir == null) {
            result.error("INVALID_ARGS", "Missing targetDir for import", null)
            return
        }
        pendingOpenDocumentResult = result
        pendingOpenDocumentTargetDir = targetDir
        try {
            openDocumentLauncher.launch(mimeTypes)
        } catch (e: Exception) {
            pendingOpenDocumentResult = null
            pendingOpenDocumentTargetDir = null
            result.error("LAUNCH_ERROR", e.message, null)
        }
    }

    private fun writeBackup(call: MethodCall, result: Result) {
        val treeUriString = call.argument<String>("treeUri")
        val sourceFilePath = call.argument<String>("sourceFilePath")
        val displayName = call.argument<String>("displayName")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

        if (treeUriString == null || sourceFilePath == null || displayName == null) {
            result.error(
                "INVALID_ARGS",
                "Missing treeUri, sourceFilePath, or displayName",
                null,
            )
            return
        }

        val treeUri = Uri.parse(treeUriString)
        val sourceFile = File(sourceFilePath)

        storageBridge.writeDocument(treeUri, sourceFile, displayName, mimeType, result)
    }

    private fun readBackup(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: run {
            result.error("INVALID_ARGS", "Missing uri", null)
            return
        }
        val targetDir = call.argument<String>("targetDir") ?: run {
            result.error("INVALID_ARGS", "Missing targetDir for import", null)
            return
        }

        val uri = Uri.parse(uriString)
        storageBridge.copyUriToTempFile(uri, File(targetDir), result)
    }

    private fun isUriValid(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: run {
            result.error("INVALID_ARGS", "Missing uri", null)
            return
        }
        val uri = Uri.parse(uriString)

        Thread {
            val valid = storageBridge.isUriValid(uri)
            runOnUiThread { result.success(valid) }
        }.start()
    }

    private fun deleteDocument(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: run {
            result.error("INVALID_ARGS", "Missing uri", null)
            return
        }
        val uri = Uri.parse(uriString)

        Thread {
            val deleted = storageBridge.deleteDocument(uri)
            runOnUiThread { result.success(deleted) }
        }.start()
    }

    private fun releaseUri(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: run {
            result.error("INVALID_ARGS", "Missing uri", null)
            return
        }
        val uri = Uri.parse(uriString)

        storageBridge.releaseUri(uri)
        result.success(null)
    }

    private fun getDisplayName(call: MethodCall, result: Result) {
        val uriString = call.argument<String>("uri") ?: run {
            result.error("INVALID_ARGS", "Missing uri", null)
            return
        }
        val uri = Uri.parse(uriString)

        Thread {
            val name = storageBridge.getDisplayName(uri) ?: uri.lastPathSegment ?: "Selected item"
            runOnUiThread { result.success(name) }
        }.start()
    }
}
