import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../settings/ai_settings_view.dart';
import '../theme/app_theme.dart';
import 'unread_chat_summary_models.dart';

typedef UnreadChatSummaryOperation = Future<UnreadChatSummary> Function();

class UnreadChatSummaryView extends StatefulWidget {
  const UnreadChatSummaryView({
    super.key,
    required this.snapshot,
    required this.summarize,
  });

  final UnreadChatRangeSnapshot snapshot;
  final UnreadChatSummaryOperation summarize;

  @override
  State<UnreadChatSummaryView> createState() => _UnreadChatSummaryViewState();
}

class _UnreadChatSummaryViewState extends State<UnreadChatSummaryView> {
  UnreadChatSummary? _summary;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    if (!_loading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final summary = await widget.summarize();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.aiSummaryTitle.l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 36),
              children: [
                Text(
                  AppStrings.t(AppStringKeys.aiSummaryRunningCount, {
                    'value1': widget.snapshot.unreadCount,
                  }),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 30,
                    height: 1.18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _privateTimestamp(context),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 15,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 42),
                if (_loading) _loadingContent(context),
                if (!_loading && _error != null) _errorContent(context),
                if (!_loading && _error == null && _summary != null)
                  _summaryContent(context, _summary!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingContent(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppStringKeys.aiSummaryThinking.l10n(context),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 10),
            AppActivityIndicator(size: 18, color: c.textSecondary),
          ],
        ),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: AppTheme.brand, width: 3)),
          ),
          child: Text(
            AppStrings.t(AppStringKeys.aiSummaryFoundCount, {
              'value1': widget.snapshot.unreadCount,
            }),
            style: TextStyle(color: c.textSecondary, fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _errorContent(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppIcon(
            HeroAppIcons.triangleExclamation,
            size: 25,
            color: Color(0xFFE39A20),
          ),
          const SizedBox(height: 12),
          Text(
            AppStringKeys.aiSummaryFailed.l10n(context),
            style: AppTextStyle.bodyLarge(
              c.textPrimary,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppStringKeys.aiSummaryUnavailable.l10n(context),
            style: AppTextStyle.footnote(c.textSecondary),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _action(
                  context,
                  label: AppStringKeys.aiSummaryRetry.l10n(context),
                  filled: true,
                  onTap: _run,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _action(
                  context,
                  label: AppStringKeys.aiSummaryOpenSettings.l10n(context),
                  filled: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AiSettingsView(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryContent(BuildContext context, UnreadChatSummary summary) {
    final hasContent =
        summary.overview.trim().isNotEmpty ||
        summary.highlights.isNotEmpty ||
        summary.needsReply.isNotEmpty ||
        summary.decisions.isNotEmpty ||
        summary.actions.isNotEmpty ||
        summary.questions.isNotEmpty ||
        summary.uncertainties.isNotEmpty;
    if (!hasContent) {
      return Text(
        summary.coverage.fetchedMessageCount == 0
            ? AppStringKeys.aiSummaryNoUnread.l10n(context)
            : AppStringKeys.aiSummaryNoContent.l10n(context),
        style: AppTextStyle.body(context.colors.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!summary.coverage.complete) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE39A20).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              AppStrings.t(AppStringKeys.aiSummaryIncomplete, {
                'value1': summary.coverage.summarizedUnreadMessageCount,
              }),
              style: AppTextStyle.footnote(const Color(0xFFD58700)),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (summary.overview.trim().isNotEmpty)
          _overviewSection(context, summary),
        _itemSection(
          context,
          title: AppStringKeys.aiSummaryHighlights.l10n(context),
          items: summary.highlights,
        ),
        _itemSection(
          context,
          title: AppStringKeys.aiSummaryNeedsReply.l10n(context),
          items: summary.needsReply,
        ),
        _itemSection(
          context,
          title: AppStringKeys.aiSummaryDecisions.l10n(context),
          items: summary.decisions,
        ),
        _itemSection(
          context,
          title: AppStringKeys.aiSummaryActions.l10n(context),
          items: summary.actions,
        ),
        _itemSection(
          context,
          title: AppStringKeys.aiSummaryQuestions.l10n(context),
          items: summary.questions,
        ),
        _itemSection(
          context,
          title: AppStringKeys.aiSummaryUncertainties.l10n(context),
          items: summary.uncertainties,
        ),
      ],
    );
  }

  Widget _overviewSection(BuildContext context, UnreadChatSummary summary) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: summary.overviewEvidenceIds.isEmpty
            ? null
            : () => _openEvidence(summary.overviewEvidenceIds.first),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.divider, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeading(
                context,
                AppStringKeys.aiSummaryOverview.l10n(context),
              ),
              const SizedBox(height: 9),
              Text(
                summary.overview,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 16,
                  height: 1.48,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemSection(
    BuildContext context, {
    required String title,
    required List<UnreadChatSummaryItem> items,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(context, title),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.divider, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  if (index > 0) const InsetDivider(leadingInset: 34),
                  _summaryItem(context, items[index]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(BuildContext context, UnreadChatSummaryItem item) {
    final c = context.colors;
    final canOpen = item.evidenceIds.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canOpen ? () => _openEvidence(item.evidenceIds.first) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.text,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  height: 1.43,
                ),
              ),
            ),
            if (canOpen) ...[
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 14,
                  color: c.textTertiary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(BuildContext context, String title) => Text(
    title,
    style: TextStyle(
      color: context.colors.textPrimary,
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _action(
    BuildContext context, {
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    final color = filled ? const Color(0xFFFFFFFF) : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? AppTheme.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: filled ? null : Border.all(color: AppTheme.brand),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _openEvidence(String evidenceId) {
    final messageId = int.tryParse(
      evidenceId.startsWith('m') ? evidenceId.substring(1) : evidenceId,
    );
    if (messageId != null && messageId > 0) {
      Navigator.of(context).pop(messageId);
    }
  }

  String _privateTimestamp(BuildContext context) {
    final local = widget.snapshot.capturedAt.toLocal();
    final material = MaterialLocalizations.of(context);
    final date = material.formatMediumDate(local);
    final time = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$date  $time  ${AppStringKeys.aiSummaryPrivate.l10n(context)}';
  }
}
