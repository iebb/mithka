package ad.neko.mithka.system_picture_in_picture

import android.app.Activity
import android.app.AppOpsManager
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Rect
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Process
import android.util.Rational
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import kotlin.math.roundToInt

/** Included Android implementation of Mithka's shared system-PiP channel. */
class SystemPictureInPicturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var preparedId: String? = null
    private val preparedArguments = mutableMapOf<String, Any?>()
    private var activityStarted = false
    private var inPictureInPicture = false
    private var exitPending = false
    private var receiverRegistered = false

    private val actionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != actionIntentName()) return
            val id = intent.getStringExtra(EXTRA_ID) ?: return
            if (id != preparedId) return
            val action = intent.getStringExtra(EXTRA_ACTION) ?: return
            if (action != ACTION_PLAY && action != ACTION_PAUSE) return
            preparedArguments["playing"] = action == ACTION_PLAY
            applyPictureInPictureParams()
            invoke("actionRequested", mapOf("id" to id, "action" to action))
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
        currentPlugin = WeakReference(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        unregisterActionReceiver()
        channel?.setMethodCallHandler(null)
        channel = null
        clearPreparedSession(resetParams = false)
        if (currentPlugin?.get() === this) currentPlugin = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        registerActionReceiver()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unregisterActionReceiver()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        registerActionReceiver()
        applyPictureInPictureParams()
    }

    override fun onDetachedFromActivity() {
        unregisterActionReceiver()
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "prepare" -> result.success(prepare(call.arguments as? Map<*, *>))
            "startPrepared" -> result.success(startPrepared(call.arguments as? Map<*, *>))
            "update" -> {
                update(call.arguments as? Map<*, *>)
                result.success(null)
            }
            "cancel" -> {
                val requestedId = call.argument<String>("id")
                if (requestedId == null || requestedId == preparedId) {
                    clearPreparedSession(resetParams = !inPictureInPicture)
                }
                result.success(null)
            }
            "stop" -> {
                clearPreparedSession(resetParams = !inPictureInPicture)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun prepare(arguments: Map<*, *>?): Boolean {
        if (!isSupported()) return false
        val id = arguments?.get("id") as? String ?: return false
        preparedId = id
        preparedArguments.clear()
        mergeArguments(arguments)
        applyPictureInPictureParams()
        return true
    }

    private fun update(arguments: Map<*, *>?) {
        val id = arguments?.get("id") as? String ?: return
        if (id != preparedId) return
        mergeArguments(arguments)
        applyPictureInPictureParams()
    }

    private fun isSupported(): Boolean {
        val currentActivity = activity ?: return false
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            currentActivity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE) &&
            hasPictureInPicturePermission(currentActivity)
    }

    /** Mirrors Telegram Android's feature and AppOps PiP availability check. */
    private fun hasPictureInPicturePermission(activity: Activity): Boolean {
        val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return false
        val mode = appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
            Process.myUid(),
            activity.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED || mode == AppOpsManager.MODE_DEFAULT
    }

    private fun startPrepared(arguments: Map<*, *>?): Boolean {
        if (!isSupported()) return false
        val id = arguments?.get("id") as? String ?: return false
        if (id != preparedId) return false
        mergeArguments(arguments)
        applyPictureInPictureParams()
        return enterPictureInPictureManually()
    }

    private fun enterPictureInPictureManually(): Boolean {
        val currentActivity = activity ?: return false
        if (!isSupported() || preparedId == null || inPictureInPicture) return false
        if (preparedArguments["playing"] != true) return false
        val params = paramsForPreparedSession() ?: return false
        return try {
            val entered = currentActivity.enterPictureInPictureMode(params)
            if (entered) notifyStarted()
            entered
        } catch (_: IllegalArgumentException) {
            false
        } catch (_: IllegalStateException) {
            false
        }
    }

    private fun applyPictureInPictureParams() {
        val currentActivity = activity ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val params = paramsForPreparedSession() ?: return
        try {
            currentActivity.setPictureInPictureParams(params)
        } catch (_: IllegalArgumentException) {
            // Some vendor builds apply stricter expanded-ratio validation.
        } catch (_: IllegalStateException) {
            // The Activity may be between detach and configuration reattach.
        }
    }

    private fun paramsForPreparedSession(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val builder = PictureInPictureParams.Builder()
        aspectRatio()?.let { ratio ->
            builder.setAspectRatio(ratio)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                try {
                    builder.setExpandedAspectRatio(ratio)
                } catch (_: IllegalArgumentException) {
                    // Keep the normal PiP ratio if expanded PiP rejects it.
                }
            }
        }
        sourceRect()?.let(builder::setSourceRectHint)
        builder.setActions(remoteActions())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(
                preparedId != null && preparedArguments["playing"] == true,
            )
        }
        return try {
            builder.build()
        } catch (_: IllegalArgumentException) {
            // Rebuild without the optional expanded ratio on strict devices.
            fallbackParams()
        }
    }

    private fun fallbackParams(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val builder = PictureInPictureParams.Builder()
        aspectRatio()?.let(builder::setAspectRatio)
        sourceRect()?.let(builder::setSourceRectHint)
        builder.setActions(remoteActions())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(
                preparedId != null && preparedArguments["playing"] == true,
            )
        }
        return try {
            builder.build()
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun aspectRatio(): Rational? {
        val width = (preparedArguments["width"] as? Number)?.toDouble() ?: 0.0
        val height = (preparedArguments["height"] as? Number)?.toDouble() ?: 0.0
        if (!width.isFinite() || !height.isFinite() || width <= 0 || height <= 0) return null
        val ratio = width / height
        return when {
            ratio < MIN_ASPECT_RATIO -> Rational(45, 100)
            ratio > MAX_ASPECT_RATIO -> Rational(235, 100)
            else -> Rational(width.roundToInt().coerceAtLeast(1), height.roundToInt().coerceAtLeast(1))
        }
    }

    private fun sourceRect(): Rect? {
        val currentActivity = activity ?: return null
        val left = (preparedArguments["sourceLeft"] as? Number)?.toInt() ?: return null
        val top = (preparedArguments["sourceTop"] as? Number)?.toInt() ?: return null
        val right = (preparedArguments["sourceRight"] as? Number)?.toInt() ?: return null
        val bottom = (preparedArguments["sourceBottom"] as? Number)?.toInt() ?: return null
        val decor = currentActivity.window.decorView
        val clipped = Rect(
            left.coerceIn(0, decor.width),
            top.coerceIn(0, decor.height),
            right.coerceIn(0, decor.width),
            bottom.coerceIn(0, decor.height),
        )
        return clipped.takeUnless(Rect::isEmpty)
    }

    private fun remoteActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return emptyList()
        val currentActivity = activity ?: return emptyList()
        val id = preparedId ?: return emptyList()
        val playing = preparedArguments["playing"] == true
        val action = if (playing) ACTION_PAUSE else ACTION_PLAY
        val label = ((if (playing) preparedArguments["pauseLabel"] else preparedArguments["playLabel"])
            as? String)?.takeIf(String::isNotBlank) ?: if (playing) "Pause" else "Play"
        val iconResource = if (playing) R.drawable.mithka_pip_pause else R.drawable.mithka_pip_play
        val intent = Intent(actionIntentName())
            .setPackage(currentActivity.packageName)
            .putExtra(EXTRA_ID, id)
            .putExtra(EXTRA_ACTION, action)
        val pendingIntent = PendingIntent.getBroadcast(
            currentActivity,
            id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return listOf(
            RemoteAction(
                Icon.createWithResource(currentActivity, iconResource),
                label,
                label,
                pendingIntent,
            ),
        )
    }

    private fun mergeArguments(arguments: Map<*, *>?) {
        arguments?.forEach { (key, value) ->
            if (key is String && value != null) preparedArguments[key] = value
        }
    }

    private fun notifyStarted() {
        if (inPictureInPicture) return
        val id = preparedId ?: return
        inPictureInPicture = true
        exitPending = false
        invoke("didStart", callbackArguments(id))
    }

    private fun notifyRestored() {
        if (!inPictureInPicture) return
        val id = preparedId ?: return
        inPictureInPicture = false
        exitPending = false
        invoke("didRestore", callbackArguments(id))
        applyPictureInPictureParams()
    }

    private fun notifyStopped() {
        if (!inPictureInPicture) return
        val id = preparedId ?: return
        val arguments = callbackArguments(id)
        inPictureInPicture = false
        exitPending = false
        clearPreparedSession(resetParams = false)
        invoke("didStop", arguments)
    }

    private fun callbackArguments(id: String): Map<String, Any?> = mapOf(
        "id" to id,
        "positionMs" to ((preparedArguments["positionMs"] as? Number)?.toLong() ?: 0L),
        "playing" to (preparedArguments["playing"] == true),
        "speed" to ((preparedArguments["speed"] as? Number)?.toDouble() ?: 1.0),
        "muted" to (preparedArguments["muted"] == true),
    )

    private fun clearPreparedSession(resetParams: Boolean) {
        preparedId = null
        preparedArguments.clear()
        exitPending = false
        if (resetParams) applyEmptyPictureInPictureParams()
    }

    private fun applyEmptyPictureInPictureParams() {
        val currentActivity = activity ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val builder = PictureInPictureParams.Builder().setActions(emptyList())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(false)
        }
        try {
            currentActivity.setPictureInPictureParams(builder.build())
        } catch (_: IllegalArgumentException) {
        } catch (_: IllegalStateException) {
        }
    }

    private fun invoke(method: String, arguments: Map<String, Any?>) {
        activity?.runOnUiThread { channel?.invokeMethod(method, arguments) }
    }

    private fun actionIntentName(): String =
        "${activity?.packageName ?: "ad.neko.mithka"}.mithka.PICTURE_IN_PICTURE_ACTION"

    private fun registerActionReceiver() {
        val currentActivity = activity ?: return
        if (receiverRegistered) return
        val filter = IntentFilter(actionIntentName())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            currentActivity.registerReceiver(actionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            currentActivity.registerReceiver(actionReceiver, filter)
        }
        receiverRegistered = true
    }

    private fun unregisterActionReceiver() {
        val currentActivity = activity ?: return
        if (!receiverRegistered) return
        try {
            currentActivity.unregisterReceiver(actionReceiver)
        } catch (_: IllegalArgumentException) {
        }
        receiverRegistered = false
    }

    private fun handleActivityStarted(activity: Activity) {
        if (this.activity !== activity) return
        activityStarted = true
        registerActionReceiver()
    }

    private fun handleActivityResumed(activity: Activity) {
        if (this.activity !== activity) return
        if (inPictureInPicture && exitPending && !activity.isInPictureInPictureMode) {
            notifyRestored()
        }
    }

    private fun handleActivityPaused(activity: Activity) {
        if (this.activity !== activity) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            activity.isInPictureInPictureMode &&
            preparedArguments["playing"] == true
        ) {
            notifyStarted()
        }
    }

    private fun handleActivityStopped(activity: Activity) {
        if (this.activity !== activity) return
        activityStarted = false
        if (inPictureInPicture) notifyStopped()
        unregisterActionReceiver()
    }

    private fun handleActivityDestroyed(activity: Activity) {
        if (this.activity !== activity) return
        if (inPictureInPicture) notifyStopped()
        unregisterActionReceiver()
    }

    private fun handleUserLeaveHint(activity: Activity): Boolean {
        if (this.activity !== activity || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return false
        return enterPictureInPictureManually()
    }

    private fun handlePictureInPictureRequested(activity: Activity): Boolean {
        if (this.activity !== activity || Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return false
        return enterPictureInPictureManually()
    }

    private fun handlePictureInPictureModeChanged(
        activity: Activity,
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        if (this.activity !== activity) return
        if (isInPictureInPictureMode) {
            notifyStarted()
        } else if (inPictureInPicture) {
            if (activityStarted) {
                exitPending = true
            } else {
                notifyStopped()
            }
        }
    }

    companion object {
        private const val CHANNEL_NAME = "mithka/system_picture_in_picture"
        private const val EXTRA_ID = "mithka_pip_id"
        private const val EXTRA_ACTION = "mithka_pip_action"
        private const val ACTION_PLAY = "play"
        private const val ACTION_PAUSE = "pause"
        private const val MIN_ASPECT_RATIO = 0.45
        private const val MAX_ASPECT_RATIO = 2.35
        private var currentPlugin: WeakReference<SystemPictureInPicturePlugin>? = null

        @JvmStatic
        fun onActivityStarted(activity: Activity) = currentPlugin?.get()?.handleActivityStarted(activity)

        @JvmStatic
        fun onActivityResumed(activity: Activity) = currentPlugin?.get()?.handleActivityResumed(activity)

        @JvmStatic
        fun onActivityPaused(activity: Activity) = currentPlugin?.get()?.handleActivityPaused(activity)

        @JvmStatic
        fun onActivityStopped(activity: Activity) = currentPlugin?.get()?.handleActivityStopped(activity)

        @JvmStatic
        fun onActivityDestroyed(activity: Activity) = currentPlugin?.get()?.handleActivityDestroyed(activity)

        @JvmStatic
        fun onUserLeaveHint(activity: Activity): Boolean =
            currentPlugin?.get()?.handleUserLeaveHint(activity) == true

        @JvmStatic
        fun onPictureInPictureRequested(activity: Activity): Boolean =
            currentPlugin?.get()?.handlePictureInPictureRequested(activity) == true

        @JvmStatic
        fun onPictureInPictureModeChanged(
            activity: Activity,
            isInPictureInPictureMode: Boolean,
            newConfig: Configuration,
        ) = currentPlugin?.get()?.handlePictureInPictureModeChanged(
            activity,
            isInPictureInPictureMode,
            newConfig,
        )
    }
}
