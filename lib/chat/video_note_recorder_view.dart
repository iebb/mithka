import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

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

/// An owned video-message camera with Telegram-style hold, cancel, lock and
/// pause controls. Keeping capture inside the app also lets users switch the
/// active lens before recording instead of being sent to the system camera.
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
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(VideoNoteCaptureResult(path: video.path, duration: seconds));
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

  String get _elapsedLabel {
    final seconds = _elapsed.inSeconds.clamp(0, 60);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

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
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: CameraPreview(controller),
                ),
              )
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
                label: 'Close camera',
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
                      borderRadius: BorderRadius.circular(16),
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

  Widget _controls() {
    if (_recording && _locked) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _roundButton(
            icon: HeroAppIcons.trash,
            label: 'Cancel recording',
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
          label: 'Switch camera',
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
        width: 76,
        height: 76,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: locked ? AppTheme.brand : const Color(0xFFE53935),
            shape: locked ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: locked ? BorderRadius.circular(10) : null,
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
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: onTap == null ? 0.25 : 0.55),
            shape: BoxShape.circle,
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
    _timer?.cancel();
    unawaited(_controller?.dispose());
    _controller = null;
    super.dispose();
  }
}
