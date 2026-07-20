import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../settings/ai_settings_view.dart';
import '../theme/app_theme.dart';
import 'unread_chat_summary_models.dart';
import 'unread_chat_summary_service.dart';

typedef UnreadChatSummaryOperation =
    Future<UnreadChatSummary> Function(
      UnreadChatSummaryProgressCallback onProgress,
    );

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
  bool _showTechnicalDetails = false;
  UnreadChatSummaryProgress _progress = const UnreadChatSummaryProgress(
    stage: UnreadChatSummaryProgressStage.loadingMessages,
  );

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
        _showTechnicalDetails = false;
        _progress = const UnreadChatSummaryProgress(
          stage: UnreadChatSummaryProgressStage.loadingMessages,
        );
      });
    }
    try {
      final summary = await widget.summarize(_reportProgress);
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

  void _reportProgress(UnreadChatSummaryProgress progress) {
    if (!mounted || !_loading) return;
    setState(() => _progress = progress);
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
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 36),
              children: [
                Text(
                  _pageHeading(context),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 25,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
                const SizedBox(height: 28),
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

  String _pageHeading(BuildContext context) {
    final summary = _summary;
    if (!_loading && summary != null && summary.title.trim().isNotEmpty) {
      return summary.title.trim();
    }
    return AppStringKeys.aiSummaryTitle.l10n(context);
  }

  Widget _loadingContent(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        AppActivityIndicator(size: 18, color: AppTheme.brand),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _progressLabel(context),
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _progressLabel(BuildContext context) {
    switch (_progress.stage) {
      case UnreadChatSummaryProgressStage.loadingMessages:
        if (_progress.messageCount <= 0) {
          return AppStringKeys.aiSummaryReading.l10n(context);
        }
        return AppStrings.t(AppStringKeys.aiSummaryReadingCount, {
          'value1': _progress.messageCount,
        });
      case UnreadChatSummaryProgressStage.summarizingChunks:
        return AppStrings.t(AppStringKeys.aiSummaryChunkProgress, {
          'value1': _progress.completed,
          'value2': _progress.total,
        });
      case UnreadChatSummaryProgressStage.assemblingSummary:
        return AppStringKeys.aiSummaryAssembling.l10n(context);
    }
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppIcon(
                HeroAppIcons.triangleExclamation,
                size: 22,
                color: Color(0xFFE39A20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppStringKeys.aiSummaryFailed.l10n(context),
                  style: AppTextStyle.bodyLarge(
                    c.textPrimary,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppStringKeys.aiSummaryUnavailable.l10n(context),
            style: AppTextStyle.footnote(c.textSecondary),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                setState(() => _showTechnicalDetails = !_showTechnicalDetails),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      AppStringKeys.aiSummaryTechnicalDetails.l10n(context),
                      style: AppTextStyle.caption(c.textSecondary),
                    ),
                  ),
                  AppIcon(
                    _showTechnicalDetails
                        ? HeroAppIcons.chevronUp
                        : HeroAppIcons.chevronDown,
                    size: 16,
                    color: c.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_showTechnicalDetails) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.groupedBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.divider, width: 0.5),
              ),
              child: SelectableText(
                _technicalErrorDetails(),
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 12,
                  height: 1.45,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
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

  String _technicalErrorDetails() {
    final error = _error;
    if (error is UnreadChatSummaryFailure) return error.technicalDetails;
    final value = error?.toString().trim() ?? 'unknown_error';
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length <= 1000
        ? normalized
        : '${normalized.substring(0, 997)}...';
  }

  Widget _summaryContent(BuildContext context, UnreadChatSummary summary) {
    final hasContent =
        summary.title.trim().isNotEmpty ||
        summary.overview.trim().isNotEmpty ||
        summary.topics.isNotEmpty ||
        summary.rant != null ||
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
        Text(
          AppStrings.t(AppStringKeys.aiSummaryProcessedCount, {
            'value1': summary.coverage.summarizedMessageCount,
          }),
          style: AppTextStyle.body(context.colors.textSecondary),
        ),
        const SizedBox(height: 22),
        if (!summary.coverage.complete) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE39A20).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.t(AppStringKeys.aiSummaryIncomplete, {
                    'value1': summary.coverage.summarizedUnreadMessageCount,
                    'value2': summary.coverage.expectedUnreadCount,
                  }),
                  style: AppTextStyle.footnote(const Color(0xFFD58700)),
                ),
                const SizedBox(height: 4),
                Text(
                  _coverageReason(context, summary.coverage),
                  style: AppTextStyle.footnote(const Color(0xFFD58700)),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _run,
                  child: Text(
                    AppStringKeys.aiSummaryRetry.l10n(context),
                    style: AppTextStyle.footnote(
                      AppTheme.brand,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (summary.overview.trim().isNotEmpty)
          _overviewSection(context, summary),
        if (summary.topics.isNotEmpty) _topicSection(context, summary.topics),
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
        if (summary.rant case final rant?) _rantSection(context, rant),
        const SizedBox(height: 24),
        Text(
          AppStringKeys.aiSummaryDisclaimer.l10n(context),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.colors.textTertiary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _overviewSection(BuildContext context, UnreadChatSummary summary) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: _textWithEvidenceBadges(
        context,
        text: summary.overview,
        evidenceIds: summary.overviewEvidenceIds,
        style: TextStyle(color: c.textSecondary, fontSize: 17, height: 1.58),
      ),
    );
  }

  Widget _topicSection(
    BuildContext context,
    List<UnreadChatSummaryTopic> topics,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeading(context, AppStringKeys.aiSummaryTopics.l10n(context)),
        const SizedBox(height: 12),
        for (var index = 0; index < topics.length; index++) ...[
          _topic(context, index + 1, topics[index]),
          if (index + 1 < topics.length) const SizedBox(height: 24),
        ],
      ],
    ),
  );

  Widget _topic(BuildContext context, int index, UnreadChatSummaryTopic topic) {
    final c = context.colors;
    final timeRange = _topicTimeRange(context, topic);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$index. ${topic.title}',
          style: TextStyle(
            color: c.textPrimary,
            fontSize: 18,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (timeRange != null) ...[
          const SizedBox(height: 10),
          Text(
            '• ${AppStringKeys.aiSummaryTopicTime.l10n(context)} · $timeRange',
            style: TextStyle(color: c.textSecondary, fontSize: 14, height: 1.4),
          ),
        ],
        const SizedBox(height: 10),
        _textWithEvidenceBadges(
          context,
          text: topic.summary,
          evidenceIds: topic.evidenceIds,
          style: TextStyle(color: c.textSecondary, fontSize: 16, height: 1.55),
        ),
      ],
    );
  }

  Widget _rantSection(BuildContext context, UnreadChatSummaryItem rant) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(top: 22),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: _textWithEvidenceBadges(
        context,
        text: rant.text,
        evidenceIds: rant.evidenceIds,
        prefix: [
          TextSpan(
            text: '${AppStringKeys.aiSummaryRant.l10n(context)}：',
            style: const TextStyle(
              color: Color(0xFF2EBF75),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        style: TextStyle(color: c.textSecondary, fontSize: 16, height: 1.58),
      ),
    );
  }

  String? _topicTimeRange(BuildContext context, UnreadChatSummaryTopic topic) {
    final first = topic.firstDate;
    final last = topic.lastDate;
    if (first == null || last == null || first <= 0 || last <= 0) return null;
    final start = DateTime.fromMillisecondsSinceEpoch(first * 1000).toLocal();
    final end = DateTime.fromMillisecondsSinceEpoch(last * 1000).toLocal();
    final material = MaterialLocalizations.of(context);
    final startDate = material.formatMediumDate(start);
    final startTime = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(start),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final endTime = material.formatTimeOfDay(
      TimeOfDay.fromDateTime(end),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final sameDay =
        start.year == end.year &&
        start.month == end.month &&
        start.day == end.day;
    if (sameDay) return '$startDate  $startTime–$endTime';
    return '$startDate  $startTime – ${material.formatMediumDate(end)}  $endTime';
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
              child: _textWithEvidenceBadges(
                context,
                text: item.text,
                evidenceIds: item.evidenceIds,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  height: 1.43,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textWithEvidenceBadges(
    BuildContext context, {
    required String text,
    required List<String> evidenceIds,
    required TextStyle style,
    List<InlineSpan> prefix = const [],
  }) => Text.rich(
    TextSpan(
      children: [
        ...prefix,
        TextSpan(text: text),
        for (
          var evidenceIndex = 0;
          evidenceIndex < evidenceIds.length && evidenceIndex < 5;
          evidenceIndex++
        )
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 1),
              child: Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openEvidence(evidenceIds[evidenceIndex]),
                  child: Container(
                    key: ValueKey(
                      'ai-summary-evidence-badge-${evidenceIds[evidenceIndex]}',
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: context.colors.searchFill,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      '${evidenceIndex + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colors.textSecondary,
                        fontSize: 10,
                        height: 1.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
    style: style,
  );

  String _coverageReason(
    BuildContext context,
    UnreadChatSummaryCoverage coverage,
  ) {
    if (coverage.usedLocalFallback) {
      return AppStringKeys.aiSummaryLocalFallback.l10n(context);
    }
    final reasons = <String>[];
    if (coverage.failedRequestCount > 0) {
      reasons.add(AppStringKeys.aiSummaryPartialFailure.l10n(context));
    }
    if (coverage.processingCapped) {
      reasons.add(AppStringKeys.aiSummarySampled.l10n(context));
    }
    if (!coverage.reachedReadBoundary ||
        coverage.historyCapped ||
        coverage.historyStalled ||
        coverage.countMismatch) {
      reasons.add(AppStringKeys.aiSummaryHistoryIncomplete.l10n(context));
    }
    return reasons.join(' ');
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
