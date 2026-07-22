import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';

class MessageContactCardContent extends StatelessWidget {
  const MessageContactCardContent({
    super.key,
    required this.contact,
    required this.background,
    required this.foreground,
    required this.secondary,
    this.borderRadius,
    this.onOpen,
  });

  final MessageContactCard contact;
  final Color background;
  final Color foreground;
  final Color secondary;
  final BorderRadius? borderRadius;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final nameCharacters = contact.displayName.trim().characters;
    final initials = nameCharacters.isEmpty ? '' : nameCharacters.first;
    return GestureDetector(
      key: const ValueKey('messageContactCard'),
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Container(
        constraints: const BoxConstraints(minWidth: 230, maxWidth: 290),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: borderRadius ?? BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: initials.isEmpty
                  ? AppIcon(
                      HeroAppIcons.idBadge,
                      size: 22,
                      color: AppTheme.brand,
                    )
                  : Text(
                      initials.toUpperCase(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.brand,
                      ),
                    ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: foreground,
                    ),
                  ),
                  if (contact.phoneNumber.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      contact.phoneNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ],
                ],
              ),
            ),
            if (contact.userId > 0)
              AppIcon(HeroAppIcons.chevronRight, size: 17, color: secondary),
          ],
        ),
      ),
    );
  }
}

class MessagePollContent extends StatelessWidget {
  const MessagePollContent({
    super.key,
    required this.poll,
    required this.background,
    required this.foreground,
    required this.secondary,
    this.borderRadius,
    required this.onVote,
    this.onStop,
    this.onAddOption,
    this.onShowResults,
  });

  final MessagePoll poll;
  final Color background;
  final Color foreground;
  final Color secondary;
  final BorderRadius? borderRadius;
  final ValueChanged<int>? onVote;
  final VoidCallback? onStop;
  final VoidCallback? onAddOption;
  final VoidCallback? onShowResults;

  @override
  Widget build(BuildContext context) {
    final showResults =
        poll.canSeeResults ||
        poll.isClosed ||
        poll.chosenOptionIndexes.isNotEmpty;
    return Container(
      key: const ValueKey('messagePollCard'),
      constraints: const BoxConstraints(minWidth: 250, maxWidth: 310),
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius ?? BorderRadius.circular(9),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (poll.media != null)
            SizedBox(
              height: 132,
              width: double.infinity,
              child: TDImage(photo: poll.media, cornerRadius: 0),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  poll.question.isEmpty
                      ? AppStringKeys.tdMessagePoll.l10n(context)
                      : poll.question,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
                if (poll.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    poll.description,
                    style: TextStyle(fontSize: 13, color: secondary),
                  ),
                ],
                const SizedBox(height: 10),
                for (final option in poll.options) ...[
                  _PollOptionRow(
                    option: option,
                    multiple: poll.allowsMultipleAnswers,
                    showResults: showResults,
                    enabled: !poll.isClosed && onVote != null,
                    foreground: foreground,
                    secondary: secondary,
                    onTap: () => onVote?.call(option.index),
                  ),
                  if (option != poll.options.last) const SizedBox(height: 7),
                ],
                if (poll.explanation.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Text(
                    poll.explanation,
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.t(AppStringKeys.messagePollVotes, {
                          'value1': poll.totalVoterCount,
                        }),
                        style: TextStyle(fontSize: 12, color: secondary),
                      ),
                    ),
                    if (poll.isClosed)
                      Text(
                        AppStringKeys.messagePollClosed.l10n(context),
                        style: TextStyle(fontSize: 12, color: secondary),
                      )
                    else if (onStop != null)
                      GestureDetector(
                        key: const ValueKey('messagePollStop'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onStop,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 3,
                          ),
                          child: Text(
                            AppStringKeys.messagePollStop.l10n(context),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.brand,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (poll.canAddOption || poll.canGetVoters) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      if (poll.canAddOption)
                        _PollTextAction(
                          key: const ValueKey('messagePollAddOption'),
                          label: AppStrings.t(
                            AppStringKeys.pollComposerAddOption,
                          ),
                          onTap: onAddOption,
                        ),
                      if (poll.canAddOption && poll.canGetVoters)
                        const Spacer(),
                      if (poll.canGetVoters)
                        _PollTextAction(
                          key: const ValueKey('messagePollViewResults'),
                          label: AppStrings.t(
                            AppStringKeys.messageSpecialContentViewResults,
                          ),
                          onTap: onShowResults,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PollTextAction extends StatelessWidget {
  const _PollTextAction({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.brand,
        ),
      ),
    ),
  );
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.option,
    required this.multiple,
    required this.showResults,
    required this.enabled,
    required this.foreground,
    required this.secondary,
    required this.onTap,
  });

  final MessagePollOption option;
  final bool multiple;
  final bool showResults;
  final bool enabled;
  final Color foreground;
  final Color secondary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final percentage = showResults ? option.votePercentage.clamp(0, 100) : 0;
    return GestureDetector(
      key: ValueKey('messagePollOption-${option.index}'),
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: percentage / 100,
                child: Container(color: AppTheme.brand.withValues(alpha: 0.13)),
              ),
            ),
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: option.isChosen
                    ? AppTheme.brand
                    : secondary.withValues(alpha: 0.3),
                width: option.isChosen ? 1.2 : 0.7,
              ),
            ),
            child: Row(
              children: [
                if (option.isBeingChosen)
                  const AppActivityIndicator(size: 17)
                else
                  AppIcon(
                    option.isChosen
                        ? HeroAppIcons.circleCheck
                        : (multiple
                              ? HeroAppIcons.square
                              : HeroAppIcons.circle),
                    size: 18,
                    color: option.isChosen ? AppTheme.brand : secondary,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    option.text,
                    style: TextStyle(fontSize: 14, color: foreground),
                  ),
                ),
                if (showResults) ...[
                  const SizedBox(width: 7),
                  Text(
                    '$percentage%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: option.isChosen ? AppTheme.brand : secondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MessageChecklistContent extends StatelessWidget {
  const MessageChecklistContent({
    super.key,
    required this.checklist,
    required this.background,
    required this.foreground,
    required this.secondary,
    this.borderRadius,
    required this.onToggleTask,
    this.onAddTask,
  });

  final MessageChecklist checklist;
  final Color background;
  final Color foreground;
  final Color secondary;
  final BorderRadius? borderRadius;
  final ValueChanged<MessageChecklistTask>? onToggleTask;
  final VoidCallback? onAddTask;

  @override
  Widget build(BuildContext context) {
    final complete = checklist.tasks.where((task) => task.isCompleted).length;
    return Container(
      key: const ValueKey('messageChecklistCard'),
      constraints: const BoxConstraints(minWidth: 245, maxWidth: 310),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius ?? BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            checklist.title.isEmpty
                ? AppStringKeys.tdMessageChecklist.l10n(context)
                : checklist.title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
          const SizedBox(height: 9),
          for (final task in checklist.tasks) ...[
            GestureDetector(
              key: ValueKey('messageChecklistTask-${task.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: checklist.canMarkTasksAsDone && onToggleTask != null
                  ? () => onToggleTask?.call(task)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(
                      task.isCompleted
                          ? HeroAppIcons.circleCheck
                          : HeroAppIcons.circle,
                      size: 19,
                      color: task.isCompleted ? AppTheme.brand : secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.text,
                        style: TextStyle(
                          fontSize: 14,
                          color: task.isCompleted ? secondary : foreground,
                          decoration: task.isCompleted
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.t(AppStringKeys.messageChecklistProgress, {
                    'value1': complete,
                    'value2': checklist.tasks.length,
                  }),
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ),
              if (checklist.canAddTasks && onAddTask != null)
                GestureDetector(
                  key: const ValueKey('messageChecklistAddTask'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onAddTask,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIcon(
                        HeroAppIcons.plus,
                        size: 15,
                        color: AppTheme.brand,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        AppStringKeys.messageChecklistAdd.l10n(context),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.brand,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class MessageStoryContent extends StatelessWidget {
  const MessageStoryContent({
    super.key,
    required this.story,
    required this.background,
    required this.foreground,
    required this.secondary,
    this.borderRadius,
    this.onOpen,
  });

  final MessageStoryReference story;
  final Color background;
  final Color foreground;
  final Color secondary;
  final BorderRadius? borderRadius;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => GestureDetector(
    key: const ValueKey('messageStoryCard'),
    behavior: HitTestBehavior.opaque,
    onTap: onOpen,
    child: Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius ?? BorderRadius.circular(9),
        border: Border.all(
          color: AppTheme.brand.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const AppIcon(
              HeroAppIcons.circleNotch,
              size: 23,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStringKeys.messageStoryShared.l10n(context),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  story.viaMention
                      ? AppStringKeys.messageStoryMention.l10n(context)
                      : AppStringKeys.messageStoryOpen.l10n(context),
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
              ],
            ),
          ),
          AppIcon(HeroAppIcons.chevronRight, size: 17, color: secondary),
        ],
      ),
    ),
  );
}

class MessageSummaryCardContent extends StatelessWidget {
  const MessageSummaryCardContent({
    super.key,
    required this.card,
    required this.background,
    required this.foreground,
    required this.secondary,
    this.borderRadius,
  });

  final MessageSummaryCard card;
  final Color background;
  final Color foreground;
  final Color secondary;
  final BorderRadius? borderRadius;

  AppIconData get _icon => switch (card.kind) {
    MessageSummaryKind.game => HeroAppIcons.grip,
    MessageSummaryKind.invoice => HeroAppIcons.file,
    MessageSummaryKind.giveaway => HeroAppIcons.star,
    MessageSummaryKind.paidMedia => HeroAppIcons.lock,
    MessageSummaryKind.gift => HeroAppIcons.solidStar,
    MessageSummaryKind.suggestedPost => HeroAppIcons.penToSquare,
  };

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey('messageSummaryCard-${card.kind.name}'),
    constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
    decoration: BoxDecoration(
      color: background,
      borderRadius: borderRadius ?? BorderRadius.circular(9),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (card.image != null)
          SizedBox(
            width: double.infinity,
            height: 132,
            child: Stack(
              fit: StackFit.expand,
              children: [
                TDImage(photo: card.image, cornerRadius: 0),
                if (card.video != null)
                  const Center(
                    child: AppIcon(
                      HeroAppIcons.play,
                      size: 28,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AppIcon(_icon, size: 20, color: AppTheme.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    if (card.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        card.subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: secondary),
                      ),
                    ],
                    if (card.detail.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        card.detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.brand,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class MessageSuggestedPostStatusContent extends StatelessWidget {
  const MessageSuggestedPostStatusContent({
    super.key,
    required this.info,
    required this.background,
    required this.foreground,
    required this.secondary,
    this.borderRadius,
  });

  final MessageSuggestedPostInfo info;
  final Color background;
  final Color foreground;
  final Color secondary;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final label = switch (info.state) {
      SuggestedPostState.pending => AppStringKeys.suggestedPostPending,
      SuggestedPostState.approved => AppStringKeys.suggestedPostApproved,
      SuggestedPostState.declined => AppStringKeys.suggestedPostDeclined,
      SuggestedPostState.unknown => AppStringKeys.suggestedPostOffer,
    };
    final detail = <String>[
      if (info.price != null) TDParse.suggestedPostPriceLabel(info.price!),
      if (info.sendDate > 0) DateText.messageDetailLabel(info.sendDate),
    ];
    return Container(
      key: const ValueKey('messageSuggestedPostStatus'),
      constraints: const BoxConstraints(minWidth: 210, maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: borderRadius ?? BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          AppIcon(HeroAppIcons.penToSquare, size: 16, color: AppTheme.brand),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.t(label),
                  style: TextStyle(
                    color: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    detail.join(' · '),
                    style: TextStyle(color: secondary, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
