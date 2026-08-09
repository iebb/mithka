package ad.neko.mithka

import android.content.Context
import android.util.Log
import org.webrtc.Camera2Enumerator
import org.webrtc.CameraVideoCapturer
import org.webrtc.CapturerObserver
import org.webrtc.EglBase
import org.webrtc.JavaI420Buffer
import org.webrtc.SurfaceTextureHelper
import org.webrtc.VideoFrame
import org.webrtc.YuvHelper
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Owns the device camera via WebRTC's [org.webrtc.Camera2Capturer] and fans each
 * captured frame out two ways:
 *   • [onLocalFrame] — the raw WebRTC frame, rendered into the self-preview PiP;
 *   • [onEncodedFrame] — the same frame packed as tightly-packed I420, forwarded to
 *     ntgcalls via sendExternalFrame so the peer sees us.
 *
 * ntgcalls' own DEVICE camera capture never surfaces frames for a local preview, so
 * we capture ourselves and feed ntgcalls an EXTERNAL video stream instead. Flipping
 * the camera uses [CameraVideoCapturer.switchCamera]; [onSwitched] reports the new
 * facing so the caller can un-mirror the preview for the back camera.
 */
class CameraCapture(
    private val context: Context,
    private val eglContext: EglBase.Context,
    private val onLocalFrame: (VideoFrame) -> Unit,
    private val onEncodedFrame: (ByteArray, Int, Int, Int, Long) -> Unit,
    private val onSwitched: (Boolean) -> Unit,
) {
    private var capturer: CameraVideoCapturer? = null
    private var helper: SurfaceTextureHelper? = null

    @Volatile
    var isFront = true
        private set

    @Volatile
    private var sawFrame = false

    @Volatile
    private var sentOnce = false

    // Recycled staging buffers: a fresh direct buffer per frame is ~41 MB/s of
    // direct memory at 720p30 for the whole call, and direct memory is only
    // reclaimed by forcing a GC — which stalls this capture thread. A buffer goes
    // back to the pool only when the preview renderer releases the frame wrapping
    // it, and that callback runs on the renderer's EGL thread, hence the
    // concurrent queue.
    //
    // The heap array handed to sendExternalFrame is deliberately NOT pooled:
    // ntgcalls is a prebuilt AAR, so whether it copies the array before returning
    // cannot be checked from this repo, and reusing it would corrupt in-flight
    // frames if it does not. ART reclaims a short-lived array cheaply anyway.
    private val dstPool = ConcurrentLinkedQueue<ByteBuffer>()

    companion object {
        // Fixed encoder resolution. ntgcalls' WebRTC video encoder aborts
        // (SIGABRT on its VideoEncoderQue thread) if the frames it receives change
        // size or have odd/unexpected dimensions, so we normalize every outgoing
        // frame to exactly this even size (matching the CAPTURE VideoDescription).
        private const val TARGET_W = 1280
        private const val TARGET_H = 720
        private const val FRAME_SIZE = TARGET_W * TARGET_H * 3 / 2

        // Frames that may be in flight at once: the preview renderer holds at
        // most one, so three is slack.
        private const val SCRATCH_DEPTH = 3
    }

    /** Open the requested camera (front/back) and start delivering frames. */
    fun start(front: Boolean) {
        stop()
        isFront = front
        sawFrame = false
        sentOnce = false
        val enumerator = Camera2Enumerator(context)
        val names = enumerator.deviceNames
        val name = names.firstOrNull { enumerator.isFrontFacing(it) == front }
            ?: names.firstOrNull()
        if (name == null) {
            Log.e("CallMediaVid", "CameraCapture: no camera devices")
            return
        }
        val cap = enumerator.createCapturer(name, null)
        val h = SurfaceTextureHelper.create("CallCapture", eglContext)
        capturer = cap
        helper = h
        cap.initialize(h, context, object : CapturerObserver {
            override fun onCapturerStarted(success: Boolean) {
                Log.i("CallMediaVid", "CameraCapture started=$success front=$front")
            }

            override fun onCapturerStopped() {}

            override fun onFrameCaptured(frame: VideoFrame) {
                if (!sawFrame) {
                    sawFrame = true
                    Log.i(
                        "CallMediaVid",
                        "CameraCapture first frame ${frame.rotatedWidth}x${frame.rotatedHeight} rot=${frame.rotation}",
                    )
                }
                // Both the local preview and the outgoing frame are produced from
                // the same upright I420 inside encodeAndSend.
                encodeAndSend(frame)
            }
        })
        cap.startCapture(1280, 720, 30)
    }

    /** Flip between the front- and back-facing camera. */
    fun switch() {
        val cap = capturer ?: return
        cap.switchCamera(object : CameraVideoCapturer.CameraSwitchHandler {
            override fun onCameraSwitchDone(front: Boolean) {
                isFront = front
                onSwitched(front)
            }

            override fun onCameraSwitchError(error: String) {
                Log.e("CallMediaVid", "switchCamera failed: $error")
            }
        })
    }

    fun stop() {
        runCatching { capturer?.stopCapture() }
        runCatching { capturer?.dispose() }
        runCatching { helper?.dispose() }
        capturer = null
        helper = null
        dstPool.clear()
    }

    /** Normalize → bake rotation → send. We center-crop to 16:9, scale to a fixed
     *  even landscape (TARGET_WxTARGET_H), then physically rotate the I420 to upright
     *  and send it with rotation=0. ntgcalls' video encoder aborts (SIGABRT on its
     *  VideoEncoderQue thread) when it has to rotate an externally-supplied frame
     *  itself, so we hand it an already-upright frame. Runs on the capturer's GL
     *  thread, so the crop/scale + texture→I420 readback are valid. */
    private fun encodeAndSend(frame: VideoFrame) {
        val src = frame.buffer
        val sw = src.width
        val sh = src.height
        if (sw <= 0 || sh <= 0) return
        var cw = sw
        var ch = sh
        if (sw * TARGET_H > sh * TARGET_W) {
            cw = sh * TARGET_W / TARGET_H
        } else {
            ch = sw * TARGET_H / TARGET_W
        }
        cw = cw and 1.inv()
        ch = ch and 1.inv()
        val cx = (sw - cw) / 2
        val cy = (sh - ch) / 2
        val scaled = runCatching {
            src.cropAndScale(cx, cy, cw, ch, TARGET_W, TARGET_H)
        }.getOrNull() ?: return
        val i420 = runCatching { scaled.toI420() }.getOrNull()
        if (i420 == null) {
            scaled.release()
            return
        }
        try {
            val rot = frame.rotation
            val dst = dstPool.poll()?.apply { clear() }
                ?: ByteBuffer.allocateDirect(FRAME_SIZE)
            // Bake `rot` into the pixels; output is tightly-packed I420.
            YuvHelper.I420Rotate(
                i420.dataY, i420.strideY,
                i420.dataU, i420.strideU,
                i420.dataV, i420.strideV,
                dst, TARGET_W, TARGET_H, rot,
            )
            // 90/270 swap the dimensions.
            val swap = rot == 90 || rot == 270
            val outW = if (swap) TARGET_H else TARGET_W
            val outH = if (swap) TARGET_W else TARGET_H

            // Local self-preview: render the same upright I420 (the renderer mirrors
            // it for the "local" role). Wrapping the CPU buffer avoids the fragile
            // cross-GL-context texture path.
            val ySize = outW * outH
            val cSize = ySize / 4
            val yb = dst.duplicate().apply { position(0); limit(ySize) }.slice()
            val ub = dst.duplicate().apply { position(ySize); limit(ySize + cSize) }.slice()
            val vb = dst.duplicate().apply {
                position(ySize + cSize); limit(ySize + 2 * cSize)
            }.slice()
            val localBuf = JavaI420Buffer.wrap(outW, outH, yb, outW, ub, outW / 2, vb, outW / 2) {
                // Recycle only once the renderer is done with these slices.
                if (dstPool.size < SCRATCH_DEPTH) dstPool.offer(dst)
            }
            val localFrame = VideoFrame(localBuf, 0, frame.timestampNs)
            onLocalFrame(localFrame)
            localFrame.release()

            val bytes = ByteArray(FRAME_SIZE)
            dst.rewind()
            dst.get(bytes)
            if (!sentOnce) {
                sentOnce = true
                Log.i(
                    "CallMediaVid",
                    "send upright ${outW}x$outH (baked rot=$rot) bytes=$FRAME_SIZE src ${sw}x$sh",
                )
            }
            onEncodedFrame(bytes, outW, outH, 0, frame.timestampNs / 1_000_000L)
        } catch (e: Throwable) {
            Log.e("CallMediaVid", "encodeAndSend failed", e)
        } finally {
            i420.release()
            scaled.release()
        }
    }
}
