import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../platform/camera_permission.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

typedef QrLoginScannerBuilder =
    Widget Function(
      BuildContext context,
      MobileScannerController controller,
      void Function(BarcodeCapture capture) onDetect,
    );

class QrLoginScannerView extends StatefulWidget {
  const QrLoginScannerView({
    super.key,
    this.cameraPermission = const SystemCameraPermissionGateway(),
    this.scannerBuilder,
  });

  final CameraPermissionGateway cameraPermission;

  @visibleForTesting
  final QrLoginScannerBuilder? scannerBuilder;

  @override
  State<QrLoginScannerView> createState() => _QrLoginScannerViewState();
}

class _QrLoginScannerViewState extends State<QrLoginScannerView>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  CameraPermissionAccess? _cameraAccess;
  bool _permissionBusy = false;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_resolveCameraPermission(request: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resolveCameraPermission(request: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _resolveCameraPermission({required bool request}) async {
    if (_permissionBusy) return;
    _permissionBusy = true;
    if (mounted) setState(() {});
    CameraPermissionAccess access;
    try {
      access = request
          ? await widget.cameraPermission.request()
          : await widget.cameraPermission.check();
    } catch (_) {
      access = CameraPermissionAccess.denied;
    } finally {
      _permissionBusy = false;
    }
    if (!mounted) return;
    setState(() => _cameraAccess = access);
  }

  Future<void> _openCameraSettings() async {
    await widget.cameraPermission.openSettings();
    if (!mounted) return;
    await _resolveCameraPermission(request: false);
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    if (_accepting) return;
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue ?? barcode.displayValue)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .firstOrNull;
    if (raw == null) return;

    setState(() => _accepting = true);
    try {
      await _controller.stop();
      await TdClient.shared.acceptLoginQrLink(raw);
      if (!mounted) return;
      showToast(context, AppStringKeys.privacyLoginQrAccepted);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        error is FormatException
            ? AppStringKeys.privacyLoginQrInvalid
            : AppStringKeys.privacyLoginQrAcceptFailed,
      );
      setState(() => _accepting = false);
      await _controller.start();
    }
  }

  Future<void> _switchCamera() async {
    final state = _controller.value;
    if (_accepting || !state.isInitialized || !state.isRunning) return;
    await _controller.switchCamera();
  }

  Future<void> _toggleTorch() async {
    final state = _controller.value;
    if (_accepting ||
        !state.isInitialized ||
        !state.isRunning ||
        state.torchState == TorchState.unavailable) {
      return;
    }
    await _controller.toggleTorch();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStringKeys.privacyScanLoginQr,
      onBack: () => Navigator.of(context).pop(false),
      constrainContent: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: _cameraAccess == CameraPermissionAccess.granted
                ? widget.scannerBuilder?.call(
                        context,
                        _controller,
                        _handleCapture,
                      ) ??
                      MobileScanner(
                        key: const ValueKey('qr-login-mobile-scanner'),
                        controller: _controller,
                        onDetect: _handleCapture,
                        placeholderBuilder: (context) => const ColoredBox(
                          color: Colors.black,
                          child: Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2.4,
                              ),
                            ),
                          ),
                        ),
                        errorBuilder: (context, error) => ColoredBox(
                          color: Colors.black,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 36,
                              ),
                              child: Text(
                                AppStrings.t(
                                  AppStringKeys.qrScannerCameraUnavailable,
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 15,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ),
                        ),
                      )
                : const ColoredBox(color: Colors.black),
          ),
          Positioned.fill(child: _ScannerOverlay(accepting: _accepting)),
          Positioned(
            top: AppSpacing.lg,
            right: AppSpacing.xxl,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _controller,
                  builder: (context, state, _) => _CircleButton(
                    icon: HeroAppIcons.camera,
                    onTap: !_accepting && state.isInitialized && state.isRunning
                        ? _switchCamera
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                ValueListenableBuilder<MobileScannerState>(
                  valueListenable: _controller,
                  builder: (context, state, _) => _CircleButton(
                    icon: HeroAppIcons.flash,
                    active: state.torchState == TorchState.on,
                    onTap:
                        _accepting ||
                            !state.isInitialized ||
                            !state.isRunning ||
                            state.torchState == TorchState.unavailable
                        ? null
                        : _toggleTorch,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 28,
            right: 28,
            bottom: MediaQuery.of(context).padding.bottom + 34,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.t(AppStringKeys.privacyScanLoginQr),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.t(AppStringKeys.privacyScanLoginQrSubtitle),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xCCFFFFFF),
                    fontSize: 14,
                    height: 1.35,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
          if (_cameraAccess != CameraPermissionAccess.granted)
            Positioned.fill(child: _cameraPermissionState()),
        ],
      ),
    );
  }

  Widget _cameraPermissionState() {
    final checking = _cameraAccess == null || _permissionBusy;
    final blocked = _cameraAccess == CameraPermissionAccess.blocked;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (checking)
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2.4),
                )
              else ...[
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    HeroAppIcons.camera,
                    size: 32,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  AppStrings.t(AppStringKeys.qrScannerCameraUnavailable),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 16,
                    height: 1.35,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  key: ValueKey(
                    blocked
                        ? 'qr-login-camera-open-settings'
                        : 'qr-login-camera-retry',
                  ),
                  behavior: HitTestBehavior.opaque,
                  onTap: blocked
                      ? _openCameraSettings
                      : () =>
                            unawaited(_resolveCameraPermission(request: true)),
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.brand,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Text(
                      AppStrings.t(
                        blocked
                            ? AppStringKeys.storyOpenSettings
                            : AppStringKeys.privacyRetry,
                      ),
                      style: const TextStyle(
                        color: Color(0xFFFFFFFF),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  const _ScannerOverlay({required this.accepting});

  final bool accepting;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxWidth * 0.68).clamp(230.0, 320.0);
        return Stack(
          children: [
            Container(color: const Color(0x66000000)),
            Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: side,
                height: side,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.xxl),
                  border: Border.all(
                    color: accepting ? AppTheme.brand : const Color(0xFFFFFFFF),
                    width: 3,
                  ),
                ),
                child: accepting
                    ? Center(
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2.8,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.brand,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final AppIconData icon;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? AppTheme.brand : const Color(0x66000000),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        child: Center(
          child: AppIcon(
            icon,
            size: 22,
            color: onTap == null
                ? const Color(0x66FFFFFF)
                : const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}
