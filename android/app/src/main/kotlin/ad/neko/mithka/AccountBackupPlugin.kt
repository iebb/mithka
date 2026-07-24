package ad.neko.mithka

import android.app.backup.BackupManager
import android.content.Context
import android.util.AtomicFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

/**
 * Stores only explicitly selected, compact TDLib session exports. Synced
 * copies use Mithka's Android backup directory; device-only copies use
 * noBackupFilesDir so Android backup and device transfer exclude them.
 *
 * The session contents are deliberately opaque here. Flutter creates and
 * validates the payload; Android only gives it an account-scoped, atomic file.
 * Filenames are hashes so account identifiers never become paths or backup
 * metadata.
 */
class AccountBackupPlugin(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val appContext = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val syncedBackupDirectory = File(appContext.filesDir, BACKUP_DIRECTORY)
    private val localBackupDirectory = File(appContext.noBackupFilesDir, LOCAL_BACKUP_DIRECTORY)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isSupported" -> result.success(true)
                "isLocalStorageSupported" -> result.success(true)
                "saveSession" -> {
                    val id = requiredId(call)
                    val data = call.argument<ByteArray>("data")
                        ?: throw IllegalArgumentException("Missing session data")
                    require(data.isNotEmpty()) { "Session data is empty" }
                    require(data.size <= MAX_SESSION_BYTES) { "Session data is too large" }
                    saveSession(id, data, storageDirectory(call), isLocal(call))
                    result.success(null)
                }
                "getAllSessions" -> result.success(getAllSessions(storageDirectory(call)))
                "deleteSession" -> {
                    deleteSession(requiredId(call), storageDirectory(call), isLocal(call))
                    result.success(null)
                }
                "deleteAllSessions" -> {
                    deleteAllSessions(storageDirectory(call), isLocal(call))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            // Never attach payloads or account identifiers to platform errors.
            result.error("account_backup_failed", error.localizedMessage, null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun requiredId(call: MethodCall): String {
        val id = call.argument<String>("id")?.trim().orEmpty()
        require(id.isNotEmpty()) { "Missing account id" }
        require(id.length <= MAX_ACCOUNT_ID_LENGTH) { "Account id is too long" }
        return id
    }

    private fun isLocal(call: MethodCall): Boolean =
        call.argument<String>("storage") == LOCAL_STORAGE

    private fun storageDirectory(call: MethodCall): File =
        if (isLocal(call)) localBackupDirectory else syncedBackupDirectory

    private fun saveSession(id: String, data: ByteArray, directory: File, local: Boolean) {
        ensureBackupDirectory(directory)
        val atomicFile = AtomicFile(sessionFile(id, directory))
        val stream = atomicFile.startWrite()
        try {
            stream.write(data)
            atomicFile.finishWrite(stream)
        } catch (error: Exception) {
            atomicFile.failWrite(stream)
            throw error
        }
        if (!local) BackupManager(appContext).dataChanged()
    }

    private fun getAllSessions(directory: File): List<ByteArray> {
        if (!directory.isDirectory) return emptyList()
        return directory
            .listFiles { file -> file.isFile && file.name.endsWith(SESSION_SUFFIX) }
            .orEmpty()
            .sortedByDescending(File::lastModified)
            .mapNotNull { file ->
                if (file.length() !in 1..MAX_SESSION_BYTES.toLong()) {
                    null
                } else {
                    runCatching { AtomicFile(file).readFully() }.getOrNull()
                }
            }
    }

    private fun deleteSession(id: String, directory: File, local: Boolean) {
        val file = sessionFile(id, directory)
        val existed = file.exists() || File("${file.path}.bak").exists()
        AtomicFile(file).delete()
        if (existed) {
            removeDirectoryIfEmpty(directory)
            if (!local) BackupManager(appContext).dataChanged()
        }
    }

    private fun deleteAllSessions(directory: File, local: Boolean) {
        if (!directory.isDirectory) return
        var changed = false
        directory.listFiles().orEmpty().forEach { file ->
            if (file.isFile && file.name.endsWith(SESSION_SUFFIX)) {
                AtomicFile(file).delete()
                changed = true
            }
        }
        removeDirectoryIfEmpty(directory)
        if (changed && !local) BackupManager(appContext).dataChanged()
    }

    private fun ensureBackupDirectory(directory: File) {
        check(directory.isDirectory || directory.mkdirs()) {
            "Could not create the account backup directory"
        }
    }

    private fun removeDirectoryIfEmpty(directory: File) {
        if (directory.listFiles().isNullOrEmpty()) directory.delete()
    }

    private fun sessionFile(id: String, directory: File): File {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(id.toByteArray(Charsets.UTF_8))
            .joinToString(separator = "") { byte -> "%02x".format(byte) }
        return File(directory, "$digest$SESSION_SUFFIX")
    }

    companion object {
        private const val CHANNEL = "mithka/account_backup"
        private const val BACKUP_DIRECTORY = "account_backups"
        private const val LOCAL_BACKUP_DIRECTORY = "account_backups_local"
        private const val LOCAL_STORAGE = "local"
        private const val SESSION_SUFFIX = ".session"
        private const val MAX_ACCOUNT_ID_LENGTH = 256
        private const val MAX_SESSION_BYTES = 1024 * 1024
    }
}
