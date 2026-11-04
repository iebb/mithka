package ad.neko.mithka

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption
import java.util.concurrent.Executors

class DownloadStoragePlugin(
    private val activity: FlutterFragmentActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "mithka/download_storage")
    private val preferences = activity.getSharedPreferences("download_storage", 0)
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pickerResult: MethodChannel.Result? = null
    private val picker = activity.activityResultRegistry.register(
        "mithka-save-folder",
        ActivityResultContracts.StartActivityForResult(),
    ) { response ->
        val pending = pickerResult
        pickerResult = null
        if (response.resultCode != android.app.Activity.RESULT_OK) {
            pending?.success(null)
        } else {
            try {
                val data = response.data ?: throw IOException("No folder selected")
                val uri = data.data ?: throw IOException("No folder selected")
                val flags = data.flags and (
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
                activity.contentResolver.takePersistableUriPermission(uri, flags)
                require(flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION != 0)
                val old = preferences.getString("save_tree", null)
                check(preferences.edit().putString("save_tree", uri.toString()).commit())
                if (old != null && old != uri.toString()) releaseGrant(Uri.parse(old))
                pending?.success(folderLabel(uri))
            } catch (error: Exception) {
                pending?.error("save_folder_failed", error.message, null)
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickSaveFolder" -> {
                if (pickerResult != null) {
                    result.error("picker_busy", "A folder picker is already open", null)
                    return
                }
                pickerResult = result
                try {
                    picker.launch(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                        addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                        )
                    })
                } catch (error: Exception) {
                    pickerResult = null
                    result.error("save_folder_failed", error.message, null)
                }
            }
            "saveFolder" -> run(result) {
                preferences.getString("save_tree", null)?.let { folderLabel(Uri.parse(it)) }
            }
            "resetSaveFolder" -> run(result) {
                val old = preferences.getString("save_tree", null)
                check(preferences.edit().remove("save_tree").commit())
                if (old != null) releaseGrant(Uri.parse(old))
                null
            }
            "copyDirectory" -> run(result) {
                val source = ownedFile(call.argument<String>("source")!!)
                val destination = ownedFile(call.argument<String>("destination")!!)
                require(!destination.toPath().startsWith(source.toPath()))
                copyDirectory(source, destination)
                null
            }
            "exportFile" -> run(result) {
                exportFile(
                    ownedFile(call.argument<String>("source")!!),
                    call.argument<String>("name")!!,
                    call.argument<String>("mimeType")!!,
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun run(result: MethodChannel.Result, action: () -> Any?) {
        executor.execute {
            try {
                val value = action()
                main.post { result.success(value) }
            } catch (error: Exception) {
                main.post { result.error("download_storage_failed", error.message, null) }
            }
        }
    }

    private fun ownedFile(path: String): File {
        val file = File(path).canonicalFile
        val roots = listOf(activity.filesDir, activity.cacheDir) +
            activity.getExternalFilesDirs(null).filterNotNull()
        require(roots.any { file.toPath().startsWith(it.canonicalFile.toPath()) }) {
            "The path is outside app-specific storage"
        }
        return file
    }

    private fun copyDirectory(source: File, destination: File) {
        check(source.isDirectory)
        check(destination.isDirectory || destination.mkdirs())
        for (entry in source.listFiles() ?: throw IOException("Cannot list source files")) {
            require(!Files.isSymbolicLink(entry.toPath())) { "Cannot migrate symbolic links" }
            val target = File(destination, entry.name)
            require(!Files.isSymbolicLink(target.toPath()))
            if (entry.isDirectory) {
                copyDirectory(entry, target)
            } else {
                val temporary = File.createTempFile(".mithka-copy-", ".tmp", destination)
                try {
                    // TDLib persists nanosecond mtimes. Dart/Java File timestamps
                    // truncate them, causing a migrated cache to be invalidated.
                    Files.copy(
                        entry.toPath(), temporary.toPath(),
                        StandardCopyOption.REPLACE_EXISTING,
                        StandardCopyOption.COPY_ATTRIBUTES,
                        LinkOption.NOFOLLOW_LINKS,
                    )
                    check(Files.size(entry.toPath()) == Files.size(temporary.toPath()))
                    check(
                        Files.getLastModifiedTime(entry.toPath()) ==
                            Files.getLastModifiedTime(temporary.toPath()),
                    ) { "The destination cannot preserve file timestamps" }
                    Files.move(
                        temporary.toPath(), target.toPath(),
                        StandardCopyOption.REPLACE_EXISTING,
                        StandardCopyOption.ATOMIC_MOVE,
                    )
                } finally {
                    temporary.delete()
                }
            }
        }
    }

    private fun folderLabel(tree: Uri): String {
        val document = DocumentsContract.buildDocumentUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree),
        )
        activity.contentResolver.query(
            document, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        throw IOException("The saved folder is unavailable; select it again")
    }

    private fun exportFile(source: File, name: String, mimeType: String): String {
        require(source.isFile)
        require(name.isNotBlank() && '/' !in name && '\\' !in name)
        val saved = preferences.getString("save_tree", null)
            ?: throw IOException("Select a save folder in storage settings")
        val tree = Uri.parse(saved)
        val parent = DocumentsContract.buildDocumentUriUsingTree(
            tree, DocumentsContract.getTreeDocumentId(tree),
        )
        val destination = DocumentsContract.createDocument(
            activity.contentResolver, parent, mimeType, name,
        ) ?: throw IOException("Cannot create the saved file")
        try {
            activity.contentResolver.openOutputStream(destination, "w")!!.use { output ->
                source.inputStream().use { input -> input.copyTo(output) }
            }
        } catch (error: Exception) {
            try {
                DocumentsContract.deleteDocument(activity.contentResolver, destination)
            } catch (_: Exception) {}
            throw error
        }
        return folderLabel(tree)
    }

    private fun releaseGrant(uri: Uri) {
        try {
            activity.contentResolver.releasePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {}
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        picker.unregister()
        pickerResult?.error("activity_closed", "The folder picker was closed", null)
        pickerResult = null
        executor.shutdown()
    }
}
