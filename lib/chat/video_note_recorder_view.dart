import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../media/media_metadata.dart';
import '../theme/app_theme.dart';
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
  });

  final CameraController controller;

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
              child: CameraPreview(controller),
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
/// function returns is never deleted by the service.
///
/// [crop] and [accept] exist so tests can drive the decision without a platform
/// channel; production passes neither and reaches [VideoNoteCropService].
Future<String> videoNoteUploadPath(
  String recordedPath, {
  Future<String?> Function(String path)? crop,
  void Function(String path)? accept,
}) async {
  String? cropped;
  try {
    cropped = await (crop ?? VideoNoteCropService.crop)(recordedPath);
  } catch (_) {
    cropped = null;
  }
  if (cropped == null || cropped.isEmpty || cropped == recordedPath) {
    return recordedPath;
  }
  try {
    if (!await File(cropped).exists()) return recordedPath;
  } catch (_) {
    return recordedPath;
  }
  try {
    final original = File(recordedPath);
    if (await original.exists()) await original.delete();
  } catch (_) {
    // Best-effort: the platform cache reclaims the recording anyway.
  }
  // The cropped file is verified and the recording it replaces is gone: from
  // here the caller owns the crop and will hand it to the send path.
  (accept ?? VideoNoteCropService.accept)(cropped);
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

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCameras());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_recording) {
        unawaited(_cancelRecording());
      } else {
        unawaited(_disposeController());
      }
    } else if (state == AppLifecycleState.resumed && !_recording) {
      unawaited(_initializeCamera(_cameraIndex));
    }
  }

  Future<void> _loadCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) throw StateError('No camera is available.');
      _cameras = cameras;
      final front = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      _cameraIndex = front >= 0 ? front : 0;
      await _initializeCamera(_cameraIndex);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _initializeCamera(int index) async {
    if (_cameras.isEmpty || index < 0 || index >= _cameras.length) return;
    if (mounted) {
      setState(() {
        _initializing = true;
        _error = null;
      });
    }
    await _disposeController();
    final controller = CameraController(_cameras[index], ResolutionPreset.high);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.prepareForVideoRecording();
      if (!mounted || !identical(_controller, controller)) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraIndex = index;
        _initializing = false;
      });
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = error.description ?? error.code;
      });
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) await controller.dispose();
  }

  Future<void> _switchCamera() async {
    if (_finishing || _recording || _cameras.length < 2) return;
    var next = (_cameraIndex + 1) % _cameras.length;
    final currentDirection = _cameras[_cameraIndex].lensDirection;
    for (var offset = 1; offset <= _cameras.length; offset++) {
      final candidate = (_cameraIndex + offset) % _cameras.length;
      if (_cameras[candidate].lensDirection != currentDirection) {
        next = candidate;
        break;
      }
    }
    await _initializeCamera(next);
  }

  Future<void> _startRecording({bool locked = false}) async {
    final controller = _controller;
    if (_recording ||
        _finishing ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.startVideoRecording();
      if (!mounted) return;
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
    } on CameraException catch (error) {
      if (mounted) setState(() => _error = error.description ?? error.code);
    }
  }

  Future<void> _togglePause() async {
    final controller = _controller;
    if (!_recording || _finishing || controller == null) return;
    try {
      if (_paused) {
        await controller.resumeVideoRecording();
      } else {
        await controller.pauseVideoRecording();
      }
      if (mounted) setState(() => _paused = !_paused);
    } on CameraException catch (error) {
      if (mounted) setState(() => _error = error.description ?? error.code);
    }
  }

  Future<void> _finishRecording() async {
    final controller = _controller;
    if (!_recording || _finishing || controller == null) return;
    _finishing = true;
    _timer?.cancel();
    try {
      final video = await controller.stopVideoRecording();
      final seconds =
          (_elapsed.inMilliseconds < 1000
                  ? 1
                  : (_elapsed.inMilliseconds / 1000).ceil().clamp(1, 60))
              .toInt();
      // The camera records 16:9 while both the preview and the received bubble
      // show a centred square; crop the file so the note is what was recorded.
      final path = await videoNoteUploadPath(video.path);
      if (!mounted) {
        // The recorder was left while the crop was still running: nobody will
        // send the file it produced, so drop it instead of leaving an unowned
        // temporary next to the recording. A crop accepted a microsecond
        // before dispose is no longer the service's to reclaim, so the file
        // this call resolved to is deleted here too; the recording itself is
        // only kept when it is the resolved path.
        unawaited(VideoNoteCropService.abandonInFlight());
        if (path != video.path) {
          try {
            final cropped = File(path);
            if (await cropped.exists()) await cropped.delete();
          } catch (_) {
            // The platform cache reclaims it anyway.
          }
        }
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

  Future<void> _cancelRecording() async {
    final controller = _controller;
    if (!_recording || _finishing || controller == null) return;
    _finishing = true;
    _timer?.cancel();
    try {
      final video = await controller.stopVideoRecording();
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
    return ColoredBox(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              _preview(controller)
            else if (_initializing)
              const Center(child: AppActivityIndicator(color: Colors.white))
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _error ?? 'Camera unavailable',
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
                label: AppStrings.t(AppStringKeys.videoNoteRecorderCloseCamera),
                onTap: _recording
                    ? () => unawaited(_cancelRecording())
                    : () => Navigator.of(context).pop(),
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
            Positioned(left: 18, right: 18, bottom: 22, child: _controls()),
          ],
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
        return VideoNotePreviewBox(controller: controller, viewport: viewport);
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
            if (_recording && !_locked) unawaited(_finishRecording());
          },
          child: _recordButton(),
        ),
        _roundButton(
          icon: HeroAppIcons.arrowsRotate,
          label: AppStrings.t(AppStringKeys.videoNoteRecorderSwitchCamera),
          onTap: _cameras.length > 1 ? () => unawaited(_switchCamera()) : null,
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
    WidgetsBinding.instance.removeObserver(this);
    // A route closed mid-export owns no result: the exporter's file is
    // reclaimed when it finishes.
    unawaited(VideoNoteCropService.abandonInFlight());
    _timer?.cancel();
    unawaited(_controller?.dispose());
    _controller = null;
    super.dispose();
  }
}
