package ad.neko.mithka

import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.util.Log
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
    private val translators = mutableMapOf<String, Translator>()

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mithka/clipboard")
            .setMethodCallHandler { call, result ->
                if (call.method != "readImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                val clip = clipboard.primaryClip
                if (clip == null || clip.itemCount == 0) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val uri = clip.getItemAt(0).uri
                if (uri == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val mimeType = contentResolver.getType(uri)
                    ?: clip.description?.getMimeType(0)
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
    }

    private fun listSystemFonts(): List<String> {
        val fonts = linkedSetOf(
            "sans-serif",
            "sans-serif-condensed",
            "sans-serif-medium",
            "sans-serif-light",
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
                                    ?.trim()
                                    ?.takeIf { it.isNotEmpty() }
                                    ?.let { fonts.add(it) }
                                "alias" -> {
                                    parser.getAttributeValue(null, "name")
                                        ?.trim()
                                        ?.takeIf { it.isNotEmpty() }
                                        ?.let { fonts.add(it) }
                                    parser.getAttributeValue(null, "to")
                                        ?.trim()
                                        ?.takeIf { it.isNotEmpty() }
                                        ?.let { fonts.add(it) }
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

    private fun registerPlugins(flutterEngine: FlutterEngine) {
        val pluginClasses = buildList {
            add("com.ryanheise.audio_session.AudioSessionPlugin")
            add("com.mr.flutter.plugin.filepicker.FilePickerPlugin")
            add("io.flutter.plugins.firebase.analytics.FlutterFirebaseAnalyticsPlugin")
            add("io.flutter.plugins.firebase.core.FlutterFirebaseCorePlugin")
            add("com.dexterous.flutterlocalnotifications.FlutterLocalNotificationsPlugin")
            add("io.flutter.plugins.flutter_plugin_android_lifecycle.FlutterAndroidLifecyclePlugin")
            add("xyz.canardoux.fluttersound.FlutterSound")
            // fvp 0.37.2 crashes in libmdk.so during JNI_OnLoad on Android 14+
            // before Dart can handle it. Older Android versions keep the backend.
            if (Build.VERSION.SDK_INT < 34) {
                add("com.mediadevkit.fvp.FvpPlugin")
            }
            add("com.baseflow.geolocator.GeolocatorPlugin")
            add("io.flutter.plugins.imagepicker.ImagePickerPlugin")
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
