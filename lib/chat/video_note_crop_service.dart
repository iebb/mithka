import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// Crops a recorded video note down to the centred square the recorder preview
/// shows, so the uploaded file holds only the pixels a client actually draws.
///
/// The recorder masks its preview with a circle, and message bubbles render the
/// received note through the same circular mask. A 16:9 recording (the camera's
/// `ResolutionPreset.high` output) therefore carries a wide band on both sides
/// that no client ever shows. The native editor re-encodes the file to the
/// centred square, which makes the note WYSIWYG and keeps clients that letterbox
/// instead of centre-cropping from rendering it wrong.
///
/// Every failure is swallowed and reported as `null`: a video note must remain
/// sendable when the platform editor is missing, refuses the file, or runs out
/// of time, and the caller then keeps the uncropped recording.
abstract final class VideoNoteCropService {
  static const _channel = MethodChannel('mithka/media_editor');

  /// Upper bound for the native re-encode. A 60-second 720p square export
  /// completes in a couple of seconds on device; past this the recorder sends
  /// the original file rather than keep its screen busy.
  static const defaultTimeout = Duration(seconds: 15);

  /// Returns the path of the cropped file, or `null` when no crop was produced.
  ///
  /// A non-null result is always a file other than [path], so the caller may
  /// delete the recording it passed in once the crop has been accepted.
  static Future<String?> crop(
    String path, {
    Duration timeout = defaultTimeout,
  }) async {
    if (path.trim().isEmpty) return null;
    final raw = _channel.invokeMethod<String>('cropVideoNote', {'path': path});
    _inFlight = raw;
    unawaited(
      raw.then((_) {}, onError: (_) {}).whenComplete(() {
        if (identical(_inFlight, raw)) _inFlight = null;
      }),
    );
    try {
      final output = await raw.timeout(timeout);
      if (output == null || output.isEmpty || output == path) return null;
      // Whoever took delivery owns the file from here, so cleanup has nothing
      // left to reclaim.
      _inFlight = null;
      return output;
    } catch (_) {
      // MissingPluginException, PlatformException, TimeoutException and a
      // malformed reply all mean the same thing here: send the recording.
      return null;
    }
  }

  /// The export the last [crop] call started, tracked by the platform request
  /// itself.
  ///
  /// A route that is left while the native exporter is still running has no
  /// caller left to hand the path to; [abandonInFlight] lets the request
  /// finish and deletes the file it produced, so a timed-out export cannot
  /// leave an unowned temporary next to the recording.
  static Future<String?>? _inFlight;

  /// Waits for the in-flight export (bounded by [timeout]) and deletes the
  /// file it produced, which by then has no owner.
  ///
  /// Returns immediately when nothing is in flight, and never deletes a path a
  /// caller already received.
  static Future<void> abandonInFlight({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final raw = _inFlight;
    if (raw == null) return;
    _inFlight = null;
    String? output;
    try {
      output = await raw.timeout(timeout);
    } catch (_) {
      // A failed or still-pending export produced nothing to clean up.
      return;
    }
    if (output == null || output.isEmpty) return;
    await _deleteQuietly(output);
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The platform cache reclaims it anyway.
    }
  }
}

/// True when a [width] x [height] frame is already square within one pixel, so
/// a native crop would only re-encode the file for no visual gain.
///
/// The recorder cannot know the recorded size before the file exists, so it
/// always asks for the crop and falls back; the native editors use the same
/// one-pixel tolerance to decide whether their output is acceptable.
bool isSquareVideoNote(int width, int height) {
  if (width <= 0 || height <= 0) return false;
  return (width - height).abs() <= 1;
}
