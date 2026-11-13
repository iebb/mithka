package ad.neko.mithka

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.verify.domain.DomainVerificationManager
import android.content.pm.verify.domain.DomainVerificationUserState
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Links that cross the app boundary.
 *
 * Mithka handles tg:// and (once the user approves t.me on Android 12+) t.me
 * links, so a generic VIEW intent for a link Mithka could not open in-app can
 * resolve straight back to Mithka. [openExternally] never lets that happen:
 * web links go to the user's browser, resolved explicitly, and other schemes
 * go to another handler with Mithka excluded.
 */
class ExternalLinksPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openExternally" -> {
                val uri = call.argument<String>("url")
                    ?.let { runCatching { Uri.parse(it) }.getOrNull() }
                if (uri == null || uri.scheme.isNullOrBlank()) {
                    result.success(false)
                    return
                }
                result.success(openExternally(uri))
            }
            "openByDefaultState" -> result.success(openByDefaultState())
            "openByDefaultSettings" -> result.success(openByDefaultSettings())
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    private fun openExternally(uri: Uri): Boolean {
        val intent = Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
        return try {
            when (uri.scheme?.lowercase()) {
                "http", "https" -> openInBrowser(intent)
                else -> openInOtherApp(intent)
            }
        } catch (error: Exception) {
            Log.w(TAG, "Unable to open link outside Mithka", error)
            false
        }
    }

    /**
     * Targets a browser package explicitly. The default browser is the one
     * that resolves a neutral https URL no app claims (never the app that owns
     * t.me); with no default set, the system chooser opens with Mithka
     * excluded.
     */
    private fun openInBrowser(intent: Intent): Boolean {
        val pm = activity.packageManager
        val own = activity.packageName
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse(NEUTRAL_WEB_URL))
            .addCategory(Intent.CATEGORY_BROWSABLE)
        val browsers = pm.queryIntentActivities(probe, PackageManager.MATCH_DEFAULT_ONLY)
            .map { it.activityInfo.packageName }
            .filter { it != own }
            .distinct()
        // With no default set this resolves to the system resolver (package
        // "android" or an OEM resolver), which is not in [browsers].
        val defaultBrowser = pm.resolveActivity(probe, PackageManager.MATCH_DEFAULT_ONLY)
            ?.activityInfo
            ?.packageName
            ?.takeIf { it in browsers }
        val target = defaultBrowser ?: browsers.singleOrNull()
        if (target != null && start(Intent(intent).setPackage(target))) return true
        return startChooserExcludingSelf(intent)
    }

    /** Hands a non-web link (tg://) to another handler, excluding Mithka. */
    private fun openInOtherApp(intent: Intent): Boolean {
        val own = activity.packageName
        val others = activity.packageManager
            .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .filter { it.activityInfo.packageName != own }
        if (others.isEmpty()) return false
        if (others.size == 1) {
            return start(Intent(intent).setPackage(others.single().activityInfo.packageName))
        }
        return startChooserExcludingSelf(intent)
    }

    /** The system chooser for [intent] with every Mithka activity removed. */
    private fun startChooserExcludingSelf(intent: Intent): Boolean {
        val own = activity.packageName
        val ownComponents = activity.packageManager
            .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .filter { it.activityInfo.packageName == own }
            .map { ComponentName(own, it.activityInfo.name) }
            .ifEmpty { listOf(ComponentName(own, MainActivity::class.java.name)) }
            .toTypedArray()
        val chooser = Intent.createChooser(intent, null)
            .putExtra(Intent.EXTRA_EXCLUDE_COMPONENTS, ownComponents)
        return start(chooser)
    }

    private fun start(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (_: ActivityNotFoundException) {
        false
    } catch (error: SecurityException) {
        Log.w(TAG, "Link handler refused the launch", error)
        false
    }

    private fun openByDefaultState(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return mapOf("supported" to false)
        }
        return mapOf("supported" to true, "tmeApproved" to tmeApproved())
    }

    @RequiresApi(Build.VERSION_CODES.S)
    private fun tmeApproved(): Boolean? = try {
        val manager = activity.getSystemService(DomainVerificationManager::class.java)
        val state = manager?.getDomainVerificationUserState(activity.packageName)
        state?.let {
            val host = it.hostToStateMap["t.me"]
            it.isLinkHandlingAllowed &&
                (host == DomainVerificationUserState.DOMAIN_STATE_SELECTED ||
                    host == DomainVerificationUserState.DOMAIN_STATE_VERIFIED)
        }
    } catch (error: Exception) {
        Log.w(TAG, "Unable to read link handling state", error)
        null
    }

    private fun openByDefaultSettings(): Boolean {
        val data = Uri.parse("package:${activity.packageName}")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            start(Intent(Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS, data))
        ) {
            return true
        }
        return start(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, data))
    }

    companion object {
        private const val CHANNEL = "mithka/external_links"
        private const val TAG = "ExternalLinks"

        // A web URL no app claims as an app link, so it resolves to the
        // user's default browser rather than to whichever app owns t.me.
        private const val NEUTRAL_WEB_URL = "https://example.com/"
    }
}
