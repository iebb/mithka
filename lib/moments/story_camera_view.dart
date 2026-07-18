import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class StoryCameraResult {
  const StoryCameraResult.capture(this.file) : openGallery = false;
  const StoryCameraResult.gallery() : file = null, openGallery = true;

  final XFile? file;
  final bool openGallery;
}

class StoryCameraView extends StatefulWidget {
  const StoryCameraView({super.key});

  @override
  State<StoryCameraView> createState() => _StoryCameraViewState();
}

class _StoryCameraViewState extends State<StoryCameraView>
    with WidgetsBindingObserver {
  static const _maximumVideoDuration = Duration(seconds: 60);

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _capturing = false;
  bool _recording = false;
  bool _flashEnabled = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadCameras());
  }

  Future<void> _loadCameras() async {
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) throw StateError('No camera is available.');
      _cameras = cameras;
      final back = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      _cameraIndex = back >= 0 ? back : 0;
      await _initializeCamera(_cameraIndex);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
      });
    }
  }

  Future<void> _initializeCamera(int index) async {
    if (_cameras.isEmpty || index < 0 || index >= _cameras.length) return;
    setState(() {
      _initializing = true;
    });
    await _disposeController();
    final controller = CameraController(_cameras[index], ResolutionPreset.high);
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted || !identical(_controller, controller)) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraIndex = index;
        _initializing = false;
      });
    } on CameraException catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
      });
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) await controller.dispose();
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (_capturing ||
        _recording ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      if (mounted) Navigator.of(context).pop(StoryCameraResult.capture(file));
    } on CameraException catch (error) {
      debugPrint('Story photo capture failed: ${error.code}');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (_capturing ||
        _recording ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    try {
      await controller.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!mounted || !_recording) return;
        setState(() => _elapsed += const Duration(milliseconds: 100));
        if (_elapsed >= _maximumVideoDuration) unawaited(_finishRecording());
      });
    } on CameraException catch (error) {
      debugPrint('Story video recording failed: ${error.code}');
    }
  }

  Future<void> _finishRecording() async {
    final controller = _controller;
    if (!_recording || _capturing || controller == null) return;
    setState(() => _capturing = true);
    _timer?.cancel();
    try {
      final file = await controller.stopVideoRecording();
      if (mounted) Navigator.of(context).pop(StoryCameraResult.capture(file));
    } on CameraException catch (_) {
      if (mounted) {
        setState(() {
          _recording = false;
        });
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _switchCamera() async {
    if (_recording || _capturing || _cameras.length < 2) return;
    final currentDirection = _cameras[_cameraIndex].lensDirection;
    var next = (_cameraIndex + 1) % _cameras.length;
    for (var offset = 1; offset <= _cameras.length; offset++) {
      final candidate = (_cameraIndex + offset) % _cameras.length;
      if (_cameras[candidate].lensDirection != currentDirection) {
        next = candidate;
        break;
      }
    }
    await _initializeCamera(next);
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (_recording || controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      final enabled = !_flashEnabled;
      await controller.setFlashMode(enabled ? FlashMode.auto : FlashMode.off);
      if (mounted) setState(() => _flashEnabled = enabled);
    } on CameraException catch (error) {
      debugPrint('Story camera flash failed: ${error.code}');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_recording) {
        unawaited(_finishRecording());
      } else {
        unawaited(_disposeController());
      }
    } else if (state == AppLifecycleState.resumed && !_recording) {
      unawaited(_initializeCamera(_cameraIndex));
    }
  }

  String get _elapsedLabel {
    final seconds = _elapsed.inSeconds.clamp(0, 60);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: ColoredBox(
                    color: const Color(0xFF1C1C1E),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (controller != null &&
                            controller.value.isInitialized)
                          Center(
                            child: AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: CameraPreview(controller),
                            ),
                          )
                        else if (_initializing)
                          const Center(
                            child: AppActivityIndicator(color: Colors.white),
                          )
                        else
                          _permissionMessage(),
                        Positioned(
                          left: 14,
                          top: 14,
                          child: _roundButton(
                            icon: HeroAppIcons.xmark,
                            label: 'Close camera',
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ),
                        Positioned(
                          right: 14,
                          top: 14,
                          child: _roundButton(
                            icon: HeroAppIcons.flash,
                            label: 'Automatic flash',
                            active: _flashEnabled,
                            onTap: _toggleFlash,
                          ),
                        ),
                        if (_recording)
                          Positioned(
                            top: 22,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xB3000000),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Text(
                                  _elapsedLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 128,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _roundButton(
                    icon: HeroAppIcons.images,
                    label: 'Open gallery',
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const StoryCameraResult.gallery()),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _capturePhoto,
                    onLongPressStart: (_) => unawaited(_startRecording()),
                    onLongPressEnd: (_) => unawaited(_finishRecording()),
                    child: Container(
                      width: 78,
                      height: 78,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        decoration: BoxDecoration(
                          color: _recording
                              ? const Color(0xFFE53935)
                              : Colors.white,
                          shape: _recording
                              ? BoxShape.rectangle
                              : BoxShape.circle,
                          borderRadius: _recording
                              ? BorderRadius.circular(13)
                              : null,
                        ),
                      ),
                    ),
                  ),
                  _roundButton(
                    icon: HeroAppIcons.arrowsRotate,
                    label: 'Switch camera',
                    onTap: _cameras.length > 1 ? _switchCamera : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionMessage() {
    final noCamera = _cameras.isEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const AppIcon(
                HeroAppIcons.camera,
                size: 38,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              (noCamera
                      ? AppStringKeys.storyCameraUnavailable
                      : AppStringKeys.storyCameraAccessTitle)
                  .l10n(context),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              (noCamera
                      ? AppStringKeys.storyChooseMediaHint
                      : AppStringKeys.storyCameraAccessDescription)
                  .l10n(context),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFA1A1AA),
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: noCamera
                  ? () => Navigator.of(
                      context,
                    ).pop(const StoryCameraResult.gallery())
                  : openAppSettings,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  (noCamera
                          ? AppStringKeys.storyGallery
                          : AppStringKeys.storyOpenSettings)
                      .l10n(context),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roundButton({
    required AppIconData icon,
    required String label,
    FutureOr<void> Function()? onTap,
    bool active = false,
  }) => Semantics(
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
          color: active
              ? AppTheme.brand
              : Colors.black.withValues(alpha: onTap == null ? 0.28 : 0.58),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: AppIcon(
          icon,
          size: 22,
          color: Colors.white.withValues(alpha: onTap == null ? 0.38 : 1),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_controller?.dispose());
    _controller = null;
    super.dispose();
  }
}
