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

import '../app/pip_bounds_debug_overlay.dart';
import '../app/video_split_controller.dart';
import '../auth/telegram_country_names.dart';
import '../call/call_manager.dart';
import '../channels/topic_chat_view.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/full_page_back_swipe.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../media/app_asset_picker.dart';
import '../moments/story_viewer_view.dart';
import '../notifications/notification_controller.dart';
import '../profile/profile_detail_view.dart';
import '../settings/ai_settings_controller.dart';
import '../settings/apple_pcc_api.dart';
import '../settings/blocked_user_service.dart';
import '../settings/business_tools_views.dart';
import '../settings/developer_mode_controller.dart';
import '../settings/keyword_blocker.dart';
import '../settings/quick_reaction_settings_view.dart';
import '../settings/sensitive_content_controller.dart';
import '../settings/topic_group_display_mode.dart';
import '../settings/translation_api.dart';
import '../settings/translation_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../theme/telegram_cloud_theme.dart';
import '../theme/theme_controller.dart';
import 'apple_pcc_unread_summary_provider.dart';
import 'blocked_message_runs.dart';
import 'channel_direct_messages_service.dart';
import 'channel_direct_messages_view.dart';
import 'chat_auto_scroll_policy.dart';
import 'chat_first_contact_card.dart';
import 'chat_first_contact_info.dart';
import 'chat_info_view.dart';
import 'chat_input_bar.dart';
import 'chat_media_drop_region.dart';
import 'chat_message_merge.dart';
import 'chat_picker_view.dart';
import 'chat_scroll_metrics.dart';
import 'chat_search_view.dart';
import 'chat_session_cache.dart';
import 'chat_unread_progress.dart';
import 'chat_view_model.dart';
import 'chat_wallpaper.dart';
import 'checklist_composer_view.dart';
import 'custom_emoji.dart';
import 'emoji_store.dart';
import 'emoji_text_controller.dart';
import 'forward_options.dart';
import 'full_image_viewer.dart';
import 'image_edit_view.dart';
import 'link_handler.dart';
import 'media_album_layout.dart';
import 'media_library_saver.dart';
import 'media_send_preview_view.dart';
import 'message_action_menu.dart';
import 'message_bubble.dart';
import 'message_replies_sheet.dart';
import 'music_player_controller.dart';
import 'openai_compatible_unread_summary_provider.dart';
import 'outgoing_attachment.dart';
import 'poll_results_view.dart';
import 'quick_reaction_choice.dart';
import 'rich_text_composer_view.dart';
import 'shared_contact_sheet.dart';
import 'sticker_set_detail_view.dart';
import 'sticker_viewer.dart';
import 'telegram_mini_app_view.dart';
import 'transcript_pivot_partition.dart';
import 'unread_chat_summary_models.dart';
import 'unread_chat_summary_service.dart';
import 'unread_chat_summary_view.dart';
import 'video_playback_queue.dart';
import 'video_player_view.dart';

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
  }) => service.summarize(snapshot, onProgress: onProgress);

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
            borderRadius: BorderRadius.circular(16),
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
                  fontWeight: FontWeight.w700,
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
                borderRadius: BorderRadius.circular(5),
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
            fontWeight: FontWeight.w700,
            color: color,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

enum _MediaEditAction { edit, replace, delete }

enum _MessageEditorMode { plain, richText }

class _PlainMessageEditResult {
  const _PlainMessageEditResult(this.text, this.entities);

  final String text;
  final List<Map<String, dynamic>> entities;
}

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

class _MessageEditorModeDialog extends StatelessWidget {
  const _MessageEditorModeDialog();

  @override
  Widget build(BuildContext context) {
    return const _ChatEditChoiceDialog<_MessageEditorMode>(
      title: AppStringKeys.chatEditMessageTitle,
      choices: [
        (
          value: _MessageEditorMode.plain,
          icon: HeroAppIcons.font,
          label: AppStringKeys.chatEditPlainText,
          destructive: false,
        ),
        (
          value: _MessageEditorMode.richText,
          icon: HeroAppIcons.wandMagicSparkles,
          label: AppStringKeys.composerRichText,
          destructive: false,
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
          borderRadius: BorderRadius.circular(14),
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
                  fontWeight: FontWeight.w700,
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

class _PlainMessageEditDialog extends StatefulWidget {
  const _PlainMessageEditDialog({
    required this.initialText,
    required this.initialEntities,
  });

  final String initialText;
  final List<Map<String, dynamic>> initialEntities;

  @override
  State<_PlainMessageEditDialog> createState() =>
      _PlainMessageEditDialogState();
}

class _PlainMessageEditDialogState extends State<_PlainMessageEditDialog> {
  late final EmojiTextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = EmojiTextEditingController()
      ..setFormattedText(widget.initialText, widget.initialEntities);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final (text, entities) = _controller.toFormatted();
    Navigator.of(context).pop(_PlainMessageEditResult(text, entities));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Center(
        child: Container(
          width: math.min(MediaQuery.sizeOf(context).width - 40, 480),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
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
              Text(
                AppStringKeys.chatEditMessageTitle.l10n(context),
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                constraints: const BoxConstraints(
                  minHeight: 88,
                  maxHeight: 220,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: c.searchFill,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: EditableText(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    height: 1.35,
                  ),
                  cursorColor: AppTheme.brand,
                  backgroundCursorColor: c.textTertiary,
                  keyboardType: TextInputType.multiline,
                  maxLines: null,
                  textInputAction: TextInputAction.newline,
                  selectionColor: AppTheme.brand.withValues(alpha: 0.24),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _PlainEditButton(
                    label: AppStringKeys.countryPickerCancel,
                    color: c.textSecondary,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  _PlainEditButton(
                    label: AppStringKeys.messageActionEdit,
                    color: AppTheme.brand,
                    onTap: _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlainEditButton extends StatelessWidget {
  const _PlainEditButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label.l10n(context),
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.none,
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
    this.initialMessageId,
    this.seedMessage,
    this.showBackButton = true,
    this.headerHeight = 48,
    this.headerColor,
    this.showHeaderDivider = true,
    this.headerBottom,
    this.headerBottomHeight = 44,
    this.onOpenTopicMode,
    this.onBack,
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
  final ValueChanged<int?>? onOpenTopicMode;
  final VoidCallback? onBack;

  @override
  State<ChatView> createState() => _ChatViewState();
}

/// Drops reusable transcript and scroll snapshots after an OS memory warning.
/// The active chat owns its own view model and is not affected.
void clearChatMemoryCaches() {
  _ChatViewState._sessionCache.clear();
  _ChatViewState._sessionScrollSnapshots.clear();
}

class _TranscriptEntry {
  _TranscriptEntry(this.messages, this.startIndex);

  final List<ChatMessage> messages;
  final int startIndex;

  ChatMessage get first => messages.first;
  ChatMessage get last => messages.last;
  bool get isBlockedRun =>
      messages.isNotEmpty && messages.every((message) => message.blockedByUser);
  bool get isImageGroup => messages.length > 1 && !isBlockedRun;

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
    this.pivotMessageId,
    this.anchorMessageId,
    this.anchorViewportOffset,
  });

  final double pixels;
  final bool wasAtLoadedBottom;
  final int? pivotMessageId;
  final int? anchorMessageId;
  final double? anchorViewportOffset;
}

class _ChatViewState extends State<ChatView> {
  late final bool _openAtLatest;
  late final _ChatScrollSnapshot? _sessionScrollSnapshot;
  late final ChatSessionRenderState? _sessionRenderState;
  late bool _olderHistoryExhaustedHint;
  late final ChatViewModel _vm;
  late final ScrollController _scroll;
  final _pinnedKey = GlobalKey(); // the pinned message's row, for scroll-to
  final _targetKey = GlobalKey(); // arbitrary linked/anchored message row
  final _unreadKey = GlobalKey(); // the "以下为新消息" divider, for entry scroll
  final _transcriptViewportKey = GlobalKey();
  final _newerTranscriptSliverKey = GlobalKey();
  final _firstContactLayoutKey = GlobalKey();
  final Map<int, GlobalKey> _entryVisibilityKeys = <int, GlobalKey>{};
  Map<int, _TranscriptEntry> _trackedTranscriptEntries = const {};
  TranscriptPivot? _transcriptPivot;
  bool _transcriptPivotFrozen = false;
  bool _transcriptPivotFreezeScheduled = false;
  late int _historyWindowRevision;
  late int _historyWindowInvalidationRevision;
  final Set<int> _reportedVisibleMessageIds = <int>{};
  final Set<int> _expandedBlockedRunIds = <int>{};
  bool _unreadProgressUpdateScheduled = false;
  ChatMessage? _actionTarget;
  Rect? _actionRect; // global bounds of the long-pressed bubble
  MessageActionSource _actionSource = MessageActionSource.normal;
  bool _reactionExpanded = false; // full reaction picker vs. quick bar
  String _reactionTab = 'standard'; // 'standard' or a custom-emoji pack id
  int _lastCount = 0;
  bool _didInitialScroll = false; // one-time entry positioning has run
  bool _showJumpDown = false; // scrolled up → show jump-to-bottom button
  bool _bannerDismissed = false; // "N条新消息" banner dismissed / caught up
  Timer? _bannerTimer; // auto-hides the banner a few seconds after it appears
  Timer? _readSyncTimer;
  int? _scrollTargetId;
  int? _lastNewestMessageId;
  int? _lastOldestMessageId;
  final ChatUnreadProgress _unreadProgress = ChatUnreadProgress();
  int get _liveNewMessageCount => _unreadProgress.liveCount;
  int get _remainingUnreadCount => _liveNewMessageCount > 0
      ? _liveNewMessageCount
      : _showEntryUnreadBanner
      ? _entryUnreadCount
      : _unreadProgress.remaining(initialUnreadCount: _vm.unreadCount);
  int _entryUnreadCount = 0;
  int _entryLastReadInboxId = 0;
  int? _entryFirstUnreadMessageId;
  bool _showEntryUnreadBanner = false;
  double _keyboardInset = 0;
  bool _shortTranscriptFillScheduled = false;
  bool _isFillingShortTranscript = false;
  int _shortTranscriptFillGeneration = 0;
  bool _shortFirstContactRevealScheduled = false;
  bool _showingFullyVisibleFirstContactHistory = false;
  bool _transcriptViewportClaimedByUser = false;
  bool _loadingLatestFromAnchor = false;
  bool _initialTranscriptReady = false;
  final Set<int> _transcriptPointersDown = <int>{};
  bool _bottomScrollScheduled = false;
  bool _scheduledBottomAnimated = true;
  int _scheduledBottomGeneration = 0;
  final _bottomFollow = ChatBottomFollowCoordinator();
  final Set<int> _selectedMessageIds = {};
  int? _selectionAnchorId;
  bool _selectionScrollingUp = false;
  double _lastScrollPixels = 0;
  bool _backSwipePopping = false;
  bool _loadingOlderFromScroll = false;
  final OldestHistoryPullController _olderHistoryPull =
      OldestHistoryPullController();
  bool _revealLoadedOlderPage = false;
  bool _loadedOlderRevealPending = false;
  bool _loadedOlderRevealScheduled = false;
  bool _wasLoadingOlder = false;
  bool _maintainSessionScrollAnchor = false;
  ChatThemeStyle? _resolvedChatThemeStyle;
  TelegramCloudTheme? _resolvedCloudTheme;
  bool _themingEnabled = true;
  bool _sessionAnchorMaintenanceScheduled = false;
  bool _maintainRestoredBottom = false;
  final _restoredBottomCorrection = ChatBottomCorrectionCoordinator();
  bool _openingUnreadMention = false;
  bool _openingUnreadSummary = false;
  bool _exitStatePrepared = false;
  bool _notificationVisibilityRegistered = false;

  /// Gap (seconds) between messages that triggers a fresh time separator.
  static const _separatorGap = 300;
  static const _initialTargetAlignment = 0.30;
  static const _initialUnreadAlignment = 0.12;
  static const _pendingTranscriptOrderId = 0x7FFFFFFFFFFFFFFF;
  static OverlayEntry? _globalPictureInPictureVideo;
  static final Map<int, _ChatScrollSnapshot> _sessionScrollSnapshots = {};
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
    _wallpaperController.addListener(_onWallpaperChanged);
    unawaited(_wallpaperController.load(widget.chatId));
    unawaited(_wallpaperController.loadDefaultWallpaper(dark: false));
    unawaited(_wallpaperController.loadDefaultWallpaper(dark: true));
    unawaited(_wallpaperController.loadGlobalChatThemes());
    _openAtLatest = context.read<ThemeController>().openChatsAtLatest;
    _sessionRenderState = widget.initialMessageId == null
        ? _sessionCache.read(widget.chatId)
        : null;
    _olderHistoryExhaustedHint =
        _sessionRenderState?.olderHistoryExhausted ?? false;
    _sessionScrollSnapshot = widget.initialMessageId == null
        ? _sessionScrollSnapshots[widget.chatId]
        : null;
    final savedPivotMessageId = _sessionScrollSnapshot?.pivotMessageId;
    if (savedPivotMessageId != null) {
      _transcriptPivot = TranscriptPivot(savedPivotMessageId);
      _transcriptPivotFrozen = savedPivotMessageId != _pendingTranscriptOrderId;
    }
    final initialScrollPlan = chatInitialScrollPlan(
      hasCachedTranscript: _sessionRenderState?.messages.isNotEmpty ?? false,
      savedPixels: _sessionScrollSnapshot?.pixels,
      savedAtBottom: _sessionScrollSnapshot?.wasAtLoadedBottom ?? false,
    );
    _maintainRestoredBottom = initialScrollPlan.correctToBottomAfterLayout;
    final sessionScrollSnapshot = _sessionScrollSnapshot;
    _maintainSessionScrollAnchor =
        sessionScrollSnapshot?.anchorMessageId != null &&
        sessionScrollSnapshot?.anchorViewportOffset != null;
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
      sessionMessages: _sessionRenderState?.messages,
      sessionAnchoredHistory: _sessionRenderState?.anchoredHistory ?? false,
      sessionFirstContactInfo: _sessionRenderState?.firstContactInfo,
      seedMessage: widget.seedMessage,
    );
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
    }
    _vm.addListener(_onModel);
    _setScrollTarget(widget.initialMessageId);
    _vm.onAppear();
    _readSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _isAtLoadedBottom(80)) {
        _markReadAtBottomIfNeeded();
      }
    });
    // Sync blocked-user-hiding toggle from theme.
    final theme = context.read<ThemeController>();
    BlockedUserService.shared.enabled = theme.hideBlockedUserMessages;
    // Load premium status early so the message menu can correctly hide the
    // emoji add/表情包 actions for non-premium users (the menu reads it).
    EmojiStore.shared.loadIfNeeded();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notificationVisibilityRegistered) return;
    _notificationVisibilityRegistered = true;
    NotificationController.shared.registerVisibleChat(
      this,
      widget.chatId,
      () =>
          mounted &&
          (ModalRoute.of(context)?.isCurrent ?? false) &&
          TickerMode.valuesOf(context).enabled,
    );
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
    _saveSessionScrollSnapshot();
    _scheduleUnreadProgressUpdate();
    if (_selectionAnchorId != null && scrollingUp != _selectionScrollingUp) {
      setState(() => _selectionScrollingUp = scrollingUp);
    }
    if (pos.userScrollDirection == ScrollDirection.forward &&
        isNearOldest(pos, threshold: 500)) {
      unawaited(_loadOlderFromScroll());
    }
    if (_vm.anchoredHistory &&
        pos.userScrollDirection == ScrollDirection.reverse &&
        isNearLatest(pos, threshold: 36)) {
      unawaited(_returnToLatest());
    }
    final nearBottom = _isNearBottom(80);
    if (_isAtLoadedBottom(1)) _autoScrollPolicy.returnToBottom();
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
    if (_initialTranscriptReady &&
        notification.direction != ScrollDirection.idle) {
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
      if (!mounted ||
          !_loadedOlderRevealPending ||
          !_scroll.hasClients ||
          _hasTranscriptPointerDown ||
          _isUserScrolling) {
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

  void _onTranscriptPointerDown(PointerDownEvent event) {
    _transcriptPointersDown.add(event.pointer);
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
    _scheduleSessionScrollAnchorMaintenance();
    _scheduleRestoredBottomCorrection();
  }

  void _claimTranscriptViewport() {
    _cancelBottomFollow();
    ++_shortTranscriptFillGeneration;
    _transcriptViewportClaimedByUser = true;
    _showingFullyVisibleFirstContactHistory = false;
    _maintainSessionScrollAnchor = false;
    _maintainRestoredBottom = false;
    _transcriptPivotFrozen = true;
  }

  void _stopActiveTranscriptScroll() {
    if (!_scroll.hasClients || !_scroll.position.isScrollingNotifier.value) {
      return;
    }
    _scroll.jumpTo(_scroll.position.pixels);
  }

  void _saveSessionScrollSnapshot() {
    if (!_didInitialScroll ||
        !_initialTranscriptReady ||
        _maintainSessionScrollAnchor ||
        !_scroll.hasClients ||
        widget.initialMessageId != null) {
      return;
    }
    final pos = _scroll.position;
    if (!pos.hasContentDimensions) return;
    final wasAtLoadedBottom = _isAtLoadedBottom(80);
    final anchor = wasAtLoadedBottom ? null : _captureSessionScrollAnchor();
    _sessionScrollSnapshots[widget.chatId] = _ChatScrollSnapshot(
      pixels: clampScrollOffset(pos, pos.pixels),
      wasAtLoadedBottom: wasAtLoadedBottom,
      pivotMessageId: _transcriptPivot?.cutoffMessageId,
      anchorMessageId: anchor?.messageId,
      anchorViewportOffset: anchor?.viewportOffset,
    );
  }

  void _prepareExitState() {
    if (_exitStatePrepared) return;
    _exitStatePrepared = true;
    if (!_maintainSessionScrollAnchor) _saveSessionScrollSnapshot();
    _cacheCurrentTranscript();
    if (_isAtLoadedBottom(80)) {
      unawaited(_vm.markLoadedMessagesRead());
    }
  }

  void _cacheCurrentTranscript() {
    if (widget.initialMessageId != null || !_vm.initialLoaded) return;
    _sessionCache.store(
      chatId: widget.chatId,
      messages: _vm.messages,
      anchoredHistory: _vm.anchoredHistory,
      olderHistoryExhausted: !_vm.hasOlderHistory || _olderHistoryExhaustedHint,
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
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _prepareExitState();
      },
      child: child,
    );
  }

  Widget _withBackSwipe(Widget child) {
    return FullPageBackSwipe(
      enabled: _canBackSwipe,
      onBack: () => unawaited(_popFromBackSwipe()),
      child: child,
    );
  }

  ({int messageId, double viewportOffset})? _captureSessionScrollAnchor() {
    final viewportContext = _transcriptViewportKey.currentContext;
    final viewportRenderObject = viewportContext?.findRenderObject();
    if (viewportRenderObject is! RenderBox || !viewportRenderObject.attached) {
      return null;
    }
    final viewportTop = viewportRenderObject.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportRenderObject.size.height;
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
      final itemTop = itemRenderObject.localToGlobal(Offset.zero).dy;
      final itemBottom = itemTop + itemRenderObject.size.height;
      if (itemBottom <= viewportTop || itemTop >= viewportBottom) continue;
      if (itemTop >= viewportTop) {
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
    return (
      messageId: anchorMessageId,
      viewportOffset: anchorTop - viewportTop,
    );
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
    final viewportOrigin = viewportRenderObject.localToGlobal(Offset.zero);
    final viewportRect = viewportOrigin & viewportRenderObject.size;
    var changed = false;
    final newlyVisible = <ChatMessage>[];

    for (final entry in _trackedTranscriptEntries.entries) {
      final itemContext = _entryVisibilityKeys[entry.key]?.currentContext;
      final itemRenderObject = itemContext?.findRenderObject();
      if (itemRenderObject is! RenderBox || !itemRenderObject.attached) {
        continue;
      }
      final itemOrigin = itemRenderObject.localToGlobal(Offset.zero);
      final itemRect = itemOrigin & itemRenderObject.size;
      if (!itemRect.overlaps(viewportRect)) continue;

      for (final message in entry.value.messages) {
        if (message.isOutgoing || message.isService) continue;
        if (_reportedVisibleMessageIds.add(message.id)) {
          newlyVisible.add(message);
        }
        changed =
            _unreadProgress.markVisible(
              messageId: message.id,
              initialUnread: message.id > _vm.lastReadInboxId,
            ) ||
            changed;
      }
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
  }

  void _scheduleScrollToBottom({bool animated = true}) {
    final generation = _bottomFollow.begin();
    _scheduledBottomGeneration = generation;
    if (_bottomScrollScheduled) {
      _scheduledBottomAnimated = _scheduledBottomAnimated && animated;
      return;
    }
    _bottomScrollScheduled = true;
    _scheduledBottomAnimated = animated;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shouldAnimate = _scheduledBottomAnimated;
      final scheduledGeneration = _scheduledBottomGeneration;
      _bottomScrollScheduled = false;
      _scheduledBottomAnimated = true;
      if (!_bottomFollow.isCurrent(scheduledGeneration) ||
          !_canFollowLoadedBottom()) {
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
    _autoScrollPolicy.returnToBottom();
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
      schedulePostFrame: (callback) {
        WidgetsBinding.instance.addPostFrameCallback((_) => callback());
      },
      canFollow: _canFollowLoadedBottom,
      distanceToLatest: () =>
          (_loadedBottomOffset - _scroll.position.pixels).abs(),
      latestExtent: () => _loadedBottomOffset,
      correct: () => _scroll.jumpTo(_loadedBottomOffset),
      settled: () {
        _markReadAtBottomIfNeeded();
        _clearBottomIndicatorsIfNeeded();
        _saveSessionScrollSnapshot();
      },
    );
  }

  void _cancelBottomFollow() {
    _bottomFollow.cancel();
  }

  Future<void> _returnToLatest() async {
    if (_loadingLatestFromAnchor) return;
    _cancelSessionScrollAnchorMaintenance();
    _autoScrollPolicy.returnToBottom();
    if (!_vm.anchoredHistory) {
      _setScrollTarget(null);
      if (_liveNewMessageCount > 0) {
        setState(() {
          _unreadProgress.clearLiveMessages();
          _bannerDismissed = _vm.unreadCount <= 0;
        });
      }
      _scheduleScrollToBottom();
      unawaited(_vm.markLoadedMessagesRead());
      return;
    }
    _loadingLatestFromAnchor = true;
    _setScrollTarget(null);
    try {
      final ok = await _vm.loadLatestHistory();
      if (!ok) return;
      if (!mounted) return;
      setState(() {
        _unreadProgress.clearLiveMessages();
        _bannerDismissed = _vm.unreadCount <= 0;
      });
      _scheduleScrollToBottom();
      unawaited(_vm.markLoadedMessagesRead());
    } finally {
      _loadingLatestFromAnchor = false;
    }
  }

  void _markReadAtBottomIfNeeded() {
    if (!_vm.initialLoaded || _vm.messages.isEmpty || _vm.anchoredHistory) {
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
      unawaited(_returnToLatest());
      return;
    }
    _scheduleScrollToBottom();
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
    _autoScrollPolicy.returnToBottom();
    _setScrollTarget(null);
    if (_vm.anchoredHistory) {
      unawaited(_returnToLatest());
      return;
    }
    _scheduleScrollToBottom(animated: false);
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

  int? _firstLoadedEntryUnreadMessageId() => firstUnreadMessageIdAfterBoundary(
    incomingMessageIds: _vm.messages
        .where((message) => !message.isOutgoing && !message.isService)
        .map((message) => message.id),
    lastReadInboxId: _entryLastReadInboxId,
  );

  /// Jump to the unread boundary captured when the chat opened. The live TDLib
  /// boundary may already point at the newest message after the chat is marked
  /// read, so it cannot be used to resolve this button later.
  Future<void> _jumpToFirstUnread() async {
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
      await _vm.loadAroundMessage(entryBoundaryId, scrollToTarget: false);
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
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
      return;
    }
    _entryFirstUnreadMessageId = targetMessageId;
    await _scrollToMessage(
      targetMessageId,
      alignment: _initialUnreadAlignment,
      forceAlignment: true,
    );
  }

  void _onModel() {
    if (!mounted) return;
    final olderLoadFinished = _wasLoadingOlder && !_vm.isLoadingOlder;
    _wasLoadingOlder = _vm.isLoadingOlder;
    final oldest = _oldestServerMessage(_vm.messages);
    final previousOldestId = _lastOldestMessageId;
    final prependedOlder =
        oldest != null &&
        previousOldestId != null &&
        oldest.id < previousOldestId;
    final hydratedShortTranscript = shouldRebaseForHydratedOlderPage(
      prependedOlder: prependedOlder,
      latestArmWasShort: _isTranscriptShort(),
      historyFillInFlight: _isFillingShortTranscript || _loadingOlderFromScroll,
      revealRequested: _revealLoadedOlderPage,
    );
    final wasPinnedToLoadedBottom =
        _didInitialScroll &&
        !_hasTranscriptPointerDown &&
        !_isUserScrolling &&
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
        _sessionScrollSnapshots.remove(widget.chatId);
      } else if (!preservesSavedCoordinate) {
        _olderHistoryExhaustedHint = false;
      }
    }
    if (shouldRebasePendingTranscriptPivot(
      pivot: _transcriptPivot,
      pendingOrderId: _pendingTranscriptOrderId,
      hasServerMessage: _vm.messages.any(
        (message) => !isPendingChatMessage(message) && message.id > 0,
      ),
    )) {
      _resetTranscriptPivot();
    }
    if (hydratedShortTranscript ||
        (!_transcriptPivotFrozen &&
            _vm.initialLoaded &&
            !identical(_transcriptCacheMessages, _vm.messages))) {
      // Cold local pages may be followed by a larger remote hydration. Until
      // the latest arm fills a viewport (or the user scrolls), let that fuller
      // initial window establish the fixed cutoff.
      _resetTranscriptPivot();
    }
    final liveIncomingMessageIds = _vm.consumeLiveIncomingMessageIds();
    if (_vm.messages.length != _lastCount) {
      final wasNearBottom = _isNearBottom(72);
      final previousNewestId = _lastNewestMessageId;
      final newest = _latestServerMessage(_vm.messages);
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
        _loadedOlderRevealPending = true;
        _scheduleLoadedOlderReveal();
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
      _setScrollTarget(target);
      if (_didInitialScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensureMessageVisible(target);
        });
      }
    }
    // Telegram-style entry: once the initial history (incl. the unread
    // boundary) is loaded, jump to the first unread message — or stay at the
    // bottom when caught up. Runs exactly once per chat open.
    if (!_didInitialScroll && _vm.initialLoaded) {
      _entryUnreadCount = _vm.unreadCount;
      _entryLastReadInboxId = _vm.lastReadInboxId;
      final firstEntryUnreadMessageId = _firstLoadedEntryUnreadMessageId();
      final loadedIncomingUnreadCount = _vm.messages
          .where(
            (message) =>
                !message.isOutgoing &&
                !message.isService &&
                message.id > _entryLastReadInboxId,
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
    if (wasPinnedToLoadedBottom && !_bottomScrollScheduled) {
      _scheduleScrollToBottom(animated: false);
    }
    setState(() {});
    _cacheCurrentTranscript();
    _scheduleSessionScrollAnchorMaintenance();
    _scheduleRestoredBottomCorrection();
  }

  void _setScrollTarget(int? messageId) {
    if (messageId != null) {
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
      if (!mounted || !_maintainSessionScrollAnchor || !_scroll.hasClients) {
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
    setState(() => _initialTranscriptReady = true);
    _saveSessionScrollSnapshot();
    _scheduleShortTranscriptFill();
  }

  Future<void> _restoreSessionScrollPosition() async {
    final snapshot = _sessionScrollSnapshot;
    if (snapshot == null || !_scroll.hasClients) return;
    if (_hasSessionScrollAnchor) {
      final estimate = _estimateMessageOffset(snapshot.anchorMessageId!, 0);
      if (estimate != null) _scroll.jumpTo(estimate);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
      if (_restoreSessionScrollAnchor(snapshot)) {
        await WidgetsBinding.instance.endOfFrame;
        if (mounted && _scroll.hasClients) {
          _restoreSessionScrollAnchor(snapshot);
        }
        return;
      }
    }
    _jumpToSessionScrollSnapshot(snapshot);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;

    var guard = 0;
    while (mounted &&
        _scroll.hasClients &&
        _vm.canLoadOlder &&
        snapshot.pixels + 24 < _scroll.position.minScrollExtent &&
        guard < 6) {
      final loaded = await _vm.loadOlderLocal();
      if (!loaded) break;
      await WidgetsBinding.instance.endOfFrame;
      guard++;
    }

    if (!mounted || !_scroll.hasClients) return;
    _jumpToSessionScrollSnapshot(snapshot);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scroll.hasClients) return;
    _jumpToSessionScrollSnapshot(snapshot);
    _saveSessionScrollSnapshot();
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
    if (!_scroll.hasClients) return;
    _jumpToInitialEstimate();
    for (var i = 0; i < 3; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;
      await _correctInitialPosition();
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
    final target = widget.initialMessageId ?? _scrollTargetId;
    if (target != null) {
      _setScrollTarget(target);
      return _estimateMessageOffset(target, _initialTargetAlignment);
    }
    if (_vm.anchoredHistory) {
      return null;
    }
    if (_shouldOpenAtBottom) {
      return max;
    }
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    if (_vm.unreadCount <= 0 || i < 0 || !boundaryLoaded) {
      if (_vm.unreadCount > 0 && _vm.lastReadInboxId > 0) {
        _setScrollTarget(_vm.lastReadInboxId);
        return _estimateMessageOffset(
          _vm.lastReadInboxId,
          _initialTargetAlignment,
        );
      }
      return max;
    }
    return _estimateMessageOffset(
      _vm.messages[i].id,
      _initialUnreadAlignment,
      beforeUnreadDivider: true,
    );
  }

  Future<bool> _correctInitialPosition() async {
    if (!_scroll.hasClients) return false;
    final target = widget.initialMessageId ?? _scrollTargetId;
    if (target != null) {
      _setScrollTarget(target);
      final corrected = await _ensureKeyVisible(
        _targetKey,
        alignment: _initialTargetAlignment,
      );
      if (corrected && mounted && _scrollTargetId == target) {
        setState(() => _setScrollTarget(null));
      }
      return corrected;
    }
    if (_vm.anchoredHistory) return true;
    if (_shouldOpenAtBottom) {
      _scrollToBottom();
      unawaited(_vm.markLoadedMessagesRead());
      return true;
    }
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    if (_vm.unreadCount > 0 && i >= 0 && boundaryLoaded) {
      final corrected = await _ensureKeyVisible(
        _unreadKey,
        alignment: _initialUnreadAlignment,
      );
      if (corrected) return true;
      return false;
    }
    if (_vm.unreadCount > 0 && _vm.lastReadInboxId > 0) {
      _setScrollTarget(_vm.lastReadInboxId);
      final corrected = await _ensureKeyVisible(
        _targetKey,
        alignment: _initialTargetAlignment,
      );
      if (corrected) return true;
    }
    _scrollToBottom();
    return true;
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
    final partition = _partitionTranscript(entries);
    final messages = _transcriptCacheMessages ?? _vm.messages;
    final position = _scroll.position;
    final viewport = _scroll.position.viewportDimension;
    final targetIsBeforePivot = partition.beforePivot.contains(targetEntry);

    if (targetIsBeforePivot) {
      final targetIndex = partition.beforePivot.indexOf(targetEntry);
      var targetTop = 0.0;
      for (var i = targetIndex; i < partition.beforePivot.length; i++) {
        targetTop -= _estimatedEntryExtent(partition.beforePivot[i]);
      }
      if (!beforeUnreadDivider &&
          _needsUnreadDivider(targetEntry.startIndex, messages: messages)) {
        targetTop += _estimatedUnreadDividerExtent;
      }
      return clampScrollOffset(position, targetTop - viewport * alignment);
    }

    final targetIndex = partition.pivotAndAfter.indexOf(targetEntry);
    var targetTop = 0.0;
    for (var i = 0; i < targetIndex; i++) {
      targetTop += _estimatedEntryExtent(partition.pivotAndAfter[i]);
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
    _autoScrollPolicy.returnToBottom();
    if (_positionShortFirstContactHistoryIfItFits(requireAtLatest: false)) {
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

  Future<void> _fillShortTranscript() async {
    if (!mounted ||
        !_scroll.hasClients ||
        !_vm.initialLoaded ||
        _vm.anchoredHistory ||
        _maintainSessionScrollAnchor ||
        _transcriptPivotFrozen ||
        _autoScrollPolicy.preservesViewport ||
        _scrollTargetId != null ||
        !_vm.canLoadOlder) {
      return;
    }
    if (!_isTranscriptShort()) return;

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
    if (_canContinueShortTranscriptFill(generation)) {
      if (loadedAny) _positionAfterShortFill();
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
        !_vm.anchoredHistory &&
        !_maintainSessionScrollAnchor &&
        !_transcriptPivotFrozen &&
        !_autoScrollPolicy.preservesViewport &&
        _scrollTargetId == null;
  }

  bool _isTranscriptShort() {
    if (!_scroll.hasClients) return true;
    // With a center sliver, only the after-center arm defines the latest edge.
    // A large negative min extent says nothing about whether that arm fills
    // the viewport.
    return _scroll.position.maxScrollExtent <= 24;
  }

  void _positionAfterShortFill() {
    if (_shouldOpenAtBottom) {
      _scrollToBottom();
      return;
    }
    final i = _firstUnreadIndex();
    final boundaryLoaded = _isUnreadBoundaryLoaded();
    if (_vm.unreadCount > 0 && i >= 0 && boundaryLoaded) {
      final ctx = _unreadKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.12);
        return;
      }
    }
    _scrollToBottom();
  }

  bool _isUnreadBoundaryLoaded() {
    if (_vm.messages.isEmpty) return false;
    return _vm.lastReadInboxId <= 0 ||
        _vm.messages.first.id <= _vm.lastReadInboxId;
  }

  bool get _canBackSwipe =>
      widget.showBackButton && !_isSelecting && _actionTarget == null;

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
      final viewportTop = viewportRenderObject.localToGlobal(Offset.zero).dy;
      final viewportBottom = viewportTop + viewportRenderObject.size.height;
      var bestDistance = double.infinity;
      int? bestIndex;
      for (final trackedEntry in _trackedTranscriptEntries.entries) {
        final itemContext =
            _entryVisibilityKeys[trackedEntry.key]?.currentContext;
        final itemRenderObject = itemContext?.findRenderObject();
        if (itemRenderObject is! RenderBox || !itemRenderObject.attached) {
          continue;
        }
        final itemTop = itemRenderObject.localToGlobal(Offset.zero).dy;
        final itemBottom = itemTop + itemRenderObject.size.height;
        if (itemBottom <= viewportTop || itemTop >= viewportBottom) continue;
        final distance = topEdge
            ? (itemTop <= viewportTop ? 0.0 : itemTop - viewportTop)
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
    NotificationController.shared.unregisterVisibleChat(this);
    _wallpaperController.removeListener(_onWallpaperChanged);
    _bannerTimer?.cancel();
    _readSyncTimer?.cancel();
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
              borderRadius: BorderRadius.circular(16),
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

  Widget _messageBubble(ChatMessage message, int messageIndex) {
    _vm.ensureMessageCapabilities(message);
    return MessageBubble(
      message: message,
      peerTitle: _vm.peerTitle,
      peerPhoto: _vm.peerPhoto,
      isGroup: _vm.isGroup,
      meName: _vm.meName,
      mePhoto: _vm.mePhoto,
      meId: _vm.meId,
      showRepeat: _vm.canForwardContent && _isRepeatTail(messageIndex),
      onRepeat: () => _vm.repeatMessage(message),
      onLongPress: _isSelecting ? null : _showActionMenuForMessage,
      onDoubleTap: _isSelecting
          ? null
          : (m) => unawaited(_showTextSelection(m)),
      onReply: (m) => _vm.setReply(m),
      onAvatarTap: _openSenderProfile,
      onAvatarLongPress: (m) {
        if (_vm.isGroup && (m.senderName?.isNotEmpty ?? false)) {
          _vm.insertMention(m);
        }
      },
      onOpenReply: _scrollToMessage,
      onOpenComments: _openMessageComments,
      showCommentAttachment: _vm.isChannel,
      onOpenImage: _openImage,
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
      onToggleReaction: (r) => _vm.toggleReaction(message, r),
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
      hint: 'New option',
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
                borderRadius: BorderRadius.circular(16),
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
                        borderRadius: BorderRadius.circular(10),
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
    final action = await showSharedContactActions(context, contact);
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
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ChatView(chatId: chatId, title: contact.displayName),
            ),
          );
        } catch (_) {
          if (mounted) {
            showToast(context, AppStringKeys.topicPostContentActionFailed);
          }
        }
      case SharedContactAction.call:
        if (contact.userId > 0) {
          context.read<CallManager>().startCall(contact.userId, false);
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
    if (VideoSplitController.instance.isOpen) {
      VideoSplitController.instance.play(session);
      return;
    }
    if (VideoPiPController.instance.isOpen) {
      VideoPiPController.instance.play(session);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) => VideoPlaylistPlayerView(
          queue: session.queue,
          initialMuted: muted,
          onSwitchMode: (queue, mode) =>
              _switchVideoMode(routeContext, queue, mode),
        ),
      ),
    );
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
          thumb: candidate.image,
          width: candidate.imageWidth,
          height: candidate.imageHeight,
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
        _showVideoPictureInPicture(routeContext, session);
        Navigator.of(routeContext).maybePop();
      case VideoDisplayMode.split:
        VideoSplitController.instance.play(session);
        Navigator.of(routeContext).maybePop();
    }
  }

  static void _showVideoPictureInPicture(
    BuildContext context,
    VideoSplitSession initialSession,
  ) {
    final pip = VideoPiPController.instance;
    if (_globalPictureInPictureVideo != null) {
      pip.play(initialSession);
      return;
    }
    if (pip.isOpen) {
      pip.play(initialSession);
      return;
    }
    pip.play(initialSession);
    _globalPictureInPictureVideo?.remove();
    _globalPictureInPictureVideo = null;

    final overlay = Overlay.of(context, rootOverlay: true);
    final screen = MediaQuery.sizeOf(context);
    const margin = 16.0;
    var aspect = _sessionAspect(initialSession);
    var boxWidth = (screen.width * 0.46).clamp(220.0, 360.0);
    var boxHeight = (boxWidth / aspect).clamp(130.0, 260.0);
    boxWidth = boxHeight * aspect;
    var displayedVideoId = initialSession.video.id;
    var offset = Offset(
      screen.width - boxWidth - margin,
      screen.height - boxHeight - MediaQuery.paddingOf(context).bottom - 110,
    );

    late final OverlayEntry entry;
    void close() {
      entry.remove();
      if (_globalPictureInPictureVideo == entry) {
        _globalPictureInPictureVideo = null;
      }
      if (pip.session?.video.id == displayedVideoId) {
        pip.close();
      }
    }

    entry = OverlayEntry(
      builder: (overlayContext) => StatefulBuilder(
        builder: (context, setOverlayState) {
          final media = MediaQuery.sizeOf(context);
          final padding = MediaQuery.paddingOf(context);
          void clampFrame() {
            final maxWidth = math.max(80.0, media.width - margin * 2);
            final maxHeight = math.max(
              80.0,
              media.height - padding.top - padding.bottom - margin * 2,
            );
            if (boxWidth > maxWidth) {
              boxWidth = maxWidth;
              boxHeight = boxWidth / aspect;
            }
            if (boxHeight > maxHeight) {
              boxHeight = maxHeight;
              boxWidth = boxHeight * aspect;
            }
            final minX = math.min(margin, media.width - boxWidth);
            final maxX = math.max(minX, media.width - boxWidth - margin);
            final minY = math.min(
              padding.top + margin,
              media.height - boxHeight,
            );
            final maxY = math.max(
              minY,
              media.height - boxHeight - padding.bottom - margin,
            );
            offset = Offset(
              offset.dx.clamp(minX, maxX),
              offset.dy.clamp(minY, maxY),
            );
          }

          void syncSession(VideoSplitSession session) {
            if (session.video.id == displayedVideoId) return;
            displayedVideoId = session.video.id;
            aspect = _sessionAspect(session);
            boxHeight = (boxWidth / aspect).clamp(110.0, media.height * 0.72);
            boxWidth = boxHeight * aspect;
            clampFrame();
          }

          void move(DragUpdateDetails details) {
            setOverlayState(() {
              offset += details.delta;
              clampFrame();
            });
          }

          void resizeFromCorner(
            DragUpdateDetails details, {
            required int horizontalSign,
            required int verticalSign,
          }) {
            setOverlayState(() {
              final oldWidth = boxWidth;
              final oldHeight = boxHeight;
              final minW = math.min(180.0, media.width - margin * 2);
              final maxW = math.max(minW, media.width - margin * 2);
              final widthFromX = boxWidth + details.delta.dx * horizontalSign;
              final widthFromY =
                  boxWidth + details.delta.dy * verticalSign * aspect;
              final nextWidth =
                  (widthFromX - boxWidth).abs() > (widthFromY - boxWidth).abs()
                  ? widthFromX
                  : widthFromY;
              boxWidth = nextWidth.clamp(minW, maxW);
              boxHeight = boxWidth / aspect;
              if (boxHeight > media.height * 0.72) {
                boxHeight = media.height * 0.72;
                boxWidth = boxHeight * aspect;
              }
              if (boxHeight < 110) {
                boxHeight = 110;
                boxWidth = boxHeight * aspect;
              }
              if (horizontalSign < 0) {
                offset = offset.translate(oldWidth - boxWidth, 0);
              }
              if (verticalSign < 0) {
                offset = offset.translate(0, oldHeight - boxHeight);
              }
              clampFrame();
            });
          }

          return AnimatedBuilder(
            animation: pip,
            builder: (context, _) {
              final session = pip.session;
              if (session == null) return const SizedBox.shrink();
              syncSession(session);
              clampFrame();
              final showDebugBounds = context
                  .watch<DeveloperModeController>()
                  .showPiPBounds;
              return Positioned(
                left: offset.dx,
                top: offset.dy,
                width: boxWidth,
                height: boxHeight,
                child: Material(
                  type: MaterialType.transparency,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onPanUpdate: move,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: VideoPlayerView(
                              key: ValueKey(
                                '${session.video.id}:${session.messageId ?? 0}',
                              ),
                              video: session.video,
                              thumb: session.thumb,
                              width: session.width,
                              height: session.height,
                              presentation:
                                  VideoPlayerPresentation.pictureInPicture,
                              compactControls: true,
                              onClose: close,
                              sourceChatId: session.chatId,
                              messageId: session.messageId,
                              previousVideo: session.queue.previous,
                              nextVideo: session.queue.next,
                              onNavigate: (delta) {
                                final nextSession = session.moveBy(delta);
                                if (nextSession != null) pip.play(nextSession);
                              },
                              currentMode: VideoDisplayMode.pictureInPicture,
                              onSwitchMode: (mode) => _switchPiPSessionMode(
                                context,
                                close,
                                mode,
                                session,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _PiPCornerHandle(
                        alignment: Alignment.topLeft,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: -1,
                          verticalSign: -1,
                        ),
                      ),
                      _PiPCornerHandle(
                        alignment: Alignment.topRight,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: 1,
                          verticalSign: -1,
                        ),
                      ),
                      _PiPCornerHandle(
                        alignment: Alignment.bottomLeft,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: -1,
                          verticalSign: 1,
                        ),
                      ),
                      _PiPCornerHandle(
                        alignment: Alignment.bottomRight,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: 1,
                          verticalSign: 1,
                        ),
                      ),
                      if (showDebugBounds)
                        PiPBoundsDebugOverlay(
                          offset: offset,
                          size: Size(boxWidth, boxHeight),
                          viewport: media,
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
    _globalPictureInPictureVideo = entry;
    overlay.insert(entry);
  }

  void _openImage(ChatMessage message) {
    final pairs = _vm.messages
        .where((m) => m.isPhoto && m.image != null)
        .toList();
    final items = pairs.map((m) => m.image!).toList();
    final start = pairs.indexWhere((m) => m.id == message.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            FullImageViewer(items: items, startIndex: start < 0 ? 0 : start),
      ),
    );
  }

  void _openSticker(ChatMessage message) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StickerViewer(message: message),
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
    );
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
            telegramText(AppStringKeys.chatTodoSetSuccess),
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
            telegramText(AppStringKeys.chatTodoUnsetSuccess),
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
        if (sid != null) {
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StickerSetDetailView(setId: sid),
              ),
            ),
          );
        }
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
      final draft = await showModalBottomSheet<SuggestedPostDraft>(
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

  Future<void> _showTextSelection(ChatMessage message) async {
    if (message.text.isEmpty || !mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStrings.t(AppStringKeys.musicPlayerClose),
      barrierColor: Colors.black.withValues(alpha: 0.48),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, _, _) => _MessageTextSelectionDialog(
        text: message.text,
        onTranslate: _translateSelectedText,
        onAddToBlocklist: _addSelectionToBlocklist,
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _addSelectionToBlocklist(String selectedText) {
    final rule = _keywordCandidate(selectedText);
    if (rule.isEmpty) return;
    KeywordBlocker.shared.add(rule);
    if (!mounted) return;
    showToast(
      context,
      AppStrings.t(AppStringKeys.keywordBlockerRuleAdded, {'value1': rule}),
    );
  }

  Future<String?> _translateSelectedText(String selectedText) async {
    final sourceText = selectedText.trim();
    if (sourceText.isEmpty || !mounted) return null;
    final translation = context.read<TranslationController>();
    final targetLanguage = _translationTargetLanguage(translation);
    try {
      return switch (translation.provider) {
        TranslationProvider.iosSystem ||
        TranslationProvider.androidMlKit => NativeTranslationApi.translate(
          text: sourceText,
          sourceLanguageCode: 'autodetect',
          targetLanguageCode: targetLanguage,
        ),
        TranslationProvider.tdlib => _vm.translateText(
          sourceText,
          targetLanguage,
        ),
        _ => ThirdPartyTranslationApi.translate(
          provider: translation.provider,
          text: sourceText,
          sourceLanguageCode: 'autodetect',
          targetLanguageCode: targetLanguage,
          lingvaEndpoint: translation.lingvaEndpoint,
          libreTranslateEndpoint: translation.libreTranslateEndpoint,
          libreTranslateApiKey: translation.libreTranslateApiKey,
        ),
      };
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatTranslateFailed, {'value1': e}),
        );
      }
      return null;
    }
  }

  String _keywordCandidate(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 80) return normalized;
    return normalized.substring(0, 80).trim();
  }

  Future<void> _showReactionUsers(
    ChatMessage message,
    MessageReaction reaction,
  ) async {
    if (!mounted || message.reactions.isEmpty) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStrings.t(AppStringKeys.musicPlayerClose),
      barrierColor: Colors.black.withValues(alpha: 0.46),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => _ReactionUsersSheet(
        viewModel: _vm,
        message: message,
        initialReaction: reaction,
      ),
      transitionBuilder: (context, animation, _, child) {
        final offset =
            Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return SlideTransition(position: offset, child: child);
      },
    );
  }

  Future<bool> _translateMessage(
    ChatMessage message, {
    bool showErrors = true,
  }) async {
    final translation = context.read<TranslationController>();
    if (!translation.enabled) return true;
    final sourceText = _translationSourceText(message);
    if (sourceText.trim().isEmpty) return true;
    final targetLanguage = _translationTargetLanguage(translation);
    try {
      if (translation.provider == TranslationProvider.iosSystem ||
          translation.provider == TranslationProvider.androidMlKit) {
        await _vm.translateMessageExternally(
          message.id,
          targetLanguage,
          () => NativeTranslationApi.translate(
            text: sourceText,
            sourceLanguageCode: 'autodetect',
            targetLanguageCode: targetLanguage,
          ),
          showLoading: defaultTargetPlatform != TargetPlatform.iOS,
        );
      } else if (translation.provider == TranslationProvider.tdlib) {
        await _vm.translateMessage(message.id, targetLanguage);
      } else {
        await _vm.translateMessageExternally(
          message.id,
          targetLanguage,
          () => ThirdPartyTranslationApi.translate(
            provider: translation.provider,
            text: sourceText,
            sourceLanguageCode: 'autodetect',
            targetLanguageCode: targetLanguage,
            lingvaEndpoint: translation.lingvaEndpoint,
            libreTranslateEndpoint: translation.libreTranslateEndpoint,
            libreTranslateApiKey: translation.libreTranslateApiKey,
          ),
        );
      }
      return true;
    } catch (e) {
      if (!mounted) return false;
      if (showErrors) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatTranslateFailed, {'value1': e}),
        );
      }
      return false;
    }
  }

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
          if (message.contentType == 'messagePhoto') {
            await _editPhotoInPlace(message);
          } else {
            await _editMessageText(message);
          }
        case _MediaEditAction.replace:
          await _replaceMessageMedia(message);
        case _MediaEditAction.delete:
          await _deleteMessageMedia(message);
      }
      return;
    }
    await _editMessageText(message);
  }

  Future<void> _editMessageText(ChatMessage message) async {
    var premium = false;
    try {
      premium = await _vm.currentUserIsPremium();
    } catch (_) {}
    if (!mounted) return;
    var mode = _MessageEditorMode.plain;
    if (premium) {
      final selected = await showGeneralDialog<_MessageEditorMode>(
        context: context,
        barrierDismissible: true,
        barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
        barrierColor: Colors.black.withValues(alpha: 0.38),
        transitionDuration: const Duration(milliseconds: 170),
        pageBuilder: (_, _, _) => const _MessageEditorModeDialog(),
      );
      if (!mounted || selected == null) return;
      mode = selected;
    }
    if (mode == _MessageEditorMode.richText) {
      await _editMessageWithRichText(message);
    } else {
      await _editMessagePlain(message);
    }
  }

  Future<void> _editMessagePlain(ChatMessage message) async {
    final result = await showGeneralDialog<_PlainMessageEditResult>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.black.withValues(alpha: 0.38),
      transitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (_, _, _) => _PlainMessageEditDialog(
        initialText: _editableMessageText(message),
        initialEntities: [
          for (final entity in message.textEntities) entity.toTdJson(),
        ],
      ),
    );
    if (!mounted || result == null) return;
    try {
      if (_isEditableMediaMessage(message)) {
        await _vm.editMessageCaption(
          message.id,
          result.text,
          entities: result.entities,
        );
      } else {
        if (result.text.trim().isEmpty) {
          showToast(context, AppStringKeys.chatMessageRequired);
          return;
        }
        await _vm.editMessageText(
          message.id,
          result.text,
          entities: result.entities,
        );
      }
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  Future<void> _editPhotoInPlace(ChatMessage message) async {
    final image = message.image;
    if (image == null) return;
    final path = await TdFileCenter.shared.pathFor(image);
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      showToast(context, AppStringKeys.composerOpenAttachmentFailed);
      return;
    }
    final result = await Navigator.of(context).push<ImageEditResult>(
      MaterialPageRoute(
        builder: (_) => ImageEditView(
          sourcePath: path,
          initialCaption: _editableMessageText(message),
        ),
      ),
    );
    if (!mounted || result == null) return;
    try {
      await _vm.editMessageMedia(
        message.id,
        OutgoingAttachment(
          path: result.path,
          kind: OutgoingAttachmentKind.photo,
        ),
        caption: result.caption,
      );
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
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
    final text = message.text.trim();
    if (text.isEmpty || (text.startsWith('[') && text.endsWith(']'))) return '';
    final placeholders = <String>{
      telegramText(AppStringKeys.composerImagePreview),
      telegramText(AppStringKeys.chatVideoPlaceholder),
      telegramText(AppStringKeys.composerAnimatedEmojiPreview),
      telegramText(AppStringKeys.tdMessageGif),
      telegramText(AppStringKeys.tdMessageMusic),
      telegramText(AppStringKeys.channelsFileAttachment),
      if (message.document != null)
        telegramText(AppStringKeys.tdMessageFileWithName, {
          'value1': message.document!.fileName,
        }),
    };
    return placeholders.contains(text) ? '' : message.text;
  }

  String _mediaLabel(ChatMessage message) => switch (message.contentType) {
    'messagePhoto' => telegramText(AppStringKeys.composerImagePreview),
    'messageVideo' => telegramText(AppStringKeys.chatVideoPlaceholder),
    'messageAnimation' => telegramText(AppStringKeys.tdMessageGif),
    'messageAudio' => telegramText(AppStringKeys.tdMessageMusic),
    _ => telegramText(AppStringKeys.topicPostContentFile),
  };

  Future<void> _editMessageWithRichText(ChatMessage message) async {
    final result = await showRichTextComposerSheet(
      context,
      initialText: message.text,
      initialEntities: [
        for (final entity in message.textEntities) entity.toTdJson(),
      ],
      title: AppStringKeys.chatEditMessageTitle,
      submitText: AppStringKeys.messageActionEdit,
      hintText: AppStringKeys.tabMessages,
    );
    if (!mounted || result == null) return;
    if (result.text.trim().isEmpty && result.attachments.isEmpty) {
      showToast(context, AppStringKeys.chatMessageRequired);
      return;
    }
    try {
      var mediaStart = 0;
      if (result.attachments.isNotEmpty &&
          (message.contentType == 'messagePhoto' ||
              message.contentType == 'messageVideo')) {
        final media = result.attachments.first;
        final canReplaceMedia =
            media.kind == OutgoingAttachmentKind.photo ||
            media.kind == OutgoingAttachmentKind.video;
        if (canReplaceMedia) {
          await _vm.editMessageMedia(
            message.id,
            media,
            caption: result.text,
            entities: result.entities,
          );
          mediaStart = 1;
        }
      }
      if (mediaStart == 0 &&
          (result.text != message.text ||
              !_sameFormattedEntities(result.entities, message.textEntities))) {
        if (message.contentType == 'messagePhoto' ||
            message.contentType == 'messageVideo') {
          await _vm.editMessageCaption(
            message.id,
            result.text,
            entities: result.entities,
          );
        } else {
          await _vm.editMessageText(
            message.id,
            result.text,
            entities: result.entities,
          );
        }
      }
      final extras = result.attachments.skip(mediaStart).toList();
      if (extras.isNotEmpty) {
        await _vm.sendAttachments(extras);
        if (mounted) _onComposerMessageSent();
      }
    } catch (e) {
      if (mounted) showToast(context, '$e');
    }
  }

  bool _sameFormattedEntities(
    List<Map<String, dynamic>> edited,
    List<MessageTextEntity> original,
  ) {
    if (edited.length != original.length) return false;
    for (var i = 0; i < edited.length; i++) {
      final value = edited[i];
      final expected = original[i];
      final type = value['type'];
      if (value['offset'] != expected.offset ||
          value['length'] != expected.length ||
          type is! Map ||
          type['@type'] != expected.type ||
          type['url'] != expected.url ||
          type['user_id'] != expected.userId ||
          '${type['custom_emoji_id'] ?? ''}' !=
              '${expected.customEmojiId ?? ''}' ||
          type['language'] != expected.language) {
        return false;
      }
    }
    return true;
  }

  void _openSenderProfile(ChatMessage m) {
    if (m.senderIsChat) {
      final senderChatId = m.senderId;
      if (senderChatId == null) return;
      final senderTitle = (m.senderName ?? m.senderTitle ?? _vm.peerTitle)
          .trim();
      final title = senderTitle.isEmpty ? _vm.peerTitle : senderTitle;
      final Widget destination = senderChatId == widget.chatId
          ? ChatInfoView(chatId: senderChatId, title: title)
          : ChatView(chatId: senderChatId, title: title);
      Navigator.of(
        context,
      ).push(PageRouteBuilder<void>(pageBuilder: (_, _, _) => destination));
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

  void _openPeerProfile() {
    final uid = _vm.peerUserId;
    if (uid == null || uid <= 0) return;
    _openUserProfile(uid, _vm.peerTitle);
  }

  void _openUserProfile(int userId, String name) {
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
    context.read<CallManager>().startCall(uid, isVideo);
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

  Color? _effectiveOutgoingColor() {
    final chatColor = _resolvedChatThemeStyle?.outgoingColor;
    return chatColor ?? _resolvedCloudTheme?.outgoingColor;
  }

  Color? _effectiveOutgoingTextColor() =>
      _resolvedChatThemeStyle?.outgoingTextColor ??
      _resolvedCloudTheme?.outgoingTextColor;

  Color? _effectiveIncomingColor() =>
      _resolvedChatThemeStyle?.incomingColor ??
      _resolvedCloudTheme?.incomingColor;

  Color? _effectiveIncomingTextColor() =>
      _resolvedChatThemeStyle?.incomingTextColor ??
      _resolvedCloudTheme?.incomingTextColor;

  @override
  Widget build(BuildContext context) {
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
    _resolvedChatThemeStyle = !_themingEnabled
        ? null
        : chatThemeStyle ??
              (_resolvedCloudTheme == null
                  ? _wallpaperController.globalThemeStyleFor(dark: dark)
                  : null);
    // Keep blocked-user hiding toggle in sync with theme.
    BlockedUserService.shared.enabled = themeController.hideBlockedUserMessages;
    if (_vm.isAdministeredDirectMessagesGroup) {
      return ChannelDirectMessagesView(
        chatId: widget.chatId,
        title: widget.title,
      );
    }
    final showPeerRestrictionBlock =
        _vm.isPeerRestricted && _vm.messages.isEmpty;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    _syncKeyboardInset(keyboardInset);
    // Not a member, joinable, and nothing to preview → a custom join screen
    // (header + centered card) instead of the transcript + composer.
    if (!_vm.isMember && _vm.canJoin && _vm.messages.isEmpty) {
      return _withExitState(
        _withBackSwipe(
          Scaffold(
            backgroundColor: c.groupedBackground,
            body: _joinScreenBody(),
          ),
        ),
      );
    }
    return _withExitState(
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
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        showPeerRestrictionBlock
                            ? _header()
                            : (_isSelecting ? _selectionHeader() : _header()),
                        if (showPeerRestrictionBlock)
                          Expanded(child: _restrictedPeerBlockPage())
                        else ...[
                          Expanded(child: _transcriptLayer()),
                          _chatMusicPlayer(),
                          _isSelecting
                              ? _selectionActionBar()
                              : _composerArea(),
                        ],
                      ],
                    ),
                  ),
                  if (_actionTarget != null && !_isSelecting)
                    _actionMenuOverlay(),
                ],
              ),
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
          borderRadius: BorderRadius.circular(12),
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

  Widget _transcriptLayer() {
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
        if (!transcriptReady) Positioned.fill(child: _transcriptSkeleton()),
        if (transcriptReady && _vm.isLoadingOlder)
          Positioned(
            key: const ValueKey('chat-older-history-loading'),
            top: showPinnedTodo ? 72 : 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.colors.card.withValues(alpha: 0.94),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.colors.divider,
                      width: 0.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const AppActivityIndicator(size: 17),
                ),
              ),
            ),
          ),
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
      ],
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
      behavior: HitTestBehavior.opaque,
      onTap: _returnToLatest,
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
        child: AppIcon(
          HeroAppIcons.angleDown,
          size: 22,
          color: c.textSecondary,
        ),
      ),
    );
  }

  /// Unread/new-message pill. In latest-on-open mode it points up to the
  /// unread boundary; in unread-boundary mode it points down to the newest.
  Widget _newMessagesBanner({
    required bool pointsDown,
    required bool showsUnreadCount,
  }) {
    final c = context.colors;
    final count = _remainingUnreadCount;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: pointsDown
          ? _returnToLatest
          : () => unawaited(_jumpToFirstUnread()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: c.navBar,
          borderRadius: BorderRadius.circular(16),
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
    final banner = _newMessagesBanner(
      pointsDown: pointsDown,
      showsUnreadCount: showsUnreadCount,
    );
    if (!_canOfferUnreadSummary(settings)) return banner;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [_unreadSummaryButton(), const SizedBox(width: 6), banner],
    );
  }

  bool _canOfferUnreadSummary(AiSettingsController? settings) =>
      settings?.initialized == true &&
      settings?.enabled == true &&
      settings?.isConfiguredForCurrentProvider == true &&
      _vm.unreadSummarySnapshot != null &&
      !_vm.isSecretChat &&
      !_vm.hasProtectedContent;

  Widget _unreadSummaryButton() {
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
                color: const Color(0xFFFFFFFF).withValues(alpha: 0.24),
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
            child: const Text(
              'AI',
              style: TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w800,
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

    final providerMode = settings!.provider;
    final endpoint = settings.openAiChatCompletionsUri;
    final model = settings.model;
    final apiKey = settings.apiKey;
    final pccContextSize = settings.pccCapabilities?.contextSize;
    final session = _createUnreadSummarySession(
      providerMode: providerMode,
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      pccContextSize: pccContextSize,
    );
    int? messageId;
    try {
      messageId = await Navigator.of(context).push<int>(
        MaterialPageRoute<int>(
          builder: (_) => UnreadChatSummaryView(
            snapshot: snapshot,
            summarize: (onProgress) =>
                session.summarize(snapshot, onProgress: onProgress),
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
    required AiProviderMode providerMode,
    required Uri? endpoint,
    required String model,
    required String apiKey,
    required int? pccContextSize,
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

    switch (providerMode) {
      case AiProviderMode.applePcc:
        return _UnreadSummarySession(
          UnreadChatSummaryService(
            historyLoader: loader,
            maxChunkMessages: 520,
            maxChunks: 2,
            maxChunkTokenEstimate: unreadSummaryChunkTokenBudget(
              pccContextSize,
            ),
            mergeChunkSummariesLocally: true,
            provider: ApplePccUnreadSummaryProvider(
              api: ApplePccApi(summaryTimeout: const Duration(seconds: 75)),
              reasoningLevel: ApplePccReasoningLevel.light,
            ),
          ),
        );
      case AiProviderMode.openAiCompatible:
        if (endpoint == null || model.trim().isEmpty) {
          throw StateError('The summary server is not configured.');
        }
        final provider = OpenAiCompatibleUnreadSummaryProvider(
          serverBaseUri: endpoint,
          model: model.trim(),
          apiKey: apiKey,
        );
        return _UnreadSummarySession(
          UnreadChatSummaryService(
            historyLoader: loader,
            provider: provider,
            maxChunks: 3,
            maxConcurrentRequests: 3,
            mergeChunkSummariesLocally: true,
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
              fontWeight: FontWeight.w700,
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
          ChatInputBar(
            vm: _vm,
            onStartCall: _startCall,
            onMessageSent: _onComposerMessageSent,
            onPanelGeometryChanged: _onComposerPanelGeometryChanged,
            onMediaSendTapped: _onComposerMediaSendTapped,
          ),
        ],
      );
    }
    if (!_vm.isMember && _vm.canJoin) return _joinBar();
    // Subscribed to a channel you can't post in → mute/unmute (like official).
    if (_vm.isChannel && _vm.isMember) return _channelMuteBar();
    return _disabledComposer(_vm.sendDisabledReason);
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
                paused
                    ? 'Business bot paused in this chat'
                    : _vm.businessBotCanReply
                    ? 'Business bot can reply in this chat'
                    : 'Business bot has read-only access',
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
    final changed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => BusinessBotChatControlSheet(
        chatId: widget.chatId,
        botName: 'Connected Business Bot',
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
        10 + MediaQuery.of(context).padding.bottom,
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
          14 + MediaQuery.of(context).padding.bottom,
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
        10 + MediaQuery.of(context).padding.bottom,
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
            telegramText(label),
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
        14 + MediaQuery.of(context).padding.bottom,
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
    return Column(
      children: [
        _header(),
        Expanded(
          child: Center(
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
                      AppStrings.t(AppStringKeys.chatMemberCount, {
                        'value1': _vm.memberCount,
                      }),
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
                        borderRadius: BorderRadius.circular(23),
                      ),
                      child: Text(
                        telegramText(label),
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
        ),
      ],
    );
  }

  Widget _header() {
    final c = context.colors;
    final subtitle = _vm.subtitle;
    final actionActive = _vm.hasActiveChatAction;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
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
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatInfoView(
                          chatId: widget.chatId,
                          title: _vm.peerTitle,
                        ),
                      ),
                    ),
                    child: AppIcon(
                      HeroAppIcons.bars,
                      size: 22,
                      color: c.textPrimary,
                    ),
                  ),
                  if (_vm.isForum) ...[
                    const SizedBox(width: 18),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openTopicMode,
                      child: AppIcon(
                        HeroAppIcons.hashtag,
                        size: 22,
                        color: c.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
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

  Widget _headerTitleBlock(String subtitle, bool actionActive) {
    final c = context.colors;
    final titleText = Text(
      _vm.headerTitle,
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
        if (_vm.isForum)
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
    if (_vm.isForum) {
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
    kind: _vm.isChannel ? ChatKind.channel : ChatKind.group,
    photo: _vm.peerPhoto,
    isForum: true,
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
    if (!_vm.isForum) return;
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
    await showModalBottomSheet<void>(
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
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
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
              HeroAppIcons.share.data,
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
        ? AppStringKeys.chatSearchMessageResultLabel
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
          borderRadius: BorderRadius.circular(14),
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
    if (_vm.pinnedMessage?.id == pinned.id && _isKeyMostlyVisible(_pinnedKey)) {
      return;
    }
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
  }) async {
    if (mounted) {
      setState(() => _setScrollTarget(messageId));
    } else {
      _setScrollTarget(messageId);
    }
    if (_vm.messages.any((m) => m.id == messageId)) {
      await _ensureMessageVisible(
        messageId,
        pinnedJump: pinnedJump,
        alignment: alignment,
        forceAlignment: forceAlignment,
      );
      return;
    }
    final loaded = await _vm.loadAroundMessage(
      messageId,
      scrollToTarget: false,
    );
    if (!loaded || !mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _ensureMessageVisible(
      messageId,
      pinnedJump: pinnedJump,
      alignment: alignment,
      forceAlignment: forceAlignment,
    );
  }

  Future<void> _openHashtagSearch(String hashtag) async {
    final tag = hashtag.trim();
    if (tag.isEmpty) return;
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => ChatSearchView(
          chatId: widget.chatId,
          title: _vm.peerTitle,
          initialQuery: tag.startsWith('#') ? tag : '#$tag',
        ),
      ),
    );
    if (!mounted || result == null) return;
    await _scrollToMessage(result);
  }

  Future<void> _ensureMessageVisible(
    int messageId, {
    bool pinnedJump = false,
    bool instant = false,
    double? alignment,
    bool forceAlignment = false,
  }) async {
    final targetAlignment = alignment ?? (pinnedJump ? 0.08 : 0.3);
    for (var tries = 0; tries < 6; tries++) {
      final activeKey = _scrollTargetId == messageId ? _targetKey : _pinnedKey;
      final ctx = activeKey.currentContext;
      if (ctx != null && ctx.mounted) {
        // Do not realign a message that is already on screen. Reply, search,
        // and other linked-message jumps used to always force the row to 30%
        // of the viewport, which made an already-visible target bounce.
        if (!forceAlignment && _isKeyMostlyVisible(activeKey)) {
          if (mounted && _scrollTargetId == messageId) {
            setState(() => _setScrollTarget(null));
          }
          return;
        }
        await Scrollable.ensureVisible(
          ctx,
          alignment: targetAlignment,
          duration: instant
              ? Duration.zero
              : pinnedJump
              ? const Duration(milliseconds: 140)
              : const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignmentPolicy: pinnedJump && alignment == null
              ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
              : ScrollPositionAlignmentPolicy.explicit,
        );
        if (mounted && _scrollTargetId == messageId) {
          setState(() => _setScrollTarget(null));
        }
        return;
      }
      if (!_scroll.hasClients) return;
      final estimate = _estimateMessageOffset(messageId, targetAlignment);
      if (estimate != null) _scroll.jumpTo(estimate);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
    }
    if (mounted && _scrollTargetId == messageId) {
      setState(() => _setScrollTarget(null));
    }
  }

  bool _isKeyMostlyVisible(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return false;
    final renderObject = ctx.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final media = MediaQuery.of(context);
    final origin = renderObject.localToGlobal(Offset.zero);
    final rect = origin & renderObject.size;
    final viewportTop =
        media.padding.top +
        widget.headerHeight +
        (widget.headerBottom == null ? 0 : widget.headerBottomHeight) +
        (widget.showHeaderDivider ? 1 : 0);
    final viewportBottom =
        media.size.height - media.viewInsets.bottom - media.padding.bottom - 72;
    return rect.top >= viewportTop - 24 && rect.bottom <= viewportBottom + 24;
  }

  Widget _transcript() {
    final groupImages = context.watch<ThemeController>().groupImageMessages;
    final entries = _transcriptEntries(groupImages);
    final partition = _partitionTranscript(entries);
    _scheduleTranscriptPivotFreeze();
    // Slivers before `center` grow away from it. Delegate index zero is the
    // child nearest the center, so the chronological older half is reversed.
    final olderEntries = partition.beforePivot.reversed.toList(growable: false);
    final newerEntries = partition.pivotAndAfter;
    final messages = _transcriptCacheMessages ?? _vm.messages;
    final firstContactInfo = _vm.firstContactInfo;
    final firstContactAtCenter =
        firstContactInfo != null &&
        shouldPlaceFirstContactCardAtCenter(
          hasTranscriptEntries: entries.isNotEmpty,
        );
    final firstContactBeforeCenter =
        firstContactInfo != null && !firstContactAtCenter;
    final olderChildCount =
        olderEntries.length + (firstContactBeforeCenter ? 1 : 0);
    final newerLeadingItemCount = firstContactAtCenter ? 1 : 0;
    final olderIndexByKey = <Key, int>{
      for (var i = 0; i < olderEntries.length; i++) olderEntries[i].key: i,
    };
    final newerIndexByKey = <Key, int>{
      for (var i = 0; i < newerEntries.length; i++)
        newerEntries[i].key: i + newerLeadingItemCount,
    };
    _scheduleUnreadProgressUpdate();
    _scheduleShortFirstContactReveal();
    return Container(
      color: _effectiveWallpaper() == null
          ? context.colors.chatBackground
          : const Color(0x00000000),
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
                    return _buildFirstContactCard(firstContactInfo!);
                  },
                  childCount: olderChildCount,
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
                  findChildIndexCallback: (key) {
                    if (key == const ValueKey('chat-first-contact-card')) {
                      return firstContactAtCenter ? 0 : null;
                    }
                    return newerIndexByKey[key];
                  },
                  semanticIndexOffset: olderChildCount,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
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
          !_autoScrollPolicy.preservesViewport) {
        _scheduleScrollToBottom(animated: false);
      }
    });
  }

  Widget _buildTranscriptEntry(
    _TranscriptEntry entry,
    List<ChatMessage> messages,
  ) {
    final message = entry.first;
    final messageIndex = entry.startIndex;
    final isTarget = entry.messages.any((m) => m.id == _scrollTargetId);
    final isPinned = entry.messages.any((m) => m.id == _vm.pinnedMessage?.id);
    final content = Column(
      key: isTarget
          ? _targetKey
          : isPinned
          ? _pinnedKey
          : null,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_needsUnreadDivider(messageIndex, messages: messages))
          KeyedSubtree(key: _unreadKey, child: _unreadDivider()),
        if (_needsSeparator(messageIndex, messages: messages))
          TimeSeparator(unix: message.date),
        if (message.isService)
          SystemBanner(text: message.text)
        else if (entry.isBlockedRun)
          _blockedMessagePlaceholder(context, entry)
        else if (entry.isImageGroup)
          _selectionEntry(entry, _imageGroupBubble(entry.messages))
        else
          _selectionEntry(entry, _messageBubble(message, messageIndex)),
      ],
    );
    final visibilityKey = _entryVisibilityKeys.putIfAbsent(
      entry.last.id,
      GlobalKey.new,
    );
    return KeyedSubtree(
      key: entry.key,
      child: KeyedSubtree(
        key: visibilityKey,
        child: RepaintBoundary(child: content),
      ),
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
      if (!_isTranscriptShort() || !_vm.canLoadOlder) {
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
    final previousVisibilityKeys = Map<int, GlobalKey>.of(_entryVisibilityKeys);
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
    _entryVisibilityKeys
      ..clear()
      ..addAll(nextVisibilityKeys);
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
    setState(() {
      _actionTarget = message;
      _actionRect = rect;
      _actionSource = source;
      _reactionExpanded = false;
      _reactionTab = 'standard';
    });
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
      if (!_canGroupImage(first)) {
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
        if (!_sameImageGroup(group.last, next)) break;
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

  bool _canGroupImage(ChatMessage message) {
    return !message.isService && message.isAlbumVisualMedia;
  }

  bool _sameImageGroup(ChatMessage previous, ChatMessage next) {
    if (!_canGroupImage(next)) return false;
    if (previous.isOutgoing != next.isOutgoing) return false;
    if (previous.senderId != next.senderId) return false;
    if (previous.mediaAlbumId != 0 || next.mediaAlbumId != 0) {
      return previous.mediaAlbumId != 0 &&
          previous.mediaAlbumId == next.mediaAlbumId;
    }
    return false;
  }

  Widget _imageGroupBubble(List<ChatMessage> group) {
    final c = context.colors;
    final first = group.first;
    final outgoing = first.isOutgoing;
    final avatarTitle = outgoing
        ? (first.senderIsChat ? (first.senderName ?? _vm.meName) : _vm.meName)
        : (_vm.isGroup && (first.senderName?.isNotEmpty ?? false))
        ? first.senderName!
        : _vm.peerTitle;
    final avatarPhoto = outgoing
        ? (first.senderIsChat ? first.senderPhoto : _vm.mePhoto)
        : (_vm.isGroup ? first.senderPhoto : _vm.peerPhoto);
    ChatMessage? captionMessage;
    for (final message in group) {
      if (_albumCaption(message).isNotEmpty) {
        captionMessage = message;
        break;
      }
    }
    Widget avatar() => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openSenderProfile(first),
      onLongPress: outgoing
          ? null
          : () {
              if (_vm.isGroup && (first.senderName?.isNotEmpty ?? false)) {
                _vm.insertMention(first);
              }
            },
      child: PhotoAvatar(title: avatarTitle, photo: avatarPhoto, size: 38),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final chatWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final gallery = _imageGroupGallery(
          group,
          outgoing,
          captionMessage,
          maxWidth: _messageMediaMaxWidth(chatWidth),
        );
        final Widget body = outgoing
            ? gallery
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_vm.isGroup && (first.senderName?.isNotEmpty ?? false))
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 4),
                      child: Text(
                        first.senderName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ),
                  gallery,
                ],
              );

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: outgoing
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: outgoing
                ? [
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: body,
                      ),
                    ),
                    const SizedBox(width: 8),
                    avatar(),
                  ]
                : [avatar(), const SizedBox(width: 8), Flexible(child: body)],
          ),
        );
      },
    );
  }

  Widget _imageGroupGallery(
    List<ChatMessage> group,
    bool outgoing,
    ChatMessage? captionMessage, {
    required double maxWidth,
  }) {
    final c = context.colors;
    final themedOutgoing = _effectiveOutgoingColor();
    final themedIncoming = _effectiveIncomingColor();
    final outgoingColor = themedOutgoing ?? AppTheme.bubbleOutgoing;
    final outgoingTextColor =
        _effectiveOutgoingTextColor() ??
        (outgoingColor.computeLuminance() > 0.64
            ? const Color(0xFF171717)
            : AppTheme.bubbleOutgoingText);
    final incomingTextColor =
        _effectiveIncomingTextColor() ?? c.bubbleIncomingText;
    final visible = group.take(9).toList();
    const padding = 4.0;
    final layout = buildTelegramMediaAlbumLayout(
      items: [
        for (final message in visible)
          MediaAlbumItem(
            width: message.imageWidth,
            height: message.imageHeight,
          ),
      ],
      maxWidth: maxWidth - padding * 2,
      gap: 4,
      maxSingleHeight: 300,
      minRowHeight: 82,
      maxRowHeight: 230,
    );
    return Container(
      constraints: BoxConstraints(maxWidth: layout.width + padding * 2),
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: outgoing ? outgoingColor : themedIncoming ?? c.bubbleIncoming,
        borderRadius: BorderRadius.circular(8),
        border: outgoing ? null : Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: layout.width,
            height: layout.height,
            child: Stack(
              children: [
                for (var i = 0; i < visible.length; i++)
                  Positioned.fromRect(
                    rect: layout.tiles[i],
                    child: _imageGroupTile(
                      visible[i],
                      width: layout.tiles[i].width,
                      height: layout.tiles[i].height,
                      extraCount: i == visible.length - 1
                          ? math.max(0, group.length - visible.length)
                          : 0,
                    ),
                  ),
              ],
            ),
          ),
          if (captionMessage != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: outgoing
                  ? () => unawaited(_editMessageText(captionMessage))
                  : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 7, 6, 3),
                child: Text(
                  _albumCaption(captionMessage),
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.25,
                    color: outgoing ? outgoingTextColor : incomingTextColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _albumCaption(ChatMessage message) {
    final text = message.text.trim();
    if (text.isEmpty || (text.startsWith('[') && text.endsWith(']'))) return '';
    final imagePlaceholder = telegramText(AppStringKeys.composerImagePreview);
    final videoPlaceholder = telegramText(AppStringKeys.chatVideoPlaceholder);
    return text == imagePlaceholder || text == videoPlaceholder ? '' : text;
  }

  Widget _imageGroupTile(
    ChatMessage message, {
    required double width,
    required double height,
    required int extraCount,
  }) {
    final tileKey = GlobalKey();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_isSelecting) {
          _toggleSelection([message]);
          return;
        }
        if (message.video != null) {
          _playVideo(message);
        } else {
          _openImage(message);
        }
      },
      onLongPress: _isSelecting
          ? null
          : () {
              final box =
                  tileKey.currentContext?.findRenderObject() as RenderBox?;
              final rect = box != null && box.hasSize
                  ? box.localToGlobal(Offset.zero) & box.size
                  : null;
              _showActionMenuForMessage(
                message,
                rect,
                message.video != null
                    ? MessageActionSource.video
                    : MessageActionSource.normal,
              );
            },
      child: SizedBox(
        key: tileKey,
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            TDImage(
              photo: message.image,
              cornerRadius: 5,
              cacheWidth: _cachePx(width),
              cacheHeight: _cachePx(height),
              showProgress: true,
            ),
            if (message.video != null)
              Center(
                child: Container(
                  width: 42,
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    HeroAppIcons.play,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            if (extraCount > 0)
              Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  '+$extraCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (_isSelecting)
              Positioned(
                top: 6,
                right: 6,
                child: IgnorePointer(child: _mediaSelectionIndicator(message)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mediaSelectionIndicator(ChatMessage message) {
    final selected = _selectedMessageIds.contains(message.id);
    return Container(
      key: ValueKey('media-selection-${message.id}'),
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppTheme.brand : Colors.black.withValues(alpha: 0.28),
        border: Border.all(
          color: selected ? AppTheme.brand : Colors.white,
          width: selected ? 0 : 1.4,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 4),
        ],
      ),
      child: selected
          ? const AppIcon(HeroAppIcons.check, size: 17, color: Colors.white)
          : null,
    );
  }

  int _cachePx(double logical) =>
      (logical * MediaQuery.devicePixelRatioOf(context)).ceil();

  void _react(String emoji) {
    final target = _actionTarget;
    setState(() {
      _actionTarget = null;
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
    });
    if (target != null) _vm.addReaction(target.id, emoji);
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
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
    });
    if (target != null) _vm.addCustomReaction(target.id, customEmojiId);
  }

  Widget _actionMenuOverlay() {
    final media = MediaQuery.of(context);
    final screenH = media.size.height;
    final topSafe = media.padding.top + 8;
    final bottomSafe = screenH - media.padding.bottom - 8;
    final outgoing = _actionTarget!.isOutgoing;
    final rect = _actionRect;
    final showActionMenu = !_reactionExpanded;

    final reactionH = _reactionExpanded ? 268.0 : 48.0;
    final menuH = showActionMenu ? MessageActionMenu.preferredHeight : 0.0;
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
      menuTop = (rect.bottom + gap).clamp(topSafe, bottomSafe - menuH);
    } else {
      reactionTop = (screenH - reactionH - menuH - menuGap) / 2;
      menuTop = reactionTop + reactionH + menuGap;
    }
    final align = outgoing ? Alignment.centerRight : Alignment.centerLeft;

    void dismiss() => setState(() {
      _actionTarget = null;
      _actionRect = null;
      _actionSource = MessageActionSource.normal;
      _reactionExpanded = false;
    });

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: dismiss,
              child: Container(color: Colors.black.withValues(alpha: 0.25)),
            ),
          ),
          // Call logs and other special messages aren't reactable — no +1 bar.
          if (!_actionTarget!.isCall)
            Positioned(
              top: reactionTop,
              left: 10,
              right: 10,
              child: AnimatedBuilder(
                animation: EmojiStore.shared,
                builder: (context, _) {
                  if (_reactionExpanded) {
                    return Align(
                      alignment: align,
                      child: _expandedReactionPicker(),
                    );
                  }
                  final reactions = effectiveQuickReactions(
                    context.watch<ThemeController>().quickReactions,
                    allowCustomEmoji: EmojiStore.shared.isPremium,
                  );
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
              top: menuTop,
              left: 10,
              right: 10,
              child: Align(
                alignment: align,
                child: MessageActionMenu(
                  message: _actionTarget!,
                  isPinned: _vm.pinnedMessage?.id == _actionTarget!.id,
                  allowForwarding: _vm.canForwardContent,
                  allowSuggestedPostOffer:
                      _vm.isDirectMessagesGroup &&
                      !_vm.isAdministeredDirectMessagesGroup,
                  source: _actionSource,
                  onSelect: (action) => _perform(action, _actionTarget!),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _expandedReactionPicker() {
    final store = EmojiStore.shared;
    final packs = store.isPremium ? store.customPacks : const [];
    return Container(
      width: 300,
      height: 268,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(child: _reactionContent(packs)),
          _reactionTabStrip(packs),
        ],
      ),
    );
  }

  Widget _reactionContent(List packs) {
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
        for (final e in availableStandardReactions)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _react(e),
            child: Center(
              child: Text(
                e,
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
                _reactionExpanded = false;
              });
              Navigator.of(context).push(
                PageRouteBuilder<void>(
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
          borderRadius: BorderRadius.circular(8),
        ),
        child: SizedBox(width: 28, height: 28, child: Center(child: child)),
      ),
    );
  }
}

class _MessageTextSelectionDialog extends StatefulWidget {
  const _MessageTextSelectionDialog({
    required this.text,
    required this.onTranslate,
    required this.onAddToBlocklist,
  });

  final String text;
  final Future<String?> Function(String text) onTranslate;
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
    final height = math.min(MediaQuery.sizeOf(context).height * 0.62, 560.0);
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: ColoredBox(
            color: c.card,
            child: SizedBox(
              height: height,
              width: double.infinity,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: c.divider,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _reactionTabs(c),
                  Divider(height: 1, thickness: 0.5, color: c.divider),
                  Expanded(child: _reactionUsers(c)),
                ],
              ),
            ),
          ),
        ),
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
          borderRadius: BorderRadius.circular(10),
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
    if (selected.isEmpty || _translating) return;
    setState(() => _translating = true);
    final translated = await widget.onTranslate(selected);
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
                  borderRadius: BorderRadius.circular(12),
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
                                fontWeight: FontWeight.w700,
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
                          Expanded(
                            child: _TextSelectionAction(
                              icon: HeroAppIcons.language,
                              label: AppStringKeys.messageActionTranslate,
                              onTap: _translating ? null : _translateSelection,
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

void _switchPiPSessionMode(
  BuildContext context,
  VoidCallback close,
  VideoDisplayMode mode,
  VideoSplitSession session,
) {
  if (mode == VideoDisplayMode.pictureInPicture) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  close();
  switch (mode) {
    case VideoDisplayMode.pictureInPicture:
      break;
    case VideoDisplayMode.split:
      VideoSplitController.instance.play(session);
    case VideoDisplayMode.fullscreen:
      navigator.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (routeContext) => VideoPlaylistPlayerView(
            queue: session.queue,
            onSwitchMode: (queue, nextMode) {
              final currentSession = VideoSplitSession.fromQueue(queue);
              switch (nextMode) {
                case VideoDisplayMode.fullscreen:
                  break;
                case VideoDisplayMode.pictureInPicture:
                  VideoPiPController.instance.play(currentSession);
                  Navigator.of(routeContext).maybePop();
                case VideoDisplayMode.split:
                  VideoSplitController.instance.play(currentSession);
                  Navigator.of(routeContext).maybePop();
              }
            },
          ),
        ),
      );
  }
}

double _sessionAspect(VideoSplitSession session) {
  return (session.width != null &&
          session.height != null &&
          session.width! > 0 &&
          session.height! > 0)
      ? session.width! / session.height!
      : 16 / 9;
}

class _PiPCornerHandle extends StatelessWidget {
  const _PiPCornerHandle({required this.alignment, required this.onDrag});

  final Alignment alignment;
  final GestureDragUpdateCallback onDrag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: alignment.x < 0 ? -8 : null,
      right: alignment.x > 0 ? -8 : null,
      top: alignment.y < 0 ? -8 : null,
      bottom: alignment.y > 0 ? -8 : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: onDrag,
        child: const SizedBox(width: 44, height: 44),
      ),
    );
  }
}
