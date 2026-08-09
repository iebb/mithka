import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';

class FeedbackReportView extends StatefulWidget {
  const FeedbackReportView({super.key});

  @override
  State<FeedbackReportView> createState() => _FeedbackReportViewState();
}

class _FeedbackReportViewState extends State<FeedbackReportView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _controller.text.trim();
    if (message.isEmpty || _sending) return;
    setState(() => _sending = true);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    try {
      final id = await Sentry.captureFeedback(SentryFeedback(message: message));
      if (!mounted) return;
      if (id == const SentryId.empty()) {
        setState(() => _sending = false);
        showToast(context, AppStringKeys.feedbackReportFailed);
        return;
      }
      final shortId = id.toString().substring(0, 8);
      if (overlay != null) {
        showToastOverlay(
          overlay,
          AppStrings.t(AppStringKeys.feedbackReportSent, {'value1': shortId}),
          visibleFor: const Duration(seconds: 3),
        );
      }
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      showToast(context, AppStringKeys.feedbackReportFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final canSend = _controller.text.trim().isNotEmpty && !_sending;
    return SettingsPageScaffold(
      title: AppStringKeys.feedbackReportTitle,
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          SettingsNote(
            text: AppStrings.t(AppStringKeys.feedbackReportDescription),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsPanel(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 190),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                minLines: 7,
                maxLines: 12,
                maxLength: 4096,
                onChanged: (_) => setState(() {}),
                style: AppTextStyle.body(
                  colors.textPrimary,
                ).copyWith(height: 1.4),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  counterStyle: AppTextStyle.caption(colors.textTertiary),
                  hintText: AppStrings.t(
                    AppStringKeys.feedbackReportPlaceholder,
                  ),
                  hintStyle: AppTextStyle.body(
                    colors.textTertiary,
                  ).copyWith(height: 1.4),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canSend ? _submit : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 48,
              decoration: BoxDecoration(
                color: canSend
                    ? AppTheme.brand
                    : colors.textTertiary.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_sending)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    else
                      const AppIcon(
                        HeroAppIcons.paperPlane,
                        size: 19,
                        color: Colors.white,
                      ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      AppStrings.t(
                        _sending
                            ? AppStringKeys.feedbackReportSending
                            : AppStringKeys.feedbackReportSend,
                      ),
                      style: AppTextStyle.bodyLarge(
                        Colors.white,
                        weight: AppTextWeight.semibold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsNote(text: AppStrings.t(AppStringKeys.feedbackReportPrivacy)),
        ],
      ),
    );
  }
}
