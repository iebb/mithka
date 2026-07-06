import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

class QrLoginScannerView extends StatefulWidget {
  const QrLoginScannerView({super.key});

  @override
  State<QrLoginScannerView> createState() => _QrLoginScannerViewState();
}

class _QrLoginScannerViewState extends State<QrLoginScannerView> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _accepting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _handleCapture,
              placeholderBuilder: (context) => const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2.4),
                  ),
                ),
              ),
              errorBuilder: (context, error) => ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text(
                      AppStrings.t(AppStringKeys.privacyLoginQrAcceptFailed),
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
            ),
          ),
          Positioned.fill(child: _ScannerOverlay(accepting: _accepting)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  _CircleButton(
                    icon: HeroAppIcons.xmark,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const Spacer(),
                  _CircleButton(
                    icon: HeroAppIcons.camera,
                    onTap: _accepting ? null : _controller.switchCamera,
                  ),
                  const SizedBox(width: 12),
                  ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _controller,
                    builder: (context, state, _) => _CircleButton(
                      icon: HeroAppIcons.flash,
                      active: state.torchState == TorchState.on,
                      onTap:
                          _accepting ||
                              state.torchState == TorchState.unavailable
                          ? null
                          : _controller.toggleTorch,
                    ),
                  ),
                ],
              ),
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
                    fontWeight: FontWeight.w700,
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
        ],
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
                  borderRadius: BorderRadius.circular(28),
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
