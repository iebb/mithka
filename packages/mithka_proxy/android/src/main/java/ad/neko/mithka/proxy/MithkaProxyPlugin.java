package ad.neko.mithka.proxy;

import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;
import androidx.webkit.ProxyConfig;
import androidx.webkit.ProxyController;
import androidx.webkit.WebViewFeature;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import java.util.concurrent.Executor;

/** Routes this app's WebViews, and nothing else, through the local proxy. */
public final class MithkaProxyPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Executor onMain = main::post;
    private MethodChannel channel;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "ad.neko.mithka/proxy");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if ("isSupported".equals(call.method)) {
            result.success(WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE));
            return;
        }
        if (!"configure".equals(call.method)) {
            result.notImplemented();
            return;
        }
        // Older WebView providers cannot be proxied per app; the caller shows
        // the direct fallback instead.
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE)) {
            result.success(false);
            return;
        }
        final Integer port = call.argument("port");
        if (port != null && (port < 1 || port > 65535)) {
            result.error("invalid_port", "Invalid proxy port", null);
            return;
        }
        try {
            final ProxyController controller = ProxyController.getInstance();
            final Runnable done = () -> result.success(true);
            if (port == null) {
                controller.clearProxyOverride(onMain, done);
            } else {
                // No DIRECT rule: a load fails rather than leaving the proxy
                // when the local engine is gone. Loopback stays direct, which
                // is WebView's implicit bypass.
                final ProxyConfig config = new ProxyConfig.Builder()
                        .addProxyRule("http://127.0.0.1:" + port)
                        .build();
                controller.setProxyOverride(config, onMain, done);
            }
        } catch (RuntimeException error) {
            result.error("proxy_unavailable", "WebView proxy configuration failed", null);
        }
    }
}
