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
///
/// Ownership is per request, not per "last export": [crop] starts an export and
/// the service keeps the file it produces, [accept] hands that file to the
/// caller for sending, and [abandonInFlight] reclaims every file nobody
/// accepted. Cleanup is attached to the platform future itself, so an export
/// that lands after the caller gave up is still deleted.
abstract final class VideoNoteCropService {
  static const _channel = MethodChannel('mithka/media_editor');

  /// Upper bound for the native re-encode. A 60-second 720p square export
  /// completes in a couple of seconds on device; past this the recorder sends
  /// the original file rather than keep its screen busy.
  static const defaultTimeout = Duration(seconds: 15);

  /// Exports that have started and whose output no caller has accepted yet.
  static final Set<_CropRequest> _requests = <_CropRequest>{};

  /// Returns the path of the cropped file, or `null` when no crop was produced.
  ///
  /// A non-null result is always a file other than [path], so the caller may
  /// delete the recording it passed in once it has accepted the crop. The
  /// service still owns the returned file until [accept] is called: a caller
  /// that walks away without accepting leaves it to [abandonInFlight].
  static Future<String?> crop(
    String path, {
    Duration timeout = defaultTimeout,
  }) async {
    if (path.trim().isEmpty) return null;
    final request = _CropRequest(
      input: path,
      raw: _channel.invokeMethod<String>('cropVideoNote', {'path': path}),
    );
    _requests.add(request);
    // Cleanup rides the platform future, not a timer: whenever the export
    // eventually lands, an abandoned request's file is deleted then.
    unawaited(
      request.raw
          .then<void>(
            (output) {
              request.output = output;
            },
            onError: (Object _) {
              // A failed export produced nothing to reclaim.
            },
          )
          .whenComplete(() {
            request.settled = true;
            request.done.complete();
            if (request.abandoned && !request.accepted) {
              unawaited(_reclaim(request));
            }
          }),
    );
    try {
      final output = await request.raw.timeout(timeout);
      if (output == null || output.isEmpty || output == path) {
        _abandon(request);
        return null;
      }
      request.output = output;
      return output;
    } catch (_) {
      // MissingPluginException, PlatformException, TimeoutException and a
      // malformed reply all mean the same thing here: send the recording.
      // The request stays registered so a late output is still reclaimed.
      _abandon(request);
      return null;
    }
  }

  /// Hands the file [crop] produced at [path] to the caller, which now owns it
  /// and is responsible for deleting it once the note has been sent.
  ///
  /// Called only after the caller has verified the file it is about to send.
  /// An unknown path is a no-op, so a caller may accept unconditionally.
  static void accept(String path) {
    if (path.trim().isEmpty) return;
    for (final request in _requests.toList()) {
      if (request.output == path) {
        request.accepted = true;
        _requests.remove(request);
      }
    }
  }

  /// Abandons every export no caller accepted and deletes the file it produced.
  ///
  /// A request whose platform call already settled is reclaimed immediately; a
  /// request still running has its deletion attached to the platform future's
  /// own completion, so [timeout] only bounds how long this call waits before
  /// returning. It never drops the cleanup: an export that lands after the wait
  /// gives up is still deleted then.
  ///
  /// Never deletes the recording a request was started from, and never deletes
  /// a file [accept] took ownership of.
  static Future<void> abandonInFlight({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final pending = _requests.where((request) => !request.accepted).toList();
    if (pending.isEmpty) return;
    for (final request in pending) {
      _abandon(request);
    }
    for (final request in pending) {
      if (request.settled) await _reclaim(request);
    }
    final unsettled = pending.where((request) => !request.settled);
    if (unsettled.isEmpty) return;
    await Future.wait(
      unsettled.map((request) => request.done.future),
    ).timeout(timeout, onTimeout: () => const <void>[]);
  }

  /// Marks [request] unowned; its file is deleted now when the export already
  /// finished, or by the platform continuation when it finishes later.
  static void _abandon(_CropRequest request) {
    request.abandoned = true;
    if (request.settled && !request.accepted) unawaited(_reclaim(request));
  }

  /// Deletes the file [request] produced, unless a caller accepted it first.
  static Future<void> _reclaim(_CropRequest request) async {
    _requests.remove(request);
    if (request.accepted) return;
    final output = request.output;
    if (output == null || output.isEmpty || output == request.input) return;
    await _deleteQuietly(output, request);
  }

  static Future<void> _deleteQuietly(String path, _CropRequest request) async {
    try {
      final file = File(path);
      if (!await file.exists()) return;
      // The caller may have accepted the file while the existence check ran.
      if (request.accepted) return;
      await file.delete();
    } catch (_) {
      // The platform cache reclaims it anyway.
    }
  }
}

/// One platform export and the file it produced, owned by the service until a
/// caller accepts it or the recorder abandons it.
final class _CropRequest {
  _CropRequest({required this.input, required this.raw});

  /// The recording the export was started from; never deleted by the service.
  final String input;

  /// The platform call itself, so cleanup can attach to its completion.
  final Future<String?> raw;

  /// The path the platform answered with, once it has answered.
  String? output;

  /// Whether the platform call has completed, successfully or not.
  bool settled = false;

  /// Whether a caller took ownership through [VideoNoteCropService.accept].
  bool accepted = false;

  /// Whether the recorder gave up on this export.
  bool abandoned = false;

  final Completer<void> done = Completer<void>();
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
