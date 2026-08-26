//
//  update_progress_dialog.dart
//
//  The modal that runs a desktop one-click update: it drives
//  DesktopUpdater.prepare, reports each stage with a determinate bar while the
//  package downloads, and stays cancellable until the moment the swap is
//  handed off. Nothing on disk has changed when it is dismissed.
//

import 'package:flutter/material.dart';

import '../components/app_dialog.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'desktop_updater.dart';
import 'release_feed.dart';

enum DesktopUpdateResultKind { ready, cancelled, failed }

class DesktopUpdateResult {
  const DesktopUpdateResult(this.kind, [this.update]);

  final DesktopUpdateResultKind kind;

  /// The staged build, present only when [kind] is
  /// [DesktopUpdateResultKind.ready].
  final PreparedDesktopUpdate? update;
}

/// Downloads and unpacks [asset] behind a modal sheet.
///
/// The dialog cannot be dismissed by tapping outside, because backing out has
/// to run the cancellation that closes the socket and clears the staging
/// directory.
Future<DesktopUpdateResult> runDesktopUpdate(
  BuildContext context, {
  required ReleaseAsset asset,
  required String version,
}) async {
  final result = await showGeneralDialog<DesktopUpdateResult>(
    context: context,
    barrierLabel: AppStrings.t(AppStringKeys.updateDownloadingTitle),
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: AppMotion.duration(context, AppMotion.responsive),
    transitionBuilder: AppMotion.dialogTransition,
    pageBuilder: (_, _, _) =>
        _DesktopUpdateSheet(asset: asset, version: version),
  );
  return result ?? const DesktopUpdateResult(DesktopUpdateResultKind.cancelled);
}

class _DesktopUpdateSheet extends StatefulWidget {
  const _DesktopUpdateSheet({required this.asset, required this.version});

  final ReleaseAsset asset;
  final String version;

  @override
  State<_DesktopUpdateSheet> createState() => _DesktopUpdateSheetState();
}

class _DesktopUpdateSheetState extends State<_DesktopUpdateSheet> {
  final _cancellation = DesktopUpdateCancellation();
  DesktopUpdateProgress _progress = const DesktopUpdateProgress(
    DesktopUpdateStage.downloading,
  );

  /// Whether this sheet has already popped. The widget stays mounted for the
  /// length of the dismiss transition, so a cancelled run that reports back
  /// during it would otherwise pop the route underneath.
  bool _settled = false;

  void _settle(DesktopUpdateResult result) {
    if (_settled || !mounted) return;
    _settled = true;
    Navigator.of(context).pop(result);
  }

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final prepared = await DesktopUpdater.prepare(
        widget.asset,
        version: widget.version,
        cancellation: _cancellation,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (_settled || !mounted) {
        // The sheet is already gone; leave nothing staged behind.
        await prepared.discard();
        return;
      }
      _settle(DesktopUpdateResult(DesktopUpdateResultKind.ready, prepared));
    } catch (_) {
      _settle(
        DesktopUpdateResult(
          _cancellation.isCancelled
              ? DesktopUpdateResultKind.cancelled
              : DesktopUpdateResultKind.failed,
        ),
      );
    }
  }

  void _cancel() {
    // Closing right away makes the click feel answered; prepare() then unwinds
    // on its own and finds the sheet already settled.
    _cancellation.cancel();
    _settle(const DesktopUpdateResult(DesktopUpdateResultKind.cancelled));
  }

  String get _stageLabel => AppStrings.t(switch (_progress.stage) {
    DesktopUpdateStage.downloading => AppStringKeys.updateStageDownloading,
    DesktopUpdateStage.verifying => AppStringKeys.updateStageVerifying,
    DesktopUpdateStage.extracting => AppStringKeys.updateStageExtracting,
    DesktopUpdateStage.staging => AppStringKeys.updateStageStaging,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fraction = _progress.fraction;
    return AppDialogSurface(
      title: AppStrings.t(AppStringKeys.updateDownloadingTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _stageLabel,
            textAlign: TextAlign.center,
            style: AppTextStyle.body(c.dialogText),
          ),
          const SizedBox(height: 16),
          // An unknown total still advances the bar's stage rather than sitting
          // at zero, so the sheet never looks stalled.
          AppProgressBar(value: fraction ?? _stageFallbackFraction, height: 4),
          const SizedBox(height: 10),
          Text(
            _progress.totalBytes > 0
                ? AppStrings.t(AppStringKeys.updateProgressOfTotal, {
                    'value1': _formatBytes(_progress.receivedBytes),
                    'value2': _formatBytes(_progress.totalBytes),
                  })
                : widget.version,
            textAlign: TextAlign.center,
            style: AppTextStyle.footnote(c.textSecondary),
          ),
        ],
      ),
      actions: [
        AppDialogAction(
          label: AppStrings.t(AppStringKeys.confirmCancel),
          onTap: _cancel,
        ),
      ],
    );
  }

  /// Progress for the post-download stages, which have no byte count of their
  /// own but all follow a completed download.
  double get _stageFallbackFraction => switch (_progress.stage) {
    DesktopUpdateStage.downloading => 0,
    DesktopUpdateStage.verifying => 0.9,
    DesktopUpdateStage.extracting => 0.95,
    DesktopUpdateStage.staging => 1,
  };
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
}
