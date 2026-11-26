//
//  chat_view.dart
//
//  The conversation screen. A gray canvas hosting a scrolling transcript of
//  bubbles, time separators and system banners, with a flat header and a pinned
//  input bar. Backed by ChatViewModel. Port of the Swift `ChatView`.
//

import 'dart:async';
import 'dart:io';
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
import '../app/app_navigator.dart';
import '../app/chat_deep_link_controller.dart';
import '../app/chat_pane.dart';
import '../app/desktop/desktop_video_window.dart';
import '../app/ipad_window_chrome.dart';
import '../app/primary_chat_launcher.dart';
import '../app/top_corner_cluster.dart';
import '../app/video_split_controller.dart';
import '../auth/account_store.dart';
import '../auth/telegram_country_names.dart';
import '../call/call_manager.dart';
import '../channels/topic_list_actions.dart';
import '../channels/topic_list_host.dart';
import '../channels/topic_list_row.dart';
import '../channels/topic_navigation.dart';
import '../chats/chat_list_view.dart';
import '../chats/search_token_views.dart';
import '../communities/community_models.dart';
import '../communities/community_view.dart';
import '../components/app_anchored_menu.dart';
import '../components/app_confirm_dialog.dart';
import '../components/app_dialog.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/app_press_ripple.dart';
import '../components/confirm_dialog.dart';
import '../components/full_page_back_swipe.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../config/build_flags.dart';
import '../history/message_history_revision_view.dart';
import '../history/message_history_settings.dart';
import '../history/message_history_store.dart';
import '../media/app_asset_picker.dart';
import '../media/media_metadata.dart';
import '../moments/moments_view.dart' show ChannelMomentsView;
import '../moments/story_viewer_view.dart';
import '../notifications/notification_controller.dart';
import '../platform/desktop_clipboard_images.dart';
import '../profile/profile_detail_view.dart';
import '../settings/ai_translation/ai_endpoint_style.dart';
import '../settings/ai_translation/ai_settings_controller.dart';
import '../settings/ai_translation/apple_pcc_api.dart';
import '../settings/ai_translation/translation_api.dart';
import '../settings/ai_translation/translation_controller.dart';
import '../settings/business/business_tools_views.dart';
import '../settings/privacy_security/blocked_user_service.dart';
import '../settings/privacy_security/hidden_sender_store.dart';
import '../settings/privacy_security/sensitive_content_controller.dart';
import '../settings/quick_reaction_settings_view.dart';
import '../tdlib/forum_topic_index.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../tdlib/td_requests.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/content_size.dart';
import '../theme/date_text.dart';
import '../theme/telegram_cloud_theme.dart';
import '../theme/theme_controller.dart';
import 'admin/channel_direct_messages_service.dart';
import 'admin/channel_direct_messages_view.dart';
import 'admin/chat_info_view.dart';
import 'admin/group_remark_controller.dart';
import 'ai_translation/ai_chat_translation_service.dart';
import 'ai_translation/apple_pcc_unread_summary_provider.dart';
import 'ai_translation/auto_translate_policy.dart';
import 'ai_translation/chat_translation_panel.dart';
import 'ai_translation/message_translation_cache.dart';
import 'ai_translation/openai_compatible_unread_summary_provider.dart';
import 'ai_translation/telegram_ai_service.dart';
import 'ai_translation/telegram_cocoon_unread_summary_provider.dart';
import 'ai_translation/translation_fallback.dart';
import 'ai_translation/unread_chat_summary_models.dart';
import 'ai_translation/unread_chat_summary_service.dart';
import 'ai_translation/unread_chat_summary_view.dart';
import 'appearance/chat_appearance_message_preview.dart';
import 'appearance/chat_wallpaper.dart';
import 'channel_bottom_panel.dart';
import 'chat_auto_scroll_policy.dart';
import 'chat_first_contact_card.dart';
import 'chat_first_contact_info.dart';
import 'chat_frame_scheduler.dart';
import 'chat_message_merge.dart';
import 'chat_open_performance.dart';
import 'chat_picker_view.dart';
import 'chat_return_to_latest_coordinator.dart';
import 'chat_scroll_metrics.dart';
import 'chat_send_failure.dart';
import 'chat_session_cache.dart';
import 'chat_unread_progress.dart';
import 'chat_view_model.dart';
import 'composer/chat_input_bar.dart';
import 'composer/chat_media_drop_region.dart';
import 'composer/checklist_composer_view.dart';
import 'composer/media_send_preview_view.dart';
import 'composer/outgoing_attachment.dart';
import 'composer_reply_options_sheet.dart';
import 'forum_topic_transcript.dart';
import 'forward_handoff.dart';
import 'forward_options_sheet.dart';
import 'links_search/chat_message_search_bar.dart';
import 'links_search/chat_message_search_controller.dart';
import 'links_search/internal_chat_link_router.dart';
import 'links_search/link_handler.dart';
import 'media/image_preview.dart';
import 'media/media_download_service.dart';
import 'media/media_library_saver.dart';
import 'media/music_player_controller.dart';
import 'media/video_playback_queue.dart';
import 'media/video_player_view.dart';
import 'messages/blocked_message_runs.dart';
import 'messages/chat_community_service_card.dart';
import 'messages/forward_markdown.dart';
import 'messages/forward_options.dart';
import 'messages/hide_sender_dialog.dart';
import 'messages/image_media_album_bubble.dart';
import 'messages/media_album_layout.dart';
import 'messages/media_spoiler.dart';
import 'messages/message_action_menu.dart';
import 'messages/message_action_menu_presentation.dart';
import 'messages/message_bubble.dart';
import 'messages/message_bubble_repository_view.dart';
import 'messages/message_quote_selection_dialog.dart';
import 'messages/message_reaction_availability.dart';
import 'messages/message_replies_sheet.dart';
import 'messages/message_swipe_reply.dart';
import 'messages/message_text_quote.dart';
import 'messages/poll_results_view.dart';
import 'messages/quick_reaction_choice.dart';
import 'messages/shared_contact_sheet.dart';
import 'mini_apps/bot_api_access_warning.dart';
import 'mini_apps/telegram_mini_app_view.dart';
import 'protected_forward.dart';
import 'stickers/custom_emoji.dart';
import 'stickers/emoji_store.dart';
import 'stickers/sticker_set_detail_view.dart';
import 'stickers/sticker_viewer.dart';
import 'transcript_entry_boundary.dart';
import 'transcript_pivot_partition.dart';

part 'chat_view_actions_moderation.dart';
part 'chat_view_chrome_topics_search.dart';
part 'chat_view_dialogs.dart';
part 'chat_view_scroll_session.dart';
part 'chat_view_transcript_overlay.dart';
part 'chat_view_translation_summary.dart';

@visibleForTesting
bool chatTranscriptAllowsCommentAttachment({required bool isChannel}) =>
    isChannel;

@visibleForTesting
bool chatViewRequiresFullSync({
  required int previousRevision,
  required int nextRevision,
}) => previousRevision != nextRevision;

/// Whether a model notification should still synchronize the transcript.
///
/// A covered transcript defers until its tickers come back. One that has already
/// captured its exit state is only animating out, and its own exit work is what
/// notifies the model: marking the conversation read notifies once, then the
/// local `updateChatReadInbox` it emits notifies again, so both land inside the
/// closing transition. Synchronizing there walks the transcript and rebuilds a
/// page nobody will see again, which is the stutter behind closing a chat.
@visibleForTesting
bool chatViewSyncsModelNotification({
  required bool viewTickerEnabled,
  required bool exitStatePrepared,
}) => viewTickerEnabled && !exitStatePrepared;

/// Rebuilds a narrow chat fragment only while its route is active. Hidden
/// split-view/tab routes deliberately detach from high-frequency TDLib bubble
/// and header updates; their next TickerMode build reads the latest model.
class _ActiveChatListenableBuilder extends StatefulWidget {
  const _ActiveChatListenableBuilder({
    required this.listenable,
    required this.builder,
  });

  final Listenable listenable;
  final WidgetBuilder builder;

  @override
  State<_ActiveChatListenableBuilder> createState() =>
      _ActiveChatListenableBuilderState();
}

class _ActiveChatListenableBuilderState
    extends State<_ActiveChatListenableBuilder> {
  bool _listening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setListening(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(covariant _ActiveChatListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_listening && !identical(oldWidget.listenable, widget.listenable)) {
      oldWidget.listenable.removeListener(_handleChange);
      widget.listenable.addListener(_handleChange);
    }
  }

  void _setListening(bool value) {
    if (_listening == value) return;
    _listening = value;
    if (value) {
      widget.listenable.addListener(_handleChange);
    } else {
      widget.listenable.removeListener(_handleChange);
    }
  }

  void _handleChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);

  @override
  void dispose() {
    if (_listening) widget.listenable.removeListener(_handleChange);
    super.dispose();
  }
}

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

/// Lets an adaptive parent ask the transcript it already shows to reveal the
/// newest message.
///
/// Tapping the conversation that is already open in the split pane has nothing
/// to navigate to, so it has to mean "take me to the latest message" instead of
/// rebuilding the same pane and leaving the reader wherever they had scrolled.
class ChatRevealLatestController {
  VoidCallback? _revealLatest;

  /// Registers the currently visible chat and returns a matching detacher.
  VoidCallback register(VoidCallback revealLatest) {
    _revealLatest = revealLatest;
    return () {
      if (identical(_revealLatest, revealLatest)) _revealLatest = null;
    };
  }

  void revealLatest() => _revealLatest?.call();
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
    this.onTrailingPaneToggle,
  });

  final Widget header;
  final Widget body;
  final Widget? trailingPane;
  final double trailingPaneWidth;

  /// Shows [ChatTrailingPaneEdgeTab] on the pane's leading edge (or the
  /// conversation's trailing edge while the pane is closed) when set.
  final VoidCallback? onTrailingPaneToggle;

  @override
  Widget build(BuildContext context) {
    final pane = trailingPane;
    final paneShown = pane != null && trailingPaneWidth > 0;
    final onToggle = onTrailingPaneToggle;
    // One Row and one Stack whether or not the pane is open, so toggling it
    // keeps the transcript's element (and its scroll position) in place.
    return Column(
      children: [
        KeyedSubtree(key: const ValueKey('chatFullWidthHeader'), child: header),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: KeyedSubtree(
                      key: const ValueKey('chatConversationContent'),
                      child: body,
                    ),
                  ),
                  if (paneShown) ...[
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
                ],
              ),
              if (onToggle != null)
                // The tab's flat edge lies on the divider, so it reads as a
                // grip of the pane; it takes no width from either side.
                PositionedDirectional(
                  end: paneShown ? trailingPaneWidth : 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: ChatTrailingPaneEdgeTab(
                      paneShown: paneShown,
                      onTap: onToggle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A narrow tab that opens and closes the trailing context pane. The visible
/// grip is [visualWidth] × [visualHeight] with its start corners rounded; the
/// hit target extends [hitWidth] × [hitHeight] into the conversation.
@visibleForTesting
class ChatTrailingPaneEdgeTab extends StatelessWidget {
  const ChatTrailingPaneEdgeTab({
    super.key = const ValueKey('chatTrailingPaneEdgeTab'),
    required this.paneShown,
    required this.onTap,
  });

  static const double visualWidth = 16;
  static const double visualHeight = 56;
  static const double hitWidth = 44;
  static const double hitHeight = 64;

  final bool paneShown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AppInteractiveSurface(
      semanticLabel:
          (paneShown
                  ? AppStringKeys.chatContextPaneHide
                  : AppStringKeys.chatContextPaneShow)
              .l10n(context),
      expanded: paneShown,
      isButton: true,
      showHover: false,
      onTap: onTap,
      borderRadius: const BorderRadiusDirectional.horizontal(
        start: Radius.circular(AppRadius.control),
      ),
      child: SizedBox(
        width: hitWidth,
        height: hitHeight,
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Container(
            key: const ValueKey('chatTrailingPaneEdgeTabGrip'),
            width: visualWidth,
            height: visualHeight,
            decoration: BoxDecoration(
              // Card, not the pane's own fill: that is within a shade of the
              // conversation canvas in the light palette.
              color: c.card,
              border: Border.all(color: c.divider),
              borderRadius: const BorderRadiusDirectional.horizontal(
                start: Radius.circular(AppRadius.control),
              ),
            ),
            alignment: Alignment.center,
            // Points the way the pane will move: toward the edge to close it,
            // back out to open it.
            child: AnimatedRotation(
              turns: paneShown ? 0 : 0.5,
              duration: AppMotion.duration(context, AppMotion.responsive),
              curve: AppMotion.standard,
              child: AppIcon(
                rtl ? HeroAppIcons.chevronLeft : HeroAppIcons.chevronRight,
                size: AppIconSize.xs,
                color: c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.chatId,
    required this.title,
    this.forumTopicId,
    this.initialMessageId,
    this.seedMessage,
    this.externalReplyHandoff,
    this.forwardHandoff,
    this.showBackButton = true,
    this.headerHeight = 48,
    this.headerColor,
    this.showHeaderDivider = true,
    this.headerBottom,
    this.headerBottomHeight = 44,
    this.trailingPane,
    this.trailingPaneWidth = 0,
    this.onTrailingPaneToggle,
    this.requestComposerFocusOnReady = false,
    this.onOpenTopicTranscript,
    this.onChatKindResolved,
    this.onInfoPressed,
    this.onOpenFullInfo,
    this.onOpenUserProfile,
    this.onBack,
    this.exitController,
    this.revealLatestController,
  });
  final int chatId;
  final String title;

  /// When set, the transcript renders this single forum topic as an ordinary
  /// chat (topics always fold into the chat transcript now).
  final int? forumTopicId;
  final int? initialMessageId;
  final ChatMessage? seedMessage;

  /// A reply carried over from another chat (see
  /// `ComposerReplyOptionsSheet`'s reply-in-another-chat entry). The
  /// composer starts with this cross-chat reply pending.
  final ExternalReplyHandoff? externalReplyHandoff;

  /// A forward carried over from the picking chat (forward-to-chat). The
  /// composer starts with this forward pending as a reply-style preview.
  final ForwardMessagesHandoff? forwardHandoff;
  final bool showBackButton;

  /// Minimum toolbar height; accessible title/status text can grow it.
  final double headerHeight;
  final Color? headerColor;
  final bool showHeaderDivider;
  final Widget? headerBottom;
  final double headerBottomHeight;
  final Widget? trailingPane;
  final double trailingPaneWidth;

  /// Opens or closes [trailingPane] from a tab on its edge. Set only while
  /// the owner can actually show the pane beside this chat.
  final VoidCallback? onTrailingPaneToggle;
  final bool requestComposerFocusOnReady;

  /// Lets an owning shell switch this chat to a topic transcript (or the
  /// whole chat for null), so the new transcript is built with the shell's
  /// current wiring.
  final ValueChanged<int?>? onOpenTopicTranscript;
  final ValueChanged<ChatKind>? onChatKindResolved;
  final VoidCallback? onInfoPressed;
  final VoidCallback? onOpenFullInfo;
  final void Function(int userId, String name)? onOpenUserProfile;
  final VoidCallback? onBack;
  final ChatViewExitController? exitController;

  /// Lets an owning shell ask this transcript — the one already on screen — to
  /// show its newest message.
  final ChatRevealLatestController? revealLatestController;

  @override
  State<ChatView> createState() => _ChatViewState();
}

/// Drops reusable transcript and scroll snapshots after an OS memory warning.
/// The active chat owns its own view model and is not affected.
void clearChatMemoryCaches() {
  _ChatViewState._sessionCache.clear();
  _ChatViewState._sessionScrollSnapshots.clear();
}

/// Seeds the transcript cache a [ChatView] restores from on open, for tests.
@visibleForTesting
void seedChatSessionCacheForTesting({
  required int accountSlot,
  required int chatId,
  int? forumTopicId,
  required List<ChatMessage> messages,
  required bool anchoredHistory,
}) {
  _ChatViewState._sessionCache.store(
    accountSlot: accountSlot,
    chatId: chatId,
    forumTopicId: forumTopicId,
    messages: messages,
    anchoredHistory: anchoredHistory,
  );
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
    this.isChannel = false,
  });

  final ValueChanged<bool> onStartCall;
  final VoidCallback? onToggleContext;
  final VoidCallback onOpenFullInfo;
  final bool showCallActions;
  final bool isChannel;

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
          label:
              (isChannel
                      ? AppStringKeys.chatInfoChannelAnnouncement
                      : AppStringKeys.chatInfoGroupAnnouncement)
                  .l10n(context),
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
        width: math.max(44, AppMetric.hitTarget),
        height: math.max(44, AppMetric.hitTarget),
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

/// Where the reader was standing when an in-transcript jump (a reply quote tap
/// or View in Chat) took them to another message. While this is live the
/// floating arrow returns here instead of the newest message.
class _ChatJumpOrigin {
  const _ChatJumpOrigin({
    required this.messageId,
    required this.viewportOffset,
  });

  /// Topmost fully visible row (or the closest partially visible one above it)
  /// at the moment the jump was requested.
  final int messageId;

  /// That row's top in viewport-local pixels, restored as-is on return.
  final double viewportOffset;
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
  void _updateState(VoidCallback fn) => setState(fn);

  late final bool _openAtLatest;
  late final ({int accountSlot, int chatId, int? forumTopicId}) _sessionKey;
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

  final Map<int, RenderBox> _mountedTranscriptEntries = {};

  bool _bottomGapCorrectionScheduled = false;
  TranscriptPivot? _transcriptPivot;

  bool _transcriptPivotFrozen = false;

  bool _transcriptPivotFreezeScheduled = false;
  late int _historyWindowRevision;
  late int _historyWindowInvalidationRevision;
  late int _fullViewRevision;

  final Set<int> _expandedBlockedRunIds = <int>{};

  final Set<int> _showOriginalTranslationMessageIds = <int>{};
  int? _desktopStickerSetId;

  bool _unreadProgressUpdateScheduled = false;

  bool _viewTickerEnabled = true;

  bool _modelDirtyWhileInactive = false;

  bool _reactivationSyncScheduled = false;
  ChatMessage? _actionTarget;
  int? _desktopQuoteMessageId;
  MessageTextQuote? _desktopQuote;
  MessageTextQuote? _actionQuote;
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

  // The message a reaction from the open menu lands on: the album's

  // interaction owner when the menu was opened on an album member.
  int? _actionReactionMessageId;

  int _actionReactionAvailabilityGeneration = 0;
  bool? _actionMessageLinkAvailable;
  bool? _actionCanReply;

  int _actionPropertiesGeneration = 0;
  Offset?
  _actionAnchor; // overlay-space point the HUD grows from / collapses to
  Widget? _actionOverlaySnapshot; // last visible overlay, replayed during exit

  int _lastCount = 0;

  bool _didInitialScroll = false; // one-time entry positioning has run

  bool _showJumpDown = false; // scrolled up → show jump-to-bottom button

  bool _bannerDismissed = false; // "N条新消息" banner dismissed / caught up
  Timer? _bannerTimer; // auto-hides the banner a few seconds after it appears
  Timer? _readSyncTimer;
  Timer? _handoffUpdateTimer;
  Timer? _linkedMessageHighlightFadeTimer;
  Timer? _linkedMessageHighlightClearTimer;
  int? _scrollTargetId;

  int _scrollTargetGeneration = 0;

  /// See [_ChatJumpOrigin]. Live from the moment a reply/View in Chat jump

  /// starts until the arrow consumes it, the user drags the transcript away

  /// from the jump target, or the session ends.
  _ChatJumpOrigin? _jumpOrigin;

  // Unlike the target generation, this survives a successful target clear so

  // post-layout corrections can still be cancelled by a newer user intent.

  int _jumpOriginReturnGeneration = 0;

  /// Scroll offset when the drag that may abandon [_jumpOrigin] began. Null

  /// outside such a drag, so programmatic scrolls cannot measure against it.
  double? _jumpOriginDragBaseline;

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
  int? _linkedMessageHighlightId;

  bool _linkedMessageHighlightActive = false;

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

  bool _openingUnreadReaction = false;

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

  /// Bot API access warning dismissal, keyed by chat so a topic switch does

  /// not re-show a warning the user already dismissed in another topic.

  static final Map<int, int> _dismissedBotApiWarningByChat = {};
  VoidCallback? _detachExitController;
  VoidCallback? _detachRevealLatestController;
  VoidCallback? _detachPaneBackHandler;

  final ChatSessionCacheWriteGate _sessionCacheWriteGate =
      ChatSessionCacheWriteGate();

  /// Gap (seconds) between messages that triggers a fresh time separator.

  static const _separatorGap = 300;

  static const _initialTargetAlignment = 0.30;

  static const _initialUnreadAlignment = 0.12;

  static const _pendingTranscriptOrderId = 0x7FFFFFFFFFFFFFFF;
  static final Map<
    ({int accountSlot, int chatId, int? forumTopicId}),
    _ChatScrollSnapshot
  >
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
    _detachRevealLatestController = widget.revealLatestController?.register(
      _onRevealLatestRequested,
    );
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
      forumTopicId: widget.forumTopicId,
    );
    _sessionRenderState = widget.initialMessageId == null
        ? _sessionCache.read(
            accountSlot: _sessionKey.accountSlot,
            chatId: _sessionKey.chatId,
            forumTopicId: _sessionKey.forumTopicId,
          )
        : null;
    // A topic switch rebuilds this transcript; restore the chat-level
    // language-detection result so the translation panel does not hide on
    // the first frame and pop open a beat later.
    final headerSnapshot = ChatHeaderStateCache.read(
      _sessionKey.accountSlot,
      _sessionKey.chatId,
    );
    if (headerSnapshot != null &&
        headerSnapshot.chatLanguageDetectionComplete) {
      _detectedChatLanguage = headerSnapshot.detectedChatLanguage;
      _chatLanguageDetectionComplete = true;
      _chatLanguageDetectedAt = headerSnapshot.chatLanguageDetectedAt;
      _chatLanguageDetectionNewestMessageId =
          headerSnapshot.chatLanguageDetectionNewestMessageId;
    }
    _dismissedBotApiWarningMask = _dismissedBotApiWarningByChat[widget.chatId];
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
      forumTopicId: widget.forumTopicId,
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
    _fullViewRevision = _vm.fullViewRevision;
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
    _vm.addListener(_publishTopicList);
    _setScrollTarget(widget.initialMessageId);
    _adoptExternalReplyHandoff();
    _adoptForwardHandoff();
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
    if (oldWidget.chatId != widget.chatId ||
        oldWidget.forumTopicId != widget.forumTopicId) {
      // A switch to another conversation or topic invalidates every recorded
      // reading position, this one included.
      _forgetJumpOrigin();
    }
    if (!identical(oldWidget.exitController, widget.exitController)) {
      _detachExitController?.call();
      _detachExitController = widget.exitController?.register(
        _prepareExitState,
      );
    }
    if (!identical(
      oldWidget.revealLatestController,
      widget.revealLatestController,
    )) {
      _detachRevealLatestController?.call();
      _detachRevealLatestController = widget.revealLatestController?.register(
        _onRevealLatestRequested,
      );
    }
  }

  /// Whether this chat's topics are known — resolved live or seeded from the

  /// process-wide index — so a pane rebuilt for another topic keeps its rail

  /// instead of flashing an "All"-only strip until getChat resolves.

  bool get _topicsKnown =>
      _vm.supportsTopics ||
      ForumTopicIndex.shared.knowsTopics(
        _sessionKey.accountSlot,
        widget.chatId,
      );

  // The split shell's topic-list relay: while this transcript lives in a

  // sidebar-placement shell, its topic list is handed to the shell, which

  // overlays it on the chat list column the way Telegram iOS does. The shell

  // owns that pane, so topic switches keep its scroll position.
  TopicListHost? _shellTopicListHost;
  TopicListAttachment? _publishedAttachment;

  bool _topicListOverlaid = false;

  /// Wide split shells overlay this transcript's topic list on the chat list

  /// column, so the in-pane rail stays out of the conversation there.

  void _syncTopicListHostScope() {
    _shellTopicListHost =
        TopicListPlacementScope.of(context) == TopicListPlacement.sidebar
        ? context.read<TopicListHost?>()
        : null;
  }

  /// Publishes (or retracts) this transcript's topic list with the shell's

  /// relay. Publishing an unchanged list is a no-op, so the shell's pane —

  /// and its scroll position — survives every topic switch.

  void _publishTopicList() {
    if (!mounted) return;
    final host = _shellTopicListHost;
    // Forums hand their topic list to the shell the way Telegram iOS does;
    // bot-topic chats keep the in-pane rail they already had. A pane rebuilt
    // for another topic of the same forum inherits the outgoing attachment's
    // verdict, because its fresh view model only learns isForum after an
    // async getChat — without the handoff the shell would drop the overlay
    // mid-switch and lose the pane's scroll. A fresh pane for a chat whose
    // topics the shared index already knows is equally a forum: the index
    // only fills from forum topic traffic, so it is evidence enough to keep
    // the list on the chat list column while getChat is still in flight.
    final prior = host?.attachment;
    final takesOverForumList = prior?.chatId == widget.chatId;
    final indexKnowsTopics = ForumTopicIndex.shared.knowsTopics(
      _vm.accountSlot,
      widget.chatId,
    );
    final overlaid =
        host != null &&
        (takesOverForumList || _vm.isForum || indexKnowsTopics) &&
        !_vm.hasForumTabs;
    _topicListOverlaid = overlaid;
    final attachment = overlaid ? _topicListAttachment() : null;
    final previous = _publishedAttachment;
    if (attachment != null &&
        previous != null &&
        previous.sameContent(attachment)) {
      return;
    }
    _publishedAttachment = attachment;
    // The shell's sidebar listens to the host; publishing mid-build would
    // mark an already-built ancestor dirty.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attachment != null) {
        if (mounted) host?.publish(attachment);
        return;
      }
      if (previous != null) host?.unpublish(previous);
    });
  }

  TopicListAttachment _topicListAttachment() => TopicListAttachment(
    chatId: widget.chatId,
    title: _vm.peerTitle.isEmpty ? widget.title : _vm.peerTitle,
    usesSquareAvatar: _vm.isGroup || _vm.isChannel,
    photo: _vm.peerPhoto,
    topics: _topicListRows(),
    selectedTopicId: widget.forumTopicId,
    onSelect: _openTopicTranscript,
    onCreateTopic: _vm.canCreateForumTopics ? _openCreateTopicDialog : null,
    onMarkAllRead: _hasUnreadTopics ? _markAllTopicsRead : null,
    onTopicMenu: _showTopicRowMenu,
  );

  bool get _hasUnreadTopics =>
      _vm.forumTopics.any((topic) => topic.unreadCount > 0);

  /// The rows handed to the shell. A pane rebuilt for another topic seeds

  /// from the shared index first, which knows identities and counters but

  /// not previews; the rows already published for this chat fill those in so

  /// the overlay never flashes to bare rows mid-switch.

  List<TopicNavigationItem> _topicListRows() {
    final prior = _shellTopicListHost?.attachment;
    final previousRows = prior?.chatId == widget.chatId
        ? {for (final item in prior!.topics) item.id: item}
        : null;
    return [
      for (final topic in _vm.forumTopics)
        _topicNavigationItem(topic, prior: previousRows?[topic.id]),
    ];
  }

  TopicNavigationItem _topicNavigationItem(
    ForumTopicOption topic, {
    TopicNavigationItem? prior,
  }) => TopicNavigationItem(
    id: topic.id,
    name: topic.name,
    iconCustomEmojiId: topic.iconCustomEmojiId,
    iconColor: topic.iconColor,
    unreadCount: topic.unreadCount,
    isMuted: topic.isMuted,
    // A fresh model page can explicitly unpin a topic; the previously
    // published marker must not turn that false back into true.
    isPinned: topic.isPinned,
    isGeneral: topic.isGeneral || (prior?.isGeneral ?? false),
    isClosed: topic.isClosed || (prior?.isClosed ?? false),
    lastPreview: topic.lastPreview.isNotEmpty
        ? topic.lastPreview
        : prior?.lastPreview ?? '',
    lastSender: topic.lastPreview.isNotEmpty
        ? topic.lastSender
        : prior?.lastSender,
    lastMessageDate: topic.lastMessageDate != 0
        ? topic.lastMessageDate
        : prior?.lastMessageDate ?? 0,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detachPaneBackHandler?.call();
    _detachPaneBackHandler = ChatPane.registerBackHandler(context, () {
      if (_search.isActive) {
        _closeSearch();
        return true;
      }
      _prepareExitState();
      return false;
    });
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
    _syncTopicListHostScope();
    _publishTopicList();
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

  bool get _hasTranscriptPointerDown => _transcriptPointersDown.isNotEmpty;

  bool get _initialTranscriptPositioningAborted =>
      _initialTranscriptPositionCancelled ||
      _hasTranscriptPointerDown ||
      _transcriptViewportClaimedByUser;

  bool get _sessionReopenPending =>
      !_sessionReopenDispositionResolved ||
      _sessionReopenResolutionInFlight ||
      _prioritizingSessionUnread;

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
    for (final entry in _mountedTranscriptEntries.entries) {
      final itemRenderObject = entry.value;
      if (!itemRenderObject.attached) {
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

  bool _scrollTickActive = false;
  double? _scrollTickLoadedBottomOffset;

  double get _loadedBottomOffset {
    if (!_scrollTickActive) return _measureLoadedBottomOffset();
    return _scrollTickLoadedBottomOffset ??= _measureLoadedBottomOffset();
  }

  bool get _isUserScrolling =>
      _scroll.hasClients && _scroll.position.isScrollingNotifier.value;

  bool get _showReturnToLatestProgress =>
      _returnToLatestCoordinator.showProgress;

  /// Records where the reader is standing before an in-transcript jump. A

  /// chain of jumps keeps the FIRST origin: that is the place the reader

  /// actually left, and every later jump is only a detour away from it.

  /// Remembers where the viewport stood when a real drag began. A tap (reply

  /// quote, timestamp) produces no scroll notification, so it can never be

  /// mistaken for the drag that abandons the origin.

  /// Drops the origin once a drag has carried the viewport a meaningful

  /// distance away from the jump target. A small nudge to read the quoted

  /// neighbourhood keeps the arrow pointing back at where the reader left.

  /// The floating arrow: returns to the message the reader left while a jump

  /// origin is live, and to the newest message otherwise.

  /// The shell asked for the newest message — because the reader tapped the

  /// conversation that is already open, or re-opened it from a link. This is

  /// the same intent as tapping the return-to-latest arrow, so it goes through

  /// the same coordinator: an anchored history window loads the latest page

  /// first, and a plain scroll-up just animates back to the edge.

  /// The transcript sits above the composer in a forward scroll view, so a

  /// field that wraps onto more lines shrinks the viewport from the bottom and

  /// would cover the newest message. Unlike a panel change this keeps a

  /// pending unread/linked-message jump.

  /// Jump to the unread boundary captured when the chat opened. The live TDLib

  /// boundary may already point at the newest message after the chat is marked

  /// read, so it cannot be used to resolve this button later.

  /// Makes an arbitrary loaded target the first child after the scroll view's

  /// center sliver, so Flutter lays it out without depending on guessed row

  /// heights. The transcript keeps the same chronological order on both sides

  /// of the new pivot; only its zero scroll coordinate moves to the target.

  /// One-time positioning when a chat opens. This must never block painting:

  /// a hidden transcript reads as a black screen in dark mode. We jump to the

  /// deterministic estimate immediately and then do one zero-duration correction

  /// after layout, without waiting to reveal the UI.

  /// Puts [messageId] back at [desiredOffset] pixels below the transcript

  /// viewport top, measured rather than replayed as raw pixels: the row may sit

  /// in a different sliver window than it did when the offset was recorded.

  ChatInitialViewportTarget _initialViewportTarget() {
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    return resolveChatInitialViewportTarget(
      explicitMessageId: widget.initialMessageId,
      pendingMessageId: _scrollTargetId,
      openAtBottom: _shouldOpenAtBottom,
      anchoredHistory: _vm.anchoredHistory,
      unreadCount: _entryUnreadCount,
      firstUnreadMessageId: i < 0 ? null : _vm.messages[i].id,
      unreadBoundaryLoaded: boundaryLoaded,
      lastReadInboxId: _entryLastReadInboxId,
    );
  }

  static const _estimatedUnreadDividerExtent = 33.0;

  static const _estimatedSeparatorExtent = 34.0;

  /// Unparks a frozen newest (or newest-like) pivot when older messages are

  /// already in the model but only the after-center arm is visible.

  bool get _canBackSwipe =>
      widget.showBackButton &&
      !_isSelecting &&
      !_search.isActive &&
      _actionTarget == null;

  bool get _isSelecting => _selectionAnchorId != null;

  @override
  void dispose() {
    _prepareExitState();
    _detachPaneBackHandler?.call();
    _detachExitController?.call();
    _detachRevealLatestController?.call();
    NotificationController.shared.unregisterVisibleChat(this);
    ActiveConversation.shared.unregister(this);
    _wallpaperController.removeListener(_onWallpaperChanged);
    _bannerTimer?.cancel();
    _readSyncTimer?.cancel();
    _handoffUpdateTimer?.cancel();
    _linkedMessageHighlightFadeTimer?.cancel();
    _linkedMessageHighlightClearTimer?.cancel();
    _translation.removeListener(_onTranslationSettingsChanged);
    _ai?.removeListener(_onTranslationSettingsChanged);
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    final topicListHost = _shellTopicListHost;
    final publishedTopicList = _publishedAttachment;
    if (topicListHost != null && publishedTopicList != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => topicListHost.unpublish(publishedTopicList),
      );
    }
    _vm.removeListener(_publishTopicList);
    _vm.removeListener(_onModel);
    _vm.onDisappear();
    _vm.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _unreadDivider() {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: c.linkBlue, height: 1, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              AppStringKeys.chatNewMessagesDivider.l10n(context),
              style: TextStyle(fontSize: 12, color: c.linkBlue),
            ),
          ),
          Expanded(child: Divider(color: c.linkBlue, height: 1, thickness: 1)),
        ],
      ),
    );
  }

  /// The section marker above the first message of a topic run, in the forum

  /// transcript that mixes every topic together.

  ///

  /// Telegram iOS renders this as a tappable header naming the topic the

  /// messages below belong to, so the list stays attributable without opening

  /// each topic. Tapping it opens that topic's own transcript, matching the

  /// topic list's navigation.

  ///

  /// The row keeps a [AppSpacing.sm] top inset like the transcript's other

  /// separator plates. A message hangs its detail timestamp 5px below its own

  /// row (`MessageBubble`'s floating timestamp, shown on tap, hover and with

  /// 「始终显示消息时间」), so a row that started flush with the message above

  /// would have its badge plate painted over that timestamp.

  Widget _topicSectionHeader(int topicId) {
    final c = context.colors;
    final display = _topicSectionDisplay(topicId);
    final plate = servicePlateBackground(c);
    final foreground = servicePlateForeground(plate);
    return Padding(
      key: ValueKey('forum-topic-section-$topicId'),
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Center(
        child: GestureDetector(
          key: ValueKey('forum-topic-section-tap-$topicId'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _openTopicTranscript(topicId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: plate,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (display.isGeneral && _vm.peerTitle.isNotEmpty)
                  PhotoAvatar(
                    title: _vm.peerTitle,
                    photo: _vm.peerPhoto,
                    size: 16,
                    square: true,
                    allowAnimation: false,
                  )
                else
                  TopicIconSurface(
                    size: 16,
                    iconCustomEmojiId: display.iconCustomEmojiId,
                    tint: display.iconColor == 0
                        ? foreground
                        : Color(0xFF000000 | (display.iconColor & 0xFFFFFF)),
                  ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    display.name,
                    key: ValueKey('forum-topic-section-label-$topicId'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption(foreground),
                  ),
                ),
                const SizedBox(width: 2),
                AppIcon(HeroAppIcons.chevronRight, size: 11, color: foreground),
              ],
            ),
          ),
        ),
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
    final revisionIds = groupedMedia.isEmpty
        ? <int>[message.id]
        : <int>[for (final member in groupedMedia) member.id];
    return _ActiveChatListenableBuilder(
      listenable: Listenable.merge([
        for (final messageId in revisionIds)
          _vm.messageRevisionListenable(messageId),
      ]),
      builder: (context) => _buildMessageBubble(
        message,
        messageIndex,
        groupedMedia: groupedMedia,
        targetMediaMessageId: targetMediaMessageId,
        targetMediaKey: targetMediaKey,
      ),
    );
  }

  /// Answers a swipe on the transcript. The gesture is a shortcut to typing,

  /// so the composer takes the caret as well as the reply target.

  Widget _buildMessageBubble(
    ChatMessage message,
    int messageIndex, {
    required List<ChatMessage> groupedMedia,
    required int? targetMediaMessageId,
    required GlobalKey? targetMediaKey,
  }) {
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
      showRepeat:
          (_vm.canForwardContent || _protectedCopyEnabled) &&
          _isRepeatTail(messageIndex),
      onRepeat: () => _vm.repeatMessage(message),
      onLongPress: _isSelecting ? null : _showActionMenuForMessage,
      onDesktopQuoteChanged: _handleDesktopQuoteChanged,
      mobileTextSelectionAreaKey: mobileSelectionKey,
      onMobileTextSelectionChanged: _handleMobileTextSelectionChanged,
      onMobileTextSelectionDisposed: mobileSelectionKey == null
          ? null
          : () => _handleMobileTextSelectionDisposed(
              message.id,
              mobileSelectionKey,
            ),
      onReply: _beginSwipeReply,
      onAvatarTap: _openSenderProfile,
      onAvatarLongPress: (m) {
        if (_vm.isGroup && (m.senderName?.isNotEmpty ?? false)) {
          _vm.insertMention(m);
        }
      },
      onOpenReply: _openReplyMessage,
      onOpenForwarded: _openForwardedMessage,
      onTapViaBot: (m) => unawaited(_activateMessageViaBot(m)),
      onOpenComments: _openMessageComments,
      showCommentAttachment: chatTranscriptAllowsCommentAttachment(
        isChannel: _vm.isChannel,
      ),
      channelHasLinkedDiscussion: _vm.hasLinkedDiscussion,
      showChannelPostStats:
          _vm.isChannel && context.read<ThemeController>().showChannelPostStats,
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

  /// Whether the transcript mixes every topic into one list: a forum opened

  /// without a specific topic. Telegram iOS sections that list by topic so

  /// each message stays attributable; a single-topic transcript is already

  /// scoped and needs no sections. A topics-enabled bot's chat mixes the

  /// same way when opened without a topic — its messages carry explicit

  /// topic ids and no General bucket exists, so the headers attribute them

  /// exactly like a forum's.

  bool get _showsForumTopicSections =>
      (_vm.isForum || _vm.supportsBotTopics) && !_vm.isForumTopicTranscript;

  /// Desktop counterpart of 保存到相册: fetch the original if it is not local

  /// yet, then copy it into a folder the user picks.

  /// Hides [message]'s sender on this device, in this group or everywhere.

  /// Nothing reaches Telegram: unlike Block, the member is not blocked,

  /// reported or told.

  /// Someone else's message in a group; never the group itself posting as

  /// an anonymous admin, and not in broadcast channels.

  /// Opens the profile of a user who reacted, or the chat when the reaction

  /// was sent by a chat. A deleted account has neither.

  List<String> get _effectiveTranslationOptions =>
      effectiveTranslationOptionIds(
        translation: _translation,
        ai: _ai,
        nativeProviders: _nativeTranslationProviders,
        isBotApiAccount: _vm.isBotApiAccount,
      );

  bool get _hasAvailableTranslationOption =>
      _effectiveTranslationOptions.isNotEmpty;

  int get _botApiWarningMask =>
      (_vm.showBotApiPrivacyWarning ? 1 : 0) |
      (_vm.showBotApiBotToBotWarning ? 2 : 0);

  String get _botApiWarningDismissalKey =>
      'mithka.botApiAccessWarningDismissed.v1.${_sessionKey.accountSlot}';

  bool get _showsBotApiAccessWarning {
    final mask = _botApiWarningMask;
    return mask != 0 && _dismissedBotApiWarningMask != mask;
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

  Widget _chatTranslationPanel() => ChatTranslationPanel(
    active: _automaticTranslationEnabled,
    targetLanguageLabel: _translation.targetLanguageLabel.l10n(context),
    isTranslating: _autoTranslationRunning,
    onToggle: _toggleAutomaticTranslation,
    onChooseLanguage: () => unawaited(_showChatTranslationLanguagePicker()),
    onDismiss: _dismissAutomaticTranslation,
  );

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

  /// The link-routing target this transcript mounts below its subtree. Kept

  /// as a field so handlers running on the State's own context — which sits

  /// ABOVE the scope, so `InternalChatLinkScope.targetOf(context)` returns

  /// null there — can still open links as this chat, on this account (a

  /// multi-account shell otherwise drops the account-less request silently).

  late final InternalChatLinkTarget _internalLinkTarget =
      InternalChatLinkTarget(
        chatId: widget.chatId,
        accountSlot: _sessionKey.accountSlot,
        openMessage: _scrollToMessage,
      );

  @override
  Widget build(BuildContext context) {
    Widget withInternalLinkRouting(Widget child) =>
        InternalChatLinkScope(target: _internalLinkTarget, child: child);

    _shellLayoutGeneration++;
    final c = context.colors;
    final themeController = context.watch<ThemeController>();
    _themingEnabled = themeController.themingEnabled;
    // The model has no theme access of its own, so the outgoing 盘古之白
    // switches are mirrored on every build: flipping one in Settings takes
    // effect on the next send without recreating the transcript.
    _vm
      ..panguOnSend = themeController.panguOnSend
      ..panguOnEdit = themeController.panguOnEdit;
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
                                    : _topicTabStrip(
                                        _withTopicNavigation(
                                          Column(
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
                                        ),
                                      ),
                                trailingPane: searchPane
                                    ? _searchResultsPane()
                                    : widget.trailingPane,
                                trailingPaneWidth: searchPane
                                    ? chatSearchResultsPaneWidth
                                    : widget.trailingPaneWidth,
                                // Search results own the trailing slot
                                // while they are up; the tab returns after.
                                onTrailingPaneToggle: searchPane
                                    ? null
                                    : widget.onTrailingPaneToggle,
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
                        if ((_actionTarget != null ||
                                _actionOverlaySnapshot != null) &&
                            !_isSelecting)
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

  Widget _withTopicNavigation(Widget child) {
    if (!_topicsKnown ||
        !usesSplitSelectionLayout(MediaQuery.sizeOf(context))) {
      return child;
    }
    // A sidebar-placement shell paints this chat's topic list over its chat
    // list column; the conversation pane keeps its full width there.
    if (_topicListOverlaid) return child;
    return TopicNavigationLayout(
      topics: [
        for (final topic in _vm.forumTopics) _topicNavigationItem(topic),
      ],
      selectedTopicId: widget.forumTopicId,
      hasForumTabs: _vm.hasForumTabs,
      onSelected: _openTopicTranscript,
      onCreateTopic: _vm.canCreateForumTopics ? _openCreateTopicDialog : null,
      onMarkAllRead: _hasUnreadTopics ? _markAllTopicsRead : null,
      onTopicMenu: _showTopicRowMenu,
      generalAvatarTitle: _vm.peerTitle.isEmpty ? widget.title : _vm.peerTitle,
      generalAvatarPhoto: _vm.peerPhoto,
      child: child,
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
        ? (_vm.isChannel
                  ? AppStringKeys.chatRestrictedTelegramTosMessageChannel
                  : AppStringKeys.chatRestrictedTelegramTosMessage)
              .l10n(context)
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
        if (transcriptReady &&
            (_vm.unreadMentionCount > 0 || _vm.unreadReactionCount > 0))
          Positioned(
            top:
                (showPinnedTodo ? 72.0 : 8.0) +
                (newMessagesPlacement == ChatNewMessagesControlPlacement.top
                    ? 52
                    : 0),
            right: 12,
            child: _unreadActivityIndicators(),
          ),
        if (transcriptReady)
          Positioned(
            right: 16,
            bottom: 12,
            child: AnimatedSwitcher(
              duration: AppMotion.duration(context, AppMotion.quick),
              switchInCurve: AppMotion.standard,
              switchOutCurve: AppMotion.accelerate,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.8, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: bottomIndicator == ChatBottomIndicator.jumpToBottom
                  ? _jumpToBottomButton()
                  : const SizedBox.shrink(),
            ),
          ),
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
    return _openAtLatest || !_vm.historyReachesLatest || !_isNearBottom(80);
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
        child: AppPressRipple(
          borderRadius: BorderRadius.circular(20),
          child: Center(
            child: _showReturnToLatestProgress
                ? AppActivityIndicator(size: 18, color: c.textSecondary)
                : AppIcon(
                    HeroAppIcons.angleDown,
                    size: 22,
                    color: c.textSecondary,
                  ),
          ),
        ),
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
          // The unread pill always means "go to the newest message", even
          // while the arrow would return to a jump origin.
          ? () => _requestReturnToLatest(userInitiated: true)
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

  Widget _unreadActivityIndicators() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_vm.unreadMentionCount > 0)
          _unreadActivityIndicator(
            key: const ValueKey('unread-mention-indicator'),
            icon: HeroAppIcons.at,
            count: _vm.unreadMentionCount,
            label: AppStrings.t(AppStringKeys.notificationMentions),
            opening: _openingUnreadMention,
            onTap: _openUnreadMention,
            onLongPress: _showReadAllMentionsMenu,
          ),
        if (_vm.unreadMentionCount > 0 && _vm.unreadReactionCount > 0)
          const SizedBox(height: AppSpacing.md),
        if (_vm.unreadReactionCount > 0)
          _unreadActivityIndicator(
            key: const ValueKey('unread-reaction-indicator'),
            icon: HeroAppIcons.heart,
            count: _vm.unreadReactionCount,
            label: AppStrings.t(AppStringKeys.notificationReactions),
            opening: _openingUnreadReaction,
            onTap: _openUnreadReaction,
            // the reference client clears reactions on the long press itself, without
            // the read-all menu it shows for mentions.
            onLongPress: (_) {
              unawaited(HapticFeedback.mediumImpact());
              unawaited(_markAllReactionsRead());
            },
          ),
      ],
    );
  }

  Widget _unreadActivityIndicator({
    required Key key,
    required AppIconData icon,
    required int count,
    required String label,
    required bool opening,
    required VoidCallback onTap,
    required ValueChanged<Rect> onLongPress,
  }) {
    final countLabel = count > 999 ? '999+' : '$count';
    return Semantics(
      button: true,
      label: '$label: $countLabel',
      child: Builder(
        builder: (pillContext) => GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: opening ? null : onTap,
          // The menu hangs off the pill itself, so its anchor is this
          // widget's own box — not the transcript or the press point.
          onLongPress: opening
              ? null
              : () {
                  final box = pillContext.findRenderObject() as RenderBox?;
                  if (box == null || !box.hasSize) return;
                  onLongPress(box.localToGlobal(Offset.zero) & box.size);
                },
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: opening ? 0.62 : 1,
            child: Container(
              height: 34,
              constraints: const BoxConstraints(minWidth: 40),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(icon, size: AppIconSize.lg, color: Colors.white),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    countLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppTextSize.caption,
                      fontWeight: AppTextWeight.semibold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // MARK: - Composer area (input bar / join bar / disabled bar)

  Widget _chatMusicPlayer() {
    // In split layouts the shell shows the player under every pane.
    if (MusicPlayerShellScope.providesPlayer(context)) {
      return const SizedBox.shrink();
    }
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
    // Subscribed to a channel you can't post in → the channel bottom panel:
    // stock mute/unmute, the discussion / direct-message actions, or nothing.
    if (_vm.isChannel && _vm.isMember) {
      return ChannelBottomPanel(
        mode: context.watch<ThemeController>().channelBottomBarMode,
        muted: _vm.isMuted,
        hasDiscussion: _vm.hasLinkedDiscussion,
        hasDirectMessages: _vm.hasDirectMessagesGroup,
        onToggleMute: () => _vm.toggleMute(),
        onOpenDiscussion: () =>
            unawaited(_openChannelLinkedChat(_vm.linkedDiscussionChatId)),
        onOpenDirectMessages: () =>
            unawaited(_openChannelLinkedChat(_vm.directMessagesChatId)),
      );
    }
    return _disabledComposer(_vm.sendDisabledReason);
  }

  // ChatInputBar subscribes to the view model itself, so the parent's

  // notification-driven rebuilds only re-run its build for nothing. Every other

  // constructor argument is either the (final) view model or a method tear-off,

  // so these five flags are the whole input set.
  Widget? _composerBarCache;

  bool _composerBarRequestInitialFocus = false;

  bool _composerBarEnterToSend = false;

  bool _composerBarQuickRepliesEnabled = false;

  bool _composerBarShowCallAction = false;

  bool _composerBarSimpleMode = false;
  String? _composerBarMediaKind;

  Widget _chatInputBar() {
    final themeController = context.watch<ThemeController>();
    final requestInitialFocus = widget.requestComposerFocusOnReady;
    final enterToSend = themeController.enterToSend;
    final quickRepliesEnabled = themeController.quickRepliesEnabled;
    final showCallAction = !_usesWideGroupHeader;
    final simpleMode = themeController.simpleMode;
    final mediaSegment = themeController.mediaPanelSegment;
    final cached = _composerBarCache;
    if (cached != null &&
        _composerBarRequestInitialFocus == requestInitialFocus &&
        _composerBarEnterToSend == enterToSend &&
        _composerBarQuickRepliesEnabled == quickRepliesEnabled &&
        _composerBarShowCallAction == showCallAction &&
        _composerBarSimpleMode == simpleMode &&
        _composerBarMediaKind == mediaSegment) {
      return cached;
    }
    _composerBarRequestInitialFocus = requestInitialFocus;
    _composerBarEnterToSend = enterToSend;
    _composerBarQuickRepliesEnabled = quickRepliesEnabled;
    _composerBarShowCallAction = showCallAction;
    _composerBarSimpleMode = simpleMode;
    _composerBarMediaKind = mediaSegment;
    return _composerBarCache = ChatInputBar(
      vm: _vm,
      requestInitialFocus: requestInitialFocus,
      enterToSend: enterToSend,
      quickRepliesEnabled: quickRepliesEnabled,
      showCallAction: showCallAction,
      simpleMode: simpleMode,
      initialMediaKind: mediaSegment,
      onMediaKindChanged: (v) => themeController.mediaPanelSegment = v,
      onStartCall: _startCall,
      onMessageSent: _onComposerMessageSent,
      onPanelGeometryChanged: _onComposerPanelGeometryChanged,
      onInputHeightChanged: _onComposerInputHeightChanged,
      onMediaSendTapped: _onComposerMediaSendTapped,
      onBotTopicCreated: _openTopicTranscript,
      onReplyOptionsRequested: _showComposerReplyOptions,
      onForwardOptionsRequested: _showComposerForwardOptions,
      onReplySourceJump: _jumpToReplySource,
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

  /// Bottom bar with a 加入 / 申请加入 button for a joinable chat you can preview.

  Widget _joinBar() {
    final c = context.colors;
    final requested = _vm.joinRequested;
    final label = requested
        ? AppStringKeys.chatJoinRequestSent
        : (_vm.joinByRequest
              ? AppStringKeys.chatRequestToJoin
              : (_vm.isChannel
                    ? AppStringKeys.chatJoinChannel
                    : AppStringKeys.chatJoinGroup));
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
              : (_vm.isChannel
                    ? AppStringKeys.chatJoinChannel
                    : AppStringKeys.chatJoinGroup));
    return ChatHeaderTrailingPaneLayout(
      header: _header(),
      trailingPane: widget.trailingPane,
      trailingPaneWidth: widget.trailingPaneWidth,
      onTrailingPaneToggle: widget.onTrailingPaneToggle,
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
    return _ActiveChatListenableBuilder(
      listenable: _vm.headerRevisionListenable,
      builder: (context) => _buildHeader(),
    );
  }

  Widget _buildHeader() {
    final c = context.colors;
    final subtitle = _vm.subtitle;
    final actionActive = _vm.hasActiveChatAction;
    final wideGroupHeader = _usesWideGroupHeader;
    return Container(
      padding: EdgeInsets.only(top: topChromeInsetOf(context)),
      decoration: BoxDecoration(
        color: widget.headerColor ?? c.navBar,
        border: widget.showHeaderDivider
            ? Border(bottom: BorderSide(color: c.divider, width: 0.5))
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Let the two text lines determine the height at accessibility
          // sizes instead of squeezing them into a fixed toolbar.
          ConstrainedBox(
            key: const ValueKey('chatHeaderToolbar'),
            constraints: BoxConstraints(minHeight: widget.headerHeight),
            child: Padding(
              // Only the toolbar row meets the corner status cluster; the
              // panels below it keep the full width.
              padding:
                  const EdgeInsets.symmetric(horizontal: 14) +
                  TopClusterInsets.of(context),
              child: Row(
                children: [
                  if (widget.showBackButton)
                    GestureDetector(
                      key: const ValueKey('chatHeaderBack'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _handleBack,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: AppIcon(
                            HeroAppIcons.chevronLeft,
                            size: 22,
                            color: c.textPrimary,
                          ),
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
                  if (_canViewAsMoments)
                    _ChatHeaderAction(
                      key: const ValueKey('chatHeaderViewAsMoments'),
                      label: AppStringKeys.chatViewAsMoments.l10n(context),
                      icon: HeroAppIcons.newspaper,
                      onTap: () => unawaited(_openChannelMoments()),
                    ),
                  if (wideGroupHeader)
                    WideGroupChatHeaderActions(
                      onStartCall: (isVideo) => unawaited(_startCall(isVideo)),
                      showCallActions:
                          Theme.of(context).platform != TargetPlatform.macOS,
                      isChannel: _vm.isChannel,
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
                  if (_showsTopicSurfaces) ...[
                    _ChatHeaderAction(
                      key: const ValueKey('chatHeaderTopics'),
                      label: AppStringKeys.topicChatAllTopics.l10n(context),
                      icon: HeroAppIcons.hashtag,
                      onTap: () {
                        // A shell overlay the user dismissed comes back from
                        // the header; other shells pick from the sheet.
                        final host = _topicListOverlaid
                            ? _shellTopicListHost
                            : null;
                        if (host != null && host.listHidden) {
                          host.showList();
                          return;
                        }
                        unawaited(_showTopicSelector());
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
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

  /// Topics keep their dedicated surface — header chevron, topic picker, and

  /// the # header action — whenever the chat is a topic chat. The picker

  /// switches between topic transcripts.

  bool get _showsTopicSurfaces => _topicsKnown;

  /// The join screen and a restricted peer both render the chat header over a

  /// page with no transcript behind it. Offering search there would open a

  /// field that can only ever report nothing.

  bool get _canSearchMessages =>
      !_vm.isPeerRestricted && (_vm.isMember || _vm.messages.isNotEmpty);

  /// A broadcast channel's posts also read as a Moments feed. The join screen

  /// and a restricted channel have no posts to show there.

  bool get _canViewAsMoments =>
      _vm.isChannel && _vm.forumTopicId == null && _canSearchMessages;

  bool get _usesWideGroupHeader {
    return wideGroupHeaderActionsEnabled(
      MediaQuery.sizeOf(context),
      isGroup: _vm.isGroup,
      hasContextPaneToggle: widget.onInfoPressed != null,
    );
  }

  Widget _headerTitleBlock(String subtitle, bool actionActive) {
    final c = context.colors;
    final serverTitle = _vm.displayTitle;
    final displayTitle =
        _vm.forumTopicId == null && _vm.isGroup && !_vm.isChannel
        ? context.watch<GroupRemarkController?>()?.displayTitleFor(
                widget.chatId,
                serverTitle,
              ) ??
              serverTitle
        : serverTitle;
    final headerTitle =
        _vm.forumTopicId == null && _vm.isGroup && _vm.memberCount > 0
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
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showsTopicSurfaces)
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
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: text,
    );
    if (_showsTopicSurfaces) {
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

  /// Opens a topic, or the whole chat for null, as the ordinary chat

  /// transcript (topics-as-group setting). Replaces this transcript in place

  /// so the navigation stack stays flat. An owning shell rebuilds the

  /// transcript itself; a bare split detail pane swaps its own content.

  // MARK: - Topic moderation (Telegram iOS parity)

  /// Telegram iOS offers topic creation right from the topic list.

  /// Clears every topic in the list at once: one scoped read per topic, with

  /// the unread counters cleared optimistically and restored if a read fails.

  /// The topic row's context menu (iOS swipe action / long press). Destructive

  /// and management items only appear while the account holds the right;

  Widget _forumTopicIcon(
    ForumTopicOption? topic,
    bool all,
    AppColors c, {
    bool current = false,
  }) {
    if (all) {
      return AppIcon(HeroAppIcons.hashtag, color: AppTheme.brand, size: 24);
    }
    final iconId = topic?.iconCustomEmojiId ?? 0;
    if (iconId != 0) return CustomEmojiView(id: iconId, size: 24);
    final rawColor = topic?.iconColor ?? 0;
    final color = current
        ? AppTheme.brand
        : rawColor == 0
        ? c.textSecondary
        : Color(0xFF000000 | (rawColor & 0xFFFFFF));
    return AppIcon(HeroAppIcons.solidMessage, color: color, size: 24);
  }

  Widget _selectionHeader() {
    final c = context.colors;
    final count = _selectedMessageIds.length;
    return Container(
      padding: headerChromePaddingOf(context),
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
              actionEnabled: _vm.canForwardContent || _protectedCopyEnabled,
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
        key: const ValueKey('chatPinnedBar'),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          // Solid composer surface, like the docked panels below the
          // transcript: no translucent card fill and no drop shadow.
          color: c.inputBarBackground,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: c.divider.withValues(alpha: 0.55),
            width: 0.5,
          ),
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

  /// Scrolls the transcript to a message. If it is not loaded, ask TDLib for a

  /// page centered around that id instead of fetching the whole middle history.

  /// A hashtag is already a query over the open chat, so it opens in-chat

  /// search rather than pushing a screen over the transcript it refers to.

  // MARK: - In-chat search

  /// The controller notifies per keystroke, per page and per resolved sender,

  /// and every search surface already AnimatedBuilds on it. `isActive` is the

  /// only value this build reads, so anything else would rebuild the whole

  /// transcript for a repaint that happens elsewhere.

  /// Moves the transcript to a hit and leaves it marked.

  ///

  /// The alignment sits the message just above centre so the messages around

  /// it — the reason the user searched — are on screen too.

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
    onJumpToMessage: _jumpToDateMessage,
  );

  /// Lands the transcript on the message a calendar date resolved to.

  ///

  /// Unlike a search hit nothing is marked — the jump reads as navigation, not

  /// as a match — and the search session stays open for the next step.

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

  /// Repeats ordinary target alignment while rich content finishes laying out.

  /// The first pass carries the visible motion; the two short correction passes

  /// absorb thumbnail, preview, reaction, and text reflow during that motion.

  /// Whether the row already rests where `Scrollable.ensureVisible` would put

  /// it, using the viewport's own reveal math so pinned slivers and oversized

  /// rows are accounted for exactly as the real call accounts for them.

  /// Aligns a pinned target more than once because media rows can finish a

  /// thumbnail decode while the first scroll animation is still laying out.

  /// The old one-shot calculation consequently landed the containing album a

  /// few pixels above or below the pinned banner, especially on Android.

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
    _scheduleTranscriptBottomGapCorrection();
    // No fill of its own: ChatWallpaperBackground already covers this region
    // with the same chatBackground when no wallpaper is set, and a transparent
    // ColoredBox still issues a full-viewport drawRect.
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0) _scheduleTranscriptBottomGapCorrection();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onTranscriptScrollNotification,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onTranscriptPointerDown,
          onPointerUp: _onTranscriptPointerEnd,
          onPointerCancel: _onTranscriptPointerEnd,
          child: CustomScrollView(
            key: _transcriptViewportKey,
            controller: _scroll,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                      return _buildTranscriptEntry(
                        olderEntries[index],
                        messages,
                      );
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
      messageBody = ContentSizeScope(
        child: message.communityPreview != null
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
              ),
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
    final visibilityKey = _entryVisibilityKeys.putIfAbsent(
      entry.last.id,
      GlobalKey.new,
    );
    return KeyedSubtree(
      key: entry.key,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_needsUnreadDivider(messageIndex, messages: messages))
            KeyedSubtree(
              key: _unreadKey,
              child: ContentSizeScope(child: _unreadDivider()),
            ),
          if (_needsSeparator(messageIndex, messages: messages))
            ContentSizeScope(child: TimeSeparator(unix: message.date)),
          if (_needsTopicSeparator(messageIndex, messages: messages))
            ContentSizeScope(
              child: _topicSectionHeader(_topicSectionId(message)!),
            ),
          // Anchor the message itself: unread/date separators can disappear
          // between visits and must not shift the restored reading position.
          TranscriptEntryBoundary(
            key: visibilityKey,
            messageId: entry.last.id,
            mountedEntries: _mountedTranscriptEntries,
            child: _messageNavigationHighlight(entry, positionedMessageBody),
          ),
        ],
      ),
    );
  }

  /// Washes the row holding a search hit or a just-opened reply destination.

  /// A full-width tint makes an album or document run read as one destination;

  /// reply navigation holds the stronger tint for 650 ms, then fades it out.

  Widget _messageNavigationHighlight(_TranscriptEntry entry, Widget content) {
    final searchHighlighted =
        _searchHighlightId != null &&
        entry.messages.any((m) => m.id == _searchHighlightId);
    final linkedHighlighted =
        _linkedMessageHighlightId != null &&
        entry.messages.any((m) => m.id == _linkedMessageHighlightId);
    if (!searchHighlighted && !linkedHighlighted) return content;
    final alpha = linkedHighlighted && _linkedMessageHighlightActive
        ? 0.18
        : searchHighlighted
        ? 0.12
        : 0.0;
    return AnimatedContainer(
      duration: AppMotion.duration(context, AppMotion.deliberate),
      curve: AppMotion.standard,
      color: AppTheme.brand.withValues(alpha: alpha),
      child: content,
    );
  }

  // The transcript is rebuilt on every view-model notification (send/read/

  // typing/file progress); grouping a few hundred messages each time is

  // avoidable garbage, so entries are memoized on their actual inputs.
  List<_TranscriptEntry>? _transcriptCache;
  List<ChatMessage>? _transcriptCacheMessages;

  bool _transcriptCacheGrouped = false;

  // The unread divider is the only unread-dependent part of grouping, and it

  // reads the state captured on entry — not the live counters, which move with

  // every message read while scrolling.

  int _transcriptCacheEntryUnreadCount = -1;

  int _transcriptCacheEntryLastReadInboxId = -1;

  int _transcriptCacheEntryLatestMessageId = -1;
  int? _transcriptCacheEntryFirstUnreadMessageId;

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

  /// The link row appears only once the server confirms the message carries

  /// one (`messageProperties.can_get_link`), and the reply row only once it

  /// confirms a reply is accepted (`messageProperties.can_be_replied`). A

  /// chat without a composer never gets one at all. While the offline

  /// properties query is in flight both entries stay hidden, so the menu

  /// never grows a row it would have to remove a moment later.

  /// An album shows one set of reactions, those of its interaction owner, so

  /// a reaction picked on any member goes to that owner.

  Widget _documentGroupBubble(
    _TranscriptEntry entry, {
    int? targetMessageId,
    GlobalKey? targetKey,
  }) {
    for (final member in entry.messages) {
      _vm.ensureMessageCapabilities(member);
    }
    return _ActiveChatListenableBuilder(
      listenable: Listenable.merge([
        for (final message in entry.messages)
          _vm.messageRevisionListenable(message.id),
      ]),
      builder: (context) {
        // Replies/reactions can move album interaction ownership to another
        // member, so reselect the owner inside the localized rebuild.
        final owner = _mediaAlbumInteractionOwner(entry.messages);
        final ownerIndex = entry.startIndex + entry.messages.indexOf(owner);
        return _buildMessageBubble(
          owner,
          ownerIndex,
          groupedMedia: entry.messages,
          targetMediaMessageId: targetMessageId,
          targetMediaKey: targetKey,
        );
      },
    );
  }

  Widget _imageGroupBubble(
    List<ChatMessage> group, {
    int? targetMessageId,
    GlobalKey? targetKey,
  }) {
    return _ActiveChatListenableBuilder(
      listenable: Listenable.merge([
        for (final message in group) _vm.messageRevisionListenable(message.id),
      ]),
      builder: (context) => _buildImageGroupBubble(
        group,
        targetMessageId: targetMessageId,
        targetKey: targetKey,
      ),
    );
  }

  Widget _buildImageGroupBubble(
    List<ChatMessage> group, {
    required int? targetMessageId,
    required GlobalKey? targetKey,
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
    // An album is one row, so it swipes as one. The reply lands on the member
    // that already owns the album's interaction, the way a document album's
    // bubble does.
    return MessageSwipeReplyRow(
      swipeEnabled: !_isSelecting && mobileSelectionKey == null,
      onReply: () => _beginSwipeReply(_mediaAlbumInteractionOwner(group)),
      child: ImageMediaAlbumBubble(
        messages: group,
        peerTitle: _vm.peerTitle,
        peerPhoto: _vm.peerPhoto,
        isGroup: _vm.isGroup,
        meName: _vm.meName,
        mePhoto: _vm.mePhoto,
        meId: _vm.meId,
        hasCustomChatTheme: _hasCustomChatTheme,
        showCommentAttachment: chatTranscriptAllowsCommentAttachment(
          isChannel: _vm.isChannel,
        ),
        channelHasLinkedDiscussion: _vm.hasLinkedDiscussion,
        showChannelPostStats:
            _vm.isChannel &&
            context.read<ThemeController>().showChannelPostStats,
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
        onTapViaBot: (message) => unawaited(_activateMessageViaBot(message)),
        onOpenImage: _openImage,
        onPlayVideo: _playVideo,
        onEditCaption: (message) => unawaited(_editMessageText(message)),
        onOpenComments: _openMessageComments,
        onLongPress: _showActionMenuForMessage,
        onToggleReaction: (message, reaction) =>
            unawaited(_toggleMessageReaction(message, reaction)),
        onShowReactionUsers: _showReactionUsers,
        onDesktopQuoteChanged: _handleDesktopQuoteChanged,
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
      ),
    );
  }

  Widget _actionMenuOverlay() {
    final liveTarget = _actionTarget;
    if (liveTarget != null) {
      // Capture the fully configured surfaces this frame. Every close path
      // clears the live state immediately, and the presentation replays this
      // snapshot while the exit animation runs — otherwise the collapsing HUD
      // would show the already-cleared state instead of the closing menu.
      _actionOverlaySnapshot = _actionOverlayContent(liveTarget);
    }
    final content = _actionOverlaySnapshot;
    if (content == null) return const SizedBox.shrink();
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
                onTap: _dismissActionOverlay,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: MessageActionMenuPresentation(
                visible: liveTarget != null,
                anchor: _actionAnchor,
                onExitComplete: _handleActionOverlayExitComplete,
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Clears the live action state, handing the closing overlay its snapshot to

  /// replay during the exit. A second dismiss while the exit is still running

  /// finds no live target and leaves the running reverse alone.

  /// The exit animation landed: drop the snapshot and unmount the overlay. A

  /// late report for a menu that has since re-opened (or closed again) is

  /// stale — only a snapshot from the reported close is released here.

  Widget _actionOverlayContent(ChatMessage target) {
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
    final outgoing = target.isOutgoing;
    final rect = _actionRect;
    final expandedReactions = _reactionExpanded;
    final showActionMenu = !expandedReactions;
    final desktopMenu = isDesktopTargetPlatform(Theme.of(context).platform);
    final mobileDropdown =
        !desktopMenu &&
        context.watch<ThemeController>().mobileMessageActionMenuStyle ==
            MobileMessageActionMenuStyle.dropdown;
    final verticalMenu = desktopMenu || mobileDropdown;
    final reactionAvailability = _actionReactionAvailability;
    final showReactions = messageActionShowsReactionControls(
      isCall: target.isCall,
      availability: reactionAvailability,
    );
    final actionMenu = MessageActionMenu(
      message: target,
      isPinned: _vm.pinnedMessage?.id == target.id,
      allowForwarding: _vm.canForwardContent,
      allowProtectedCopyForward: _protectedCopyEnabled && !target.isService,
      allowTranslation:
          _hasAvailableTranslationOption &&
          _translationSourceText(target).trim().isNotEmpty,
      allowQuote: _vm.canQuoteText && _actionCanReply == true,
      // A channel post is answered in its linked discussion group, so a
      // channel that has one keeps Reply even when the channel itself takes no
      // messages — the comments sheet, which speaks for the group, decides
      // whether this account can send and says so after it opens. Everywhere
      // else a reply needs a composer here, and a message the server refuses
      // to have replied to is dropped even where posting is allowed. Null
      // while the properties query is in flight: fail closed, exactly like the
      // link row.
      allowReply:
          (_vm.isChannel && _vm.hasLinkedDiscussion && !target.isService) ||
          (_vm.canSendMessages && _actionCanReply == true),
      hasSelectedQuote: _actionQuote != null,
      allowSuggestedPostOffer:
          _vm.isDirectMessagesGroup && !_vm.isAdministeredDirectMessagesGroup,
      allowHideSender: _canHideSender(target),
      allowCopyMessageLink:
          !target.isCall && _actionMessageLinkAvailable == true,
      allowViewEdits: _actionTargetHasEdits(target),
      source: _actionSource,
      showingOriginalTranslation: _showOriginalTranslationMessageIds.contains(
        target.id,
      ),
      layout: verticalMenu
          ? MessageActionMenuLayout.vertical
          : MessageActionMenuLayout.grid,
      onSelect: (action) => _perform(action, target),
    );

    // Desktop treats the strip as the menu's upper storey and places the pair
    // as one block. Its row is reserved the moment the menu opens and only
    // collapses if the server comes back with nothing to offer, so the menu
    // does not jump out from under a settled pointer when the answer lands.
    final desktopStrip =
        desktopMenu &&
        !_reactionExpanded &&
        !target.isCall &&
        (reactionAvailability == null || reactionAvailability.canAdd);
    final desktopStripH = desktopStrip
        ? MenuReactionBar.heightFor(context) + _menuReactionGap
        : 0.0;
    final reactionH = !showReactions
        ? 0.0
        : _reactionExpanded
        ? _expandedPickerSize.height
        : QuickReactionBar.heightFor(context);
    final preferredMenuH = actionMenu.preferredHeightFor(context);
    double reactionTop, menuTop, menuH;
    if (desktopMenu) {
      // The pair travels as one block, placed by desktopOrigin below: the
      // strip is the menu's upper storey, so it never covers the menu.
      menuH = showActionMenu
          ? math.min(
              preferredMenuH,
              math.max(0.0, bottomSafe - topSafe - desktopStripH),
            )
          : 0.0;
      reactionTop = 0;
      menuTop = 0;
    } else {
      // Phone overlay: the strip stays above the message and the menu never
      // crosses it — a message near the bottom flips the menu above the strip
      // instead of letting it climb over the reactions.
      final placement = MessageActionMenu.placeMobileOverlay(
        anchor: rect,
        preferredMenuHeight: preferredMenuH,
        stripHeight: reactionH,
        topSafe: topSafe,
        bottomSafe: bottomSafe,
        viewportHeight: screenH,
        menuStartsAtAnchorTop: verticalMenu,
      );
      reactionTop = placement.stripTop;
      menuTop = placement.menuTop;
      menuH = showActionMenu ? placement.menuHeight : 0.0;
    }
    final align = outgoing ? Alignment.centerRight : Alignment.centerLeft;
    final verticalMenuWidth = math.min(
      actionMenu.preferredWidthFor(context),
      math.max(0.0, screenW - 20),
    );
    final boundedActionMenu = verticalMenu
        ? SizedBox(width: verticalMenuWidth, height: menuH, child: actionMenu)
        : actionMenu;
    final desktopOrigin = desktopMenu
        ? MessageActionMenu.verticalOriginForPointer(
            pointer: rect?.topLeft ?? Offset(10, topSafe),
            viewport: screenSize,
            menuSize: _reactionExpanded
                ? _expandedPickerSize
                : Size(verticalMenuWidth, desktopStripH + menuH),
            topSafe: topSafe,
            bottomSafe: bottomSafe,
          )
        : Offset.zero;

    return Stack(
      children: [
        // Call logs and other special messages aren't reactable — no strip.
        if (showReactions)
          Positioned(
            top: desktopMenu ? desktopOrigin.dy : reactionTop,
            left: desktopMenu ? desktopOrigin.dx : 10,
            right: desktopMenu ? null : 10,
            child: AnimatedBuilder(
              animation: EmojiStore.shared,
              builder: (context, _) {
                final availability = reactionAvailability!;
                if (expandedReactions) {
                  final picker = _expandedReactionPicker(availability);
                  return desktopMenu
                      ? picker
                      : Align(alignment: align, child: picker);
                }
                final reactions = _quickReactionChoices(availability);
                if (desktopMenu) {
                  return SizedBox(
                    width: verticalMenuWidth,
                    child: MenuReactionBar(
                      reactions: reactions,
                      onReaction: _reactQuick,
                      onExpand: () => setState(() => _reactionExpanded = true),
                    ),
                  );
                }
                return Align(
                  alignment: align,
                  child: QuickReactionBar(
                    reactions: reactions,
                    onReaction: _reactQuick,
                    onExpand: () => setState(() => _reactionExpanded = true),
                  ),
                );
              },
            ),
          ),
        if (showActionMenu)
          Positioned(
            top: desktopMenu ? desktopOrigin.dy + desktopStripH : menuTop,
            left: desktopMenu ? desktopOrigin.dx : 10,
            right: desktopMenu ? null : 10,
            child: desktopMenu
                ? boundedActionMenu
                : Align(alignment: align, child: boundedActionMenu),
          ),
      ],
    );
  }

  /// The gap between the strip and the menu it rides on — tight enough that

  /// the pair reads as one stack, wide enough to keep both borders visible.

  static const _menuReactionGap = 4.0;

  static const _expandedPickerSize = Size(300, 268);

  Widget _expandedReactionPicker(MessageReactionAvailability availability) {
    final store = EmojiStore.shared;
    final palette = MessageActionPalette.of(context);
    final packs = availability.allowArbitraryCustom
        ? store.customPacks
        : const <CustomEmojiPack>[];
    return Container(
      width: _expandedPickerSize.width,
      height: _expandedPickerSize.height,
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 12)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(child: _reactionContent(packs, availability, palette)),
          _reactionTabStrip(packs, palette),
        ],
      ),
    );
  }

  Widget _reactionContent(
    List<CustomEmojiPack> packs,
    MessageReactionAvailability availability,
    MessageActionPalette palette,
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
                      color: palette.foreground,
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
                      color: palette.foreground,
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

  Widget _reactionTabStrip(List packs, MessageActionPalette palette) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.divider, width: 0.5)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        children: [
          _reactionTab2(
            'standard',
            AppIcon(
              HeroAppIcons.solidFaceSmile,
              size: 22,
              color: palette.foreground.withValues(alpha: 0.7),
            ),
          ),
          for (final pack in packs)
            _reactionTab2(
              pack.id.toString(),
              pack.emoji.isNotEmpty && pack.emoji.first.customEmojiId != 0
                  ? CustomEmojiView(
                      id: pack.emoji.first.customEmojiId,
                      size: 26,
                      color: palette.foreground,
                    )
                  : AppIcon(
                      HeroAppIcons.objectGroup,
                      size: 20,
                      color: palette.foreground.withValues(alpha: 0.7),
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
            child: SizedBox(
              width: 40,
              height: 36,
              child: Center(
                child: AppIcon(
                  HeroAppIcons.gear,
                  size: 21,
                  color: palette.foreground.withValues(alpha: 0.7),
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
