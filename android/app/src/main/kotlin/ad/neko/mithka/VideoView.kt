package ad.neko.mithka

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import org.webrtc.RendererCommon
import org.webrtc.TextureViewRenderer

/**
 * Embeds an ntgcalls/WebRTC `TextureViewRenderer` into the Flutter widget tree as a
 * PlatformView (`viewType = "mithka/video_view"`). The `role` creation-param
 * ("remote" | "local") decides which call stream renders here; the view registers
 * its renderer with [CallMediaPlugin] so the call's FrameCallback can route frames
 * to it. Registered in MainActivity.configureFlutterEngine.
 */
class VideoViewFactory(private val plugin: CallMediaPlugin) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any?>
        val role = params?.get("role") as? String ?: "remote"
        return VideoPlatformView(context, plugin, role)
    }
}

private class VideoPlatformView(
    context: Context,
    private val plugin: CallMediaPlugin,
    private val role: String,
) : PlatformView {
    private val renderer = TextureViewRenderer(context).apply {
        init(plugin.eglContext(), null)
        // Preserve the decoded frame's aspect ratio. Any unused space stays
        // black instead of stretching or cropping the caller's video.
        setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FIT)
        setEnableHardwareScaler(true)
        // Mirror the local self-preview like a front-facing camera.
        if (role == "local") setMirror(true)
    }

    init {
        plugin.registerRenderer(role, renderer)
    }

    override fun getView() = renderer

    override fun dispose() {
        plugin.unregisterRenderer(role, renderer)
        runCatching { renderer.release() }
    }
}
