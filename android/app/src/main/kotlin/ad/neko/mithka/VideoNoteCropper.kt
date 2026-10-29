package ad.neko.mithka

/**
 * Square cropping of recorded video notes on Android.
 *
 * Video notes are recorded at 1280x720 (16:9) while the recorder preview and the
 * received message bubble only ever show the centred square, so roughly 44% of
 * every uploaded Android note is pixels no client draws, and the file differs
 * from what a client that records square would produce. iOS crops the recording
 * after capture through `AVAssetExportSession` (see
 * `AppDelegate.cropVideoNote`). Android has no equivalent system API and this
 * app deliberately carries no media3/transformer dependency, so the same result
 * needs a hand-written pipeline:
 *
 *   MediaExtractor -> MediaCodec decoder (ByteBuffer mode) -> centred square
 *   copy -> MediaCodec H.264 encoder -> MediaMuxer, with the audio track copied
 *   through unchanged and `MediaMuxer.setOrientationHint` preserving rotation.
 *
 * That pipeline is NOT implemented here, and `cropVideoNote` therefore answers
 * `unsupported`. A hand-written YUV copy is only correct when every one of the
 * following is handled for each device, and none of it can be compiled, run or
 * inspected on hardware in the change that introduced this file:
 *
 *  - decoder output layout: planar I420 vs semi-planar NV12/NV21, with
 *    rowStride != width and sliceHeight != height (the `Image` plane strides are
 *    the only safe source of truth, and U/V may share one interleaved buffer);
 *  - crop origin: chroma is subsampled 2x2, so an odd crop x/y shifts U and V by
 *    half a luma pixel and tints the entire note;
 *  - encoder input: many hardware encoders accept only
 *    `COLOR_FormatSurface`; `COLOR_FormatYUV420Flexible` input through
 *    `getInputImage` is not universally supported and the layout it expects
 *    varies by vendor;
 *  - timestamps: decoder PTS must be re-stamped monotonically for the muxer and
 *    codec-config buffers must be folded into the track format instead of being
 *    written as samples.
 *
 * Getting any of those wrong yields a note that looks plausible in a thumbnail
 * and is green, torn or silent in playback — worse than a note that keeps its
 * uncropped framing. Until a device-tested implementation replaces this object,
 * Android sends the recording unchanged; Dart treats every failure as "send the
 * recording" (`VideoNoteCropService.crop`), so the Dart side needs no change
 * when the crop lands.
 */
internal object VideoNoteCropper {
    /** Error code reported to Dart; every failure there falls back to the file. */
    const val UNSUPPORTED_CODE = "unsupported"

    /** Reason reported to Dart. Informational only; never shown to the user. */
    const val UNSUPPORTED_REASON =
        "Square video-note cropping is not implemented on Android yet; " +
            "the recording is sent uncropped."
}
