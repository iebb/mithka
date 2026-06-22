package ad.neko.mithkal

import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.github.pytgcalls.NTgCalls
import io.github.pytgcalls.media.AudioDescription
import io.github.pytgcalls.media.MediaDescription
import io.github.pytgcalls.media.MediaSource
import io.github.pytgcalls.media.StreamMode
import io.github.pytgcalls.media.VideoDescription
import io.github.pytgcalls.p2p.RTCServer
import java.util.concurrent.Executors

/**
 * Bridges the Dart `CallMediaEngine` to ntgcalls' 1:1 P2P API.
 *
 * Flutter (TgcallsMediaEngine) sends the TDLib `callStateReady` payload over the
 * `mithkal/call_media` MethodChannel; we drive ntgcalls with it:
 *   createP2PCall → setStreamSources(mic[/camera]) → skipExchange(key) → connectP2P
 * (TDLib already performed the DH key exchange, so we `skipExchange`.)
 *
 * The WebRTC handshake for v3/v4 calls runs over a signaling channel carried by
 * TDLib: ntgcalls emits bytes via the SignalingDataCallback → we forward them to
 * Dart over the `events` EventChannel → Dart relays via TDLib sendCallSignalingData;
 * inbound TDLib updateNewCallSignalingData arrives back as `receiveSignaling` →
 * ntgcalls.sendSignalingData. Without this loop the call never leaves "connecting".
 */
class CallMediaPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) {
    private val methods = MethodChannel(messenger, "mithkal/call_media")
    private val events = EventChannel(messenger, "mithkal/call_media/events")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var ntg: NTgCalls? = null
    private var chatId: Long = 0L
    private var eventSink: EventChannel.EventSink? = null
    private var prevAudioMode = AudioManager.MODE_NORMAL

    companion object {
        // ntgcalls' Android device metadata is synthetic JSON; only is_microphone
        // is read (it must match the stream direction).
        private const val MIC_META = "{\"is_microphone\":true}"
        private const val SPK_META = "{\"is_microphone\":false}"
    }

    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                eventSink = sink
            }

            override fun onCancel(args: Any?) {
                eventSink = null
            }
        })
        // libntgcalls.so (~20MB WebRTC) loads lazily on the first call, when the
        // NTgCalls instance is constructed — no startup cost for non-callers.
        methods.setMethodCallHandler { call, result ->
            if (call.method == "getProtocol") {
                worker.execute {
                    runCatching {
                        val p = NTgCalls.getProtocol()
                        android.util.Log.i(
                            "CallMedia",
                            "ntgcalls protocol min=${p.minLayer} max=${p.maxLayer} versions=${p.libraryVersions}",
                        )
                        mapOf(
                            "min" to p.minLayer,
                            "max" to p.maxLayer,
                            "versions" to p.libraryVersions,
                        )
                    }.onSuccess { v -> main.post { result.success(v) } }
                        .onFailure { e -> main.post { result.error("call_media", e.message, null) } }
                }
                return@setMethodCallHandler
            }
            when (call.method) {
                "start" -> worker.execute { runCatching { start(call.argument("config")!!) }
                    .onSuccess { reply(result, null) }
                    .onFailure { reply(result, it) } }
                "stop" -> worker.execute { runCatching { stop() }
                    .onSuccess { reply(result, null) }.onFailure { reply(result, it) } }
                "setMuted" -> worker.execute { runCatching { setMuted(call.arguments as Boolean) }
                    .onSuccess { reply(result, null) }.onFailure { reply(result, it) } }
                "setSpeaker" -> { setSpeaker(call.arguments as Boolean); result.success(null) }
                "setVideoEnabled" -> worker.execute {
                    runCatching { setVideoEnabled(call.arguments as Boolean) }
                        .onSuccess { reply(result, null) }.onFailure { reply(result, it) } }
                "receiveSignaling" -> worker.execute {
                    runCatching {
                        val data = call.arguments as ByteArray
                        ntg?.sendSignalingData(chatId, data)
                    }.onSuccess { reply(result, null) }.onFailure { reply(result, it) } }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        runCatching { stop() }
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        worker.shutdownNow()
    }

    private fun reply(result: MethodChannel.Result, error: Throwable?) {
        main.post {
            if (error == null) result.success(null)
            else result.error("call_media", error.message, null)
        }
    }

    private fun emit(event: Map<String, Any?>) = main.post { eventSink?.success(event) }

    // MARK: - ntgcalls lifecycle

    @Suppress("UNCHECKED_CAST")
    private fun start(config: Map<String, Any?>) {
        stop() // tear down any previous call

        chatId = (config["callId"] as Number).toLong()
        val isOutgoing = config["isOutgoing"] as Boolean
        val isVideo = config["isVideo"] as Boolean
        val p2pAllowed = config["p2pAllowed"] as? Boolean ?: true
        val key = config["encryptionKey"] as ByteArray
        val versions = (config["libraryVersions"] as? List<String>) ?: emptyList()
        val servers = (config["servers"] as? List<Map<String, Any?>>) ?: emptyList()

        val instance = NTgCalls()
        ntg = instance

        // Outbound signaling: ntgcalls → Dart → TDLib sendCallSignalingData.
        instance.setSignalingDataCallback { _, data ->
            emit(mapOf("type" to "signaling", "data" to data))
        }
        // Connection state for the UI / diagnostics.
        instance.setConnectionChangeCallback { _, info ->
            emit(mapOf("type" to "state", "state" to info.state.name))
        }

        // Sequence per the Telegram-X reference: create → CAPTURE (mic) →
        // PLAYBACK (speaker) → skipExchange → connectP2P.
        instance.createP2PCall(chatId)
        instance.setStreamSources(chatId, StreamMode.CAPTURE, captureMedia(isVideo))
        instance.setStreamSources(chatId, StreamMode.PLAYBACK, playbackMedia())
        // TDLib already did the DH exchange and handed us the 256-byte shared key.
        instance.skipExchange(chatId, key, isOutgoing)
        instance.connectP2P(chatId, servers.mapNotNull(::toRtcServer), versions, p2pAllowed)

        beginAudioSession()
    }

    private fun stop() {
        val instance = ntg ?: return
        runCatching { instance.stop(chatId) }
        ntg = null
        endAudioSession()
    }

    private fun setMuted(muted: Boolean) {
        val instance = ntg ?: return
        if (muted) instance.mute(chatId) else instance.unmute(chatId)
    }

    private fun setVideoEnabled(enabled: Boolean) {
        ntg?.setStreamSources(chatId, StreamMode.CAPTURE, captureMedia(enabled))
    }

    /** CAPTURE media (what we send): the microphone. On Android ntgcalls' device
     *  metadata is a synthetic JSON string — the default mic is exactly
     *  {"is_microphone":true} (an empty/invalid string throws "Invalid device
     *  metadata"). getMediaDevices() isn't needed (it only returns this constant)
     *  AND avoiding it sidesteps the camera-enumeration SIGABRT (ntgcalls never
     *  sets the WebRTC app Context). Camera capture is a follow-up once that
     *  Context init is in place. */
    private fun captureMedia(video: Boolean): MediaDescription {
        val mic = AudioDescription(MediaSource.DEVICE, MIC_META, true, 48000, 2)
        return MediaDescription(mic, null, null, null)
    }

    /** PLAYBACK media (what we hear): the default speaker, {"is_microphone":false}
     *  so is_microphone matches the (non-capture) direction. */
    private fun playbackMedia(): MediaDescription {
        val speaker = AudioDescription(MediaSource.DEVICE, SPK_META, true, 48000, 2)
        return MediaDescription(null, speaker, null, null)
    }

    // MARK: - Server mapping (TDLib callServer → ntgcalls RTCServer)

    @Suppress("UNCHECKED_CAST")
    private fun toRtcServer(s: Map<String, Any?>): RTCServer? {
        val id = (s["id"] as? Number)?.toLong() ?: return null
        return RTCServer(
            id,
            s["ipv4"] as? String ?: "",
            s["ipv6"] as? String ?: "",
            (s["port"] as? Number)?.toInt() ?: 0,
            s["username"] as? String ?: "",
            s["password"] as? String ?: "",
            s["turn"] as? Boolean ?: false,
            s["stun"] as? Boolean ?: false,
            s["tcp"] as? Boolean ?: false,
            s["peerTag"] as? ByteArray,
        )
    }

    // MARK: - Audio routing (earpiece default; speaker toggle)

    private fun beginAudioSession() {
        prevAudioMode = audio.mode
        audio.mode = AudioManager.MODE_IN_COMMUNICATION
        setSpeaker(false)
    }

    private fun endAudioSession() {
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) audio.clearCommunicationDevice()
            @Suppress("DEPRECATION")
            audio.isSpeakerphoneOn = false
            audio.mode = prevAudioMode
        }
    }

    private fun setSpeaker(on: Boolean) {
        runCatching {
            @Suppress("DEPRECATION")
            audio.isSpeakerphoneOn = on
        }
    }
}
