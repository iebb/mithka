import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../chat/link_handler.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../theme/app_theme.dart';

class QrScanCandidate {
  const QrScanCandidate({required this.value, required this.type});

  final String value;
  final BarcodeType type;

  bool get isTelegram => isTelegramQrValue(value);
  bool get isUrl {
    var candidate = value.trim();
    if (candidate.startsWith('www.')) candidate = 'https://$candidate';
    final uri = Uri.tryParse(candidate);
    return uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https');
  }
}

bool isTelegramQrValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return false;
  if (value.toLowerCase().startsWith('tg:')) return true;
  var candidate = value;
  if (!candidate.contains('://')) candidate = 'https://$candidate';
  final uri = Uri.tryParse(candidate);
  if (uri == null) return false;
  return const {
    't.me',
    'www.t.me',
    'telegram.me',
    'www.telegram.me',
    'telegram.dog',
    'www.telegram.dog',
  }.contains(uri.host.toLowerCase());
}

List<QrScanCandidate> qrCandidatesFromCapture(BarcodeCapture capture) {
  final seen = <String>{};
  final candidates = <QrScanCandidate>[];
  for (final barcode in capture.barcodes) {
    final value = (barcode.rawValue ?? barcode.displayValue)?.trim();
    if (value == null || value.isEmpty || !seen.add(value)) continue;
    candidates.add(QrScanCandidate(value: value, type: barcode.type));
  }
  return candidates;
}

class QrScannerView extends StatefulWidget {
  const QrScannerView({super.key});

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView> {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  List<QrScanCandidate> _choices = const [];
  QrScanCandidate? _detail;
  bool _paused = false;
  double _panelDrag = 0;

  bool get _hasPanel => _choices.isNotEmpty || _detail != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_paused) return;
    final candidates = qrCandidatesFromCapture(capture);
    if (candidates.isEmpty) return;
    _paused = true;
    if (candidates.length == 1) {
      _selectCandidate(candidates.first);
      return;
    }
    setState(() {
      _choices = candidates;
      _detail = null;
      _panelDrag = 0;
    });
  }

  void _selectCandidate(QrScanCandidate candidate) {
    if (candidate.isTelegram) {
      Navigator.of(context).pop(candidate.value);
      return;
    }
    setState(() {
      _choices = const [];
      _detail = candidate;
      _panelDrag = 0;
    });
  }

  void _resumeScanning() {
    setState(() {
      _choices = const [];
      _detail = null;
      _panelDrag = 0;
      _paused = false;
    });
  }

  void _updatePanelDrag(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    if (delta <= 0 && _panelDrag <= 0) return;
    setState(() => _panelDrag = (_panelDrag + delta).clamp(0, 180));
  }

  void _finishPanelDrag(DragEndDetails details) {
    if (_panelDrag > 64 || (details.primaryVelocity ?? 0) > 520) {
      _resumeScanning();
    } else {
      setState(() => _panelDrag = 0);
    }
  }

  Future<void> _copyDetail() async {
    final value = _detail?.value;
    if (value == null) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) showToast(context, AppStringKeys.qrScannerCopied);
  }

  Future<void> _openDetail() async {
    final value = _detail?.value;
    if (value == null) return;
    await openLink(context, value);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _handleCapture,
              placeholderBuilder: (_) => const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.qrcode,
                    size: 44,
                    color: Color(0x99FFFFFF),
                  ),
                ),
              ),
              errorBuilder: (_, _) => ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Text(
                      AppStrings.t(AppStringKeys.qrScannerCameraUnavailable),
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
          Positioned.fill(
            child: BarcodeOverlay(
              controller: _controller,
              boxFit: BoxFit.cover,
              color: AppTheme.brand,
              style: PaintingStyle.stroke,
            ),
          ),
          Positioned.fill(child: _QrScannerFrame(dimmed: _hasPanel)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  _ScannerCircleButton(
                    icon: HeroAppIcons.xmark,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  _ScannerCircleButton(
                    icon: HeroAppIcons.arrowsRotate,
                    onTap: _controller.switchCamera,
                  ),
                  const SizedBox(width: 12),
                  ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _controller,
                    builder: (context, state, _) => _ScannerCircleButton(
                      icon: HeroAppIcons.flash,
                      active: state.torchState == TorchState.on,
                      onTap: state.torchState == TorchState.unavailable
                          ? null
                          : _controller.toggleTorch,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!_hasPanel)
            Positioned(
              left: 28,
              right: 28,
              bottom: MediaQuery.of(context).padding.bottom + 34,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppStrings.t(AppStringKeys.qrScannerTitle),
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
                    AppStrings.t(AppStringKeys.qrScannerHint),
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
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: 12,
            right: 12,
            bottom: _hasPanel
                ? MediaQuery.of(context).padding.bottom + 12 - _panelDrag
                : -420,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _updatePanelDrag,
              onVerticalDragEnd: _finishPanelDrag,
              child: _choices.isNotEmpty
                  ? _QrChoiceCard(
                      choices: _choices,
                      onSelect: _selectCandidate,
                      onClose: _resumeScanning,
                    )
                  : _QrDetailCard(
                      candidate: _detail,
                      onCopy: _copyDetail,
                      onOpen: _detail?.isUrl == true ? _openDetail : null,
                      onClose: _resumeScanning,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrScannerFrame extends StatelessWidget {
  const _QrScannerFrame({required this.dimmed});

  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxWidth * 0.68).clamp(230.0, 320.0);
        return IgnorePointer(
          child: Stack(
            children: [
              ColoredBox(
                color: dimmed
                    ? const Color(0x77000000)
                    : const Color(0x44000000),
                child: const SizedBox.expand(),
              ),
              Center(
                child: Container(
                  width: side,
                  height: side,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFFFFFFFF),
                      width: 2.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScannerCircleButton extends StatelessWidget {
  const _ScannerCircleButton({
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

class _QrChoiceCard extends StatelessWidget {
  const _QrChoiceCard({
    required this.choices,
    required this.onSelect,
    required this.onClose,
  });

  final List<QrScanCandidate> choices;
  final ValueChanged<QrScanCandidate> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return _QrBottomCard(
      title: AppStrings.t(AppStringKeys.qrScannerMultipleTitle),
      subtitle: AppStrings.t(AppStringKeys.qrScannerMultipleHint),
      onClose: onClose,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 230),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: choices.length,
          separatorBuilder: (_, _) => SizedBox(
            height: AppMetric.divider,
            child: ColoredBox(color: context.colors.divider),
          ),
          itemBuilder: (context, index) {
            final candidate = choices[index];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(candidate),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.colors.listHeaderTint,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: context.colors.linkBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            candidate.isTelegram
                                ? 'Telegram'
                                : candidate.isUrl
                                ? AppStrings.t(AppStringKeys.qrScannerLink)
                                : AppStrings.t(AppStringKeys.qrScannerText),
                            style: TextStyle(
                              color: context.colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            candidate.value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppIcon(
                      HeroAppIcons.chevronRight,
                      size: 18,
                      color: context.colors.textTertiary,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QrDetailCard extends StatelessWidget {
  const _QrDetailCard({
    required this.candidate,
    required this.onCopy,
    required this.onOpen,
    required this.onClose,
  });

  final QrScanCandidate? candidate;
  final VoidCallback onCopy;
  final VoidCallback? onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final value = candidate?.value ?? '';
    return _QrBottomCard(
      title: AppStrings.t(AppStringKeys.qrScannerDetailsTitle),
      subtitle: candidate?.isUrl == true
          ? AppStrings.t(AppStringKeys.qrScannerLink)
          : AppStrings.t(AppStringKeys.qrScannerText),
      onClose: onClose,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardIconButton(
            icon: HeroAppIcons.clipboard,
            tooltip: AppStrings.t(AppStringKeys.qrScannerCopy),
            onTap: onCopy,
          ),
          if (onOpen != null) ...[
            const SizedBox(width: 8),
            _CardIconButton(
              icon: HeroAppIcons.arrowTopRight,
              tooltip: AppStrings.t(AppStringKeys.qrScannerOpen),
              onTap: onOpen!,
            ),
          ],
        ],
      ),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 130),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.groupedBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          child: Text(
            value,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}

class _QrBottomCard extends StatelessWidget {
  const _QrBottomCard({
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.textTertiary.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              ?trailing,
              const SizedBox(width: 8),
              _CardIconButton(
                icon: HeroAppIcons.xmark,
                tooltip: AppStrings.t(AppStringKeys.musicPlayerClose),
                onTap: onClose,
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _CardIconButton extends StatelessWidget {
  const _CardIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final AppIconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.colors.listHeaderTint,
            shape: BoxShape.circle,
          ),
          child: AppIcon(icon, size: 19, color: context.colors.textPrimary),
        ),
      ),
    );
  }
}
