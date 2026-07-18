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
 * Stores only explicitly selected, compact TDLib session exports in the one
 * directory admitted by Mithka's Android backup rules.
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
    private val backupDirectory = File(appContext.filesDir, BACKUP_DIRECTORY)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "isSupported" -> result.success(true)
                "saveSession" -> {
                    val id = requiredId(call)
                    val data = call.argument<ByteArray>("data")
                        ?: throw IllegalArgumentException("Missing session data")
                    require(data.isNotEmpty()) { "Session data is empty" }
                    require(data.size <= MAX_SESSION_BYTES) { "Session data is too large" }
                    saveSession(id, data)
                    result.success(null)
                }
                "getAllSessions" -> result.success(getAllSessions())
                "deleteSession" -> {
                    deleteSession(requiredId(call))
                    result.success(null)
                }
                "deleteAllSessions" -> {
                    deleteAllSessions()
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

    private fun saveSession(id: String, data: ByteArray) {
        ensureBackupDirectory()
        val atomicFile = AtomicFile(sessionFile(id))
        val stream = atomicFile.startWrite()
        try {
            stream.write(data)
            atomicFile.finishWrite(stream)
        } catch (error: Exception) {
            atomicFile.failWrite(stream)
            throw error
        }
        BackupManager(appContext).dataChanged()
    }

    private fun getAllSessions(): List<ByteArray> {
        if (!backupDirectory.isDirectory) return emptyList()
        return backupDirectory
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

    private fun deleteSession(id: String) {
        val file = sessionFile(id)
        val existed = file.exists() || File("${file.path}.bak").exists()
        AtomicFile(file).delete()
        if (existed) {
            removeDirectoryIfEmpty()
            BackupManager(appContext).dataChanged()
        }
    }

    private fun deleteAllSessions() {
        if (!backupDirectory.isDirectory) return
        var changed = false
        backupDirectory.listFiles().orEmpty().forEach { file ->
            if (file.isFile && file.name.endsWith(SESSION_SUFFIX)) {
                AtomicFile(file).delete()
                changed = true
            }
        }
        removeDirectoryIfEmpty()
        if (changed) BackupManager(appContext).dataChanged()
    }

    private fun ensureBackupDirectory() {
        check(backupDirectory.isDirectory || backupDirectory.mkdirs()) {
            "Could not create the account backup directory"
        }
    }

    private fun removeDirectoryIfEmpty() {
        if (backupDirectory.listFiles().isNullOrEmpty()) backupDirectory.delete()
    }

    private fun sessionFile(id: String): File {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(id.toByteArray(Charsets.UTF_8))
            .joinToString(separator = "") { byte -> "%02x".format(byte) }
        return File(backupDirectory, "$digest$SESSION_SUFFIX")
    }

    companion object {
        private const val CHANNEL = "mithka/account_backup"
        private const val BACKUP_DIRECTORY = "account_backups"
        private const val SESSION_SUFFIX = ".session"
        private const val MAX_ACCOUNT_ID_LENGTH = 256
        private const val MAX_SESSION_BYTES = 1024 * 1024
    }
}
