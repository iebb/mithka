//
//  chat_message_search_bar.dart
//
//  The surfaces in-chat search draws over an open conversation: the header
//  field that replaces the chat title, the compact navigator that replaces the
//  composer on a phone, and the results list a wide chat keeps beside the
//  transcript. None of them touch TDLib — they read and drive
//  `ChatMessageSearchController`.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/ipad_window_chrome.dart';
import '../chats/search_token_views.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'chat_message_search_controller.dart';

/// The chat header while search is on: back out of search, type, and — where
/// there is room for them — step between hits without leaving the field.
class ChatSearchHeaderBar extends StatelessWidget {
  const ChatSearchHeaderBar({
    super.key,
    required this.controller,
    required this.height,
    required this.onClose,
    this.backgroundColor,
    this.showDivider = true,
    this.showSteppers = false,
  });

  final ChatMessageSearchController controller;
  final double height;
  final VoidCallback onClose;
  final Color? backgroundColor;
  final bool showDivider;

  /// Wide layouts keep the up/down controls in the header because the composer
  /// stays put; narrow ones get them in [ChatSearchNavigator] instead.
  final bool showSteppers;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const ValueKey('chatSearchHeader'),
      padding: EdgeInsets.only(
        top:
            MediaQuery.of(context).padding.top +
            iPadWindowChromeInsetOf(context),
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? c.navBar,
        border: showDivider
            ? Border(bottom: BorderSide(color: c.divider, width: 0.5))
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              child: _fieldRow(context, c),
            ),
          ),
          ChatSearchFilterStrip(controller: controller),
        ],
      ),
    );
  }

  Widget _fieldRow(BuildContext context, AppColors c) => Row(
    children: [
      AppInteractiveSurface(
        key: const ValueKey('chatSearchClose'),
        semanticLabel: AppStringKeys.navigationBack.l10n(context),
        onTap: onClose,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: AppMetric.hitTarget,
          height: AppMetric.hitTarget,
          child: Center(
            child: AppIcon(
              HeroAppIcons.chevronLeft,
              size: AppIconSize.nav,
              color: c.textPrimary,
            ),
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: _ChatSearchField(controller: controller, onClose: onClose),
      ),
      if (showSteppers) ...[
        const SizedBox(width: AppSpacing.sm),
        ChatSearchSteppers(controller: controller),
      ],
    ],
  );
}

/// A resolved `from:` token, shown so the narrowed search is visible rather
/// than implied by a shrinking result list.
class _ChatSearchSenderChip extends StatelessWidget {
  const _ChatSearchSenderChip({required this.name, required this.onRemove});

  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyle.caption(
      AppTheme.brand,
      weight: AppTextWeight.semibold,
    );
    return Container(
      key: const ValueKey('chatSearchSenderChip'),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppStringKeys.chatSearchTokenFrom.l10n(context),
            style: style.copyWith(
              color: AppTheme.brand.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 3),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
          AppInteractiveSurface(
            key: const ValueKey('chatSearchSenderChipRemove'),
            semanticLabel: AppStringKeys.desktopSearchScopeRemove.l10n(context),
            onTap: onRemove,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox.square(
              dimension: 16,
              child: Center(
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: 10,
                  color: AppTheme.brand,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Narrows a chat's search to one kind of message.
///
/// The strip stays out of the way until search is actually open, and scrolls
/// horizontally so a narrow phone never truncates the last chip.
class ChatSearchFilterStrip extends StatelessWidget {
  const ChatSearchFilterStrip({super.key, required this.controller});

  static const double height = 44;

  final ChatMessageSearchController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => SizedBox(
      key: const ValueKey('chatSearchFilterStrip'),
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xs,
        ),
        itemCount: ChatSearchFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) {
          final filter = ChatSearchFilter.values[index];
          return SettingsFilterChip(
            key: ValueKey('chatSearchFilter-${filter.name}'),
            label: filter.labelKey.l10n(context),
            selected: controller.filter == filter,
            onTap: () => controller.setFilter(filter),
          );
        },
      ),
    ),
  );
}

class _ChatSearchField extends StatelessWidget {
  const _ChatSearchField({required this.controller, required this.onClose});

  final ChatMessageSearchController controller;
  final VoidCallback onClose;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final shift =
        pressed.contains(LogicalKeyboardKey.shiftLeft) ||
        pressed.contains(LogicalKeyboardKey.shiftRight);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        // Enter walks back through time, matching the up control; shift
        // reverses it, the way a find bar behaves everywhere else.
        if (shift) {
          controller.stepNewer();
        } else {
          unawaited(controller.stepOlder());
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        onClose();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final counter = controller.hasResults
        ? AppStrings.t(AppStringKeys.chatSearchMatchCounter, {
            'value1': '${controller.matchPosition}',
            'value2': '${controller.matchCount}',
          })
        : null;
    return Container(
      height: AppMetric.searchHeight,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(
          color: controller.focusNode.hasFocus
              ? AppTheme.brand.withValues(alpha: 0.72)
              : c.divider.withValues(alpha: 0.55),
          width: controller.focusNode.hasFocus ? 1.25 : 0.5,
        ),
      ),
      child: Row(
        children: [
          AppIcon(
            HeroAppIcons.magnifyingGlass,
            size: AppMetric.searchIcon,
            color: c.textTertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          if (controller.senderName case final sender?) ...[
            _ChatSearchSenderChip(
              name: sender,
              onRemove: controller.clearSender,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Focus(
              onKeyEvent: _handleKey,
              child: TextField(
                key: const ValueKey('chatSearchField'),
                controller: controller.textController,
                focusNode: controller.focusNode,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                style: AppTextStyle.body(c.textPrimary),
                cursorColor: AppTheme.brand,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText:
                      (controller.hasSearch
                              ? AppStringKeys.chatSearchInThisChat
                              : AppStringKeys.chatSearchTokenHint)
                          .l10n(context),
                  hintStyle: AppTextStyle.body(c.textTertiary),
                ),
                onChanged: controller.updateQuery,
                onSubmitted: (_) => unawaited(controller.stepOlder()),
              ),
            ),
          ),
          if (counter != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              counter,
              key: const ValueKey('chatSearchCounter'),
              style: AppTextStyle.caption(c.textTertiary),
            ),
          ],
          if (controller.hasQuery) ...[
            const SizedBox(width: AppSpacing.xs),
            AppInteractiveSurface(
              key: const ValueKey('chatSearchClear'),
              semanticLabel: AppStringKeys.desktopSearchClear.l10n(context),
              onTap: controller.clear,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: SizedBox.square(
                dimension: 20,
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.xmark,
                    size: AppIconSize.xs,
                    color: c.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Up (older) / down (newer) hit controls, sized for both a header row and a
/// thumb-height navigator.
class ChatSearchSteppers extends StatelessWidget {
  const ChatSearchSteppers({super.key, required this.controller});

  final ChatMessageSearchController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ChatSearchStepper(
          key: const ValueKey('chatSearchStepOlder'),
          icon: HeroAppIcons.chevronUp,
          label: AppStringKeys.chatSearchOlderMatch.l10n(context),
          enabled: controller.canStepOlder,
          onTap: () => unawaited(controller.stepOlder()),
        ),
        _ChatSearchStepper(
          key: const ValueKey('chatSearchStepNewer'),
          icon: HeroAppIcons.chevronDown,
          label: AppStringKeys.chatSearchNewerMatch.l10n(context),
          enabled: controller.canStepNewer,
          onTap: controller.stepNewer,
        ),
      ],
    ),
  );
}

class _ChatSearchStepper extends StatelessWidget {
  const _ChatSearchStepper({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      semanticLabel: label,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: AppMetric.hitTarget,
        height: AppMetric.hitTarget,
        child: Center(
          child: AppIcon(
            icon,
            size: AppIconSize.lg,
            color: enabled
                ? c.textPrimary
                : c.textTertiary.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}

/// Replaces the composer while searching a narrow chat: how many hits there
/// are, a way to see them all, and the two stepper controls.
class ChatSearchNavigator extends StatelessWidget {
  const ChatSearchNavigator({
    super.key,
    required this.controller,
    required this.onShowResults,
  });

  static const double height = 48;

  final ChatMessageSearchController controller;
  final VoidCallback onShowResults;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final c = context.colors;
    final canShowResults = controller.hasResults;
    return Container(
      key: const ValueKey('chatSearchNavigator'),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: AppInteractiveSurface(
                    key: const ValueKey('chatSearchShowResults'),
                    semanticLabel: AppStringKeys.chatSearchAllResults.l10n(
                      context,
                    ),
                    enabled: canShowResults,
                    onTap: canShowResults ? onShowResults : null,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              chatSearchStatusLabel(context, controller),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.footnote(
                                canShowResults ? c.textPrimary : c.textTertiary,
                              ),
                            ),
                          ),
                          if (canShowResults) ...[
                            const SizedBox(width: AppSpacing.sm),
                            AppIcon(
                              HeroAppIcons.chevronUp,
                              size: AppIconSize.xs,
                              color: c.textTertiary,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                ChatSearchSteppers(controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One-line state for the navigator and the results header.
String chatSearchStatusLabel(
  BuildContext context,
  ChatMessageSearchController controller,
) {
  if (!controller.hasSearch) {
    return AppStringKeys.chatSearchMessagePlaceholder.l10n(context);
  }
  if (controller.hasResults) {
    return AppStrings.plural(
      AppStringKeys.chatSearchResultCount,
      controller.matchCount,
    );
  }
  return controller.isLoading
      ? AppStringKeys.chatSearchSearching.l10n(context)
      : AppStringKeys.chatSearchNoMessagesFound.l10n(context);
}

/// The hit list a wide chat keeps beside the transcript. The same list is what
/// a narrow chat shows in its results sheet.
class ChatSearchResultsPane extends StatelessWidget {
  const ChatSearchResultsPane({
    super.key,
    required this.controller,
    required this.peerTitle,
    required this.onSelect,
    this.showHeader = true,
    this.backgroundColor,
  });

  final ChatMessageSearchController controller;
  final String peerTitle;
  final ValueChanged<ChatMessage> onSelect;
  final bool showHeader;

  /// Defaults to the trailing-pane wash. A full screen passes the page
  /// background so the list does not read as a pane floating on itself.
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final c = context.colors;
    // A token being typed is a question about who, so the surface answers that
    // instead of listing hits for a half-written filter.
    final token = controller.activeToken;
    if (token != null) {
      return ColoredBox(
        color: backgroundColor ?? c.panelBackground,
        child: SearchTokenSuggestionList(
          suggestions: controller.suggestions,
          onPick: controller.applySuggestion,
          shrinkWrap: false,
        ),
      );
    }
    if (controller.showsTokenHints) {
      return ColoredBox(
        color: backgroundColor ?? c.panelBackground,
        child: SingleChildScrollView(
          child: SearchTokenHints(
            hints: const [searchTokenFromHint, searchTokenHasHint],
            onPick: controller.startToken,
          ),
        ),
      );
    }
    return ColoredBox(
      key: const ValueKey('chatSearchResultsPane'),
      color: backgroundColor ?? c.panelBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
            SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        chatSearchStatusLabel(context, controller),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.callout(
                          c.textPrimary,
                          weight: AppTextWeight.semibold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: c.divider),
          ],
          Expanded(child: _list(context)),
        ],
      ),
    );
  }

  Widget _list(BuildContext context) {
    final c = context.colors;
    if (!controller.hasResults) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Text(
            chatSearchStatusLabel(context, controller),
            textAlign: TextAlign.center,
            style: AppTextStyle.footnote(c.textTertiary),
          ),
        ),
      );
    }
    final results = controller.results;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.axis == Axis.vertical &&
            metrics.extentAfter < 320 &&
            controller.hasMore) {
          controller.loadMore();
        }
        return false;
      },
      child: ListView.builder(
        key: const ValueKey('chatSearchResultsList'),
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        itemCount: results.length,
        itemBuilder: (context, index) {
          final message = results[index];
          return ChatSearchResultRow(
            message: message,
            query: controller.query,
            peerTitle: peerTitle,
            selected: index == controller.activeIndex,
            onTap: () => onSelect(message),
          );
        },
      ),
    );
  }
}

/// One hit: who said it, when, and the matched run inside the message.
class ChatSearchResultRow extends StatelessWidget {
  const ChatSearchResultRow({
    super.key,
    required this.message,
    required this.query,
    required this.peerTitle,
    required this.selected,
    required this.onTap,
  });

  final ChatMessage message;
  final String query;
  final String peerTitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = message.senderName ?? message.senderTitle ?? peerTitle;
    final snippet = message.text.trim().isEmpty
        ? AppStringKeys.chatSearchMessageResultLabel.l10n(context)
        : message.text.replaceAll('\n', ' ');
    return AppInteractiveSurface(
      key: ValueKey('chatSearchResult-${message.id}'),
      onTap: onTap,
      selected: selected,
      child: AnimatedContainer(
        duration: AppMotion.duration(context, AppMotion.quick),
        curve: AppMotion.standard,
        color: selected
            ? AppTheme.brand.withValues(alpha: 0.12)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PhotoAvatar(
              title: name,
              photo: message.senderPhoto,
              size: 32,
              allowAnimation: false,
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.footnote(
                            c.textPrimary,
                            weight: AppTextWeight.medium,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        DateText.listLabel(message.date),
                        style: AppTextStyle.tiny(c.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text.rich(
                    TextSpan(
                      children: chatSearchHighlightSpans(
                        text: snippet,
                        query: query,
                        matchStyle: TextStyle(
                          color: AppTheme.brand,
                          fontWeight: AppTextWeight.semibold,
                        ),
                      ),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption(
                      c.textSecondary,
                    ).copyWith(height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The narrow-layout equivalent of the results pane, presented as a sheet so
/// the transcript stays behind it.
Future<void> showChatSearchResultsSheet({
  required BuildContext context,
  required ChatMessageSearchController controller,
  required String peerTitle,
  required ValueChanged<ChatMessage> onSelect,
}) {
  final c = context.colors;
  return showAppModalSheet<void>(
    context: context,
    backgroundColor: c.panelBackground,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.62,
    ),
    builder: (sheetContext) => AnimatedBuilder(
      animation: controller,
      builder: (_, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    chatSearchStatusLabel(sheetContext, controller),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.callout(
                      sheetContext.colors.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ChatSearchResultsPane(
              controller: controller,
              peerTitle: peerTitle,
              showHeader: false,
              onSelect: (message) {
                Navigator.of(sheetContext).pop();
                onSelect(message);
              },
            ),
          ),
        ],
      ),
    ),
  );
}
