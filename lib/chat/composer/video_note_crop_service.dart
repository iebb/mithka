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
/// Ownership is per request, with a ticket, not per "last export": [start]
/// begins an export and returns the [VideoNoteCropTicket] that owns the file
/// it produces. The ticket — not a global slot — is what the caller accepts
/// or abandons, so a second recorder that is still handing its file to the
/// send path never sees its crop reclaimed by a different route being torn
/// down. Cleanup rides the platform future itself (so an export that lands
/// after the abandon timeout is still reclaimed), and the delivery flag is
/// only set after the caller has verified and taken the file.
abstract final class VideoNoteCropService {
  static const _channel = MethodChannel('mithka/media_editor');

  /// Upper bound for the native re-encode. A 60-second 720p square export
  /// completes in a couple of seconds on device; past this the recorder sends
  /// the original file rather than keep its screen busy.
  static const defaultTimeout = Duration(seconds: 15);

  /// Exports that have started and whose output no caller has accepted yet.
  static final Set<_CropRequest> _requests = <_CropRequest>{};

  /// Begins a square-crop export of the recording at [path] and returns the
  /// ticket that owns the produced file.
  ///
  /// The caller either takes the delivered file via [VideoNoteCropTicket.accept]
  /// after verifying it and deleting the recording it replaces, or explicitly
  /// surrenders it via [VideoNoteCropTicket.abandon]. Returns `null` for an
  /// empty path.
  static VideoNoteCropTicket? start(String path) {
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
            if (!request.done.isCompleted) request.done.complete();
            // Unconditional cleanup of exactly this request's temp, bound to
            // the true platform completion rather than to the abandonInFlight
            // bounded wait.
            if (request.abandoned && !request.accepted) {
              unawaited(_reclaim(request));
            }
          }),
    );
    return VideoNoteCropTicket._(request);
  }

  /// Compatibility wrapper around [start] for the existing helper API.
  ///
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
    final ticket = start(path);
    if (ticket == null) return null;
    return ticket.resolve(timeout: timeout);
  }

  /// Hands the file [crop] produced at [path] to the caller, which now owns it
  /// and is responsible for deleting it once the note has been sent.
  ///
  /// Called only after the caller has verified the file it is about to send.
  /// An unknown path is a no-op, so a caller may accept unconditionally. This
  /// static accepts any path; the ticket scope ([VideoNoteCropTicket.accept])
  /// is what the recorder's per-request flow uses to protect a second live
  /// recorder's crop.
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
  /// gives up is still deleted when the platform actually completes.
  ///
  /// For a producer that owns one ticket, use that ticket's [VideoNoteCropTicket.abandon]
  /// instead so a second live producer's crop is untouched; this remains the
  /// test/process sweep.
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
  ///
  /// Memoized on the request: the platform completion callback, an abandon and
  /// the global sweep may all race here, and they all await the same single
  /// deletion instead of each firing an unawaited one.
  static Future<void> _reclaim(_CropRequest request) {
    final existing = request.reclaimed;
    if (existing != null) return existing;
    final future = _deleteOwnedFile(request);
    request.reclaimed = future;
    _requests.remove(request);
    return future;
  }

  static Future<void> _deleteOwnedFile(_CropRequest request) async {
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

  /// Awaits the platform result of [request], bounded by [timeout], and maps
  /// it to a usable file path.
  ///
  /// Returns `null` when the editor is missing, refused, echoed the input,
  /// answered nothing, or timed out. On such outcomes the request is
  /// explicitly abandoned so a late platform success is still reclaimed by the
  /// true completion.
  static Future<String?> _resolve(
    _CropRequest request, {
    Duration timeout = defaultTimeout,
  }) async {
    try {
      final output = await request.raw.timeout(timeout);
      if (output == null || output.isEmpty || output == request.input) {
        _abandon(request);
        return null;
      }
      request.output = output;
      // Delivered, not yet abandoned and not accepted: the caller is between
      // the platform answer and its accept/abandon decision. Nothing is
      // reclaimed here, so a normal handoff keeps the file while any later
      // abandonment still reclaims it — and only this request's own file.
      return output;
    } catch (_) {
      // MissingPluginException, PlatformException, TimeoutException and a
      // malformed reply all mean the same thing here: send the recording.
      // The request stays registered so a late output is still reclaimed.
      _abandon(request);
      return null;
    }
  }

  static Future<void> _abandonTicket(
    _CropRequest request, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (request.accepted) return;
    final existing = request.reclaimed;
    if (existing != null) {
      await existing;
      return;
    }
    request.abandoned = true;
    if (request.settled) {
      await _reclaim(request);
      return;
    }
    await request.done.future.timeout(timeout, onTimeout: () => null);
  }
}

/// Ownership handle for one crop export.
///
/// The service keeps the produced file until the caller either
/// [accept]s it for the send path or [abandon]s it; the platform
/// completion callback reclaims it even after an [abandon] wait gives up.
final class VideoNoteCropTicket {
  const VideoNoteCropTicket._(this._request);

  final _CropRequest _request;

  /// Resolves to the cropped file path, or `null` when no crop was produced.
  Future<String?> resolve({
    Duration timeout = VideoNoteCropService.defaultTimeout,
  }) => VideoNoteCropService._resolve(_request, timeout: timeout);

  /// Takes ownership of the file at [path] for the send path, scoped to this
  /// ticket's request.
  ///
  /// Returns `true` when [path] is this ticket's verified output and is now
  /// owned; `false` for an unrelated or already-reclaimed/accepted ticket.
  bool accept(String path) {
    if (path.trim().isEmpty) return false;
    if (_request.output != path) return false;
    if (_request.accepted || _request.reclaimed != null) return false;
    _request.accepted = true;
    VideoNoteCropService._requests.remove(_request);
    return true;
  }

  /// Surrenders this export; its file is deleted when the platform finishes,
  /// even when the bounded wait gives up.
  Future<void> abandon({Duration timeout = const Duration(seconds: 5)}) =>
      VideoNoteCropService._abandonTicket(_request, timeout: timeout);
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

  /// The single deletion of this request's file, so every racer awaits the
  /// same future instead of firing parallel unawaited deletions.
  Future<void>? reclaimed;

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
