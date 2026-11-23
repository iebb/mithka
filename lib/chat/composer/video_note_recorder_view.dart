import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../../components/app_icons.dart';
import '../../components/ui_components.dart';
import '../../media/media_metadata.dart';
import '../../theme/app_theme.dart';
import 'video_note_crop_service.dart';

class VideoNoteCaptureResult {
  const VideoNoteCaptureResult({required this.path, required this.duration});

  final String path;
  final int duration;
}

enum VideoNoteRecordGesture { continueRecording, lock, cancel }

VideoNoteRecordGesture videoNoteRecordGestureForDelta({
  required double dx,
  required double dy,
}) {
  if (dx < -90) return VideoNoteRecordGesture.cancel;
  if (dy < -70) return VideoNoteRecordGesture.lock;
  return VideoNoteRecordGesture.continueRecording;
}

/// The box a live video-message preview is laid out in before it is scaled to
/// cover the recorder's available area.
@immutable
class VideoNotePreviewFootprint {
  const VideoNotePreviewFootprint({
    required this.size,
    required this.coverCropped,
  });

  /// Sensor size with its axes turned to the current screen axis. The long
  /// side follows the viewport's long side, so the box always shares the
  /// viewport's orientation.
  final Size size;

  /// Whether [size] and the viewport have different aspect ratios, so a
  /// cover fit crops instead of filling exactly.
  final bool coverCropped;

  @override
  String toString() =>
      'VideoNotePreviewFootprint(size: $size, coverCropped: $coverCropped)';
}

/// Ratios closer than this count as equal; sensor sizes are integers, so a
/// sub-thousandth difference is float noise rather than a real mismatch.
const double _previewRatioTolerance = 0.001;

bool _hasPreviewArea(Size size) =>
    size.isFinite && size.width > 0 && size.height > 0;

/// Decides how the live video-message preview fills [viewport].
///
/// [aspectRatio] is the ratio [CameraPreview] itself puts on its box (see
/// [videoNotePreviewAspectRatio]); the footprint reuses that box shape rather
/// than deriving one from the window, so the preview is scaled, never
/// re-shaped, by Stage Manager, split view, or a sensor orientation the screen
/// does not share.
///
/// The footprint is then cover-fitted, never letterboxed, because a recorder
/// must fill its window with live pixels. The footprint's `coverCropped` flag
/// reports whether that fit crops the camera frame.
///
/// A null, empty, or non-finite [previewSize] means the camera has not reported
/// a frame yet: no preview box exists, so the footprint is [viewport] itself
/// (an honest "fill the window") rather than an invented shape. An
/// unmeasurable [viewport] falls back to the camera box, so the returned size is
/// always finite and non-negative.
VideoNotePreviewFootprint videoNotePreviewFootprint({
  required Size? previewSize,
  required Size viewport,
  required double aspectRatio,
}) {
  final hasViewport = _hasPreviewArea(viewport);
  if (previewSize == null || !_hasPreviewArea(previewSize)) {
    return VideoNotePreviewFootprint(
      size: hasViewport ? viewport : Size.zero,
      coverCropped: false,
    );
  }
  final longSide = previewSize.longestSide;
  final shortSide = previewSize.shortestSide;
  // The frames the package's own box can occupy at [aspectRatio]: landscape
  // (long side across) when the ratio is at least 1, portrait otherwise.
  final oriented = aspectRatio >= 1
      ? Size(longSide, shortSide)
      : Size(shortSide, longSide);
  if (!hasViewport) {
    return VideoNotePreviewFootprint(size: oriented, coverCropped: false);
  }
  final ratioDelta = (oriented.aspectRatio - viewport.aspectRatio).abs();
  return VideoNotePreviewFootprint(
    size: oriented,
    coverCropped: ratioDelta > _previewRatioTolerance,
  );
}

/// The orientation whose frame shape `CameraPreview` lays out.
///
/// Mirrors the pinned package's own chain exactly: the recording orientation
/// while recording, otherwise a paused preview's frozen orientation, otherwise
/// a locked capture orientation, otherwise the device's. The window plays no
/// part in it.
///
/// The package force-unwraps the recording orientation; a camera value built
/// with `isRecordingVideo` set but no orientation would make its preview throw,
/// so this falls back through the rest of the chain instead.
DeviceOrientation _applicablePreviewOrientation(CameraValue value) {
  return value.previewPauseOrientation ??
      value.lockedCaptureOrientation ??
      value.deviceOrientation;
}

/// The aspect ratio `CameraPreview` puts on its own `AspectRatio` box, or null
/// when it draws no such box.
///
/// Derived exactly as `camera` 0.12.0+2 derives it: the preview size's
/// width/height when the applicable orientation is a landscape one, and the
/// reciprocal otherwise. The landscape branch depends on the camera's
/// orientation, never on what shape [CameraValue.previewSize] happens to have:
/// a portrait 720x1280 frame in `portraitUp` gets 16:9, not 9:16.
///
/// Null means the package has no box to match - [CameraPreview] draws a bare
/// [Container] until the controller is initialized, and its own ratio getter
/// would throw on a null preview size - so the caller cannot invent one.
/// Never throws.
double? videoNotePreviewAspectRatio(CameraValue value) {
  final preview = value.previewSize;
  if (preview == null || preview.isEmpty) return null;
  final sensorRatio = preview.width / preview.height;
  final orientation = value.isRecordingVideo
      ? (value.recordingOrientation ?? _applicablePreviewOrientation(value))
      : _applicablePreviewOrientation(value);
  final landscape =
      orientation == DeviceOrientation.landscapeLeft ||
      orientation == DeviceOrientation.landscapeRight;
  return landscape ? sensorRatio : 1 / sensorRatio;
}

/// The live preview under the recorder's chrome.
///
/// Listens to [controller] because every input the package's ratio depends on -
/// recording start/stop, a paused preview, a capture-orientation lock, a device
/// rotation - changes [CameraValue] without changing the window. Reading the
/// value once inside a [LayoutBuilder] rebuilt only the inner [CameraPreview]
/// on those changes and left this outer box, which is what the cover fit
/// scales, at the old ratio - the stretch this box exists to prevent.
///
/// [viewport] is the area to cover; the box inside it keeps the package's ratio
/// and is scaled, never re-shaped.
class VideoNotePreviewBox extends StatelessWidget {
  const VideoNotePreviewBox({
    super.key,
    required this.controller,
    required this.viewport,
    required this.onFocus,
  });

  final CameraController controller;
  final ValueChanged<Offset> onFocus;

  /// The area the preview must cover, normally the recorder's constraints.
  final Size viewport;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final previewSize = value.previewSize;
        final ratio = videoNotePreviewAspectRatio(value);
        // No frame yet: the package draws a bare Container, so there is no
        // ratio to honour; fill the window until it reports one.
        if (previewSize == null || ratio == null) {
          return const SizedBox.expand();
        }
        final footprint = videoNotePreviewFootprint(
          previewSize: previewSize,
          viewport: viewport,
          aspectRatio: ratio,
        );
        if (footprint.size.isEmpty) return const SizedBox.expand();
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: footprint.coverCropped ? Clip.hardEdge : Clip.none,
            child: SizedBox(
              key: const ValueKey('videoNotePreviewFootprint'),
              width: footprint.size.width,
              height: footprint.size.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: value.focusPointSupported
                    ? (tap) {
                        // The hit test already inverts the FittedBox transform.
                        final point = Offset(
                          (tap.localPosition.dx / footprint.size.width).clamp(
                            0.0,
                            1.0,
                          ),
                          (tap.localPosition.dy / footprint.size.height).clamp(
                            0.0,
                            1.0,
                          ),
                        );
                        onFocus(point);
                      }
                    : null,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Resolves the file a finished video note is sent from: the centred square
/// crop when the native editor produced one, otherwise the recording itself.
///
/// The crop is best-effort. A missing platform editor, a failed export, a
/// malformed reply or a timeout all fall back to [recordedPath], because a
/// slightly wide note is far better than a lost one. When the crop did produce
/// a new file, the recording it replaces is deleted so the cache does not hold
/// two copies of the same note. The produced file stays owned by
/// [VideoNoteCropService] until that deletion step has succeeded; only then is
/// it accepted, so an abandoned crop is still reclaimed while a file this
/// function returns is never deleted by the service. Ownership is per request:
/// production threads the ticket from [VideoNoteCropService.start] through
/// [onStarted] so a disposed recorder only surrenders its own export.
///
/// [crop] and [accept] exist so tests can drive the decision without a platform
/// channel; production passes neither (or passes [ticket]) and reaches
/// [VideoNoteCropService]. [onStarted] and [ticket] let a disposed recorder
/// hand its own ticket to cleanup — neither parameter is pushed by the caller
/// in normal use.
Future<String> videoNoteUploadPath(
  String recordedPath, {
  Future<String?> Function(String path)? crop,
  void Function(String path)? accept,
  VideoNoteCropTicket? ticket,
  void Function(VideoNoteCropTicket)? onStarted,
}) async {
  VideoNoteCropTicket? local = ticket;
  String? cropped;
  if (crop == null && local == null) {
    local = VideoNoteCropService.start(recordedPath);
    if (local != null) onStarted?.call(local);
  }
  try {
    if (local != null) {
      cropped = await local.resolve();
    } else {
      cropped = await (crop ?? (String _) async => null)(recordedPath);
    }
  } catch (_) {
    cropped = null;
  }
  if (cropped == null || cropped.isEmpty || cropped == recordedPath) {
    // The ticket already abandoned the failed/echoed/null crop in resolve, so
    // nothing lingers even when the route finishes early.
    return recordedPath;
  }
  try {
    if (!await File(cropped).exists()) {
      if (local != null) await local.abandon(timeout: Duration.zero);
      return recordedPath;
    }
  } catch (_) {
    if (local != null) await local.abandon(timeout: Duration.zero);
    return recordedPath;
  }
  try {
    final original = File(recordedPath);
    if (await original.exists()) await original.delete();
  } catch (_) {
    // Best-effort: the platform cache reclaims the recording anyway.
  }
  // The cropped file is verified and the recording it replaces is gone: from
  // here the caller owns the crop and will hand it to the send path. The
  // delivery flag is only set after the caller truly has the file, so a
  // recorder disposed between the service's delivery and this line still
  // sees an unaccepted request and reclaims its own crop — and only that crop.
  if (accept != null) {
    accept(cropped);
  } else if (local != null) {
    local.accept(cropped);
  } else {
    VideoNoteCropService.accept(cropped);
  }
  return cropped;
}

/// An owned video-message camera with Telegram-style hold, cancel, lock and
/// pause controls. Keeping capture inside the app also lets users switch the
/// active lens before recording instead of being sent to the system camera.
///
/// Camera-route chrome over the black preview (concrete values, no shortcuts):
///  * the round control surfaces are white at 16% (`0x29FFFFFF`) with a 25%
///    white outline (`0x40FFFFFF`) — a translucent light film over the live
///    preview, not an opaque mid-gray pill;
///  * a disabled control drops to white at 8% (`0x14FFFFFF`) with a 12%
///    outline (`0x1FFFFFFF`) and 40% icon opacity;
///  * the shutter disc keeps the full-strength red `0xFFE53935` while it is
///    the record affordance, and turns into the brand-accent square while a
///    locked recording is waiting to be stopped.
class VideoNoteRecorderView extends StatefulWidget {
  const VideoNoteRecorderView({super.key});

  @override
  State<VideoNoteRecorderView> createState() => _VideoNoteRecorderViewState();
}

class _VideoNoteRecorderViewState extends State<VideoNoteRecorderView>
    with WidgetsBindingObserver {
  static const _maximumDuration = Duration(seconds: 60);

  /// How long a recorder waits for the previous camera to be released before
  /// it tries to open its own.
  static const _releaseWaitLimit = Duration(seconds: 5);

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  // A native reply may still update the controller. Drain its outstanding
  // calls before disposal and await disposal before opening another lens.
  final _pending = <Future<void>>{};
  // A freshly pushed recorder also waits for the previous route to release hardware.
  static Future<void>? _released;
  int _session = 0;
  bool _suspended = false;
  bool _starting = false;
  bool _releasedShutter = false;
  Future<void>? _pauseCommand;
  int _cameraIndex = 0;
  List<double> _zoomLevels = const [];
  double _zoom = 1;
  bool _settingZoom = false;
  bool _initializing = true;
  bool _recording = false;
  bool _paused = false;
  bool _locked = false;
  bool _finishing = false;
  double _pressStartX = 0;
  double _pressStartY = 0;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  String? _error;

  /// The export this recorder started, or `null` when no export is in flight.
  ///
  /// A ticket — not a global "last export" slot — owns the produced file, so
  /// a route disposed mid-export abandons only its own export and never a
  /// second recorder instance's still-pending handoff. Scope is a single
  /// [State]-liveness; missing traces are reclaimed by the platform.
  VideoNoteCropTicket? _cropTicket;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCameras());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera and microphone permission prompts make the app inactive
    // while the first camera is still opening. Tearing that camera down only
    // to reopen it the moment the prompt closes opened the device twice; a
    // real trip to the background still arrives as hidden/paused below.
    final permissionPrompt =
        state == AppLifecycleState.inactive && _initializing && !_recording;
    if (!permissionPrompt &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      if (_suspended) return;
      _suspended = true;
      ++_session;
      if (_recording && !_finishing) unawaited(_cancelRecording());
      setState(() => _initializing = true);
      unawaited(_disposeController());
    } else if (state == AppLifecycleState.resumed && _suspended) {
      _suspended = false;
      unawaited(
        _cameras.isEmpty ? _loadCameras() : _initializeCamera(_cameraIndex),
      );
    }
  }

  int _preferredCamera(CameraLensDirection direction) {
    final candidates = _cameras.indexed.where(
      (entry) => entry.$2.lensDirection == direction,
    );
    if (candidates.isEmpty) return -1;
    int rank(CameraDescription camera) => switch (camera.lensType) {
      CameraLensType.wide => 0,
      // CameraX may expose only Camera2 IDs. ID 0 is a common primary
      // rear camera, a hint only for a lens with no type metadata.
      CameraLensType.unknown
          when direction == CameraLensDirection.back && camera.name == '0' =>
        1,
      CameraLensType.ultraWide => 2,
      CameraLensType.unknown => 3,
      CameraLensType.telephoto => 4,
    };
    return candidates.reduce((a, b) => rank(b.$2) < rank(a.$2) ? b : a).$1;
  }

  bool _active(int session) => mounted && !_suspended && _session == session;

  Future<void> _loadCameras() async {
    final session = ++_session;
    try {
      final cameras = await availableCameras();
      if (!_active(session)) return;
      if (cameras.isEmpty) {
        setState(() => _initializing = false);
        return;
      }
      _cameras = cameras;
      final front = _preferredCamera(CameraLensDirection.front);
      final back = _preferredCamera(CameraLensDirection.back);
      await _initializeCamera(
        front >= 0
            ? front
            : back >= 0
            ? back
            : 0,
      );
    } catch (error) {
      if (_active(session)) {
        setState(() {
          _initializing = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<T> _track<T>(Future<T> operation) {
    final done = operation.then<void>((_) {}, onError: (Object _) {});
    _pending.add(done);
    unawaited(done.then((_) => _pending.remove(done)));
    return operation;
  }

  Future<bool> _optional(Future<void> Function() command) async {
    try {
      await _track(command());
      return true;
    } catch (error) {
      if (error is! CameraException &&
          error is! PlatformException &&
          error is! MissingPluginException &&
          error is! UnimplementedError) {
        rethrow;
      }
      debugPrint('Video note camera setting unavailable: $error');
      return false;
    }
  }

  Future<void> _initializeCamera(int index) async {
    final session = ++_session;
    _cameraIndex = index;
    setState(() {
      _initializing = true;
      _error = null;
      _zoomLevels = const [];
      _settingZoom = false;
    });
    // A native call that never answers would otherwise keep every later
    // recorder on a spinner until the app restarts. After the bound, opening
    // is attempted anyway; if the old camera still holds the device, that
    // attempt fails with a readable error the user can close.
    await _disposeController().timeout(
      _releaseWaitLimit,
      onTimeout: () => debugPrint('Video note camera release is still pending'),
    );
    if (!_active(session)) return;
    final controller = CameraController(_cameras[index], ResolutionPreset.high);
    _controller = controller;
    try {
      await _track(controller.initialize());
      if (!_active(session)) return;
      await _track(controller.prepareForVideoRecording());
      if (!_active(session)) return;
      await _optional(() => controller.setFocusMode(FocusMode.auto));
      if (!_active(session)) return;
      await _optional(() => controller.setExposureMode(ExposureMode.auto));
      if (!_active(session)) return;
      var levels = <double>[];
      var zoom = 1.0;
      await _optional(() async {
        final min = await controller.getMinZoomLevel();
        if (!_active(session)) return;
        final max = await controller.getMaxZoomLevel();
        if (!_active(session) ||
            !min.isFinite ||
            !max.isFinite ||
            min <= 0 ||
            min >= max) {
          return;
        }
        zoom = 1.0.clamp(min, max);
        await controller.setZoomLevel(zoom);
        levels = {
          min,
          zoom,
          0.5.clamp(min, max),
          2.0.clamp(min, max),
          3.0.clamp(min, max),
        }.toList()..sort();
        if (levels.length == 1) levels.add(max);
      });
      if (!_active(session)) return;
      setState(() {
        _zoom = zoom;
        _zoomLevels = levels;
        _initializing = false;
      });
    } catch (error) {
      if (!_active(session)) return;
      unawaited(_disposeController());
      setState(() {
        _initializing = false;
        _error = error is CameraException
            ? error.description ?? error.code
            : error.toString();
      });
    }
  }

  Future<void> _disposeController() {
    final controller = _controller;
    _controller = null;
    if (controller == null) return _released ?? Future.value();
    final release = _releaseAfterPending(
      controller,
      _pending.toList(),
      detachFirst: mounted,
    );
    _released = release;
    return release.whenComplete(() {
      if (identical(_released, release)) _released = null;
    });
  }

  Future<void> _releaseAfterPending(
    CameraController controller,
    List<Future<void>> pending, {
    required bool detachFirst,
  }) async {
    await Future.wait(pending);
    // A mounted recorder (going back, backgrounding, switching lens) may still
    // show this controller's preview, and stopping a recording below marks
    // that preview for a rebuild. Releasing before the next frame left it to
    // build against a disposed controller, which throws. The caller has
    // already dropped the controller from state, so after one frame nothing
    // on screen refers to it.
    if (detachFirst) await WidgetsBinding.instance.endOfFrame;
    try {
      // The route may have closed before the native start reply arrived.
      if (controller.value.isRecordingVideo) {
        final abandoned = await controller.stopVideoRecording();
        final file = File(abandoned.path);
        if (await file.exists()) await file.delete();
      }
    } catch (error) {
      debugPrint('Video note cleanup: $error');
    } finally {
      try {
        await controller.dispose();
      } on CameraException catch (error) {
        debugPrint('Video note camera release: $error');
      } on PlatformException catch (error) {
        debugPrint('Video note camera release: $error');
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_initializing ||
        _starting ||
        _finishing ||
        _recording ||
        _cameras.length < 2) {
      return;
    }
    final current = _cameras[_cameraIndex].lensDirection;
    final target = current == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    var next = _preferredCamera(target);
    if (next < 0) next = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera(next);
  }

  Future<void> _setZoom(double level) async {
    final controller = _controller;
    if (controller == null || _settingZoom || _finishing || _initializing) {
      return;
    }
    _settingZoom = true;
    try {
      final accepted = await _optional(() => controller.setZoomLevel(level));
      if (!mounted || !identical(controller, _controller)) return;
      setState(() {
        if (accepted) {
          _zoom = level;
        } else if (level != _zoom) {
          _zoomLevels.remove(level);
        }
      });
    } finally {
      if (identical(controller, _controller)) _settingZoom = false;
    }
  }

  Future<void> _startRecording({bool locked = false}) async {
    final controller = _controller;
    if (_initializing ||
        _starting ||
        _recording ||
        _finishing ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    _starting = true;
    _releasedShutter = false;
    try {
      await _track(controller.startVideoRecording());
      if (!mounted || !identical(controller, _controller)) return;
      setState(() {
        _recording = true;
        _paused = false;
        _locked = locked;
        _elapsed = Duration.zero;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || _paused) return;
        setState(() => _elapsed += const Duration(milliseconds: 100));
        if (_elapsed >= _maximumDuration) unawaited(_finishRecording());
      });
      if (_releasedShutter && !locked) await _finishRecording();
    } on CameraException catch (error) {
      if (mounted && identical(controller, _controller)) {
        setState(() => _error = error.description ?? error.code);
      }
    } finally {
      _starting = false;
    }
  }

  Future<void> _togglePause() async {
    final controller = _controller;
    if (!_recording ||
        _pauseCommand != null ||
        _finishing ||
        controller == null) {
      return;
    }
    try {
      _pauseCommand = _paused
          ? controller.resumeVideoRecording()
          : controller.pauseVideoRecording();
      await _track(_pauseCommand!);
      if (mounted && identical(controller, _controller) && _recording) {
        setState(() => _paused = !_paused);
      }
    } on CameraException catch (error) {
      if (mounted) setState(() => _error = error.description ?? error.code);
    } finally {
      _pauseCommand = null;
    }
  }

  Future<XFile> _stopRecording(CameraController controller) async {
    final pause = _pauseCommand;
    if (pause != null) {
      try {
        await pause;
      } on CameraException {
        /* Stop even if pause failed. */
      }
    }
    return controller.stopVideoRecording();
  }

  Future<void> _finishRecording() async {
    final controller = _controller;
    if (!_recording || _finishing || controller == null) return;
    final route = ModalRoute.of(context);
    _finishing = true;
    _timer?.cancel();
    try {
      final video = await _track(_stopRecording(controller));
      if (!mounted || route?.isCurrent != true) {
        // No consumer remains and no crop has started. Reclaim this recording
        // without starting another native encode for a disposed route.
        await _abandonCropAfterResolve(video.path, video.path);
        return;
      }
      final seconds =
          (_elapsed.inMilliseconds < 1000
                  ? 1
                  : (_elapsed.inMilliseconds / 1000).ceil().clamp(1, 60))
              .toInt();
      // The camera records 16:9 while both the preview and the received bubble
      // show a centred square; crop the file so the note is what was recorded.
      // Ownership stays with this state via a ticket: a disposed recorder
      // surrenders only its own export, never a second recorder instance's
      // still-pending handoff.
      final path = await videoNoteUploadPath(
        video.path,
        onStarted: (ticket) => _cropTicket = ticket,
      );
      if (!mounted || route?.isCurrent != true) {
        // The recorder was left while the crop was still running: nobody will
        // send the file it produced, so drop it instead of leaving an unowned
        // temporary next to the recording. A crop accepted a microsecond
        // before dispose is no longer the service's to reclaim, so the file
        // this call resolved to and the discarded recording are reclaimed here.
        unawaited(_abandonCropAfterResolve(path, video.path));
        return;
      }
      Navigator.of(
        context,
      ).pop(VideoNoteCaptureResult(path: path, duration: seconds));
    } on CameraException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.description ?? error.code;
          _recording = false;
          _paused = false;
          _locked = false;
        });
      }
    } finally {
      _finishing = false;
    }
  }

  /// Surrenders this recorder's own export and, when a path already exists,
  /// reclaims the discarded recording and output without touching another ticket.
  Future<void> _abandonCropAfterResolve(
    String path,
    String recordingPath,
  ) async {
    for (final ownedPath in {path, recordingPath}) {
      try {
        final file = File(ownedPath);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // The platform cache reclaims it anyway.
      }
    }
    // The ticket owns the file; surrender exactly this request's export so a
    // second recorder that is still handing its crop to the send path is
    // untouched. When the service already accepted it (handed to the send path
    // via videoNoteUploadPath), abandon is a no-op and the send path owns the
    // file.
    final ticket = _cropTicket;
    _cropTicket = null;
    if (ticket != null) await ticket.abandon();
  }

  Future<void> _cancelRecording() async {
    final controller = _controller;
    if (!_recording || _finishing || controller == null) return;
    _finishing = true;
    _timer?.cancel();
    try {
      final video = await _track(_stopRecording(controller));
      try {
        final file = File(video.path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // The temporary camera file is reclaimed by the platform cache.
      }
    } catch (_) {
      // The recording may already have been stopped by the lifecycle.
    } finally {
      _finishing = false;
      if (mounted) {
        setState(() {
          _recording = false;
          _paused = false;
          _locked = false;
          _elapsed = Duration.zero;
        });
      }
    }
  }

  String get _elapsedLabel =>
      formatMediaDuration(_elapsed.inSeconds.clamp(0, 60));

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope<VideoNoteCaptureResult>(
      onPopInvokedWithResult: (popped, _) {
        if (!popped) return;
        WidgetsBinding.instance.removeObserver(this);
        _suspended = true;
        ++_session;
        _timer?.cancel();
        final release = _disposeController();
        // The route stays on screen for its reverse transition: rebuild now
        // so it stops showing the preview of the camera being released.
        setState(() => _initializing = true);
        unawaited(release);
      },
      child: ColoredBox(
        color: Colors.black,
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!_initializing &&
                  controller != null &&
                  controller.value.isInitialized)
                _preview(controller)
              else if (_initializing)
                const Center(child: AppActivityIndicator(color: Colors.white))
              else
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      [
                        AppStrings.t(AppStringKeys.storyCameraUnavailable),
                        if (_error != null) _error,
                      ].join('\n'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                ),
              Positioned(
                left: 12,
                top: 8,
                child: _roundButton(
                  icon: HeroAppIcons.xmark,
                  label: AppStrings.t(
                    AppStringKeys.videoNoteRecorderCloseCamera,
                  ),
                  onTap: () {
                    if (_recording && !_finishing) {
                      unawaited(_cancelRecording());
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ),
              if (_recording)
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Text(
                        _paused ? 'Paused · $_elapsedLabel' : _elapsedLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              if (controller != null &&
                  !_initializing &&
                  _zoomLevels.length > 1)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 110,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    children: [
                      for (final level in _zoomLevels)
                        Semantics(
                          button: true,
                          selected: _zoom == level,
                          child: GestureDetector(
                            onTap: () => _setZoom(level),
                            child: Container(
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xB3000000),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: _zoom == level
                                      ? Colors.white
                                      : Colors.transparent,
                                ),
                              ),
                              child: Center(
                                widthFactor: 1,
                                heightFactor: 1,
                                child: Text(
                                  '${level == level.truncateToDouble() ? level.toStringAsFixed(0) : level.toString()}×',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Positioned(left: 18, right: 18, bottom: 22, child: _controls()),
            ],
          ),
        ),
      ),
    );
  }

  /// Fills the recorder with the live preview without distorting it.
  ///
  /// Only the available area is measured here; [VideoNotePreviewBox] then
  /// keeps its box at the same ratio [CameraPreview] uses (see
  /// [videoNotePreviewAspectRatio]) and scales that box to cover the window.
  /// The box listens to the controller itself, so an orientation or recording
  /// change repaints the tight outer footprint even when the window, and
  /// therefore these constraints, stay exactly the same size.
  Widget _preview(CameraController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final measured = constraints.biggest;
        final viewport = measured.isFinite && !measured.isEmpty
            ? measured
            : MediaQuery.sizeOf(context);
        return VideoNotePreviewBox(
          controller: controller,
          viewport: viewport,
          onFocus: (point) {
            if (!_finishing && identical(controller, _controller)) {
              unawaited(_optional(() => controller.setFocusPoint(point)));
            }
          },
        );
      },
    );
  }

  Widget _controls() {
    if (_recording && _locked) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: HeroAppIcons.trash,
            label: AppStrings.t(AppStringKeys.videoNoteRecorderCancelRecording),
            onTap: () => unawaited(_cancelRecording()),
          ),
          _roundButton(
            icon: _paused ? HeroAppIcons.play : HeroAppIcons.pause,
            label: _paused ? 'Resume recording' : 'Pause recording',
            onTap: () => unawaited(_togglePause()),
          ),
          _recordButton(
            locked: true,
            onTap: () => unawaited(_finishRecording()),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        const SizedBox(width: 48),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => unawaited(_startRecording(locked: true)),
          onLongPressStart: (details) {
            _pressStartX = details.globalPosition.dx;
            _pressStartY = details.globalPosition.dy;
            unawaited(_startRecording());
          },
          onLongPressMoveUpdate: (details) {
            if (!_recording || _locked) return;
            final dx = details.globalPosition.dx - _pressStartX;
            final dy = details.globalPosition.dy - _pressStartY;
            switch (videoNoteRecordGestureForDelta(dx: dx, dy: dy)) {
              case VideoNoteRecordGesture.cancel:
                unawaited(_cancelRecording());
                break;
              case VideoNoteRecordGesture.lock:
                setState(() => _locked = true);
                break;
              case VideoNoteRecordGesture.continueRecording:
                break;
            }
          },
          onLongPressEnd: (_) {
            _releasedShutter = true;
            if (_recording && !_locked) unawaited(_finishRecording());
          },
          child: _recordButton(),
        ),
        _roundButton(
          icon: HeroAppIcons.arrowsRotate,
          label: AppStrings.t(AppStringKeys.videoNoteRecorderSwitchCamera),
          onTap:
              !_recording && !_initializing && !_starting && _cameras.length > 1
              ? () => unawaited(_switchCamera())
              : null,
        ),
      ],
    );
  }

  Widget _recordButton({bool locked = false, VoidCallback? onTap}) {
    final button = Semantics(
      button: true,
      label: locked
          ? 'Stop video message'
          : 'Hold to record, slide up to lock, left to cancel',
      child: Container(
        key: const ValueKey('videoNoteRecordButton'),
        width: 76,
        height: 76,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: AnimatedContainer(
          key: const ValueKey('videoNoteRecordButtonDisc'),
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            // Full-strength red while the disc is the record affordance; the
            // accent square replaces it once the recording is locked and the
            // press becomes "stop".
            color: locked ? AppTheme.brand : const Color(0xFFE53935),
            shape: locked ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: locked
                ? BorderRadius.circular(AppRadius.control)
                : null,
          ),
        ),
      ),
    );
    return onTap == null
        ? button
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: button,
          );
  }

  Widget _roundButton({
    required AppIconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: ValueKey('videoNoteRecorderRoundButton-$label'),
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // A uniform light film over the black preview rather than an
            // opaque mid-gray slab; disabled controls fade out instead of
            // keeping a solid plate.
            color: onTap == null
                ? const Color(0x14FFFFFF)
                : const Color(0x29FFFFFF),
            shape: BoxShape.circle,
            border: Border.all(
              color: onTap == null
                  ? const Color(0x1FFFFFFF)
                  : const Color(0x40FFFFFF),
              width: 0.5,
            ),
          ),
          child: AppIcon(
            icon,
            size: 22,
            color: Colors.white.withValues(alpha: onTap == null ? 0.4 : 1),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    ++_session;
    WidgetsBinding.instance.removeObserver(this);
    // A route closed mid-export owns no result: this recorder's own ticket is
    // surrendered when its platform call completes, even when that is long
    // after dispose returned. A recorder with no ticket never started an
    // export of its own, so it surrenders nothing — a global sweep here
    // could reclaim another live recorder's pending or accepted crop.
    final ticket = _cropTicket;
    _cropTicket = null;
    if (ticket != null) {
      unawaited(ticket.abandon());
    }
    _timer?.cancel();
    unawaited(_disposeController());
    super.dispose();
  }
}
