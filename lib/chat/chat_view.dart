//
//  chat_view.dart
//
//  The conversation screen. A gray canvas hosting a scrolling transcript of
//  bubbles, time separators and system banners, with a flat header and a pinned
//  input bar. Backed by ChatViewModel. Port of the Swift `ChatView`.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/active_conversation.dart';
import '../app/adaptive_split_layout.dart';
import '../app/desktop_video_window.dart';
import '../app/primary_chat_launcher.dart';
import '../app/video_split_controller.dart';
import '../auth/telegram_country_names.dart';
import '../call/call_manager.dart';
import '../channels/topic_chat_view.dart';
import '../chats/search_token_views.dart';
import '../communities/community_models.dart';
import '../communities/community_view.dart';
import '../components/app_dialog.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/confirm_dialog.dart';
import '../components/full_page_back_swipe.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../media/app_asset_picker.dart';
import '../moments/story_viewer_view.dart';
import '../notifications/notification_controller.dart';
import '../profile/profile_detail_view.dart';
import '../settings/ai_endpoint_style.dart';
import '../settings/ai_settings_controller.dart';
import '../settings/apple_pcc_api.dart';
import '../settings/blocked_user_service.dart';
import '../settings/business_tools_views.dart';
import '../settings/quick_reaction_settings_view.dart';
import '../settings/sensitive_content_controller.dart';
import '../settings/topic_group_display_mode.dart';
import '../settings/translation_api.dart';
import '../settings/translation_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/telegram_cloud_theme.dart';
import '../theme/theme_controller.dart';
import 'ai_chat_translation_service.dart';
import 'apple_pcc_unread_summary_provider.dart';
import 'auto_translate_policy.dart';
import 'blocked_message_runs.dart';
import 'bot_api_access_warning.dart';
import 'channel_direct_messages_service.dart';
import 'channel_direct_messages_view.dart';
import 'chat_appearance_message_preview.dart';
import 'chat_auto_scroll_policy.dart';
import 'chat_community_service_card.dart';
import 'chat_first_contact_card.dart';
import 'chat_first_contact_info.dart';
import 'chat_frame_scheduler.dart';
import 'chat_info_view.dart';
import 'chat_input_bar.dart';
import 'chat_media_drop_region.dart';
import 'chat_message_merge.dart';
import 'chat_message_search_bar.dart';
import 'chat_message_search_controller.dart';
import 'chat_open_performance.dart';
import 'chat_picker_view.dart';
import 'chat_return_to_latest_coordinator.dart';
import 'chat_scroll_metrics.dart';
import 'chat_send_failure.dart';
import 'chat_session_cache.dart';
import 'chat_translation_panel.dart';
import 'chat_unread_progress.dart';
import 'chat_view_model.dart';
import 'chat_wallpaper.dart';
import 'checklist_composer_view.dart';
import 'custom_emoji.dart';
import 'emoji_store.dart';
import 'forward_options.dart';
import 'group_remark_controller.dart';
import 'image_media_album_bubble.dart';
import 'image_preview.dart';
import 'internal_chat_link_router.dart';
import 'link_handler.dart';
import 'media_album_layout.dart';
import 'media_library_saver.dart';
import 'media_send_preview_view.dart';
import 'message_action_menu.dart';
import 'message_bubble.dart';
import 'message_bubble_repository_view.dart';
import 'message_reaction_availability.dart';
import 'message_replies_sheet.dart';
import 'message_translation_cache.dart';
import 'music_player_controller.dart';
import 'openai_compatible_unread_summary_provider.dart';
import 'outgoing_attachment.dart';
import 'poll_results_view.dart';
import 'quick_reaction_choice.dart';
import 'shared_contact_sheet.dart';
import 'sticker_set_detail_view.dart';
import 'sticker_viewer.dart';
import 'telegram_ai_service.dart';
import 'telegram_cocoon_unread_summary_provider.dart';
import 'telegram_mini_app_view.dart';
import 'transcript_pivot_partition.dart';
import 'translation_fallback.dart';
import 'unread_chat_summary_models.dart';
import 'unread_chat_summary_service.dart';
import 'unread_chat_summary_view.dart';
import 'video_playback_queue.dart';
import 'video_player_view.dart';

@visibleForTesting
bool chatTranscriptAllowsCommentAttachment({required bool isChannel}) =>
    isChannel;

@visibleForTesting
Future<T?> showReactionUsersModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showAppAdaptiveSheetDialog<T>(
    context: context,
    builder: builder,
    barrierLabel: AppStrings.t(AppStringKeys.musicPlayerClose),
    barrierColor: Colors.black.withValues(alpha: 0.46),
    transitionDuration: const Duration(milliseconds: 220),
    centeredBackgroundColor: context.colors.card,
    mobileTransitionBuilder: (context, animation, _, child) {
      final offset = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return SlideTransition(position: offset, child: child);
    },
  );
}

@visibleForTesting
const reactionUsersCenteredFrameKey = ValueKey<String>(
  'reaction-users-centered-frame',
);

@visibleForTesting
const reactionUsersTouchFrameKey = ValueKey<String>(
  'reaction-users-touch-frame',
);

@visibleForTesting
const reactionUsersDragHandleKey = ValueKey<String>(
  'reaction-users-drag-handle',
);

@visibleForTesting
class ReactionUsersSheetFrame extends StatelessWidget {
  const ReactionUsersSheetFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final centered = appModalUsesCenteredPresentation(
      MediaQuery.sizeOf(context),
    );
    final height = math.min(MediaQuery.sizeOf(context).height * 0.62, 560.0);
    final content = SizedBox(
      height: height,
      width: double.infinity,
      child: Column(
        children: [
          if (centered)
            const SizedBox(height: 8)
          else ...[
            const SizedBox(height: 10),
            Container(
              key: reactionUsersDragHandleKey,
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: c.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(child: child),
        ],
      ),
    );
    if (centered) {
      return ColoredBox(
        key: reactionUsersCenteredFrameKey,
        color: c.card,
        child: content,
      );
    }
    return SafeArea(
      top: false,
      child: Align(
        key: reactionUsersTouchFrameKey,
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: ColoredBox(color: c.card, child: content),
        ),
      ),
    );
  }
}

@visibleForTesting
bool protectedContentRequiresMobileSelectionClear({
  required bool hasProtectedContent,
  required bool hasSelectionKey,
}) => hasProtectedContent && hasSelectionKey;

@visibleForTesting
bool selectionAreaContainsGlobalTextPosition({
  required GlobalKey<SelectionAreaState> selectionAreaKey,
  required Offset globalPosition,
}) {
  final root = selectionAreaKey.currentContext?.findRenderObject();
  if (root is! RenderBox ||
      !root.attached ||
      !root.hasSize ||
      !(Offset.zero & root.size).contains(root.globalToLocal(globalPosition))) {
    return false;
  }

  bool visibleWithinSelectionArea(RenderParagraph paragraph) {
    RenderObject? current = paragraph;
    while (current != null) {
      if (current case final RenderBox box when box.hasSize) {
        final localPosition = box.globalToLocal(globalPosition);
        if (!(Offset.zero & box.size).contains(localPosition)) return false;
      }
      if (identical(current, root)) return true;
      current = current.parent;
    }
    return false;
  }

  var contains = false;
  void visit(RenderObject child) {
    if (contains || !child.attached) return;
    if (child case final RenderParagraph paragraph
        when paragraph.hasSize &&
            paragraph.registrar != null &&
            visibleWithinSelectionArea(paragraph)) {
      final localPosition = paragraph.globalToLocal(globalPosition);
      if ((Offset.zero & paragraph.size).contains(localPosition)) {
        contains = true;
        return;
      }
    }
    child.visitChildren(visit);
  }

  if (root case final RenderParagraph paragraph
      when paragraph.hasSize &&
          paragraph.registrar != null &&
          visibleWithinSelectionArea(paragraph)) {
    final localPosition = paragraph.globalToLocal(globalPosition);
    contains = (Offset.zero & paragraph.size).contains(localPosition);
  }
  if (!contains) root.visitChildren(visit);
  return contains;
}

@visibleForTesting
class ChatActionOverlayGestureLayer extends StatelessWidget {
  const ChatActionOverlayGestureLayer({
    super.key,
    required this.selectionAreaKey,
    required this.child,
  });

  final GlobalKey<SelectionAreaState>? selectionAreaKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => _MessageSelectionHitTestPassthrough(
    key: const ValueKey('message-action-overlay-gesture-layer'),
    selectionAreaKey: isDesktopTargetPlatform(Theme.of(context).platform)
        ? null
        : selectionAreaKey,
    child: child,
  );
}

class _MessageSelectionHitTestPassthrough
    extends SingleChildRenderObjectWidget {
  const _MessageSelectionHitTestPassthrough({
    super.key,
    required this.selectionAreaKey,
    required super.child,
  });

  final GlobalKey<SelectionAreaState>? selectionAreaKey;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMessageSelectionHitTestPassthrough(selectionAreaKey);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderMessageSelectionHitTestPassthrough renderObject,
  ) {
    renderObject.selectionAreaKey = selectionAreaKey;
  }
}

class _RenderMessageSelectionHitTestPassthrough extends RenderProxyBox {
  _RenderMessageSelectionHitTestPassthrough(this.selectionAreaKey);

  GlobalKey<SelectionAreaState>? selectionAreaKey;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final key = selectionAreaKey;
    if (key != null &&
        selectionAreaContainsGlobalTextPosition(
          selectionAreaKey: key,
          globalPosition: localToGlobal(position),
        )) {
      // Keep the visible overlay controls first, then add only the selected
      // text region underneath. Letting the Stack hit-test the whole transcript
      // would also admit its scroll and swipe-to-reply recognizers while the
      // action menu is open.
      final overlayHit = super.hitTest(result, position: position);
      final selectionRoot = key.currentContext?.findRenderObject();
      if (selectionRoot is RenderBox &&
          selectionRoot.attached &&
          selectionRoot.hasSize) {
        final globalToOverlay = Matrix4.tryInvert(getTransformTo(null));
        if (globalToOverlay == null) return overlayHit;
        final selectionToOverlay = globalToOverlay
          ..multiply(selectionRoot.getTransformTo(null));
        final selectionHit = result.addWithPaintTransform(
          transform: selectionToOverlay,
          position: position,
          hitTest: (result, localPosition) =>
              selectionRoot.hitTest(result, position: localPosition),
        );
        return overlayHit || selectionHit;
      }
      return overlayHit;
    }
    return super.hitTest(result, position: position);
  }
}

@visibleForTesting
bool chatTranscriptBoundaryChanged({
  required int previousCount,
  required int currentCount,
  required int? previousNewestMessageId,
  required int? currentNewestMessageId,
  required int? previousOldestMessageId,
  required int? currentOldestMessageId,
  required bool hasBufferedLiveMessages,
}) =>
    previousCount != currentCount ||
    previousNewestMessageId != currentNewestMessageId ||
    previousOldestMessageId != currentOldestMessageId ||
    hasBufferedLiveMessages;

class _MessageDeleteOptions {
  const _MessageDeleteOptions({
    required this.deleteMessage,
    required this.reportSpam,
    required this.blockSender,
    required this.deleteAllFromSender,
  });

  final bool deleteMessage;
  final bool reportSpam;
  final bool blockSender;
  final bool deleteAllFromSender;

  bool get hasAny =>
      deleteMessage || reportSpam || blockSender || deleteAllFromSender;
}

class _UnreadSummarySession {
  const _UnreadSummarySession(this.service, {this.onDispose});

  final UnreadChatSummaryService service;
  final VoidCallback? onDispose;

  Future<UnreadChatSummary> summarize(
    UnreadChatRangeSnapshot snapshot, {
    UnreadChatSummaryProgressCallback? onProgress,
    UnreadChatSummaryDraftCallback? onDraft,
  }) => service.summarize(snapshot, onProgress: onProgress, onDraft: onDraft);

  void dispose() => onDispose?.call();
}

class _ChecklistDialogButton extends StatelessWidget {
  const _ChecklistDialogButton({
    required this.label,
    required this.foreground,
    required this.onTap,
    this.fill,
  });

  final String label;
  final Color foreground;
  final VoidCallback? onTap;
  final Color? fill;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 38,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Text(
        label.l10n(context),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    ),
  );
}

class _MessageDeleteOptionsDialog extends StatefulWidget {
  const _MessageDeleteOptionsDialog({
    required this.canActOnSender,
    required this.canDeleteAllFromSender,
    required this.senderName,
  });

  final bool canActOnSender;
  final bool canDeleteAllFromSender;
  final String senderName;

  @override
  State<_MessageDeleteOptionsDialog> createState() =>
      _MessageDeleteOptionsDialogState();
}

class _MessageDeleteOptionsDialogState
    extends State<_MessageDeleteOptionsDialog> {
  bool _deleteMessage = true;
  bool _reportSpam = false;
  bool _blockSender = false;
  bool _deleteAllFromSender = false;

  _MessageDeleteOptions get _options => _MessageDeleteOptions(
    deleteMessage: _deleteMessage,
    reportSpam: _reportSpam,
    blockSender: _blockSender,
    deleteAllFromSender: _deleteAllFromSender,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final options = _options;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: math.min(MediaQuery.of(context).size.width - 40, 420),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStringKeys.chatDeleteSingleMessageQuestion.l10n(context),
                style: TextStyle(
                  fontSize: 19,
                  height: 1.28,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 22),
              _optionRow(
                label: AppStringKeys.chatDeleteOptionDeleteMessage.l10n(
                  context,
                ),
                value: _deleteMessage,
                onTap: () => setState(() => _deleteMessage = !_deleteMessage),
              ),
              if (widget.canActOnSender) ...[
                _optionRow(
                  label: AppStringKeys.chatDeleteOptionReportSpam.l10n(context),
                  value: _reportSpam,
                  onTap: () => setState(() => _reportSpam = !_reportSpam),
                ),
                _optionRow(
                  label: AppStringKeys.chatDeleteOptionBlockSender.l10n(
                    context,
                  ),
                  value: _blockSender,
                  onTap: () => setState(() => _blockSender = !_blockSender),
                ),
                if (widget.canDeleteAllFromSender)
                  _optionRow(
                    label: AppStrings.t(
                      AppStringKeys.chatDeleteOptionDeleteAllFromSender,
                      {'value1': widget.senderName},
                    ),
                    value: _deleteAllFromSender,
                    onTap: () => setState(
                      () => _deleteAllFromSender = !_deleteAllFromSender,
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _dialogButton(
                    label: AppStringKeys.countryPickerCancel.l10n(context),
                    color: c.textSecondary,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 10),
                  _dialogButton(
                    label: AppStringKeys.chatDelete.l10n(context),
                    color: options.hasAny
                        ? const Color(0xFFFF6961)
                        : c.textTertiary,
                    onTap: options.hasAny
                        ? () => Navigator.of(context).pop(options)
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionRow({
    required String label,
    required bool value,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value ? AppTheme.brand : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: value ? AppTheme.brand : c.textTertiary,
                  width: 2,
                ),
              ),
              child: value
                  ? const AppIcon(
                      HeroAppIcons.check,
                      size: 17,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.25,
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: color,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

enum _MediaEditAction { edit, replace, delete }

class _MediaEditActionDialog extends StatelessWidget {
  const _MediaEditActionDialog({required this.mediaLabel});

  final String mediaLabel;

  @override
  Widget build(BuildContext context) {
    return _ChatEditChoiceDialog<_MediaEditAction>(
      title: mediaLabel,
      choices: const [
        (
          value: _MediaEditAction.edit,
          icon: HeroAppIcons.penToSquare,
          label: AppStringKeys.messageActionEdit,
          destructive: false,
        ),
        (
          value: _MediaEditAction.replace,
          icon: HeroAppIcons.images,
          label: AppStringKeys.chatMediaReplace,
          destructive: false,
        ),
        (
          value: _MediaEditAction.delete,
          icon: HeroAppIcons.trash,
          label: AppStringKeys.chatMediaDelete,
          destructive: true,
        ),
      ],
    );
  }
}

typedef _ChatEditChoice<T> = ({
  T value,
  AppIconData icon,
  String label,
  bool destructive,
});

class _ChatEditChoiceDialog<T> extends StatelessWidget {
  const _ChatEditChoiceDialog({required this.title, required this.choices});

  final String title;
  final List<_ChatEditChoice<T>> choices;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: math.min(MediaQuery.sizeOf(context).width - 40, 360),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
              child: Text(
                title.l10n(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            for (final choice in choices)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(choice.value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        choice.icon,
                        size: 22,
                        color: choice.destructive
                            ? const Color(0xFFFF6961)
                            : c.textSecondary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          choice.label.l10n(context),
                          style: TextStyle(
                            color: choice.destructive
                                ? const Color(0xFFFF6961)
                                : c.textPrimary,
                            fontSize: 16,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lets an adaptive parent save a chat's measured viewport before replacing
/// its detail pane. Waiting for [State.dispose] is too late on desktop because
/// the render tree has already detached, so message geometry is unavailable.
class ChatViewExitController {
  VoidCallback? _prepareExit;

  /// Registers the currently visible chat and returns a matching detacher.
  VoidCallback register(VoidCallback prepareExit) {
    _prepareExit = prepareExit;
    return () {
      if (identical(_prepareExit, prepareExit)) _prepareExit = null;
    };
  }

  void prepareExit() => _prepareExit?.call();
}

/// Keeps the chat header full-width while reserving a trailing context pane
/// only below it. This avoids the empty header gutter produced by placing the
/// context pane beside the entire chat view.
@visibleForTesting
class ChatHeaderTrailingPaneLayout extends StatelessWidget {
  const ChatHeaderTrailingPaneLayout({
    super.key,
    required this.header,
    required this.body,
    this.trailingPane,
    this.trailingPaneWidth = 0,
  });

  final Widget header;
  final Widget body;
  final Widget? trailingPane;
  final double trailingPaneWidth;

  @override
  Widget build(BuildContext context) {
    final pane = trailingPane;
    return Column(
      children: [
        KeyedSubtree(key: const ValueKey('chatFullWidthHeader'), child: header),
        Expanded(
          child: pane == null || trailingPaneWidth <= 0
              ? KeyedSubtree(
                  key: const ValueKey('chatConversationContent'),
                  child: body,
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: KeyedSubtree(
                        key: const ValueKey('chatConversationContent'),
                        child: body,
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: context.colors.divider,
                    ),
                    SizedBox(
                      key: const ValueKey('chatTrailingContextPane'),
                      width: trailingPaneWidth,
                      child: pane,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.chatId,
    required this.title,
    this.initialMessageId,
    this.seedMessage,
    this.showBackButton = true,
    this.headerHeight = 48,
    this.headerColor,
    this.showHeaderDivider = true,
    this.headerBottom,
    this.headerBottomHeight = 44,
    this.trailingPane,
    this.trailingPaneWidth = 0,
    this.requestComposerFocusOnReady = false,
    this.onOpenTopicMode,
    this.onChatKindResolved,
    this.onInfoPressed,
    this.onOpenFullInfo,
    this.onOpenUserProfile,
    this.onBack,
    this.exitController,
  });
  final int chatId;
  final String title;
  final int? initialMessageId;
  final ChatMessage? seedMessage;
  final bool showBackButton;
  final double headerHeight;
  final Color? headerColor;
  final bool showHeaderDivider;
  final Widget? headerBottom;
  final double headerBottomHeight;
  final Widget? trailingPane;
  final double trailingPaneWidth;
  final bool requestComposerFocusOnReady;
  final ValueChanged<int?>? onOpenTopicMode;
  final ValueChanged<ChatKind>? onChatKindResolved;
  final VoidCallback? onInfoPressed;
  final VoidCallback? onOpenFullInfo;
  final void Function(int userId, String name)? onOpenUserProfile;
  final VoidCallback? onBack;
  final ChatViewExitController? exitController;

  @override
  State<ChatView> createState() => _ChatViewState();
}

/// Drops reusable transcript and scroll snapshots after an OS memory warning.
/// The active chat owns its own view model and is not affected.
void clearChatMemoryCaches() {
  _ChatViewState._sessionCache.clear();
  _ChatViewState._sessionScrollSnapshots.clear();
}

@visibleForTesting
bool wideGroupHeaderActionsEnabled(
  Size windowSize, {
  required bool isGroup,
  required bool hasContextPaneToggle,
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) =>
    usesSplitSelectionLayout(windowSize, platform: platform, isWeb: isWeb) &&
    (isGroup || hasContextPaneToggle);

@visibleForTesting
class WideGroupChatHeaderActions extends StatelessWidget {
  const WideGroupChatHeaderActions({
    super.key,
    required this.onStartCall,
    required this.onOpenFullInfo,
    this.onToggleContext,
    this.showCallActions = true,
  });

  final ValueChanged<bool> onStartCall;
  final VoidCallback? onToggleContext;
  final VoidCallback onOpenFullInfo;
  final bool showCallActions;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showCallActions) ...[
        _ChatHeaderAction(
          key: const ValueKey('chatHeaderGroupVoiceCall'),
          label: AppStringKeys.composerGroupVoiceCall.l10n(context),
          icon: HeroAppIcons.phone,
          onTap: () => onStartCall(false),
        ),
        _ChatHeaderAction(
          key: const ValueKey('chatHeaderGroupVideoCall'),
          label: AppStringKeys.composerGroupVideoCall.l10n(context),
          icon: HeroAppIcons.video,
          onTap: () => onStartCall(true),
        ),
      ],
      if (onToggleContext != null)
        _ChatHeaderAction(
          key: const ValueKey('chatHeaderGroupContextToggle'),
          label: AppStringKeys.chatInfoGroupAnnouncement.l10n(context),
          icon: HeroAppIcons.grip,
          onTap: onToggleContext!,
        ),
      _ChatHeaderAction(
        key: const ValueKey('chatHeaderFullInfo'),
        label: AppStringKeys.chatInfoTitle.l10n(context),
        icon: HeroAppIcons.gear,
        onTap: onOpenFullInfo,
      ),
    ],
  );
}

class _ChatHeaderAction extends StatelessWidget {
  const _ChatHeaderAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      semanticLabel: label,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: AppMetric.hitTarget,
        height: AppMetric.hitTarget,
        child: Center(
          child: AppIcon(icon, size: AppIconSize.nav, color: c.textPrimary),
        ),
      ),
    );
  }
}

class _TranscriptEntry {
  _TranscriptEntry(this.messages, this.startIndex);

  final List<ChatMessage> messages;
  final int startIndex;

  ChatMessage get first => messages.first;
  ChatMessage get last => messages.last;
  bool get isBlockedRun =>
      messages.isNotEmpty && messages.every((message) => message.blockedByUser);
  ChatMediaAlbumKind? get mediaAlbumKind =>
      messages.length > 1 && !isBlockedRun ? chatMediaAlbumKind(first) : null;
  bool get isImageGroup => mediaAlbumKind == ChatMediaAlbumKind.visual;
  bool get isDocumentGroup => mediaAlbumKind == ChatMediaAlbumKind.document;

  /// Stable identity for element reuse across index shifts (history pages
  /// prepend and shift every index).
  late final Key key = ValueKey(
    isBlockedRun
        ? 'blocked-${last.id}'
        : first.mediaAlbumId != 0
        ? 'album-${first.mediaAlbumId}-${last.id}'
        : 'message-${first.id}',
  );
}

class _ChatScrollSnapshot {
  const _ChatScrollSnapshot({
    required this.pixels,
    required this.wasAtLoadedBottom,
    required this.knownLatestMessageId,
    this.pivotMessageId,
    this.anchorMessageId,
    this.anchorViewportOffset,
  });

  final double pixels;
  final bool wasAtLoadedBottom;
  final int knownLatestMessageId;
  final int? pivotMessageId;
  final int? anchorMessageId;
  final double? anchorViewportOffset;
}

/// Reads the keyboard inset in an element of its own.
///
/// The chat screen only uses the inset for scroll bookkeeping, but reading it
/// from `build()` put `_ChatViewState` on the viewInsets aspect — which the
/// keyboard animates every frame, rebuilding the header, composer and every
/// materialized bubble. Rebuilding this wrapper hands back the very same child
/// widget, so `Element.updateChild` short-circuits the whole subtree.
class _KeyboardInsetProbe extends StatelessWidget {
  const _KeyboardInsetProbe({required this.onInset, required this.child});

  final ValueChanged<double> onInset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onInset(MediaQuery.viewInsetsOf(context).bottom);
    return child;
  }
}

class _ChatViewState extends State<ChatView> {
  late final bool _openAtLatest;
  late final ({int accountSlot, int chatId}) _sessionKey;
  late _ChatScrollSnapshot? _sessionScrollSnapshot;
  late final ChatSessionRenderState? _sessionRenderState;
  late bool _olderHistoryExhaustedHint;
  late final ChatViewModel _vm;
  ChatKind? _reportedChatKind;
  late final TranslationController _translation;
  AiSettingsController? _ai;
  Set<TranslationProvider> _nativeTranslationProviders = const {};
  int? _dismissedBotApiWarningMask;
  late final ScrollController _scroll;
  final _pinnedKey = GlobalKey(); // the pinned message's row, for scroll-to
  final _targetKey = GlobalKey(); // arbitrary linked/anchored message row
  final _unreadKey = GlobalKey(); // the "以下为新消息" divider, for entry scroll
  final _transcriptViewportKey = GlobalKey();
  final _newerTranscriptSliverKey = GlobalKey();
  final _firstContactLayoutKey = GlobalKey();
  Map<int, GlobalKey> _entryVisibilityKeys = <int, GlobalKey>{};
  Map<int, _TranscriptEntry> _trackedTranscriptEntries = const {};
  TranscriptPivot? _transcriptPivot;
  bool _transcriptPivotFrozen = false;
  bool _transcriptPivotFreezeScheduled = false;
  late int _historyWindowRevision;
  late int _historyWindowInvalidationRevision;
  final Set<int> _expandedBlockedRunIds = <int>{};
  final Set<int> _showOriginalTranslationMessageIds = <int>{};
  int? _desktopStickerSetId;
  bool _unreadProgressUpdateScheduled = false;
  bool _viewTickerEnabled = true;
  bool _modelDirtyWhileInactive = false;
  bool _reactivationSyncScheduled = false;
  ChatMessage? _actionTarget;
  Rect? _actionRect; // bounds in the action-overlay Stack's coordinate space
  final GlobalKey _actionOverlayKey = GlobalKey();
  GlobalKey<SelectionAreaState>? _mobileTextSelectionAreaKey;
  int? _mobileTextSelectionMessageId;
  bool _mobileTextSelectionActive = false;
  Offset? _lastActionPointerGlobalPosition;
  MessageActionSource _actionSource = MessageActionSource.normal;
  bool _reactionExpanded = false; // full reaction picker vs. quick bar
  String _reactionTab = 'standard'; // 'standard' or a custom-emoji pack id
  MessageReactionAvailability? _actionReactionAvailability;
  int _actionReactionAvailabilityGeneration = 0;
  int _lastCount = 0;
  bool _didInitialScroll = false; // one-time entry positioning has run
  bool _showJumpDown = false; // scrolled up → show jump-to-bottom button
  bool _bannerDismissed = false; // "N条新消息" banner dismissed / caught up
  Timer? _bannerTimer; // auto-hides the banner a few seconds after it appears
  Timer? _readSyncTimer;
  Timer? _handoffUpdateTimer;
  int? _scrollTargetId;
  int _scrollTargetGeneration = 0;
  int _transcriptGestureGeneration = 0;
  int? _lastNewestMessageId;
  int? _lastOldestMessageId;
  final ChatUnreadProgress _unreadProgress = ChatUnreadProgress();
  int get _liveNewMessageCount => _unreadProgress.liveCount;
  int get _remainingUnreadCount =>
      _unreadProgress.badgeCount(entryUnreadCount: _entryUnreadCount);
  int _entryUnreadCount = 0;
  int _entryLastReadInboxId = 0;
  int _entryLatestMessageId = 0;
  int? _entryFirstUnreadMessageId;
  bool _showEntryUnreadBanner = false;
  late final ChatMessageSearchController _search;

  /// Mirrors `_search.isActive`, so the controller's per-keystroke
  /// notifications only setState when the value this build reads changed.
  bool _searchActive = false;

  /// Whether the last layout had room for the results pane. Read by callbacks
  /// that run outside build, where the constraints are no longer at hand.
  bool _searchResultsPaneVisible = false;

  /// The hit the search cursor is sitting on. Unlike [_scrollTargetId] this
  /// survives the jump that put it there, so the bubble stays marked while the
  /// user steps through the rest of the results.
  int? _searchHighlightId;
  double _keyboardInset = 0;
  // Bumped once per ChatView build; the shell LayoutBuilder reuses its subtree
  // whenever the generation and the available width are both unchanged.
  int _shellLayoutGeneration = 0;
  int _cachedShellLayoutGeneration = -1;
  double _cachedShellLayoutWidth = double.nan;
  Widget? _cachedShellLayout;
  bool _shortTranscriptFillScheduled = false;
  bool _isFillingShortTranscript = false;
  int _shortTranscriptFillGeneration = 0;
  bool _shortFirstContactRevealScheduled = false;
  bool _showingFullyVisibleFirstContactHistory = false;
  bool _transcriptViewportClaimedByUser = false;
  late final ChatReturnToLatestCoordinator _returnToLatestCoordinator;
  late final ChatRestoredPositionGuard _restoredPositionGuard;
  final ChatSessionReopenNavigationGuard _sessionReopenNavigationGuard =
      ChatSessionReopenNavigationGuard();
  late bool _sessionReopenDispositionResolved;
  bool _sessionReopenResolutionInFlight = false;
  bool _prioritizingSessionUnread = false;
  bool _preserveSnapshotAfterFailedSessionJump = false;
  bool _initialTranscriptReady = false;
  bool _initialTranscriptPositionCancelled = false;
  final Set<int> _transcriptPointersDown = <int>{};
  bool _bottomScrollScheduled = false;
  bool _scheduledBottomAnimated = true;
  int _scheduledBottomGeneration = 0;
  final _bottomFollow = ChatBottomFollowCoordinator();
  final Set<int> _selectedMessageIds = {};
  int? _selectionAnchorId;
  bool _selectionScrollingUp = false;
  double _lastScrollPixels = 0;
  ScrollDirection _lastTranscriptUserScrollDirection = ScrollDirection.idle;
  bool _backSwipePopping = false;
  bool _loadingOlderFromScroll = false;
  final OldestHistoryPullController _olderHistoryPull =
      OldestHistoryPullController();
  bool _revealLoadedOlderPage = false;
  bool _loadedOlderRevealPending = false;
  bool _loadedOlderRevealScheduled = false;
  int _loadedOlderRevealGestureGeneration = 0;
  bool _parkedShortTranscriptRepairScheduled = false;
  bool _wasLoadingOlder = false;
  bool _maintainSessionScrollAnchor = false;
  ChatThemeStyle? _resolvedChatThemeStyle;
  TelegramCloudTheme? _resolvedCloudTheme;
  bool _themingEnabled = true;
  bool _hasCustomChatTheme = false;
  bool _sessionAnchorMaintenanceScheduled = false;
  bool _maintainRestoredBottom = false;
  final _restoredBottomCorrection = ChatBottomCorrectionCoordinator();
  bool _openingUnreadMention = false;
  bool _openingUnreadSummary = false;
  bool _exitStatePrepared = false;
  bool _notificationVisibilityRegistered = false;
  bool _chatLanguageDetectionRunning = false;
  bool _chatLanguageDetectionComplete = false;
  int? _chatLanguageDetectionNewestMessageId;
  DateTime? _chatLanguageDetectedAt;
  String? _detectedChatLanguage;
  bool _autoTranslationRunning = false;
  bool _autoTranslationPassPending = false;
  final Set<int> _autoTranslationFailedMessageIds = <int>{};
  final Set<int> _autoTranslatedMessageIds = <int>{};
  bool _sendFailureDialogVisible = false;
  VoidCallback? _detachExitController;
  final ChatSessionCacheWriteGate _sessionCacheWriteGate =
      ChatSessionCacheWriteGate();

  /// Gap (seconds) between messages that triggers a fresh time separator.
  static const _separatorGap = 300;
  static const _initialTargetAlignment = 0.30;
  static const _initialUnreadAlignment = 0.12;
  static const _pendingTranscriptOrderId = 0x7FFFFFFFFFFFFFFF;
  static final Map<({int accountSlot, int chatId}), _ChatScrollSnapshot>
  _sessionScrollSnapshots = {};
  static final ChatSessionCache _sessionCache = ChatSessionCache();
  late final ChatAutoScrollPolicy _autoScrollPolicy;
  final ChatWallpaperController _wallpaperController =
      ChatWallpaperController.shared;

  double _messageMediaMaxWidth([double? chatWidth]) {
    final width = chatWidth ?? MediaQuery.sizeOf(context).width;
    return math.max(1.0, width * 0.75);
  }

  int _transcriptOrderId(ChatMessage message) =>
      isPendingChatMessage(message) ? _pendingTranscriptOrderId : message.id;

  ChatMessage? _latestServerMessage(List<ChatMessage> messages) {
    for (final message in messages.reversed) {
      if (!isPendingChatMessage(message) && message.id > 0) return message;
    }
    return null;
  }

  ChatMessage? _oldestServerMessage(List<ChatMessage> messages) {
    for (final message in messages) {
      if (!isPendingChatMessage(message) && message.id > 0) return message;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _detachExitController = widget.exitController?.register(_prepareExitState);
    _wallpaperController.addListener(_onWallpaperChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_wallpaperController.load(widget.chatId));
      unawaited(_wallpaperController.loadDefaultWallpaper(dark: false));
      unawaited(_wallpaperController.loadDefaultWallpaper(dark: true));
      unawaited(_wallpaperController.loadGlobalChatThemes());
    });
    _openAtLatest = context.read<ThemeController>().openChatsAtLatest;
    _sessionKey = (
      accountSlot: TdClient.shared.activeSlot,
      chatId: widget.chatId,
    );
    _sessionRenderState = widget.initialMessageId == null
        ? _sessionCache.read(
            accountSlot: _sessionKey.accountSlot,
            chatId: _sessionKey.chatId,
          )
        : null;
    _olderHistoryExhaustedHint =
        _sessionRenderState?.olderHistoryExhausted ?? false;
    _sessionScrollSnapshot = widget.initialMessageId == null
        ? _sessionScrollSnapshots[_sessionKey]
        : null;
    final sessionRenderState = _sessionRenderState;
    final hasCachedLatestTranscript =
        sessionRenderState != null &&
        !sessionRenderState.anchoredHistory &&
        sessionRenderState.messages.isNotEmpty;
    final openAtBottom = shouldOpenChatAtBottom(
      hasExplicitTarget: widget.initialMessageId != null,
      openAtLatest: _openAtLatest,
      hasSnapshot: _sessionScrollSnapshot != null,
      snapshotWasAtBottom: _sessionScrollSnapshot?.wasAtLoadedBottom ?? false,
      hasCachedLatestTranscript: hasCachedLatestTranscript,
    );
    final savedPivotMessageId = _sessionScrollSnapshot?.pivotMessageId;
    final hasSessionTranscript =
        _sessionRenderState?.messages.isNotEmpty ?? false;
    if (shouldRestoreTranscriptPivot(
      pivotMessageId: savedPivotMessageId,
      hasSessionTranscript: hasSessionTranscript,
      newestMessageId: _latestServerMessage(
        _sessionRenderState?.messages ?? const [],
      )?.id,
      openAtBottom: openAtBottom,
    )) {
      _transcriptPivot = TranscriptPivot(savedPivotMessageId!);
      _transcriptPivotFrozen = savedPivotMessageId != _pendingTranscriptOrderId;
    } else if (savedPivotMessageId != null && !hasSessionTranscript) {
      // Drop the orphan pivot from the in-memory snapshot so a later reopen
      // with a fresh transcript cache does not reintroduce the thin after-arm.
      final snapshot = _sessionScrollSnapshots[_sessionKey];
      if (snapshot != null && snapshot.pivotMessageId != null) {
        _sessionScrollSnapshots[_sessionKey] = _ChatScrollSnapshot(
          pixels: snapshot.pixels,
          wasAtLoadedBottom: snapshot.wasAtLoadedBottom,
          knownLatestMessageId: snapshot.knownLatestMessageId,
          anchorMessageId: snapshot.anchorMessageId,
          anchorViewportOffset: snapshot.anchorViewportOffset,
        );
      }
    }
    final initialScrollPlan = chatInitialScrollPlan(
      hasCachedTranscript: _sessionRenderState?.messages.isNotEmpty ?? false,
      savedPixels: _sessionScrollSnapshot?.pixels,
      savedAtBottom: _sessionScrollSnapshot?.wasAtLoadedBottom ?? false,
      openAtBottom: openAtBottom,
    );
    _maintainRestoredBottom = initialScrollPlan.correctToBottomAfterLayout;
    final sessionScrollSnapshot = _sessionScrollSnapshot;
    _maintainSessionScrollAnchor =
        sessionScrollSnapshot?.anchorMessageId != null &&
        sessionScrollSnapshot?.anchorViewportOffset != null;
    _sessionReopenDispositionResolved =
        sessionScrollSnapshot == null || widget.initialMessageId != null;
    _restoredPositionGuard = ChatRestoredPositionGuard(
      sessionScrollSnapshot != null && !sessionScrollSnapshot.wasAtLoadedBottom,
    );
    _autoScrollPolicy = ChatAutoScrollPolicy(
      preserveViewport:
          sessionScrollSnapshot != null &&
          !sessionScrollSnapshot.wasAtLoadedBottom,
    );
    _scroll = ScrollController(
      initialScrollOffset: initialScrollPlan.initialOffset,
    )..addListener(_onScroll);
    _vm = ChatViewModel(
      chatId: widget.chatId,
      title: widget.title,
      markReadOnOpen: _shouldOpenAtBottom,
      initialMessageId: widget.initialMessageId,
      sessionAnchorMessageId: _shouldRestoreSessionScroll
          ? _sessionScrollSnapshot?.anchorMessageId
          : null,
      sessionFallbackOpenAtLatest: _openAtLatest,
      sessionMessages: _sessionRenderState?.messages,
      sessionAnchoredHistory: _sessionRenderState?.anchoredHistory ?? false,
      sessionFirstContactInfo: _sessionRenderState?.firstContactInfo,
      seedMessage: widget.seedMessage,
    );
    _returnToLatestCoordinator = ChatReturnToLatestCoordinator(
      loadLatest: _vm.loadLatestHistory,
      invalidateLatestLoad: _vm.invalidateLatestHistoryLoad,
      needsLatestLoad: () => shouldLoadLatestChatHistory(
        anchoredHistory: _vm.anchoredHistory,
        historyReachesLatest: _vm.historyReachesLatest,
      ),
      onChanged: _onReturnToLatestCoordinatorChanged,
      onReadyAvailable: _drainReturnToLatestIntent,
    );
    _translation = context.read<TranslationController>();
    _translation.addListener(_onTranslationSettingsChanged);
    _ai = context.read<AiSettingsController?>();
    _ai?.addListener(_onTranslationSettingsChanged);
    unawaited(_loadNativeTranslationProviders());
    unawaited(_loadBotApiWarningDismissal());
    _historyWindowRevision = _vm.historyWindowRevision;
    _historyWindowInvalidationRevision = _vm.historyWindowInvalidationRevision;
    unawaited(
      TelegramCountryNames.shared
          .load()
          .then((_) {
            if (mounted && _vm.firstContactInfo != null) setState(() {});
          })
          .catchError((Object _) {}),
    );
    if (_sessionRenderState != null && _vm.messages.isNotEmpty) {
      _didInitialScroll = true;
      _initialTranscriptReady = true;
      _lastCount = _vm.messages.length;
      _lastNewestMessageId = _latestServerMessage(_vm.messages)?.id;
      _lastOldestMessageId = _oldestServerMessage(_vm.messages)?.id;
      if (initialScrollPlan.correctToBottomAfterLayout) {
        _scheduleRestoredBottomCorrection();
      }
      _scheduleShortTranscriptFill();
      _scheduleParkedShortTranscriptRepair();
    } else if (widget.seedMessage != null) {
      _lastCount = _vm.messages.length;
      _lastNewestMessageId = _latestServerMessage(_vm.messages)?.id;
      _lastOldestMessageId = _oldestServerMessage(_vm.messages)?.id;
    }
    _search = ChatMessageSearchController(
      chatId: widget.chatId,
      onActivateResult: _openSearchResult,
    )..addListener(_onSearchChanged);
    _vm.addListener(_onModel);
    _setScrollTarget(widget.initialMessageId);
    _vm.onAppear();
    _readSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _viewTickerEnabled && _isAtLoadedBottom(80)) {
        _markReadAtBottomIfNeeded();
      }
    });
    // Sync blocked-user-hiding toggle from theme.
    final theme = context.read<ThemeController>();
    BlockedUserService.shared.enabled = theme.hideBlockedUserMessages;
    // Load premium status early so the message menu can correctly hide the
    // emoji add/表情包 actions for non-premium users (the menu reads it).
    EmojiStore.shared.loadIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleChatLanguageDetection();
      _scheduleAutomaticTranslations();
    });
  }

  @override
  void didUpdateWidget(covariant ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.exitController, widget.exitController)) return;
    _detachExitController?.call();
    _detachExitController = widget.exitController?.register(_prepareExitState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final reactivated = !_viewTickerEnabled && tickerEnabled;
    _viewTickerEnabled = tickerEnabled;
    if (reactivated &&
        _modelDirtyWhileInactive &&
        !_reactivationSyncScheduled) {
      _reactivationSyncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reactivationSyncScheduled = false;
        if (!mounted || !_viewTickerEnabled || !_modelDirtyWhileInactive) {
          return;
        }
        _onModel();
      });
    }
    if (!_notificationVisibilityRegistered) {
      _notificationVisibilityRegistered = true;
      bool isVisible() =>
          mounted &&
          (ModalRoute.of(context)?.isCurrent ?? false) &&
          TickerMode.valuesOf(context).enabled;
      NotificationController.shared.registerVisibleChat(
        this,
        widget.chatId,
        isVisible,
      );
      // The desktop title-bar search scopes to whatever conversation is in
      // front; the title is read lazily so it follows the loaded peer name
      // rather than freezing the placeholder this route opened with.
      ActiveConversation.shared.register(
        this,
        chatId: widget.chatId,
        title: () => _vm.peerTitle.isEmpty ? widget.title : _vm.peerTitle,
        isVisible: isVisible,
        accountSlot: _sessionKey.accountSlot,
        messageId: _handoffMessageId,
      );
    }
    _scheduleHandoffRefresh();
  }

  int? _handoffMessageId() {
    if (!_initialTranscriptReady || _vm.messages.isEmpty) {
      final messageId = widget.initialMessageId;
      return messageId != null && messageId > 0 ? messageId : null;
    }
    if (_scroll.hasClients && _isAtLoadedBottom(80)) {
      final messageId = _latestServerMessage(_vm.messages)?.id;
      return messageId != null && messageId > 0 ? messageId : null;
    }
    final messageId =
        _captureSessionScrollAnchor()?.messageId ?? widget.initialMessageId;
    return messageId != null && messageId > 0 ? messageId : null;
  }

  void _scheduleHandoffRefresh() {
    _handoffUpdateTimer?.cancel();
    _handoffUpdateTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) ActiveConversation.shared.refresh();
    });
  }

  bool get _shouldRestoreSessionScroll {
    final snapshot = _sessionScrollSnapshot;
    return shouldRestoreChatSessionOffset(
      hasExplicitTarget: widget.initialMessageId != null,
      hasSnapshot: snapshot != null,
      snapshotWasAtBottom: snapshot?.wasAtLoadedBottom ?? false,
    );
  }

  bool get _shouldOpenAtBottom {
    final snapshot = _sessionScrollSnapshot;
    return shouldOpenChatAtBottom(
      hasExplicitTarget: widget.initialMessageId != null,
      openAtLatest: _openAtLatest,
      hasSnapshot: snapshot != null,
      snapshotWasAtBottom: snapshot?.wasAtLoadedBottom ?? false,
      hasCachedLatestTranscript:
          _sessionRenderState != null && !_sessionRenderState.anchoredHistory,
    );
  }

  bool get _hasSessionScrollAnchor =>
      _sessionScrollSnapshot?.anchorMessageId != null &&
      _sessionScrollSnapshot?.anchorViewportOffset != null;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final scrollingUp = pos.pixels < _lastScrollPixels;
    _lastScrollPixels = pos.pixels;
    _autoScrollPolicy.noteUserScroll(
      towardOlderMessages: pos.userScrollDirection == ScrollDirection.forward,
      isAtBottom: _isAtLoadedBottom(1),
    );
    // Persist cheap scalar state while the finger is moving. Capturing an
    // anchor walks every mounted transcript entry and performs layout-space
    // conversions, so defer that work until scrolling settles or the view
    // exits.
    _saveSessionScrollSnapshot(captureAnchor: false);
    _scheduleUnreadProgressUpdate();
    if (_selectionAnchorId != null && scrollingUp != _selectionScrollingUp) {
      setState(() => _selectionScrollingUp = scrollingUp);
    }
    if (pos.userScrollDirection == ScrollDirection.forward &&
        isNearOldest(pos, threshold: 500)) {
      unawaited(_loadOlderFromScroll());
    }
    final nearBottom = _isNearBottom(80);
    if (_isAtLoadedBottom(1)) {
      _autoScrollPolicy.returnToBottom();
      if (!_hasTranscriptPointerDown) {
        _transcriptViewportClaimedByUser = false;
      }
    }
    if (nearBottom &&
        (_liveNewMessageCount > 0 ||
            (!_openAtLatest && !_bannerDismissed && _vm.unreadCount > 0))) {
      setState(() {
        _unreadProgress.clearLiveMessages();
        _bannerDismissed = true;
      });
    }
    if (nearBottom) _markReadAtBottomIfNeeded();
    // Show the jump-to-bottom button once scrolled up from the newest message.
    final show =
        !_isAtLoadedBottom() &&
        (_vm.anchoredHistory || distanceToLatest(pos) > 120);
    if (show != _showJumpDown) setState(() => _showJumpDown = show);
  }

  bool _onTranscriptUserScroll(UserScrollNotification notification) {
    if (notification.direction == ScrollDirection.idle) {
      final endedTowardLatest =
          _lastTranscriptUserScrollDirection == ScrollDirection.reverse;
      _lastTranscriptUserScrollDirection = ScrollDirection.idle;
      final protectedRestoredPosition = _restoredPositionGuard
          .finishUserScroll();
      _returnToLatestCoordinator.userDragEnded();
      if (endedTowardLatest && !protectedRestoredPosition) {
        _requestAutomaticReturnToLatestIfNearLatest();
      }
    } else if (_initialTranscriptReady) {
      // Once an older-page request is in flight, a turn toward the latest
      // messages means the user has abandoned the pull. A later model frame
      // must not reveal that page by jumping the viewport back to the oldest
      // edge.
      if (notification.direction == ScrollDirection.reverse) {
        _revealLoadedOlderPage = false;
        _loadedOlderRevealPending = false;
      }
      _lastTranscriptUserScrollDirection = notification.direction;
      _restoredPositionGuard.noteUserScroll();
      _claimTranscriptViewport();
    }
    return false;
  }

  bool _onTranscriptScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is UserScrollNotification) {
      _onTranscriptUserScroll(notification);
    }
    if (notification is ScrollStartNotification) {
      _olderHistoryPull.reset();
    } else if (notification is ScrollUpdateNotification) {
      if (_olderHistoryPull.updateBouncingPosition(notification.metrics)) {
        _triggerOlderHistoryPull();
      }
    } else if (notification is OverscrollNotification) {
      if (isNearOldest(notification.metrics, threshold: 1) &&
          _olderHistoryPull.addClampedOverscroll(notification.overscroll)) {
        _triggerOlderHistoryPull();
      }
    } else if (notification is ScrollEndNotification) {
      _olderHistoryPull.reset();
      _scheduleLoadedOlderReveal();
      _saveSessionScrollSnapshot();
      _scheduleHandoffRefresh();
    }
    return false;
  }

  void _triggerOlderHistoryPull() {
    if (!_initialTranscriptReady ||
        _vm.messages.isEmpty ||
        !_vm.hasOlderHistory) {
      return;
    }
    _revealLoadedOlderPage = true;
    _loadedOlderRevealGestureGeneration = _transcriptGestureGeneration;
    _cancelBottomFollow();
    if (!_vm.isLoadingOlder && !_isFillingShortTranscript) {
      unawaited(_loadOlderFromScroll());
    }
  }

  void _scheduleLoadedOlderReveal() {
    if (!_loadedOlderRevealPending || _loadedOlderRevealScheduled) return;
    _loadedOlderRevealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadedOlderRevealScheduled = false;
      final supersededByUser =
          _transcriptGestureGeneration != _loadedOlderRevealGestureGeneration;
      final blockedByNavigation =
          _scrollTargetId != null ||
          _maintainSessionScrollAnchor ||
          _maintainRestoredBottom;
      if (!mounted ||
          !_loadedOlderRevealPending ||
          !_scroll.hasClients ||
          _hasTranscriptPointerDown ||
          _isUserScrolling ||
          supersededByUser ||
          blockedByNavigation) {
        if (_loadedOlderRevealPending &&
            (supersededByUser || blockedByNavigation)) {
          _loadedOlderRevealPending = false;
        }
        return;
      }
      _loadedOlderRevealPending = false;
      final target = _scroll.position.minScrollExtent;
      if ((_scroll.position.pixels - target).abs() > 0.5) {
        _scroll.jumpTo(target);
      }
      _saveSessionScrollSnapshot();
    });
  }

  bool get _hasTranscriptPointerDown => _transcriptPointersDown.isNotEmpty;

  bool get _initialTranscriptPositioningAborted =>
      _initialTranscriptPositionCancelled ||
      _hasTranscriptPointerDown ||
      _transcriptViewportClaimedByUser;

  void _onTranscriptPointerDown(PointerDownEvent event) {
    _transcriptPointersDown.add(event.pointer);
    ++_transcriptGestureGeneration;
    if (!_initialTranscriptReady) {
      _initialTranscriptPositionCancelled = true;
      // Let the first real drag claim the viewport immediately, even if the
      // opening unread correction has not completed its first frame yet.
      _initialTranscriptReady = true;
    }
    // A delayed message jump must never win back the viewport after the user
    // has touched the transcript. Clear the target before any subsequent
    // history/layout await can reuse its key.
    if (_scrollTargetId != null) {
      setState(_invalidateScrollNavigation);
    } else {
      _invalidateScrollNavigation();
    }
    _cancelSessionReopenNavigation();
    _cancelSessionScrollAnchorMaintenance();
    _maintainRestoredBottom = false;
    // A hold cancels an in-flight driven scroll immediately. It does not claim
    // the viewport permanently unless it becomes an actual drag.
    _cancelBottomFollow();
    _stopActiveTranscriptScroll();
    ++_shortTranscriptFillGeneration;
  }

  void _onTranscriptPointerEnd(PointerEvent event) {
    _transcriptPointersDown.remove(event.pointer);
    _scheduleLoadedOlderReveal();
    _scheduleShortFirstContactReveal();
    _scheduleShortTranscriptFill();
    _scheduleSessionScrollAnchorMaintenance();
    _scheduleRestoredBottomCorrection();
    if (!_hasTranscriptPointerDown && _isAtLoadedBottom(1)) {
      _transcriptViewportClaimedByUser = false;
    }
    if (!_hasTranscriptPointerDown) _drainReturnToLatestIntent();
  }

  void _claimTranscriptViewport() {
    ++_transcriptGestureGeneration;
    if (_scrollTargetId != null) {
      setState(_invalidateScrollNavigation);
    } else {
      _invalidateScrollNavigation();
    }
    _cancelSessionReopenNavigation(userClaimedViewport: true);
    _cancelBottomFollow();
    _returnToLatestCoordinator.cancelForUserDrag();
    ++_shortTranscriptFillGeneration;
    _transcriptViewportClaimedByUser = true;
    _showingFullyVisibleFirstContactHistory = false;
    _maintainSessionScrollAnchor = false;
    _maintainRestoredBottom = false;
    // Do not freeze a thin after-center arm: that parks older history above the
    // center while the open animation / first touch is still settling.
    if (shouldFreezeTranscriptPivot(
      latestArmIsShort: _isTranscriptShort(),
      canLoadOlder: _vm.canLoadOlder,
    )) {
      _transcriptPivotFrozen = true;
    }
  }

  void _stopActiveTranscriptScroll() {
    if (!_scroll.hasClients || !_scroll.position.isScrollingNotifier.value) {
      return;
    }
    _scroll.jumpTo(_scroll.position.pixels);
  }

  void _saveSessionScrollSnapshot({bool captureAnchor = true}) {
    if (!_didInitialScroll ||
        !_initialTranscriptReady ||
        !shouldSaveChatSessionScrollSnapshot(
          sessionReopenPending: _sessionReopenPending,
          preservingSnapshotAfterFailedJump:
              _preserveSnapshotAfterFailedSessionJump,
        ) ||
        _maintainSessionScrollAnchor ||
        !_scroll.hasClients) {
      return;
    }
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return;
    final wasAtLoadedBottom = isChatSessionAtLoadedBottom(
      anchoredHistory: _vm.anchoredHistory,
      distanceToLoadedBottom: (_loadedBottomOffset - pos.pixels).abs(),
    );
    final anchor = wasAtLoadedBottom || !captureAnchor
        ? null
        : _captureSessionScrollAnchor();
    _sessionScrollSnapshots[_sessionKey] = _ChatScrollSnapshot(
      pixels: clampScrollOffset(pos, pos.pixels),
      wasAtLoadedBottom: wasAtLoadedBottom,
      knownLatestMessageId: math.max(
        _vm.knownLatestMessageId,
        _latestServerMessage(_vm.messages)?.id ?? 0,
      ),
      pivotMessageId: _transcriptPivot?.cutoffMessageId,
      anchorMessageId: anchor?.messageId,
      anchorViewportOffset: anchor?.viewportOffset,
    );
  }

  bool get _sessionReopenPending =>
      !_sessionReopenDispositionResolved ||
      _sessionReopenResolutionInFlight ||
      _prioritizingSessionUnread;

  void _cancelSessionReopenNavigation({bool userClaimedViewport = false}) {
    final wasPending = _sessionReopenPending;
    _sessionReopenNavigationGuard.cancel();
    _sessionReopenResolutionInFlight = false;
    _sessionReopenDispositionResolved = true;
    if (_prioritizingSessionUnread) {
      _prioritizingSessionUnread = false;
      _invalidateScrollNavigation();
    }
    if (userClaimedViewport) {
      _preserveSnapshotAfterFailedSessionJump = false;
    } else if (wasPending) {
      _preserveSnapshotAfterFailedSessionJump = true;
    }
  }

  void _prepareExitState() {
    if (_exitStatePrepared) return;
    _exitStatePrepared = true;
    final sessionReopenPending = _sessionReopenPending;
    _cancelSessionReopenNavigation();
    if (!sessionReopenPending && !_maintainSessionScrollAnchor) {
      _saveSessionScrollSnapshot();
    }
    _cacheCurrentTranscript(force: true);
    if (shouldMarkChatReadOnExit(
      isAtLoadedBottom: _isAtLoadedBottom(80),
      sessionReopenPending: sessionReopenPending,
      restoredPositionProtected: _restoredPositionGuard.blocksAutomaticReturn,
      preservesViewport: _autoScrollPolicy.preservesViewport,
      historyReachesLatest: _vm.historyReachesLatest,
    )) {
      unawaited(_vm.markLoadedMessagesRead());
    }
  }

  void _cacheCurrentTranscript({bool force = false}) {
    if (!_vm.initialLoaded || !_initialTranscriptReady) return;
    final olderHistoryExhausted =
        !_vm.hasOlderHistory || _olderHistoryExhaustedHint;
    if (!_sessionCacheWriteGate.shouldStore(
      messages: _vm.messages,
      anchoredHistory: _vm.anchoredHistory,
      olderHistoryExhausted: olderHistoryExhausted,
      firstContactInfo: _vm.firstContactInfo,
      force: force,
    )) {
      return;
    }
    _sessionCache.store(
      accountSlot: _sessionKey.accountSlot,
      chatId: widget.chatId,
      messages: _vm.messages,
      anchoredHistory: _vm.anchoredHistory,
      olderHistoryExhausted: olderHistoryExhausted,
      firstContactInfo: _vm.firstContactInfo,
    );
  }

  void _handleBack() {
    _prepareExitState();
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
    } else {
      Navigator.of(context).pop();
    }
  }

  Widget _withExitState(Widget child) {
    return PopScope(
      // Back closes search before it closes the chat, so a hit list never
      // takes the whole conversation with it.
      canPop: !_search.isActive,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _prepareExitState();
          return;
        }
        if (_search.isActive) _closeSearch();
      },
      child: child,
    );
  }

  Widget _withBackSwipe(Widget child) {
    return FullPageBackSwipe(
      enabled: _canBackSwipe,
      onBack: () => unawaited(_popFromBackSwipe()),
      beforeRoutePop: _prepareExitState,
      child: child,
    );
  }

  ({int messageId, double viewportOffset})? _captureSessionScrollAnchor() {
    final viewportContext = _transcriptViewportKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.attached) {
      return null;
    }
    // Viewport-local coordinates: the offset is already relative to the
    // viewport top, and stopping the transform walk at the viewport avoids the
    // full ancestor chain per row.
    final viewportBottom = viewportRenderObject.size.height;
    int? visibleAnchorMessageId;
    double? visibleAnchorTop;
    int? partialAnchorMessageId;
    double? partialAnchorTop;
    for (final entry in _trackedTranscriptEntries.entries) {
      final itemContext = _entryVisibilityKeys[entry.key]?.currentContext;
      final itemRenderObject = itemContext?.findRenderObject();
      if (itemRenderObject is! RenderBox || !itemRenderObject.attached) {
        continue;
      }
      final itemTop = itemRenderObject
          .localToGlobal(Offset.zero, ancestor: viewportRenderObject)
          .dy;
      final itemBottom = itemTop + itemRenderObject.size.height;
      if (itemBottom <= 0 || itemTop >= viewportBottom) continue;
      if (itemTop >= 0) {
        if (visibleAnchorTop == null || itemTop < visibleAnchorTop) {
          visibleAnchorMessageId = entry.key;
          visibleAnchorTop = itemTop;
        }
      } else if (partialAnchorTop == null || itemTop > partialAnchorTop) {
        partialAnchorMessageId = entry.key;
        partialAnchorTop = itemTop;
      }
    }
    final anchorMessageId = visibleAnchorMessageId ?? partialAnchorMessageId;
    final anchorTop = visibleAnchorTop ?? partialAnchorTop;
    if (anchorMessageId == null || anchorTop == null) return null;
    return (messageId: anchorMessageId, viewportOffset: anchorTop);
  }

  void _scheduleUnreadProgressUpdate() {
    if (_unreadProgressUpdateScheduled ||
        !_initialTranscriptReady ||
        !mounted) {
      return;
    }
    _unreadProgressUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unreadProgressUpdateScheduled = false;
      if (mounted) _updateUnreadProgressFromViewport();
    });
  }

  void _updateUnreadProgressFromViewport() {
    final viewportContext = _transcriptViewportKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.attached) {
      return;
    }
    // Measured in the viewport's own space: a root-relative localToGlobal walks
    // and multiplies the whole ancestor transform chain for every mounted row,
    // once per scroll frame.
    final viewportRect = Offset.zero & viewportRenderObject.size;
    var changed = false;
    final newlyVisible = <ChatMessage>[];

    for (final entry in _trackedTranscriptEntries.entries) {
      final itemContext = _entryVisibilityKeys[entry.key]?.currentContext;
      final itemRenderObject = itemContext?.findRenderObject();
      if (itemRenderObject is! RenderBox || !itemRenderObject.attached) {
        continue;
      }
      final itemOrigin = itemRenderObject.localToGlobal(
        Offset.zero,
        ancestor: viewportRenderObject,
      );
      final itemRect = itemOrigin & itemRenderObject.size;
      if (!itemRect.overlaps(viewportRect)) continue;

      for (final message in entry.value.messages) {
        if (message.isOutgoing || message.isService) continue;
        final observation = _unreadProgress.observeVisibleIncoming(
          messageId: message.id,
          initialUnread: _isEntryUnreadMessage(message.id),
        );
        if (observation.shouldReportViewed) {
          newlyVisible.add(message);
        }
        changed = observation.unreadCountChanged || changed;
      }
    }

    if (_showEntryUnreadBanner &&
        _unreadProgress.initialRemaining(entryUnreadCount: _entryUnreadCount) ==
            0) {
      _showEntryUnreadBanner = false;
      changed = true;
    }

    if (newlyVisible.isNotEmpty) {
      _vm.markVisibleMessagesViewed(newlyVisible);
    }

    if (changed && mounted) setState(() {});
  }

  bool _isNearBottom([double threshold = 160]) {
    if (!_scroll.hasClients) return true;
    final position = _scroll.position;
    if (_showingFullyVisibleFirstContactHistory &&
        (position.pixels - position.minScrollExtent).abs() <= 1) {
      return true;
    }
    return isNearLatest(position, threshold: threshold);
  }

  double get _loadedBottomOffset {
    final position = _scroll.position;
    return _showingFullyVisibleFirstContactHistory
        ? position.minScrollExtent
        : position.maxScrollExtent;
  }

  bool _isAtLoadedBottom([double threshold = 24]) {
    return !_vm.anchoredHistory && _isNearBottom(threshold);
  }

  void _clearBottomIndicatorsIfNeeded() {
    if (!_scroll.hasClients || !_isAtLoadedBottom()) return;
    var changed = false;
    if (_showJumpDown) {
      _showJumpDown = false;
      changed = true;
    }
    if (_liveNewMessageCount > 0) {
      _unreadProgress.clearLiveMessages();
      changed = true;
    }
    if (!_bannerDismissed) {
      if (!_showEntryUnreadBanner) {
        _bannerDismissed = true;
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  bool get _isUserScrolling =>
      _scroll.hasClients && _scroll.position.isScrollingNotifier.value;

  Future<void> _loadOlderFromScroll() async {
    if (_loadingOlderFromScroll ||
        _isFillingShortTranscript ||
        !_scroll.hasClients ||
        !_vm.canLoadOlder) {
      return;
    }
    _loadingOlderFromScroll = true;
    try {
      final loaded = await _vm.loadOlder();
      if (loaded) {
        _olderHistoryExhaustedHint = false;
      } else if (!_vm.hasOlderHistory) {
        _olderHistoryExhaustedHint = true;
      }
    } finally {
      _loadingOlderFromScroll = false;
    }
  }

  void _syncKeyboardInset(double inset) {
    if ((_keyboardInset - inset).abs() < 0.5) return;
    final wasNearBottom = _isNearBottom(260);
    final opening = inset > _keyboardInset;
    _keyboardInset = inset;
    if ((wasNearBottom || opening) &&
        !_autoScrollPolicy.preservesViewport &&
        _scrollTargetId == null) {
      _scheduleScrollToBottom(animated: false);
    }
    // The keyboard changes the viewport height without rebuilding the shell
    // any more, so the viewport-measuring sweeps _transcript() used to schedule
    // on every keyboard frame have to be asked for here instead.
    _scheduleTranscriptPivotFreeze();
    _scheduleUnreadProgressUpdate();
    _scheduleShortFirstContactReveal();
  }

  void _scheduleScrollToBottom({
    bool animated = true,
    bool userInitiated = false,
  }) {
    if (userInitiated) _transcriptViewportClaimedByUser = false;
    final generation = _bottomFollow.begin();
    _scheduledBottomGeneration = generation;
    if (_bottomScrollScheduled) {
      _scheduledBottomAnimated = _scheduledBottomAnimated && animated;
      return;
    }
    _bottomScrollScheduled = true;
    _scheduledBottomAnimated = animated;
    scheduleChatPostFrame(() {
      final shouldAnimate = _scheduledBottomAnimated;
      final scheduledGeneration = _scheduledBottomGeneration;
      _bottomScrollScheduled = false;
      _scheduledBottomAnimated = true;
      if (!_bottomFollow.isCurrent(scheduledGeneration)) return;
      if (!_canFollowLoadedBottom()) {
        _autoScrollPolicy.allowViewportPreservation();
        return;
      }
      // Re-measure after this frame's layout before choosing min (fully
      // visible first-contact history) versus max (the normal latest edge).
      // This prevents a stale min correction followed by a max correction.
      _positionShortFirstContactHistoryIfItFits(requireAtLatest: false);
      unawaited(
        _moveToLoadedBottom(animated: shouldAnimate).whenComplete(() {
          _scheduleBottomGeometryFollow(scheduledGeneration);
        }),
      );
    });
  }

  Future<void> _moveToLoadedBottom({required bool animated}) async {
    if (!_canFollowLoadedBottom()) return;
    _autoScrollPolicy.requestReturnToBottom();
    final target = _loadedBottomOffset;
    final delta = (target - _scroll.position.pixels).abs();
    if (delta <= 0.5) return;
    if (!animated || delta < 48) {
      _scroll.jumpTo(target);
      return;
    }
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    );
  }

  bool _canFollowLoadedBottom() =>
      mounted &&
      _scroll.hasClients &&
      !_hasTranscriptPointerDown &&
      !_transcriptViewportClaimedByUser &&
      !_vm.anchoredHistory &&
      !_autoScrollPolicy.preservesViewport &&
      _scrollTargetId == null;

  void _scheduleBottomGeometryFollow(
    int generation, {
    int remainingFrames = 12,
  }) {
    _bottomFollow.follow(
      generation: generation,
      remainingFrames: remainingFrames,
      schedulePostFrame: scheduleChatPostFrame,
      canFollow: _canFollowLoadedBottom,
      distanceToLatest: () =>
          (_loadedBottomOffset - _scroll.position.pixels).abs(),
      latestExtent: () => _loadedBottomOffset,
      correct: () => _scroll.jumpTo(_loadedBottomOffset),
      settled: () {
        _autoScrollPolicy.returnToBottom();
        _markReadAtBottomIfNeeded();
        _clearBottomIndicatorsIfNeeded();
        _saveSessionScrollSnapshot();
      },
      abandoned: _autoScrollPolicy.allowViewportPreservation,
    );
  }

  void _cancelBottomFollow() {
    _bottomFollow.cancel();
    _autoScrollPolicy.allowViewportPreservation();
  }

  bool get _showReturnToLatestProgress =>
      _returnToLatestCoordinator.showProgress;

  void _onReturnToLatestTapped() {
    _requestReturnToLatest(userInitiated: true);
  }

  void _onReturnToLatestCoordinatorChanged() {
    if (!mounted) return;
    final failure = _returnToLatestCoordinator.takeFailure();
    if (failure != null) {
      _autoScrollPolicy.allowViewportPreservation();
      if (failure.userInitiated) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
    setState(() {});
  }

  void _drainReturnToLatestIntent() {
    if (!mounted || !_scroll.hasClients) return;
    final intent = _returnToLatestCoordinator.takeReady(
      pointerDown: _hasTranscriptPointerDown,
    );
    if (intent == null) return;
    _cancelSessionScrollAnchorMaintenance();
    _stopActiveTranscriptScroll();
    _autoScrollPolicy.requestReturnToBottom();
    _setScrollTarget(null);
    if (intent.userInitiated || _liveNewMessageCount > 0) {
      setState(() {
        _unreadProgress.clearLiveMessages();
        _bannerDismissed = _vm.unreadCount <= 0;
      });
    }
    _transcriptViewportClaimedByUser = false;
    _scheduleScrollToBottom();
    _markReadAtBottomIfNeeded();
  }

  void _requestReturnToLatest({bool userInitiated = false}) {
    if (!userInitiated && _hasTranscriptPointerDown) return;
    if (userInitiated) {
      _transcriptViewportClaimedByUser = false;
      _cancelSessionReopenNavigation(userClaimedViewport: true);
      _restoredPositionGuard.cancel();
      _cancelSessionScrollAnchorMaintenance();
      _cancelBottomFollow();
      _stopActiveTranscriptScroll();
      _autoScrollPolicy.requestReturnToBottom();
    }
    _returnToLatestCoordinator.request(
      userInitiated
          ? ChatReturnToLatestSource.user
          : ChatReturnToLatestSource.automatic,
    );
  }

  void _requestAutomaticReturnToLatestIfNearLatest() {
    if (!shouldRequestAutomaticReturnToLatest(
      anchoredHistory: _vm.anchoredHistory,
      restoredPositionProtected: _restoredPositionGuard.blocksAutomaticReturn,
      pointerDown: _hasTranscriptPointerDown,
      hasScrollTarget: _scrollTargetId != null,
      hasScrollClients: _scroll.hasClients,
      isNearLatestEdge:
          _scroll.hasClients && isNearLatest(_scroll.position, threshold: 36),
    )) {
      return;
    }
    _requestReturnToLatest();
  }

  void _markReadAtBottomIfNeeded() {
    if (!shouldAllowAutomaticChatRead(
          sessionReopenPending: _sessionReopenPending,
          restoredPositionProtected:
              _restoredPositionGuard.blocksAutomaticReturn,
          preservesViewport: _autoScrollPolicy.preservesViewport,
          historyReachesLatest: _vm.historyReachesLatest,
        ) ||
        !_vm.initialLoaded ||
        _vm.messages.isEmpty ||
        _vm.anchoredHistory) {
      return;
    }
    unawaited(_vm.markLoadedMessagesRead());
  }

  void _onComposerMessageSent() {
    _cancelSessionScrollAnchorMaintenance();
    _maintainRestoredBottom = false;
    _autoScrollPolicy.noteMessageSent();
    _setScrollTarget(null);
    _unreadProgress.clearLiveMessages();
    _bannerDismissed = true;
    if (_vm.anchoredHistory) {
      _requestReturnToLatest(userInitiated: true);
      return;
    }
    _scheduleScrollToBottom(userInitiated: true);
  }

  void _onComposerPanelGeometryChanged() {
    final wasNearBottom = _isNearBottom(260);
    if (!_autoScrollPolicy.shouldFollowComposerPanelChange(
      wasNearBottom: wasNearBottom,
    )) {
      return;
    }
    _setScrollTarget(null);
    _scheduleScrollToBottom(animated: false);
  }

  void _onComposerMediaSendTapped() {
    _cancelSessionScrollAnchorMaintenance();
    _maintainRestoredBottom = false;
    _autoScrollPolicy.requestReturnToBottom();
    _setScrollTarget(null);
    if (_vm.anchoredHistory) {
      _requestReturnToLatest(userInitiated: true);
      return;
    }
    _scheduleScrollToBottom(animated: false, userInitiated: true);
  }

  void _playMusicMessage(ChatMessage message) {
    unawaited(
      MusicPlayerController.shared.playChat(
        message,
        widget.chatId,
        title: widget.title,
      ),
    );
  }

  void _sendCommand(String command) {
    if (!_vm.sendCommand(command)) return;
    _onComposerMessageSent();
  }

  void _sendKeyboardButtonText(String text) {
    if (!_vm.sendKeyboardButtonText(text)) return;
    _onComposerMessageSent();
  }

  void _sendBotStart() {
    if (!_vm.sendBotStart()) return;
    _onComposerMessageSent();
  }

  void _captureEntryUnreadState() {
    _entryUnreadCount = _vm.unreadCount;
    _entryLastReadInboxId = _vm.lastReadInboxId;
    _entryLatestMessageId = resolveCapturedEntryLatestMessageId(
      knownLatestMessageId: _vm.knownLatestMessageId,
      loadedLatestMessageId: _latestServerMessage(_vm.messages)?.id ?? 0,
    );
  }

  bool _isEntryUnreadMessage(int messageId) => isCapturedEntryUnreadMessage(
    messageId: messageId,
    lastReadInboxId: _entryLastReadInboxId,
    latestMessageId: _entryLatestMessageId,
  );

  int? _firstLoadedEntryUnreadMessageId() => firstUnreadMessageIdAfterBoundary(
    incomingMessageIds: _vm.messages
        .where(
          (message) =>
              !message.isOutgoing &&
              !message.isService &&
              _isEntryUnreadMessage(message.id),
        )
        .map((message) => message.id),
    lastReadInboxId: _entryLastReadInboxId,
  );

  /// Jump to the unread boundary captured when the chat opened. The live TDLib
  /// boundary may already point at the newest message after the chat is marked
  /// read, so it cannot be used to resolve this button later.
  Future<void> _jumpToFirstUnread() async {
    _claimTranscriptViewport();
    await _jumpToFirstUnreadImpl();
  }

  Future<bool> _jumpToFirstUnreadForSession(int generation) =>
      _jumpToFirstUnreadImpl(sessionReopenGeneration: generation);

  Future<bool> _jumpToFirstUnreadImpl({int? sessionReopenGeneration}) async {
    final gestureGeneration = _transcriptGestureGeneration;

    bool isCancelled() =>
        _transcriptGestureGeneration != gestureGeneration ||
        (sessionReopenGeneration != null &&
            !_sessionReopenNavigationGuard.isCurrent(sessionReopenGeneration));

    if (isCancelled()) return false;
    var targetMessageId = _entryFirstUnreadMessageId;
    final entryBoundaryId = _entryLastReadInboxId;
    _cancelSessionScrollAnchorMaintenance();
    _cancelBottomFollow();
    _autoScrollPolicy.noteUserScroll(
      towardOlderMessages: true,
      isAtBottom: false,
    );
    setState(() {
      _unreadProgress.clearLiveMessages();
      _showEntryUnreadBanner = false;
      _bannerDismissed = true;
    });

    if (targetMessageId == null && entryBoundaryId > 0) {
      setState(() => _setScrollTarget(entryBoundaryId));
      await _vm.loadAroundMessage(
        entryBoundaryId,
        scrollToTarget: false,
        isCancelled: isCancelled,
      );
      if (!mounted || isCancelled()) return false;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || isCancelled()) return false;
      targetMessageId = _firstLoadedEntryUnreadMessageId();
      if (targetMessageId == null &&
          _vm.messages.any((message) => message.id == entryBoundaryId)) {
        targetMessageId = entryBoundaryId;
      }
    }

    // With a zero boundary (for example, a never-opened channel), TDLib has no
    // concrete message to page around. Moving to the oldest loaded unread
    // message still gives the control a useful, deterministic upward action.
    targetMessageId ??= _firstLoadedEntryUnreadMessageId();
    if (targetMessageId == null) {
      if (_scrollTargetId != null) setState(() => _setScrollTarget(null));
      return false;
    }
    _entryFirstUnreadMessageId = targetMessageId;
    final didReachTarget = await _scrollToMessageAndReport(
      targetMessageId,
      alignment: _initialUnreadAlignment,
      forceAlignment: true,
      isCancelled: isCancelled,
    );
    return didReachTarget && !isCancelled();
  }

  void _scheduleSendFailureDialog(ChatSendFailure failure) {
    _sendFailureDialogVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _sendFailureDialogVisible = false;
        return;
      }
      unawaited(_showSendFailureDialog(failure));
    });
  }

  Future<void> _showSendFailureDialog(ChatSendFailure failure) async {
    final message = switch (failure.kind) {
      ChatSendFailureKind.paidMessageRequired
          when failure.paidMessageStarCount > 0 =>
        AppStrings.t(AppStringKeys.chatSendFailedPaidCount, {
          'value1': failure.paidMessageStarCount,
        }),
      ChatSendFailureKind.paidMessageRequired => AppStrings.t(
        AppStringKeys.chatSendFailedPaid,
      ),
      ChatSendFailureKind.insufficientStars => AppStrings.t(
        AppStringKeys.chatSendFailedInsufficientStars,
      ),
      ChatSendFailureKind.premiumRequired => AppStrings.t(
        AppStringKeys.chatSendFailedPremium,
      ),
      ChatSendFailureKind.mutualContactRequired => AppStrings.t(
        AppStringKeys.chatSendFailedMutualContact,
      ),
      ChatSendFailureKind.privacyRestricted => AppStrings.t(
        AppStringKeys.chatSendFailedPrivacy,
      ),
      ChatSendFailureKind.blocked => AppStrings.t(
        AppStringKeys.chatSendFailedBlocked,
      ),
      ChatSendFailureKind.chatPermissionDenied => AppStrings.t(
        AppStringKeys.chatSendFailedPermission,
      ),
      ChatSendFailureKind.recipientUnavailable => AppStrings.t(
        AppStringKeys.chatSendFailedUnavailable,
      ),
      ChatSendFailureKind.rateLimited => AppStrings.t(
        AppStringKeys.chatSendFailedRateLimited,
      ),
      ChatSendFailureKind.generic => AppStrings.t(
        AppStringKeys.chatSendFailedGeneric,
        {'value1': failure.technicalMessage},
      ),
    };
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStrings.t(AppStringKeys.confirmOk),
      barrierColor: Colors.black.withValues(alpha: 0.52),
      transitionDuration: AppMotion.duration(context, AppMotion.responsive),
      transitionBuilder: AppMotion.dialogTransition,
      pageBuilder: (dialogContext, _, _) => AppDialogSurface(
        title: AppStrings.t(AppStringKeys.chatSendFailedTitle),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyle.body(
            dialogContext.colors.textSecondary,
          ).copyWith(height: 1.4),
        ),
        actions: [
          AppDialogAction(
            label: AppStrings.t(AppStringKeys.confirmOk),
            primary: true,
            onTap: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _sendFailureDialogVisible = false;
    final nextFailure = _vm.consumeSendFailure();
    if (nextFailure != null) _scheduleSendFailureDialog(nextFailure);
  }

  void _resolveRestoredSessionEntry() {
    if (_sessionReopenDispositionResolved ||
        _sessionReopenResolutionInFlight ||
        !_vm.chatReadStateLoaded) {
      return;
    }
    final snapshot = _sessionScrollSnapshot;
    if (snapshot == null) {
      _sessionReopenDispositionResolved = true;
      return;
    }
    _sessionReopenResolutionInFlight = true;
    final generation = _sessionReopenNavigationGuard.begin();
    final readStateRevision = _vm.chatReadStateRevision;
    unawaited(
      _resolveRestoredSessionEntryAsync(
        snapshot: snapshot,
        generation: generation,
        readStateRevision: readStateRevision,
      ),
    );
  }

  Future<void> _resolveRestoredSessionEntryAsync({
    required _ChatScrollSnapshot snapshot,
    required int generation,
    required int readStateRevision,
  }) async {
    // TDLib can deliver updateNewMessage and the paired unread-count update as
    // separate events. Let the current event batch settle, then retry whenever
    // either boundary changes during the read-only confirmation probe.
    await Future<void>.delayed(Duration.zero);
    if (!mounted || !_sessionReopenNavigationGuard.isCurrent(generation)) {
      return;
    }
    if (_vm.chatReadStateRevision != readStateRevision) {
      _sessionReopenResolutionInFlight = false;
      _resolveRestoredSessionEntry();
      return;
    }
    final confirmedUnreadMessageId = await _vm
        .confirmedNewIncomingUnreadSinceSession(
          savedKnownLatestMessageId: snapshot.knownLatestMessageId,
          expectedReadStateRevision: readStateRevision,
        );
    if (!mounted || !_sessionReopenNavigationGuard.isCurrent(generation)) {
      return;
    }
    if (_vm.chatReadStateRevision != readStateRevision) {
      _sessionReopenResolutionInFlight = false;
      _resolveRestoredSessionEntry();
      return;
    }

    _sessionReopenResolutionInFlight = false;
    _sessionReopenDispositionResolved = true;
    final prioritizeUnread = shouldPrioritizeUnreadOnChatReopen(
      currentUnreadCount: _vm.unreadCount,
      currentLastReadInboxId: _vm.lastReadInboxId,
      savedAnchorMessageId: snapshot.anchorMessageId,
      hasConfirmedNewUnread: confirmedUnreadMessageId != null,
    );
    final disposition = resolveChatReopenDisposition(
      hasExplicitTarget: widget.initialMessageId != null,
      hasSavedPosition: true,
      prioritizeUnread: prioritizeUnread,
    );
    if (disposition != ChatReopenDisposition.firstUnread) return;

    _prioritizingSessionUnread = true;
    _maintainRestoredBottom = false;
    _restoredPositionGuard.cancel();
    _cancelSessionScrollAnchorMaintenance();
    _cancelBottomFollow();
    _stopActiveTranscriptScroll();
    _resetTranscriptPivot();
    _captureEntryUnreadState();
    _entryFirstUnreadMessageId = _entryLastReadInboxId == 0
        ? confirmedUnreadMessageId
        : _firstLoadedEntryUnreadMessageId();
    var jumped = false;
    try {
      jumped = await _jumpToFirstUnreadForSession(generation);
    } catch (_) {
      jumped = false;
    }
    if (!mounted || !_sessionReopenNavigationGuard.isCurrent(generation)) {
      return;
    }
    _prioritizingSessionUnread = false;
    if (jumped) {
      _preserveSnapshotAfterFailedSessionJump = false;
      _sessionScrollSnapshots.remove(_sessionKey);
      _saveSessionScrollSnapshot();
    } else {
      _preserveSnapshotAfterFailedSessionJump = true;
    }
  }

  void _onModel() {
    if (!mounted) return;
    _syncProtectedContentSelectionState();
    _reportChatKindIfReady();
    if (!_viewTickerEnabled) {
      _modelDirtyWhileInactive = true;
      return;
    }
    _modelDirtyWhileInactive = false;
    _scheduleHandoffRefresh();
    if (!_sendFailureDialogVisible) {
      final failure = _vm.consumeSendFailure();
      if (failure != null) _scheduleSendFailureDialog(failure);
    }
    _resolveRestoredSessionEntry();
    final olderLoadFinished = _wasLoadingOlder && !_vm.isLoadingOlder;
    _wasLoadingOlder = _vm.isLoadingOlder;
    final oldest = _oldestServerMessage(_vm.messages);
    final previousOldestId = _lastOldestMessageId;
    final prependedOlder =
        oldest != null &&
        previousOldestId != null &&
        oldest.id < previousOldestId;
    // _isTranscriptShort walks every cached entry; nothing below moves the
    // scroll position or the pivot, so one measurement serves all three tests.
    final latestArmIsShort = _isTranscriptShort();
    final hydratedShortTranscript = shouldRebaseForHydratedOlderPage(
      prependedOlder: prependedOlder,
      latestArmWasShort: latestArmIsShort,
      historyFillInFlight: _isFillingShortTranscript || _loadingOlderFromScroll,
      revealRequested: _revealLoadedOlderPage,
    );
    final followingLatest =
        !_autoScrollPolicy.preservesViewport &&
        !_maintainSessionScrollAnchor &&
        !_transcriptViewportClaimedByUser;
    final hasMessageOlderThanPivot =
        _transcriptPivot != null &&
        _vm.messages.any(
          (message) =>
              _transcriptOrderId(message) < _transcriptPivot!.cutoffMessageId,
        );
    final expandedInitialWindow = shouldRebaseForExpandedInitialWindow(
      transcriptChanged: !identical(_transcriptCacheMessages, _vm.messages),
      latestArmIsShort: latestArmIsShort,
      hasMessageOlderThanPivot: hasMessageOlderThanPivot,
      followingLatest: followingLatest,
      viewportClaimedByUser: _transcriptViewportClaimedByUser,
    );
    final parkedShortArm = shouldRebaseParkedShortTranscriptPivot(
      pivotCutoffMessageId: _transcriptPivot?.cutoffMessageId,
      latestArmIsShort: latestArmIsShort,
      hasMessageOlderThanPivot: hasMessageOlderThanPivot,
      followingLatest: followingLatest,
      viewportClaimedByUser: _transcriptViewportClaimedByUser,
    );
    final wasPinnedToLoadedBottom =
        _didInitialScroll &&
        !_hasTranscriptPointerDown &&
        !_isUserScrolling &&
        !_transcriptViewportClaimedByUser &&
        !_autoScrollPolicy.preservesViewport &&
        _scrollTargetId == null &&
        _isAtLoadedBottom(2);
    final historyWindowInvalidated =
        _historyWindowInvalidationRevision !=
        _vm.historyWindowInvalidationRevision;
    _historyWindowInvalidationRevision = _vm.historyWindowInvalidationRevision;
    if (_historyWindowRevision != _vm.historyWindowRevision) {
      _historyWindowRevision = _vm.historyWindowRevision;
      final preservesSavedCoordinate =
          shouldPreserveChatSessionAnchorAcrossWindowChange(
            anchorMaintenanceActive: _maintainSessionScrollAnchor,
            hasSavedPivot: _sessionScrollSnapshot?.pivotMessageId != null,
            historyWindowInvalidated: historyWindowInvalidated,
          );
      if (!preservesSavedCoordinate) {
        _cancelSessionScrollAnchorMaintenance();
        _cancelBottomFollow();
        _stopActiveTranscriptScroll();
        _resetTranscriptPivot();
      }
      if (historyWindowInvalidated) {
        _maintainRestoredBottom = false;
        _olderHistoryExhaustedHint = true;
        _transcriptViewportClaimedByUser = false;
        _showingFullyVisibleFirstContactHistory = false;
        _autoScrollPolicy.returnToBottom();
        _sessionScrollSnapshots.remove(_sessionKey);
      } else if (!preservesSavedCoordinate) {
        _olderHistoryExhaustedHint = false;
      }
    }
    // The server-message scan only matters for a pending cutoff; as an argument
    // it ran on every notification.
    if (_transcriptPivot?.cutoffMessageId == _pendingTranscriptOrderId &&
        shouldRebasePendingTranscriptPivot(
          pivot: _transcriptPivot,
          pendingOrderId: _pendingTranscriptOrderId,
          hasServerMessage: _vm.messages.any(
            (message) => !isPendingChatMessage(message) && message.id > 0,
          ),
        )) {
      _resetTranscriptPivot();
    }
    final shouldResetParkedPivot =
        parkedShortArm ||
        expandedInitialWindow ||
        hydratedShortTranscript ||
        (!_transcriptPivotFrozen &&
            _vm.initialLoaded &&
            !identical(_transcriptCacheMessages, _vm.messages));
    if (shouldResetParkedPivot) {
      // Cold local pages may be followed by a larger remote hydration. Until
      // the latest arm fills a viewport (or the user scrolls), let that fuller
      // initial window establish the fixed cutoff. Also unpark a frozen newest
      // pivot that already has older messages sitting in before-center.
      _resetTranscriptPivot();
    }
    final rebasedParkedShortArm = parkedShortArm || expandedInitialWindow;
    final liveIncomingMessageIds = _vm.consumeLiveIncomingMessageIds();
    final newest = _latestServerMessage(_vm.messages);
    final transcriptBoundaryChanged = chatTranscriptBoundaryChanged(
      previousCount: _lastCount,
      currentCount: _vm.messages.length,
      previousNewestMessageId: _lastNewestMessageId,
      currentNewestMessageId: newest?.id,
      previousOldestMessageId: _lastOldestMessageId,
      currentOldestMessageId: oldest?.id,
      hasBufferedLiveMessages: liveIncomingMessageIds.isNotEmpty,
    );
    if (transcriptBoundaryChanged) {
      final wasNearBottom = _isNearBottom(72);
      final previousNewestId = _lastNewestMessageId;
      final appendedNewest =
          newest != null &&
          newest.id != previousNewestId &&
          (newest.isOutgoing ||
              previousNewestId == null ||
              newest.id > previousNewestId);
      final appendedIncomingIds = appendedLiveIncomingMessageIds(
        previousNewestMessageId: previousNewestId,
        liveIncomingMessageIds: liveIncomingMessageIds,
        currentMessageIds: _vm.messages.map((message) => message.id),
      );
      if (prependedOlder && _revealLoadedOlderPage) {
        _revealLoadedOlderPage = false;
        if (_transcriptGestureGeneration ==
            _loadedOlderRevealGestureGeneration) {
          _loadedOlderRevealPending = true;
          _scheduleLoadedOlderReveal();
        }
      }
      _lastCount = _vm.messages.length;
      _lastNewestMessageId = newest?.id ?? _lastNewestMessageId;
      _lastOldestMessageId = oldest?.id ?? _lastOldestMessageId;
      final shouldAutoScroll =
          _didInitialScroll &&
          _scrollTargetId == null &&
          !_vm.anchoredHistory &&
          appendedNewest &&
          !_hasTranscriptPointerDown &&
          !_transcriptViewportClaimedByUser &&
          !_isUserScrolling &&
          _autoScrollPolicy.shouldFollowAppendedMessage(
            wasNearBottom: wasNearBottom,
          );
      if (shouldAutoScroll) {
        _unreadProgress.clearLiveMessages();
        _scheduleScrollToBottom(animated: newest.isOutgoing);
      } else if (_didInitialScroll &&
          appendedNewest &&
          appendedIncomingIds.isNotEmpty &&
          (_hasTranscriptPointerDown ||
              _isUserScrolling ||
              _autoScrollPolicy.preservesViewport ||
              !wasNearBottom ||
              !_isAtLoadedBottom(1))) {
        _unreadProgress.addLiveMessages(appendedIncomingIds);
        _bannerDismissed = false;
        _bannerTimer?.cancel();
        _bannerTimer = null;
      }
    }
    if (olderLoadFinished && _revealLoadedOlderPage) {
      _revealLoadedOlderPage = false;
    }
    final target = _vm.consumePendingScrollToId();
    if (target != null) {
      _setScrollTarget(target, forceNavigation: true);
      final navigationGeneration = _scrollTargetGeneration;
      if (_didInitialScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !_isCurrentScrollTarget(target, navigationGeneration)) {
            return;
          }
          unawaited(
            _ensureMessageVisible(
              target,
              navigationGeneration: navigationGeneration,
            ),
          );
        });
      }
    }
    // Telegram-style entry: once the initial history (incl. the unread
    // boundary) is loaded, jump to the first unread message — or stay at the
    // bottom when caught up. Runs exactly once per chat open.
    if (!_didInitialScroll && _vm.initialLoaded) {
      _captureEntryUnreadState();
      final firstEntryUnreadMessageId = _firstLoadedEntryUnreadMessageId();
      final loadedIncomingUnreadCount = _vm.messages
          .where(
            (message) =>
                !message.isOutgoing &&
                !message.isService &&
                _isEntryUnreadMessage(message.id),
          )
          .length;
      final entryBoundaryIsLoaded =
          _entryLastReadInboxId > 0 &&
          _vm.messages.isNotEmpty &&
          _vm.messages.first.id <= _entryLastReadInboxId;
      final entireUnreadRangeIsLoaded =
          _entryUnreadCount > 0 &&
          loadedIncomingUnreadCount >= _entryUnreadCount;
      _entryFirstUnreadMessageId =
          entryBoundaryIsLoaded || entireUnreadRangeIsLoaded
          ? firstEntryUnreadMessageId
          : null;
      _showEntryUnreadBanner = _openAtLatest && _entryUnreadCount > 0;
      _didInitialScroll = true;
      if (_vm.messages.isEmpty) {
        _initialTranscriptReady = true;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_completeInitialScroll());
        });
      }
    } else if (_vm.initialLoaded && _vm.messages.isNotEmpty) {
      _scheduleShortTranscriptFill();
    }
    // Keep the entry unread banner visible; only live-new-message banners
    // auto-hide after a short delay. (Each new live message cancels the
    // timer, so the countdown restarts from the latest arrival.)
    if (_liveNewMessageCount > 0 && _bannerTimer == null && !_bannerDismissed) {
      _bannerTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _bannerDismissed = true);
      });
    }
    if ((wasPinnedToLoadedBottom || rebasedParkedShortArm) &&
        !_transcriptViewportClaimedByUser &&
        !_bottomScrollScheduled) {
      _scheduleScrollToBottom(animated: false);
    }
    _scheduleChatLanguageDetection();
    _scheduleAutomaticTranslations();
    setState(() {});
    _cacheCurrentTranscript();
    _scheduleSessionScrollAnchorMaintenance();
    _scheduleRestoredBottomCorrection();
    _scheduleParkedShortTranscriptRepair();
  }

  void _reportChatKindIfReady() {
    final kind = _vm.chatKind;
    final callback = widget.onChatKindResolved;
    if (kind == null || callback == null || kind == _reportedChatKind) return;
    _reportedChatKind = kind;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _vm.chatKind != kind) return;
      widget.onChatKindResolved?.call(kind);
    });
  }

  bool _isCurrentScrollTarget(int messageId, int navigationGeneration) =>
      _scrollTargetId == messageId &&
      _scrollTargetGeneration == navigationGeneration;

  void _invalidateScrollNavigation() {
    if (_scrollTargetId != null) {
      _setScrollTarget(null);
    } else {
      ++_scrollTargetGeneration;
    }
  }

  void _setScrollTarget(int? messageId, {bool forceNavigation = false}) {
    if (forceNavigation || _scrollTargetId != messageId) {
      ++_scrollTargetGeneration;
    }
    if (messageId != null) {
      _restoredPositionGuard.cancel();
      _returnToLatestCoordinator.cancel();
      _maintainRestoredBottom = false;
      _cancelSessionScrollAnchorMaintenance();
      _cancelBottomFollow();
      _stopActiveTranscriptScroll();
    }
    _scrollTargetId = messageId;
  }

  void _cancelSessionScrollAnchorMaintenance() {
    _maintainSessionScrollAnchor = false;
  }

  void _scheduleRestoredBottomCorrection() {
    if (!_maintainRestoredBottom) return;
    if (_vm.anchoredHistory || _scrollTargetId != null) {
      _maintainRestoredBottom = false;
      return;
    }
    _restoredBottomCorrection.schedule(
      enabled: _maintainRestoredBottom,
      schedulePostFrame: (callback) {
        WidgetsBinding.instance.addPostFrameCallback((_) => callback());
      },
      canCorrect: () =>
          mounted &&
          _maintainRestoredBottom &&
          !_hasTranscriptPointerDown &&
          !_transcriptViewportClaimedByUser &&
          !_vm.anchoredHistory &&
          _scrollTargetId == null &&
          _scroll.hasClients,
      correct: _scrollToBottom,
    );
  }

  void _scheduleSessionScrollAnchorMaintenance() {
    if (!_maintainSessionScrollAnchor ||
        !_initialTranscriptReady ||
        _sessionAnchorMaintenanceScheduled) {
      return;
    }
    final snapshot = _sessionScrollSnapshot;
    if (snapshot == null) return;
    _sessionAnchorMaintenanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionAnchorMaintenanceScheduled = false;
      if (!mounted ||
          !_maintainSessionScrollAnchor ||
          !_scroll.hasClients ||
          _transcriptViewportClaimedByUser ||
          _scrollTargetId != null) {
        return;
      }
      if (_hasTranscriptPointerDown) return;
      _restoreSessionScrollAnchor(snapshot);
    });
  }

  int _firstUnreadIndex() => _vm.messages.indexWhere(
    (m) => !m.isOutgoing && !m.isService && m.id > _vm.lastReadInboxId,
  );

  /// One-time positioning when a chat opens. This must never block painting:
  /// a hidden transcript reads as a black screen in dark mode. We jump to the
  /// deterministic estimate immediately and then do one zero-duration correction
  /// after layout, without waiting to reveal the UI.
  Future<void> _completeInitialScroll() async {
    if (_shouldRestoreSessionScroll) {
      await _restoreSessionScrollPosition();
    } else {
      await _positionInitialTranscript();
    }
    if (!mounted) return;
    if (_initialTranscriptPositioningAborted) {
      setState(() => _initialTranscriptReady = true);
      return;
    }
    if (_repairParkedShortTranscriptPivot()) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (_initialTranscriptPositioningAborted) {
        setState(() => _initialTranscriptReady = true);
        return;
      }
      if (_canFollowLoadedBottom()) _scrollToBottom();
    }
    if (!mounted) return;
    setState(() => _initialTranscriptReady = true);
    _saveSessionScrollSnapshot();
    _scheduleShortTranscriptFill();
  }

  Future<void> _restoreSessionScrollPosition() async {
    final snapshot = _sessionScrollSnapshot;
    if (snapshot == null ||
        !_scroll.hasClients ||
        _initialTranscriptPositioningAborted) {
      return;
    }
    if (_hasSessionScrollAnchor) {
      final anchorMessageId = snapshot.anchorMessageId!;
      for (var attempt = 0; attempt < 4; attempt++) {
        if (_initialTranscriptPositioningAborted) return;
        if (_restoreSessionScrollAnchor(snapshot)) {
          await WidgetsBinding.instance.endOfFrame;
          if (mounted &&
              _scroll.hasClients &&
              !_initialTranscriptPositioningAborted) {
            _restoreSessionScrollAnchor(snapshot);
          }
          return;
        }
        final estimate = _estimateMessageOffset(anchorMessageId, 0);
        if (estimate != null) _scroll.jumpTo(estimate);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted ||
            !_scroll.hasClients ||
            _initialTranscriptPositioningAborted) {
          return;
        }
      }
      // A transcript can be evicted before its independently stored scroll
      // anchor. Raw pixels belong to that old centered window, so never apply
      // them to a new window (or one that no longer contains the anchor).
      final hasMatchingCachedWindow = _sessionRenderState != null;
      final anchorStillLoaded = _vm.messages.any(
        (message) => message.id == anchorMessageId,
      );
      if (!hasMatchingCachedWindow || !anchorStillLoaded) {
        await _invalidateSessionSnapshotAndPositionCold();
        return;
      }
    }
    if (_sessionRenderState == null) {
      await _invalidateSessionSnapshotAndPositionCold();
      return;
    }
    if (_initialTranscriptPositioningAborted) return;
    _jumpToSessionScrollSnapshot(snapshot);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !_scroll.hasClients ||
        _initialTranscriptPositioningAborted) {
      return;
    }

    var guard = 0;
    while (mounted &&
        _scroll.hasClients &&
        !_initialTranscriptPositioningAborted &&
        _vm.canLoadOlder &&
        snapshot.pixels + 24 < _scroll.position.minScrollExtent &&
        guard < 6) {
      final loaded = await _vm.loadOlderLocal();
      if (!loaded) break;
      await WidgetsBinding.instance.endOfFrame;
      if (_initialTranscriptPositioningAborted) return;
      guard++;
    }

    if (!mounted ||
        !_scroll.hasClients ||
        _initialTranscriptPositioningAborted) {
      return;
    }
    _jumpToSessionScrollSnapshot(snapshot);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted ||
        !_scroll.hasClients ||
        _initialTranscriptPositioningAborted) {
      return;
    }
    _jumpToSessionScrollSnapshot(snapshot);
    _saveSessionScrollSnapshot();
  }

  Future<void> _invalidateSessionSnapshotAndPositionCold() async {
    _sessionScrollSnapshots.remove(_sessionKey);
    _sessionScrollSnapshot = null;
    _cancelSessionReopenNavigation(userClaimedViewport: true);
    _maintainSessionScrollAnchor = false;
    _restoredPositionGuard.cancel();
    if (_openAtLatest) {
      _autoScrollPolicy.returnToBottom();
    } else {
      _autoScrollPolicy.allowViewportPreservation();
    }
    _resetTranscriptPivot();
    await _positionInitialTranscript();
  }

  bool _restoreSessionScrollAnchor(_ChatScrollSnapshot snapshot) {
    final messageId = snapshot.anchorMessageId;
    final desiredOffset = snapshot.anchorViewportOffset;
    if (messageId == null || desiredOffset == null || !_scroll.hasClients) {
      return false;
    }
    final viewportContext = _transcriptViewportKey.currentContext;
    final itemContext = _entryVisibilityKeys[messageId]?.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    final itemRenderObject = itemContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox ||
        !viewportRenderObject.attached ||
        itemRenderObject is! RenderBox ||
        !itemRenderObject.attached) {
      return false;
    }
    final viewportTop = viewportRenderObject.localToGlobal(Offset.zero).dy;
    final itemTop = itemRenderObject.localToGlobal(Offset.zero).dy;
    final position = _scroll.position;
    final target = correctedChatSessionScrollOffset(
      currentPixels: position.pixels,
      currentAnchorViewportOffset: itemTop - viewportTop,
      savedAnchorViewportOffset: desiredOffset,
      minScrollExtent: position.minScrollExtent,
      maxScrollExtent: position.maxScrollExtent,
    );
    _scroll.jumpTo(target);
    return true;
  }

  void _jumpToSessionScrollSnapshot(_ChatScrollSnapshot snapshot) {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final target = clampScrollOffset(pos, snapshot.pixels);
    _scroll.jumpTo(target);
  }

  Future<void> _positionInitialTranscript() async {
    if (!_scroll.hasClients || _initialTranscriptPositioningAborted) return;
    _jumpToInitialEstimate();
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          !_scroll.hasClients ||
          _initialTranscriptPositioningAborted) {
        return;
      }
      await _correctInitialPosition();
      if (_initialTranscriptPositioningAborted) return;
    }
  }

  void _jumpToInitialEstimate() {
    if (!_scroll.hasClients || _vm.messages.isEmpty) return;
    final position = _initialPositionEstimate();
    if (position == null) return;
    _scroll.jumpTo(position);
  }

  double? _initialPositionEstimate() {
    if (!_scroll.hasClients || _vm.messages.isEmpty) return null;
    final max = _scroll.position.maxScrollExtent;
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    final decision = resolveChatInitialViewportTarget(
      explicitMessageId: widget.initialMessageId,
      pendingMessageId: _scrollTargetId,
      openAtBottom: _shouldOpenAtBottom,
      anchoredHistory: _vm.anchoredHistory,
      unreadCount: _vm.unreadCount,
      firstUnreadMessageId: i < 0 ? null : _vm.messages[i].id,
      unreadBoundaryLoaded: boundaryLoaded,
      lastReadInboxId: _vm.lastReadInboxId,
    );
    return switch (decision.kind) {
      ChatInitialViewportTargetKind.message ||
      ChatInitialViewportTargetKind.readBoundary => () {
        final target = decision.messageId!;
        _setScrollTarget(target);
        return _estimateMessageOffset(target, _initialTargetAlignment);
      }(),
      ChatInitialViewportTargetKind.firstUnread => _estimateMessageOffset(
        decision.messageId!,
        _initialUnreadAlignment,
        beforeUnreadDivider: true,
      ),
      ChatInitialViewportTargetKind.loadedBottom => max,
      ChatInitialViewportTargetKind.preserveAnchoredHistory => null,
    };
  }

  Future<bool> _correctInitialPosition() async {
    if (!_scroll.hasClients || _initialTranscriptPositioningAborted) {
      return false;
    }
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    final decision = resolveChatInitialViewportTarget(
      explicitMessageId: widget.initialMessageId,
      pendingMessageId: _scrollTargetId,
      openAtBottom: _shouldOpenAtBottom,
      anchoredHistory: _vm.anchoredHistory,
      unreadCount: _vm.unreadCount,
      firstUnreadMessageId: i < 0 ? null : _vm.messages[i].id,
      unreadBoundaryLoaded: boundaryLoaded,
      lastReadInboxId: _vm.lastReadInboxId,
    );
    switch (decision.kind) {
      case ChatInitialViewportTargetKind.message:
      case ChatInitialViewportTargetKind.readBoundary:
        final target = decision.messageId!;
        _setScrollTarget(target);
        final corrected = await _ensureKeyVisible(
          _targetKey,
          alignment: _initialTargetAlignment,
        );
        if (_initialTranscriptPositioningAborted) return false;
        if (corrected && mounted && _scrollTargetId == target) {
          setState(() => _setScrollTarget(null));
        }
        return corrected;
      case ChatInitialViewportTargetKind.firstUnread:
        return _ensureKeyVisible(
          _unreadKey,
          alignment: _initialUnreadAlignment,
        );
      case ChatInitialViewportTargetKind.loadedBottom:
        _scrollToBottom();
        _markReadAtBottomIfNeeded();
        return true;
      case ChatInitialViewportTargetKind.preserveAnchoredHistory:
        return true;
    }
  }

  Future<bool> _ensureKeyVisible(
    GlobalKey key, {
    required double alignment,
  }) async {
    final ctx = key.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    await Scrollable.ensureVisible(ctx, alignment: alignment);
    return true;
  }

  double? _estimateMessageOffset(
    int messageId,
    double alignment, {
    bool beforeUnreadDivider = false,
  }) {
    final entries = _transcriptEntries(
      context.read<ThemeController>().groupImageMessages,
    );
    if (entries.isEmpty || !_scroll.hasClients) return null;
    _TranscriptEntry? targetEntry;
    for (final entry in entries) {
      if (entry.messages.any((message) => message.id == messageId)) {
        targetEntry = entry;
        break;
      }
    }
    if (targetEntry == null) return null;
    // The visibility retry loop calls this up to six times in a row, so it
    // reuses the partition and key indexes _transcript() already cached rather
    // than repartitioning the whole entry list and rescanning it per attempt.
    // `older` holds beforePivot reversed, which is why it is walked forwards.
    final List<_TranscriptEntry> older;
    final List<_TranscriptEntry> newer;
    final int olderIndex;
    final int newerIndex;
    if (identical(entries, _sliverCacheEntries) &&
        identical(_transcriptPivot, _sliverCachePivot) &&
        _sliverCacheInitialLoaded == _vm.initialLoaded &&
        _sliverCacheLeadingItemCount >= 0) {
      older = _sliverCacheOlderEntries!;
      newer = _sliverCacheNewerEntries!;
      olderIndex = _sliverCacheOlderIndexByKey![targetEntry.key] ?? -1;
      // The newer map is offset by the leading first-contact card, which is not
      // an entry.
      final mapped = olderIndex >= 0
          ? null
          : _sliverCacheNewerIndexByKey![targetEntry.key];
      newerIndex = mapped == null ? -1 : mapped - _sliverCacheLeadingItemCount;
    } else {
      final partition = _partitionTranscript(entries);
      older = partition.beforePivot.reversed.toList(growable: false);
      newer = partition.pivotAndAfter;
      olderIndex = older.indexOf(targetEntry);
      newerIndex = olderIndex >= 0 ? -1 : newer.indexOf(targetEntry);
    }
    final messages = _transcriptCacheMessages ?? _vm.messages;
    final position = _scroll.position;
    final viewport = _scroll.position.viewportDimension;

    if (olderIndex >= 0) {
      var targetTop = 0.0;
      for (var i = 0; i <= olderIndex; i++) {
        targetTop -= _estimatedEntryExtent(older[i]);
      }
      if (!beforeUnreadDivider &&
          _needsUnreadDivider(targetEntry.startIndex, messages: messages)) {
        targetTop += _estimatedUnreadDividerExtent;
      }
      return clampScrollOffset(position, targetTop - viewport * alignment);
    }

    var targetTop = 0.0;
    for (var i = 0; i < newerIndex; i++) {
      targetTop += _estimatedEntryExtent(newer[i]);
    }
    if (!beforeUnreadDivider &&
        _needsUnreadDivider(targetEntry.startIndex, messages: messages)) {
      targetTop += _estimatedUnreadDividerExtent;
    }
    return clampScrollOffset(position, targetTop - viewport * alignment);
  }

  static const _estimatedUnreadDividerExtent = 33.0;
  static const _estimatedSeparatorExtent = 34.0;

  double _estimatedEntryExtent(_TranscriptEntry entry) {
    var extent = 0.0;
    final messages = _transcriptCacheMessages ?? _vm.messages;
    if (_needsUnreadDivider(entry.startIndex, messages: messages)) {
      extent += _estimatedUnreadDividerExtent;
    }
    if (_needsSeparator(entry.startIndex, messages: messages)) {
      extent += _estimatedSeparatorExtent;
    }
    final first = entry.first;
    if (first.isService) return extent + 38;
    if (entry.isBlockedRun) {
      if (!_expandedBlockedRunIds.contains(entry.last.id)) return extent + 40;
      return extent +
          entry.messages.fold<double>(
            0,
            (sum, message) => sum + _estimatedMessageExtent(message),
          );
    }
    if (entry.isImageGroup) {
      return extent + _estimatedImageGroupExtent(entry);
    }
    if (entry.isDocumentGroup) {
      final hasCaption = entry.messages.any(
        (message) => message.text.trim().isNotEmpty,
      );
      return extent + entry.messages.length * 71 + (hasCaption ? 54 : 0) + 16;
    }
    return extent + _estimatedMessageExtent(first);
  }

  double _estimatedImageGroupExtent(_TranscriptEntry entry) {
    final width = MediaQuery.sizeOf(context).width;
    final maxWidth = _messageMediaMaxWidth(width);
    final layout = buildTelegramMediaAlbumLayout(
      items: [
        for (final message in entry.messages.take(9))
          MediaAlbumItem(
            width: message.imageWidth,
            height: message.imageHeight,
          ),
      ],
      maxWidth: maxWidth - 8,
      gap: 4,
      maxSingleHeight: 300,
      minRowHeight: 82,
      maxRowHeight: 230,
    );
    final hasCaption = entry.messages.any((m) => m.text.trim().isNotEmpty);
    return layout.height + (hasCaption ? 38 : 0) + 16;
  }

  double _estimatedMessageExtent(ChatMessage message) {
    if (message.animatedSticker != null || message.videoSticker != null) {
      return 180;
    }
    if (message.image != null || message.video != null) {
      final h = message.imageHeight ?? 180;
      final w = message.imageWidth ?? 180;
      final scaled = w <= 0 ? 180.0 : _messageMediaMaxWidth() * h / w;
      return scaled.clamp(120.0, 310.0) + 16;
    }
    if (message.document != null ||
        message.music != null ||
        message.voice != null ||
        message.location != null ||
        message.isCall) {
      return 78;
    }
    if (message.diceEmoji != null || message.stickerFileId != null) {
      return 94;
    }
    final text = message.text.trim();
    final width = MediaQuery.sizeOf(context).width;
    final charsPerLine = math.max(10, (width * 0.52 / 15).floor());
    final lines = text.isEmpty
        ? 1
        : (text.length / charsPerLine).ceil().clamp(1, 8);
    final sender = _vm.isGroup && !message.isOutgoing ? 18.0 : 0.0;
    final reply = message.replyToMessageId != null ? 42.0 : 0.0;
    final buttons = message.buttonRows.isNotEmpty
        ? message.buttonRows.length * 38.0
        : 0.0;
    return 30 + sender + reply + lines * 22.0 + buttons;
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _cancelSessionScrollAnchorMaintenance();
    _autoScrollPolicy.requestReturnToBottom();
    if (_positionShortFirstContactHistoryIfItFits(requireAtLatest: false)) {
      _autoScrollPolicy.returnToBottom();
      _markReadAtBottomIfNeeded();
      _clearBottomIndicatorsIfNeeded();
      return;
    }
    _showingFullyVisibleFirstContactHistory = false;
    final generation = _bottomFollow.begin();
    final position = _scroll.position;
    if ((_loadedBottomOffset - position.pixels).abs() > 0.5) {
      _scroll.jumpTo(_loadedBottomOffset);
    }
    _markReadAtBottomIfNeeded();
    _clearBottomIndicatorsIfNeeded();
    _scheduleBottomGeometryFollow(generation);
  }

  void _scheduleShortTranscriptFill() {
    if (_shortTranscriptFillScheduled || _isFillingShortTranscript) return;
    _shortTranscriptFillScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shortTranscriptFillScheduled = false;
      unawaited(_fillShortTranscript());
    });
  }

  void _scheduleParkedShortTranscriptRepair() {
    if (_parkedShortTranscriptRepairScheduled) return;
    _parkedShortTranscriptRepairScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _parkedShortTranscriptRepairScheduled = false;
      if (!mounted) return;
      if (!_repairParkedShortTranscriptPivot()) return;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _canFollowLoadedBottom()) _scrollToBottom();
      });
    });
  }

  /// Unparks a frozen newest (or newest-like) pivot when older messages are
  /// already in the model but only the after-center arm is visible.
  bool _repairParkedShortTranscriptPivot() {
    if (!mounted ||
        (_vm.anchoredHistory && !_isTranscriptShort()) ||
        _maintainSessionScrollAnchor ||
        _autoScrollPolicy.preservesViewport ||
        _scrollTargetId != null ||
        _initialTranscriptPositionCancelled ||
        _transcriptViewportClaimedByUser) {
      return false;
    }
    final pivot = _transcriptPivot;
    if (pivot == null) return false;
    final hasOlder = _vm.messages.any(
      (message) => _transcriptOrderId(message) < pivot.cutoffMessageId,
    );
    if (!shouldRebaseParkedShortTranscriptPivot(
      pivotCutoffMessageId: pivot.cutoffMessageId,
      latestArmIsShort: _isTranscriptShort(),
      hasMessageOlderThanPivot: hasOlder,
      followingLatest: true,
      hasExplicitMessageTarget: widget.initialMessageId != null,
      viewportClaimedByUser: _transcriptViewportClaimedByUser,
    )) {
      return false;
    }
    _resetTranscriptPivot();
    _transcriptCache = null;
    _transcriptCacheMessages = null;
    return true;
  }

  Future<void> _fillShortTranscript() async {
    if (!mounted ||
        !_scroll.hasClients ||
        !_vm.initialLoaded ||
        _initialTranscriptPositionCancelled) {
      return;
    }
    // Repair does not need another network page: history may already sit in
    // before-center under a frozen pivot.
    if (_repairParkedShortTranscriptPivot()) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _canFollowLoadedBottom()) _scrollToBottom();
    }
    if (!mounted ||
        !_scroll.hasClients ||
        (_vm.anchoredHistory && !_isTranscriptShort()) ||
        _maintainSessionScrollAnchor ||
        _autoScrollPolicy.preservesViewport ||
        _scrollTargetId != null ||
        _initialTranscriptPositionCancelled ||
        _transcriptViewportClaimedByUser ||
        !_vm.canLoadOlder) {
      return;
    }
    if (!_isTranscriptShort()) return;
    // A restored or touch-claimed freeze on a thin arm must not block fill;
    // otherwise older pages stay in the before-center sliver forever.
    if (_transcriptPivotFrozen) {
      if (!shouldFreezeTranscriptPivot(
        latestArmIsShort: true,
        canLoadOlder: _vm.canLoadOlder,
      )) {
        _transcriptPivotFrozen = false;
      } else {
        return;
      }
    }

    final generation = ++_shortTranscriptFillGeneration;
    _isFillingShortTranscript = true;
    var loadedAny = false;
    try {
      var guard = 0;
      while (_canContinueShortTranscriptFill(generation) &&
          _vm.canLoadOlder &&
          _isTranscriptShort() &&
          guard < 8) {
        final loaded = await _vm.loadOlder();
        if (!loaded) break;
        _olderHistoryExhaustedHint = false;
        loadedAny = true;
        if (!_canContinueShortTranscriptFill(generation)) break;
        await WidgetsBinding.instance.endOfFrame;
        if (!_canContinueShortTranscriptFill(generation)) break;
        guard++;
      }
    } finally {
      _isFillingShortTranscript = false;
    }
    if (!_vm.hasOlderHistory) _olderHistoryExhaustedHint = true;
    if (_repairParkedShortTranscriptPivot()) {
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _canFollowLoadedBottom()) {
        _scrollToBottom();
        return;
      }
    }
    if (_canContinueShortTranscriptFill(generation)) {
      if (loadedAny) await _positionAfterShortFill(generation);
      // An empty older page flips canLoadOlder without a model notification.
      // Re-evaluate the first-contact card now that history is known complete.
      _scheduleShortFirstContactReveal();
    }
    if (_revealLoadedOlderPage && _vm.canLoadOlder) {
      unawaited(_loadOlderFromScroll());
    }
  }

  bool _canContinueShortTranscriptFill(int generation) {
    return mounted &&
        generation == _shortTranscriptFillGeneration &&
        _scroll.hasClients &&
        !_hasTranscriptPointerDown &&
        !_initialTranscriptPositionCancelled &&
        !_transcriptViewportClaimedByUser &&
        !(_vm.anchoredHistory && !_isTranscriptShort()) &&
        !_maintainSessionScrollAnchor &&
        !_autoScrollPolicy.preservesViewport &&
        _scrollTargetId == null &&
        (!_transcriptPivotFrozen || _isTranscriptShort());
  }

  bool _isTranscriptShort() {
    if (!_scroll.hasClients) return true;
    // With a center sliver, only the after-center arm defines the latest edge.
    // A large negative min extent says nothing about whether that arm fills
    // the viewport.
    return isLatestTranscriptArmShort(
      maxScrollExtent: _scroll.position.maxScrollExtent,
      afterCenterEntryCount: _latestArmEntryCount(),
    );
  }

  int _latestArmEntryCount() {
    final entries = _transcriptCache;
    if (entries == null || entries.isEmpty) {
      return _vm.messages.isEmpty ? 0 : _vm.messages.length;
    }
    final pivot = _transcriptPivot;
    if (pivot == null) return entries.length;
    var count = 0;
    for (final entry in entries) {
      final belongsToLatestArm = entry.messages.any(
        (message) => _transcriptOrderId(message) >= pivot.cutoffMessageId,
      );
      if (belongsToLatestArm) count++;
    }
    return count;
  }

  Future<void> _positionAfterShortFill(int generation) async {
    if (!_canContinueShortTranscriptFill(generation)) return;
    if (_shouldOpenAtBottom) {
      _scrollToBottom();
      return;
    }
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    if (_vm.unreadCount > 0 && i >= 0 && boundaryLoaded) {
      final ctx = _unreadKey.currentContext;
      if (ctx != null) {
        await Scrollable.ensureVisible(ctx, alignment: 0.12);
        if (!_canContinueShortTranscriptFill(generation)) return;
        return;
      }
    }
    if (_canContinueShortTranscriptFill(generation)) _scrollToBottom();
  }

  bool _isUnreadBoundaryLoaded() {
    if (_vm.messages.isEmpty) return false;
    return _vm.lastReadInboxId <= 0 ||
        _vm.messages.first.id <= _vm.lastReadInboxId;
  }

  bool get _canBackSwipe =>
      widget.showBackButton &&
      !_isSelecting &&
      !_search.isActive &&
      _actionTarget == null;

  Future<void> _popFromBackSwipe() async {
    if (_backSwipePopping || !mounted) return;
    _backSwipePopping = true;
    try {
      _prepareExitState();
      final onBack = widget.onBack;
      if (onBack != null) {
        onBack();
      } else {
        await Navigator.of(context).maybePop();
      }
    } finally {
      _backSwipePopping = false;
    }
  }

  bool get _isSelecting => _selectionAnchorId != null;

  void _enterSelection(ChatMessage message) {
    setState(() {
      _actionTarget = null;
      _actionRect = null;
      _clearMobileTextSelectionState();
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
      _selectionAnchorId = message.id;
      _selectedMessageIds
        ..clear()
        ..add(message.id);
      _selectionScrollingUp = false;
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionAnchorId = null;
      _selectedMessageIds.clear();
    });
  }

  void _toggleSelection(Iterable<ChatMessage> messages) {
    final ids = messages.where((m) => !m.isService).map((m) => m.id).toList();
    if (ids.isEmpty) return;
    setState(() {
      final allSelected = ids.every(_selectedMessageIds.contains);
      if (allSelected) {
        _selectedMessageIds.removeAll(ids);
      } else {
        _selectedMessageIds.addAll(ids);
      }
      if (_selectedMessageIds.isEmpty) _selectionAnchorId = null;
    });
  }

  List<int> _orderedSelectedIds() => _vm.messages
      .where((m) => _selectedMessageIds.contains(m.id))
      .map((m) => m.id)
      .toList();

  int _approxVisibleMessageIndex({required bool topEdge}) {
    if (!_scroll.hasClients || _vm.messages.isEmpty) return 0;
    final pos = _scroll.position;
    final viewportContext = _transcriptViewportKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is RenderBox && viewportRenderObject.attached) {
      // Viewport-local coordinates keep the transform walk off the ancestor
      // chain above the scrollable.
      final viewportBottom = viewportRenderObject.size.height;
      var bestDistance = double.infinity;
      int? bestIndex;
      for (final trackedEntry in _trackedTranscriptEntries.entries) {
        final itemContext =
            _entryVisibilityKeys[trackedEntry.key]?.currentContext;
        final itemRenderObject = itemContext?.findRenderObject();
        if (itemRenderObject is! RenderBox || !itemRenderObject.attached) {
          continue;
        }
        final itemTop = itemRenderObject
            .localToGlobal(Offset.zero, ancestor: viewportRenderObject)
            .dy;
        final itemBottom = itemTop + itemRenderObject.size.height;
        if (itemBottom <= 0 || itemTop >= viewportBottom) continue;
        final distance = topEdge
            ? (itemTop <= 0 ? 0.0 : itemTop)
            : (itemBottom >= viewportBottom
                  ? 0.0
                  : viewportBottom - itemBottom);
        if (distance >= bestDistance) continue;
        bestDistance = distance;
        final entry = trackedEntry.value;
        bestIndex = topEdge
            ? entry.startIndex
            : entry.startIndex + entry.messages.length - 1;
      }
      if (bestIndex != null) {
        return bestIndex.clamp(0, _vm.messages.length - 1);
      }
    }

    final viewport = math.max(pos.viewportDimension, 1.0);
    final edgeOffset = topEdge ? pos.pixels : pos.pixels + viewport;
    final frac = scrollFraction(pos, offset: edgeOffset);
    return (frac * (_vm.messages.length - 1)).round().clamp(
      0,
      _vm.messages.length - 1,
    );
  }

  void _selectToVisibleEdge() {
    final anchorId = _selectionAnchorId;
    if (anchorId == null || _vm.messages.isEmpty) return;
    final anchorIndex = _vm.messages.indexWhere((m) => m.id == anchorId);
    if (anchorIndex < 0) return;
    final edgeIndex = _approxVisibleMessageIndex(
      topEdge: _selectionScrollingUp,
    );
    final start = math.min(anchorIndex, edgeIndex);
    final end = math.max(anchorIndex, edgeIndex);
    setState(() {
      for (final message in _vm.messages.getRange(start, end + 1)) {
        if (!message.isService) _selectedMessageIds.add(message.id);
      }
    });
  }

  Future<void> _forwardSelected() async {
    final ids = _orderedSelectedIds();
    if (ids.isEmpty) return;
    if (!_vm.canForwardContent) {
      _showForwardFailure(const ForwardBlockedException());
      return;
    }
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: AppStringKeys.chatForwardToTitle,
          showForwardOptions: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final target = result.chat;
    try {
      await _vm.forwardMany(ids, target.id, options: result.forwardOptions);
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatMessagesForwardedCount, {
          'value1': ids.length,
        }),
      );
      _exitSelection();
    } catch (e) {
      if (!mounted) return;
      _showForwardFailure(e);
    }
  }

  Future<void> _saveSelected() async {
    final ids = _orderedSelectedIds();
    if (ids.isEmpty) return;
    if (!_vm.canForwardContent) {
      _showForwardFailure(const ForwardBlockedException());
      return;
    }
    try {
      await _vm.saveToFavoritesMany(ids);
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatMessagesSavedCount, {
          'value1': ids.length,
        }),
      );
      _exitSelection();
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatSaveFailed, {'value1': e}),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final ids = _orderedSelectedIds();
    if (ids.isEmpty) return;
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.chatDeleteMessagesQuestion,
      message: AppStrings.t(
        AppStringKeys.chatDeleteSelectedMessagesConfirmation,
        {'value1': ids.length},
      ),
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    try {
      await _vm.deleteMessages(ids);
      if (mounted) _exitSelection();
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatDeleteActionsFailed, {'value1': e}),
      );
    }
  }

  @override
  void dispose() {
    _prepareExitState();
    _detachExitController?.call();
    NotificationController.shared.unregisterVisibleChat(this);
    ActiveConversation.shared.unregister(this);
    _wallpaperController.removeListener(_onWallpaperChanged);
    _bannerTimer?.cancel();
    _readSyncTimer?.cancel();
    _handoffUpdateTimer?.cancel();
    _translation.removeListener(_onTranslationSettingsChanged);
    _ai?.removeListener(_onTranslationSettingsChanged);
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    _vm.removeListener(_onModel);
    _vm.onDisappear();
    _vm.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onWallpaperChanged() {
    if (mounted) setState(() {});
  }

  bool _needsUnreadDivider(int index, {List<ChatMessage>? messages}) {
    messages ??= _vm.messages;
    if (_vm.unreadCount <= 0) return false;
    if (index < 0 || index >= messages.length) return false;
    final m = messages[index];
    if (m.isOutgoing || m.isService || m.id <= _vm.lastReadInboxId) {
      return false;
    }
    if (index == 0) return true;
    return messages[index - 1].id <= _vm.lastReadInboxId;
  }

  Widget _unreadDivider() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.divider, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              AppStringKeys.chatNewMessagesDivider.l10n(context),
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
          ),
          Expanded(child: Divider(color: c.divider, height: 1)),
        ],
      ),
    );
  }

  Widget _blockedMessagePlaceholder(
    BuildContext context,
    _TranscriptEntry entry,
  ) {
    final c = context.colors;
    final runId = entry.last.id;
    if (_expandedBlockedRunIds.contains(runId)) {
      return _selectionEntry(
        entry,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < entry.messages.length; i++)
              _messageBubble(entry.messages[i], entry.startIndex + i),
          ],
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        key: ValueKey('blocked-message-run-$runId'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expandedBlockedRunIds.add(runId)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 28, 4),
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 32),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: c.divider.withValues(alpha: 0.55),
                width: 0.5,
              ),
            ),
            child: Text(
              '\u00B7 \u00B7 \u00B7',
              style: TextStyle(fontSize: 16, height: 1, color: c.textSecondary),
            ),
          ),
        ),
      ),
    );
  }

  Widget _messageBubble(
    ChatMessage message,
    int messageIndex, {
    List<ChatMessage> groupedMedia = const <ChatMessage>[],
    int? targetMediaMessageId,
    GlobalKey? targetMediaKey,
  }) {
    if (groupedMedia.isEmpty) {
      _vm.ensureMessageCapabilities(message);
    } else {
      for (final member in groupedMedia) {
        _vm.ensureMessageCapabilities(member);
      }
    }
    final mobileSelectionKey =
        !_vm.hasProtectedContent && _mobileTextSelectionMessageId == message.id
        ? _mobileTextSelectionAreaKey
        : null;
    return MessageBubble(
      message: message,
      selected: _selectedMessageIds.contains(message.id),
      groupedMedia: groupedMedia,
      targetMediaMessageId: targetMediaMessageId,
      targetMediaKey: targetMediaKey,
      translationDisplayStyle: _translation.displayStyle,
      showOriginalTranslationMessageIds: _showOriginalTranslationMessageIds,
      peerTitle: _vm.peerTitle,
      peerPhoto: _vm.peerPhoto,
      isGroup: _vm.isGroup,
      meName: _vm.meName,
      mePhoto: _vm.mePhoto,
      meId: _vm.meId,
      showRepeat: _vm.canForwardContent && _isRepeatTail(messageIndex),
      onRepeat: () => _vm.repeatMessage(message),
      onLongPress: _isSelecting ? null : _showActionMenuForMessage,
      mobileTextSelectionAreaKey: mobileSelectionKey,
      onMobileTextSelectionChanged: _handleMobileTextSelectionChanged,
      onMobileTextSelectionDisposed: mobileSelectionKey == null
          ? null
          : () => _handleMobileTextSelectionDisposed(
              message.id,
              mobileSelectionKey,
            ),
      onReply: (m) => _vm.setReply(m),
      onAvatarTap: _openSenderProfile,
      onAvatarLongPress: (m) {
        if (_vm.isGroup && (m.senderName?.isNotEmpty ?? false)) {
          _vm.insertMention(m);
        }
      },
      onOpenReply: _scrollToMessage,
      onOpenForwarded: _openForwardedMessage,
      onOpenComments: _openMessageComments,
      showCommentAttachment: chatTranscriptAllowsCommentAttachment(
        isChannel: _vm.isChannel,
      ),
      channelHasLinkedDiscussion: _vm.hasLinkedDiscussion,
      onOpenImage: _openImage,
      onOpenImageGallery: _openImageGallery,
      onApplyMessageBubble: offersMessageBubbleApplyAction(message)
          ? (message) => unawaited(
              applyMessageBubbleRepositoryPhoto(
                context,
                message,
                sourceMessageLink: messageBubbleRepositoryLink(message.id),
              ),
            )
          : null,
      onOpenSticker: _openSticker,
      onPlayVideo: _playVideo,
      onPlayMusic: _playMusicMessage,
      onButtonTap: _pressMessageButton,
      onBotCommandTap: _sendCommand,
      onHashtagTap: _openHashtagSearch,
      isRead: _vm.isRead(message),
      outgoingBubbleColor: _effectiveOutgoingColor(),
      outgoingBubbleTextColor: _effectiveOutgoingTextColor(),
      incomingBubbleColor: _effectiveIncomingColor(),
      incomingBubbleTextColor: _effectiveIncomingTextColor(),
      messageColors: _effectiveMessageColors(),
      hasCustomChatTheme: _hasCustomChatTheme,
      onToggleReaction: (r) => unawaited(_toggleMessageReaction(message, r)),
      onShowReactionUsers: _showReactionUsers,
      onRedial: _startCall,
      onOpenContact: _openSharedContact,
      onVotePoll: (message, optionIndex) =>
          unawaited(_votePoll(message, optionIndex)),
      onStopPoll: (message) => unawaited(_stopPoll(message)),
      onAddPollOption: (message) => unawaited(_addPollOption(message)),
      onShowPollResults: _showPollResults,
      onToggleChecklistTask: (message, task) =>
          unawaited(_toggleChecklistTask(message, task)),
      onAddChecklistTask: (message) => unawaited(_addChecklistTask(message)),
      onOpenStory: _openSharedStory,
      onTranscribeVoice:
          _vm.canUseSpeechRecognition && message.canRecognizeSpeech
          ? (message) => unawaited(_transcribeVoice(message))
          : null,
      onSummarizeMessage:
          _vm.canUseAiSummary && message.summaryLanguageCode.isNotEmpty
          ? (message) => unawaited(_summarizeMessage(message))
          : null,
    );
  }

  Future<void> _votePoll(ChatMessage message, int optionIndex) async {
    try {
      await _vm.votePoll(message, optionIndex);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<void> _transcribeVoice(ChatMessage message) async {
    try {
      await _vm.recognizeSpeech(message);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<void> _summarizeMessage(ChatMessage message) async {
    try {
      await _vm.summarizeMessage(message);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _stopPoll(ChatMessage message) async {
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.messagePollStop,
      message: AppStringKeys.messagePollStopConfirm,
      confirmText: AppStringKeys.messagePollStop,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _vm.stopPoll(message);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<void> _addPollOption(ChatMessage message) async {
    final value = await _promptChecklistTask(
      title: AppStrings.t(AppStringKeys.chatAddPollOption),
      hint: AppStrings.t(AppStringKeys.chatAddPollOptionHint),
    );
    if (value == null || value.trim().isEmpty || !mounted) return;
    try {
      await _vm.addPollOption(message, value);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  void _showPollResults(ChatMessage message) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PollResultsView(chatId: _vm.chatId, message: message),
      ),
    );
  }

  Future<void> _toggleChecklistTask(
    ChatMessage message,
    MessageChecklistTask task,
  ) async {
    try {
      await _vm.toggleChecklistTask(message, task);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<void> _addChecklistTask(ChatMessage message) async {
    final value = await _promptChecklistTask();
    if (value == null || value.trim().isEmpty || !mounted) return;
    try {
      await _vm.addChecklistTask(message, value);
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<String?> _promptChecklistTask({String? title, String? hint}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final c = context.colors;
          final canSubmit = controller.text.trim().isNotEmpty;
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              width: 360,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title ??
                        AppStringKeys.messageChecklistNewTask.l10n(context),
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 13),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 128,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      hintText:
                          hint ??
                          AppStringKeys.messageChecklistTaskHint.l10n(context),
                      filled: true,
                      fillColor: c.searchFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ChecklistDialogButton(
                        label: AppStringKeys.countryPickerCancel,
                        foreground: c.textSecondary,
                        onTap: () => Navigator.of(dialogContext).pop(),
                      ),
                      const SizedBox(width: 8),
                      _ChecklistDialogButton(
                        label: AppStringKeys.messageChecklistAdd,
                        foreground: c.onAccent,
                        fill: canSubmit ? AppTheme.brand : c.divider,
                        onTap: canSubmit
                            ? () => Navigator.of(
                                dialogContext,
                              ).pop(controller.text.trim())
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _openSharedContact(ChatMessage message) async {
    final contact = message.contact;
    if (contact == null) return;
    final action = await showSharedContactActions(
      context,
      contact,
      showCallAction: Theme.of(context).platform != TargetPlatform.macOS,
    );
    if (action == null || !mounted) return;
    switch (action) {
      case SharedContactAction.viewProfile:
        if (contact.userId > 0) {
          _openUserProfile(contact.userId, contact.displayName);
        }
      case SharedContactAction.message:
        if (contact.userId <= 0) return;
        try {
          final chat = await TdClient.shared.query({
            '@type': 'createPrivateChat',
            'user_id': contact.userId,
            'force': false,
          });
          final chatId = chat.int64('id');
          if (!mounted || chatId == null) return;
          await openChatFromCurrentWindow(
            context,
            chatId: chatId,
            title: contact.displayName,
          );
        } catch (_) {
          if (mounted) {
            showToast(context, AppStringKeys.topicPostContentActionFailed);
          }
        }
      case SharedContactAction.call:
        if (contact.userId > 0) {
          final started = context.read<CallManager>().startCall(
            contact.userId,
            false,
          );
          if (started != CallStartResult.started && mounted) {
            showToast(
              context,
              started == CallStartResult.unsupported
                  ? AppStringKeys.callsUnavailableOnDesktop
                  : AppStringKeys.callAlreadyInProgress,
            );
          }
        }
      case SharedContactAction.copyNumber:
        await Clipboard.setData(ClipboardData(text: contact.phoneNumber));
        if (mounted) showToast(context, AppStringKeys.topicPostContentCopied);
      case SharedContactAction.addContact:
        try {
          await TdClient.shared.query({
            '@type': 'addContact',
            'contact': {
              '@type': 'contact',
              'phone_number': contact.phoneNumber,
              'first_name': contact.firstName,
              'last_name': contact.lastName,
              'vcard': contact.vcard,
              'user_id': contact.userId,
            },
            'share_phone_number': false,
          });
          if (mounted) showToast(context, AppStringKeys.sharedContactAdded);
        } catch (_) {
          if (mounted) showToast(context, AppStringKeys.sharedContactAddFailed);
        }
    }
  }

  void _openSharedStory(ChatMessage message) {
    final story = message.story;
    if (story == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => StoryViewerView(
          chatId: story.posterChatId,
          storyIds: [story.storyId],
        ),
      ),
    );
  }

  bool _needsSeparator(int index, {List<ChatMessage>? messages}) {
    messages ??= _vm.messages;
    if (index < 0 || index >= messages.length) return false;
    if (index == 0) return true;
    return messages[index].date - messages[index - 1].date > _separatorGap;
  }

  bool _isRepeatTail(int index) {
    final messages = _vm.messages;
    if (index != messages.length - 1 || index == 0) return false;
    final a = messages[index], b = messages[index - 1];
    if (a.isService || b.isService) return false;
    // 复读 (+1) only echoes identical plain-text OR identical photos. Audio,
    // voice, location, stickers, polls, files, videos, contacts and call logs
    // are never repeatable — even when their placeholder text happens to match.
    if (a.isPlainText && b.isPlainText) {
      final ta = a.text.trim(), tb = b.text.trim();
      return ta.isNotEmpty && ta == tb;
    }
    if (a.isPhoto && b.isPhoto) {
      return a.image != null && b.image != null && a.image!.id == b.image!.id;
    }
    return false;
  }

  void _playVideo(ChatMessage message, {bool muted = false}) {
    if (message.video == null) return;
    final session = _videoSession(message);
    if (supportsDesktopVideoWindows) {
      unawaited(_openDesktopVideoWindow(session, muted: muted));
      return;
    }
    if (VideoSplitController.instance.isOpen) {
      VideoSplitController.instance.play(session);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => VideoOnDemandPlayerView(
          queue: session.queue,
          initialMuted: muted,
          onSwitchMode: (queue, mode) =>
              _switchVideoMode(routeContext, queue, mode),
        ),
      ),
    );
  }

  Future<void> _openDesktopVideoWindow(
    VideoSplitSession session, {
    required bool muted,
  }) async {
    final opened = await DesktopVideoWindowService.instance.open(
      session,
      muted: muted,
    );
    if (!opened && mounted) {
      showToast(context, AppStringKeys.videoPlayerLoadFailed);
    }
  }

  VideoSplitSession _videoSession(ChatMessage message) {
    final videoMessages = _vm.messages
        .where((candidate) => candidate.video != null)
        .toList();
    if (!videoMessages.any((candidate) => candidate.id == message.id)) {
      videoMessages.add(message);
    }
    final items = [
      for (final candidate in videoMessages)
        VideoPlaybackItem(
          video: candidate.video!,
          accountSlot: _sessionKey.accountSlot,
          thumb: candidate.image,
          width: candidate.imageWidth,
          height: candidate.imageHeight,
          durationSeconds: candidate.videoDuration,
          sourceChatId: widget.chatId,
          messageId: candidate.id,
          title: _videoPlaybackTitle(candidate),
        ),
    ];
    final index = videoMessages.indexWhere(
      (candidate) => candidate.id == message.id,
    );
    return VideoSplitSession.fromQueue(
      VideoPlaybackQueue(items: items, index: index < 0 ? 0 : index),
    );
  }

  String _videoPlaybackTitle(ChatMessage message) {
    final text = message.text.trim().replaceAll('\n', ' ');
    if (text.isEmpty || (text.startsWith('[') && text.endsWith(']'))) {
      return widget.title;
    }
    return text;
  }

  void _switchVideoMode(
    BuildContext routeContext,
    VideoPlaybackQueue queue,
    VideoDisplayMode mode,
  ) {
    final session = VideoSplitSession.fromQueue(queue);
    switch (mode) {
      case VideoDisplayMode.fullscreen:
        break;
      case VideoDisplayMode.pictureInPicture:
        // iOS has already handed the player to AVPictureInPictureController.
        // There is no app-level PiP overlay fallback.
        Navigator.of(routeContext).maybePop();
      case VideoDisplayMode.split:
        VideoSplitController.instance.play(session);
        Navigator.of(routeContext).maybePop();
    }
  }

  void _openImage(ChatMessage message) {
    final pairs = _vm.messages
        .where((m) => m.isPhoto && m.image != null)
        .toList();
    final items = pairs.map((m) => m.image!).toList();
    final start = pairs.indexWhere((m) => m.id == message.id);
    unawaited(
      openImagePreview(
        context,
        items: items,
        startIndex: start < 0 ? 0 : start,
      ),
    );
  }

  void _openImageGallery({
    required List<TdFileRef> items,
    required int startIndex,
  }) {
    unawaited(openImagePreview(context, items: items, startIndex: startIndex));
  }

  void _openSticker(ChatMessage message) {
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StickerViewer(
          message: message,
          onOpenSet: desktop ? _openStickerSet : null,
        ),
      ),
    );
  }

  void _openStickerSet(int setId) {
    if (isDesktopTargetPlatform(Theme.of(context).platform)) {
      setState(() => _desktopStickerSetId = setId);
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StickerSetDetailView(setId: setId)),
      ),
    );
  }

  Future<void> _openMessageComments(ChatMessage message) async {
    await showMessageRepliesSheet(
      context: context,
      chatId: widget.chatId,
      message: message,
      peerTitle: _vm.peerTitle,
      onAvatarTap: _openSenderProfile,
      onOpenReply: _scrollToMessage,
      onOpenImage: _openImage,
      onOpenSticker: _openSticker,
      onPlayVideo: _playVideo,
      onPlayMusic: _playMusicMessage,
      onButtonTap: _pressMessageButton,
      onBotCommandTap: _sendCommand,
      onHashtagTap: _openHashtagSearch,
      onViewInChat: _viewMessageRepliesInChat,
    );
  }

  Future<void> _openForwardedMessage(ChatMessage message) async {
    final chatId = message.forwardFromChatId;
    final messageId = message.forwardFromMessageId;
    if (chatId == null || chatId == 0 || messageId == null || messageId <= 0) {
      return;
    }
    if (chatId == widget.chatId) {
      await _scrollToMessage(messageId);
      return;
    }
    if (!mounted) return;
    await openChatFromCurrentWindow(
      context,
      chatId: chatId,
      title: message.forwardDisplayName,
      initialMessageId: messageId,
    );
  }

  Future<void> _viewMessageRepliesInChat(
    MessageRepliesViewTarget target,
  ) async {
    if (target.chatId == widget.chatId) {
      await _scrollToMessage(target.messageId);
      return;
    }
    if (!mounted) return;
    await openChatFromCurrentWindow(
      context,
      chatId: target.chatId,
      title: target.title,
      initialMessageId: target.messageId,
    );
  }

  /// Header-bar launcher for a bot's menu mini app (mirrors the composer's
  /// former pill action).
  Future<void> _openBotMenuApp(BotMenuInfo menu) async {
    final botUserId = _vm.peerUserId;
    if (botUserId == null) {
      if (!menu.isLegacyMenuUrl && menu.webAppUrl.isNotEmpty) {
        await openLink(context, menu.webAppUrl);
      }
      return;
    }
    final opened = await openTelegramMiniApp(
      context,
      chatId: _vm.chatId,
      botUserId: botUserId,
      url: menu.url,
      title: menu.actionTitle,
      menuWebApp: true,
    );
    if (!opened && mounted) {
      showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
    }
  }

  Future<void> _pressMessageButton(
    ChatMessage message,
    MessageButton button,
  ) async {
    final url = button.url;
    if (url != null && url.isNotEmpty) {
      if (button.isWebApp) {
        final botUserId = await _vm.webAppBotUserId(message);
        if (!mounted) return;
        if (botUserId != null) {
          final opened = await openTelegramMiniApp(
            context,
            chatId: _vm.chatId,
            botUserId: botUserId,
            url: url,
            title: button.text,
            keyboardButtonText: button.isReplyKeyboard ? button.text : null,
          );
          if (opened) return;
        }
        if (!mounted) return;
        showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
        return;
      }
      await openLink(context, url);
      return;
    }
    final userId = button.userId;
    if (userId != null && userId > 0) {
      await openLink(context, 'tg://user?id=$userId');
      return;
    }
    final copyText = button.copyText;
    if (copyText != null && copyText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: copyText));
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentCopied);
      }
      return;
    }
    if (button.isCallback) {
      try {
        final answer = await _vm.answerCallbackButton(message.id, button);
        if (!mounted) return;
        final answerUrl = answer.str('url');
        if (answerUrl != null && answerUrl.isNotEmpty) {
          await openLink(context, answerUrl);
          return;
        }
        final text = answer.str('text');
        if (text != null && text.isNotEmpty) {
          showToast(context, text);
        }
      } catch (e) {
        if (!mounted) return;
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
      return;
    }
    if (button.isReplyKeyboard && button.type == 'keyboardButtonTypeText') {
      _sendKeyboardButtonText(button.text);
      return;
    }
    if (button.switchInlineQuery != null) {
      showToast(context, AppStringKeys.chatInlineSwitchButtonUnsupported);
      return;
    }
    showToast(context, AppStringKeys.chatButtonUnsupported);
  }

  Future<void> _perform(MessageAction action, ChatMessage message) async {
    setState(() {
      _actionTarget = null;
      _actionRect = null;
      _clearMobileTextSelectionState();
      _actionSource = MessageActionSource.normal;
    });
    switch (action) {
      case MessageAction.copy:
        unawaited(Clipboard.setData(ClipboardData(text: message.text)));
      case MessageAction.edit:
        unawaited(_editMessage(message));
      case MessageAction.suggestOffer:
        unawaited(_offerSuggestedPost(message));
      case MessageAction.translate:
        unawaited(_translateMessage(message));
      case MessageAction.displayOriginal:
        setState(() => _showOriginalTranslationMessageIds.add(message.id));
      case MessageAction.displayTranslation:
        setState(() => _showOriginalTranslationMessageIds.remove(message.id));
      case MessageAction.reply:
        _vm.setReply(message);
      case MessageAction.replies:
        await _openMessageComments(message);
      case MessageAction.forward:
        unawaited(_forwardMessage(message));
      case MessageAction.repeat:
        try {
          final preserveSender = context
              .read<ThemeController>()
              .preserveSenderWhenRepeating;
          await _vm.forward(
            message.id,
            _vm.chatId,
            options: ForwardOptions(removeSender: !preserveSender),
          );
          if (!mounted) return;
          _scrollToBottom();
        } catch (e) {
          if (!mounted) return;
          _showForwardFailure(e);
        }
      case MessageAction.report:
        final confirmed = await confirmDialog(
          context,
          title: AppStringKeys.chatReportTitle,
          message: AppStringKeys.chatReportMessage,
          confirmText: AppStringKeys.chatReportConfirm,
          destructive: true,
        );
        if (!mounted || !confirmed) return;
        try {
          await _vm.reportMessage(message);
          if (!mounted) return;
          showToast(context, AppStringKeys.chatReportSent);
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatReportFailed, {'value1': e}),
          );
        }
      case MessageAction.block:
        final confirmed = await confirmDialog(
          context,
          title: AppStringKeys.chatBlockUserTitle,
          message: AppStringKeys.chatBlockUserMessage,
          confirmText: AppStringKeys.chatBlockUserConfirm,
          destructive: true,
        );
        if (!mounted || !confirmed) return;
        try {
          await _vm.blockAndReportSender(message);
          if (!mounted) return;
          showToast(context, AppStringKeys.chatBlockUserDone);
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatBlockUserFailed, {'value1': e}),
          );
        }
      case MessageAction.playMuted:
        _playVideo(message, muted: true);
      case MessageAction.addToPlaylist:
        unawaited(showMusicPlaylists(context, addMessage: message));
      case MessageAction.saveToPhotos:
        DateTime? progressShownAt;
        final progressTimer = Timer(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          progressShownAt = DateTime.now();
          showToast(
            context,
            AppStringKeys.chatSavingToPhotos,
            visibleFor: const Duration(milliseconds: 900),
          );
        });
        final result = await MediaLibrarySaver.save(message);
        progressTimer.cancel();
        if (!mounted) return;
        if (progressShownAt case final shownAt?) {
          final remaining =
              const Duration(milliseconds: 1400) -
              DateTime.now().difference(shownAt);
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
          if (!mounted) return;
        }
        showToast(context, switch (result) {
          MediaLibrarySaveResult.saved => AppStringKeys.chatSavedToPhotos,
          MediaLibrarySaveResult.permissionDenied =>
            AppStringKeys.chatSaveToPhotosPermissionDenied,
          MediaLibrarySaveResult.failed || MediaLibrarySaveResult.unsupported =>
            AppStringKeys.chatSaveToPhotosFailed,
        }, visibleFor: const Duration(seconds: 2));
      case MessageAction.multiSelect:
        _enterSelection(message);
      case MessageAction.pinTodo:
        try {
          await _vm.pinTodo(message);
          if (!mounted) return;
          showToastOverlay(
            Overlay.of(context),
            AppStrings.t(AppStringKeys.chatTodoSetSuccess),
          );
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatTodoSetFailed, {'value1': e}),
          );
        }
      case MessageAction.unpinTodo:
        try {
          await _vm.unpinTodo(message);
          if (!mounted) return;
          showToastOverlay(
            Overlay.of(context),
            AppStrings.t(AppStringKeys.chatTodoUnsetSuccess),
          );
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatTodoUnsetFailed, {'value1': e}),
          );
        }
      case MessageAction.save:
        try {
          await _vm.saveToFavorites(message.id);
          if (!mounted) return;
          showToast(context, AppStringKeys.chatSavedToSavedMessages);
        } catch (e) {
          if (!mounted) return;
          showToast(
            context,
            AppStrings.t(AppStringKeys.chatSaveFailed, {'value1': e}),
          );
        }
      case MessageAction.saveSticker:
        final id = message.stickerFileId ?? message.animatedSticker?.id;
        if (id != null) {
          _vm.saveFavoriteSticker(id);
          showToast(context, AppStringKeys.chatStickerAddSuccess);
        }
      case MessageAction.viewStickerSet:
        final sid = message.stickerSetId;
        if (sid != null) _openStickerSet(sid);
      case MessageAction.delete:
        await _performDeleteAction(message);
    }
  }

  Future<void> _offerSuggestedPost(ChatMessage message) async {
    final loader = ChannelDirectMessageTopicController(
      chatId: _vm.chatId,
      topicId: 0,
    );
    try {
      final properties = await TdClient.shared.query({
        '@type': 'getMessageProperties',
        'chat_id': _vm.chatId,
        'message_id': message.id,
      });
      if (properties.boolean('can_add_offer') != true &&
          properties.boolean('can_edit_suggested_post_info') != true) {
        if (mounted) {
          showToast(context, AppStringKeys.suggestedPostOfferUnavailable);
        }
        return;
      }
      final limits = await loader.loadLimits();
      if (!mounted) return;
      final draft = await showAppModalSheet<SuggestedPostDraft>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SuggestedPostComposerSheet(
          limits: limits,
          offerOnly: true,
          initialInfo: message.suggestedPostInfo,
        ),
      );
      if (draft == null || !mounted) return;
      await _vm.addSuggestedPostOffer(
        message.id,
        price: draft.price,
        sendDate: draft.sendDate,
      );
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      loader.dispose();
    }
  }

  Future<void> _performDeleteAction(ChatMessage message) async {
    final options = await _confirmMessageDeleteOptions(message);
    if (!mounted || options == null) return;
    try {
      if (options.reportSpam && !options.blockSender) {
        await _vm.reportMessage(message);
      }
      if (options.blockSender) {
        await _vm.blockAndReportSender(message);
      }
      if (options.deleteAllFromSender) {
        await _vm.deleteMessagesFromSender(message);
      } else if (options.deleteMessage) {
        await _vm.deleteMessage(message.id);
      }
      if (!mounted) return;
      showToast(context, AppStringKeys.chatDeleteActionsDone);
    } catch (e) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatDeleteActionsFailed, {'value1': e}),
      );
    }
  }

  Future<_MessageDeleteOptions?> _confirmMessageDeleteOptions(
    ChatMessage message,
  ) {
    final senderName = _deleteSenderName(message);
    return showGeneralDialog<_MessageDeleteOptions>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStrings.t(AppStringKeys.countryPickerCancel),
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) => _MessageDeleteOptionsDialog(
        canActOnSender: !message.isOutgoing && message.senderId != null,
        canDeleteAllFromSender:
            !message.isOutgoing &&
            message.senderId != null &&
            _vm.canDeleteMessagesBySender,
        senderName: senderName,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  String _deleteSenderName(ChatMessage message) {
    final name = (message.senderName ?? message.senderTitle ?? '').trim();
    if (name.isNotEmpty) return name;
    return AppStrings.t(AppStringKeys.topicChatUsers);
  }

  bool _isTelegramTranslationOption(String option) =>
      TranslationOptionIds.translationProvider(option) ==
      TranslationProvider.tdlib;

  Future<String> _translateTextWithGoogleCloud(
    String providerId, {
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) async {
    final provider = _translation.googleCloudProviderById(providerId);
    if (provider == null || !provider.hasApiKey) {
      throw TranslationApiException(
        AppStringKeys.translationAiProviderUnavailable.l10n(context),
      );
    }
    final apiKey = await _translation.googleCloudApiKeyForProvider(providerId);
    if (apiKey.isEmpty) {
      throw TranslationApiException(
        AppStrings.t(AppStringKeys.translationGoogleCloudApiKeyRequired),
      );
    }
    return ThirdPartyTranslationApi.translateGoogleCloud(
      text: text,
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
      apiKey: apiKey,
    );
  }

  Future<String> _translateTextWithOption(
    String option, {
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String> priorMessages = const [],
  }) {
    final googleCloudProviderId = TranslationOptionIds.googleCloudProviderId(
      option,
    );
    if (googleCloudProviderId != null) {
      return _translateTextWithGoogleCloud(
        googleCloudProviderId,
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );
    }
    final candidateId = TranslationOptionIds.aiCandidateId(option);
    if (candidateId != null) {
      final candidate = _ai?.modelCandidateByIdForFeature(
        AiFeature.translation,
        candidateId,
      );
      if (candidate == null) {
        throw TranslationApiException(
          AppStringKeys.translationAiProviderUnavailable.l10n(context),
        );
      }
      return _translateTextWithAi(
        candidate: candidate,
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        priorMessages: priorMessages,
      );
    }
    final provider = TranslationOptionIds.translationProvider(option);
    return switch (provider) {
      TranslationProvider.iosSystem ||
      TranslationProvider.androidMlKit => NativeTranslationApi.translate(
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      ),
      TranslationProvider.tdlib => _vm.translateText(text, targetLanguageCode),
      TranslationProvider.googleTranslate ||
      TranslationProvider.myMemory ||
      TranslationProvider.lingva ||
      TranslationProvider.libreTranslate => ThirdPartyTranslationApi.translate(
        provider: provider!,
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        lingvaEndpoint: _translation.lingvaEndpoint,
        libreTranslateEndpoint: _translation.libreTranslateEndpoint,
        libreTranslateApiKey: _translation.libreTranslateApiKey,
      ),
      null => throw TranslationApiException(
        AppStringKeys.translationAiProviderUnavailable.l10n(context),
      ),
    };
  }

  Future<void> _showReactionUsers(
    ChatMessage message,
    MessageReaction reaction,
  ) async {
    if (!mounted || message.reactions.isEmpty) return;
    await showReactionUsersModal<void>(
      context,
      builder: (dialogContext) => _ReactionUsersSheet(
        viewModel: _vm,
        message: message,
        initialReaction: reaction,
      ),
    );
  }

  Future<bool> _translateMessage(
    ChatMessage message, {
    bool showErrors = true,
    bool allowWhenManualTranslationDisabled = false,
    String sourceLanguageCode = 'autodetect',
  }) async {
    final translation = context.read<TranslationController>();
    if (!translation.enabled && !allowWhenManualTranslationDisabled) {
      return true;
    }
    final sourceText = _translationSourceText(message);
    if (sourceText.trim().isEmpty) return true;
    final targetLanguage = _translationTargetLanguage(translation);
    final noProviderMessage = AppStringKeys.translationAiProviderUnavailable
        .l10n(context);
    final ai = _ai;
    if (ai != null && !ai.initialized) {
      try {
        await ai.initialize();
      } catch (_) {
        // Keep the non-AI providers in the fallback chain available.
      }
    }
    final options = _effectiveTranslationOptions;
    if (options.isEmpty) return false;
    try {
      final cached = await translation.messageCache.resolve(
        MessageTranslationCacheKey(
          accountSlot: _sessionKey.accountSlot,
          chatId: widget.chatId,
          messageId: message.id,
          sourceText: sourceText,
          targetLanguageCode: targetLanguage,
        ),
        () async {
          Object? lastError;
          MessageTranslationResult? result;
          for (final option in options) {
            try {
              result = await _translateMessageWithOption(
                option,
                message: message,
                sourceText: sourceText,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguage,
              );
              break;
            } catch (error) {
              lastError = error;
              if (_isTelegramTranslationOption(option) &&
                  isTelegramTranslationRateLimit(error)) {
                translation.markTelegramTranslationUnavailable();
              }
            }
          }
          if (result == null) {
            throw lastError ?? TranslationApiException(noProviderMessage);
          }
          return MessageTranslationValue(
            text: result.text,
            entities: result.entities,
            languageCode: result.languageCode,
          );
        },
      );
      if (mounted) {
        _vm.restoreMessageTranslation(message.id, (
          text: cached.text,
          entities: cached.entities,
          languageCode: cached.languageCode,
        ));
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      if (showErrors) {
        showToast(
          context,
          _translationFailureMessage(e),
          visibleFor: isTelegramAiPremiumFlood(e)
              ? const Duration(seconds: 4)
              : const Duration(milliseconds: 1400),
        );
      }
      return false;
    }
  }

  Future<MessageTranslationResult> _translateMessageWithOption(
    String option, {
    required ChatMessage message,
    required String sourceText,
    required String sourceLanguageCode,
    required String targetLanguageCode,
  }) {
    if (_isTelegramTranslationOption(option)) {
      return _vm.translateMessage(message.id, targetLanguageCode);
    }
    final provider = TranslationOptionIds.translationProvider(option);
    return _vm.translateMessageExternally(
      message.id,
      targetLanguageCode,
      () => _translateTextWithOption(
        option,
        text: sourceText,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        priorMessages: _aiTranslationContextFor(message),
      ),
      showLoading:
          provider != TranslationProvider.iosSystem ||
          defaultTargetPlatform != TargetPlatform.iOS,
    );
  }

  String _translationFailureMessage(Object error) {
    if (isTelegramAiPremiumFlood(error)) {
      return '${AppStrings.t(AppStringKeys.telegramAiDailyLimitReached)}\n'
          '${AppStrings.t(AppStringKeys.telegramAiDailyLimitMessage)}';
    }
    return AppStrings.t(AppStringKeys.chatTranslateFailed, {'value1': error});
  }

  List<String> get _effectiveTranslationOptions =>
      effectiveTranslationOptionIds(
        translation: _translation,
        ai: _ai,
        nativeProviders: _nativeTranslationProviders,
        isBotApiAccount: _vm.isBotApiAccount,
      );

  bool get _hasAvailableTranslationOption =>
      _effectiveTranslationOptions.isNotEmpty;

  Future<void> _loadNativeTranslationProviders() async {
    final providers = await NativeTranslationApi.availableProviders();
    if (!mounted || setEquals(providers, _nativeTranslationProviders)) return;
    setState(() => _nativeTranslationProviders = providers);
    _scheduleChatLanguageDetection(force: true);
    _scheduleAutomaticTranslations();
  }

  int get _botApiWarningMask =>
      (_vm.showBotApiPrivacyWarning ? 1 : 0) |
      (_vm.showBotApiBotToBotWarning ? 2 : 0);

  String get _botApiWarningDismissalKey =>
      'mithka.botApiAccessWarningDismissed.v1.${_sessionKey.accountSlot}';

  bool get _showsBotApiAccessWarning {
    final mask = _botApiWarningMask;
    return mask != 0 && _dismissedBotApiWarningMask != mask;
  }

  Future<void> _loadBotApiWarningDismissal() async {
    final prefs = await SharedPreferences.getInstance();
    final mask = prefs.getInt(_botApiWarningDismissalKey);
    if (!mounted || mask == _dismissedBotApiWarningMask) return;
    setState(() => _dismissedBotApiWarningMask = mask);
  }

  void _dismissBotApiAccessWarning() {
    final mask = _botApiWarningMask;
    if (mask == 0) return;
    setState(() => _dismissedBotApiWarningMask = mask);
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setInt(_botApiWarningDismissalKey, mask),
      ),
    );
  }

  void _onTranslationSettingsChanged() {
    if (!mounted) return;
    if (_translation.displayStyle != TranslationDisplayStyle.translatedOnly) {
      _showOriginalTranslationMessageIds.clear();
    }
    _autoTranslationFailedMessageIds.clear();
    if (!_automaticTranslationEnabled && _autoTranslatedMessageIds.isNotEmpty) {
      _vm.clearTranslations(_autoTranslatedMessageIds);
      _autoTranslatedMessageIds.clear();
    }
    _scheduleChatLanguageDetection(force: true);
    _scheduleAutomaticTranslations();
    setState(() {});
  }

  bool get _automaticTranslationEnabled =>
      _hasAvailableTranslationOption &&
      _translation.translateChats &&
      _translation.autoTranslateEnabledFor(widget.chatId) &&
      _translation.shouldTranslateLanguage(_detectedChatLanguage);

  bool get _hasIncomingTranslatableMessages => _vm.messages.any(
    (message) =>
        !message.isOutgoing &&
        !message.isService &&
        automaticTranslationSourceText(message).trim().isNotEmpty,
  );

  bool get _showsChatTranslationPanel {
    if (!_hasAvailableTranslationOption) return false;
    if (_automaticTranslationEnabled) return true;
    if (!_translation.translateChats ||
        _translation.autoTranslateSuggestionDismissedFor(widget.chatId) ||
        !_hasIncomingTranslatableMessages ||
        !_chatLanguageDetectionComplete) {
      return false;
    }
    return _translation.shouldTranslateLanguage(_detectedChatLanguage);
  }

  void _scheduleChatLanguageDetection({bool force = false}) {
    if (!_hasAvailableTranslationOption ||
        !_translation.translateChats ||
        _chatLanguageDetectionRunning) {
      return;
    }
    if (!force && _chatLanguageDetectionComplete) {
      final detectedAt = _chatLanguageDetectedAt;
      if (_detectedChatLanguage != null &&
          detectedAt != null &&
          DateTime.now().difference(detectedAt) < const Duration(hours: 1)) {
        return;
      }
    }
    final samples = automaticTranslationLanguageSamples(_vm.messages);
    if (samples.isEmpty) return;
    final newestId = _vm.messages.reversed
        .firstWhere(
          (message) =>
              !message.isOutgoing &&
              !message.isService &&
              automaticTranslationSourceText(message).trim().length >= 10,
          orElse: () => _vm.messages.last,
        )
        .id;
    if (!force && _chatLanguageDetectionComplete) {
      if (_chatLanguageDetectionNewestMessageId == newestId) return;
    }
    _chatLanguageDetectionRunning = true;
    unawaited(() async {
      final detections = await Future.wait(
        samples.map(NativeTranslationApi.identifyLanguage),
      );
      final evidence = <AutomaticTranslationLanguageEvidence>[
        for (var index = 0; index < samples.length; index++)
          if (detections[index] case final detected?)
            AutomaticTranslationLanguageEvidence(
              languageCode: detected.languageCode,
              confidence: detected.confidence,
              characterCount: samples[index].runes.length,
            ),
      ];
      final detected = dominantAutomaticTranslationLanguage(evidence);
      if (!mounted) return;
      _chatLanguageDetectionRunning = false;
      _chatLanguageDetectionComplete = true;
      _chatLanguageDetectionNewestMessageId = newestId;
      _chatLanguageDetectedAt = DateTime.now();
      _detectedChatLanguage = detected;
      _scheduleAutomaticTranslations();
      setState(() {});
    }());
  }

  void _scheduleAutomaticTranslations() {
    if (!_automaticTranslationEnabled) return;
    if (_autoTranslationRunning) {
      _autoTranslationPassPending = true;
      return;
    }
    if (_autoTranslationPassPending) return;
    _autoTranslationPassPending = true;
    scheduleMicrotask(() {
      _autoTranslationPassPending = false;
      if (!mounted || !_automaticTranslationEnabled) return;
      unawaited(_runAutomaticTranslationPass());
    });
  }

  Future<void> _runAutomaticTranslationPass() async {
    if (_autoTranslationRunning || !_automaticTranslationEnabled) return;
    _autoTranslationRunning = true;
    if (mounted) setState(() {});
    try {
      final messages = _vm.messages.length > 32
          ? _vm.messages.sublist(_vm.messages.length - 32)
          : _vm.messages;
      final candidates = automaticTranslationCandidates(
        messages,
        targetLanguageCode: _translationTargetLanguage(_translation),
        excludedMessageIds: _autoTranslationFailedMessageIds,
      );
      for (final message in candidates) {
        if (!mounted || !_automaticTranslationEnabled) break;
        final translated = await _translateMessage(
          message,
          showErrors: false,
          allowWhenManualTranslationDisabled: true,
          sourceLanguageCode: _detectedChatLanguage ?? 'autodetect',
        );
        if (translated) {
          _autoTranslatedMessageIds.add(message.id);
        } else {
          _autoTranslationFailedMessageIds.add(message.id);
        }
      }
    } finally {
      _autoTranslationRunning = false;
      if (mounted) setState(() {});
      if (_autoTranslationPassPending) {
        _autoTranslationPassPending = false;
        _scheduleAutomaticTranslations();
      }
    }
  }

  void _toggleAutomaticTranslation() {
    final active = _translation.autoTranslateEnabledFor(widget.chatId);
    _translation.setAutoTranslateEnabledFor(widget.chatId, !active);
  }

  void _dismissAutomaticTranslation() {
    _translation.dismissAutoTranslateSuggestionFor(widget.chatId);
  }

  Future<void> _showChatTranslationLanguagePicker() async {
    final c = context.colors;
    await showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: TranslationController.targetLanguages.length,
            separatorBuilder: (_, _) => const InsetDivider(leadingInset: 54),
            itemBuilder: (_, index) {
              final language = TranslationController.targetLanguages[index];
              final selected = _translation.targetLanguageCode == language.code;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _translation.targetLanguageCode = language.code;
                  Navigator.of(sheetContext).pop();
                },
                child: SizedBox(
                  height: 52,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        AppIcon(
                          HeroAppIcons.globe,
                          size: 19,
                          color: selected ? AppTheme.brand : c.textSecondary,
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            language.label.l10n(sheetContext),
                            style: TextStyle(
                              fontSize: 16,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        if (selected)
                          AppIcon(
                            HeroAppIcons.check,
                            size: 18,
                            color: AppTheme.brand,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _chatTranslationPanel() => ChatTranslationPanel(
    active: _automaticTranslationEnabled,
    targetLanguageLabel: _translation.targetLanguageLabel.l10n(context),
    isTranslating: _autoTranslationRunning,
    onToggle: _toggleAutomaticTranslation,
    onChooseLanguage: () => unawaited(_showChatTranslationLanguagePicker()),
    onDismiss: _dismissAutomaticTranslation,
  );

  String _translationSourceText(ChatMessage message) {
    final parts = [
      message.text,
      message.linkPreview?.title ?? '',
      message.linkPreview?.description ?? '',
    ].where((p) => p.trim().isNotEmpty);
    return parts.join('\n');
  }

  String _translationTargetLanguage(TranslationController translation) {
    if (translation.targetLanguageCode != 'auto') {
      return translation.targetLanguageCode;
    }
    final locale = Localizations.localeOf(context);
    final country = locale.countryCode?.toUpperCase();
    if (locale.languageCode == 'zh') {
      return switch (country) {
        'TW' || 'HK' || 'MO' => 'zh-Hant',
        _ => 'zh-Hans',
      };
    }
    return locale.languageCode;
  }

  Future<String> _translateTextWithAi({
    required AiModelCandidate candidate,
    required String text,
    required String sourceLanguageCode,
    required String targetLanguageCode,
    List<String> priorMessages = const [],
  }) async {
    final unavailableMessage = AppStringKeys.translationAiProviderUnavailable
        .l10n(context);
    final targetLanguageName = _translation.targetLanguageLabel.l10n(context);
    final ai = _ai;
    if (ai == null) throw TranslationApiException(unavailableMessage);
    if (!ai.initialized) await ai.initialize();
    if (!ai.isConfiguredCandidate(candidate)) {
      throw TranslationApiException(unavailableMessage);
    }
    final service = AiChatTranslationService.fromCandidate(
      ai,
      candidate,
      instructions: _translation.aiTranslationPrompt,
      telegramAi: _vm.telegramAi,
    );
    try {
      return await service.translate(
        text: text,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        targetLanguageName: targetLanguageName,
        priorMessages: priorMessages,
      );
    } finally {
      service.dispose();
    }
  }

  List<String> _aiTranslationContextFor(ChatMessage message) {
    final index = _vm.messages.indexWhere((item) => item.id == message.id);
    if (index <= 0) return const [];
    final contextMessages = <String>[];
    for (var i = index - 1; i >= 0 && contextMessages.length < 4; i--) {
      final source = automaticTranslationSourceText(
        _vm.messages[i],
      ).replaceAll(RegExp(r'\s+'), ' ').trim();
      if (source.isEmpty) continue;
      contextMessages.add(
        source.length > 400 ? source.substring(0, 400) : source,
      );
    }
    return contextMessages.reversed.toList(growable: false);
  }

  bool _isEditableMediaMessage(ChatMessage message) =>
      message.contentType == 'messagePhoto' ||
      message.contentType == 'messageVideo' ||
      message.contentType == 'messageAnimation' ||
      message.contentType == 'messageAudio' ||
      message.contentType == 'messageDocument';

  Future<void> _editMessage(ChatMessage message) async {
    if (message.checklist case final checklist?) {
      final result = await Navigator.of(context).push<ChecklistComposerResult>(
        MaterialPageRoute(
          builder: (_) => ChecklistComposerView(
            initialTitle: checklist.title,
            initialTasks: [for (final task in checklist.tasks) task.text],
            initialOthersCanAddTasks: checklist.othersCanAddTasks,
            initialOthersCanMarkTasksAsDone: checklist.othersCanMarkTasksAsDone,
          ),
        ),
      );
      if (!mounted || result == null) return;
      try {
        await _vm.editChecklist(message, result);
      } catch (error) {
        if (mounted) showToast(context, error.toString());
      }
      return;
    }
    if (_isEditableMediaMessage(message)) {
      final action = await showGeneralDialog<_MediaEditAction>(
        context: context,
        barrierDismissible: true,
        barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
        barrierColor: Colors.black.withValues(alpha: 0.38),
        transitionDuration: const Duration(milliseconds: 170),
        pageBuilder: (_, _, _) =>
            _MediaEditActionDialog(mediaLabel: _mediaLabel(message)),
      );
      if (!mounted || action == null) return;
      switch (action) {
        case _MediaEditAction.edit:
          await _editMessageText(message);
        case _MediaEditAction.replace:
          await _replaceMessageMedia(message);
        case _MediaEditAction.delete:
          await _deleteMessageMedia(message);
      }
      return;
    }
    await _editMessageText(message);
  }

  Future<void> _editMessageText(ChatMessage message) {
    _vm.beginMessageEdit(message);
    return Future.value();
  }

  Future<void> _replaceMessageMedia(ChatMessage message) async {
    OutgoingAttachment? replacement;
    if (message.contentType == 'messagePhoto' ||
        message.contentType == 'messageVideo' ||
        message.contentType == 'messageAnimation') {
      final selection = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.imageAndVideo,
        maxAssets: 1,
      );
      if (!mounted || selection.assets.isEmpty) return;
      final asset = selection.assets.first;
      final file = asset.file;
      final kind = isPickedAssetVideo(file)
          ? OutgoingAttachmentKind.video
          : isPickedAssetGif(file)
          ? OutgoingAttachmentKind.animation
          : OutgoingAttachmentKind.photo;
      replacement = OutgoingAttachment(
        path: file.path,
        kind: kind,
        previewBytes: asset.thumbnailBytes,
        width: asset.width,
        height: asset.height,
      );
    } else {
      final picked = await FilePicker.platform.pickFiles(
        type: message.contentType == 'messageAudio'
            ? FileType.audio
            : FileType.any,
      );
      final path = picked?.files.single.path;
      if (!mounted || path == null) return;
      replacement = OutgoingAttachment(
        path: path,
        kind: message.contentType == 'messageAudio'
            ? OutgoingAttachmentKind.audio
            : OutgoingAttachmentKind.document,
      );
    }
    try {
      await _vm.editMessageMedia(
        message.id,
        replacement,
        caption: _editableMessageText(message),
        entities: [
          for (final entity in message.textEntities) entity.toTdJson(),
        ],
      );
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  Future<void> _deleteMessageMedia(ChatMessage message) async {
    final confirmed = await confirmDialog(
      context,
      title: AppStringKeys.chatDeleteSingleMessageQuestion,
      confirmText: AppStringKeys.chatDelete,
      destructive: true,
    );
    if (!mounted || !confirmed) return;
    try {
      await _vm.deleteMessage(message.id);
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  String _editableMessageText(ChatMessage message) {
    return message.text.trim().isEmpty ? '' : message.text;
  }

  String _mediaLabel(ChatMessage message) => switch (message.contentType) {
    'messagePhoto' => AppStrings.t(AppStringKeys.composerImagePreview),
    'messageVideo' => AppStrings.t(AppStringKeys.chatVideoPlaceholder),
    'messageAnimation' => AppStrings.t(AppStringKeys.tdMessageGif),
    'messageAudio' => AppStrings.t(AppStringKeys.tdMessageMusic),
    _ => AppStrings.t(AppStringKeys.topicPostContentFile),
  };

  void _openSenderProfile(ChatMessage m) {
    if (m.senderIsChat) {
      final senderChatId = m.senderId;
      if (senderChatId == null) return;
      final senderTitle = (m.senderName ?? m.senderTitle ?? _vm.peerTitle)
          .trim();
      final title = senderTitle.isEmpty ? _vm.peerTitle : senderTitle;
      if (senderChatId == widget.chatId) {
        unawaited(_openChatInfo(title: title, useAppPageRoute: true));
        return;
      }
      unawaited(
        openChatFromCurrentWindow(context, chatId: senderChatId, title: title),
      );
      return;
    }
    final uid = m.isOutgoing
        ? _vm.meId
        : (_vm.isGroup ? m.senderId : _vm.peerUserId);
    if (uid == null || uid <= 0) return;
    _openUserProfile(
      uid,
      m.isOutgoing ? _vm.meName : (m.senderName ?? _vm.peerTitle),
    );
  }

  Future<void> _openChatInfo({
    String? title,
    bool useAppPageRoute = false,
  }) async {
    final chatTitle = title ?? _vm.peerTitle;
    final Route<int> route = useAppPageRoute
        ? AppPageRoute<int>(
            pageBuilder: (_, _, _) =>
                ChatInfoView(chatId: widget.chatId, title: chatTitle),
          )
        : MaterialPageRoute<int>(
            builder: (_) =>
                ChatInfoView(chatId: widget.chatId, title: chatTitle),
          );
    final messageId = await Navigator.of(context).push<int>(route);
    if (!mounted || messageId == null) return;
    await _scrollToMessage(messageId);
  }

  void _handleInfoPressed() {
    final onInfoPressed = widget.onInfoPressed;
    if (onInfoPressed != null) {
      onInfoPressed();
      return;
    }
    unawaited(_openChatInfo());
  }

  void _handleFullInfoPressed() {
    final onOpenFullInfo = widget.onOpenFullInfo;
    if (onOpenFullInfo != null) {
      onOpenFullInfo();
      return;
    }
    unawaited(_openChatInfo());
  }

  void _openPeerProfile() {
    final uid = _vm.peerUserId;
    if (uid == null || uid <= 0) return;
    _openUserProfile(uid, _vm.peerTitle);
  }

  void _openUserProfile(int userId, String name) {
    final onOpenUserProfile = widget.onOpenUserProfile;
    if (onOpenUserProfile != null) {
      onOpenUserProfile(userId, name);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileDetailView(userId: userId, name: name),
      ),
    );
  }

  Future<void> _startCall(bool isVideo) async {
    if (_vm.isGroup) {
      try {
        await context.read<CallManager>().startGroupCall(
          chatId: _vm.chatId,
          title: _vm.peerTitle,
          isVideo: isVideo,
        );
      } catch (error) {
        if (!mounted) return;
        showToast(context, error.toString());
      }
      return;
    }
    final uid = _vm.peerUserId;
    if (uid == null) {
      showToast(context, AppStringKeys.chatContactCallsOnly);
      return;
    }
    final started = context.read<CallManager>().startCall(uid, isVideo);
    if (started != CallStartResult.started && mounted) {
      showToast(
        context,
        started == CallStartResult.unsupported
            ? AppStringKeys.callsUnavailableOnDesktop
            : AppStringKeys.callAlreadyInProgress,
      );
    }
  }

  Future<void> _forwardMessage(ChatMessage message) async {
    if (!_vm.canForwardContent) {
      _showForwardFailure(const ForwardBlockedException());
      return;
    }
    final result = await Navigator.of(context).push<ChatPickerResult>(
      MaterialPageRoute(
        builder: (_) => const ChatPickerView(
          title: AppStringKeys.chatForwardToTitle,
          showForwardOptions: true,
        ),
      ),
    );
    if (result == null || !mounted) return;
    final target = result.chat;
    try {
      await _vm.forward(message.id, target.id, options: result.forwardOptions);
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatForwardedToName, {
          'value1': target.title,
        }),
      );
    } catch (e) {
      if (!mounted) return;
      _showForwardFailure(e);
    }
  }

  void _showForwardFailure(Object error) {
    showToast(
      context,
      isForwardProtectedError(error)
          ? AppStringKeys.chatForwardProtected
          : AppStrings.t(AppStringKeys.chatForwardFailed, {'value1': error}),
    );
  }

  ChatWallpaper? _effectiveWallpaper() {
    if (!_themingEnabled) return null;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chatWallpaper = _wallpaperController.wallpaperFor(
      widget.chatId,
      dark: dark,
    );
    if (chatWallpaper != null) return chatWallpaper;
    final defaultWallpaper = _wallpaperController.defaultWallpaper(dark: dark);
    if (defaultWallpaper != null) {
      return _wallpaperController.resolvedWallpaper(defaultWallpaper);
    }
    final globalChatWallpaper = _wallpaperController.globalThemeWallpaperFor(
      dark: dark,
    );
    final cloudWallpaper = _resolvedCloudTheme?.wallpaper;
    if (cloudWallpaper != null) {
      return _wallpaperController.resolvedWallpaper(cloudWallpaper);
    }
    return globalChatWallpaper == null
        ? null
        : _wallpaperController.resolvedWallpaper(globalChatWallpaper);
  }

  // Both run once per bubble; build() already resolved themingEnabled into the
  // field, so re-subscribing to ThemeController per row is pure overhead.
  Color? _effectiveOutgoingColor() {
    if (!_themingEnabled) {
      return AppTheme.bubbleOutgoing;
    }
    final chatColor = _resolvedChatThemeStyle?.outgoingColor;
    return chatColor ?? _resolvedCloudTheme?.outgoingColor;
  }

  Color? _effectiveOutgoingTextColor() {
    if (!_themingEnabled) {
      return AppTheme.bubbleOutgoingText;
    }
    return _resolvedChatThemeStyle?.outgoingTextColor ??
        _resolvedCloudTheme?.outgoingTextColor;
  }

  Color? _effectiveIncomingColor() =>
      _resolvedChatThemeStyle?.incomingColor ??
      _resolvedCloudTheme?.incomingColor;

  Color? _effectiveIncomingTextColor() =>
      _resolvedChatThemeStyle?.incomingTextColor ??
      _resolvedCloudTheme?.incomingTextColor;

  TelegramMessageColors? _effectiveMessageColors() {
    if (!_themingEnabled) return null;
    final style = _resolvedChatThemeStyle;
    return style == null
        ? _resolvedCloudTheme?.messageColors
        : TelegramMessageColors.fromChatThemeStyle(style);
  }

  @override
  Widget build(BuildContext context) {
    Widget withInternalLinkRouting(Widget child) => InternalChatLinkScope(
      target: InternalChatLinkTarget(
        chatId: widget.chatId,
        accountSlot: _sessionKey.accountSlot,
        openMessage: _scrollToMessage,
      ),
      child: child,
    );

    _shellLayoutGeneration++;
    final c = context.colors;
    final themeController = context.watch<ThemeController>();
    _themingEnabled = themeController.themingEnabled;
    final dark = Theme.of(context).brightness == Brightness.dark;
    _resolvedCloudTheme = themeController.cloudThemeFor(
      dark ? Brightness.dark : Brightness.light,
    );
    final chatThemeStyle = _themingEnabled
        ? _wallpaperController.themeStyleFor(widget.chatId, dark: dark)
        : null;
    _hasCustomChatTheme =
        _themingEnabled &&
        (chatThemeStyle != null ||
            (_resolvedCloudTheme == null &&
                _wallpaperController.hasExplicitGlobalThemeSelection(
                  dark: dark,
                )));
    _resolvedChatThemeStyle = !_themingEnabled
        ? null
        : chatThemeStyle ??
              (_resolvedCloudTheme == null
                  ? _wallpaperController.globalThemeStyleFor(dark: dark)
                  : null);
    // Keep blocked-user hiding toggle in sync with theme.
    BlockedUserService.shared.enabled = themeController.hideBlockedUserMessages;
    if (_vm.isAdministeredDirectMessagesGroup) {
      return withInternalLinkRouting(
        ChannelDirectMessagesView(chatId: widget.chatId, title: widget.title),
      );
    }
    if (_vm.isMessageBubbleRepository) {
      return withInternalLinkRouting(
        MessageBubbleRepositoryView(viewModel: _vm, onBack: _handleBack),
      );
    }
    final showPeerRestrictionBlock =
        _vm.isPeerRestricted && _vm.messages.isEmpty;
    Widget withKeyboardInsetProbe(Widget child) =>
        _KeyboardInsetProbe(onInset: _syncKeyboardInset, child: child);
    // Not a member, joinable, and nothing to preview → a custom join screen
    // (header + centered card) instead of the transcript + composer.
    if (!_vm.isMember && _vm.canJoin && _vm.messages.isEmpty) {
      return withKeyboardInsetProbe(
        withInternalLinkRouting(
          _withExitState(
            _withBackSwipe(
              Scaffold(
                backgroundColor: c.groupedBackground,
                body: _joinScreenBody(),
              ),
            ),
          ),
        ),
      );
    }
    return withKeyboardInsetProbe(
      withInternalLinkRouting(
        _withExitState(
          _withBackSwipe(
            Scaffold(
              backgroundColor: c.inputBarBackground,
              resizeToAvoidBottomInset: true,
              body: ChatWallpaperBackground(
                wallpaper: _effectiveWallpaper(),
                fallbackColor: c.chatBackground,
                brightness: Theme.of(context).brightness,
                child: ChatMediaDropRegion(
                  enabled:
                      _vm.canSendMessages &&
                      !_isSelecting &&
                      !showPeerRestrictionBlock,
                  onImagesDropped: _previewAndSendDroppedImages,
                  child: Listener(
                    onPointerDown: _handleChatPointerDown,
                    child: Stack(
                      key: _actionOverlayKey,
                      children: [
                        Positioned.fill(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // Scaffold shrinks its body as the keyboard slides,
                              // so this builder re-runs every animation frame
                              // even though only the width matters. Handing back
                              // the same widget lets Element.updateChild skip the
                              // header, transcript and composer entirely.
                              final width = constraints.maxWidth;
                              final cached = _cachedShellLayout;
                              if (cached != null &&
                                  _cachedShellLayoutGeneration ==
                                      _shellLayoutGeneration &&
                                  _cachedShellLayoutWidth == width) {
                                return cached;
                              }
                              final searchPane = _searchUsesResultsPane(width);
                              _searchResultsPaneVisible = searchPane;
                              final searching = _search.isActive;
                              final shell = ChatHeaderTrailingPaneLayout(
                                header: showPeerRestrictionBlock
                                    ? _header()
                                    : searching
                                    ? _searchHeader(showSteppers: searchPane)
                                    : (_isSelecting
                                          ? _selectionHeader()
                                          : _header()),
                                body: showPeerRestrictionBlock
                                    ? _restrictedPeerBlockPage()
                                    : Column(
                                        children: [
                                          Expanded(
                                            child: _transcriptLayer(
                                              searchPane: searchPane,
                                            ),
                                          ),
                                          _chatMusicPlayer(),
                                          // A narrow chat trades the composer
                                          // for the hit navigator; a wide one
                                          // keeps composing beside the results.
                                          if (searching && !searchPane)
                                            _searchNavigator()
                                          else if (_isSelecting)
                                            _selectionActionBar()
                                          else
                                            _composerArea(),
                                        ],
                                      ),
                                trailingPane: searchPane
                                    ? _searchResultsPane()
                                    : widget.trailingPane,
                                trailingPaneWidth: searchPane
                                    ? chatSearchResultsPaneWidth
                                    : widget.trailingPaneWidth,
                              );
                              _cachedShellLayout = shell;
                              _cachedShellLayoutGeneration =
                                  _shellLayoutGeneration;
                              _cachedShellLayoutWidth = width;
                              return shell;
                            },
                          ),
                        ),
                        if (_desktopStickerSetId != null)
                          _desktopStickerSetPanel(_desktopStickerSetId!),
                        if (_actionTarget != null && !_isSelecting)
                          _actionMenuOverlay(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopStickerSetPanel(int setId) {
    final colors = context.colors;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.centerRight,
          child: Container(
            key: const ValueKey('desktop-sticker-set-panel'),
            width: constraints.maxWidth / 2,
            height: constraints.maxHeight,
            decoration: BoxDecoration(
              color: colors.groupedBackground,
              border: Border(left: BorderSide(color: colors.divider)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 22,
                  offset: const Offset(-6, 0),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: StickerSetDetailView(
              key: ValueKey('desktop-sticker-set-$setId'),
              setId: setId,
              onClose: () => setState(() => _desktopStickerSetId = null),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _previewAndSendDroppedImages(
    List<OutgoingAttachment> attachments,
  ) async {
    if (!_vm.canSendMessages || attachments.isEmpty || !mounted) return;
    final preview = await Navigator.of(context).push<MediaSendPreviewResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MediaSendPreviewView(
          attachments: attachments,
          allowWhenOnline: _vm.canSendWhenOnline,
          effects: _vm.availableMessageEffects,
        ),
      ),
    );
    if (!mounted || preview == null || preview.attachments.isEmpty) return;
    final resolved = await resolveAttachmentListDimensions(preview.attachments);
    await _vm.sendAttachments(
      resolved,
      caption: preview.caption,
      sendConfiguration: preview.sendConfiguration,
    );
    if (mounted) _onComposerMessageSent();
  }

  Widget _restrictedPeerBlockPage() {
    return Center(child: _restrictedPeerBlockCard());
  }

  Widget _restrictedPeerBlockCard() {
    final c = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface =
        _effectiveIncomingColor() ??
        (isDark ? AppColors.dark.card : AppColors.light.card);
    final textColor = _effectiveIncomingTextColor() ?? c.textPrimary;
    final text = _vm.peerRestrictionText.trim().isEmpty
        ? AppStringKeys.chatRestrictedTelegramTosMessage.l10n(context)
        : _vm.peerRestrictionText.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: _shouldOfferPeerSensitiveContentUnblock
              ? () => unawaited(_showPeerSensitiveContentUnblockDialog())
              : null,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              height: 1.25,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  bool get _shouldOfferPeerSensitiveContentUnblock {
    if (!_vm.isPeerRestricted) return false;
    if (SensitiveContentController.shared.enabled) return false;
    return _vm.isPeerPornographicRestricted ||
        TDParse.isPornographicRestrictionText(_vm.peerRestrictionText);
  }

  Future<void> _showPeerSensitiveContentUnblockDialog() async {
    final ok = await confirmDialog(
      context,
      title: AppStringKeys.sensitiveContentUnblockTitle,
      message: AppStringKeys.sensitiveContentUnblockMessage,
      confirmText: AppStringKeys.sensitiveContentUnblockConfirm,
    );
    if (!ok) return;
    try {
      await SensitiveContentController.shared.setEnabled(true);
      await _vm.refreshPeerRestrictionState();
      if (!mounted) return;
      showToast(
        context,
        AppStringKeys.sensitiveContentUnblockDone.l10n(context),
      );
    } catch (error) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.sensitiveContentUnblockFailed, {
          'value1': error.toString(),
        }),
      );
    }
  }

  Widget _transcriptLayer({required bool searchPane}) {
    final aiSettings = context.watch<AiSettingsController?>();
    final transcriptReady = _initialTranscriptReady;
    final newMessagesPlacement = chatNewMessagesControlPlacement(
      isScrolledUp: _showJumpDown,
      hasNewMessages: _shouldShowNewMessagesBanner,
      isEntryUnread: _showEntryUnreadBanner,
    );
    final bottomIndicator = chatBottomIndicator(
      isScrolledUp: _showJumpDown,
      hasNewMessages:
          newMessagesPlacement == ChatNewMessagesControlPlacement.bottom,
    );
    final showPinnedTodo =
        transcriptReady &&
        !_isSelecting &&
        // The pinned bar and the suggestion card want the same corner, and a
        // pinned message is not what is being looked for mid-search.
        !_search.isActive &&
        _vm.pinnedMessage != null &&
        !_vm.pinnedDismissed;
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: transcriptReady ? 1 : 0,
            child: IgnorePointer(
              ignoring: !transcriptReady,
              child: _transcript(),
            ),
          ),
        ),
        if (shouldShowTranscriptSkeleton(
          initialTranscriptReady: transcriptReady,
        ))
          Positioned.fill(child: _transcriptSkeleton()),
        if (showPinnedTodo)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _pinnedBar(_vm.pinnedMessage!),
          ),
        if (transcriptReady && _isSelecting) _selectToHereButton(),
        if (transcriptReady &&
            newMessagesPlacement == ChatNewMessagesControlPlacement.top)
          Positioned(
            right: 16,
            top: showPinnedTodo ? 72 : 12,
            child: _newMessagesControl(
              aiSettings,
              pointsDown: false,
              showsUnreadCount: true,
            ),
          ),
        if (transcriptReady &&
            newMessagesPlacement == ChatNewMessagesControlPlacement.bottom)
          Positioned(
            right: 16,
            bottom: 12,
            child: _newMessagesControl(
              aiSettings,
              pointsDown: true,
              showsUnreadCount:
                  _liveNewMessageCount == 0 &&
                  (_showEntryUnreadBanner || _vm.unreadCount > 0),
            ),
          ),
        if (transcriptReady && _vm.unreadMentionCount > 0)
          Positioned(
            top:
                (showPinnedTodo ? 72.0 : 8.0) +
                (newMessagesPlacement == ChatNewMessagesControlPlacement.top
                    ? 52
                    : 0),
            right: 12,
            child: _unreadMentionIndicator(),
          ),
        if (transcriptReady &&
            bottomIndicator == ChatBottomIndicator.jumpToBottom)
          Positioned(right: 16, bottom: 12, child: _jumpToBottomButton()),
        // Without a pane to hold them, suggestions float over the transcript
        // rather than replacing it — the conversation stays in view while a
        // sender is picked. The AnimatedBuilder keeps a suggestion arriving
        // from rebuilding every visible bubble underneath it.
        if (!searchPane && _search.isActive)
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            child: AnimatedBuilder(
              animation: _search,
              builder: (_, _) => _searchOverlay ?? const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }

  /// The floating suggestion or hint card, or null when neither applies.
  Widget? get _searchOverlay {
    if (!_search.isActive) return null;
    final showsSuggestions = _search.activeToken != null;
    if (!showsSuggestions && !_search.showsTokenHints) return null;
    final c = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const ValueKey('chatSearchFloatingSuggestions'),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.42,
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.divider, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: showsSuggestions
            ? SearchTokenSuggestionList(
                suggestions: _search.suggestions,
                onPick: _search.applySuggestion,
              )
            : SingleChildScrollView(
                child: SearchTokenHints(
                  hints: const [searchTokenFromHint, searchTokenHasHint],
                  onPick: _search.startToken,
                ),
              ),
      ),
    );
  }

  Widget _transcriptSkeleton() {
    final c = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    final rows = <Widget>[];
    for (var i = 0; i < 9; i++) {
      final outgoing = i == 2 || i == 6;
      final bubbleWidth = math.min(
        width * (outgoing ? 0.58 : (i.isEven ? 0.66 : 0.48)),
        360.0,
      );
      final bubbleHeight = i == 4 ? 82.0 : (i.isEven ? 48.0 : 38.0);
      rows.add(
        Padding(
          padding: EdgeInsets.fromLTRB(
            outgoing ? 72 : 14,
            i == 0 ? 14 : 8,
            outgoing ? 14 : 72,
            8,
          ),
          child: Row(
            mainAxisAlignment: outgoing
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!outgoing) ...[
                _skeletonBlock(36, 36, radius: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  crossAxisAlignment: outgoing
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    if (!outgoing && i % 3 == 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 5),
                        child: _skeletonBlock(86, 10, radius: 5),
                      ),
                    _skeletonBlock(bubbleWidth, bubbleHeight, radius: 10),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _effectiveWallpaper() == null
              ? c.chatBackground
              : const Color(0x00000000),
        ),
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: rows,
        ),
      ),
    );
  }

  Widget _skeletonBlock(double width, double height, {double radius = 8}) {
    final c = context.colors;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: c.textPrimary.withValues(alpha: 0.075),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  bool get _shouldShowNewMessagesBanner {
    if (_remainingUnreadCount <= 0 || _bannerDismissed) {
      return false;
    }
    if (_showEntryUnreadBanner) return true;
    if (_liveNewMessageCount > 0) return !_isAtLoadedBottom();
    if (_isAtLoadedBottom()) return false;
    return _openAtLatest || !_isNearBottom(80);
  }

  /// Small button (bottom-right of the transcript) to return to the newest
  /// message; shown only when the user has scrolled up.
  Widget _jumpToBottomButton() {
    final c = context.colors;
    return GestureDetector(
      key: const ValueKey('chat-jump-to-bottom'),
      behavior: HitTestBehavior.opaque,
      onTap: _onReturnToLatestTapped,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.navBar,
          shape: BoxShape.circle,
          border: Border.all(color: c.divider, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: _showReturnToLatestProgress
            ? AppActivityIndicator(size: 18, color: c.textSecondary)
            : AppIcon(HeroAppIcons.angleDown, size: 22, color: c.textSecondary),
      ),
    );
  }

  /// Unread/new-message pill. In latest-on-open mode it points up to the
  /// unread boundary; in unread-boundary mode it points down to the newest.
  Widget _newMessagesBanner({
    required bool pointsDown,
    required bool showsUnreadCount,
    required bool hasAiAttachment,
  }) {
    final c = context.colors;
    final count = _remainingUnreadCount;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: pointsDown
          ? _onReturnToLatestTapped
          : () => unawaited(_jumpToFirstUnread()),
      child: Container(
        padding: EdgeInsetsDirectional.fromSTEB(
          12,
          7,
          hasAiAttachment ? 48 : 12,
          7,
        ),
        decoration: BoxDecoration(
          color: c.navBar,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: c.divider, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pointsDown && _showReturnToLatestProgress)
              AppActivityIndicator(size: 14, color: AppTheme.brand)
            else
              AppIcon(
                pointsDown ? HeroAppIcons.arrowDown : HeroAppIcons.arrowUp,
                size: 14,
                color: AppTheme.brand,
              ),
            const SizedBox(width: 5),
            Text(
              AppStrings.t(
                showsUnreadCount
                    ? AppStringKeys.chatUnreadMessagesCount
                    : AppStringKeys.chatNewMessagesCount,
                {'value1': count},
              ),
              style: TextStyle(
                fontSize: 13,
                color: c.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _newMessagesControl(
    AiSettingsController? settings, {
    required bool pointsDown,
    required bool showsUnreadCount,
  }) {
    final aiAttachment = _canOfferUnreadSummary(settings)
        ? _unreadSummaryButton()
        : null;
    final banner = _newMessagesBanner(
      pointsDown: pointsDown,
      showsUnreadCount: showsUnreadCount,
      hasAiAttachment: aiAttachment != null,
    );
    return ChatNewMessagesControlShell(
      unreadBadge: banner,
      aiAttachment: aiAttachment,
    );
  }

  bool _canOfferUnreadSummary(AiSettingsController? settings) =>
      shouldShowUnreadChatSummaryAttachment(
        unreadMessageCount: _remainingUnreadCount,
        providerAvailable:
            settings?.initialized == true &&
            settings?.enabled == true &&
            settings?.isConfiguredForFeature(AiFeature.summary) == true &&
            _vm.unreadSummarySnapshot != null &&
            !_vm.isSecretChat &&
            !_vm.hasProtectedContent,
      );

  Widget _unreadSummaryButton() {
    final c = context.colors;
    return Semantics(
      button: true,
      label: AppStringKeys.aiSummaryButton.l10n(context),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openingUnreadSummary ? null : _openUnreadSummary,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: _openingUnreadSummary ? 0.62 : 1,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brand,
              shape: BoxShape.circle,
              border: Border.all(
                color: c.textPrimary.withValues(alpha: 0.24),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              'AI',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUnreadSummary() async {
    final snapshot = _vm.unreadSummarySnapshot;
    final settings = context.read<AiSettingsController?>();
    if (snapshot == null || !_canOfferUnreadSummary(settings)) return;
    setState(() => _openingUnreadSummary = true);

    final configuration = settings!.configurationForFeature(AiFeature.summary);
    final endpoint = configuration.endpoint;
    final endpointStyle = configuration.endpointStyle;
    final model = configuration.model;
    final apiKey = configuration.apiKey;
    final hostedContextSize =
        configuration.candidate.kind == AiModelCandidateKind.server
        ? configuration.contextWindowTokens
        : null;
    final pccContextSize =
        configuration.candidate.kind == AiModelCandidateKind.applePcc
        ? configuration.contextWindowTokens
        : null;
    final onDeviceContextSize =
        configuration.candidate.kind == AiModelCandidateKind.appleOnDevice
        ? configuration.contextWindowTokens
        : null;
    final outputLanguage = Localizations.localeOf(context).toLanguageTag();
    final session = _createUnreadSummarySession(
      candidateKind: configuration.candidate.kind,
      endpoint: endpoint,
      endpointStyle: endpointStyle,
      model: model,
      apiKey: apiKey,
      hostedContextSize: hostedContextSize,
      pccContextSize: pccContextSize,
      onDeviceContextSize: onDeviceContextSize,
      outputLanguage: outputLanguage,
      summaryGuidance: settings.aiSummaryPrompt,
    );
    int? messageId;
    try {
      messageId = await Navigator.of(context).push<int>(
        MaterialPageRoute<int>(
          builder: (_) => UnreadChatSummaryView(
            snapshot: snapshot,
            summarize: (onProgress, onDraft) => session.summarize(
              snapshot,
              onProgress: onProgress,
              onDraft: onDraft,
            ),
          ),
        ),
      );
    } finally {
      session.dispose();
      if (mounted) setState(() => _openingUnreadSummary = false);
    }
    if (!mounted) return;
    if (messageId != null) await _scrollToMessage(messageId);
  }

  _UnreadSummarySession _createUnreadSummarySession({
    required AiModelCandidateKind candidateKind,
    required Uri? endpoint,
    required AiEndpointStyle endpointStyle,
    required String model,
    required String apiKey,
    required int? hostedContextSize,
    required int? pccContextSize,
    required int? onDeviceContextSize,
    required String outputLanguage,
    required String summaryGuidance,
  }) {
    final loader = UnreadChatHistoryLoader(
      query: (accountSlot, request) {
        final clientId = TdClient.shared.clientId(accountSlot);
        if (clientId == null) {
          throw StateError('The account used for this chat is unavailable.');
        }
        return TdClient.shared.queryTo(request, clientId);
      },
    );
    final guidanceTokenEstimate = estimateUnreadSummaryPromptTokens({
      'user_guidance': summaryGuidance,
    });
    int messagePayloadBudget(int totalPayloadTokens) =>
        math.max(1, totalPayloadTokens - guidanceTokenEstimate);

    switch (candidateKind) {
      case AiModelCandidateKind.telegramCocoon:
        const contextWindow = 8192;
        final tokenBudget = unreadSummaryTokenBudget(
          contextWindow,
          trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
          maximumResponseTokens: 1300,
          maximumPayloadTokens: 5500,
        );
        return _UnreadSummarySession(
          UnreadChatSummaryService(
            historyLoader: loader,
            maxChunkMessages: 180,
            maxChunks: 5,
            maxConcurrentRequests: 1,
            maxChunkTokenEstimate: messagePayloadBudget(
              tokenBudget.payloadTokens,
            ),
            mergeChunkSummariesLocally: true,
            trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
            summaryGuidance: summaryGuidance,
            providerCode: 'telegram_cocoon',
            contextWindowTokens: contextWindow,
            outputLanguage: outputLanguage,
            initialPromptTokenEstimate: tokenBudget.initialPromptTokens,
            reservedNonPayloadTokenEstimate:
                tokenBudget.reservedNonPayloadTokens,
            provider: TelegramCocoonUnreadSummaryProvider(
              telegramAi: _vm.telegramAi,
            ),
          ),
        );
      case AiModelCandidateKind.applePcc:
        final contextWindow = math.min(
          pccContextSize ?? applePccContextTokenLimit,
          applePccContextTokenLimit,
        );
        final tokenBudget = unreadSummaryTokenBudget(
          contextWindow,
          trustedInstructions: unreadChatSummaryTrustedInstructions,
          maximumResponseTokens: 1300,
        );
        return _UnreadSummarySession(
          UnreadChatSummaryService(
            historyLoader: loader,
            maxChunkMessages: 180,
            maxChunks: 5,
            maxChunkTokenEstimate: math.min(
              7000,
              messagePayloadBudget(tokenBudget.payloadTokens),
            ),
            mergeChunkSummariesLocally: true,
            summaryGuidance: summaryGuidance,
            providerCode: 'apple_pcc',
            contextWindowTokens: contextWindow,
            outputLanguage: outputLanguage,
            initialPromptTokenEstimate: tokenBudget.initialPromptTokens,
            reservedNonPayloadTokenEstimate:
                tokenBudget.reservedNonPayloadTokens,
            provider: ApplePccUnreadSummaryProvider(
              api: ApplePccApi(summaryTimeout: const Duration(seconds: 50)),
              reasoningLevel: ApplePccReasoningLevel.light,
              chunkMaximumResponseTokens: 1300,
            ),
          ),
        );
      case AiModelCandidateKind.appleOnDevice:
        final contextWindow = math.min(
          onDeviceContextSize ?? appleOnDeviceContextTokenLimit,
          appleOnDeviceContextTokenLimit,
        );
        final tokenBudget = unreadSummaryTokenBudget(
          contextWindow,
          maximumContextSize: appleOnDeviceContextTokenLimit,
          trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
          maximumResponseTokens: 650,
        );
        return _UnreadSummarySession(
          UnreadChatSummaryService(
            historyLoader: loader,
            maxChunkMessages: 70,
            maxChunks: 4,
            maxConcurrentRequests: 1,
            maxChunkTokenEstimate: messagePayloadBudget(
              tokenBudget.payloadTokens,
            ),
            mergeChunkSummariesLocally: true,
            trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
            summaryGuidance: summaryGuidance,
            providerCode: 'apple_on_device',
            contextWindowTokens: contextWindow,
            outputLanguage: outputLanguage,
            initialPromptTokenEstimate: tokenBudget.initialPromptTokens,
            reservedNonPayloadTokenEstimate:
                tokenBudget.reservedNonPayloadTokens,
            provider: ApplePccUnreadSummaryProvider(
              api: ApplePccApi(summaryTimeout: const Duration(seconds: 40)),
              model: AppleAiModel.onDevice,
              reasoningLevel: ApplePccReasoningLevel.light,
              chunkMaximumResponseTokens: 650,
              mergeMaximumResponseTokens: 650,
            ),
          ),
        );
      case AiModelCandidateKind.server:
        if (endpoint == null || model.trim().isEmpty) {
          throw StateError('The summary server is not configured.');
        }
        final contextWindow =
            hostedContextSize ?? AiModelProfile.defaultContextWindowTokens;
        // Reserve response space while selecting input, but do not send a
        // generation cap to user-configured servers.
        const responseTokenReserve = 4096;
        final tokenBudget = unreadSummaryTokenBudget(
          contextWindow,
          maximumContextSize: AiModelProfile.maximumContextWindowTokens,
          trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
          maximumResponseTokens: responseTokenReserve,
          maximumPayloadTokens: contextWindow,
        );
        final provider = OpenAiCompatibleUnreadSummaryProvider(
          serverBaseUri: endpoint,
          model: model.trim(),
          apiKey: apiKey,
          endpointStyle: endpointStyle,
        );
        return _UnreadSummarySession(
          UnreadChatSummaryService(
            historyLoader: loader,
            provider: provider,
            maxChunkMessages: 1000000,
            maxChunks: 4,
            maxConcurrentRequests: 4,
            maxChunkTokenEstimate: messagePayloadBudget(
              tokenBudget.payloadTokens,
            ),
            maxChunkTimeGapSeconds: 0,
            trustedInstructions: unreadChatSummaryCompactTrustedInstructions,
            summaryGuidance: summaryGuidance,
            providerCode: '${endpointStyle.storageValue}/$model',
            contextWindowTokens: contextWindow,
            outputLanguage: outputLanguage,
            initialPromptTokenEstimate: tokenBudget.initialPromptTokens,
            reservedNonPayloadTokenEstimate:
                tokenBudget.reservedNonPayloadTokens,
          ),
          onDispose: provider.close,
        );
    }
  }

  Widget _unreadMentionIndicator() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openingUnreadMention ? null : _openUnreadMention,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: _openingUnreadMention ? 0.62 : 1,
        child: Container(
          width: 40,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.brand,
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Text(
            '@',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUnreadMention() async {
    if (_openingUnreadMention || _vm.unreadMentionCount <= 0) return;
    setState(() => _openingUnreadMention = true);
    final messageId = await _vm.openNextUnreadMention();
    if (messageId != null && mounted) {
      await _scrollToMessage(messageId);
      if (_vm.messages.any((message) => message.id == messageId)) {
        await _vm.markUnreadMentionRead(messageId);
      }
    }
    if (mounted) setState(() => _openingUnreadMention = false);
  }

  // MARK: - Composer area (input bar / join bar / disabled bar)

  Widget _chatMusicPlayer() {
    return AnimatedBuilder(
      animation: MusicPlayerController.shared,
      builder: (context, _) {
        final player = MusicPlayerController.shared;
        return AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: player.isVisible && !player.collapsed
              ? const GlobalMusicPlayerBar()
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _composerArea() {
    if (_vm.peerIsBot &&
        _vm.initialLoaded &&
        _vm.messages.isEmpty &&
        !_vm.botStartSent &&
        _vm.canSendMessages) {
      return _botStartBar();
    }
    if (_vm.canSendMessages) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_vm.businessBotUserId != 0) _businessBotManageBar(),
          _chatInputBar(),
        ],
      );
    }
    if (!_vm.isMember && _vm.canJoin) return _joinBar();
    // Subscribed to a channel you can't post in → mute/unmute (like official).
    if (_vm.isChannel && _vm.isMember) return _channelMuteBar();
    return _disabledComposer(_vm.sendDisabledReason);
  }

  // ChatInputBar subscribes to the view model itself, so the parent's
  // notification-driven rebuilds only re-run its build for nothing. Every other
  // constructor argument is either the (final) view model or a method tear-off,
  // so these four flags are the whole input set.
  Widget? _composerBarCache;
  bool _composerBarRequestInitialFocus = false;
  bool _composerBarEnterToSend = false;
  bool _composerBarQuickRepliesEnabled = false;
  bool _composerBarShowCallAction = false;

  Widget _chatInputBar() {
    final themeController = context.watch<ThemeController>();
    final requestInitialFocus = widget.requestComposerFocusOnReady;
    final enterToSend = themeController.enterToSend;
    final quickRepliesEnabled = themeController.quickRepliesEnabled;
    final showCallAction = !_usesWideGroupHeader;
    final cached = _composerBarCache;
    if (cached != null &&
        _composerBarRequestInitialFocus == requestInitialFocus &&
        _composerBarEnterToSend == enterToSend &&
        _composerBarQuickRepliesEnabled == quickRepliesEnabled &&
        _composerBarShowCallAction == showCallAction) {
      return cached;
    }
    _composerBarRequestInitialFocus = requestInitialFocus;
    _composerBarEnterToSend = enterToSend;
    _composerBarQuickRepliesEnabled = quickRepliesEnabled;
    _composerBarShowCallAction = showCallAction;
    return _composerBarCache = ChatInputBar(
      vm: _vm,
      requestInitialFocus: requestInitialFocus,
      enterToSend: enterToSend,
      quickRepliesEnabled: quickRepliesEnabled,
      showCallAction: showCallAction,
      onStartCall: _startCall,
      onMessageSent: _onComposerMessageSent,
      onPanelGeometryChanged: _onComposerPanelGeometryChanged,
      onMediaSendTapped: _onComposerMediaSendTapped,
      onBotTopicCreated: _openTopicMode,
    );
  }

  Widget _businessBotManageBar() {
    final c = context.colors;
    final paused = _vm.businessBotPaused;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          AppIcon(
            paused ? HeroAppIcons.pause : HeroAppIcons.code,
            size: 18,
            color: paused ? c.textSecondary : AppTheme.brand,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showBusinessBotControls,
              child: Text(
                AppStrings.t(
                  paused
                      ? AppStringKeys.chatBusinessBotPaused
                      : _vm.businessBotCanReply
                      ? AppStringKeys.chatBusinessBotCanReply
                      : AppStringKeys.chatBusinessBotReadOnly,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ),
          ),
          if (_vm.businessBotManageUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openLink(context, _vm.businessBotManageUrl),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  AppStrings.t(AppStringKeys.appearanceManage),
                  style: TextStyle(fontSize: 14, color: AppTheme.brand),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showBusinessBotControls() async {
    final changed = await showAppModalSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => BusinessBotChatControlSheet(
        chatId: widget.chatId,
        botName: AppStrings.t(AppStringKeys.chatConnectedBusinessBot),
        paused: _vm.businessBotPaused,
      ),
    );
    if (changed == true) await _vm.refreshPeerRestrictionState();
  }

  Widget _botStartBar() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _sendBotStart,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.brand,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Text(
            AppStringKeys.startButton.l10n(context),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.onBrand,
            ),
          ),
        ),
      ),
    );
  }

  Widget _channelMuteBar() {
    final c = context.colors;
    final muted = _vm.isMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _vm.toggleMute(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
          16,
          14,
          16,
          14 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: c.navBar,
          border: Border(top: BorderSide(color: c.divider, width: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(HeroAppIcons.solidBell, size: 18, color: AppTheme.brand),
            const SizedBox(width: 8),
            Text(
              (muted ? AppStringKeys.chatUnmute : AppStringKeys.callMute).l10n(
                context,
              ),
              style: TextStyle(fontSize: 16, color: AppTheme.brand),
            ),
          ],
        ),
      ),
    );
  }

  /// Bottom bar with a 加入 / 申请加入 button for a joinable chat you can preview.
  Widget _joinBar() {
    final c = context.colors;
    final requested = _vm.joinRequested;
    final label = requested
        ? AppStringKeys.chatJoinRequestSent
        : (_vm.joinByRequest
              ? AppStringKeys.chatRequestToJoin
              : AppStringKeys.chatJoinGroup);
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: requested ? null : () => _vm.joinChat(),
        child: Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: requested ? c.searchFill : AppTheme.brand,
            borderRadius: BorderRadius.circular(23),
          ),
          child: Text(
            AppStrings.t(label),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: requested ? c.textSecondary : AppTheme.onBrand,
            ),
          ),
        ),
      ),
    );
  }

  /// Static bar shown when sending is blocked (muted / channel / removed).
  Widget _disabledComposer(String reason) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        14 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      alignment: Alignment.center,
      child: Text(
        (reason.isEmpty ? AppStringKeys.chatCannotSendMessages : reason).l10n(
          context,
        ),
        style: TextStyle(fontSize: 14, color: c.textSecondary),
      ),
    );
  }

  /// custom join screen for a joinable chat with no previewable content.
  Widget _joinScreenBody() {
    final c = context.colors;
    final requested = _vm.joinRequested;
    final label = requested
        ? AppStringKeys.chatJoinRequestPending
        : (_vm.joinByRequest
              ? AppStringKeys.chatRequestToJoin
              : AppStringKeys.chatJoinGroup);
    return ChatHeaderTrailingPaneLayout(
      header: _header(),
      trailingPane: widget.trailingPane,
      trailingPaneWidth: widget.trailingPaneWidth,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhotoAvatar(
                title: _vm.peerTitle,
                photo: _vm.peerPhoto,
                size: 88,
                square:
                    _vm.isGroup &&
                    !context.watch<ThemeController>().circularGroupAvatars,
              ),
              const SizedBox(height: 16),
              Text(
                _vm.peerTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
              if (_vm.memberCount > 0) ...[
                const SizedBox(height: 6),
                Text(
                  AppStrings.plural(
                    AppStringKeys.chatMemberCount,
                    _vm.memberCount,
                  ),
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                ),
              ],
              const SizedBox(height: 28),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: requested ? null : () => _vm.joinChat(),
                child: Container(
                  height: 46,
                  constraints: const BoxConstraints(minWidth: 200),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  decoration: BoxDecoration(
                    color: requested ? c.searchFill : AppTheme.brand,
                    borderRadius: BorderRadius.circular(AppRadius.xxl),
                  ),
                  child: Text(
                    AppStrings.t(label),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: requested ? c.textSecondary : AppTheme.onBrand,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    final subtitle = _vm.subtitle;
    final actionActive = _vm.hasActiveChatAction;
    final wideGroupHeader = _usesWideGroupHeader;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      decoration: BoxDecoration(
        color: widget.headerColor ?? c.navBar,
        border: widget.showHeaderDivider
            ? Border(bottom: BorderSide(color: c.divider, width: 0.5))
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: widget.headerHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  if (widget.showBackButton)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleBack,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: AppIcon(
                          HeroAppIcons.chevronLeft,
                          size: 22,
                          color: c.textPrimary,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 4),
                  Expanded(child: _headerTitleBlock(subtitle, actionActive)),
                  // Bot mini-app launcher lives in the header (menu bar), not
                  // on the message row.
                  if (_vm.peerIsBot && _vm.botMenu?.isWebApp == true)
                    _ChatHeaderAction(
                      key: const ValueKey('chatHeaderBotApp'),
                      label: _vm.botMenu!.actionTitle,
                      icon: HeroAppIcons.tableCells,
                      onTap: () => unawaited(_openBotMenuApp(_vm.botMenu!)),
                    ),
                  if (_canSearchMessages)
                    _ChatHeaderAction(
                      key: const ValueKey('chatHeaderSearch'),
                      label: AppStringKeys.chatSearchInThisChat.l10n(context),
                      icon: HeroAppIcons.magnifyingGlass,
                      onTap: _openSearch,
                    ),
                  if (wideGroupHeader)
                    WideGroupChatHeaderActions(
                      onStartCall: (isVideo) => unawaited(_startCall(isVideo)),
                      showCallActions:
                          Theme.of(context).platform != TargetPlatform.macOS,
                      onToggleContext: widget.onInfoPressed == null
                          ? null
                          : _handleInfoPressed,
                      onOpenFullInfo: _handleFullInfoPressed,
                    )
                  else
                    _ChatHeaderAction(
                      key: const ValueKey('chatHeaderInfo'),
                      label: AppStringKeys.chatInfoTitle.l10n(context),
                      icon: widget.onOpenFullInfo == null
                          ? HeroAppIcons.bars
                          : HeroAppIcons.gear,
                      onTap: widget.onOpenFullInfo == null
                          ? _handleInfoPressed
                          : _handleFullInfoPressed,
                    ),
                  if (_vm.supportsTopics) ...[
                    _ChatHeaderAction(
                      key: const ValueKey('chatHeaderTopics'),
                      label: AppStringKeys.topicChatAllTopics.l10n(context),
                      icon: HeroAppIcons.hashtag,
                      onTap: _openTopicMode,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_showsChatTranslationPanel) _chatTranslationPanel(),
          if (_showsBotApiAccessWarning)
            BotApiAccessWarning(
              showPrivacyWarning: _vm.showBotApiPrivacyWarning,
              showBotToBotWarning: _vm.showBotApiBotToBotWarning,
              onDismiss: _dismissBotApiAccessWarning,
            ),
          if (widget.headerBottom != null)
            SizedBox(
              height: widget.headerBottomHeight,
              child: widget.headerBottom,
            ),
        ],
      ),
    );
  }

  /// The join screen and a restricted peer both render the chat header over a
  /// page with no transcript behind it. Offering search there would open a
  /// field that can only ever report nothing.
  bool get _canSearchMessages =>
      !_vm.isPeerRestricted && (_vm.isMember || _vm.messages.isNotEmpty);

  bool get _usesWideGroupHeader {
    return wideGroupHeaderActionsEnabled(
      MediaQuery.sizeOf(context),
      isGroup: _vm.isGroup,
      hasContextPaneToggle: widget.onInfoPressed != null,
    );
  }

  Widget _headerTitleBlock(String subtitle, bool actionActive) {
    final c = context.colors;
    final serverTitle = _vm.peerTitle;
    final displayTitle = _vm.isGroup && !_vm.isChannel
        ? context.watch<GroupRemarkController?>()?.displayTitleFor(
                widget.chatId,
                serverTitle,
              ) ??
              serverTitle
        : serverTitle;
    final headerTitle = _vm.isGroup && _vm.memberCount > 0
        ? '$displayTitle(${_vm.memberCount})'
        : displayTitle;
    final titleText = Text(
      headerTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: c.textPrimary,
      ),
    );
    final title = _vm.isSecretChat
        ? Row(
            children: [
              AppIcon(HeroAppIcons.lock, size: 15, color: c.textSecondary),
              const SizedBox(width: 5),
              Expanded(child: titleText),
            ],
          )
        : titleText;
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_vm.supportsTopics)
          Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 4),
              AppIcon(
                HeroAppIcons.chevronDown,
                size: 14,
                color: c.textSecondary,
              ),
            ],
          )
        else
          title,
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: actionActive ? AppTheme.brand : c.textSecondary,
            ),
          ),
      ],
    );
    if (_vm.supportsTopics) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showTopicSelector,
        child: content,
      );
    }
    if ((_vm.peerUserId ?? 0) > 0) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openPeerProfile,
        child: content,
      );
    }
    return content;
  }

  ChatSummary _topicChatSummary() => ChatSummary(
    id: widget.chatId,
    title: _vm.peerTitle,
    lastMessage: '',
    lastMessageId: 0,
    date: 0,
    unreadCount: _vm.unreadCount,
    order: 0,
    isMuted: _vm.isMuted,
    kind: _vm.peerIsBot
        ? ChatKind.bot
        : _vm.isChannel
        ? ChatKind.channel
        : ChatKind.group,
    photo: _vm.peerPhoto,
    isForum: _vm.isForum,
    supportsBotTopics: _vm.supportsBotTopics,
  );

  Future<void> _openTopicMode([int? threadId]) async {
    await TopicGroupDisplayPreference.set(TopicGroupDisplayMode.channel);
    if (!mounted) return;
    final onOpenTopicMode = widget.onOpenTopicMode;
    if (onOpenTopicMode != null) {
      onOpenTopicMode(threadId);
      return;
    }
    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TopicChatView(
            chat: _topicChatSummary(),
            initialThreadId: threadId,
          ),
        ),
      ),
    );
  }

  Future<void> _showTopicSelector() async {
    if (!_vm.supportsTopics) return;
    if (_vm.forumTopics.isEmpty && !_vm.forumTopicsLoading) {
      await _vm.loadForumTopics();
    }
    if (!mounted) return;
    final topics = _vm.forumTopics;
    if (topics.isEmpty) {
      showToast(
        context,
        _vm.forumTopicsLoading
            ? AppStringKeys.chatLoadingTopics
            : AppStringKeys.chatNoTopics,
      );
      return;
    }
    final c = context.colors;
    await showAppModalSheet<void>(
      context: context,
      backgroundColor: c.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: topics.length + 1,
          separatorBuilder: (_, _) =>
              Divider(height: 1, indent: 56, color: c.divider),
          itemBuilder: (_, index) {
            final all = index == 0;
            final topic = all ? null : topics[index - 1];
            return ListTile(
              leading: _forumTopicIcon(topic, all, c),
              title: Text(
                (all ? AppStringKeys.topicChatAllTopics : topic!.name).l10n(
                  context,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textPrimary, fontSize: 16),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openTopicMode(topic?.id);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _forumTopicIcon(ForumTopicOption? topic, bool all, AppColors c) {
    if (all) {
      return AppIcon(HeroAppIcons.hashtag, color: AppTheme.brand, size: 24);
    }
    final iconId = topic?.iconCustomEmojiId ?? 0;
    if (iconId != 0) return CustomEmojiView(id: iconId, size: 24);
    final rawColor = topic?.iconColor ?? 0;
    final color = rawColor == 0
        ? c.textSecondary
        : Color(0xFF000000 | (rawColor & 0xFFFFFF));
    return AppIcon(HeroAppIcons.solidMessage, color: color, size: 24);
  }

  Widget _selectionHeader() {
    final c = context.colors;
    final count = _selectedMessageIds.length;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _exitSelection,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppStringKeys.countryPickerCancel.l10n(context),
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
            ),
            Expanded(
              child: Text(
                AppStrings.t(AppStringKeys.chatSelectedMessagesCount, {
                  'value1': count,
                }),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: 22,
                color: c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectToHereButton() {
    final c = context.colors;
    final align = _selectionScrollingUp
        ? Alignment.topLeft
        : Alignment.bottomLeft;
    final margin = EdgeInsets.only(
      left: 12,
      top: _selectionScrollingUp ? 12 : 0,
      bottom: _selectionScrollingUp ? 0 : 12,
    );
    return Align(
      alignment: align,
      child: Padding(
        padding: margin,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _selectToVisibleEdge,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: c.navBar,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _selectionScrollingUp
                      ? HeroAppIcons.arrowUp.data
                      : HeroAppIcons.chevronDown.data,
                  size: 18,
                  color: AppTheme.brand,
                ),
                const SizedBox(width: 5),
                Text(
                  AppStringKeys.chatSelectUntilHere.l10n(context),
                  style: TextStyle(fontSize: 15, color: AppTheme.brand),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _selectionActionBar() {
    final c = context.colors;
    final enabled = _selectedMessageIds.isNotEmpty;
    Widget button(
      IconData icon,
      VoidCallback onTap, {
      bool actionEnabled = true,
    }) {
      final available = enabled && actionEnabled;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: available ? onTap : null,
        child: SizedBox(
          width: 58,
          height: 52,
          child: Icon(
            icon,
            size: 26,
            color: available ? c.textPrimary : c.textTertiary,
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 58,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            button(
              HeroAppIcons.forward.data,
              _forwardSelected,
              actionEnabled: _vm.canForwardContent,
            ),
            button(
              HeroAppIcons.star.data,
              _saveSelected,
              actionEnabled: _vm.canForwardContent,
            ),
            button(HeroAppIcons.trash.data, _deleteSelected),
            button(
              HeroAppIcons.ellipsis.data,
              () =>
                  showToast(context, AppStringKeys.chatMoreActionsUnsupported),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinnedBar(ChatMessage pinned) {
    final c = context.colors;
    final text = pinned.text.trim().isEmpty
        ? AppStrings.t(AppStringKeys.chatSearchMessageResultLabel)
        : pinned.text.replaceAll('\n', ' ');
    final canPrevious = _vm.hasPreviousPinnedMessage;
    final canNext = _vm.hasNextPinnedMessage;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPinnedFromBar(pinned),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: c.divider.withValues(alpha: 0.55),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const AppIcon(
              HeroAppIcons.thumbtack,
              size: 16,
              color: Color(0xFFFFB300),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: text,
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: c.textPrimary),
              ),
            ),
            const SizedBox(width: 12),
            if (_vm.pinnedMessages.length > 1) ...[
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _pinnedNavButton(
                    icon: HeroAppIcons.chevronUp.data,
                    enabled: canPrevious,
                    onTap: _goToPreviousPinned,
                  ),
                  _pinnedNavButton(
                    icon: HeroAppIcons.chevronDown.data,
                    enabled: canNext,
                    onTap: _goToNextPinned,
                  ),
                ],
              ),
              const SizedBox(width: 4),
            ],
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _vm.dismissPinned,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: 16,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinnedNavButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 24,
        height: 18,
        child: Icon(
          icon,
          size: 14,
          color: c.textTertiary.withValues(alpha: enabled ? 1 : 0.28),
        ),
      ),
    );
  }

  Future<void> _openPinnedFromBar(ChatMessage pinned) async {
    await _scrollToMessage(pinned.id, pinnedJump: true);
  }

  void _goToPreviousPinned() {
    final pinned = _vm.previousPinnedMessage();
    if (pinned != null) {
      unawaited(_scrollToMessage(pinned.id, pinnedJump: true));
    }
  }

  void _goToNextPinned() {
    final pinned = _vm.nextPinnedMessage();
    if (pinned != null) {
      unawaited(_scrollToMessage(pinned.id, pinnedJump: true));
    }
  }

  /// Scrolls the transcript to a message. If it is not loaded, ask TDLib for a
  /// page centered around that id instead of fetching the whole middle history.
  Future<void> _scrollToMessage(
    int messageId, {
    bool pinnedJump = false,
    double? alignment,
    bool forceAlignment = false,
    bool Function()? isCancelled,
  }) async {
    _claimTranscriptViewport();
    await _scrollToMessageAndReport(
      messageId,
      pinnedJump: pinnedJump,
      alignment: alignment,
      forceAlignment: forceAlignment,
      isCancelled: isCancelled,
    );
  }

  Future<bool> _scrollToMessageAndReport(
    int messageId, {
    bool pinnedJump = false,
    double? alignment,
    bool forceAlignment = false,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() ?? false) return false;
    if (!mounted) return false;
    setState(() => _setScrollTarget(messageId, forceNavigation: true));
    final navigationGeneration = _scrollTargetGeneration;
    bool targetCancelled() =>
        !_isCurrentScrollTarget(messageId, navigationGeneration) ||
        (isCancelled?.call() ?? false);
    // The target key moves to the requested row during layout. Waiting for
    // that frame prevents an already-loaded jump from reusing the previous
    // pinned row's context.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || targetCancelled()) return false;
    if (_vm.messages.any((m) => m.id == messageId)) {
      return _ensureMessageVisibleAndReport(
        messageId,
        navigationGeneration: navigationGeneration,
        pinnedJump: pinnedJump,
        alignment: alignment,
        forceAlignment: forceAlignment,
        isCancelled: targetCancelled,
      );
    }
    final loaded = await _vm.loadAroundMessage(
      messageId,
      scrollToTarget: false,
      isCancelled: targetCancelled,
    );
    if (!loaded || !mounted || targetCancelled()) return false;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || targetCancelled()) return false;
    return _ensureMessageVisibleAndReport(
      messageId,
      navigationGeneration: navigationGeneration,
      pinnedJump: pinnedJump,
      alignment: alignment,
      forceAlignment: forceAlignment,
      isCancelled: targetCancelled,
    );
  }

  /// A hashtag is already a query over the open chat, so it opens in-chat
  /// search rather than pushing a screen over the transcript it refers to.
  void _openHashtagSearch(String hashtag) {
    final tag = hashtag.trim();
    if (tag.isEmpty) return;
    _openSearch(initialQuery: tag.startsWith('#') ? tag : '#$tag');
  }

  // MARK: - In-chat search

  /// The controller notifies per keystroke, per page and per resolved sender,
  /// and every search surface already AnimatedBuilds on it. `isActive` is the
  /// only value this build reads, so anything else would rebuild the whole
  /// transcript for a repaint that happens elsewhere.
  void _onSearchChanged() {
    final active = _search.isActive;
    if (active == _searchActive) return;
    _searchActive = active;
    if (mounted) setState(() {});
  }

  void _openSearch({String? initialQuery}) {
    if (_isSelecting) _exitSelection();
    _search.open(initialQuery: initialQuery);
  }

  void _closeSearch() {
    if (!_search.isActive) return;
    setState(() => _searchHighlightId = null);
    _search.close();
  }

  /// Moves the transcript to a hit and leaves it marked.
  ///
  /// The alignment sits the message just above centre so the messages around
  /// it — the reason the user searched — are on screen too.
  Future<void> _openSearchResult(
    ChatMessage result, {
    required bool automatic,
  }) async {
    setState(() => _searchHighlightId = result.id);
    // A phone gives up most of its height to the keyboard, so a deliberate
    // jump puts it away — the message asked for should be the thing on screen.
    // A query's own landing must not, or typing would close the keyboard on
    // every pause.
    if (!automatic && !_searchResultsPaneVisible) _search.focusNode.unfocus();
    await _scrollToMessage(
      result.id,
      alignment: 0.38,
      forceAlignment: true,
      // A query's own landing can outlive the query: the history fetch it may
      // need takes longer than the next keystroke. Aborting it beats racing it.
      isCancelled: automatic
          ? () => _search.activeMessageId != result.id
          : null,
    );
  }

  bool _searchUsesResultsPane(double conversationWidth) =>
      _search.isActive &&
      chatSearchUsesResultsPane(
        windowSize: MediaQuery.sizeOf(context),
        conversationWidth: conversationWidth,
      );

  /// [showSteppers] follows the results pane: a wide chat keeps the composer,
  /// so the up/down controls ride in the header beside the field, while a
  /// narrow one gets them in the navigator that replaces the composer.
  Widget _searchHeader({required bool showSteppers}) => ChatSearchHeaderBar(
    controller: _search,
    height: widget.headerHeight,
    backgroundColor: widget.headerColor,
    showDivider: widget.showHeaderDivider,
    showSteppers: showSteppers,
    onClose: _closeSearch,
  );

  Widget _searchResultsPane() => ChatSearchResultsPane(
    controller: _search,
    peerTitle: _vm.peerTitle,
    onSelect: _search.selectResult,
  );

  Widget _searchNavigator() => ChatSearchNavigator(
    controller: _search,
    onShowResults: () => unawaited(
      showChatSearchResultsSheet(
        context: context,
        controller: _search,
        peerTitle: _vm.peerTitle,
        onSelect: _search.selectResult,
      ),
    ),
  );

  Future<void> _ensureMessageVisible(
    int messageId, {
    required int navigationGeneration,
    bool pinnedJump = false,
    bool instant = false,
    double? alignment,
    bool forceAlignment = false,
  }) async {
    await _ensureMessageVisibleAndReport(
      messageId,
      navigationGeneration: navigationGeneration,
      pinnedJump: pinnedJump,
      instant: instant,
      alignment: alignment,
      forceAlignment: forceAlignment,
    );
  }

  Future<bool> _ensureMessageVisibleAndReport(
    int messageId, {
    required int navigationGeneration,
    bool pinnedJump = false,
    bool instant = false,
    double? alignment,
    bool forceAlignment = false,
    bool Function()? isCancelled,
  }) async {
    bool targetCancelled() =>
        !_isCurrentScrollTarget(messageId, navigationGeneration) ||
        (isCancelled?.call() ?? false);

    final targetAlignment =
        alignment ?? (pinnedJump ? pinnedMessageScrollAlignment : 0.3);
    for (var tries = 0; tries < 6; tries++) {
      if (targetCancelled()) return false;
      final activeKey = _targetKey;
      final ctx = activeKey.currentContext;
      if (ctx != null && ctx.mounted) {
        if (pinnedJump && alignment == null && _scroll.hasClients) {
          final aligned = await _alignPinnedMessage(
            messageId,
            navigationGeneration: navigationGeneration,
            instant: instant,
            isCancelled: isCancelled,
          );
          if (aligned && targetCancelled()) {
            return false;
          }
          if (aligned) {
            if (mounted && !targetCancelled()) {
              setState(() => _setScrollTarget(null));
              return true;
            }
            return false;
          }
        }
        // Do not realign a message that is already on screen. Reply, search,
        // and other linked-message jumps used to always force the row to 30%
        // of the viewport, which made an already-visible target bounce.
        if (!forceAlignment && _isKeyMostlyVisible(activeKey)) {
          if (mounted && !targetCancelled()) {
            setState(() => _setScrollTarget(null));
            return true;
          }
          return false;
        }
        if (!mounted || !ctx.mounted || targetCancelled()) return false;
        await Scrollable.ensureVisible(
          ctx,
          alignment: targetAlignment,
          duration: instant
              ? Duration.zero
              : pinnedJump
              ? const Duration(milliseconds: 140)
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        if (mounted && !targetCancelled()) {
          setState(() => _setScrollTarget(null));
          return true;
        }
        return false;
      }
      if (!_scroll.hasClients) return false;
      final estimate = _estimateMessageOffset(messageId, targetAlignment);
      if (estimate != null) _scroll.jumpTo(estimate);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted || targetCancelled()) return false;
    }
    if (mounted && !targetCancelled()) {
      setState(() => _setScrollTarget(null));
    }
    return false;
  }

  /// Aligns a pinned target more than once because media rows can finish a
  /// thumbnail decode while the first scroll animation is still laying out.
  /// The old one-shot calculation consequently landed the containing album a
  /// few pixels above or below the pinned banner, especially on Android.
  Future<bool> _alignPinnedMessage(
    int messageId, {
    required int navigationGeneration,
    required bool instant,
    bool Function()? isCancelled,
  }) async {
    bool targetCancelled() =>
        !_isCurrentScrollTarget(messageId, navigationGeneration) ||
        (isCancelled?.call() ?? false);

    for (var pass = 0; pass < 3; pass++) {
      if (targetCancelled()) return false;
      final activeKey = _targetKey;
      final targetObject = activeKey.currentContext?.findRenderObject();
      final viewportObject = _transcriptViewportKey.currentContext
          ?.findRenderObject();
      if (targetObject is! RenderBox ||
          !targetObject.attached ||
          viewportObject is! RenderBox ||
          !viewportObject.attached ||
          !_scroll.hasClients) {
        return false;
      }
      final target = pinnedMessageTargetScrollOffset(
        _scroll.position,
        targetTop: targetObject.localToGlobal(Offset.zero).dy,
        viewportTop: viewportObject.localToGlobal(Offset.zero).dy,
      );
      if ((target - _scroll.position.pixels).abs() <= 0.5) return true;
      if (instant) {
        _scroll.jumpTo(target);
      } else {
        await _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        );
      }
      if (targetCancelled()) return false;
      await WidgetsBinding.instance.endOfFrame;
      if (targetCancelled()) return false;
    }
    return !targetCancelled();
  }

  bool _isKeyMostlyVisible(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return false;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final viewportObject = _transcriptViewportKey.currentContext
        ?.findRenderObject();
    if (viewportObject is! RenderBox || !viewportObject.attached) return false;
    final targetTop = renderObject.localToGlobal(Offset.zero).dy;
    final targetBottom = targetTop + renderObject.size.height;
    final viewportTop = viewportObject.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportObject.size.height;
    final pinnedOverlayInset =
        !_search.isActive && _vm.pinnedMessage != null && !_vm.pinnedDismissed
        ? pinnedMessageTargetTopInset
        : 0.0;
    // The viewport already excludes the header, bottom composer, keyboard,
    // and safe areas. Comparing against those widgets' assumed heights was the
    // source of false "already visible" results after an Android resize.
    return targetTop >= viewportTop + pinnedOverlayInset - 24 &&
        targetBottom <= viewportBottom + 24;
  }

  Widget _transcript() {
    final groupImages = context.watch<ThemeController>().groupImageMessages;
    final entries = _transcriptEntries(groupImages);
    // Partitioning copies every entry three times over and the index maps hash
    // every row; both are pure functions of the memoized entry list plus the
    // pivot inputs, so they are cached beside it rather than redone per build.
    List<_TranscriptEntry> olderEntries;
    List<_TranscriptEntry> newerEntries;
    if (identical(entries, _sliverCacheEntries) &&
        identical(_transcriptPivot, _sliverCachePivot) &&
        _sliverCacheInitialLoaded == _vm.initialLoaded) {
      olderEntries = _sliverCacheOlderEntries!;
      newerEntries = _sliverCacheNewerEntries!;
    } else {
      final partition = _partitionTranscript(entries);
      // Slivers before `center` grow away from it. Delegate index zero is the
      // child nearest the center, so the chronological older half is reversed.
      olderEntries = partition.beforePivot.reversed.toList(growable: false);
      newerEntries = partition.pivotAndAfter;
      _sliverCacheEntries = entries;
      _sliverCachePivot = _transcriptPivot;
      _sliverCacheInitialLoaded = _vm.initialLoaded;
      _sliverCacheOlderEntries = olderEntries;
      _sliverCacheNewerEntries = newerEntries;
      // No valid leading-item count can be negative, so this forces the index
      // maps below to be rebuilt against the new arms.
      _sliverCacheLeadingItemCount = -1;
    }
    _scheduleTranscriptPivotFreeze();
    final messages = _transcriptCacheMessages ?? _vm.messages;
    final firstContactInfo = _vm.firstContactInfo;
    final firstContactAtCenter =
        firstContactInfo != null &&
        shouldPlaceFirstContactCardAtCenter(
          hasTranscriptEntries: entries.isNotEmpty,
        );
    final firstContactBeforeCenter =
        firstContactInfo != null && !firstContactAtCenter;
    final showOlderLoadingGap = _vm.isLoadingOlder;
    final olderLoadingItemCount = showOlderLoadingGap ? 1 : 0;
    final olderChildCount =
        olderEntries.length +
        (firstContactBeforeCenter ? 1 : 0) +
        olderLoadingItemCount;
    final newerLeadingItemCount = firstContactAtCenter ? 1 : 0;
    if (_sliverCacheLeadingItemCount != newerLeadingItemCount) {
      _sliverCacheLeadingItemCount = newerLeadingItemCount;
      _sliverCacheOlderIndexByKey = <Key, int>{
        for (var i = 0; i < olderEntries.length; i++) olderEntries[i].key: i,
      };
      _sliverCacheNewerIndexByKey = <Key, int>{
        for (var i = 0; i < newerEntries.length; i++)
          newerEntries[i].key: i + newerLeadingItemCount,
      };
    }
    final olderIndexByKey = _sliverCacheOlderIndexByKey!;
    final newerIndexByKey = _sliverCacheNewerIndexByKey!;
    _scheduleUnreadProgressUpdate();
    _scheduleShortFirstContactReveal();
    // No fill of its own: ChatWallpaperBackground already covers this region
    // with the same chatBackground when no wallpaper is set, and a transparent
    // ColoredBox still issues a full-viewport drawRect.
    return NotificationListener<ScrollNotification>(
      onNotification: _onTranscriptScrollNotification,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onTranscriptPointerDown,
        onPointerUp: _onTranscriptPointerEnd,
        onPointerCancel: _onTranscriptPointerEnd,
        child: CustomScrollView(
          key: _transcriptViewportKey,
          controller: _scroll,
          center: _newerTranscriptSliverKey,
          physics: const ClampingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          scrollCacheExtent: ScrollCacheExtent.pixels(
            defaultTargetPlatform == TargetPlatform.android ? 260 : 420,
          ),
          semanticChildCount:
              entries.length + (firstContactInfo == null ? 0 : 1),
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index < olderEntries.length) {
                    return _buildTranscriptEntry(olderEntries[index], messages);
                  }
                  if (firstContactBeforeCenter &&
                      index == olderEntries.length) {
                    return _buildFirstContactCard(firstContactInfo);
                  }
                  if (showOlderLoadingGap) {
                    return _historyLoadingGap('chat-older-history-gap');
                  }
                  return _buildFirstContactCard(firstContactInfo!);
                },
                childCount: olderChildCount,
                // Nothing in the transcript keeps itself alive and there is
                // no SelectableRegion, so the two keep-alive wrappers are
                // dead weight; every row already carries its own
                // RepaintBoundary.
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                findChildIndexCallback: (key) {
                  if (key == const ValueKey('chat-first-contact-card')) {
                    return firstContactBeforeCenter
                        ? olderEntries.length
                        : null;
                  }
                  return olderIndexByKey[key];
                },
                semanticIndexCallback: (_, localIndex) =>
                    olderChildCount - localIndex - 1,
              ),
            ),
            SliverList(
              key: _newerTranscriptSliverKey,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (firstContactAtCenter && index == 0) {
                    return _buildFirstContactCard(firstContactInfo);
                  }
                  return _buildTranscriptEntry(
                    newerEntries[index - newerLeadingItemCount],
                    messages,
                  );
                },
                childCount: newerEntries.length + newerLeadingItemCount,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: false,
                findChildIndexCallback: (key) {
                  if (key == const ValueKey('chat-first-contact-card')) {
                    return firstContactAtCenter ? 0 : null;
                  }
                  return newerIndexByKey[key];
                },
                semanticIndexOffset: olderChildCount,
              ),
            ),
            if (_vm.isLoadingLatest)
              SliverToBoxAdapter(
                child: _historyLoadingGap('chat-latest-history-gap'),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        ),
      ),
    );
  }

  Widget _historyLoadingGap(String key) {
    // The transcript slivers no longer add repaint boundaries, and the spinner
    // repaints continuously — keep it off the sliver's layer.
    return RepaintBoundary(
      key: ValueKey(key),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: SizedBox(
          height: 54,
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.card.withValues(alpha: 0.94),
                shape: BoxShape.circle,
                border: Border.all(color: context.colors.divider, width: 0.5),
              ),
              child: const AppActivityIndicator(size: 17),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFirstContactCard(ChatFirstContactInfo info) {
    return KeyedSubtree(
      key: const ValueKey('chat-first-contact-card'),
      child: RepaintBoundary(
        key: _firstContactLayoutKey,
        child: ChatFirstContactCard(
          info: info,
          title: _vm.peerTitle,
          photo: _vm.peerPhoto,
          onOpenProfile: _openPeerProfile,
        ),
      ),
    );
  }

  bool? _shortFirstContactHistoryFitsViewport() {
    if (_vm.firstContactInfo == null || _vm.messages.isEmpty) return false;
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
      return null;
    }
    if (_transcriptViewportClaimedByUser ||
        _hasTranscriptPointerDown ||
        _autoScrollPolicy.preservesViewport ||
        _maintainSessionScrollAnchor ||
        _scrollTargetId != null) {
      return null;
    }
    if (_vm.anchoredHistory ||
        (_vm.hasOlderHistory && !_olderHistoryExhaustedHint)) {
      return false;
    }
    if (_scroll.position.maxScrollExtent > 24) return false;

    final entries = _transcriptCache;
    final viewportObject = _transcriptViewportKey.currentContext
        ?.findRenderObject();
    final cardObject = _firstContactLayoutKey.currentContext
        ?.findRenderObject();
    final latestObject = entries == null || entries.isEmpty
        ? null
        : _entryVisibilityKeys[entries.last.last.id]?.currentContext
              ?.findRenderObject();
    if (viewportObject is! RenderBox ||
        !viewportObject.attached ||
        cardObject is! RenderBox ||
        !cardObject.attached ||
        latestObject is! RenderBox ||
        !latestObject.attached) {
      return null;
    }

    final cardTop = cardObject.localToGlobal(Offset.zero).dy;
    final latestBottom = latestObject
        .localToGlobal(Offset(0, latestObject.size.height))
        .dy;
    if (latestBottom < cardTop) return null;
    return firstContactHistoryFitsViewport(
      cardTop: cardTop,
      latestBottom: latestBottom,
      viewportExtent: viewportObject.size.height,
    );
  }

  bool _positionShortFirstContactHistoryIfItFits({
    required bool requireAtLatest,
  }) {
    final fits = _shortFirstContactHistoryFitsViewport();
    if (fits != true) {
      if (fits == false) {
        _showingFullyVisibleFirstContactHistory = false;
      }
      return false;
    }
    if (requireAtLatest &&
        !_showingFullyVisibleFirstContactHistory &&
        !isNearLatest(_scroll.position, threshold: 1)) {
      return false;
    }
    _showingFullyVisibleFirstContactHistory = true;
    final target = _scroll.position.minScrollExtent;
    if ((_scroll.position.pixels - target).abs() > 0.5) {
      _scroll.jumpTo(target);
    }
    return true;
  }

  void _scheduleShortFirstContactReveal() {
    if (_shortFirstContactRevealScheduled) return;
    _shortFirstContactRevealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shortFirstContactRevealScheduled = false;
      if (!mounted) return;
      final wasShowing = _showingFullyVisibleFirstContactHistory;
      final positioned = _positionShortFirstContactHistoryIfItFits(
        requireAtLatest: !wasShowing,
      );
      if (wasShowing &&
          !positioned &&
          !_showingFullyVisibleFirstContactHistory &&
          !_hasTranscriptPointerDown &&
          !_transcriptViewportClaimedByUser &&
          !_autoScrollPolicy.preservesViewport) {
        _scheduleScrollToBottom(animated: false);
      }
    });
  }

  Future<void> _openCommunityPreview(MessageCommunityPreview preview) async {
    if (preview.id == 0) return;
    CommunitySummary? summary;
    for (final update in TdClient.shared.latestCommunityUpdates) {
      final raw = update.obj('community');
      if (raw?.int64('id') != preview.id) continue;
      summary = CommunitySummary.fromTd(raw!);
      break;
    }
    summary ??= CommunitySummary(
      id: preview.id,
      name: preview.name,
      haveAccess: true,
      isAdministrator: false,
      canEditChatList: false,
      photo: preview.photo,
    );
    if (summary.name.isEmpty && preview.name.isNotEmpty) {
      summary.name = preview.name;
    }
    summary.photo ??= preview.photo;

    final chats = <ChatSummary>[];
    final viewableChats = <ChatSummary>[];
    try {
      final fullInfo = await TdClient.shared.query(
        communityFullInfoRequest(preview.id),
      );
      for (final peer in fullInfo.objects('peers') ?? const []) {
        final chatId = peer.int64('chat_id');
        if (chatId == null) continue;
        try {
          final chat = TDParse.chat(
            await TdClient.shared.query({
              '@type': 'getChat',
              'chat_id': chatId,
            }),
          );
          if (chat == null) continue;
          if (peer.boolean('can_view_history') == true && chat.order == 0) {
            viewableChats.add(chat);
          } else {
            chats.add(chat);
          }
        } catch (_) {
          // A community peer can disappear while its directory is loading.
        }
      }
    } catch (_) {
      // Bot API accounts expose the event's id and name but no community
      // catalogue endpoint, so their preview opens with the available header.
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      AppPageRoute<void>(
        pageBuilder: (_, _, _) => CommunityView(
          community: summary!,
          chats: chats,
          viewableChats: viewableChats,
          onCollapsedChanged: (collapsed) => summary!.collapsed = collapsed,
        ),
      ),
    );
  }

  Widget _buildTranscriptEntry(
    _TranscriptEntry entry,
    List<ChatMessage> messages,
  ) {
    final message = entry.first;
    final messageIndex = entry.startIndex;
    final isTarget = entry.messages.any((m) => m.id == _scrollTargetId);
    final isPinned = entry.messages.any((m) => m.id == _vm.pinnedMessage?.id);
    final targetMessageId = isTarget
        ? _scrollTargetId
        : isPinned
        ? _vm.pinnedMessage?.id
        : null;
    final targetKey = isTarget
        ? _targetKey
        : isPinned
        ? _pinnedKey
        : null;
    final usesExactMediaTarget = entry.isImageGroup || entry.isDocumentGroup;
    final Widget messageBody;
    if (message.isService) {
      messageBody = message.communityPreview != null
          ? ChatCommunityServiceCard(
              preview: message.communityPreview!,
              label: message.text,
              onView: () =>
                  unawaited(_openCommunityPreview(message.communityPreview!)),
            )
          : message.appearancePreview == null
          ? SystemBanner(text: message.text)
          : ChatAppearanceMessagePreview(
              preview: message.appearancePreview!,
              label: message.text,
              controller: _wallpaperController,
              fallback: SystemBanner(text: message.text),
            );
    } else if (entry.isBlockedRun) {
      messageBody = _blockedMessagePlaceholder(context, entry);
    } else if (entry.isImageGroup) {
      messageBody = _selectionEntry(
        entry,
        _imageGroupBubble(
          entry.messages,
          targetMessageId: targetMessageId,
          targetKey: targetKey,
        ),
      );
    } else if (entry.isDocumentGroup) {
      messageBody = _selectionEntry(
        entry,
        _documentGroupBubble(
          entry,
          targetMessageId: targetMessageId,
          targetKey: targetKey,
        ),
      );
    } else {
      messageBody = _selectionEntry(
        entry,
        _messageBubble(message, messageIndex),
      );
    }
    final positionedMessageBody = usesExactMediaTarget || targetKey == null
        ? messageBody
        : KeyedSubtree(key: targetKey, child: messageBody);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_needsUnreadDivider(messageIndex, messages: messages))
          KeyedSubtree(key: _unreadKey, child: _unreadDivider()),
        if (_needsSeparator(messageIndex, messages: messages))
          TimeSeparator(unix: message.date),
        positionedMessageBody,
      ],
    );
    final visibilityKey = _entryVisibilityKeys.putIfAbsent(
      entry.last.id,
      GlobalKey.new,
    );
    // The visibility key resolved to this RepaintBoundary's render object
    // already; hanging it here drops one wrapper element per row.
    return KeyedSubtree(
      key: entry.key,
      child: RepaintBoundary(
        key: visibilityKey,
        child: _searchHighlight(entry, content),
      ),
    );
  }

  /// Washes the row holding the current search hit. A full-width tint rather
  /// than a bubble outline, so an album or a document run reads as one hit.
  Widget _searchHighlight(_TranscriptEntry entry, Widget content) {
    final highlightId = _searchHighlightId;
    if (highlightId == null) return content;
    final highlighted = entry.messages.any((m) => m.id == highlightId);
    return AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.deliberate),
      curve: AppMotion.standard,
      color: highlighted
          ? AppTheme.brand.withValues(alpha: 0.12)
          : Colors.transparent,
      child: content,
    );
  }

  TranscriptPivotPartition<_TranscriptEntry> _partitionTranscript(
    List<_TranscriptEntry> entries,
  ) {
    if (entries.isEmpty) {
      return const TranscriptPivotPartition<_TranscriptEntry>(
        beforePivot: [],
        pivotAndAfter: [],
      );
    }
    final pivot = resolveTranscriptPivot(
      currentPivot: _transcriptPivot,
      initialWindowLoaded: _vm.initialLoaded,
      firstMessageId: _transcriptOrderId(entries.first.first),
    );
    if (pivot == null) {
      return TranscriptPivotPartition<_TranscriptEntry>(
        beforePivot: const [],
        pivotAndAfter: List<_TranscriptEntry>.unmodifiable(entries),
      );
    }
    final result = partitionTranscriptAtPivot<_TranscriptEntry>(
      entries: entries,
      pivot: pivot,
      messageIdsOf: (entry) => entry.messages.map(_transcriptOrderId),
    );
    _transcriptPivot = pivot;
    return result;
  }

  void _resetTranscriptPivot() {
    _transcriptPivot = null;
    _transcriptPivotFrozen = false;
  }

  void _scheduleTranscriptPivotFreeze() {
    if (_transcriptPivotFreezeScheduled ||
        _transcriptPivotFrozen ||
        !_initialTranscriptReady ||
        _maintainSessionScrollAnchor ||
        _transcriptPivot == null ||
        _transcriptPivot?.cutoffMessageId == _pendingTranscriptOrderId) {
      return;
    }
    _transcriptPivotFreezeScheduled = true;
    final scheduledPivot = _transcriptPivot;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _transcriptPivotFreezeScheduled = false;
      if (!mounted ||
          _transcriptPivotFrozen ||
          _maintainSessionScrollAnchor ||
          !_scroll.hasClients) {
        return;
      }
      if (!identical(scheduledPivot, _transcriptPivot)) {
        _scheduleTranscriptPivotFreeze();
        return;
      }
      if (shouldFreezeTranscriptPivot(
        latestArmIsShort: _isTranscriptShort(),
        canLoadOlder: _vm.canLoadOlder,
      )) {
        _transcriptPivotFrozen = true;
      }
    });
  }

  // The transcript is rebuilt on every view-model notification (send/read/
  // typing/file progress); grouping a few hundred messages each time is
  // avoidable garbage, so entries are memoized on their actual inputs.
  List<_TranscriptEntry>? _transcriptCache;
  List<ChatMessage>? _transcriptCacheMessages;
  bool _transcriptCacheGrouped = false;
  int _transcriptCacheUnreadCount = -1;
  int _transcriptCacheLastReadInboxId = -1;

  // Downstream of the grouping memo: the pivot partition and the two sliver
  // key→index maps. Keyed on the entry-list identity plus everything
  // _partitionTranscript reads, so a cache hit leaves _transcriptPivot correct.
  List<_TranscriptEntry>? _sliverCacheEntries;
  TranscriptPivot? _sliverCachePivot;
  bool _sliverCacheInitialLoaded = false;
  List<_TranscriptEntry>? _sliverCacheOlderEntries;
  List<_TranscriptEntry>? _sliverCacheNewerEntries;
  int _sliverCacheLeadingItemCount = -1;
  Map<Key, int>? _sliverCacheOlderIndexByKey;
  Map<Key, int>? _sliverCacheNewerIndexByKey;

  List<_TranscriptEntry> _transcriptEntries(bool groupImages) {
    final messages = _vm.messages;
    // blockedByUser is only written inside _applyKeywordFilter, which always
    // reassigns `messages` first — so the identity check below already covers
    // blocked-state changes. (A previous per-build Object.hashAll signature
    // over every message re-verified this at O(n) per frame; keep the flag
    // writes behind _applyKeywordFilter or the memo goes stale.)
    final cached = _transcriptCache;
    if (cached != null &&
        identical(_transcriptCacheMessages, messages) &&
        _transcriptCacheGrouped == groupImages &&
        _transcriptCacheUnreadCount == _vm.unreadCount &&
        _transcriptCacheLastReadInboxId == _vm.lastReadInboxId) {
      return cached;
    }
    final entries = groupImages ? _groupedTranscript() : _plainTranscript();
    _transcriptCache = entries;
    _transcriptCacheMessages = messages;
    _transcriptCacheGrouped = groupImages;
    _transcriptCacheUnreadCount = _vm.unreadCount;
    _transcriptCacheLastReadInboxId = _vm.lastReadInboxId;
    // Read in place rather than copied: nothing mutates the map between here
    // and the swap below, and the copy was n-sized on every incoming message.
    final previousVisibilityKeys = _entryVisibilityKeys;
    final nextVisibilityKeys = <int, GlobalKey>{};
    final usedVisibilityKeys = <GlobalKey>{};
    for (final entry in entries) {
      GlobalKey? visibilityKey;
      for (final message in entry.messages.reversed) {
        final candidate = previousVisibilityKeys[message.id];
        if (candidate != null && usedVisibilityKeys.add(candidate)) {
          visibilityKey = candidate;
          break;
        }
      }
      visibilityKey ??= GlobalKey();
      usedVisibilityKeys.add(visibilityKey);
      for (final message in entry.messages) {
        nextVisibilityKeys[message.id] = visibilityKey;
      }
    }
    _entryVisibilityKeys = nextVisibilityKeys;
    _trackedTranscriptEntries = {
      for (final entry in entries) entry.last.id: entry,
    };
    return entries;
  }

  Widget _selectionEntry(_TranscriptEntry entry, Widget child) {
    if (!_isSelecting) return child;
    final selectable = entry.messages.where((m) => !m.isService).toList();
    if (selectable.isEmpty) return child;
    final selectedCount = selectable
        .where((m) => _selectedMessageIds.contains(m.id))
        .length;
    final selected = selectedCount == selectable.length;
    final partiallySelected = selectedCount > 0 && !selected;
    final c = context.colors;
    final rowSelector = GestureDetector(
      key: ValueKey('message-row-selection-${entry.last.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleSelection(selectable),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected || partiallySelected
                ? AppTheme.brand
                : Colors.transparent,
            border: Border.all(
              color: selected || partiallySelected
                  ? AppTheme.brand
                  : c.textTertiary,
              width: selected || partiallySelected ? 0 : 1.4,
            ),
          ),
          child: selected
              ? const AppIcon(HeroAppIcons.check, size: 17, color: Colors.white)
              : partiallySelected
              ? const AppIcon(HeroAppIcons.minus, size: 15, color: Colors.white)
              : null,
        ),
      ),
    );
    return Row(
      children: [
        const SizedBox(width: 8),
        rowSelector,
        entry.isImageGroup
            ? Expanded(child: child)
            : Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _toggleSelection(selectable),
                  child: IgnorePointer(child: child),
                ),
              ),
      ],
    );
  }

  void _showActionMenuForMessage(
    ChatMessage message,
    Rect? rect, [
    MessageActionSource source = MessageActionSource.normal,
  ]) {
    EmojiStore.shared.loadIfNeeded();
    final reactionGeneration = ++_actionReactionAvailabilityGeneration;
    final overlayBox =
        _actionOverlayKey.currentContext?.findRenderObject() as RenderBox?;
    final platform = Theme.of(context).platform;
    final desktop = isDesktopTargetPlatform(platform);
    final usePointer =
        desktop ||
        (!desktop &&
            context.read<ThemeController>().mobileMessageActionMenuStyle ==
                MobileMessageActionMenuStyle.dropdown);
    final globalAnchor = MessageActionMenu.anchorRectForPresentation(
      targetRect: rect,
      pointer: _lastActionPointerGlobalPosition,
      usePointer: usePointer,
    );
    _lastActionPointerGlobalPosition = null;
    final overlayRect = globalAnchor != null && overlayBox?.hasSize == true
        ? MessageActionMenu.rectInOverlay(
            globalAnchor,
            globalToLocal: overlayBox!.globalToLocal,
          )
        : globalAnchor;
    final enableMobileTextSelection =
        !isDesktopTargetPlatform(platform) && !_vm.hasProtectedContent;
    final oldSelectionState = _mobileTextSelectionAreaKey?.currentState;
    setState(() {
      _actionTarget = message;
      _actionRect = overlayRect;
      _mobileTextSelectionAreaKey = enableMobileTextSelection
          ? GlobalKey<SelectionAreaState>()
          : null;
      _mobileTextSelectionMessageId = enableMobileTextSelection
          ? message.id
          : null;
      _mobileTextSelectionActive = false;
      _actionSource = source;
      _reactionExpanded = false;
      _reactionTab = 'standard';
      _actionReactionAvailability = null;
    });
    oldSelectionState?.selectableRegion.clearSelection();
    if (!desktop && !message.isCall) {
      unawaited(
        _loadActionReactionAvailability(message.id, reactionGeneration),
      );
    }
  }

  Future<void> _loadActionReactionAvailability(
    int messageId,
    int generation,
  ) async {
    MessageReactionAvailability? availability;
    try {
      availability = await _vm.messageReactionAvailability(messageId);
    } catch (_) {
      // Fail closed. Offering the global defaults after a failed availability
      // query recreates the exact MESSAGE_REACTION_INVALID bug this gate fixes.
    }
    if (!mounted ||
        !messageReactionAvailabilityResultIsCurrent(
          requestGeneration: generation,
          currentGeneration: _actionReactionAvailabilityGeneration,
          messageId: messageId,
          targetMessageId: _actionTarget?.id,
        )) {
      return;
    }
    setState(() => _actionReactionAvailability = availability);
  }

  void _clearMobileTextSelectionState() {
    final selectionState = _mobileTextSelectionAreaKey?.currentState;
    _mobileTextSelectionAreaKey = null;
    _mobileTextSelectionMessageId = null;
    _mobileTextSelectionActive = false;
    selectionState?.selectableRegion.clearSelection();
  }

  void _syncProtectedContentSelectionState() {
    final selectionState = _mobileTextSelectionAreaKey?.currentState;
    if (!protectedContentRequiresMobileSelectionClear(
      hasProtectedContent: _vm.hasProtectedContent,
      hasSelectionKey: _mobileTextSelectionAreaKey != null,
    )) {
      return;
    }
    _mobileTextSelectionAreaKey = null;
    _mobileTextSelectionMessageId = null;
    _mobileTextSelectionActive = false;
    _actionTarget = null;
    _actionRect = null;
    _lastActionPointerGlobalPosition = null;
    _actionSource = MessageActionSource.normal;
    _reactionExpanded = false;
    selectionState?.selectableRegion.clearSelection();
  }

  void _handleMobileTextSelectionChanged(SelectedContent? content) {
    if (content != null && content.plainText.isNotEmpty) {
      if (_actionTarget != null) {
        setState(() {
          _mobileTextSelectionActive = true;
          _actionTarget = null;
          _actionRect = null;
          _lastActionPointerGlobalPosition = null;
          _actionSource = MessageActionSource.normal;
          _reactionExpanded = false;
        });
      } else {
        _mobileTextSelectionActive = true;
      }
      return;
    }
    if (!_mobileTextSelectionActive) return;
    _mobileTextSelectionActive = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _actionTarget != null) return;
      if (_mobileTextSelectionMessageId != null) {
        setState(() => _mobileTextSelectionMessageId = null);
      }
    });
  }

  void _handleMobileTextSelectionDisposed(
    int messageId,
    GlobalKey<SelectionAreaState> selectionAreaKey,
  ) {
    if (!mounted ||
        _mobileTextSelectionMessageId != messageId ||
        !identical(_mobileTextSelectionAreaKey, selectionAreaKey)) {
      return;
    }
    setState(() {
      _mobileTextSelectionAreaKey = null;
      _mobileTextSelectionMessageId = null;
      _mobileTextSelectionActive = false;
    });
  }

  void _handleChatPointerDown(PointerDownEvent event) {
    _lastActionPointerGlobalPosition = event.position;
    final selectionAreaKey = _mobileTextSelectionAreaKey;
    if (!_mobileTextSelectionActive ||
        selectionAreaKey == null ||
        selectionAreaContainsGlobalTextPosition(
          selectionAreaKey: selectionAreaKey,
          globalPosition: event.position,
        )) {
      return;
    }
    selectionAreaKey.currentState?.selectableRegion.clearSelection();
  }

  List<_TranscriptEntry> _plainTranscript() {
    final messages = _vm.messages;
    final entries = <_TranscriptEntry>[];
    var i = 0;
    while (i < messages.length) {
      final first = messages[i];
      if (!first.blockedByUser) {
        entries.add(_TranscriptEntry([first], i));
        i++;
        continue;
      }
      final run = <ChatMessage>[first];
      final j = blockedMessageRunEnd(
        messages,
        i,
        startsNewSection: (index) =>
            _startsTranscriptPivotSection(messages, index) ||
            _needsSeparator(index, messages: messages) ||
            _needsUnreadDivider(index, messages: messages),
      );
      run.addAll(messages.sublist(i + 1, j));
      entries.add(_TranscriptEntry(run, i));
      i = j;
    }
    return entries;
  }

  List<_TranscriptEntry> _groupedTranscript() {
    final messages = _vm.messages;
    final entries = <_TranscriptEntry>[];
    var i = 0;
    while (i < messages.length) {
      final first = messages[i];
      if (first.blockedByUser) {
        final run = <ChatMessage>[first];
        final j = blockedMessageRunEnd(
          messages,
          i,
          startsNewSection: (index) =>
              _startsTranscriptPivotSection(messages, index) ||
              _needsSeparator(index, messages: messages) ||
              _needsUnreadDivider(index, messages: messages),
        );
        run.addAll(messages.sublist(i + 1, j));
        entries.add(_TranscriptEntry(run, i));
        i = j;
        continue;
      }
      if (chatMediaAlbumKind(first) == null || first.mediaAlbumId == 0) {
        entries.add(_TranscriptEntry([first], i));
        i++;
        continue;
      }

      final group = <ChatMessage>[first];
      var j = i + 1;
      while (j < messages.length) {
        final next = messages[j];
        if (_startsTranscriptPivotSection(messages, j) ||
            _needsSeparator(j, messages: messages) ||
            _needsUnreadDivider(j, messages: messages)) {
          break;
        }
        if (!areMessagesInSameMediaAlbum(group.last, next)) break;
        group.add(next);
        j++;
      }

      entries.add(_TranscriptEntry(group, i));
      i = j;
    }
    return entries;
  }

  bool _startsTranscriptPivotSection(List<ChatMessage> messages, int index) {
    if (index <= 0 || index >= messages.length) return false;
    return startsTranscriptPivotSection(
      pivot: _transcriptPivot,
      previousMessageId: _transcriptOrderId(messages[index - 1]),
      currentMessageId: _transcriptOrderId(messages[index]),
    );
  }

  Widget _documentGroupBubble(
    _TranscriptEntry entry, {
    int? targetMessageId,
    GlobalKey? targetKey,
  }) {
    final owner = _mediaAlbumInteractionOwner(entry.messages);
    final ownerIndex = entry.startIndex + entry.messages.indexOf(owner);
    return _messageBubble(
      owner,
      ownerIndex,
      groupedMedia: entry.messages,
      targetMediaMessageId: targetMessageId,
      targetMediaKey: targetKey,
    );
  }

  ChatMessage _mediaAlbumInteractionOwner(List<ChatMessage> group) {
    return selectMediaAlbumInteractionOwner(group);
  }

  Widget _imageGroupBubble(
    List<ChatMessage> group, {
    int? targetMessageId,
    GlobalKey? targetKey,
  }) {
    ChatMessage? captionMessage;
    for (final message in group) {
      if (message.text.trim().isNotEmpty) {
        captionMessage = message;
        break;
      }
    }
    final mobileSelectionKey =
        !_vm.hasProtectedContent &&
            _mobileTextSelectionMessageId == captionMessage?.id
        ? _mobileTextSelectionAreaKey
        : null;
    return ImageMediaAlbumBubble(
      messages: group,
      peerTitle: _vm.peerTitle,
      peerPhoto: _vm.peerPhoto,
      isGroup: _vm.isGroup,
      meName: _vm.meName,
      mePhoto: _vm.mePhoto,
      hasCustomChatTheme: _hasCustomChatTheme,
      showCommentAttachment: chatTranscriptAllowsCommentAttachment(
        isChannel: _vm.isChannel,
      ),
      channelHasLinkedDiscussion: _vm.hasLinkedDiscussion,
      selecting: _isSelecting,
      selectedMessageIds: _selectedMessageIds,
      outgoingBubbleColor: _effectiveOutgoingColor(),
      outgoingBubbleTextColor: _effectiveOutgoingTextColor(),
      incomingBubbleColor: _effectiveIncomingColor(),
      incomingBubbleTextColor: _effectiveIncomingTextColor(),
      messageColors: _effectiveMessageColors(),
      translationDisplayStyle: _translation.displayStyle,
      showOriginalTranslationMessageIds: _showOriginalTranslationMessageIds,
      onAvatarTap: _openSenderProfile,
      onAvatarLongPress: (message) {
        if (_vm.isGroup && (message.senderName?.isNotEmpty ?? false)) {
          _vm.insertMention(message);
        }
      },
      onOpenForwarded: _openForwardedMessage,
      onOpenImage: _openImage,
      onPlayVideo: _playVideo,
      onEditCaption: (message) => unawaited(_editMessageText(message)),
      onOpenComments: _openMessageComments,
      onLongPress: _showActionMenuForMessage,
      mobileTextSelectionAreaKey: mobileSelectionKey,
      onMobileTextSelectionChanged: _handleMobileTextSelectionChanged,
      onMobileTextSelectionDisposed:
          captionMessage == null || mobileSelectionKey == null
          ? null
          : () => _handleMobileTextSelectionDisposed(
              captionMessage!.id,
              mobileSelectionKey,
            ),
      onToggleSelection: (message) => _toggleSelection([message]),
      onBotCommandTap: _sendCommand,
      onHashtagTap: _openHashtagSearch,
      onMentionTap: _openUserProfile,
      targetMessageId: targetMessageId,
      targetKey: targetKey,
    );
  }

  void _react(String emoji) {
    final target = _actionTarget;
    setState(() {
      _actionTarget = null;
      _actionRect = null;
      _clearMobileTextSelectionState();
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
    });
    if (target != null) {
      unawaited(_sendReaction(() => _vm.addReaction(target.id, emoji)));
    }
  }

  void _reactQuick(QuickReactionChoice reaction) {
    if (reaction.isCustom) {
      _reactCustom(reaction.customEmojiId);
    } else {
      _react(reaction.emoji);
    }
  }

  void _reactCustom(int customEmojiId) {
    final target = _actionTarget;
    setState(() {
      _actionTarget = null;
      _actionRect = null;
      _clearMobileTextSelectionState();
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
    });
    if (target != null) {
      unawaited(
        _sendReaction(() => _vm.addCustomReaction(target.id, customEmojiId)),
      );
    }
  }

  Future<void> _sendReaction(Future<void> Function() send) async {
    try {
      await send();
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<void> _toggleMessageReaction(
    ChatMessage message,
    MessageReaction reaction,
  ) => _sendReaction(() => _vm.toggleReaction(message, reaction));

  Widget _actionMenuOverlay() {
    final overlayBox =
        _actionOverlayKey.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = overlayBox?.hasSize == true
        ? overlayBox!.size
        : MediaQuery.sizeOf(context);
    final safeArea = MediaQuery.paddingOf(context);
    final screenW = screenSize.width;
    final screenH = screenSize.height;
    final topSafe = safeArea.top + 8;
    final bottomSafe = screenH - safeArea.bottom - 8;
    final outgoing = _actionTarget!.isOutgoing;
    final rect = _actionRect;
    final showActionMenu = !_reactionExpanded;
    final desktopMenu = isDesktopTargetPlatform(Theme.of(context).platform);
    final mobileDropdown =
        !desktopMenu &&
        context.watch<ThemeController>().mobileMessageActionMenuStyle ==
            MobileMessageActionMenuStyle.dropdown;
    final verticalMenu = desktopMenu || mobileDropdown;
    final pointerAnchored =
        verticalMenu && rect != null && rect.width == 0 && rect.height == 0;
    final reactionAvailability = _actionReactionAvailability;
    final showReactions = messageActionShowsReactionControls(
      isDesktop: desktopMenu,
      isCall: _actionTarget!.isCall,
      availability: reactionAvailability,
    );
    final actionMenu = MessageActionMenu(
      message: _actionTarget!,
      isPinned: _vm.pinnedMessage?.id == _actionTarget!.id,
      allowForwarding: _vm.canForwardContent,
      allowTranslation: _hasAvailableTranslationOption,
      allowSuggestedPostOffer:
          _vm.isDirectMessagesGroup && !_vm.isAdministeredDirectMessagesGroup,
      source: _actionSource,
      showingOriginalTranslation: _showOriginalTranslationMessageIds.contains(
        _actionTarget!.id,
      ),
      layout: verticalMenu
          ? MessageActionMenuLayout.vertical
          : MessageActionMenuLayout.grid,
      onSelect: (action) => _perform(action, _actionTarget!),
    );

    final reactionH = !showReactions
        ? 0.0
        : _reactionExpanded
        ? 268.0
        : 48.0;
    final menuH = showActionMenu
        ? math.min(
            actionMenu.preferredHeightFor(context),
            math.max(0.0, bottomSafe - topSafe),
          )
        : 0.0;
    const gap = 8.0;
    final menuGap = showActionMenu ? gap : 0.0;

    double reactionTop, menuTop;
    if (rect != null) {
      // Reaction picker stays near the pressed message; the action menu is
      // hidden while the picker is expanded.
      reactionTop = (rect.top - reactionH - gap).clamp(
        topSafe,
        bottomSafe - reactionH,
      );
      menuTop = (verticalMenu ? rect.top : rect.bottom + gap).clamp(
        topSafe,
        bottomSafe - menuH,
      );
    } else {
      reactionTop = (screenH - reactionH - menuH - menuGap) / 2;
      menuTop = reactionTop + reactionH + menuGap;
    }
    final align = outgoing ? Alignment.centerRight : Alignment.centerLeft;
    final verticalMenuWidth = math.min(
      MessageActionMenu.desktopPreferredWidth,
      math.max(0.0, screenW - 20),
    );
    final pointerMenuOrigin = pointerAnchored
        ? MessageActionMenu.verticalOriginForPointer(
            pointer: rect.topLeft,
            viewport: screenSize,
            menuSize: Size(verticalMenuWidth, menuH),
            topSafe: topSafe,
            bottomSafe: bottomSafe,
          )
        : const Offset(10, 0);
    final boundedActionMenu = verticalMenu
        ? SizedBox(width: verticalMenuWidth, height: menuH, child: actionMenu)
        : actionMenu;

    void dismiss() => setState(() {
      _actionTarget = null;
      _actionRect = null;
      _lastActionPointerGlobalPosition = null;
      _clearMobileTextSelectionState();
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
    });

    return Positioned.fill(
      child: ChatActionOverlayGestureLayer(
        selectionAreaKey: _mobileTextSelectionMessageId == null
            ? null
            : _mobileTextSelectionAreaKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('message-action-dismiss-layer'),
                behavior: HitTestBehavior.opaque,
                onTap: dismiss,
                child: const SizedBox.expand(),
              ),
            ),
            // Call logs and other special messages aren't reactable — no +1 bar.
            if (showReactions)
              Positioned(
                top: reactionTop,
                left: 10,
                right: 10,
                child: AnimatedBuilder(
                  animation: EmojiStore.shared,
                  builder: (context, _) {
                    final availability = reactionAvailability!;
                    if (_reactionExpanded) {
                      return Align(
                        alignment: align,
                        child: _expandedReactionPicker(availability),
                      );
                    }
                    final configured = effectiveQuickReactions(
                      context.watch<ThemeController>().quickReactions,
                      allowCustomEmoji:
                          availability.allowArbitraryCustom ||
                          availability.choices.any((choice) => choice.isCustom),
                    );
                    final reactions = availability.quickChoices(configured);
                    return Align(
                      alignment: align,
                      child: QuickReactionBar(
                        reactions: reactions,
                        onReaction: _reactQuick,
                        onExpand: () =>
                            setState(() => _reactionExpanded = true),
                      ),
                    );
                  },
                ),
              ),
            if (showActionMenu)
              Positioned(
                top: pointerAnchored ? pointerMenuOrigin.dy : menuTop,
                left: pointerAnchored ? pointerMenuOrigin.dx : 10,
                right: pointerAnchored ? null : 10,
                child: pointerAnchored
                    ? boundedActionMenu
                    : Align(alignment: align, child: boundedActionMenu),
              ),
          ],
        ),
      ),
    );
  }

  Widget _expandedReactionPicker(MessageReactionAvailability availability) {
    final store = EmojiStore.shared;
    final packs = availability.allowArbitraryCustom
        ? store.customPacks
        : const <CustomEmojiPack>[];
    return Container(
      width: 300,
      height: 268,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(child: _reactionContent(packs, availability)),
          _reactionTabStrip(packs),
        ],
      ),
    );
  }

  Widget _reactionContent(
    List<CustomEmojiPack> packs,
    MessageReactionAvailability availability,
  ) {
    const reactionEmojiSize = 26.0;
    if (_reactionTab != 'standard') {
      final id = int.tryParse(_reactionTab);
      CustomEmojiPack? pack;
      for (final p in packs) {
        if (p.id == id) {
          pack = p;
          break;
        }
      }
      if (pack != null) {
        return GridView.count(
          crossAxisCount: 7,
          padding: const EdgeInsets.all(10),
          children: [
            for (final item in pack.emoji)
              if (item.customEmojiId != 0)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _reactCustom(item.customEmojiId),
                  child: Center(
                    child: CustomEmojiView(
                      id: item.customEmojiId,
                      size: reactionEmojiSize,
                      color: Colors.white,
                    ),
                  ),
                ),
          ],
        );
      }
    }
    return GridView.count(
      crossAxisCount: 7,
      padding: const EdgeInsets.all(10),
      children: [
        for (final reaction in availability.choices)
          GestureDetector(
            key: ValueKey('expanded-reaction-${reaction.storageValue}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _reactQuick(reaction),
            child: Center(
              child: reaction.isCustom
                  ? CustomEmojiView(
                      id: reaction.customEmojiId,
                      size: reactionEmojiSize,
                      color: Colors.white,
                    )
                  : Text(
                      reaction.emoji,
                      style: const TextStyle(fontSize: reactionEmojiSize),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _reactionTabStrip(List packs) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF3A3A3C), width: 0.5)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        children: [
          _reactionTab2(
            'standard',
            const AppIcon(
              HeroAppIcons.solidFaceSmile,
              size: 22,
              color: Colors.white70,
            ),
          ),
          for (final pack in packs)
            _reactionTab2(
              pack.id.toString(),
              pack.emoji.isNotEmpty && pack.emoji.first.customEmojiId != 0
                  ? CustomEmojiView(
                      id: pack.emoji.first.customEmojiId,
                      size: 26,
                      color: Colors.white,
                    )
                  : const AppIcon(
                      HeroAppIcons.objectGroup,
                      size: 20,
                      color: Colors.white70,
                    ),
            ),
          GestureDetector(
            key: const ValueKey('quick-reaction-settings'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                _actionTarget = null;
                _actionRect = null;
                _clearMobileTextSelectionState();
                _reactionExpanded = false;
              });
              Navigator.of(context).push(
                AppPageRoute<void>(
                  pageBuilder: (_, _, _) => const QuickReactionSettingsView(),
                ),
              );
            },
            child: const SizedBox(
              width: 40,
              height: 36,
              child: Center(
                child: AppIcon(
                  HeroAppIcons.gear,
                  size: 21,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reactionTab2(String key, Widget child) {
    final selected = _reactionTab == key;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _reactionTab = key),
      child: Container(
        width: 40,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4A4A4E) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: SizedBox(width: 28, height: 28, child: Center(child: child)),
      ),
    );
  }
}

// Retained as a keyboard-accessible fallback surface for future non-message
// text sources. Mobile messages now use the in-place SelectionArea flow.
// ignore: unused_element
class _MessageTextSelectionDialog extends StatefulWidget {
  const _MessageTextSelectionDialog({
    required this.text,
    required this.onTranslate,
    required this.onAddToBlocklist,
  });

  final String text;
  final Future<String?> Function(String text)? onTranslate;
  final ValueChanged<String> onAddToBlocklist;

  @override
  State<_MessageTextSelectionDialog> createState() =>
      _MessageTextSelectionDialogState();
}

class _ReactionUsersSheet extends StatefulWidget {
  const _ReactionUsersSheet({
    required this.viewModel,
    required this.message,
    required this.initialReaction,
  });

  final ChatViewModel viewModel;
  final ChatMessage message;
  final MessageReaction initialReaction;

  @override
  State<_ReactionUsersSheet> createState() => _ReactionUsersSheetState();
}

class _ReactionUsersSheetState extends State<_ReactionUsersSheet> {
  late MessageReaction _selected;
  final Map<String, Future<List<MessageReactionUser>>> _loads = {};

  @override
  void initState() {
    super.initState();
    final initialKey = _reactionKey(widget.initialReaction);
    _selected = widget.message.reactions.firstWhere(
      (reaction) => _reactionKey(reaction) == initialKey,
      orElse: () => widget.message.reactions.first,
    );
  }

  Future<List<MessageReactionUser>> _load(MessageReaction reaction) {
    final key = _reactionKey(reaction);
    return _loads.putIfAbsent(
      key,
      () => widget.viewModel.reactionUsers(widget.message, reaction),
    );
  }

  String _reactionKey(MessageReaction reaction) => reaction.customEmojiId != 0
      ? 'custom:${reaction.customEmojiId}'
      : 'emoji:${reaction.emoji ?? ''}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ReactionUsersSheetFrame(
      child: Column(
        children: [
          _reactionTabs(c),
          Divider(height: 1, thickness: 0.5, color: c.divider),
          Expanded(child: _reactionUsers(c)),
        ],
      ),
    );
  }

  Widget _reactionTabs(AppColors c) {
    return SizedBox(
      height: 52,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final reaction in widget.message.reactions)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _reactionTab(c, reaction),
              ),
          ],
        ),
      ),
    );
  }

  Widget _reactionTab(AppColors c, MessageReaction reaction) {
    final selected = _reactionKey(reaction) == _reactionKey(_selected);
    final foreground = selected ? Colors.white : c.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selected = reaction),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brand : c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _reactionGlyph(reaction, selected ? Colors.white : c.textSecondary),
            const SizedBox(width: 7),
            Text(
              '${reaction.count}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reactionUsers(AppColors c) {
    return FutureBuilder<List<MessageReactionUser>>(
      future: _load(_selected),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: Text(
              AppStrings.t(AppStringKeys.contactsLoading),
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
          );
        }
        final users = snapshot.data ?? const <MessageReactionUser>[];
        if (users.isEmpty) {
          return Center(
            child: Text(
              AppStrings.t(AppStringKeys.sharedMediaEmpty),
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: users.length,
          itemBuilder: (context, index) => _reactionUserRow(c, users[index]),
        );
      },
    );
  }

  Widget _reactionUserRow(AppColors c, MessageReactionUser user) {
    final time = DateText.listLabel(user.date);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      child: Row(
        children: [
          PhotoAvatar(title: user.title, photo: user.photo, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 17, color: c.textPrimary),
            ),
          ),
          if (time.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(time, style: TextStyle(fontSize: 12, color: c.textTertiary)),
          ],
        ],
      ),
    );
  }

  Widget _reactionGlyph(MessageReaction reaction, Color color) {
    if (reaction.customEmojiId != 0) {
      return CustomEmojiView(
        id: reaction.customEmojiId,
        size: 18,
        color: color,
      );
    }
    return Text(reaction.emoji ?? '', style: const TextStyle(fontSize: 16));
  }
}

class _MessageTextSelectionDialogState
    extends State<_MessageTextSelectionDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  String? _translation;
  bool _translating = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _selectedText {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) {
      return _controller.text.trim();
    }
    return selection.textInside(_controller.text).trim();
  }

  void _copySelection() {
    final selected = _selectedText;
    if (selected.isEmpty) return;
    Clipboard.setData(ClipboardData(text: selected));
    showToast(context, AppStringKeys.topicPostContentCopied);
  }

  Future<void> _translateSelection() async {
    final selected = _selectedText;
    final translate = widget.onTranslate;
    if (selected.isEmpty || _translating || translate == null) return;
    setState(() => _translating = true);
    final translated = await translate(selected);
    if (!mounted) return;
    setState(() {
      final isEmpty = translated == null || translated.trim().isEmpty;
      _translation = isEmpty ? null : translated;
      _translating = false;
    });
  }

  void _addSelectionToBlocklist() {
    final selected = _selectedText;
    if (selected.isEmpty) return;
    widget.onAddToBlocklist(selected);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final screen = MediaQuery.sizeOf(context);
    return SafeArea(
      child: Material(
        type: MaterialType.transparency,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: screen.height * 0.72,
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.divider, width: 0.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 12, 13),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppStringKeys.messageActionSelectText.l10n(
                                context,
                              ),
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(context).pop(),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: AppIcon(
                                HeroAppIcons.xmark,
                                color: c.textSecondary,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 0.5, color: c.divider),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 22, 28, 20),
                        child: Scrollbar(
                          child: SingleChildScrollView(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              readOnly: true,
                              autofocus: true,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              contextMenuBuilder: (_, _) =>
                                  const SizedBox.shrink(),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isCollapsed: true,
                              ),
                              style: TextStyle(
                                fontSize: 32,
                                height: 1.35,
                                color: c.textPrimary,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_translation != null) ...[
                      Container(height: 0.5, color: c.divider),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 132),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(28, 16, 28, 16),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SelectableText(
                              _translation!,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 17,
                                height: 1.4,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    Container(height: 0.5, color: c.divider),
                    SizedBox(
                      height: 76,
                      child: Row(
                        children: [
                          Expanded(
                            child: _TextSelectionAction(
                              icon: HeroAppIcons.file,
                              label: AppStringKeys.messageActionCopy,
                              onTap: _copySelection,
                            ),
                          ),
                          if (widget.onTranslate != null)
                            Expanded(
                              child: _TextSelectionAction(
                                icon: HeroAppIcons.language,
                                label: AppStringKeys.messageActionTranslate,
                                onTap: _translating
                                    ? null
                                    : _translateSelection,
                              ),
                            ),
                          Expanded(
                            child: _TextSelectionAction(
                              icon: HeroAppIcons.filter,
                              label: AppStringKeys.messageActionBlockKeyword,
                              onTap: _addSelectionToBlocklist,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextSelectionAction extends StatelessWidget {
  const _TextSelectionAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    final color = enabled ? c.textPrimary : c.textTertiary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(icon, size: 22, color: color),
          const SizedBox(height: 7),
          Text(
            label.l10n(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}
