package ad.neko.mithka.system_picture_in_picture

import android.app.Activity
import android.app.AppOpsManager
import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.util.Rational
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Included Android implementation of Mithka's shared system-PiP channel. */
class SystemPictureInPicturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var preparedId: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "mithka/system_picture_in_picture")
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        preparedId = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(isSupported())
            "prepare" -> {
                preparedId = call.argument<String>("id")
                result.success(preparedId != null && isSupported())
            }
            "startPrepared" -> result.success(startPrepared(call.arguments as? Map<*, *>))
            "update" -> {
                updateParams(call.arguments as? Map<*, *>)
                result.success(null)
            }
            "cancel" -> {
                val requestedId = call.argument<String>("id")
                if (requestedId == null || requestedId == preparedId) preparedId = null
                result.success(null)
            }
            "stop" -> {
                preparedId = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
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
        return appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
            Process.myUid(),
            activity.packageName,
        ) == AppOpsManager.MODE_ALLOWED
    }

    private fun startPrepared(arguments: Map<*, *>?): Boolean {
        val currentActivity = activity ?: return false
        if (!isSupported()) return false
        val id = arguments?.get("id") as? String ?: return false
        if (id != preparedId) return false
        return try {
            currentActivity.enterPictureInPictureMode(paramsFor(arguments))
        } catch (_: IllegalStateException) {
            false
        }
    }

    private fun updateParams(arguments: Map<*, *>?) {
        val currentActivity = activity ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            !currentActivity.isInPictureInPictureMode
        ) return
        currentActivity.setPictureInPictureParams(paramsFor(arguments))
    }

    private fun paramsFor(arguments: Map<*, *>?): PictureInPictureParams {
        val width = (arguments?.get("width") as? Number)?.toInt() ?: 0
        val height = (arguments?.get("height") as? Number)?.toInt() ?: 0
        val builder = PictureInPictureParams.Builder()
        if (width > 0 && height > 0) {
            val ratio = width.toDouble() / height.toDouble()
            val aspectRatio = when {
                ratio < 0.45 -> Rational(45, 100)
                ratio > 2.35 -> Rational(235, 100)
                else -> Rational(width, height)
            }
            builder.setAspectRatio(aspectRatio)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(false)
        }
        return builder.build()
    }
}
