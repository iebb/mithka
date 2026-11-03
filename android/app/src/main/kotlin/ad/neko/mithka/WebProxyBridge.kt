package ad.neko.mithka

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.PermissionRequest
import android.webkit.ConsoleMessage
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.net.http.SslError
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.net.HttpURLConnection
import java.net.URL

class WebProxyBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "mithka/web_proxy")
    private val carriers = mutableMapOf<String, Carrier>()
    private val handler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler { call, result ->
            val key = call.argument<String>("key")
            if (key == null) {
                result.error("invalid_carrier", null, null)
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "open" -> {
                        if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) ||
                            !WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                            result.error("unsupported_carrier", null, null)
                            return@setMethodCallHandler
                        }
                        check(!carriers.containsKey(key))
                        val carrier = Carrier(
                            key, call.argument<String>("url")!!,
                            call.argument<String>("origin")!!,
                            call.argument<String>("pathPrefix")!!,
                        )
                        carriers[key] = carrier
                        carrier.open(call.argument<String>("script")!!)
                        result.success(null)
                    }
                    "deliver" -> {
                        val carrier = carriers[key] ?: error("missing carrier")
                        carrier.view.evaluateJavascript(
                            "try { ${call.argument<String>("script")} true; } catch (_) { false; }",
                        ) { value ->
                            if (value == "true") result.success(null)
                            else result.error("carrier_delivery", null, null)
                        }
                    }
                    "close" -> {
                        val carrier = carriers.remove(key)
                        if (carrier != null) {
                            carrier.closing = true
                            val script = call.argument<String>("script").orEmpty()
                            val notify = carrier.sentMessage || script.isNotEmpty()
                            if (notify) {
                                carrier.view.evaluateJavascript(
                                    script.ifEmpty {
                                        "window.TelegramWebProxy?.onmessage?.({data:'{\"t\":\"close\"}'});"
                                    }, null,
                                )
                            }
                            handler.postDelayed(
                                { carrier.destroy() },
                                if (notify) 200L else 0L,
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                // WebView exceptions may contain the URL, including its capability.
                carriers.remove(key)?.destroy()
                result.error("carrier_failed", null, null)
            }
        }
    }

    fun dispose() {
        carriers.values.forEach { it.destroy() }
        carriers.clear()
        channel.setMethodCallHandler(null)
    }

    private inner class Carrier(
        val key: String, val url: String, val origin: String, val prefix: String,
    ) {
        val view = WebView(context)
        private val base = Uri.parse(origin)
        @Volatile var closing = false
        var sentMessage = false
        @Volatile private var failed = false

        init {
            require(base.scheme == "https" && base.host != null && base.userInfo == null)
            require(base.path.isNullOrEmpty() || base.path == "/")
            require(base.query == null && base.fragment == null)
            require(prefix.startsWith("/") && prefix.endsWith("/"))
            require(!prefix.contains("..") && !prefix.contains("%"))
            require(allows(Uri.parse(url)))
        }

        private fun allows(uri: Uri): Boolean =
            uri.scheme == "https" && uri.host == base.host &&
                (if (uri.port < 0) 443 else uri.port) == (if (base.port < 0) 443 else base.port) &&
                uri.userInfo == null && uri.path.orEmpty().startsWith(prefix) &&
                !uri.encodedPath.orEmpty().contains("%2f", ignoreCase = true) &&
                !uri.encodedPath.orEmpty().contains("%5c", ignoreCase = true) &&
                !uri.path.orEmpty().split("/").contains("..")

        private fun fail(terminated: Boolean = false) {
            handler.post {
                if (!closing && !failed) {
                    failed = true
                    channel.invokeMethod("error", mapOf("key" to key, "terminated" to terminated))
                }
            }
        }

        fun open(script: String) {
            view.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = false
                allowFileAccess = false
                allowContentAccess = false
                javaScriptCanOpenWindowsAutomatically = false
                mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
                cacheMode = android.webkit.WebSettings.LOAD_NO_CACHE
                mediaPlaybackRequiresUserGesture = true
                setGeolocationEnabled(false)
            }
            // The origin rule applies to frames too, so the native callback also
            // checks isMainFrame. Never use addJavascriptInterface here.
            WebViewCompat.addWebMessageListener(view, "mithkaWebProxy", setOf(origin)) {
                    _, message, sourceOrigin, isMainFrame, _ ->
                if (!closing && !failed && isMainFrame &&
                    sourceOrigin.toString().trimEnd('/') == origin.trimEnd('/')) {
                    sentMessage = true
                    channel.invokeMethod(
                        "message", mapOf("key" to key, "message" to message.data),
                    )
                }
            }
            WebViewCompat.addDocumentStartJavaScript(view, script, setOf(origin))
            view.webChromeClient = object : WebChromeClient() {
                override fun onPermissionRequest(request: PermissionRequest) = request.deny()
                override fun onConsoleMessage(message: ConsoleMessage): Boolean = true
            }
            view.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    if (request.isForMainFrame && allows(request.url)) return false
                    fail()
                    return true
                }

                override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) {
                    if (url == null || !allows(Uri.parse(url))) {
                        view.stopLoading()
                        fail()
                    }
                }

                override fun shouldInterceptRequest(
                    view: WebView, request: WebResourceRequest,
                ): WebResourceResponse? {
                    if (!allows(request.url)) {
                        fail()
                        return blocked()
                    }
                    if (!request.isForMainFrame) return null
                    return document(request)
                }

                override fun onReceivedError(
                    view: WebView, request: WebResourceRequest, error: WebResourceError,
                ) { fail() }

                override fun onReceivedHttpError(
                    view: WebView, request: WebResourceRequest, response: WebResourceResponse,
                ) { fail() }

                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
                    handler.cancel()
                    fail()
                }

                override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                    fail(terminated = true)
                    return true
                }
            }
            view.loadUrl(url)
        }

        // A response CSP confines WebSockets as well as resource requests;
        // WebView's request interceptor alone does not see WebSocket handshakes.
        private fun document(request: WebResourceRequest): WebResourceResponse {
            try {
                require(request.method == "GET")
                val connection = URL(request.url.toString()).openConnection() as HttpURLConnection
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 15000
                connection.readTimeout = 15000
                connection.useCaches = false
                request.requestHeaders.forEach { (name, value) ->
                    if (!name.equals("Cookie", true) && !name.equals("Accept-Encoding", true)) {
                        connection.setRequestProperty(name, value)
                    }
                }
                connection.setRequestProperty("Accept-Encoding", "identity")
                val status = connection.responseCode
                if (status !in 200..299) {
                    connection.disconnect()
                    fail()
                    return blocked()
                }
                val scope = origin.trimEnd('/') + prefix
                val websocket = "wss://" + base.encodedAuthority + prefix
                val headers = mutableMapOf<String, String>()
                connection.headerFields.forEach { (name, values) ->
                    if (name != null && !name.equals("Set-Cookie", true)) {
                        headers[name] = values.joinToString(", ")
                    }
                }
                headers["Content-Security-Policy"] =
                    "default-src 'none'; script-src $scope 'unsafe-inline' 'unsafe-eval'; " +
                    "connect-src $scope $websocket; style-src $scope 'unsafe-inline'; " +
                    "img-src $scope; frame-src 'none'; worker-src 'none'; " +
                    "base-uri 'none'; form-action 'none'"
                val stream = object : java.io.FilterInputStream(connection.inputStream) {
                    override fun close() {
                        try { super.close() } finally { connection.disconnect() }
                    }
                }
                return WebResourceResponse("text/html", "utf-8", status, "OK", headers, stream)
            } catch (_: Exception) {
                fail()
                return blocked()
            }
        }

        private fun blocked() = WebResourceResponse(
            "text/plain", "utf-8", 403, "Blocked", emptyMap(), ByteArrayInputStream(byteArrayOf()),
        )

        fun destroy() {
            closing = true
            view.stopLoading()
            WebViewCompat.removeWebMessageListener(view, "mithkaWebProxy")
            view.destroy()
        }
    }
}
