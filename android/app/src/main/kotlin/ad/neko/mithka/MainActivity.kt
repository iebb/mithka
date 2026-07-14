package ad.neko.mithka

import android.content.ClipboardManager
import android.content.ComponentName
import android.content.Context
import android.content.ClipDescription
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.view.DragEvent
import android.view.WindowManager
import android.webkit.MimeTypeMap
import androidx.core.view.WindowCompat
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory

class MainActivity : FlutterActivity() {
    private var callMedia: CallMediaPlugin? = null
    private var mediaDropChannel: MethodChannel? = null
    private var acceptingImageDrop = false
    private val translators = mutableMapOf<String, Translator>()

    override fun onCreate(savedInstanceState: Bundle?) {
        // Let Flutter paint under the status bar and gesture/nav bar.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        registerPlugins(flutterEngine)
        val plugin = CallMediaPlugin(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        callMedia = plugin
        // Embed call video surfaces (TextureViewRenderer) into the widget tree.
        flutterEngine.platformViewsController.registry
            .registerViewFactory("mithka/video_view", VideoViewFactory(plugin))

        // App info for the GitHub-release update checker: the device's supported
        // ABIs (preference-ordered, so we can match the right per-ABI APK asset)
        // and the installed version name (the semver compared to the latest tag).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/app_info")
            .setMethodCallHandler { call, result ->
                if (call.method == "info") {
                    val pkg = packageManager.getPackageInfo(packageName, 0)
                    result.success(
                        mapOf(
                            "abis" to Build.SUPPORTED_ABIS.toList(),
                            "version" to (pkg.versionName ?: ""),
                            "sdkInt" to Build.VERSION.SDK_INT,
                        ),
                    )
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mithka/firebase_configuration",
        ).setMethodCallHandler { call, result ->
            if (call.method != "isAvailable") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val appIdResource = resources.getIdentifier("google_app_id", "string", packageName)
            val appId = if (appIdResource == 0) "" else getString(appIdResource)
            result.success(appId.isNotBlank())
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/app_icon")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(true)
                    "currentIcon" -> result.success(currentLauncherIcon())
                    "setIcon" -> {
                        val args = call.arguments as? Map<*, *>
                        val name = args?.get("name") as? String ?: "default"
                        try {
                            setLauncherIcon(name)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("app_icon_failed", e.localizedMessage, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/native_translation")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capabilities" -> {
                        result.success(listOf("android_mlkit"))
                        return@setMethodCallHandler
                    }
                    "translate" -> {
                        translateOnDevice(call.arguments as? Map<*, *>, result)
                        return@setMethodCallHandler
                    }
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/fonts")
            .setMethodCallHandler { call, result ->
                if (call.method == "listFonts") {
                    result.success(listSystemFonts())
                } else {
                    result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/screen_wakelock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enable" -> {
                        runOnUiThread {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    "disable" -> {
                        runOnUiThread {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/player_brightness")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "get" -> {
                        val windowValue = window.attributes.screenBrightness
                        val value = if (windowValue >= 0f) windowValue else {
                            Settings.System.getInt(
                                contentResolver,
                                Settings.System.SCREEN_BRIGHTNESS,
                                128,
                            ) / 255f
                        }
                        result.success(value.toDouble())
                    }
                    "set" -> {
                        val value = (call.arguments as? Number)?.toFloat()
                        if (value == null) {
                            result.error("invalid_brightness", "Expected a numeric value", null)
                        } else {
                            runOnUiThread {
                                val attributes = window.attributes
                                attributes.screenBrightness = value.coerceIn(0.01f, 1f)
                                window.attributes = attributes
                            }
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/clipboard")
            .setMethodCallHandler { call, result ->
                var clipboardDescription: ClipDescription? = null
                val requestedMimeType: String?
                val uri = when (call.method) {
                    "readImage" -> {
                        val clipboard =
                            getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                        val clip = clipboard.primaryClip
                        if (clip == null || clip.itemCount == 0) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        clipboardDescription = clip.description
                        requestedMimeType = null
                        clip.getItemAt(0).uri
                    }
                    "readImageUri" -> {
                        requestedMimeType = call.argument<String>("mimeType")
                        call.argument<String>("uri")?.let(Uri::parse)
                    }
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                if (uri == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val mimeType = contentResolver.getType(uri)
                    ?: requestedMimeType
                    ?: clipboardDescription?.getMimeType(0)
                    ?: "image/png"
                if (!mimeType.startsWith("image/")) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                try {
                    contentResolver.openInputStream(uri).use { input ->
                        if (input == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val output = ByteArrayOutputStream()
                        input.copyTo(output)
                        result.success(
                            mapOf(
                                "mimeType" to mimeType,
                                "data" to output.toByteArray(),
                            ),
                        )
                    }
                } catch (e: Exception) {
                    result.error("clipboard_unavailable", e.message, null)
                }
            }
        mediaDropChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mithka/media_drop",
        )
        window.decorView.setOnDragListener { _, event -> handleMediaDragEvent(event) }
    }

    private fun handleMediaDragEvent(event: DragEvent): Boolean {
        when (event.action) {
            DragEvent.ACTION_DRAG_STARTED -> {
                acceptingImageDrop =
                    event.clipDescription?.hasMimeType("image/*") == true ||
                    event.clipDescription?.hasMimeType(ClipDescription.MIMETYPE_TEXT_URILIST) == true
                if (acceptingImageDrop) {
                    mediaDropChannel?.invokeMethod("dragEntered", null)
                    return true
                }
            }
            DragEvent.ACTION_DRAG_ENTERED -> {
                if (acceptingImageDrop) {
                    mediaDropChannel?.invokeMethod("dragEntered", null)
                    return true
                }
            }
            DragEvent.ACTION_DRAG_LOCATION -> if (acceptingImageDrop) return true
            DragEvent.ACTION_DRAG_EXITED -> {
                if (acceptingImageDrop) {
                    mediaDropChannel?.invokeMethod("dragExited", null)
                    return true
                }
            }
            DragEvent.ACTION_DROP -> {
                if (!acceptingImageDrop) return false
                val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    requestDragAndDropPermissions(event)
                } else {
                    null
                }
                val uris = buildList {
                    val clip = event.clipData
                    for (index in 0 until minOf(clip.itemCount, 10)) {
                        clip.getItemAt(index).uri?.let(::add)
                    }
                }
                Thread {
                    val paths = uris.mapNotNull { uri ->
                        val mimeType = contentResolver.getType(uri) ?: return@mapNotNull null
                        if (!mimeType.startsWith("image/")) return@mapNotNull null
                        try {
                            val extension = MimeTypeMap.getSingleton()
                                .getExtensionFromMimeType(mimeType)
                                ?.takeIf { it.matches(Regex("^[A-Za-z0-9]{2,5}$")) }
                                ?: "png"
                            val destination = File(
                                cacheDir,
                                "mithka-drop-${System.nanoTime()}.$extension",
                            )
                            contentResolver.openInputStream(uri).use { input ->
                                if (input == null) return@mapNotNull null
                                destination.outputStream().use(input::copyTo)
                            }
                            destination.absolutePath
                        } catch (error: Exception) {
                            Log.w("Mithka", "Unable to read dropped image", error)
                            null
                        }
                    }
                    runOnUiThread {
                        permissions?.release()
                        mediaDropChannel?.invokeMethod("dropImages", paths)
                    }
                }.start()
                acceptingImageDrop = false
                return true
            }
            DragEvent.ACTION_DRAG_ENDED -> {
                if (acceptingImageDrop) {
                    mediaDropChannel?.invokeMethod("dragExited", null)
                    acceptingImageDrop = false
                    return true
                }
            }
        }
        return false
    }

    private fun launcherAliases(): Map<String, String> = mapOf(
        "default" to "$packageName.MainActivityDefault",
        "white" to "$packageName.MainActivityWhite",
        "blue" to "$packageName.MainActivityBlue",
        "purple" to "$packageName.MainActivityPurple",
        "pixel" to "$packageName.MainActivityPixel",
    )

    private fun currentLauncherIcon(): String {
        val aliases = launcherAliases()
        for ((key, className) in aliases) {
            val component = ComponentName(packageName, className)
            val state = packageManager.getComponentEnabledSetting(component)
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                return key
            }
        }
        return "default"
    }

    private fun setLauncherIcon(name: String) {
        val aliases = launcherAliases()
        val target = if (aliases.containsKey(name)) name else "default"

        // Enable the target alias first so there's never a window where no
        // launcher icon alias is active — that can cause a crash when the
        // user returns to the launcher before the switch completes.
        val targetComponent = ComponentName(packageName, aliases[target]!!)
        packageManager.setComponentEnabledSetting(
            targetComponent,
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
            PackageManager.DONT_KILL_APP,
        )

        for ((key, className) in aliases) {
            if (key == target) continue
            val component = ComponentName(packageName, className)
            packageManager.setComponentEnabledSetting(
                component,
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
        }
    }

    private fun listSystemFonts(): List<String> {
        val fonts = linkedSetOf(
            "sans-serif",
            "sans-serif-condensed",
            "serif",
            "monospace",
            "Roboto",
            "Noto Sans",
            "Noto Sans CJK SC",
            "Noto Sans CJK TC",
            "Noto Sans JP",
            "Noto Sans KR",
        )
        val paths = listOf(
            "/system/etc/fonts.xml",
            "/system/etc/system_fonts.xml",
            "/product/etc/fonts.xml",
            "/vendor/etc/fonts.xml",
        )
        for (path in paths) {
            val file = File(path)
            if (!file.exists() || !file.canRead()) continue
            try {
                FileInputStream(file).use { input ->
                    val parser = XmlPullParserFactory.newInstance().newPullParser()
                    parser.setInput(input, null)
                    var event = parser.eventType
                    while (event != XmlPullParser.END_DOCUMENT) {
                        if (event == XmlPullParser.START_TAG) {
                            when (parser.name) {
                                "family" -> parser.getAttributeValue(null, "name")
                                    ?.let { addFontFamily(fonts, it) }
                                "alias" -> {
                                    if (parser.getAttributeValue(null, "weight").isNullOrBlank()) {
                                        parser.getAttributeValue(null, "name")
                                            ?.let { addFontFamily(fonts, it) }
                                    }
                                    parser.getAttributeValue(null, "to")
                                        ?.let { addFontFamily(fonts, it) }
                                }
                            }
                        }
                        event = parser.next()
                    }
                }
            } catch (e: Exception) {
                Log.w("Mithka", "Failed to read font list from $path", e)
            }
        }
        return fonts.sortedWith(String.CASE_INSENSITIVE_ORDER)
    }

    private fun addFontFamily(fonts: MutableSet<String>, name: String) {
        val family = name.trim()
        if (family.isEmpty() || isWeightedFontAlias(family)) return
        fonts.add(family)
    }

    private fun isWeightedFontAlias(name: String): Boolean {
        val normalized = name.lowercase()
        val suffixes = listOf(
            "-thin",
            "-extralight",
            "-ultralight",
            "-light",
            "-regular",
            "-medium",
            "-semibold",
            "-demibold",
            "-bold",
            "-extrabold",
            "-ultrabold",
            "-black",
            "-heavy",
            "-italic",
        )
        return suffixes.any { normalized.endsWith(it) }
    }

    private fun registerPlugins(flutterEngine: FlutterEngine) {
        val pluginClasses = buildList {
            add("com.ryanheise.audio_session.AudioSessionPlugin")
            add("com.mr.flutter.plugin.filepicker.FilePickerPlugin")
            add("io.flutter.plugins.firebase.analytics.FlutterFirebaseAnalyticsPlugin")
            add("io.flutter.plugins.firebase.core.FlutterFirebaseCorePlugin")
            add("com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin")
            add("io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin")
            add("xyz.canardoux.fluttersound.FlutterSound")
            add("com.mediadevkit.fvp.FvpPlugin")
            add("com.baseflow.geolocator.GeolocatorPlugin")
            add("io.flutter.plugins.imagepicker.ImagePickerPlugin")
            add("com.fluttercandies.photo_manager.PhotoManagerPlugin")
            add("com.github.dart_lang.jni.JniPlugin")
            add("com.crazecoder.openfile.OpenFilePlugin")
            add("dev.fluttercommunity.plus.packageinfo.PackageInfoPlugin")
            add("io.flutter.plugins.pathprovider.PathProviderPlugin")
            add("com.baseflow.permissionhandler.PermissionHandlerPlugin")
            add("io.sentry.flutter.SentryFlutterPlugin")
            add("io.flutter.plugins.sharedpreferences.SharedPreferencesPlugin")
            add("io.flutter.plugins.urllauncher.UrlLauncherPlugin")
            add("io.flutter.plugins.videoplayer.VideoPlayerPlugin")
        }

        for (className in pluginClasses) {
            try {
                val plugin = Class
                    .forName(className, false, javaClass.classLoader)
                    .asSubclass(FlutterPlugin::class.java)
                    .getDeclaredConstructor()
                    .newInstance()
                flutterEngine.plugins.add(plugin)
            } catch (e: Exception) {
                Log.e("Mithka", "Error registering plugin $className", e)
            }
        }
    }

    private fun translateOnDevice(args: Map<*, *>?, result: MethodChannel.Result) {
        val text = args?.get("text") as? String
        val targetLanguageCode = args?.get("targetLanguageCode") as? String
        val requestedSourceLanguageCode = args?.get("sourceLanguageCode") as? String
        if (text.isNullOrBlank() || targetLanguageCode.isNullOrBlank()) {
            result.error("invalid_arguments", "缺少翻译文本或目标语言", null)
            return
        }

        val target = mlKitLanguage(targetLanguageCode)
        if (target == null) {
            result.error("unsupported_language", "不支持目标语言 $targetLanguageCode", null)
            return
        }

        val requestedSource = mlKitLanguageOrNull(requestedSourceLanguageCode)
        if (requestedSource != null) {
            translateWithLanguages(text, requestedSource, target, result)
            return
        }

        result.error("source_language_required", "ML Kit 本地翻译需要明确原文语言", null)
    }

    private fun translateWithLanguages(
        text: String,
        source: String,
        target: String,
        result: MethodChannel.Result,
    ) {
        if (source == target) {
            result.success(text)
            return
        }

        val translator = translatorFor(source, target)
        translator.downloadModelIfNeeded(DownloadConditions.Builder().build())
            .addOnSuccessListener {
                translator.translate(text)
                    .addOnSuccessListener { translated -> result.success(translated) }
                    .addOnFailureListener { e ->
                        result.error("translation_failed", e.localizedMessage, null)
                    }
            }
            .addOnFailureListener { e ->
                result.error("model_download_failed", e.localizedMessage, null)
            }
    }

    private fun translatorFor(source: String, target: String): Translator {
        val key = "$source|$target"
        return translators.getOrPut(key) {
            Translation.getClient(
                TranslatorOptions.Builder()
                    .setSourceLanguage(source)
                    .setTargetLanguage(target)
                    .build(),
            )
        }
    }

    private fun mlKitLanguageOrNull(code: String?): String? {
        val normalized = normalizeLanguageTag(code) ?: return null
        return TranslateLanguage.fromLanguageTag(normalized)
    }

    private fun mlKitLanguage(code: String?): String? {
        val normalized = normalizeLanguageTag(code) ?: return null
        return TranslateLanguage.fromLanguageTag(normalized)
    }

    private fun normalizeLanguageTag(code: String?): String? {
        val lower = code
            ?.trim()
            ?.replace('_', '-')
            ?.lowercase()
            ?: return null
        if (lower.isEmpty() || lower == "auto" || lower == "autodetect" || lower == "und") {
            return null
        }
        if (lower.startsWith("zh")) return "zh"
        return lower.substringBefore('-')
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        translators.values.forEach { it.close() }
        translators.clear()
        callMedia?.dispose()
        callMedia = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
