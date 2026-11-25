import 'package:flutter/widgets.dart';

import '../../components/app_confirm_dialog.dart';
import '../../components/app_icons.dart';
import '../../components/app_interactive_surface.dart';
import '../../components/toast.dart';
import '../../components/ui_components.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'retained_download_store.dart';

/// Explicit opt-in for an already completed file; never completes a partial
/// download, changes automatic downloads, or removes an existing copy.
class RetainDownloadButton extends StatefulWidget {
  const RetainDownloadButton({
    super.key,
    required this.accountSlot,
    required this.fileId,
    required this.title,
    required this.isVideo,
    this.showLabel = false,
  });

  final int accountSlot;
  final int fileId;
  final String title;
  final bool isVideo;
  final bool showLabel;

  @override
  State<RetainDownloadButton> createState() => _RetainDownloadButtonState();
}

class _RetainDownloadButtonState extends State<RetainDownloadButton> {
  bool _busy = false;
  bool _confirming = false;

  Future<void> _keep() async {
    if (_busy || _confirming) return;
    setState(() => _confirming = true);
    try {
      final confirmed = await showAppConfirmDialog(
        context,
        title: AppStringKeys.downloadsKeepOnDevice,
        message: AppStringKeys.downloadsKeepExplanation,
        confirmText: AppStringKeys.downloadsKeepOnDevice,
      );
      if (!confirmed || !mounted) return;
      setState(() => _busy = true);
      await RetainedDownloadStore.keepFile(
        accountSlot: widget.accountSlot,
        fileId: widget.fileId,
        title: widget.title,
        isVideo: widget.isVideo,
      );
      if (mounted) {
        showToast(context, AppStringKeys.downloadsKeptOnDevice);
      }
    } catch (_) {
      // File paths and server errors can contain private information. The UI
      // needs only the actionable retry explanation, not the raw exception.
      if (mounted) showToast(context, AppStringKeys.downloadsKeepFailed);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _confirming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = AppStrings.t(AppStringKeys.downloadsKeepOnDevice);
    return AppInteractiveSurface(
      key: ValueKey('retain-download-${widget.accountSlot}-${widget.fileId}'),
      semanticLabel: label,
      enabled: !_busy && !_confirming,
      onTap: _keep,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _busy
                ? const AppActivityIndicator(size: 18)
                : AppIcon(
                    HeroAppIcons.shieldHalved,
                    size: 18,
                    color: context.colors.linkBlue,
                  ),
            if (widget.showLabel) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.linkBlue,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
