//
//  chat_input_bar.dart
//
//  Reference-style composer: rounded text field + inline send, a gray icon
//  strip, and togglable panels (function grid + emoji + sticker + voice). Sends
//  text, emoji, stickers, photos/camera, files, location, polls and voice notes
//  through the view model. Port of the Swift `ChatInputBar`.
//

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../app/desktop_utility_window.dart';
import '../components/app_dialog.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/confirm_dialog.dart';
import '../components/icon_grid.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../media/app_asset_picker.dart';
import '../platform/desktop_clipboard_images.dart';
import '../platform/desktop_screenshot.dart';
import '../settings/ai_settings_controller.dart';
import '../settings/ai_settings_view.dart';
import '../settings/apple_pcc_api.dart';
import '../settings/business_service.dart';
import '../settings/desktop_hotkey_controller.dart';
import '../settings/rich_message_relay_config.dart';
import '../settings/rich_message_relay_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'ai_reply_service.dart';
import 'audio_search_view.dart';
import 'bot_button_presentation.dart';
import 'bot_platform_service.dart';
import 'channel_direct_messages_service.dart';
import 'channel_direct_messages_view.dart';
import 'chat_view_model.dart';
import 'checklist_composer_view.dart';
import 'contact_share_picker_view.dart';
import 'custom_emoji.dart';
import 'desktop_composer_height.dart';
import 'emoji_catalog.dart';
import 'emoji_store.dart';
import 'emoji_text_controller.dart';
import 'gallery_send_mode_sheet.dart';
import 'gif_item.dart';
import 'gif_preview.dart';
import 'gif_store.dart';
import 'image_edit_view.dart';
import 'link_handler.dart';
import 'location_picker_view.dart';
import 'media_send_preview_view.dart';
import 'message_send_options.dart';
import 'outgoing_attachment.dart';
import 'poll_composer_view.dart';
import 'rich_message_bot_relay.dart';
import 'rich_message_source.dart';
import 'rich_text_composer_view.dart';
import 'scheduled_messages_view.dart';
import 'sticker_item.dart';
import 'sticker_preview.dart';
import 'sticker_set_studio_view.dart';
import 'sticker_store.dart';
import 'telegram_ai_editor_view.dart';
import 'telegram_ai_service.dart';
import 'telegram_mini_app_view.dart';
import 'video_note_preview_view.dart';
import 'video_note_recorder_view.dart';
import 'voice_note_preview_view.dart';

enum _Panel { none, function, emoji, sticker, voice }

enum _RichTextSendMode { direct, botRelay }

class _ReplyKeyboard {
  const _ReplyKeyboard({required this.message, required this.rows});

  final ChatMessage message;
  final List<List<MessageButton>> rows;
}

class MentionQuery {
  const MentionQuery({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}

class BotCommandQuery {
  const BotCommandQuery({
    required this.start,
    required this.end,
    required this.query,
  });

  final int start;
  final int end;
  final String query;
}

MentionQuery? activeMentionQuery(String text, TextSelection selection) {
  if (!selection.isValid || !selection.isCollapsed) return null;
  final cursor = selection.extentOffset;
  if (cursor < 0 || cursor > text.length) return null;
  final beforeCursor = text.substring(0, cursor);
  final match = RegExp(r'(^|\s)@([^\s@]*)$').firstMatch(beforeCursor);
  if (match == null) return null;
  final leading = match.group(1)?.length ?? 0;
  return MentionQuery(
    start: match.start + leading,
    end: cursor,
    query: match.group(2) ?? '',
  );
}

BotCommandQuery? activeBotCommandQuery(String text, TextSelection selection) {
  if (!selection.isValid ||
      !selection.isCollapsed ||
      selection.extentOffset != text.length) {
    return null;
  }
  final match = RegExp(r'^/([A-Za-z0-9_]*)$').firstMatch(text);
  if (match == null) return null;
  return BotCommandQuery(
    start: 0,
    end: text.length,
    query: match.group(1) ?? '',
  );
}

List<BotCommandOption> matchingBotCommands(
  Iterable<BotCommandOption> commands,
  String query,
) {
  final normalizedQuery = query.toLowerCase();
  return commands
      .where(
        (command) =>
            command.normalizedCommand.toLowerCase().startsWith(normalizedQuery),
      )
      .toList(growable: false);
}

bool isTelegramAiDraftEligible(String text) =>
    text.trim().isNotEmpty && text.split('\n').length >= 2;

typedef _ClipboardImage = ({Uint8List data, String mimeType});

/// The 10 Hz recorder tick, published to the waveform and the elapsed-time
/// label alone so the whole composer does not rebuild with it.
typedef _RecTick = ({double elapsed, List<double> levels});

typedef AiReplyGenerator =
    Future<TelegramAiFormattedText> Function(AiReplyRequest request);

typedef AiReplyStreamingGenerator =
    Future<TelegramAiFormattedText> Function(
      AiReplyRequest request, {
      required AiReplyDraftCallback onDraft,
      AiReplyProgressCallback? onProgress,
    });

class _AiReplyContextSnapshot {
  const _AiReplyContextSnapshot({
    required this.chatTitle,
    required this.currentUserName,
    required this.isGroup,
    required this.isSecretChat,
    required this.hasProtectedContent,
    required this.selectedMessageFingerprints,
    required this.tailFingerprints,
  });

  static const _tailLength = 8;

  final String chatTitle;
  final String currentUserName;
  final bool isGroup;
  final bool isSecretChat;
  final bool hasProtectedContent;
  final Map<int, int> selectedMessageFingerprints;
  final List<int> tailFingerprints;

  factory _AiReplyContextSnapshot.capture(
    ChatViewModel vm,
    AiReplyRequest request,
  ) {
    final selectedIds = {for (final message in request.messages) message.id};
    return _AiReplyContextSnapshot(
      chatTitle: vm.peerTitle,
      currentUserName: vm.meName,
      isGroup: vm.isGroup,
      isSecretChat: vm.isSecretChat,
      hasProtectedContent: vm.hasProtectedContent,
      selectedMessageFingerprints: {
        for (final message in vm.messages)
          if (selectedIds.contains(message.id))
            message.id: _messageFingerprint(message),
      },
      tailFingerprints: [
        for (final message in vm.messages.skip(
          math.max(0, vm.messages.length - _tailLength),
        ))
          _messageFingerprint(message),
      ],
    );
  }

  bool matches(ChatViewModel vm) {
    if (chatTitle != vm.peerTitle ||
        currentUserName != vm.meName ||
        isGroup != vm.isGroup ||
        isSecretChat != vm.isSecretChat ||
        hasProtectedContent != vm.hasProtectedContent) {
      return false;
    }
    var matchedSelectedMessages = 0;
    for (final message in vm.messages) {
      final expected = selectedMessageFingerprints[message.id];
      if (expected == null) continue;
      if (_messageFingerprint(message) != expected) return false;
      matchedSelectedMessages++;
    }
    if (matchedSelectedMessages != selectedMessageFingerprints.length) {
      return false;
    }
    final currentTail = vm.messages.skip(
      math.max(0, vm.messages.length - _tailLength),
    );
    var index = 0;
    for (final message in currentTail) {
      if (index >= tailFingerprints.length ||
          _messageFingerprint(message) != tailFingerprints[index]) {
        return false;
      }
      index++;
    }
    return index == tailFingerprints.length;
  }

  static int _messageFingerprint(ChatMessage message) => Object.hash(
    message.id,
    message.isOutgoing,
    message.isService,
    message.isContentRestricted,
    message.blockedByUser,
    message.senderName,
    message.senderId,
    message.senderIsChat,
    message.replyToMessageId,
    message.date,
    message.text,
  );
}

typedef DesktopScreenshotCapture = Future<String?> Function();
typedef DesktopUtilityWindowLauncher =
    Future<bool> Function(DesktopUtilityWindowArguments arguments);
typedef MediaSendPreviewLauncher =
    Future<MediaSendPreviewResult?> Function(
      List<OutgoingAttachment> attachments,
    );

/// Routes desktop screenshot shortcuts through the currently active composer.
///
/// A window can briefly retain more than one mounted chat while its navigator
/// transitions. Focused composers are preferred, followed by the most recently
/// registered visible composer. The selected handler owns both native capture
/// and the production media-send preview.
abstract final class DesktopChatComposerActions {
  static final Map<Object, _DesktopChatComposerActionRegistration>
  _registrations = {};

  static bool get hasVisibleComposer =>
      _registrations.values.any((registration) => registration.isVisible());

  static Future<bool> captureScreenshot() async {
    final candidates = _registrations.values.where(
      (registration) => registration.isVisible(),
    );
    _DesktopChatComposerActionRegistration? selected;
    for (final candidate in candidates) {
      selected = candidate;
      if (candidate.hasFocus()) break;
    }
    if (selected == null) return false;
    await selected.captureScreenshot();
    return true;
  }

  static void _register(
    Object owner, {
    required Future<void> Function() captureScreenshot,
    required bool Function() hasFocus,
    required bool Function() isVisible,
  }) {
    _registrations.remove(owner);
    _registrations[owner] = _DesktopChatComposerActionRegistration(
      captureScreenshot: captureScreenshot,
      hasFocus: hasFocus,
      isVisible: isVisible,
    );
  }

  static void _unregister(Object owner) => _registrations.remove(owner);
}

class _DesktopChatComposerActionRegistration {
  const _DesktopChatComposerActionRegistration({
    required this.captureScreenshot,
    required this.hasFocus,
    required this.isVisible,
  });

  final Future<void> Function() captureScreenshot;
  final bool Function() hasFocus;
  final bool Function() isVisible;
}

class _SendComposerIntent extends Intent {
  const _SendComposerIntent();
}

class _InsertComposerLineBreakIntent extends Intent {
  const _InsertComposerLineBreakIntent();
}

class _SendComposerAction extends Action<_SendComposerIntent> {
  _SendComposerAction({required this.canInvoke, required this.onInvoke});

  final bool Function() canInvoke;
  final VoidCallback onInvoke;

  @override
  bool isEnabled(_SendComposerIntent intent) => canInvoke();

  @override
  Object? invoke(_SendComposerIntent intent) {
    onInvoke();
    return null;
  }
}

@visibleForTesting
bool isComposerImeEnterFallback(
  TextEditingValue oldValue,
  TextEditingValue newValue, {
  required bool shiftPressed,
  required bool controlPressed,
}) {
  if (shiftPressed || controlPressed) return false;
  if (!oldValue.selection.isValid || !oldValue.selection.isCollapsed) {
    return false;
  }
  if (oldValue.selection.extentOffset != oldValue.text.length) return false;
  if (oldValue.composing.isValid && !oldValue.composing.isCollapsed) {
    return false;
  }
  if (newValue.composing.isValid && !newValue.composing.isCollapsed) {
    return false;
  }
  if (newValue.text != '${oldValue.text}\n') return false;
  return newValue.selection.isValid &&
      newValue.selection.isCollapsed &&
      newValue.selection.extentOffset == newValue.text.length;
}

class _ComposerEnterToSendFormatter extends TextInputFormatter {
  const _ComposerEnterToSendFormatter({required this.onSend});

  final VoidCallback onSend;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final keyboard = HardwareKeyboard.instance;
    if (!isComposerImeEnterFallback(
      oldValue,
      newValue,
      shiftPressed: keyboard.isShiftPressed,
      controlPressed: keyboard.isControlPressed,
    )) {
      return newValue;
    }
    onSend();
    return oldValue;
  }
}

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.vm,
    required this.onStartCall,
    required this.onMessageSent,
    this.onPanelGeometryChanged,
    this.onMediaSendTapped,
    this.gifPreviewBuilder,
    this.requestInitialFocus = false,
    this.enterToSend = false,
    this.quickRepliesEnabled = true,
    this.showCallAction = true,
    this.onBotTopicCreated,
    this.quickReplyLoader,
    this.quickReplySender,
    this.onVoicePanelOpenedForTesting,
    this.desktopScreenshotCapture,
    this.desktopClipboardAttachmentReader,
    this.desktopUtilityWindowLauncher,
    this.mediaSendPreviewLauncher,
    this.aiReplyGenerator,
    this.aiReplyStreamingGenerator,
    this.aiReplyHistoryLoader,
    this.desktopComposerHeightLoader,
    this.desktopComposerHeightSaver,
  });
  final ChatViewModel vm;
  final FutureOr<void> Function(bool isVideo) onStartCall;
  final VoidCallback onMessageSent;
  final VoidCallback? onPanelGeometryChanged;
  final VoidCallback? onMediaSendTapped;
  @visibleForTesting
  final Widget Function(GifItem item)? gifPreviewBuilder;
  final bool requestInitialFocus;
  final bool enterToSend;
  final bool quickRepliesEnabled;
  final bool showCallAction;
  final ValueChanged<int>? onBotTopicCreated;
  @visibleForTesting
  final Future<List<BusinessQuickReplyShortcut>> Function()? quickReplyLoader;
  @visibleForTesting
  final Future<void> Function(int chatId, int shortcutId)? quickReplySender;
  @visibleForTesting
  final VoidCallback? onVoicePanelOpenedForTesting;
  @visibleForTesting
  final DesktopScreenshotCapture? desktopScreenshotCapture;
  @visibleForTesting
  final DesktopClipboardAttachmentReader? desktopClipboardAttachmentReader;
  @visibleForTesting
  final DesktopUtilityWindowLauncher? desktopUtilityWindowLauncher;
  @visibleForTesting
  final MediaSendPreviewLauncher? mediaSendPreviewLauncher;
  @visibleForTesting
  final AiReplyGenerator? aiReplyGenerator;
  @visibleForTesting
  final AiReplyStreamingGenerator? aiReplyStreamingGenerator;
  @visibleForTesting
  final AiReplyChatHistoryLoader? aiReplyHistoryLoader;
  @visibleForTesting
  final DesktopComposerHeightLoader? desktopComposerHeightLoader;
  @visibleForTesting
  final DesktopComposerHeightSaver? desktopComposerHeightSaver;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  static const _clipboardChannel = MethodChannel('mithka/clipboard');
  static const _maximumPendingClipboardAttachments = 10;
  static const _gifTabId = -2;
  static const _stickerSearchTabId = -3;
  static const _emojiSearchTab = 'search';
  static const _imageMimeTypes = <String>[
    'image/png',
    'image/jpeg',
    'image/gif',
    'image/webp',
    'image/heic',
    'image/heif',
  ];

  final _controller = EmojiTextEditingController();
  final _focus = FocusNode();
  final _panelSearch = TextEditingController();
  final List<OutgoingAttachment> _pendingClipboardAttachments = [];
  final _desktopActionOwner = Object();
  DesktopHotkeyRegistration? _desktopScreenshotHotkeyRegistration;
  final _desktopSenderPopoverLink = LayerLink();
  final _desktopEmojiPopoverLink = LayerLink();
  final _desktopStickerPopoverLink = LayerLink();
  final _desktopSenderPopoverController = OverlayPortalController();
  final _desktopEmojiPopoverController = OverlayPortalController();
  final _desktopStickerPopoverController = OverlayPortalController();
  bool _desktopSenderPopoverVisible = false;
  bool _desktopEmojiPopoverVisible = false;
  bool _desktopStickerPopoverVisible = false;
  bool _wasEditingMessage = false;
  int? _syncedEditingMessageId;
  int _syncedComposerRevision = -1;
  _Panel _panel = _Panel.none;
  String _emojiTab = 'standard'; // 'standard' or a custom-emoji pack id
  int? _stickerPack; // active sticker pack id
  Timer? _panelSearchTimer;
  int _panelSearchGeneration = 0;
  bool _panelSearchLoading = false;
  List<String> _emojiSearchResults = const [];
  List<StickerItem> _customEmojiSearchResults = const [];
  List<StickerItem> _stickerSearchResults = const [];
  List<GifItem> _gifSearchResults = const [];
  String _gifSearchNextOffset = '';
  bool _gifSearchLoadingMore = false;

  // Voice recording (flutter_sound, Opus).
  FlutterSoundRecorder? _recorder;
  bool _recording = false;
  bool _recordingPaused = false;
  bool _recordingLocked = false;
  bool _recordCancelled = false;
  double _elapsed = 0;
  double _pressStartX = 0;
  double _pressStartY = 0;
  Timer? _recTimer;
  StreamSubscription<RecordingDisposition>? _recProgress;
  final List<double> _recLevels = [];
  final ValueNotifier<_RecTick> _recTick = ValueNotifier((
    elapsed: 0.0,
    levels: const <double>[],
  ));
  String? _recPath;
  late bool _hasText = vm.draft.trim().isNotEmpty;
  late bool _aiDraftEligible = isTelegramAiDraftEligible(vm.draft);
  bool _replyKeyboardVisible = false;
  Timer? _mentionSearchTimer;
  MentionQuery? _mentionQuery;
  List<MentionCandidate> _mentionCandidates = const [];
  int _mentionSearchGeneration = 0;
  BotCommandQuery? _botCommandQuery;
  List<BotCommandOption> _botCommandCandidates = const [];
  OverlayEntry? _relayProgressEntry;
  RichMessageRelayProgress? _relayProgress;
  final BotPlatformService _botPlatform = BotPlatformService();
  StreamSubscription<Map<String, dynamic>>? _botPlatformUpdates;
  final List<BotGuestQuery> _guestQueries = [];
  Timer? _inlineBotTimer;
  int _inlineBotGeneration = 0;
  bool _inlineBotLoading = false;
  BotPlatformCapabilities? _inlineBot;
  BotInlineResultsPage? _inlineBotResults;
  bool _quickRepliesLoaded = false;
  bool _quickReplyContextVisible = false;
  int? _quickReplySendingId;
  List<BusinessQuickReplyShortcut> _quickReplies = const [];
  int _composerRevision = 0;
  int _aiReplyGeneration = 0;
  int? _aiReplyWorkingTargetId;
  bool? _aiReplyWorkingUsesExplicitTarget;
  int? _aiReplyWorkingTargetFingerprint;
  _AiReplyContextSnapshot? _aiReplyWorkingContextSnapshot;
  bool _applyingAiReplyDraft = false;
  bool _syncingControllerFromVm = false;
  bool _initialFocusRequestConsumed = false;
  bool _keyboardSendScheduled = false;
  AiReplyProvider? _activeAiReplyProvider;
  List<AiReplyProgressPhase> _aiReplyProgressPhases = const [];
  bool _aiReplyProgressExpanded = false;
  double _desktopComposerCanvasHeight = desktopComposerDefaultCanvasHeight;
  int _desktopComposerHeightLoadGeneration = 0;
  ChatViewModel get vm => widget.vm;

  bool get _canUseQuickReplies =>
      widget.quickRepliesEnabled &&
      !vm.isGroup &&
      !vm.peerIsBot &&
      !vm.isSecretChat &&
      vm.peerUserId != vm.meId;

  @override
  void initState() {
    super.initState();
    DesktopChatComposerActions._register(
      _desktopActionOwner,
      captureScreenshot: _captureDesktopScreenshot,
      hasFocus: () => _focus.hasFocus,
      isVisible: _isDesktopComposerVisible,
    );
    _desktopScreenshotHotkeyRegistration = DesktopHotkeyRegistry.instance
        .register(
          DesktopHotkeyAction.screenshot,
          _captureDesktopScreenshot,
          isEnabled: _isDesktopComposerVisible,
        );
    _wasEditingMessage = vm.editingMessage != null;
    _syncedEditingMessageId = vm.editingMessage?.id;
    _controller.setFormattedText(
      vm.composerFormattedDraft,
      vm.composerDraftEntities,
    );
    _controller.addListener(_onTextChanged);
    _panelSearch.addListener(_queuePanelSearch);
    _focus.addListener(() {
      var needsRebuild = false;
      var panelChanged = false;
      if (_focus.hasFocus && _panel != _Panel.none) {
        _panel = _Panel.none;
        needsRebuild = true;
        panelChanged = true;
      }
      if (needsRebuild && mounted) {
        setState(() {});
        if (panelChanged) widget.onPanelGeometryChanged?.call();
      }
    });
    vm.addListener(_syncFromVm);
    EmojiStore.shared.addListener(_onStore);
    StickerStore.shared.addListener(_onStore);
    GifStore.shared.addListener(_onStore);
    _botPlatformUpdates = TdClient.shared
        .updatesOf('updateNewGuestQuery')
        .listen(_handleBotPlatformUpdate);
    if (widget.quickReplyLoader == null) {
      BusinessQuickReplyService.shared.addListener(_syncQuickReplyCache);
      _adoptQuickReplyCache(rebuild: false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestInitialFocusIfReady();
      unawaited(_restoreDesktopComposerHeight());
      if (mounted && _canUseQuickReplies) {
        unawaited(_loadQuickReplies(userInitiated: false));
      }
    });
  }

  String get _desktopComposerHeightKey => desktopComposerHeightPreferenceKey(
    accountSlot: TdClient.shared.activeSlot,
    chatId: vm.chatId,
  );

  Future<void> _restoreDesktopComposerHeight() async {
    if (!mounted || !_usesNativeDesktopComposer(context)) return;
    final generation = ++_desktopComposerHeightLoadGeneration;
    final key = _desktopComposerHeightKey;
    final loader =
        widget.desktopComposerHeightLoader ?? DesktopComposerHeightStore.load;
    final loaded = await loader(key);
    if (!mounted || generation != _desktopComposerHeightLoadGeneration) return;
    if (loaded == null ||
        !loaded.isFinite ||
        key != _desktopComposerHeightKey) {
      return;
    }
    final height = clampDesktopComposerCanvasHeight(
      loaded,
      viewportHeight: MediaQuery.sizeOf(context).height,
    );
    if (height == _desktopComposerCanvasHeight) return;
    setState(() => _desktopComposerCanvasHeight = height);
    widget.onPanelGeometryChanged?.call();
  }

  void _resizeDesktopComposer(DragUpdateDetails details) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final current = clampDesktopComposerCanvasHeight(
      _desktopComposerCanvasHeight,
      viewportHeight: viewportHeight,
    );
    final next = desktopComposerCanvasHeightAfterDrag(
      currentHeight: current,
      verticalDelta: details.delta.dy,
      viewportHeight: viewportHeight,
    );
    if (next == current) return;
    setState(() => _desktopComposerCanvasHeight = next);
    widget.onPanelGeometryChanged?.call();
  }

  void _persistDesktopComposerHeight(DragEndDetails _) {
    final height = clampDesktopComposerCanvasHeight(
      _desktopComposerCanvasHeight,
      viewportHeight: MediaQuery.sizeOf(context).height,
    );
    final saver =
        widget.desktopComposerHeightSaver ?? DesktopComposerHeightStore.save;
    unawaited(saver(_desktopComposerHeightKey, height));
  }

  void _handleBotPlatformUpdate(Map<String, dynamic> update) {
    try {
      final query = BotGuestQuery.fromUpdate(update);
      if (!mounted) return;
      setState(() {
        _guestQueries.removeWhere((value) => value.id == query.id);
        _guestQueries.insert(0, query);
        if (_guestQueries.length > 50) {
          _guestQueries.removeRange(50, _guestQueries.length);
        }
      });
    } on FormatException {
      // Ignore malformed updates; TDLib will redeliver valid guest queries.
    }
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  DateTime? _lastTyping;
  void _onTextChanged() {
    if (_syncingControllerFromVm) return;
    final applyingAiReplyDraft = _applyingAiReplyDraft;
    if (!applyingAiReplyDraft) {
      _composerRevision++;
      _invalidateAiReplyGeneration(clearProgress: true);
    }
    final (text, entities) = _controller.toFormatted();
    vm.setDraft(_controller.text, formattedText: text, entities: entities);
    // setDraft doesn't notify (it would rebuild the whole chat per keystroke), so
    // rebuild just the composer here — otherwise `hasText` stays stale and the
    // send button never appears while typing.
    final hasText = _controller.text.trim().isNotEmpty;
    final aiDraftEligible = isTelegramAiDraftEligible(_controller.text);
    if (hasText != _hasText || aiDraftEligible != _aiDraftEligible) {
      _hasText = hasText;
      _aiDraftEligible = aiDraftEligible;
      if (hasText) {
        _replyKeyboardVisible = false;
        _quickReplyContextVisible = false;
      }
      if (mounted) setState(() {});
    }
    if (applyingAiReplyDraft) return;
    if (vm.editingMessage != null) {
      _mentionSearchTimer?.cancel();
      _inlineBotTimer?.cancel();
      _mentionSearchGeneration++;
      _inlineBotGeneration++;
      final hadSuggestions =
          _mentionQuery != null ||
          _mentionCandidates.isNotEmpty ||
          _botCommandQuery != null ||
          _botCommandCandidates.isNotEmpty ||
          _inlineBotLoading ||
          _inlineBotResults != null;
      _mentionQuery = null;
      _mentionCandidates = const [];
      _botCommandQuery = null;
      _botCommandCandidates = const [];
      _inlineBotLoading = false;
      _inlineBotResults = null;
      if (hadSuggestions && mounted) setState(() {});
      return;
    }
    _updateMentionSuggestions();
    _updateBotCommandSuggestions();
    _queueInlineBotResults();
    final now = DateTime.now();
    if (_controller.text.isNotEmpty &&
        (_lastTyping == null || now.difference(_lastTyping!).inSeconds >= 4)) {
      _lastTyping = now;
      vm.sendTyping();
    }
  }

  void _updateMentionSuggestions() {
    final query = activeMentionQuery(_controller.text, _controller.selection);
    if (query == null || !vm.isGroup) {
      _mentionSearchTimer?.cancel();
      _mentionSearchGeneration++;
      if (_mentionQuery != null || _mentionCandidates.isNotEmpty) {
        _mentionQuery = null;
        _mentionCandidates = const [];
        if (mounted) setState(() {});
      }
      return;
    }
    if (_mentionQuery?.start == query.start &&
        _mentionQuery?.end == query.end &&
        _mentionQuery?.query == query.query) {
      return;
    }
    _mentionQuery = query;
    _mentionCandidates = const [];
    if (mounted) setState(() {});
    _mentionSearchTimer?.cancel();
    final generation = ++_mentionSearchGeneration;
    _mentionSearchTimer = Timer(const Duration(milliseconds: 120), () async {
      final candidates = await vm.searchMentionCandidates(query.query);
      if (!mounted || generation != _mentionSearchGeneration) return;
      final active = activeMentionQuery(
        _controller.text,
        _controller.selection,
      );
      if (active == null ||
          active.start != query.start ||
          active.end != query.end ||
          active.query != query.query) {
        return;
      }
      setState(() => _mentionCandidates = candidates);
    });
  }

  void _selectMention(MentionCandidate candidate) {
    final query = activeMentionQuery(_controller.text, _controller.selection);
    if (query == null) return;
    _mentionSearchTimer?.cancel();
    _mentionSearchGeneration++;
    _mentionQuery = null;
    _mentionCandidates = const [];
    _controller.insertTextMention(
      start: query.start,
      end: query.end,
      label: candidate.name,
      userId: candidate.userId,
    );
    _focus.requestFocus();
  }

  void _updateBotCommandSuggestions({bool force = false, bool rebuild = true}) {
    final query = activeBotCommandQuery(
      _controller.text,
      _controller.selection,
    );
    // Commands complete in groups (member bots' commands) and in private bot
    // chats (the bot's own command list from userFullInfo).
    final supportsCommands = (vm.isGroup && !vm.isChannel) || vm.peerIsBot;
    if (query == null || !supportsCommands) {
      if (_botCommandQuery == null && _botCommandCandidates.isEmpty) return;
      _botCommandQuery = null;
      _botCommandCandidates = const [];
      if (rebuild && mounted) setState(() {});
      return;
    }
    if (!force &&
        _botCommandQuery?.start == query.start &&
        _botCommandQuery?.end == query.end &&
        _botCommandQuery?.query == query.query) {
      return;
    }
    _botCommandQuery = query;
    _botCommandCandidates = matchingBotCommands(vm.botCommands, query.query);
    if (rebuild && mounted) setState(() {});
  }

  void _sendBotCommandHint(BotCommandOption command) {
    if (!vm.sendCommand(command.targetedCommand)) return;
    _controller.clear();
    _focus.requestFocus();
    widget.onMessageSent();
  }

  void _insertBotCommandHint(BotCommandOption command) {
    final query = activeBotCommandQuery(
      _controller.text,
      _controller.selection,
    );
    if (query == null) return;
    final replacement = '${command.displayCommand} ';
    final text = _controller.text.replaceRange(
      query.start,
      query.end,
      replacement,
    );
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: query.start + replacement.length,
      ),
    );
    _focus.requestFocus();
  }

  void _queueInlineBotResults() {
    final invocation = BotInlineInvocation.fromText(_controller.text);
    _inlineBotTimer?.cancel();
    final generation = ++_inlineBotGeneration;
    if (invocation == null) {
      if (_inlineBotLoading ||
          _inlineBotResults != null ||
          _inlineBot != null) {
        _inlineBotLoading = false;
        _inlineBotResults = null;
        _inlineBot = null;
        if (mounted) setState(() {});
      }
      return;
    }
    if (!_inlineBotLoading || _inlineBotResults != null) {
      _inlineBotLoading = true;
      _inlineBotResults = null;
      if (mounted) setState(() {});
    }
    _inlineBotTimer = Timer(
      const Duration(milliseconds: 260),
      () => unawaited(_loadInlineBotResults(invocation, generation)),
    );
  }

  Future<void> _loadInlineBotResults(
    BotInlineInvocation invocation,
    int generation,
  ) async {
    try {
      var bot = _inlineBot;
      if (bot == null ||
          bot.username.toLowerCase() != invocation.username.toLowerCase()) {
        bot = await _botPlatform.capabilitiesForUsername(invocation.username);
      }
      if (!bot.inlineMode) throw StateError('BOT_INLINE_MODE_DISABLED');
      final location = bot.needsLocation ? await _inlineBotLocation() : null;
      if (bot.needsLocation && location == null) {
        throw StateError('BOT_INLINE_LOCATION_UNAVAILABLE');
      }
      final response = await _botPlatform.inlineResults(
        botUserId: bot.userId,
        chatId: vm.chatId,
        query: invocation.query,
        location: location,
      );
      final page = BotInlineResultsPage.fromJson(response);
      if (!mounted || generation != _inlineBotGeneration) return;
      setState(() {
        _inlineBot = bot;
        _inlineBotResults = page;
        _inlineBotLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _inlineBotGeneration) return;
      setState(() {
        _inlineBotResults = null;
        _inlineBotLoading = false;
      });
    }
  }

  Future<Map<String, dynamic>?> _inlineBotLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final value = await Geolocator.getCurrentPosition();
    return {
      '@type': 'location',
      'latitude': value.latitude,
      'longitude': value.longitude,
      'horizontal_accuracy': value.accuracy,
    };
  }

  void _syncFromVm() {
    // A notification that changed only the typing subtitle or the peer's
    // online status leaves the revision alone; nothing here renders either.
    final revision = vm.composerRevision;
    final revisionChanged = revision != _syncedComposerRevision;
    _syncedComposerRevision = revision;
    final hadText = _hasText;
    final wasAiDraftEligible = _aiDraftEligible;
    final hadQuickReplyContext = _quickReplyContextVisible;
    final previousBotCommandQuery = _botCommandQuery;
    final previousBotCommandCandidates = _botCommandCandidates;
    final workingTargetId = _aiReplyWorkingTargetId;
    final workingUsesExplicitTarget = _aiReplyWorkingUsesExplicitTarget;
    final workingTargetFingerprint = _aiReplyWorkingTargetFingerprint;
    final workingContextSnapshot = _aiReplyWorkingContextSnapshot;
    if (workingTargetId != null &&
        (workingUsesExplicitTarget == null ||
            workingTargetFingerprint == null ||
            workingContextSnapshot == null ||
            !workingContextSnapshot.matches(vm) ||
            !_isCurrentAiReplyTarget(
              workingTargetId,
              usesExplicitTarget: workingUsesExplicitTarget,
              fingerprint: workingTargetFingerprint,
            ))) {
      _invalidateAiReplyGeneration(discardGeneratedDraft: true);
    }
    final editingMessage = vm.editingMessage;
    final editingStateChanged =
        _wasEditingMessage != (editingMessage != null) ||
        _syncedEditingMessageId != editingMessage?.id;
    if (editingStateChanged) {
      _wasEditingMessage = editingMessage != null;
      _syncedEditingMessageId = editingMessage?.id;
      _hideDesktopPopovers(rebuild: false);
      _panel = _Panel.none;
      _replyKeyboardVisible = false;
      _quickReplyContextVisible = false;
      _syncingControllerFromVm = true;
      try {
        _controller.setFormattedText(
          vm.composerFormattedDraft,
          vm.composerDraftEntities,
        );
      } finally {
        _syncingControllerFromVm = false;
      }
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        widget.onPanelGeometryChanged?.call();
      });
    } else {
      final composing = _controller.value.composing;
      final composingLocally = _focus.hasFocus || composing.isValid;
      if (!composingLocally && vm.draft != _controller.text) {
        _controller.value = TextEditingValue(
          text: vm.draft,
          selection: TextSelection.collapsed(offset: vm.draft.length),
        );
      }
    }
    _hasText = _controller.text.trim().isNotEmpty;
    _aiDraftEligible = isTelegramAiDraftEligible(_controller.text);
    if (_hasText) _quickReplyContextVisible = false;
    if (vm.editingMessage == null) {
      _updateBotCommandSuggestions(force: true, rebuild: false);
    } else {
      _botCommandQuery = null;
      _botCommandCandidates = const [];
    }
    _requestInitialFocusIfReady();
    final localChanged =
        editingStateChanged ||
        hadText != _hasText ||
        wasAiDraftEligible != _aiDraftEligible ||
        hadQuickReplyContext != _quickReplyContextVisible ||
        !identical(previousBotCommandQuery, _botCommandQuery) ||
        !identical(previousBotCommandCandidates, _botCommandCandidates);
    if (mounted && (revisionChanged || localChanged)) setState(() {});
  }

  void _requestInitialFocusIfReady() {
    if (_initialFocusRequestConsumed ||
        !widget.requestInitialFocus ||
        !vm.initialLoaded) {
      return;
    }
    if (vm.draft != _controller.text) {
      _controller.value = TextEditingValue(
        text: vm.draft,
        selection: TextSelection.collapsed(offset: vm.draft.length),
      );
    }
    _initialFocusRequestConsumed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _syncQuickReplyCache() => _adoptQuickReplyCache(rebuild: true);

  void _adoptQuickReplyCache({required bool rebuild}) {
    final service = BusinessQuickReplyService.shared;
    if (!service.shortcutsLoaded) return;
    final replies = service.shortcuts;
    _quickReplies = replies;
    _quickRepliesLoaded = true;
    if (replies.isEmpty || !widget.quickRepliesEnabled) {
      _quickReplyContextVisible = false;
    }
    if (rebuild && mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.vm, widget.vm)) {
      _hideDesktopPopovers(rebuild: false);
      _invalidateAiReplyGeneration(discardGeneratedDraft: true);
      _discardPendingClipboardAttachments();
      _initialFocusRequestConsumed = false;
      _desktopComposerCanvasHeight = desktopComposerDefaultCanvasHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_restoreDesktopComposerHeight());
      });
    } else if (!oldWidget.requestInitialFocus && widget.requestInitialFocus) {
      _initialFocusRequestConsumed = false;
    }
    _requestInitialFocusIfReady();
    if (oldWidget.quickRepliesEnabled && !widget.quickRepliesEnabled) {
      _quickReplyContextVisible = false;
    } else if (!oldWidget.quickRepliesEnabled &&
        widget.quickRepliesEnabled &&
        _canUseQuickReplies) {
      _adoptQuickReplyCache(rebuild: false);
      unawaited(_loadQuickReplies(userInitiated: false));
    }
  }

  bool _isDesktopComposerVisible() {
    if (!mounted ||
        !_usesNativeDesktopComposer(context) ||
        !TickerMode.getValuesNotifier(context).value.enabled) {
      return false;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final renderObject = context.findRenderObject();
    return renderObject is RenderBox &&
        renderObject.attached &&
        renderObject.hasSize &&
        !renderObject.size.isEmpty;
  }

  @override
  void dispose() {
    _desktopComposerHeightLoadGeneration++;
    _desktopScreenshotHotkeyRegistration?.dispose();
    DesktopChatComposerActions._unregister(_desktopActionOwner);
    // OverlayPortal tears its overlay down with this element. Calling hide()
    // while the portal is already being unmounted asserts because it no
    // longer has a z-order slot, so only clear our logical state here.
    _desktopSenderPopoverVisible = false;
    _desktopEmojiPopoverVisible = false;
    _desktopStickerPopoverVisible = false;
    _discardPendingClipboardAttachments();
    _aiReplyGeneration++;
    if (_activeAiReplyProvider case final HostedAiReplyProvider hosted) {
      hosted.close();
    }
    _activeAiReplyProvider = null;
    _aiReplyWorkingTargetId = null;
    _aiReplyWorkingUsesExplicitTarget = null;
    _aiReplyWorkingTargetFingerprint = null;
    _aiReplyWorkingContextSnapshot = null;
    vm.removeListener(_syncFromVm);
    EmojiStore.shared.removeListener(_onStore);
    StickerStore.shared.removeListener(_onStore);
    GifStore.shared.removeListener(_onStore);
    if (widget.quickReplyLoader == null) {
      BusinessQuickReplyService.shared.removeListener(_syncQuickReplyCache);
    }
    _controller.dispose();
    _panelSearch
      ..removeListener(_queuePanelSearch)
      ..dispose();
    _focus.dispose();
    _recTimer?.cancel();
    _recProgress?.cancel();
    _recTick.dispose();
    _mentionSearchTimer?.cancel();
    _panelSearchTimer?.cancel();
    _inlineBotTimer?.cancel();
    _botPlatformUpdates?.cancel();
    _hideRelayProgress();
    _recorder?.closeRecorder();
    super.dispose();
  }

  void _discardPendingClipboardAttachments() {
    final attachments = List<OutgoingAttachment>.of(
      _pendingClipboardAttachments,
    );
    _pendingClipboardAttachments.clear();
    for (final attachment in attachments) {
      unawaited(_deleteTempFile(attachment.path));
    }
  }

  void _queuePanelSearch() {
    _panelSearchTimer?.cancel();
    final query = _panelSearch.text.trim();
    if (query.isEmpty) {
      _panelSearchGeneration++;
      if (mounted) {
        setState(() {
          _panelSearchLoading = false;
          _emojiSearchResults = const [];
          _customEmojiSearchResults = const [];
          _stickerSearchResults = const [];
          _gifSearchResults = const [];
          _gifSearchNextOffset = '';
          _gifSearchLoadingMore = false;
        });
      }
      return;
    }
    if (!_isPanelSearchSelected) return;
    _panelSearchTimer = Timer(
      const Duration(milliseconds: 320),
      () => unawaited(_runPanelSearch(query)),
    );
  }

  Future<void> _runPanelSearch(String query) async {
    if (!_isPanelSearchSelected) return;
    final generation = ++_panelSearchGeneration;
    if (mounted) setState(() => _panelSearchLoading = true);
    final languageCodes = mounted
        ? [Localizations.localeOf(context).languageCode]
        : const <String>[];
    var emoji = const <String>[];
    var customEmoji = const <StickerItem>[];
    var stickers = const <StickerItem>[];
    var gifs = const <GifItem>[];
    var gifNextOffset = '';
    try {
      if ((_panel == _Panel.emoji || _desktopEmojiPopoverVisible) &&
          _emojiTab == _emojiSearchTab) {
        final results = await Future.wait([
          TdClient.shared.query({
            '@type': 'searchEmojis',
            'text': query,
            'input_language_codes': languageCodes,
          }),
          TdClient.shared.query({
            '@type': 'searchStickers',
            'sticker_type': {'@type': 'stickerTypeCustomEmoji'},
            'emojis': '',
            'query': query,
            'input_language_codes': languageCodes,
            'offset': 0,
            'limit': 80,
          }),
        ]);
        final values = <String>[];
        for (final keyword
            in results.first.objects('emoji_keywords') ??
                const <Map<String, dynamic>>[]) {
          final value = keyword.str('emoji');
          if (value != null && value.isNotEmpty && !values.contains(value)) {
            values.add(value);
          }
        }
        emoji = values;
        customEmoji = parseStickers(results.last.objects('stickers'));
      } else if ((_panel == _Panel.sticker || _desktopStickerPopoverVisible) &&
          _stickerPack == _stickerSearchTabId) {
        final results = await Future.wait<dynamic>([
          TdClient.shared.query({
            '@type': 'searchStickers',
            'sticker_type': {'@type': 'stickerTypeRegular'},
            'emojis': '',
            'query': query,
            'input_language_codes': languageCodes,
            'offset': 0,
            'limit': 100,
          }),
          _searchGifs(query),
        ]);
        final result = results.first as Map<String, dynamic>;
        final gifPage = results.last as (List<GifItem>, String);
        stickers = parseStickers(result.objects('stickers'));
        gifs = gifPage.$1;
        gifNextOffset = gifPage.$2;
      }
    } catch (_) {}
    if (!mounted ||
        generation != _panelSearchGeneration ||
        query != _panelSearch.text.trim() ||
        !_isPanelSearchSelected) {
      return;
    }
    setState(() {
      _panelSearchLoading = false;
      _emojiSearchResults = emoji;
      _customEmojiSearchResults = customEmoji;
      _stickerSearchResults = stickers;
      _gifSearchResults = gifs;
      _gifSearchNextOffset = gifNextOffset;
      _gifSearchLoadingMore = false;
    });
  }

  Future<(List<GifItem>, String)> _searchGifs(
    String query, {
    String offset = '',
  }) async {
    final option = await TdClient.shared.query({
      '@type': 'getOption',
      'name': 'animation_search_bot_username',
    });
    final username = option.str('value') ?? '';
    if (username.isEmpty) return (const <GifItem>[], '');
    final botChat = await TdClient.shared.query({
      '@type': 'searchPublicChat',
      'username': username,
    });
    final botUserId = botChat.obj('type')?.int64('user_id');
    if (botUserId == null) return (const <GifItem>[], '');
    final response = await TdClient.shared.query({
      '@type': 'getInlineQueryResults',
      'bot_user_id': botUserId,
      'chat_id': vm.chatId,
      'query': query,
      'offset': offset,
    });
    final page = parseInlineGifSearchPage(response);
    return (page.items, page.nextOffset);
  }

  Future<void> _loadMoreGifSearch() async {
    final query = _panelSearch.text.trim();
    final offset = _gifSearchNextOffset;
    if (!_isPanelSearchSelected ||
        query.isEmpty ||
        offset.isEmpty ||
        _gifSearchLoadingMore) {
      return;
    }
    setState(() => _gifSearchLoadingMore = true);
    try {
      final page = await _searchGifs(query, offset: offset);
      if (!mounted ||
          query != _panelSearch.text.trim() ||
          !_isPanelSearchSelected) {
        return;
      }
      final known = _gifSearchResults.map((item) => item.id).toSet();
      setState(() {
        _gifSearchResults = [
          ..._gifSearchResults,
          ...page.$1.where((item) => known.add(item.id)),
        ];
        _gifSearchNextOffset = page.$2;
        _gifSearchLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _gifSearchLoadingMore = false);
    }
  }

  bool get _isPanelSearchSelected =>
      ((_panel == _Panel.emoji || _desktopEmojiPopoverVisible) &&
          _emojiTab == _emojiSearchTab) ||
      ((_panel == _Panel.sticker || _desktopStickerPopoverVisible) &&
          _stickerPack == _stickerSearchTabId);

  void _setPanel(_Panel next) {
    if (_panel == next && !_quickReplyContextVisible) return;
    if (next != _Panel.none) _hideDesktopPopovers(rebuild: false);
    setState(() {
      _panel = next;
      _quickReplyContextVisible = false;
    });
    widget.onPanelGeometryChanged?.call();
  }

  void _selectEmojiTab(String tab) {
    if (_emojiTab == tab) return;
    setState(() => _emojiTab = tab);
    if (tab == _emojiSearchTab && _panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    }
  }

  void _selectStickerTab(int tab) {
    if (_stickerPack == tab) return;
    setState(() => _stickerPack = tab);
    if (tab == _stickerSearchTabId && _panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    } else if (tab == _gifTabId) {
      GifStore.shared.loadIfNeeded();
    } else if (tab == StickerStore.recentPackId) {
      StickerStore.shared.loadIfNeeded();
    } else {
      StickerStore.shared.loadPack(tab);
    }
  }

  void _finishPanelSend() {
    if (_desktopSenderPopoverVisible ||
        _desktopEmojiPopoverVisible ||
        _desktopStickerPopoverVisible) {
      _hideDesktopPopovers();
    } else {
      _setPanel(_Panel.none);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onMessageSent();
    });
  }

  // MARK: - Voice recording

  void _toggleVoice() {
    _focus.unfocus();
    _setPanel(_panel == _Panel.voice ? _Panel.none : _Panel.voice);
    if (_panel == _Panel.voice) {
      final testingHook = widget.onVoicePanelOpenedForTesting;
      if (testingHook != null) {
        testingHook();
      } else {
        unawaited(_prepareRecorder());
      }
    }
  }

  Future<void> _prepareRecorder() async {
    if (_recorder != null) return;
    var status = await Permission.microphone.status;
    if (!status.isGranted && !status.isPermanentlyDenied) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted) {
      if (!mounted) return;
      showToast(
        context,
        status.isPermanentlyDenied
            ? AppStrings.t(AppStringKeys.composerMicrophonePermissionSettings)
            : AppStrings.t(AppStringKeys.composerMicrophonePermissionRequired),
      );
      if (status.isPermanentlyDenied) unawaited(openAppSettings());
      return;
    }
    final r = FlutterSoundRecorder();
    try {
      await r.openRecorder();
      await r.setSubscriptionDuration(const Duration(milliseconds: 100));
    } catch (_) {
      return;
    }
    if (!mounted) {
      await r.closeRecorder();
      return;
    }
    // setState so the panel rebuilds with the recorder ready — otherwise the
    // press handlers keep seeing a stale `granted == false` and never record.
    setState(() => _recorder = r);
  }

  /// Telegram voice notes want OGG/Opus, but not every Android encoder supports
  /// it — pick the first codec the device can actually record.
  Future<(Codec, String)?> _pickRecordCodec(
    FlutterSoundRecorder r,
    String dir,
  ) async {
    const candidates = [
      (Codec.opusOGG, 'ogg'),
      (Codec.opusWebM, 'webm'),
      (Codec.aacADTS, 'aac'),
      (Codec.aacMP4, 'm4a'),
    ];
    for (final (codec, ext) in candidates) {
      if (await r.isEncoderSupported(codec)) {
        return (
          codec,
          '$dir/voice_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );
      }
    }
    return null;
  }

  Future<void> _startRec() async {
    final r = _recorder;
    if (r == null || _recording) return;
    final dir = await getTemporaryDirectory();
    final picked = await _pickRecordCodec(r, dir.path);
    if (picked == null) return;
    final (codec, path) = picked;
    _recPath = path;
    _recordCancelled = false;
    _recordingPaused = false;
    _recordingLocked = false;
    _elapsed = 0;
    _recLevels.clear();
    _recTick.value = (elapsed: 0.0, levels: const <double>[]);
    try {
      await r.startRecorder(toFile: _recPath, codec: codec, sampleRate: 48000);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _recording = true);
    await _recProgress?.cancel();
    _recProgress = r.onProgress?.listen((event) {
      if (!mounted) return;
      _elapsed = event.duration.inMilliseconds / 1000;
      final level = event.decibels;
      if (level != null && level.isFinite) {
        _recLevels.add((level >= 0 ? level - 120 : level).clamp(-120.0, 0.0));
      }
      _recTick.value = (
        elapsed: _elapsed,
        levels: _recLevels.reversed.take(36).toList().reversed.toList(),
      );
    });
    _recTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      // Only here to move the clock until the recorder's own progress stream
      // reports; once it has, the timer has nothing left to do.
      if (_elapsed != 0) {
        timer.cancel();
        _recTimer = null;
        return;
      }
      if (_recordingPaused) return;
      _elapsed += 0.1;
      _recTick.value = (elapsed: _elapsed, levels: _recTick.value.levels);
    });
  }

  Future<void> _stopRec() async {
    final r = _recorder;
    _recTimer?.cancel();
    _recTimer = null;
    await _recProgress?.cancel();
    _recProgress = null;
    if (r == null || !_recording) return;
    final secs = _elapsed.round();
    final cancelled = _recordCancelled;
    String? url;
    try {
      url = await r.stopRecorder();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recordingPaused = false;
      _recordingLocked = false;
    });
    if (cancelled || secs < 1 || url == null) {
      if (url != null) unawaited(_deleteTempFile(url));
      return;
    }
    final result = await Navigator.of(context).push<VoiceNotePreviewResult>(
      MaterialPageRoute(
        builder: (_) => VoiceNotePreviewView(
          path: url!,
          duration: secs,
          levels: List<double>.unmodifiable(_recLevels),
          allowWhenOnline: vm.canSendWhenOnline,
          effects: vm.availableMessageEffects,
        ),
      ),
    );
    if (!mounted) return;
    if (result == null) {
      unawaited(_deleteTempFile(url));
      return;
    }
    final sent = await vm.sendVoice(
      result.path,
      result.duration,
      waveform: result.waveform,
      sendConfiguration: result.sendConfiguration,
    );
    if (!mounted) return;
    if (sent) {
      _finishPanelSend();
    } else {
      showToast(context, AppStringKeys.topicPostContentActionFailed);
    }
  }

  Future<void> _toggleRecPause() async {
    final recorder = _recorder;
    if (recorder == null || !_recording) return;
    try {
      if (_recordingPaused) {
        await recorder.resumeRecorder();
      } else {
        await recorder.pauseRecorder();
      }
      if (mounted) setState(() => _recordingPaused = !_recordingPaused);
    } catch (_) {}
  }

  void _cancelLockedRecording() {
    if (!_recording) return;
    _recordCancelled = true;
    unawaited(_stopRec());
  }

  Future<void> _deleteTempFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  static String _recTime(double seconds) {
    final s = seconds.floor();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _toggle(_Panel panel) {
    _focus.unfocus();
    _setPanel(_panel == panel ? _Panel.none : panel);
  }

  void _pickFailed(String what) {
    _setPanel(_Panel.none);
    showToast(
      context,
      AppStrings.t(AppStringKeys.composerOpenAttachmentFailed, {
        'value1': what,
      }),
    );
  }

  void _scheduleKeyboardSend() {
    if (_keyboardSendScheduled) return;
    _keyboardSendScheduled = true;
    scheduleMicrotask(() => unawaited(_sendScheduledKeyboardText()));
  }

  Future<void> _sendScheduledKeyboardText() async {
    try {
      if (mounted) await _sendCurrentText();
    } finally {
      _keyboardSendScheduled = false;
    }
  }

  Future<void> _sendCurrentText() async {
    if (_aiReplyWorkingTargetId != null) return;
    if (vm.editingMessage != null) {
      final (text, entities) = _controller.toFormatted();
      if (!vm.editingMessageUsesCaption && text.trim().isEmpty) {
        showToast(context, AppStringKeys.chatMessageRequired);
        return;
      }
      try {
        final edited = await vm.submitMessageEdit(text, entities: entities);
        if (!mounted || !edited) return;
        _focus.requestFocus();
      } catch (error) {
        if (mounted) showToast(context, '$error');
      }
      return;
    }
    if (_pendingClipboardAttachments.isNotEmpty) {
      await _sendPendingClipboardAttachments();
      return;
    }
    if (_controller.text.trim().isEmpty) return;
    final canAttemptSend = await vm.prepareMessageSend();
    if (!mounted || !canAttemptSend) return;
    final (text, entities) = _controller.toFormatted();
    final lengthTier = telegramMessageLengthTier(text);
    if (lengthTier == TelegramMessageLengthTier.exceeded) {
      showToast(
        context,
        AppStringKeys.composerMessageExceedsRichTextLimit.l10n(context),
      );
      return;
    }
    if (lengthTier == TelegramMessageLengthTier.rich) {
      final sendAsRichText = await _confirmLongMessageAsRichText();
      if (!mounted || !sendAsRichText) return;
      if (await _richTextSendMode() == null || !mounted) return;
      if (vm.requiresPaidMessage) {
        final ok = await _confirmPaidMessageSend();
        if (!mounted || !ok) return;
      }
      final inline = formattedTextToRichInlineHtml(
        text,
        entities,
      ).replaceAll('\n', '<br>');
      final html = '<p>$inline</p>';
      await _sendRichTextResult(
        RichTextComposerResult(
          text: text,
          entities: entities,
          attachments: const [],
          segments: [RichMessageSendSegment.html(html)],
        ),
      );
      return;
    }
    if (vm.requiresPaidMessage) {
      final ok = await _confirmPaidMessageSend();
      if (!mounted || !ok) return;
    }
    final sent = await vm.sendFormatted(text, entities);
    if (!mounted || !sent) return;
    widget.onMessageSent();
    _controller.clear();
    _focus.requestFocus();
  }

  Future<void> _sendPendingClipboardAttachments({
    MessageSendConfiguration sendConfiguration =
        const MessageSendConfiguration(),
  }) async {
    if (_pendingClipboardAttachments.isEmpty) return;
    final canAttemptSend = await vm.prepareMessageSend();
    if (!mounted || !canAttemptSend) return;
    final (caption, entities) = _controller.toFormatted();
    if (telegramMessageLengthTier(caption) ==
        TelegramMessageLengthTier.exceeded) {
      showToast(
        context,
        AppStringKeys.composerMessageExceedsRichTextLimit.l10n(context),
      );
      return;
    }
    if (vm.requiresPaidMessage) {
      final ok = await _confirmPaidMessageSend();
      if (!mounted || !ok) return;
    }
    final attachments = List<OutgoingAttachment>.unmodifiable(
      _pendingClipboardAttachments,
    );
    try {
      await vm.sendAttachments(
        attachments,
        caption: caption,
        captionEntities: entities,
        sendConfiguration: sendConfiguration,
      );
    } catch (error) {
      if (mounted) showToast(context, '$error');
      return;
    }
    if (!mounted) return;
    setState(_pendingClipboardAttachments.clear);
    widget.onPanelGeometryChanged?.call();
    widget.onMessageSent();
    _controller.clear();
    _focus.requestFocus();
  }

  Future<void> _openTelegramAiEditor() async {
    if (!vm.canUseAiComposition || _controller.text.trim().isEmpty) return;
    if (_usesNativeDesktopComposer(context)) {
      try {
        await vm.persistComposerDraft();
      } catch (error) {
        if (mounted) showToast(context, error.toString());
        return;
      }
      if (!mounted) return;
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.aiEditor,
        AppStringKeys.telegramAiEditorRewriteTitle.l10n(context),
      );
      return;
    }
    final (text, entities) = _controller.toFormatted();
    final result = await Navigator.of(context).push<TelegramAiFormattedText>(
      MaterialPageRoute(
        builder: (_) => TelegramAiEditorView(
          service: vm.telegramAi,
          source: TelegramAiFormattedText(text: text, entities: entities),
        ),
      ),
    );
    if (!mounted || result == null) return;
    _controller.setFormattedText(result.text, result.entities);
    _focus.requestFocus();
  }

  bool _isAiReplyTargetEligible(ChatMessage target) {
    return !vm.isSecretChat &&
        !vm.hasProtectedContent &&
        !target.isService &&
        !target.isContentRestricted &&
        !target.blockedByUser &&
        target.text.trim().isNotEmpty;
  }

  bool _canOfferAiReply(ChatMessage target, AiSettingsController? settings) {
    if (settings?.initialized != true || !_isAiReplyTargetEligible(target)) {
      return false;
    }
    return switch (settings!.replyModelCandidate.kind) {
      AiModelCandidateKind.telegramCocoon =>
        vm.aiCapabilities?.replySupported == true,
      AiModelCandidateKind.applePcc ||
      AiModelCandidateKind.appleOnDevice ||
      AiModelCandidateKind.server => settings.isConfiguredForFeature(
        AiFeature.reply,
      ),
    };
  }

  ChatMessage? _contextualAiReplyTarget() {
    final anchorId = vm.anchoredHistory ? vm.historyAnchorMessageId : null;
    if (anchorId != null) {
      final anchor = vm.messages
          .where((message) => message.id == anchorId)
          .firstOrNull;
      if (anchor != null) {
        final safeAnchor =
            anchor.id > 0 &&
            !anchor.isService &&
            !anchor.isContentRestricted &&
            !anchor.blockedByUser &&
            anchor.text.trim().isNotEmpty;
        if (safeAnchor && (!anchor.isOutgoing || vm.isGroup)) return anchor;
        if (!vm.isGroup) return null;
      }
    }
    ChatMessage? groupFallback;
    for (final message in vm.messages.reversed) {
      if (message.isService) continue;
      final safeText =
          message.id > 0 &&
          !message.isContentRestricted &&
          !message.blockedByUser &&
          message.text.trim().isNotEmpty;
      if (safeText) {
        groupFallback ??= message;
        if (!message.isOutgoing) return message;
      }
      // In a busy group, keep looking for the newest participant message even
      // if the account owner or an ineligible message was posted afterwards.
      // Private chats retain the stronger "already answered" behavior.
      if (!vm.isGroup) {
        return null;
      }
    }
    // Group and channel composers also support drafting the next message when
    // the visible context only contains posts sent by the account owner or the
    // currently selected sender identity.
    return groupFallback;
  }

  ChatMessage? _currentAiReplyTarget() =>
      vm.replyTo ?? _contextualAiReplyTarget();

  bool _isCurrentAiReplyTarget(
    int targetMessageId, {
    required bool usesExplicitTarget,
    required int fingerprint,
  }) {
    final ChatMessage? current;
    if (usesExplicitTarget) {
      current = vm.replyTo;
    } else {
      if (vm.replyTo != null) return false;
      current = _contextualAiReplyTarget();
    }
    return current?.id == targetMessageId &&
        _aiReplyTargetFingerprint(current!) == fingerprint;
  }

  int _aiReplyTargetFingerprint(ChatMessage target) => Object.hash(
    target.id,
    target.isOutgoing,
    target.isService,
    target.isContentRestricted,
    target.blockedByUser,
    target.senderName,
    target.text,
  );

  bool _isCurrentAiReplyTargetWithoutFingerprint(
    ChatMessage target, {
    required bool usesExplicitTarget,
  }) {
    final fingerprint = _aiReplyTargetFingerprint(target);
    return _isCurrentAiReplyTarget(
      target.id,
      usesExplicitTarget: usesExplicitTarget,
      fingerprint: fingerprint,
    );
  }

  void _invalidateAiReplyGeneration({
    bool discardGeneratedDraft = false,
    bool clearProgress = false,
  }) {
    final shouldClearProgress = clearProgress || discardGeneratedDraft;
    if (_aiReplyWorkingTargetId == null &&
        _activeAiReplyProvider == null &&
        (!shouldClearProgress || _aiReplyProgressPhases.isEmpty)) {
      return;
    }
    _aiReplyGeneration++;
    _aiReplyWorkingTargetId = null;
    _aiReplyWorkingUsesExplicitTarget = null;
    _aiReplyWorkingTargetFingerprint = null;
    _aiReplyWorkingContextSnapshot = null;
    final activeProvider = _activeAiReplyProvider;
    _activeAiReplyProvider = null;
    if (activeProvider case final HostedAiReplyProvider hosted) {
      hosted.close();
    }
    if (discardGeneratedDraft && _controller.text.isNotEmpty) {
      _applyingAiReplyDraft = true;
      try {
        _controller.setFormattedText('', const []);
      } finally {
        _applyingAiReplyDraft = false;
      }
    }
    if (shouldClearProgress) {
      _aiReplyProgressPhases = const [];
      _aiReplyProgressExpanded = false;
    }
    if (mounted) setState(() {});
  }

  void _recordAiReplyProgress(
    AiReplyProgressPhase phase, {
    required int generation,
  }) {
    if (!mounted || generation != _aiReplyGeneration) return;
    if (_aiReplyProgressPhases.contains(phase)) return;
    final wasEmpty = _aiReplyProgressPhases.isEmpty;
    setState(() {
      _aiReplyProgressPhases = [..._aiReplyProgressPhases, phase];
    });
    if (wasEmpty) _notifyComposerGeometryChanged();
  }

  void _notifyComposerGeometryChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPanelGeometryChanged?.call();
    });
  }

  bool _isAiReplyGenerationCurrent({
    required int generation,
    required ChatViewModel requestVm,
    required AiSettingsController settings,
    required String modelCandidateId,
    required ChatMessage target,
    required int targetMessageId,
    required bool usesExplicitTarget,
    required int targetFingerprint,
    required int draftRevision,
    required _AiReplyContextSnapshot contextSnapshot,
  }) =>
      mounted &&
      generation == _aiReplyGeneration &&
      identical(vm, requestVm) &&
      settings.replyModelCandidate.id == modelCandidateId &&
      (widget.aiReplyHistoryLoader != null || vm.canShareAiReplyContext) &&
      _canOfferAiReply(target, settings) &&
      _isCurrentAiReplyTarget(
        targetMessageId,
        usesExplicitTarget: usesExplicitTarget,
        fingerprint: targetFingerprint,
      ) &&
      contextSnapshot.matches(vm) &&
      _composerRevision == draftRevision;

  bool _applyAiReplyDraft(
    TelegramAiFormattedText draft, {
    required int generation,
    required ChatViewModel requestVm,
    required AiSettingsController settings,
    required String modelCandidateId,
    required ChatMessage target,
    required int targetMessageId,
    required bool usesExplicitTarget,
    required int targetFingerprint,
    required int draftRevision,
    required _AiReplyContextSnapshot contextSnapshot,
  }) {
    if (!_isAiReplyGenerationCurrent(
      generation: generation,
      requestVm: requestVm,
      settings: settings,
      modelCandidateId: modelCandidateId,
      target: target,
      targetMessageId: targetMessageId,
      usesExplicitTarget: usesExplicitTarget,
      targetFingerprint: targetFingerprint,
      draftRevision: draftRevision,
      contextSnapshot: contextSnapshot,
    )) {
      if (mounted && generation == _aiReplyGeneration) {
        _invalidateAiReplyGeneration(
          discardGeneratedDraft: _composerRevision == draftRevision,
        );
      }
      return false;
    }
    _applyingAiReplyDraft = true;
    try {
      _controller.setFormattedText(draft.text, draft.entities);
    } finally {
      _applyingAiReplyDraft = false;
    }
    return true;
  }

  Future<bool> _revealCompletedAiReply(
    TelegramAiFormattedText result, {
    required bool Function(TelegramAiFormattedText draft) applyDraft,
  }) async {
    final characters = result.text.characters.toList(growable: false);
    if (characters.length < 2) return true;

    // Telegram Cocoon and Apple's native model bridge currently return one
    // completed value rather than transport-level deltas. Reveal those replies
    // through the same composer path so every AI Reply provider has consistent
    // incremental input feedback. Keep the animation bounded for long replies
    // and apply the provider's formatted entities only with the final value.
    const maximumFrames = 48;
    const frameDuration = Duration(milliseconds: 12);
    final charactersPerFrame = math.max(
      1,
      (characters.length / maximumFrames).ceil(),
    );
    final buffer = StringBuffer();
    var offset = 0;
    while (offset < characters.length) {
      final end = math.min(characters.length, offset + charactersPerFrame);
      buffer.writeAll(characters.getRange(offset, end));
      offset = end;
      if (offset == characters.length) break;
      if (!applyDraft(TelegramAiFormattedText(text: buffer.toString()))) {
        return false;
      }
      await Future<void>.delayed(frameDuration);
    }
    return true;
  }

  Future<void> _generateAiReply(
    ChatMessage target, {
    String? requiredModelCandidateId,
  }) async {
    if (_aiReplyWorkingTargetId == target.id) return;
    final usesExplicitTarget = vm.replyTo?.id == target.id;
    if (!_isCurrentAiReplyTargetWithoutFingerprint(
      target,
      usesExplicitTarget: usesExplicitTarget,
    )) {
      showToast(context, AppStringKeys.aiReplyStale.l10n(context));
      return;
    }
    final settings = context.read<AiSettingsController?>();
    if (!_canOfferAiReply(target, settings)) {
      showToast(context, AppStringKeys.aiReplyUnavailable.l10n(context));
      return;
    }

    final configuration = settings!.configurationForFeature(AiFeature.reply);
    final modelCandidateId = configuration.candidate.id;
    if (requiredModelCandidateId != null &&
        modelCandidateId != requiredModelCandidateId) {
      showToast(context, AppStringKeys.aiReplyUnavailable.l10n(context));
      return;
    }
    final (draftText, _) = _controller.toFormatted();
    final AiReplyRequest request;
    try {
      request = AiReplyRequest.fromChatMessages(
        chatTitle: vm.peerTitle,
        currentUserName: vm.meName,
        currentUserId: vm.meId,
        currentUserUsernames: vm.meUsernames,
        target: target,
        visibleMessages: vm.messages,
        isGroupChat: vm.isGroup,
        currentDraft: draftText,
        guidance: settings.aiReplyPrompt,
        outputLanguageCode: Localizations.localeOf(context).toLanguageTag(),
        contextWindowTokens: configuration.contextWindowTokens,
        historyLoader: widget.aiReplyHistoryLoader ?? vm.loadAiReplyContext,
      );
    } on AiReplyException catch (error) {
      showToast(context, error.message);
      return;
    }

    AiReplyProvider? provider;
    if (widget.aiReplyGenerator == null &&
        widget.aiReplyStreamingGenerator == null) {
      switch (configuration.candidate.kind) {
        case AiModelCandidateKind.telegramCocoon:
          provider = TelegramCocoonAiReplyProvider(service: vm.telegramAi);
        case AiModelCandidateKind.applePcc:
          provider = AppleAiReplyProvider(api: ApplePccApi());
        case AiModelCandidateKind.appleOnDevice:
          provider = AppleAiReplyProvider(
            api: ApplePccApi(),
            model: AppleAiModel.onDevice,
          );
        case AiModelCandidateKind.server:
          final endpoint = configuration.endpoint;
          if (endpoint == null || configuration.model.isEmpty) {
            showToast(context, AppStringKeys.aiReplyUnavailable.l10n(context));
            return;
          }
          provider = HostedAiReplyProvider(
            endpoint: endpoint,
            model: configuration.model,
            endpointStyle: configuration.endpointStyle,
            apiKey: configuration.apiKey,
          );
      }
    }

    final targetMessageId = target.id;
    final targetFingerprint = _aiReplyTargetFingerprint(target);
    final requestVm = vm;
    final draftRevision = _composerRevision;
    final initialContextSnapshot = _AiReplyContextSnapshot.capture(
      requestVm,
      request,
    );
    final generation = ++_aiReplyGeneration;
    setState(() {
      _aiReplyWorkingTargetId = targetMessageId;
      _aiReplyWorkingUsesExplicitTarget = usesExplicitTarget;
      _aiReplyWorkingTargetFingerprint = targetFingerprint;
      _aiReplyWorkingContextSnapshot = initialContextSnapshot;
      _activeAiReplyProvider = provider;
      _aiReplyProgressPhases = const [
        AiReplyProgressPhase.readingRecentMessages,
      ];
      _aiReplyProgressExpanded = false;
    });
    _notifyComposerGeometryChanged();
    try {
      var groundedRequest = request;
      try {
        groundedRequest = await request.withEarlierContext();
      } on AiReplyPrivacyException {
        rethrow;
      } catch (_) {
        groundedRequest = request.copyWith(contextExpanded: true);
      }
      if (!_isAiReplyGenerationCurrent(
        generation: generation,
        requestVm: requestVm,
        settings: settings,
        modelCandidateId: modelCandidateId,
        target: target,
        targetMessageId: targetMessageId,
        usesExplicitTarget: usesExplicitTarget,
        targetFingerprint: targetFingerprint,
        draftRevision: draftRevision,
        contextSnapshot: initialContextSnapshot,
      )) {
        return;
      }
      final contextSnapshot = _AiReplyContextSnapshot.capture(
        requestVm,
        groundedRequest,
      );
      _aiReplyWorkingContextSnapshot = contextSnapshot;
      bool applyDraft(TelegramAiFormattedText draft) => _applyAiReplyDraft(
        draft,
        generation: generation,
        requestVm: requestVm,
        settings: settings,
        modelCandidateId: modelCandidateId,
        target: target,
        targetMessageId: targetMessageId,
        usesExplicitTarget: usesExplicitTarget,
        targetFingerprint: targetFingerprint,
        draftRevision: draftRevision,
        contextSnapshot: contextSnapshot,
      );

      void onDraft(TelegramAiFormattedText draft) {
        applyDraft(draft);
      }

      void onProgress(AiReplyProgressPhase phase) {
        _recordAiReplyProgress(phase, generation: generation);
      }

      late final TelegramAiFormattedText result;
      var revealCompletedResult = false;
      final streamingGenerator = widget.aiReplyStreamingGenerator;
      if (streamingGenerator != null) {
        result = await streamingGenerator(
          groundedRequest,
          onDraft: onDraft,
          onProgress: onProgress,
        );
      } else if (widget.aiReplyGenerator case final generator?) {
        result = await generator(groundedRequest);
        revealCompletedResult = true;
      } else if (provider case final StreamingAiReplyProvider streaming) {
        result = await streaming.generateStreaming(
          groundedRequest,
          onDraft: onDraft,
          onProgress: onProgress,
        );
      } else {
        result = await provider!.generate(groundedRequest);
        revealCompletedResult = true;
      }
      onProgress(AiReplyProgressPhase.writingReply);
      if (revealCompletedResult &&
          !await _revealCompletedAiReply(result, applyDraft: applyDraft)) {
        return;
      }
      if (!applyDraft(result)) {
        return;
      }
      _focus.requestFocus();
    } catch (error) {
      if (mounted && generation == _aiReplyGeneration) {
        setState(() {
          _aiReplyProgressPhases = const [];
          _aiReplyProgressExpanded = false;
        });
        _notifyComposerGeometryChanged();
        showToast(
          context,
          error is AiReplyException ? error.message : error.toString(),
        );
      }
      return;
    } finally {
      if (provider case final HostedAiReplyProvider hosted) hosted.close();
      if (identical(_activeAiReplyProvider, provider)) {
        _activeAiReplyProvider = null;
      }
      if (mounted && generation == _aiReplyGeneration) {
        setState(() {
          _aiReplyWorkingTargetId = null;
          _aiReplyWorkingUsesExplicitTarget = null;
          _aiReplyWorkingTargetFingerprint = null;
          _aiReplyWorkingContextSnapshot = null;
        });
      }
    }
  }

  Future<void> _showTextSendOptions() async {
    final configuration = await showMessageSendOptionsSheet(
      context,
      allowWhenOnline: widget.vm.canSendWhenOnline,
      effects: widget.vm.availableMessageEffects,
      onOpenScheduledMessages: _openScheduledMessages,
    );
    if (!mounted || configuration == null) return;
    if (_pendingClipboardAttachments.isNotEmpty) {
      await _sendPendingClipboardAttachments(sendConfiguration: configuration);
      return;
    }
    widget.vm.useNextSendConfiguration(configuration);
    await _sendCurrentText();
  }

  void _openScheduledMessages() {
    if (_usesNativeDesktopComposer(context)) {
      unawaited(
        _openDesktopComposerPicker(
          DesktopUtilityWindowKind.scheduledMessages,
          AppStrings.t(AppStringKeys.messageSendOptionsScheduledMessages),
        ),
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ScheduledMessagesView(
            chatId: widget.vm.chatId,
            chatTitle: widget.vm.peerTitle,
          ),
        ),
      );
    });
  }

  Future<void> _openRichTextComposer() async {
    if (await _richTextSendMode() == null) return;
    if (!mounted) return;
    if (_usesNativeDesktopComposer(context)) {
      try {
        await vm.persistComposerDraft();
      } catch (error) {
        if (mounted) showToast(context, error.toString());
        return;
      }
      if (!mounted) return;
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.richTextComposer,
        AppStringKeys.composerRichTextMessageTitle.l10n(context),
      );
      return;
    }
    final result = await showRichTextComposerSheet(
      context,
      initialText: _controller.text,
      title: AppStringKeys.composerRichTextMessageTitle,
      submitText: AppStringKeys.composerSend,
    );
    if (result == null || !mounted) return;
    if (result.text.trim().isEmpty &&
        result.attachments.isEmpty &&
        result.segments.isEmpty) {
      return;
    }
    final canAttemptSend = await vm.prepareMessageSend();
    if (!mounted || !canAttemptSend) return;
    if (vm.requiresPaidMessage) {
      final ok = await _confirmPaidMessageSend();
      if (!mounted || !ok) return;
    }
    await _sendRichTextResult(result);
  }

  Future<bool> _confirmPaidMessageSend() {
    return confirmDialog(
      context,
      title: AppStrings.t(AppStringKeys.composerSendPaidMessageQuestion),
      message: AppStrings.t(AppStringKeys.composerPaidMessageCost, {
        'value1': vm.paidMessageStarCount,
      }),
      confirmText: AppStrings.t(AppStringKeys.composerSend),
    );
  }

  Future<bool> _confirmLongMessageAsRichText() async {
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) => _LongMessageRichTextPrompt(
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
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
    return result ?? false;
  }

  Future<void> _handlePaste([ContextMenuButtonItem? pasteItem]) async {
    if (vm.editingMessage == null) {
      if (_usesNativeDesktopComposer(context)) {
        if (await _queueDesktopClipboardImages()) return;
      } else {
        final image = await _readClipboardImage();
        if (image != null) {
          final queued = await _queueClipboardImageData(
            DesktopClipboardImageData(
              data: image.data,
              mimeType: image.mimeType,
            ),
          );
          if (queued) return;
        }
      }
    }

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text;
    if (text != null && text.isNotEmpty) {
      _controller.insertText(text);
    } else {
      pasteItem?.onPressed?.call();
    }
    _restoreKeyboardFocus();
  }

  Future<void> _showComposerFormatMenu(
    EditableTextState editableTextState,
  ) async {
    final selection = _controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final anchor = editableTextState.contextMenuAnchors.primaryAnchor;
    editableTextState.hideToolbar();
    final action = await showGeneralDialog<_ComposerFormatAction>(
      context: context,
      requestFocus: false,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) => _ComposerFormatMenu(anchor: anchor),
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
    if (!mounted) return;
    if (action == null) {
      _focus.unfocus();
      return;
    }
    _controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    if (action == _ComposerFormatAction.link) {
      final url = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
        barrierColor: Colors.black.withValues(alpha: 0.36),
        transitionDuration: const Duration(milliseconds: 160),
        pageBuilder: (dialogContext, _, _) => const _ComposerLinkDialog(),
      );
      if (!mounted || url == null || url.trim().isEmpty) return;
      final normalized = _normalizeComposerUrl(url);
      _controller.applyEntityFormat(start, end, {
        '@type': 'textEntityTypeTextUrl',
        'url': normalized,
      });
    } else {
      _controller.toggleFormat(action.entityType);
    }
    _controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    _focus.requestFocus();
  }

  String _normalizeComposerUrl(String value) {
    final trimmed = value.trim();
    final parsed = Uri.tryParse(trimmed);
    if (parsed?.hasScheme ?? false) return trimmed;
    return 'https://$trimmed';
  }

  void _restoreKeyboardFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
    });
  }

  Widget _desktopResizeHandle() => MouseRegion(
    cursor: SystemMouseCursors.resizeUpDown,
    child: GestureDetector(
      key: const ValueKey('desktopComposerResizeHandle'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _resizeDesktopComposer,
      onVerticalDragEnd: _persistDesktopComposerHeight,
      child: Semantics(
        label: AppStrings.t(AppStringKeys.chatInputResizeMessageInput),
        child: const SizedBox(height: 8, width: double.infinity),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final aiSettings = context.watch<AiSettingsController?>();
    final desktopComposer = _usesNativeDesktopComposer(context);
    final editingMessage = vm.editingMessage;
    final replyKeyboard = _activeReplyKeyboard();
    final replyKeyboardPanelVisible =
        editingMessage == null &&
        replyKeyboard != null &&
        _replyKeyboardVisible &&
        !_hasText &&
        _pendingClipboardAttachments.isEmpty;
    final panelSurfaceVisible =
        editingMessage == null &&
        (_panel != _Panel.none || replyKeyboardPanelVisible);
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    final bar = ColoredBox(
      key: const ValueKey('chat-input-safe-area-background'),
      color: c.inputBarBackground,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (editingMessage != null)
                  _editBanner(editingMessage)
                else if (vm.replyTo != null)
                  _replyBanner(vm.replyTo!),
                if (editingMessage == null)
                  if (_inlineBotLoading || _inlineBotResults != null)
                    _inlineBotResultMenu()
                  else if (_botCommandCandidates.isNotEmpty)
                    _botCommandMenu()
                  else if (_mentionCandidates.isNotEmpty)
                    _mentionMenu()
                  else if (_quickReplyContextVisible &&
                      _quickReplies.isNotEmpty)
                    _quickReplyContextMenu(),
                if (editingMessage == null &&
                    _pendingClipboardAttachments.isNotEmpty)
                  _clipboardAttachmentStrip(desktop: desktopComposer),
                if (desktopComposer) ...[
                  if (editingMessage == null)
                    _desktopIconStrip(
                      aiSettings: aiSettings,
                      replyKeyboard: replyKeyboard,
                    ),
                  _inputRow(
                    replyKeyboard,
                    aiSettings: aiSettings,
                    desktop: true,
                  ),
                  if (replyKeyboardPanelVisible)
                    _replyKeyboardPanel(replyKeyboard),
                ] else ...[
                  _inputRow(replyKeyboard, aiSettings: aiSettings),
                  if (replyKeyboardPanelVisible)
                    _replyKeyboardPanel(replyKeyboard)
                  else if (editingMessage == null)
                    _iconStrip(),
                ],
                if (editingMessage == null &&
                    !desktopComposer &&
                    _panel == _Panel.function)
                  _functionPanel(),
                if (editingMessage == null &&
                    !desktopComposer &&
                    _panel == _Panel.emoji)
                  _emojiPanel(),
                if (editingMessage == null &&
                    !desktopComposer &&
                    _panel == _Panel.sticker)
                  _stickerPanel(),
                if (editingMessage == null && _panel == _Panel.voice)
                  _voicePanel(),
              ],
            ),
          ),
          if (desktopComposer)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _desktopResizeHandle(),
            ),
          // The base input surface is painted exactly once across the complete
          // composer. When a media/reply panel is open, extend that panel's
          // surface through the system inset with the same single overlay used
          // by the visible panel. This keeps translucent cloud-theme colors
          // identical above and below the home indicator.
          if (panelSurfaceVisible && bottomSafeArea > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomSafeArea,
              child: IgnorePointer(
                child: ColoredBox(
                  key: const ValueKey('chat-input-panel-safe-area-background'),
                  color: c.panelBackground,
                ),
              ),
            ),
        ],
      ),
    );
    // Without its own layer the composer shares one with the chat wallpaper, so
    // a keystroke or a typing update re-records the full-screen gradient too.
    return RepaintBoundary(child: bar);
  }

  Widget _inlineBotResultMenu() {
    final c = context.colors;
    final results = _inlineBotResults?.results ?? const <BotInlineResult>[];
    Widget child;
    if (_inlineBotLoading) {
      child = SizedBox(
        height: 54,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppActivityIndicator(size: 18, color: c.textSecondary),
            const SizedBox(width: 10),
            Text(
              AppStrings.t(AppStringKeys.chatInputBarSearchingInlineResults),
              style: TextStyle(color: c.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    } else if (results.isEmpty) {
      child = SizedBox(
        height: 54,
        child: Center(
          child: Text(
            AppStrings.t(AppStringKeys.chatInputBarNoInlineResults),
            style: TextStyle(color: c.textSecondary, fontSize: 14),
          ),
        ),
      );
    } else {
      child = ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: results.length,
        separatorBuilder: (_, _) => const InsetDivider(leadingInset: 54),
        itemBuilder: (_, index) {
          final result = results[index];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_sendInlineBotResult(result)),
            child: SizedBox(
              height: 58,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    AppIcon(
                      _inlineResultIcon(result.type),
                      size: 23,
                      color: AppTheme.brand,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            result.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (result.description.isNotEmpty)
                            Text(
                              result.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.divider, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  AppIconData _inlineResultIcon(String type) => switch (type) {
    'inlineQueryResultAnimation' => HeroAppIcons.gif,
    'inlineQueryResultAudio' => HeroAppIcons.music,
    'inlineQueryResultContact' => HeroAppIcons.circleUser,
    'inlineQueryResultDocument' => HeroAppIcons.file,
    'inlineQueryResultGame' => HeroAppIcons.flash,
    'inlineQueryResultLocation' ||
    'inlineQueryResultVenue' => HeroAppIcons.locationDot,
    'inlineQueryResultPhoto' => HeroAppIcons.image,
    'inlineQueryResultSticker' => HeroAppIcons.solidFaceSmile,
    'inlineQueryResultVideo' => HeroAppIcons.video,
    'inlineQueryResultVoiceNote' => HeroAppIcons.microphone,
    _ => HeroAppIcons.font,
  };

  Future<void> _sendInlineBotResult(BotInlineResult result) async {
    final page = _inlineBotResults;
    if (page == null || page.queryId == 0 || result.id.isEmpty) return;
    try {
      final reply = vm.replyTo;
      await _botPlatform.sendInlineResult(
        chatId: vm.chatId,
        queryId: page.queryId,
        resultId: result.id,
        replyTo: reply == null
            ? null
            : {'@type': 'inputMessageReplyToMessage', 'message_id': reply.id},
      );
      if (!mounted) return;
      vm.setReply(null);
      _controller.clear();
      _focus.requestFocus();
      widget.onMessageSent();
    } catch (error) {
      _showBotPlatformFailure(error);
    }
  }

  Widget _botCommandMenu() {
    final c = context.colors;
    return Container(
      key: const ValueKey('groupBotCommandHints'),
      constraints: const BoxConstraints(maxHeight: 260),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.divider, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _botCommandCandidates.length,
        separatorBuilder: (_, _) => const InsetDivider(leadingInset: 54),
        itemBuilder: (context, index) {
          final command = _botCommandCandidates[index];
          final stableKey = '${command.botUserId}-${command.normalizedCommand}';
          return Semantics(
            button: true,
            label: '${command.botName}, ${command.displayCommand}',
            value: command.description,
            child: GestureDetector(
              key: ValueKey('groupBotCommand-$stableKey'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _sendBotCommandHint(command),
              child: SizedBox(
                height: 46,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    PhotoAvatar(
                      title: command.botName,
                      photo: command.botPhoto,
                      size: 30,
                      allowAnimation: false,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: command.displayCommand,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (command.description.trim().isNotEmpty)
                              TextSpan(
                                text: '  ${command.description.trim()}',
                                style: TextStyle(
                                  color: c.textSecondary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Semantics(
                      button: true,
                      label:
                          '${AppStrings.t(AppStringKeys.richTextComposerInsert)} ${command.displayCommand}',
                      child: GestureDetector(
                        key: ValueKey('insertGroupBotCommand-$stableKey'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _insertBotCommandHint(command),
                        child: SizedBox(
                          width: 42,
                          height: 46,
                          child: Center(
                            child: AppIcon(
                              HeroAppIcons.reply,
                              size: 18,
                              color: c.textTertiary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _mentionMenu() {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.divider, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _mentionCandidates.length,
        separatorBuilder: (_, _) => const InsetDivider(leadingInset: 54),
        itemBuilder: (context, index) {
          final candidate = _mentionCandidates[index];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectMention(candidate),
            child: SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    PhotoAvatar(
                      title: candidate.name,
                      photo: candidate.photo,
                      size: 34,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            candidate.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: c.textPrimary,
                            ),
                          ),
                          if (candidate.username.isNotEmpty)
                            Text(
                              '@${candidate.username}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // MARK: - Reply banner

  Widget _clipboardAttachmentStrip({required bool desktop}) {
    final c = context.colors;
    // A pasted 12 MP photo decodes to ~48 MB of RGBA for a 58 px chip, which
    // then evicts the rest of the image cache.
    final tileCachePx = (58 * MediaQuery.devicePixelRatioOf(context)).ceil();
    return SizedBox(
      key: const ValueKey('clipboardAttachmentStrip'),
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(
          desktop ? 18 : 12,
          4,
          desktop ? 18 : 12,
          8,
        ),
        itemCount: _pendingClipboardAttachments.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final attachment = _pendingClipboardAttachments[index];
          return SizedBox(
            key: ValueKey('clipboardAttachment-$index'),
            width: 58,
            height: 58,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: c.searchFill),
                      child: Image.file(
                        File(attachment.path),
                        fit: BoxFit.cover,
                        cacheWidth: tileCachePx,
                        errorBuilder: (_, _, _) => Center(
                          child: AppIcon(
                            HeroAppIcons.image,
                            size: 21,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: -5,
                  right: -5,
                  child: AppInteractiveSurface(
                    key: ValueKey('clipboardAttachmentRemove-$index'),
                    semanticLabel: AppStringKeys.chatInfoRemove.l10n(context),
                    onTap: () => _removeClipboardAttachment(index),
                    borderRadius: BorderRadius.circular(11),
                    child: Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: c.card,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.divider, width: 0.75),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: AppIcon(
                        HeroAppIcons.xmark,
                        size: 13,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _removeClipboardAttachment(int index) {
    if (index < 0 || index >= _pendingClipboardAttachments.length) {
      return;
    }
    final attachment = _pendingClipboardAttachments[index];
    setState(() => _pendingClipboardAttachments.removeAt(index));
    widget.onPanelGeometryChanged?.call();
    unawaited(_deleteTempFile(attachment.path));
  }

  Widget _editBanner(ChatMessage message) {
    final c = context.colors;
    final preview = _replyPreview(message).trim();
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
      child: Container(
        key: const ValueKey('composerEditBanner'),
        height: 46,
        padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            AppTheme.cloverGreen.withValues(alpha: 0.08),
            c.searchFill,
          ),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            Container(
              width: 2.5,
              height: 30,
              decoration: BoxDecoration(
                color: AppTheme.cloverGreen,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStringKeys.chatEditMessageTitle.l10n(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.cloverGreen,
                    ),
                  ),
                  if (preview.isNotEmpty)
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                ],
              ),
            ),
            AppInteractiveSurface(
              key: const ValueKey('composerEditCancel'),
              semanticLabel: AppStringKeys.countryPickerCancel.l10n(context),
              onTap: vm.cancelMessageEdit,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.all(7),
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: 17,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _replyBanner(ChatMessage m) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _replyLine(m),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => vm.setReply(null),
              child: AppIcon(
                HeroAppIcons.xmark,
                size: 18,
                color: c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _replyLine(ChatMessage m) {
    final name = m.isOutgoing
        ? vm.meName
        : (m.senderName?.isNotEmpty ?? false)
        ? m.senderName!
        : vm.peerTitle;
    return '$name:${_replyPreview(m)}';
  }

  String _replyPreview(ChatMessage m) {
    if (m.document != null) {
      return AppStrings.t(AppStringKeys.composerFilePreview, {
        'value1': m.document!.fileName,
      });
    }
    if (m.voice != null) {
      return AppStrings.t(AppStringKeys.composerVoicePreview);
    }
    if (m.location != null) {
      return AppStrings.t(AppStringKeys.composerLocationPreview);
    }
    if (m.isDice) {
      return m.diceEmoji ?? m.text;
    }
    if (m.isAnimatedEmoji) {
      return m.text;
    }
    if (m.animatedSticker != null) {
      return AppStrings.t(AppStringKeys.composerAnimatedEmojiPreview);
    }
    if (m.image != null) {
      return m.text.isEmpty
          ? AppStrings.t(AppStringKeys.composerImagePreview)
          : m.text;
    }
    return m.text;
  }

  // MARK: - Input row

  void _hideDesktopPopovers({bool rebuild = true}) {
    final changed =
        _desktopSenderPopoverVisible ||
        _desktopEmojiPopoverVisible ||
        _desktopStickerPopoverVisible;
    if (_desktopSenderPopoverVisible) {
      _desktopSenderPopoverController.hide();
      _desktopSenderPopoverVisible = false;
    }
    if (_desktopEmojiPopoverVisible) {
      _desktopEmojiPopoverController.hide();
      _desktopEmojiPopoverVisible = false;
    }
    if (_desktopStickerPopoverVisible) {
      _desktopStickerPopoverController.hide();
      _desktopStickerPopoverVisible = false;
    }
    if (changed && rebuild && mounted) setState(() {});
  }

  void _toggleDesktopSenderPopover() {
    if (_desktopSenderPopoverVisible) {
      _hideDesktopPopovers();
      return;
    }
    _hideDesktopPopovers(rebuild: false);
    _desktopSenderPopoverController.show();
    setState(() => _desktopSenderPopoverVisible = true);
  }

  void _toggleDesktopEmojiPopover() {
    if (_desktopEmojiPopoverVisible) {
      _hideDesktopPopovers();
      return;
    }
    _hideDesktopPopovers(rebuild: false);
    if (_panel != _Panel.none) {
      _panel = _Panel.none;
      widget.onPanelGeometryChanged?.call();
    }
    EmojiStore.shared.loadIfNeeded();
    _desktopEmojiPopoverController.show();
    setState(() => _desktopEmojiPopoverVisible = true);
    if (_isPanelSearchSelected && _panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    }
  }

  void _toggleDesktopStickerPopover() {
    if (_desktopStickerPopoverVisible) {
      _hideDesktopPopovers();
      return;
    }
    _hideDesktopPopovers(rebuild: false);
    if (_panel != _Panel.none) {
      _panel = _Panel.none;
      widget.onPanelGeometryChanged?.call();
    }
    StickerStore.shared.loadIfNeeded();
    GifStore.shared.loadIfNeeded();
    _desktopStickerPopoverController.show();
    setState(() => _desktopStickerPopoverVisible = true);
    if (_isPanelSearchSelected && _panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    }
  }

  Widget _desktopPopoverOverlay({
    required BuildContext overlayContext,
    required LayerLink link,
    required Key surfaceKey,
    required double width,
    required Widget child,
    required VoidCallback onDismiss,
    double cornerRadius = 14,
  }) {
    final c = overlayContext.colors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: ValueKey('${surfaceKey.toString()}Dismiss'),
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(0, -8),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): onDismiss,
            },
            child: Focus(
              key: ValueKey('${surfaceKey.toString()}Focus'),
              autofocus: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Container(
                  key: surfaceKey,
                  width: width,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.panelBackground,
                    borderRadius: BorderRadius.circular(cornerRadius),
                    border: Border.all(color: c.divider, width: 0.7),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _desktopSenderPopover(BuildContext overlayContext) {
    final options = vm.availableMessageSenders;
    final availableWidth = math.max(
      220.0,
      math.min(248.0, MediaQuery.sizeOf(overlayContext).width - 24),
    );
    return _desktopPopoverOverlay(
      overlayContext: overlayContext,
      link: _desktopSenderPopoverLink,
      surfaceKey: const ValueKey('desktopSenderPopover'),
      width: availableWidth,
      onDismiss: _hideDesktopPopovers,
      cornerRadius: 10,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: options.length,
          separatorBuilder: (_, _) => const InsetDivider(leadingInset: 48),
          itemBuilder: (_, index) => _senderOptionRow(
            options[index],
            compact: true,
            onSelected: () {
              _hideDesktopPopovers();
              vm.selectMessageSender(options[index]);
            },
          ),
        ),
      ),
    );
  }

  Widget _desktopEmojiPopover(BuildContext overlayContext) {
    final size = MediaQuery.sizeOf(overlayContext);
    final width = math.max(300.0, math.min(420.0, size.width - 24));
    final height = math.max(220.0, math.min(360.0, size.height - 88));
    return _desktopPopoverOverlay(
      overlayContext: overlayContext,
      link: _desktopEmojiPopoverLink,
      surfaceKey: const ValueKey('desktopEmojiPopover'),
      width: width,
      onDismiss: _hideDesktopPopovers,
      child: _emojiPanel(height: height, popover: true),
    );
  }

  Widget _desktopStickerPopover(BuildContext overlayContext) {
    final size = MediaQuery.sizeOf(overlayContext);
    final width = math.max(300.0, math.min(420.0, size.width - 24));
    final height = math.max(220.0, math.min(360.0, size.height - 88));
    return _desktopPopoverOverlay(
      overlayContext: overlayContext,
      link: _desktopStickerPopoverLink,
      surfaceKey: const ValueKey('desktopStickerPopover'),
      width: width,
      onDismiss: _hideDesktopPopovers,
      child: _stickerPanel(height: height, popover: true),
    );
  }

  void _showSenderPicker() {
    final options = vm.availableMessageSenders;
    if (options.length <= 1) return;
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < options.length; i++) ...[
                  _senderOptionRow(options[i]),
                  if (i < options.length - 1)
                    const InsetDivider(leadingInset: 64),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _showBotMenu({bool forceMenu = false}) {
    final commands = vm.botCommands;
    final menu = vm.botMenu;
    final showTools = vm.peerIsBot || _guestQueries.isNotEmpty;
    if (!(menu?.isWebApp ?? false) && commands.isEmpty && !showTools) return;
    if (!forceMenu && (menu?.isWebApp ?? false)) {
      unawaited(_openBotMenuWebApp(menu!));
      return;
    }
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                if (menu?.isWebApp ?? false) ...[
                  _botMenuRow(
                    icon: HeroAppIcons.bot,
                    title: menu!.actionTitle,
                    subtitle: '',
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_openBotMenuWebApp(menu));
                    },
                  ),
                  if (commands.isNotEmpty || showTools)
                    const InsetDivider(leadingInset: 56),
                ],
                for (var i = 0; i < commands.length; i++) ...[
                  _botMenuRow(
                    icon: HeroAppIcons.code,
                    title: '/${commands[i].command}',
                    subtitle: commands[i].description,
                    onTap: () {
                      Navigator.of(context).pop();
                      _insertBotCommand(commands[i].command);
                    },
                  ),
                  if (i < commands.length - 1 || showTools)
                    const InsetDivider(leadingInset: 56),
                ],
                if (showTools)
                  _botMenuRow(
                    icon: HeroAppIcons.gear,
                    title: AppStrings.t(AppStringKeys.chatInputBarBotTools),
                    subtitle: _guestQueries.isEmpty
                        ? 'Inline mode, topics, and automation'
                        : '${_guestQueries.length} guest ${_guestQueries.length == 1 ? 'query' : 'queries'} waiting',
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(_showBotTools());
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openBotMenuWebApp(BotMenuInfo menu) async {
    final botUserId = vm.peerUserId;
    if (botUserId == null) {
      if (!menu.isLegacyMenuUrl && menu.webAppUrl.isNotEmpty) {
        await openLink(context, menu.webAppUrl);
      }
      return;
    }
    final opened = await openTelegramMiniApp(
      context,
      chatId: vm.chatId,
      botUserId: botUserId,
      url: menu.url,
      title: menu.actionTitle,
      menuWebApp: true,
    );
    if (!opened && mounted) {
      showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
    }
  }

  Widget _botMenuRow({
    required AppIconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              AppIcon(icon, size: 22, color: AppTheme.brand),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, color: c.textPrimary),
                    ),
                    if (subtitle.trim().isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _insertBotCommand(String command) {
    final text = '/${command.trim()} ';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  Future<void> _showBotTools() async {
    BotPlatformCapabilities? capabilities;
    final botUserId = vm.peerUserId;
    if (vm.peerIsBot && botUserId != null) {
      try {
        capabilities = await _botPlatform.capabilitiesForUserId(botUserId);
      } catch (_) {
        // The menu still exposes account-bot and received guest-query tools.
      }
    }

    var currentAccountIsBot = false;
    try {
      currentAccountIsBot = await _botPlatform.currentAccountIsBot();
    } catch (_) {
      // User accounts don't need the bot update status action.
    }
    if (!mounted) return;

    await showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        final entries =
            <
              ({
                AppIconData icon,
                String title,
                String subtitle,
                VoidCallback onTap,
              })
            >[];
        final resolved = capabilities;
        if (resolved?.inlineMode == true &&
            resolved!.username.trim().isNotEmpty) {
          entries.add((
            icon: HeroAppIcons.at,
            title: AppStrings.t(AppStringKeys.chatInputBarUseInlineMode),
            subtitle: resolved.inlinePlaceholder.trim().isEmpty
                ? '@${resolved.username}'
                : resolved.inlinePlaceholder,
            onTap: () {
              Navigator.of(sheetContext).pop();
              _insertInlineBot(resolved);
            },
          ));
        }
        if (resolved?.hasTopics == true &&
            resolved?.allowsUsersToCreateTopics == true) {
          entries.add((
            icon: HeroAppIcons.comments,
            title: AppStrings.t(AppStringKeys.chatInputBarCreateBotTopic),
            subtitle: AppStrings.t(
              AppStringKeys.chatInputBarCreateBotTopicDetail,
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(_createBotTopic());
            },
          ));
        }
        if (resolved?.canManageBots == true) {
          entries.add((
            icon: HeroAppIcons.userPlus,
            title: AppStrings.t(AppStringKeys.chatInputBarCreateManagedBot),
            subtitle: AppStrings.t(
              AppStringKeys.chatInputBarCreateManagedBotDetailValue1,
              {'value1': resolved!.username},
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(_createManagedBot(resolved.userId));
            },
          ));
        }
        if (_guestQueries.isNotEmpty) {
          entries.add((
            icon: HeroAppIcons.comments,
            title: AppStrings.t(AppStringKeys.chatInputBarGuestQueries),
            subtitle: AppStrings.plural(
              AppStringKeys.chatInputBarGuestQueriesWaiting,
              _guestQueries.length,
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _showGuestQueries();
            },
          ));
        }
        if (currentAccountIsBot) {
          entries.add((
            icon: HeroAppIcons.gear,
            title: AppStrings.t(AppStringKeys.chatInputBarAutomationStatus),
            subtitle: AppStrings.t(
              AppStringKeys.chatInputBarAutomationStatusDetail,
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              unawaited(_updateBotAutomationStatus());
            },
          ));
        }

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      AppStrings.t(
                        AppStringKeys
                            .chatInputBarNoAdditionalToolsAreAvailableForThisBot,
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.textSecondary, fontSize: 14),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) =>
                        const InsetDivider(leadingInset: 56),
                    itemBuilder: (_, index) {
                      final entry = entries[index];
                      return _botMenuRow(
                        icon: entry.icon,
                        title: entry.title,
                        subtitle: entry.subtitle,
                        onTap: entry.onTap,
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  void _insertInlineBot(BotPlatformCapabilities bot) {
    final clean = bot.username.replaceFirst('@', '').trim();
    if (clean.isEmpty) return;
    _inlineBot = bot;
    final text = '@$clean ';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  Future<void> _createBotTopic() async {
    final name = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarCreateBotTopic),
      label: AppStrings.t(AppStringKeys.chatInputBarTopicName),
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarCreateAction),
    );
    if (name == null) return;
    try {
      final result = await _botPlatform.createBotTopic(
        chatId: vm.chatId,
        name: name,
      );
      final topicId = forumTopicIdFromResult(result);
      await vm.loadForumTopics();
      if (!mounted) return;
      final onBotTopicCreated = widget.onBotTopicCreated;
      if (topicId != null && topicId != 0 && onBotTopicCreated != null) {
        onBotTopicCreated(topicId);
        return;
      }
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatInputBarBotTopicCreated),
      );
    } catch (error) {
      _showBotPlatformFailure(error);
    }
  }

  Future<void> _createManagedBot(
    int managerBotUserId, {
    String suggestedName = '',
    String suggestedUsername = '',
  }) async {
    final name = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarCreateManagedBot),
      label: AppStrings.t(AppStringKeys.chatInputBarBotName),
      initialValue: suggestedName,
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarNextAction),
    );
    if (name == null) return;
    final username = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarCreateManagedBot),
      label: AppStrings.t(AppStringKeys.editProfileUsername),
      initialValue: suggestedUsername,
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarCreateAction),
    );
    if (username == null) return;
    try {
      await _botPlatform.createManagedBot(
        managerBotUserId: managerBotUserId,
        name: name,
        username: username,
      );
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatInputBarManagedBotCreated),
        );
      }
    } catch (error) {
      _showBotPlatformFailure(error);
    }
  }

  void _showGuestQueries() {
    showAppModalSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return SafeArea(
          child: Container(
            constraints: const BoxConstraints(maxHeight: 420),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _guestQueries.length,
              separatorBuilder: (_, _) => const InsetDivider(leadingInset: 56),
              itemBuilder: (_, index) {
                final query = _guestQueries[index];
                return _botMenuRow(
                  icon: HeroAppIcons.message,
                  title: _guestQueryPreview(query),
                  subtitle:
                      '${query.referenceMessages.length} reference ${query.referenceMessages.length == 1 ? 'message' : 'messages'}',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_replyToGuestQuery(query));
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _guestQueryPreview(BotGuestQuery query) {
    try {
      final content = query.message.obj('content');
      final text = content == null ? '' : TDParse.messageText(content).trim();
      if (text.isNotEmpty) return text;
    } catch (_) {
      // Fall back to the stable guest query identifier below.
    }
    return AppStrings.t(AppStringKeys.chatInputBarGuestQueryValue1, {
      'value1': query.id,
    });
  }

  Future<void> _replyToGuestQuery(BotGuestQuery query) async {
    final reply = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarAnswerGuestQuery),
      label: AppStrings.t(AppStringKeys.chatInputBarReply),
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarSendAction),
    );
    if (reply == null) return;
    try {
      await _botPlatform.answerGuestQuery(
        guestQueryId: query.id,
        result: {
          '@type': 'inputInlineQueryResultArticle',
          'id': 'guest_${query.id}',
          'url': '',
          'title': 'Reply',
          'description': reply,
          'thumbnail_url': '',
          'thumbnail_width': 0,
          'thumbnail_height': 0,
          'reply_markup': null,
          'input_message_content': {
            '@type': 'inputMessageText',
            'text': {
              '@type': 'formattedText',
              'text': reply,
              'entities': <Map<String, dynamic>>[],
            },
            'link_preview_options': null,
            'clear_draft': false,
          },
        },
      );
      if (!mounted) return;
      setState(() => _guestQueries.removeWhere((item) => item.id == query.id));
      showToast(
        context,
        AppStrings.t(AppStringKeys.chatInputBarGuestQueryAnswered),
      );
    } catch (error) {
      _showBotPlatformFailure(error);
    }
  }

  Future<void> _updateBotAutomationStatus() async {
    final pendingText = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarAutomationStatus),
      label: AppStrings.t(AppStringKeys.chatInputBarPendingUpdateCount),
      initialValue: '0',
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarNextAction),
      keyboardType: TextInputType.number,
    );
    if (pendingText == null) return;
    final pendingCount = int.tryParse(pendingText);
    if (pendingCount == null || pendingCount < 0) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatInputBarEnterANonNegativeUpdateCount),
        );
      }
      return;
    }
    final errorMessage = await _promptBotText(
      title: AppStrings.t(AppStringKeys.chatInputBarAutomationStatus),
      label: AppStrings.t(AppStringKeys.chatInputBarErrorMessageOptional),
      actionLabel: AppStrings.t(AppStringKeys.chatInputBarReportAction),
      allowEmpty: true,
    );
    if (errorMessage == null) return;
    try {
      await _botPlatform.updateBotAutomationStatus(
        pendingUpdateCount: pendingCount,
        errorMessage: errorMessage,
      );
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.chatInputBarAutomationStatusUpdated),
        );
      }
    } catch (error) {
      _showBotPlatformFailure(error);
    }
  }

  Future<String?> _promptBotText({
    required String title,
    required String label,
    required String actionLabel,
    String initialValue = '',
    bool allowEmpty = false,
    TextInputType? keyboardType,
  }) => showAppTextEntryDialog(
    context,
    title: title,
    label: label,
    actionLabel: actionLabel,
    initial: initialValue,
    allowEmpty: allowEmpty,
    keyboardType: keyboardType,
  );

  void _showBotPlatformFailure(Object error) {
    if (!mounted) return;
    final detail = error is TdError
        ? error.message
        : AppStrings.t(AppStringKeys.chatInputBarActionFailed);
    showToast(context, detail);
  }

  Widget _senderOptionRow(
    MessageSenderOption option, {
    VoidCallback? onSelected,
    bool compact = false,
  }) {
    final c = context.colors;
    final selected =
        vm.selectedMessageSender?.sameSender(option.sender) == true;
    return GestureDetector(
      key: compact ? ValueKey('desktopSenderOption-${option.id}') : null,
      behavior: HitTestBehavior.opaque,
      onTap: option.needsPremium
          ? null
          : onSelected ??
                () {
                  Navigator.of(context).pop();
                  vm.selectMessageSender(option);
                },
      child: SizedBox(
        height: compact ? 40 : 56,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14),
          child: Row(
            children: [
              PhotoAvatar(
                title: option.title,
                photo: option.photo,
                size: compact ? 30 : 36,
              ),
              SizedBox(width: compact ? 8 : 12),
              Expanded(
                child: Text(
                  option.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 14 : 16,
                    color: c.textPrimary,
                  ),
                ),
              ),
              if (option.needsPremium)
                Text(
                  AppStringKeys.premiumLabel.l10n(context),
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    color: AppTheme.brand,
                  ),
                )
              else if (selected)
                AppIcon(
                  HeroAppIcons.check,
                  size: compact ? 16 : 18,
                  color: AppTheme.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  _ReplyKeyboard? _activeReplyKeyboard() {
    for (final message in vm.messages.reversed) {
      // Almost every message has no buttons; skipping them keeps this
      // per-build whole-transcript walk allocation-free.
      if (message.buttonRows.isEmpty) continue;
      final rows = message.buttonRows
          .map((row) => row.where((button) => button.isReplyKeyboard).toList())
          .where((row) => row.isNotEmpty)
          .toList();
      if (rows.isNotEmpty) return _ReplyKeyboard(message: message, rows: rows);
    }
    return null;
  }

  MessageButton? _webAppButton(_ReplyKeyboard? keyboard) {
    if (keyboard == null) return null;
    for (final row in keyboard.rows) {
      for (final button in row) {
        if (button.isWebApp && (button.url?.isNotEmpty ?? false)) {
          return button;
        }
      }
    }
    return null;
  }

  Future<void> _openReplyKeyboardWebApp(
    _ReplyKeyboard keyboard,
    MessageButton button,
  ) async {
    final url = button.url;
    if (url == null || url.isEmpty) return;
    final botUserId = await vm.webAppBotUserId(keyboard.message);
    if (!mounted) return;
    if (botUserId == null) {
      showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
      return;
    }
    final opened = await openTelegramMiniApp(
      context,
      chatId: vm.chatId,
      botUserId: botUserId,
      url: url,
      title: button.text,
      keyboardButtonText: button.text,
    );
    if (!opened && mounted) {
      showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
    }
  }

  void _pressReplyKeyboardButton(
    _ReplyKeyboard keyboard,
    MessageButton button,
  ) {
    if (button.isWebApp) {
      unawaited(_openReplyKeyboardWebApp(keyboard, button));
      return;
    }
    if (button.type == 'keyboardButtonTypeText') {
      vm.sendKeyboardButtonText(button.text);
      widget.onMessageSent();
      return;
    }
    if (button.type == 'keyboardButtonTypeRequestManagedBot') {
      final managerBotUserId = vm.peerUserId;
      if (managerBotUserId != null) {
        unawaited(
          _createManagedBot(
            managerBotUserId,
            suggestedName: button.suggestedName ?? '',
            suggestedUsername: button.suggestedUsername ?? '',
          ),
        );
        return;
      }
    }
    showToast(context, AppStringKeys.chatButtonUnsupported);
  }

  void _toggleReplyKeyboard() {
    setState(() {
      _replyKeyboardVisible = !_replyKeyboardVisible;
      if (_replyKeyboardVisible) {
        _panel = _Panel.none;
        _quickReplyContextVisible = false;
      }
    });
    widget.onPanelGeometryChanged?.call();
    if (_replyKeyboardVisible) _focus.unfocus();
  }

  void _handleEmptyInputTap() {
    if (_hasText || !_canUseQuickReplies || _replyKeyboardVisible) return;
    if (_quickReplyContextVisible) {
      setState(() => _quickReplyContextVisible = false);
      return;
    }
    if (_quickRepliesLoaded) {
      if (_quickReplies.isEmpty) return;
      _focus.unfocus();
      setState(() => _quickReplyContextVisible = true);
      return;
    }
    unawaited(_loadQuickReplies(userInitiated: true));
  }

  Future<List<BusinessQuickReplyShortcut>> _fetchQuickReplies() async {
    final injected = widget.quickReplyLoader;
    if (injected != null) return injected();
    return BusinessQuickReplyService.shared.preloadShortcuts();
  }

  Future<void> _loadQuickReplies({required bool userInitiated}) async {
    if (_quickRepliesLoaded || !_canUseQuickReplies) return;
    try {
      final replies = await _fetchQuickReplies();
      if (!mounted) return;
      setState(() {
        _quickReplies = replies;
        _quickRepliesLoaded = true;
        _quickReplyContextVisible =
            userInitiated && replies.isNotEmpty && _canUseQuickReplies;
      });
      if (userInitiated && replies.isNotEmpty) _focus.unfocus();
    } catch (error) {
      if (!mounted) return;
      setState(() => _quickReplyContextVisible = false);
      if (userInitiated) {
        showToast(
          context,
          AppStrings.t(
            AppStringKeys.businessToolsCouldNotLoadQuickRepliesValue1,
            {'value1': error},
          ),
        );
        _restoreKeyboardFocus();
      }
    }
  }

  Future<void> _sendQuickReply(BusinessQuickReplyShortcut shortcut) async {
    if (_quickReplySendingId != null) return;
    setState(() => _quickReplySendingId = shortcut.id);
    try {
      final injected = widget.quickReplySender;
      if (injected != null) {
        await injected(vm.chatId, shortcut.id);
      } else {
        await BusinessQuickReplyService.shared.send(vm.chatId, shortcut.id);
      }
      if (!mounted) return;
      setState(() {
        _quickReplySendingId = null;
        _quickReplyContextVisible = false;
      });
      widget.onMessageSent();
    } catch (error) {
      if (!mounted) return;
      setState(() => _quickReplySendingId = null);
      showToast(
        context,
        AppStrings.t(AppStringKeys.businessToolsCouldNotSendQuickReplyValue1, {
          'value1': error,
        }),
      );
    }
  }

  Widget _quickReplyContextMenu() {
    if (_quickReplies.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final height = math.min(44 + (_quickReplies.length * 58), 276).toDouble();
    return Container(
      key: const ValueKey('quickReplyContextMenu'),
      height: height,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  AppIcon(
                    HeroAppIcons.solidMessage,
                    size: 17,
                    color: AppTheme.brand,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.t(AppStringKeys.businessToolsQuickReplies),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    key: const ValueKey('closeQuickReplyContextMenu'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        setState(() => _quickReplyContextVisible = false),
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Center(
                        child: AppIcon(
                          HeroAppIcons.xmark,
                          size: 18,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _quickReplies.length,
              itemBuilder: (context, index) {
                final shortcut = _quickReplies[index];
                final sending = _quickReplySendingId == shortcut.id;
                return GestureDetector(
                  key: ValueKey('quickReply-${shortcut.id}'),
                  behavior: HitTestBehavior.opaque,
                  onTap: sending
                      ? null
                      : () => unawaited(_sendQuickReply(shortcut)),
                  child: Container(
                    height: 58,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: c.divider.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '/${shortcut.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: c.textPrimary,
                                ),
                              ),
                              if (shortcut.preview.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  shortcut.preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (sending)
                          AppActivityIndicator(size: 18, color: AppTheme.brand)
                        else
                          AppIcon(
                            HeroAppIcons.paperPlane,
                            size: 18,
                            color: AppTheme.brand,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputRow(
    _ReplyKeyboard? replyKeyboard, {
    required AiSettingsController? aiSettings,
    bool desktop = false,
  }) {
    final c = context.colors;
    final editing = vm.editingMessage != null;
    final hasText =
        _hasText || editing || _pendingClipboardAttachments.isNotEmpty;
    final replyTarget = _currentAiReplyTarget();
    final aiReplyWorking =
        replyTarget != null && _aiReplyWorkingTargetId == replyTarget.id;
    final showAiReply =
        !editing &&
        (!hasText || aiReplyWorking) &&
        replyTarget != null &&
        _isAiReplyTargetEligible(replyTarget);
    final sender = vm.selectedMessageSender;
    final webAppButton = editing || desktop
        ? null
        : _webAppButton(replyKeyboard);
    final desktopCanvasHeight = clampDesktopComposerCanvasHeight(
      _desktopComposerCanvasHeight,
      viewportHeight: MediaQuery.sizeOf(context).height,
    );
    return Padding(
      key: desktop ? const ValueKey('desktopComposerInput') : null,
      padding: desktop
          ? const EdgeInsets.fromLTRB(18, 2, 18, 12)
          : const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 6),
      child: Stack(
        key: desktop ? const ValueKey('desktopComposerInputStack') : null,
        clipBehavior: Clip.none,
        children: [
          Row(
            key: desktop
                ? const ValueKey('desktopComposerFullWidthEditorRow')
                : null,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Desktop utility actions live in the toolbar so the editor
              // keeps the entire composer width.
              if (!desktop &&
                  webAppButton != null &&
                  replyKeyboard != null) ...[
                _replyKeyboardMiniAppAction(replyKeyboard, webAppButton),
                const SizedBox(width: 8),
              ] else if (!desktop &&
                  !editing &&
                  (vm.peerIsBot || _guestQueries.isNotEmpty)) ...[
                Semantics(
                  button: true,
                  label: AppStrings.t(AppStringKeys.chatInputBarOpenBotMenu),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showBotMenu,
                    onLongPress: () => _showBotMenu(forceMenu: true),
                    child: Container(
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: c.searchFill,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      alignment: Alignment.center,
                      child: AppIcon(
                        HeroAppIcons.bot,
                        size: 20,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_aiReplyProgressPhases.isNotEmpty) ...[
                      _aiReplyProgressDisclosure(isWorking: aiReplyWorking),
                      const SizedBox(height: 4),
                    ],
                    SizedBox(
                      key: desktop
                          ? const ValueKey('desktopComposerCanvas')
                          : null,
                      height: desktop ? desktopCanvasHeight : null,
                      child: Container(
                        key: const ValueKey('composerTextInputBox'),
                        decoration: desktop
                            ? const BoxDecoration()
                            : BoxDecoration(
                                color: c.searchFill,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                              ),
                        padding: desktop
                            ? const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 6,
                              )
                            : const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                        child: Row(
                          crossAxisAlignment: hasText
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.center,
                          children: [
                            if (!editing &&
                                !desktop &&
                                vm.canChooseMessageSender &&
                                sender != null) ...[
                              GestureDetector(
                                key: const ValueKey('composerSenderPicker'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _showSenderPicker,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    PhotoAvatar(
                                      title: sender.title,
                                      photo: sender.photo,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 2),
                                    AppIcon(
                                      HeroAppIcons.chevronDown,
                                      size: 16,
                                      color: c.textTertiary,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Shortcuts(
                                shortcuts: widget.enterToSend
                                    ? const {
                                        SingleActivator(
                                          LogicalKeyboardKey.enter,
                                        ): _SendComposerIntent(),
                                        SingleActivator(
                                          LogicalKeyboardKey.numpadEnter,
                                        ): _SendComposerIntent(),
                                        SingleActivator(
                                          LogicalKeyboardKey.enter,
                                          control: true,
                                        ): _InsertComposerLineBreakIntent(),
                                        SingleActivator(
                                          LogicalKeyboardKey.numpadEnter,
                                          control: true,
                                        ): _InsertComposerLineBreakIntent(),
                                      }
                                    : const {
                                        SingleActivator(
                                          LogicalKeyboardKey.enter,
                                        ): _InsertComposerLineBreakIntent(),
                                        SingleActivator(
                                          LogicalKeyboardKey.numpadEnter,
                                        ): _InsertComposerLineBreakIntent(),
                                        SingleActivator(
                                          LogicalKeyboardKey.enter,
                                          control: true,
                                        ): _SendComposerIntent(),
                                        SingleActivator(
                                          LogicalKeyboardKey.numpadEnter,
                                          control: true,
                                        ): _SendComposerIntent(),
                                      },
                                child: Actions(
                                  actions: {
                                    PasteTextIntent:
                                        CallbackAction<PasteTextIntent>(
                                          onInvoke: (_) {
                                            unawaited(_handlePaste());
                                            return null;
                                          },
                                        ),
                                    _SendComposerIntent: _SendComposerAction(
                                      canInvoke: () =>
                                          !_hasActiveTextComposition,
                                      onInvoke: () =>
                                          unawaited(_sendCurrentText()),
                                    ),
                                    _InsertComposerLineBreakIntent:
                                        CallbackAction<
                                          _InsertComposerLineBreakIntent
                                        >(
                                          onInvoke: (_) {
                                            _insertComposerLineBreak();
                                            return null;
                                          },
                                        ),
                                  },
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _focus,
                                    onTap: _handleEmptyInputTap,
                                    minLines: desktop ? null : 1,
                                    maxLines: desktop ? null : 4,
                                    expands: desktop,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: desktop
                                        ? TextInputAction.newline
                                        : widget.enterToSend
                                        ? TextInputAction.send
                                        : TextInputAction.newline,
                                    onSubmitted: !desktop && widget.enterToSend
                                        ? (_) => unawaited(_sendCurrentText())
                                        : null,
                                    inputFormatters:
                                        widget.enterToSend &&
                                            Theme.of(context).platform ==
                                                TargetPlatform.android
                                        ? [
                                            _ComposerEnterToSendFormatter(
                                              onSend: _scheduleKeyboardSend,
                                            ),
                                          ]
                                        : null,
                                    style: TextStyle(
                                      fontSize: AppTextSize.messageBody(
                                        Theme.of(context).platform,
                                      ),
                                      color: c.textPrimary,
                                    ),
                                    contentInsertionConfiguration: editing
                                        ? null
                                        : ContentInsertionConfiguration(
                                            allowedMimeTypes: _imageMimeTypes,
                                            onContentInserted:
                                                _handleInsertedContent,
                                          ),
                                    contextMenuBuilder:
                                        (
                                          BuildContext context,
                                          EditableTextState editableTextState,
                                        ) {
                                          ContextMenuButtonItem? originalPaste;
                                          final items =
                                              <ContextMenuButtonItem>[];
                                          for (final item
                                              in editableTextState
                                                  .contextMenuButtonItems) {
                                            if (item.type ==
                                                ContextMenuButtonType.paste) {
                                              originalPaste = item;
                                            } else {
                                              items.add(item);
                                            }
                                          }
                                          final paste = ContextMenuButtonItem(
                                            type: ContextMenuButtonType.paste,
                                            label:
                                                originalPaste?.label ??
                                                AppStringKeys
                                                    .accountBackupLoadPyrogramPaste
                                                    .l10n(context),
                                            onPressed: () => unawaited(
                                              _handlePaste(originalPaste),
                                            ),
                                          );
                                          final copyIndex = items.indexWhere(
                                            (item) =>
                                                item.type ==
                                                ContextMenuButtonType.copy,
                                          );
                                          final pasteIndex = copyIndex < 0
                                              ? 0
                                              : copyIndex + 1;
                                          items.insert(pasteIndex, paste);
                                          final selection =
                                              _controller.selection;
                                          if (selection.isValid &&
                                              !selection.isCollapsed) {
                                            items.insert(
                                              pasteIndex + 1,
                                              ContextMenuButtonItem(
                                                label: AppStringKeys
                                                    .composerFormat
                                                    .l10n(context),
                                                onPressed: () => unawaited(
                                                  _showComposerFormatMenu(
                                                    editableTextState,
                                                  ),
                                                ),
                                              ),
                                            );
                                          }
                                          return AdaptiveTextSelectionToolbar.buttonItems(
                                            anchors: editableTextState
                                                .contextMenuAnchors,
                                            buttonItems: items,
                                          );
                                        },
                                    decoration: InputDecoration(
                                      hintText: AppStringKeys
                                          .chatMessageInputPlaceholder
                                          .l10n(context),
                                      border: InputBorder.none,
                                      isCollapsed: true,
                                      contentPadding: desktop && hasText
                                          ? const EdgeInsets.only(bottom: 42)
                                          : EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (!desktop && !hasText && replyKeyboard != null)
                              Semantics(
                                button: true,
                                label: _replyKeyboardVisible
                                    ? 'Hide bot keyboard'
                                    : 'Show bot keyboard',
                                child: GestureDetector(
                                  key: const ValueKey(
                                    'composerReplyKeyboardToggle',
                                  ),
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _toggleReplyKeyboard,
                                  child: SizedBox(
                                    width: 32,
                                    height: 24,
                                    child: Center(
                                      child: AppIcon(
                                        _replyKeyboardVisible
                                            ? HeroAppIcons.chevronDown
                                            : HeroAppIcons.tableCells,
                                        size: _replyKeyboardVisible ? 22 : 23,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (!hasText && vm.messageAutoDeleteTime > 0) ...[
                              const SizedBox(width: 4),
                              _autoDeleteInputIndicator(),
                            ],
                            if (!desktop && showAiReply) ...[
                              const SizedBox(width: 4),
                              _aiReplyInputButton(replyTarget),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasText && !desktop) ...[
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!editing &&
                        !desktop &&
                        vm.canUseAiComposition &&
                        _aiDraftEligible) ...[
                      Semantics(
                        button: true,
                        label: AppStringKeys.telegramAiEditorTelegramAIEditor
                            .l10n(context),
                        child: GestureDetector(
                          key: const ValueKey('composerAiPrefixButton'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => unawaited(_openTelegramAiEditor()),
                          child: Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.brand.withValues(alpha: 0.10),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppTheme.brand.withValues(alpha: 0.34),
                                width: 0.75,
                              ),
                            ),
                            child: AppIcon(
                              HeroAppIcons.palette,
                              key: const ValueKey('composerAiStyleIcon'),
                              size: 19,
                              color: AppTheme.brand,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                    GestureDetector(
                      key: const ValueKey('composerSendButton'),
                      onTap: _aiReplyWorkingTargetId != null
                          ? null
                          : () => unawaited(_sendCurrentText()),
                      onLongPress: _aiReplyWorkingTargetId != null
                          ? null
                          : editing
                          ? null
                          : () => unawaited(_showTextSendOptions()),
                      child: Container(
                        width: vm.requiresPaidMessage ? 58 : 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _aiReplyWorkingTargetId != null
                              ? AppTheme.brand.withValues(alpha: 0.42)
                              : editing
                              ? AppTheme.cloverGreen
                              : AppTheme.brand,
                          shape: BoxShape.circle,
                        ),
                        child: editing
                            ? const AppIcon(
                                HeroAppIcons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : vm.requiresPaidMessage
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const AppIcon(
                                    HeroAppIcons.solidStar,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'x${vm.paidMessageStarCount}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              )
                            : const AppIcon(
                                HeroAppIcons.solidPaperPlane,
                                size: 17,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (desktop && hasText)
            Positioned(
              key: const ValueKey('desktopComposerSendOverlay'),
              right: 2,
              bottom: 6,
              child: _desktopSendButton(),
            ),
        ],
      ),
    );
  }

  bool _usesNativeDesktopComposer(BuildContext context) {
    if (kIsWeb) return false;
    return switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  bool get _hasActiveTextComposition {
    final composing = _controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  void _insertComposerLineBreak() {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final text = value.text.replaceRange(start, end, '\n');
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  Widget _desktopSendButton() {
    final editing = vm.editingMessage != null;
    final disabled = _aiReplyWorkingTargetId != null;
    final shortcut = widget.enterToSend ? 'Enter' : 'Ctrl+Enter';
    final sendLabel =
        (editing ? AppStringKeys.messageActionEdit : AppStringKeys.composerSend)
            .l10n(context);
    final radius = BorderRadius.circular(AppRadius.md);
    return AppInteractiveSurface(
      key: const ValueKey('composerSendButton'),
      semanticLabel: '$sendLabel ($shortcut)',
      enabled: !disabled,
      onTap: disabled ? null : () => unawaited(_sendCurrentText()),
      onLongPress: disabled || editing
          ? null
          : () => unawaited(_showTextSendOptions()),
      borderRadius: radius,
      child: Container(
        key: const ValueKey('desktopComposerSendButton'),
        constraints: const BoxConstraints(minWidth: 112),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: disabled
              ? AppTheme.brand.withValues(alpha: 0.42)
              : editing
              ? AppTheme.cloverGreen
              : AppTheme.brand,
          borderRadius: radius,
        ),
        child: !editing && vm.requiresPaidMessage
            ? Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const AppIcon(
                    HeroAppIcons.solidStar,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'x${vm.paidMessageStarCount}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (editing) ...[
                    const AppIcon(
                      HeroAppIcons.check,
                      size: 15,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    sendLabel,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    shortcut,
                    key: const ValueKey('desktopComposerShortcutHint'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _autoDeleteInputIndicator() {
    final label = AppLocalizations.of(context).t(
      AppStringKeys.chatAutoDeleteCountdown,
      {'value1': TDParse.formatDuration(vm.messageAutoDeleteTime)},
    );
    return Semantics(
      key: const ValueKey('composerAutoDeleteIndicator'),
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showToast(context, label),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: AppIcon(
              HeroAppIcons.stopwatch,
              size: 18,
              color: context.colors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _aiReplyProgressDisclosure({required bool isWorking}) {
    final c = context.colors;
    final expanded = _aiReplyProgressExpanded;
    return AnimatedSize(
      key: const ValueKey('composerAiReplyProcess'),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      onEnd: () => widget.onPanelGeometryChanged?.call(),
      child: Container(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            AppTheme.brand.withValues(alpha: 0.06),
            c.searchFill,
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: AppTheme.brand.withValues(alpha: 0.18),
            width: 0.6,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: expanded,
              label: AppStringKeys.aiReplyProcessTitle.l10n(context),
              value: isWorking
                  ? AppStringKeys.topicChatLoading.l10n(context)
                  : null,
              child: GestureDetector(
                key: const ValueKey('composerAiReplyProcessToggle'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _aiReplyProgressExpanded = !_aiReplyProgressExpanded;
                  });
                  _notifyComposerGeometryChanged();
                },
                child: SizedBox(
                  height: 34,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        ExcludeSemantics(
                          child: AppIcon(
                            HeroAppIcons.wandMagicSparkles,
                            size: 14,
                            color: AppTheme.brand,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            AppStringKeys.aiReplyProcessTitle.l10n(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        if (isWorking) ...[
                          const SizedBox(width: 8),
                          ExcludeSemantics(
                            child: AppActivityIndicator(
                              size: 13,
                              color: AppTheme.brand,
                            ),
                          ),
                        ],
                        const SizedBox(width: 7),
                        ExcludeSemantics(
                          child: AppIcon(
                            expanded
                                ? HeroAppIcons.chevronUp
                                : HeroAppIcons.chevronDown,
                            size: 15,
                            color: c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (expanded) ...[
              Container(height: 0.6, color: c.divider.withValues(alpha: 0.55)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 132),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
                  child: Column(
                    key: const ValueKey('composerAiReplyProcessDetails'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (index, phase)
                          in _aiReplyProgressPhases.indexed) ...[
                        if (index > 0) const SizedBox(height: 7),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.only(top: 5, right: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.brand,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _aiReplyProgressLabel(phase),
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _aiReplyProgressLabel(AiReplyProgressPhase phase) => switch (phase) {
    AiReplyProgressPhase.readingRecentMessages =>
      AppStringKeys.aiReplyProcessReading.l10n(context),
    AiReplyProgressPhase.checkingEarlierContext =>
      AppStringKeys.aiReplyProcessChecking.l10n(context),
    AiReplyProgressPhase.writingReply =>
      AppStringKeys.aiReplyProcessWriting.l10n(context),
  };

  Future<void> _showAiReplyModelPicker(ChatMessage target) async {
    if (_aiReplyWorkingTargetId != null) return;
    final settings = context.read<AiSettingsController?>();
    if (settings?.initialized != true) {
      showToast(context, AppStringKeys.aiReplyUnavailable.l10n(context));
      return;
    }
    final candidate = await showAiFeatureModelPicker(
      context,
      settings: settings!,
      feature: AiFeature.reply,
    );
    if (!mounted || candidate == null) return;
    await _generateAiReply(target, requiredModelCandidateId: candidate.id);
  }

  Widget _aiReplyInputButton(ChatMessage target) {
    final working = _aiReplyWorkingTargetId == target.id;
    return Semantics(
      button: true,
      liveRegion: working,
      label: working
          ? AppStringKeys.confirmCancel.l10n(context)
          : AppStringKeys.aiReplyAction.l10n(context),
      value: working ? AppStringKeys.topicChatLoading.l10n(context) : null,
      child: GestureDetector(
        key: const ValueKey('composerAiReplyButton'),
        behavior: HitTestBehavior.opaque,
        onTap: working
            ? () => _invalidateAiReplyGeneration(clearProgress: true)
            : () => unawaited(_generateAiReply(target)),
        onLongPress: working
            ? null
            : () => unawaited(_showAiReplyModelPicker(target)),
        child: SizedBox(
          width: 32,
          height: 28,
          child: Center(
            child: working
                ? const ExcludeSemantics(
                    child: _AiReplyThinkingIndicator(
                      key: ValueKey('composerAiReplyProgress'),
                    ),
                  )
                : AppIcon(
                    HeroAppIcons.wandMagicSparkles,
                    size: 19,
                    color: AppTheme.brand,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _replyKeyboardMiniAppAction(
    _ReplyKeyboard keyboard,
    MessageButton button,
  ) {
    final colors = _replyKeyboardButtonColors(button, prominent: true);
    return Semantics(
      button: true,
      label: button.text,
      child: GestureDetector(
        key: const ValueKey('composerReplyKeyboardMiniAppAction'),
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_openReplyKeyboardWebApp(keyboard, button)),
        onLongPress: () => _showBotMenu(forceMenu: true),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 156),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: colors.border, width: 2),
            ),
            child: BotButtonLabel(
              button: button,
              color: colors.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  ({Color background, Color foreground, Color border})
  _replyKeyboardButtonColors(MessageButton button, {required bool prominent}) {
    final c = context.colors;
    return botButtonPalette(
      button.style,
      primary: AppTheme.brand,
      standard: prominent
          ? (
              background: AppTheme.brand,
              foreground: Colors.white,
              border: c.inputBarBackground.withValues(alpha: 0.72),
            )
          : (background: c.card, foreground: c.textPrimary, border: c.divider),
    );
  }

  Widget _replyKeyboardButtonCell(
    _ReplyKeyboard keyboard,
    MessageButton button,
  ) {
    final colors = _replyKeyboardButtonColors(button, prominent: false);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _pressReplyKeyboardButton(keyboard, button),
      child: Container(
        key: ValueKey('reply-keyboard-button-${button.text}'),
        height: 48,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colors.border, width: 0.5),
        ),
        child: BotButtonLabel(
          button: button,
          color: colors.foreground,
          fontSize: AppTextSize.body,
          fontWeight: FontWeight.w500,
          iconSize: 19,
        ),
      ),
    );
  }

  Widget _replyKeyboardPanel(_ReplyKeyboard keyboard) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(maxHeight: 330),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: c.panelBackground,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (final row in keyboard.rows) ...[
              Row(
                children: [
                  for (var index = 0; index < row.length; index++) ...[
                    Expanded(
                      child: _replyKeyboardButtonCell(keyboard, row[index]),
                    ),
                    if (index < row.length - 1) const SizedBox(width: 8),
                  ],
                ],
              ),
              if (!identical(row, keyboard.rows.last))
                const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  // MARK: - Icon strip

  Widget _desktopIconStrip({
    required AiSettingsController? aiSettings,
    required _ReplyKeyboard? replyKeyboard,
  }) {
    final c = context.colors;
    final sender = vm.selectedMessageSender;
    final webAppButton = _webAppButton(replyKeyboard);
    final canToggleReplyKeyboard =
        replyKeyboard != null &&
        (_replyKeyboardVisible ||
            (!_hasText && _pendingClipboardAttachments.isEmpty));
    final replyTarget = _currentAiReplyTarget();
    final aiReplyWorking = _aiReplyWorkingTargetId != null;
    final canUseAiReply =
        aiReplyWorking ||
        (!_hasText &&
            replyTarget != null &&
            _canOfferAiReply(replyTarget, aiSettings));
    final canUseAiEditor =
        !aiReplyWorking && vm.canUseAiComposition && _aiDraftEligible;
    return Container(
      key: const ValueKey('desktopComposerToolbar'),
      width: double.infinity,
      height: 41,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (vm.canChooseMessageSender && sender != null) ...[
                    _desktopSenderPicker(sender),
                    Container(
                      width: 0.5,
                      height: 20,
                      margin: const EdgeInsets.fromLTRB(3, 0, 6, 0),
                      color: c.divider,
                    ),
                  ],
                  CompositedTransformTarget(
                    link: _desktopEmojiPopoverLink,
                    child: OverlayPortal(
                      controller: _desktopEmojiPopoverController,
                      overlayChildBuilder: _desktopEmojiPopover,
                      child: _desktopIcon(
                        key: const ValueKey('desktopComposerEmojiAction'),
                        icon: HeroAppIcons.solidFaceSmile,
                        semanticLabel: AppStrings.t(
                          AppStringKeys.composerEmoji,
                        ),
                        active: _desktopEmojiPopoverVisible,
                        onTap: _toggleDesktopEmojiPopover,
                      ),
                    ),
                  ),
                  CompositedTransformTarget(
                    link: _desktopStickerPopoverLink,
                    child: OverlayPortal(
                      controller: _desktopStickerPopoverController,
                      overlayChildBuilder: _desktopStickerPopover,
                      child: _desktopIcon(
                        key: const ValueKey('desktopComposerStickerAction'),
                        icon: HeroAppIcons.grip,
                        semanticLabel: AppStrings.t(
                          AppStringKeys.composerStickers,
                        ),
                        active: _desktopStickerPopoverVisible,
                        onTap: _toggleDesktopStickerPopover,
                      ),
                    ),
                  ),
                  _desktopIcon(
                    key: const ValueKey('desktopComposerVoiceAction'),
                    icon: HeroAppIcons.microphone,
                    semanticLabel: AppStrings.t(
                      AppStringKeys.composerHoldToTalk,
                    ),
                    active: _panel == _Panel.voice,
                    onTap: _toggleVoice,
                  ),
                  _desktopIcon(
                    key: const ValueKey('desktopComposerImageAction'),
                    icon: HeroAppIcons.image,
                    semanticLabel: AppStrings.t(AppStringKeys.composerImage),
                    active: false,
                    onTap: _pickPhotos,
                  ),
                  _desktopIcon(
                    key: const ValueKey('desktopComposerScreenshotAction'),
                    icon: HeroAppIcons.crop,
                    semanticLabel: AppStringKeys.composerScreenshot.l10n(
                      context,
                    ),
                    active: false,
                    onTap: () => unawaited(_captureDesktopScreenshot()),
                  ),
                  _desktopIcon(
                    key: const ValueKey('desktopComposerFileAction'),
                    icon: HeroAppIcons.solidFolder,
                    semanticLabel: AppStrings.t(
                      AppStringKeys.topicPostContentFile,
                    ),
                    active: false,
                    onTap: _pickFile,
                  ),
                  _desktopIcon(
                    key: const ValueKey('desktopComposerAudioAction'),
                    icon: HeroAppIcons.music,
                    semanticLabel: AppStrings.t(AppStringKeys.composerAudio),
                    active: false,
                    onTap: _pickAudio,
                  ),
                  _desktopIcon(
                    key: const ValueKey('desktopComposerLocationAction'),
                    icon: HeroAppIcons.locationDot,
                    semanticLabel: AppStringKeys.composerLocation.l10n(context),
                    active: false,
                    onTap: _sendLocation,
                  ),
                  _desktopIcon(
                    key: const ValueKey('desktopComposerContactAction'),
                    icon: HeroAppIcons.idBadge,
                    semanticLabel: AppStringKeys.composerContact.l10n(context),
                    active: false,
                    onTap: _sendContact,
                  ),
                  if (!vm.isDirectMessagesGroup)
                    _desktopIcon(
                      key: const ValueKey('desktopComposerPollAction'),
                      icon: HeroAppIcons.grip,
                      semanticLabel: AppStringKeys.composerPoll.l10n(context),
                      active: false,
                      onTap: _createPoll,
                    ),
                  if (!vm.isDirectMessagesGroup)
                    _desktopIcon(
                      key: const ValueKey('desktopComposerChecklistAction'),
                      icon: HeroAppIcons.listCheck,
                      semanticLabel: AppStringKeys.composerChecklist.l10n(
                        context,
                      ),
                      active: false,
                      onTap: _createChecklist,
                    ),
                  if (vm.isDirectMessagesGroup &&
                      !vm.isAdministeredDirectMessagesGroup)
                    _desktopIcon(
                      key: const ValueKey('desktopComposerSuggestedPostAction'),
                      icon: HeroAppIcons.penToSquare,
                      semanticLabel: AppStringKeys.suggestedPostComposerTitle
                          .l10n(context),
                      active: false,
                      onTap: _createSuggestedPost,
                    ),
                  _desktopIcon(
                    key: const ValueKey('desktopComposerScheduledAction'),
                    icon: HeroAppIcons.clock,
                    semanticLabel: AppStrings.t(
                      AppStringKeys.messageSendOptionsScheduledMessages,
                    ),
                    active: false,
                    onTap: _openScheduledMessages,
                  ),
                  if (webAppButton != null && replyKeyboard != null)
                    _desktopIcon(
                      key: const ValueKey('desktopComposerMiniAppAction'),
                      icon: HeroAppIcons.bot,
                      semanticLabel: webAppButton.text,
                      active: false,
                      onTap: () => unawaited(
                        _openReplyKeyboardWebApp(replyKeyboard, webAppButton),
                      ),
                      onLongPress: () => _showBotMenu(forceMenu: true),
                    ),
                  if (replyKeyboard != null)
                    _desktopIcon(
                      key: const ValueKey('desktopComposerReplyKeyboardAction'),
                      icon: _replyKeyboardVisible
                          ? HeroAppIcons.chevronDown
                          : HeroAppIcons.tableCells,
                      semanticLabel: _replyKeyboardVisible
                          ? 'Hide bot keyboard'
                          : 'Show bot keyboard',
                      active: _replyKeyboardVisible,
                      enabled: canToggleReplyKeyboard,
                      onTap: _toggleReplyKeyboard,
                    ),
                  // A reply-keyboard Mini App takes the primary bot slot and
                  // keeps the full command menu available on long press.
                  if (webAppButton == null &&
                      (vm.peerIsBot ||
                          _guestQueries.isNotEmpty ||
                          (vm.botMenu?.isWebApp ?? false) ||
                          vm.botCommands.isNotEmpty))
                    _desktopIcon(
                      key: const ValueKey('desktopComposerBotMenuAction'),
                      icon: HeroAppIcons.bot,
                      semanticLabel: AppStrings.t(
                        AppStringKeys.chatInputBarOpenBotMenu,
                      ),
                      active: false,
                      onTap: _showBotMenu,
                    ),
                ],
              ),
            ),
          ),
          Container(
            width: 0.5,
            height: 20,
            margin: const EdgeInsets.fromLTRB(3, 0, 4, 0),
            color: c.divider,
          ),
          _desktopIcon(
            key: const ValueKey('desktopComposerRichTextAction'),
            icon: HeroAppIcons.font,
            semanticLabel: AppStringKeys.composerRichText.l10n(context),
            active: false,
            onTap: () => unawaited(_openRichTextComposer()),
          ),
          _desktopIcon(
            key: const ValueKey('desktopComposerAiReplyAction'),
            icon: aiReplyWorking
                ? HeroAppIcons.xmark
                : HeroAppIcons.wandMagicSparkles,
            semanticLabel: aiReplyWorking
                ? AppStringKeys.confirmCancel.l10n(context)
                : AppStringKeys.aiReplyAction.l10n(context),
            active: aiReplyWorking,
            enabled: canUseAiReply,
            onTap: aiReplyWorking
                ? () => _invalidateAiReplyGeneration(clearProgress: true)
                : replyTarget == null
                ? null
                : () => unawaited(_generateAiReply(replyTarget)),
            onLongPress: !aiReplyWorking && canUseAiReply && replyTarget != null
                ? () => unawaited(_showAiReplyModelPicker(replyTarget))
                : null,
          ),
          _desktopIcon(
            key: const ValueKey('desktopComposerAiEditorAction'),
            icon: HeroAppIcons.palette,
            semanticLabel: AppStringKeys.telegramAiEditorTelegramAIEditor.l10n(
              context,
            ),
            active: false,
            enabled: canUseAiEditor,
            onTap: canUseAiEditor
                ? () => unawaited(_openTelegramAiEditor())
                : null,
          ),
        ],
      ),
    );
  }

  Widget _desktopSenderPicker(MessageSenderOption sender) {
    final label =
        '${AppStringKeys.composerSend.l10n(context)}: ${sender.title}';
    final radius = BorderRadius.circular(AppRadius.md);
    return CompositedTransformTarget(
      link: _desktopSenderPopoverLink,
      child: OverlayPortal(
        controller: _desktopSenderPopoverController,
        overlayChildBuilder: _desktopSenderPopover,
        child: Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Tooltip(
            message: label,
            child: AppInteractiveSurface(
              key: const ValueKey('desktopComposerSenderPicker'),
              semanticLabel: label,
              selected: _desktopSenderPopoverVisible,
              onTap: _toggleDesktopSenderPopover,
              borderRadius: radius,
              child: SizedBox(
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PhotoAvatar(
                        title: sender.title,
                        photo: sender.photo,
                        size: 28,
                      ),
                      const SizedBox(width: 1),
                      AppIcon(
                        HeroAppIcons.chevronDown,
                        size: 13,
                        color: context.colors.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopIcon({
    required Key key,
    required AppIconData icon,
    required String semanticLabel,
    required bool active,
    bool enabled = true,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final radius = BorderRadius.circular(AppRadius.md);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Tooltip(
        message: semanticLabel,
        child: AppInteractiveSurface(
          key: key,
          semanticLabel: semanticLabel,
          selected: active,
          enabled: enabled,
          onTap: enabled ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          borderRadius: radius,
          child: SizedBox.square(
            dimension: 32,
            child: Center(
              child: AppIcon(
                icon,
                size: 18,
                color: !enabled
                    ? context.colors.textTertiary.withValues(alpha: 0.52)
                    : active
                    ? AppTheme.brand
                    : context.colors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconStrip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          _icon(
            HeroAppIcons.microphone,
            AppStrings.t(AppStringKeys.composerHoldToTalk),
            _panel == _Panel.voice,
            _toggleVoice,
          ),
          _icon(
            HeroAppIcons.image,
            AppStrings.t(AppStringKeys.composerImage),
            false,
            _pickPhotos,
          ),
          if (Platform.isAndroid || Platform.isIOS)
            _icon(
              HeroAppIcons.camera,
              AppStrings.t(AppStringKeys.composerCamera),
              false,
              _takePhoto,
            ),
          _icon(
            HeroAppIcons.grip,
            AppStrings.t(AppStringKeys.composerStickers),
            _panel == _Panel.sticker,
            () {
              _toggle(_Panel.sticker);
              if (_panel == _Panel.sticker) {
                StickerStore.shared.loadIfNeeded();
                GifStore.shared.loadIfNeeded();
                if (_isPanelSearchSelected &&
                    _panelSearch.text.trim().isNotEmpty) {
                  _queuePanelSearch();
                }
              }
            },
          ),
          _icon(
            HeroAppIcons.solidFaceSmile,
            AppStrings.t(AppStringKeys.composerEmoji),
            _panel == _Panel.emoji,
            () {
              _toggle(_Panel.emoji);
              if (_panel == _Panel.emoji) {
                EmojiStore.shared.loadIfNeeded();
                if (_isPanelSearchSelected &&
                    _panelSearch.text.trim().isNotEmpty) {
                  _queuePanelSearch();
                }
              }
            },
          ),
          _icon(
            _panel != _Panel.none
                ? HeroAppIcons.xmark
                : HeroAppIcons.circlePlus,
            AppStrings.t(
              _panel != _Panel.none
                  ? AppStringKeys.composerCloseMenu
                  : AppStringKeys.composerOpenMenu,
            ),
            _panel == _Panel.function,
            () => _toggle(_Panel.function),
          ),
        ],
      ),
    );
  }

  Widget _icon(
    AppIconData icon,
    String semanticLabel,
    bool active,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: AppInteractiveSurface(
        semanticLabel: semanticLabel,
        selected: active,
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          height: 40,
          child: Center(
            child: AppIcon(
              icon,
              size: 24,
              color: active ? AppTheme.brand : context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // MARK: - Media pickers

  Future<void> _captureDesktopScreenshot() async {
    if (!_usesNativeDesktopComposer(context) || vm.editingMessage != null) {
      return;
    }
    try {
      final capture =
          widget.desktopScreenshotCapture ??
          DesktopScreenshotService.captureInteractiveRegion;
      final path = await capture();
      if (!mounted || path == null || path.trim().isEmpty) return;
      _focus.unfocus();
      await _previewAndSendAttachments([
        OutgoingAttachment(
          path: path,
          kind: OutgoingAttachmentKind.photo,
          fileName: Uri.file(path).pathSegments.last,
        ),
      ]);
    } catch (error, stackTrace) {
      debugPrint('Failed to capture desktop screenshot: $error\n$stackTrace');
      if (mounted) {
        _pickFailed(AppStringKeys.composerScreenshot.l10n(context));
      }
    }
  }

  /// 图片: pick one or more photos/videos and preserve their album order.
  Future<void> _pickPhotos() async {
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        await _pickDesktopPhotos();
        return;
      }
      final sendMode = await showGallerySendModeSheet(context);
      if (!mounted || sendMode == null) return;
      final sendLivePhoto = sendMode == GallerySendMode.livePhoto;
      final maxDimension = switch (sendMode) {
        GallerySendMode.media => 1280,
        GallerySendMode.highDefinition => 2560,
        _ => null,
      };
      final selection = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.imageAndVideo,
        maxAssets: 10,
        preferLivePhotoVideo: sendLivePhoto,
        photoMaxDimension: maxDimension,
      );
      if (!mounted) return;
      if (selection.failedCount > 0) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.composerOpenAttachmentFailed, {
            'value1': AppStrings.t(AppStringKeys.composerImage),
          }),
        );
      }
      final attachments = selection.assets
          .map((asset) {
            final file = asset.file;
            final kind = galleryAttachmentKind(
              sendAsFile: false,
              isVideo: isPickedAssetVideo(file),
              isAnimation: isPickedAssetGif(file),
            );
            return OutgoingAttachment(
              path: file.path,
              kind: kind,
              fileName: asset.originalFile?.name ?? file.name,
              originalPath: asset.originalFile?.path,
              previewBytes: asset.thumbnailBytes,
              width: asset.width,
              height: asset.height,
            );
          })
          .toList(growable: false);
      if (attachments.isEmpty) return;
      await _previewAndSendAttachments(attachments);
    } catch (error, stackTrace) {
      debugPrint('Failed to send selected media: $error\n$stackTrace');
      _pickFailed(AppStrings.t(AppStringKeys.composerImage));
    }
  }

  Future<void> _pickDesktopPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'heif',
        'mp4',
        'mov',
        'mkv',
        'webm',
      ],
    );
    final files = result?.files
        .where((file) => file.path != null)
        .toList(growable: false);
    if (files == null || files.isEmpty || !mounted) return;
    if (files.length > 10) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.composerMediaSelectionLimit, {'value1': 10}),
      );
      return;
    }
    final selected = files
        .map((file) {
          final path = file.path!;
          final pickedFile = XFile(path, name: file.name);
          return OutgoingAttachment(
            path: path,
            kind: galleryAttachmentKind(
              sendAsFile: false,
              isVideo: isPickedAssetVideo(pickedFile),
              isAnimation: isPickedAssetGif(pickedFile),
            ),
            fileName: file.name,
          );
        })
        .toList(growable: false);
    final attachments = await resolveAttachmentListDimensions(selected);
    if (!mounted) return;
    await _previewAndSendAttachments(attachments);
  }

  /// 相机: capture a photo and send it.
  Future<void> _takePhoto() async {
    try {
      final shot = await ImagePicker().pickImage(source: ImageSource.camera);
      if (shot == null) return;
      final edited = await _editImage(shot.path);
      if (edited != null) {
        final attachment = await resolveAttachmentDimensions(
          OutgoingAttachment(
            path: edited.path,
            kind: OutgoingAttachmentKind.photo,
          ),
        );
        await widget.vm.sendAttachments([attachment], caption: edited.caption);
        widget.onMessageSent();
      }
    } catch (_) {
      _pickFailed(AppStrings.t(AppStringKeys.composerCamera));
    }
  }

  Future<void> _recordVideoNote() async {
    try {
      final capture = await Navigator.of(context).push<VideoNoteCaptureResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const VideoNoteRecorderView(),
        ),
      );
      if (!mounted || capture == null) return;
      final preview = await Navigator.of(context).push<VideoNotePreviewResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => VideoNotePreviewView(
            path: capture.path,
            allowWhenOnline: widget.vm.canSendWhenOnline,
            effects: widget.vm.availableMessageEffects,
          ),
        ),
      );
      if (!mounted) return;
      if (preview == null) {
        unawaited(_deleteTempFile(capture.path));
        return;
      }
      final sent = await widget.vm.sendVideoNote(
        preview.path,
        preview.duration,
        sendConfiguration: preview.sendConfiguration,
      );
      if (!mounted) return;
      if (sent) {
        widget.onMessageSent();
      } else {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    } catch (_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentActionFailed);
      }
    }
  }

  Future<ImageEditResult?> _editImage(
    String path, {
    String initialCaption = '',
  }) {
    return Navigator.of(context).push<ImageEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            ImageEditView(sourcePath: path, initialCaption: initialCaption),
      ),
    );
  }

  void _handleInsertedContent(KeyboardInsertedContent content) {
    unawaited(_sendInsertedImage(content));
  }

  Future<void> _sendInsertedImage(KeyboardInsertedContent content) async {
    if (!content.mimeType.toLowerCase().startsWith('image/')) return;
    var data = content.data;
    var mimeType = content.mimeType;
    if (data == null || data.isEmpty) {
      final image = await _readInsertedImage(content.uri, content.mimeType);
      data = image?.data;
      mimeType = image?.mimeType ?? mimeType;
    }
    if (data == null || data.isEmpty) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.composerPastedImageReadFailed),
        );
      }
      return;
    }
    await _queueClipboardImageData(
      DesktopClipboardImageData(data: data, mimeType: mimeType),
    );
  }

  Future<_ClipboardImage?> _readInsertedImage(
    String uri,
    String mimeType,
  ) async {
    if (uri.isEmpty) return null;
    if (_usesNativeDesktopComposer(context)) {
      final parsed = Uri.tryParse(uri);
      if (parsed?.isScheme('file') == true) {
        try {
          final data = await File.fromUri(parsed!).readAsBytes();
          if (data.isNotEmpty) return (data: data, mimeType: mimeType);
        } on FileSystemException {
          return null;
        }
      }
    }
    try {
      final image = await _clipboardChannel.invokeMapMethod<String, dynamic>(
        'readImageUri',
        <String, dynamic>{'uri': uri, 'mimeType': mimeType},
      );
      final data = image?['data'];
      if (data is! Uint8List || data.isEmpty) return null;
      return (
        data: data,
        mimeType: (image?['mimeType'] as String?) ?? mimeType,
      );
    } catch (_) {
      return null;
    }
  }

  Future<_ClipboardImage?> _readClipboardImage() async {
    try {
      final image = await _clipboardChannel.invokeMapMethod<String, dynamic>(
        'readImage',
      );
      final data = image?['data'];
      if (data is! Uint8List || data.isEmpty) return null;
      final mimeType = (image?['mimeType'] as String?) ?? 'image/png';
      return (data: data, mimeType: mimeType);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _queueDesktopClipboardImages() async {
    final remaining =
        _maximumPendingClipboardAttachments -
        _pendingClipboardAttachments.length;
    if (remaining <= 0) {
      _showClipboardAttachmentLimit();
      return true;
    }
    final reader =
        widget.desktopClipboardAttachmentReader ??
        DesktopClipboardImageService.readAttachments;
    DesktopClipboardImageReadResult result;
    try {
      result = await reader(remaining);
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to read desktop clipboard images: $error\n$stackTrace',
      );
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.composerPastedImageReadFailed),
        );
      }
      return false;
    }
    if (!mounted) return false;
    return _applyClipboardImageReadResult(result, remaining: remaining);
  }

  Future<bool> _queueClipboardImageData(DesktopClipboardImageData image) async {
    final remaining =
        _maximumPendingClipboardAttachments -
        _pendingClipboardAttachments.length;
    if (remaining <= 0) {
      if (mounted) _showClipboardAttachmentLimit();
      return true;
    }
    try {
      final result = await DesktopClipboardImageService.storeImages([
        image,
      ], limit: remaining);
      if (!mounted) return false;
      return _applyClipboardImageReadResult(result, remaining: remaining);
    } catch (error, stackTrace) {
      debugPrint('Failed to store pasted image: $error\n$stackTrace');
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.composerPastedImageReadFailed),
        );
      }
      return false;
    }
  }

  bool _applyClipboardImageReadResult(
    DesktopClipboardImageReadResult result, {
    required int remaining,
  }) {
    if (result.availableImageCount == 0) return false;
    if (result.failedImageCount > 0) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.composerPastedImageReadFailed),
      );
    }
    if (result.availableImageCount > remaining) {
      _showClipboardAttachmentLimit();
    }
    if (result.attachments.isNotEmpty) {
      _hideDesktopPopovers(rebuild: false);
      setState(() {
        _pendingClipboardAttachments.addAll(result.attachments);
        _panel = _Panel.none;
        _replyKeyboardVisible = false;
        _quickReplyContextVisible = false;
      });
      widget.onPanelGeometryChanged?.call();
    }
    _restoreKeyboardFocus();
    return true;
  }

  void _showClipboardAttachmentLimit() {
    showToast(
      context,
      AppStrings.t(AppStringKeys.composerMediaSelectionLimit, {
        'value1': _maximumPendingClipboardAttachments,
      }),
    );
  }

  Future<void> _previewAndSendAttachments(
    List<OutgoingAttachment> attachments,
  ) async {
    final MediaSendPreviewResult? preview;
    if (widget.mediaSendPreviewLauncher case final launcher?) {
      preview = await launcher(attachments);
    } else {
      final resolved = await resolveAttachmentListDimensions(attachments);
      if (!mounted) return;
      preview = await Navigator.of(context).push<MediaSendPreviewResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MediaSendPreviewView(
            attachments: resolved,
            allowWhenOnline: widget.vm.canSendWhenOnline,
            effects: widget.vm.availableMessageEffects,
          ),
        ),
      );
    }
    if (!mounted || preview == null || preview.attachments.isEmpty) return;
    final finalAttachments = await resolveAttachmentListDimensions(
      preview.attachments,
    );
    await widget.vm.sendAttachments(
      finalAttachments,
      caption: preview.caption,
      sendConfiguration: preview.sendConfiguration,
    );
    widget.onMessageSent();
  }

  Future<void> _sendRichTextResult(RichTextComposerResult result) async {
    final mode = await _richTextSendMode();
    if (mode == null) return;
    if (!mounted) return;
    try {
      var sentAny = false;
      if (mode == _RichTextSendMode.direct) {
        for (var index = 0; index < result.segments.length; index++) {
          final segment = result.segments[index];
          if (segment.isHtml) {
            final files = await Future.wait(
              segment.richFiles.map((file) async {
                final attachment = await resolveAttachmentDimensions(
                  file.attachment,
                );
                return RichMessageSendFile(id: file.id, attachment: attachment);
              }),
            );
            await widget.vm.sendRichMessageHtml(
              segment.html,
              files: files,
              blocks: segment.blocks,
            );
            sentAny = true;
          } else if (segment.attachments.isNotEmpty) {
            await widget.vm.sendAttachments(segment.attachments);
            sentAny = true;
          }
        }
      } else {
        sentAny = await _sendRichSegmentsViaRelay(result.segments);
      }
      if (!sentAny) return;
      widget.onMessageSent();
      _controller.clear();
      _focus.requestFocus();
    } catch (error, stackTrace) {
      debugPrint('Failed to send rich message: $error\n$stackTrace');
      if (mounted) {
        _setPanel(_Panel.none);
        final message = switch (error) {
          RichMessageRelayException(:final code)
              when code == 'bot_not_started' =>
            AppStringKeys.richTextRelayBotStartRequired.l10n(context),
          RichMessageRelayException(:final message)
              when message.trim().isNotEmpty =>
            message,
          TimeoutException() => AppStringKeys.composerRichTextSendFailed.l10n(
            context,
          ),
          TdError(:final message) when message.trim().isNotEmpty => message,
          _ =>
            error.toString().trim().isNotEmpty
                ? error.toString()
                : AppStringKeys.composerRichTextSendFailed.l10n(context),
        };
        showToast(context, message);
        await _reopenFailedRichTextComposer(result);
      }
    }
  }

  Future<void> _reopenFailedRichTextComposer(
    RichTextComposerResult failedResult,
  ) async {
    if (!mounted) return;
    final result = await showRichTextComposerSheet(
      context,
      initialText: failedResult.text,
      initialEntities: failedResult.entities,
      initialAttachments: failedResult.attachments,
      title: AppStringKeys.composerRichTextMessageTitle,
      submitText: AppStringKeys.composerSend,
    );
    if (result == null || !mounted) return;
    if (result.text.trim().isEmpty &&
        result.attachments.isEmpty &&
        result.segments.isEmpty) {
      return;
    }
    final canAttemptSend = await vm.prepareMessageSend();
    if (!mounted || !canAttemptSend) return;
    if (vm.requiresPaidMessage) {
      final ok = await _confirmPaidMessageSend();
      if (!mounted || !ok) return;
    }
    await _sendRichTextResult(result);
  }

  Future<bool> _sendRichSegmentsViaRelay(
    List<RichMessageSendSegment> segments,
  ) async {
    var token = await RichMessageRelayConfig.readToken();
    if (token == null) {
      if (!mounted || !await _configureRichMessageRelay()) return false;
      token = await RichMessageRelayConfig.readToken();
    }
    if (token == null) return false;
    final currentUserId = await widget.vm.currentUserId();
    final relay = RichMessageBotRelay();
    var sentAny = false;
    _showRelayProgress();
    try {
      for (final segment in segments) {
        if (segment.isHtml) {
          final files = await Future.wait(
            segment.richFiles.map((file) async {
              final relayAttachment = await _resolveRelayAttachment(
                file.attachment,
              );
              final attachment = await resolveAttachmentDimensions(
                relayAttachment,
              );
              return RichMessageSendFile(id: file.id, attachment: attachment);
            }),
          );
          await relay.sendAndCopy(
            token: token,
            html: segment.html,
            currentUserId: currentUserId,
            targetChatId: widget.vm.chatId,
            tdClient: TdClient.shared,
            files: files,
            blocks: segment.blocks,
            onProgress: _updateRelayProgress,
          );
          sentAny = true;
        } else {
          for (final attachment in segment.attachments) {
            await relay.sendAttachmentAndCopy(
              token: token,
              attachment: attachment,
              currentUserId: currentUserId,
              targetChatId: widget.vm.chatId,
              tdClient: TdClient.shared,
              onProgress: _updateRelayProgress,
            );
            sentAny = true;
          }
        }
      }
    } finally {
      relay.close();
      _hideRelayProgress();
    }
    return sentAny;
  }

  Future<OutgoingAttachment> _resolveRelayAttachment(
    OutgoingAttachment attachment,
  ) async {
    final path = attachment.path.trim();
    if (path.isNotEmpty && await File(path).exists()) return attachment;
    final fileId = attachment.fileId;
    if (fileId == null || fileId <= 0) {
      throw StateError('Unable to read rich message media');
    }
    final downloaded = await TdFileCenter.shared.uploadPath(fileId);
    if (downloaded == null ||
        downloaded.isEmpty ||
        !await File(downloaded).exists()) {
      throw StateError('Unable to download rich message media');
    }
    return attachment.copyWith(path: downloaded);
  }

  void _showRelayProgress() {
    if (_relayProgressEntry != null || !mounted) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _relayProgress = const RichMessageRelayProgress(
      stage: RichMessageRelayStage.compose,
      step: 1,
      totalSteps: 3,
    );
    final entry = OverlayEntry(
      builder: (_) => _RelaySendingOverlay(progress: _relayProgress!),
    );
    _relayProgressEntry = entry;
    overlay.insert(entry);
  }

  void _updateRelayProgress(RichMessageRelayProgress progress) {
    _relayProgress = progress;
    _relayProgressEntry?.markNeedsBuild();
  }

  void _hideRelayProgress() {
    final entry = _relayProgressEntry;
    _relayProgressEntry = null;
    _relayProgress = null;
    if (entry?.mounted ?? false) entry!.remove();
  }

  Future<_RichTextSendMode?> _richTextSendMode() async {
    try {
      if (await TdClient.shared.activeAccountUsesBotApi()) {
        return _RichTextSendMode.direct;
      }
      if (await widget.vm.currentUserIsPremium()) {
        return _RichTextSendMode.direct;
      }
      if (await RichMessageRelayConfig.isConfigured()) {
        return _RichTextSendMode.botRelay;
      }
      if (mounted && await _configureRichMessageRelay()) {
        return _RichTextSendMode.botRelay;
      }
    } catch (error) {
      if (mounted) {
        final message = switch (error) {
          TdError(:final message) when message.trim().isNotEmpty => message,
          _ => error.toString(),
        };
        showToast(context, message);
      }
    }
    return null;
  }

  Future<bool> _configureRichMessageRelay() async {
    final configure = await confirmDialog(
      context,
      title: AppStringKeys.richTextRelayBotSetupTitle.l10n(context),
      message: AppStringKeys.richTextRelayBotSetupDescription.l10n(context),
      confirmText: AppStringKeys.richTextRelayBotConfigure.l10n(context),
    );
    if (!mounted || !configure) return false;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const RichMessageRelayView()),
    );
    return mounted && await RichMessageRelayConfig.isConfigured();
  }

  /// 文件: pick an arbitrary document and send it.
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      final attachments = result?.files
          .map((file) => file.path)
          .whereType<String>()
          .take(10)
          .map(
            (path) => OutgoingAttachment(
              path: path,
              kind: OutgoingAttachmentKind.document,
            ),
          )
          .toList();
      if (attachments == null || attachments.isEmpty) return;
      await widget.vm.sendAttachments(attachments);
      widget.onMessageSent();
    } catch (_) {
      _pickFailed(AppStrings.t(AppStringKeys.topicPostContentFile));
    }
  }

  Future<void> _openDesktopComposerPicker(
    DesktopUtilityWindowKind kind,
    String title,
  ) async {
    final utilityWindows = DesktopUtilityWindowService.instance;
    final open = widget.desktopUtilityWindowLauncher ?? utilityWindows.open;
    final opened = await open(
      DesktopUtilityWindowArguments(
        kind: kind,
        accountSlot: TdClient.shared.activeSlot,
        accountUserId: vm.meId,
        chatId: vm.chatId,
        title: title,
        localeTag: Localizations.localeOf(context).toLanguageTag(),
        dark: Theme.of(context).brightness == Brightness.dark,
      ),
    );
    if (!opened && mounted) _pickFailed(title);
  }

  /// 位置: open a map picker centred on the GPS fix; send the chosen point.
  Future<void> _sendLocation() async {
    if (_usesNativeDesktopComposer(context)) {
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.locationPicker,
        AppStringKeys.composerLocation.l10n(context),
      );
      return;
    }
    final start = await resolveLocationPickerStart();
    if (!mounted) return;
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => LocationPickerView(initial: start)),
    );
    if (picked != null) {
      widget.vm.sendLocation(picked.latitude, picked.longitude);
      widget.onMessageSent();
    }
  }

  Future<void> _sendContact() async {
    if (_usesNativeDesktopComposer(context)) {
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.contactPicker,
        AppStringKeys.composerContact.l10n(context),
      );
      return;
    }
    final contact = await Navigator.of(context).push<MessageContactCard>(
      MaterialPageRoute(builder: (_) => const ContactSharePickerView()),
    );
    if (!mounted || contact == null) return;
    final sent = await widget.vm.sendContact(contact);
    if (!mounted) return;
    if (sent) {
      widget.onMessageSent();
    } else {
      showToast(context, AppStringKeys.topicPostContentActionFailed);
    }
  }

  /// 投票: collect a question + options and send a poll.
  Future<void> _createPoll() async {
    if (_usesNativeDesktopComposer(context)) {
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.pollComposer,
        AppStringKeys.pollComposerCreatePollTitle.l10n(context),
      );
      return;
    }
    final maxOptions = await widget.vm.pollAnswerCountMax();
    if (!mounted) return;
    final result = await Navigator.of(context).push<PollComposerResult>(
      MaterialPageRoute(
        builder: (_) => PollComposerView(maxOptions: maxOptions),
      ),
    );
    if (!mounted || result == null) return;
    final sent = await widget.vm.sendPoll(result);
    if (!mounted) return;
    if (sent) {
      widget.onMessageSent();
    } else {
      showToast(context, AppStringKeys.topicPostContentActionFailed);
    }
  }

  /// 音频: pick a local audio file and send it as a music message.
  Future<void> _pickLocalAudio() async {
    try {
      final preferred = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const [
          'mp3',
          'm4a',
          'aac',
          'flac',
          'wav',
          'ogg',
          'opus',
          'amr',
        ],
      );
      final result =
          preferred ?? await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result == null) return;
      final attachments = result.files
          .map((file) => file.path)
          .whereType<String>()
          .take(10)
          .map(
            (path) => OutgoingAttachment(
              path: path,
              kind: OutgoingAttachmentKind.audio,
            ),
          )
          .toList();
      if (attachments.isEmpty) return;
      await widget.vm.sendAttachments(attachments);
      widget.onMessageSent();
    } catch (_) {
      _pickFailed(AppStrings.t(AppStringKeys.composerAudio));
    }
  }

  /// 音频: search Telegram audio first; local files remain available inside.
  Future<void> _pickAudio() async {
    if (_usesNativeDesktopComposer(context)) {
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.audioPicker,
        AppStrings.t(AppStringKeys.composerAudio),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AudioSearchView(
          onSend: (sourceChatId, message) async {
            await widget.vm.sendAudioFromMessage(sourceChatId, message);
            widget.onMessageSent();
          },
          onPickLocal: _pickLocalAudio,
        ),
      ),
    );
  }

  /// 清单: collect a title + tasks and send a checklist (to-do list).
  Future<void> _createChecklist() async {
    if (_usesNativeDesktopComposer(context)) {
      await _openDesktopComposerPicker(
        DesktopUtilityWindowKind.checklistComposer,
        AppStringKeys.checklistComposerNewChecklistTitle.l10n(context),
      );
      return;
    }
    final result = await Navigator.of(context).push<ChecklistComposerResult>(
      MaterialPageRoute(builder: (_) => const ChecklistComposerView()),
    );
    if (result == null) return;
    if (result.title.isEmpty || result.tasks.isEmpty) return;
    widget.vm.sendChecklist(result);
    widget.onMessageSent();
  }

  Future<void> _createSuggestedPost() async {
    final loader = ChannelDirectMessageTopicController(
      chatId: vm.chatId,
      topicId: 0,
    );
    try {
      final limits = await loader.loadLimits();
      if (!mounted) return;
      final draft = await showAppModalSheet<SuggestedPostDraft>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SuggestedPostComposerSheet(limits: limits),
      );
      if (draft == null || !mounted) return;
      await vm.sendSuggestedPost(
        text: draft.text,
        attachment: draft.attachment,
        price: draft.price,
        sendDate: draft.sendDate,
      );
      widget.onMessageSent();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      loader.dispose();
    }
  }

  // MARK: - Function panel

  Widget _functionPanel() {
    final items = [
      if (widget.showCallAction)
        (
          HeroAppIcons.phone.data,
          AppStrings.t(
            vm.isGroup
                ? AppStringKeys.composerGroupVoiceCall
                : AppStringKeys.composerVoiceCall,
          ),
          () => widget.onStartCall(false),
        ),
      (
        HeroAppIcons.locationDot.data,
        AppStrings.t(AppStringKeys.composerLocation),
        _sendLocation,
      ),
      (
        HeroAppIcons.idBadge.data,
        AppStrings.t(AppStringKeys.composerContact),
        _sendContact,
      ),
      (
        HeroAppIcons.solidFolder.data,
        AppStrings.t(AppStringKeys.topicPostContentFile),
        _pickFile,
      ),
      if (!vm.isDirectMessagesGroup)
        (
          HeroAppIcons.grip.data,
          AppStrings.t(AppStringKeys.composerPoll),
          _createPoll,
        ),
      (
        HeroAppIcons.music.data,
        AppStrings.t(AppStringKeys.composerAudio),
        _pickAudio,
      ),
      (
        HeroAppIcons.penToSquare.data,
        AppStrings.t(AppStringKeys.composerRichText),
        _openRichTextComposer,
      ),
      if (!vm.isDirectMessagesGroup)
        (
          HeroAppIcons.listCheck.data,
          AppStrings.t(AppStringKeys.composerChecklist),
          _createChecklist,
        ),
      if (vm.isDirectMessagesGroup && !vm.isAdministeredDirectMessagesGroup)
        (
          HeroAppIcons.penToSquare.data,
          AppStrings.t(AppStringKeys.suggestedPostComposerTitle),
          _createSuggestedPost,
        ),
      (
        HeroAppIcons.clock.data,
        AppStrings.t(AppStringKeys.messageSendOptionsScheduledMessages),
        _openScheduledMessages,
      ),
    ];
    final c = context.colors;
    return Container(
      key: const ValueKey('composerFunctionPanel'),
      width: double.infinity,
      color: c.panelBackground,
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
      child: IconGrid(
        perRow: 5,
        children: [
          for (final item in items)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _setPanel(_Panel.none);
                item.$3();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(item.$1, size: 22, color: c.textPrimary),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.$2.l10n(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: c.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // MARK: - Emoji panel (standard catalog → inserts into the field)

  Widget _emojiPanel({double height = 326, bool popover = false}) {
    final c = context.colors;
    return Container(
      key: popover ? const ValueKey('desktopEmojiPopoverContent') : null,
      height: height,
      color: c.panelBackground,
      child: Column(
        children: [
          _emojiTabStrip(),
          if (_emojiTab == _emojiSearchTab) _panelSearchField(),
          Expanded(child: _emojiContent()),
        ],
      ),
    );
  }

  Widget _emojiContent() {
    if (_emojiTab == _emojiSearchTab) {
      if (_panelSearch.text.trim().isEmpty) return const SizedBox.shrink();
      return _emojiSearchContent();
    }
    final store = EmojiStore.shared;
    if (_emojiTab != 'standard') {
      final id = int.tryParse(_emojiTab);
      CustomEmojiPack? pack;
      for (final p in store.customPacks) {
        if (p.id == id) {
          pack = p;
          break;
        }
      }
      if (pack != null) {
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
          ),
          itemCount: pack.emoji.length,
          itemBuilder: (context, index) {
            final item = pack!.emoji[index];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  _controller.insertCustomEmoji(item.customEmojiId, item.emoji),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: item.customEmojiId != 0
                    ? CustomEmojiView(
                        id: item.customEmojiId,
                        size: 34,
                        color: context.colors.textPrimary,
                      )
                    : const SizedBox(),
              ),
            );
          },
        );
      }
    }
    return CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        for (final category in EmojiCatalog.categories) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 14, top: 6, bottom: 2),
              child: Text(
                category.name.l10n(context),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final emoji = category.emojis[index];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _controller.insertText(emoji),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 26)),
                  ),
                );
              }, childCount: category.emojis.length),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }

  Widget _panelSearchField() {
    final c = context.colors;
    return Container(
      key: const ValueKey('composerMediaSearch'),
      height: 42,
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          AppIcon(
            HeroAppIcons.magnifyingGlass,
            size: 17,
            color: c.textTertiary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: TextField(
              controller: _panelSearch,
              decoration: InputDecoration.collapsed(
                hintText: AppStringKeys.composerMediaSearch.l10n(context),
              ),
              style: TextStyle(fontSize: 14, color: c.textPrimary),
            ),
          ),
          if (_panelSearch.text.isNotEmpty)
            GestureDetector(
              key: const ValueKey('composerMediaSearchClear'),
              behavior: HitTestBehavior.opaque,
              onTap: _panelSearch.clear,
              child: SizedBox(
                width: 30,
                height: 30,
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.circleXmark,
                    size: 18,
                    color: c.textTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _emojiSearchContent() {
    final count = _emojiSearchResults.length + _customEmojiSearchResults.length;
    if (count == 0) return _panelSearchState();
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        if (index < _emojiSearchResults.length) {
          final emoji = _emojiSearchResults[index];
          return GestureDetector(
            key: ValueKey('emojiSearch-$emoji'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _controller.insertText(emoji),
            child: Center(
              child: Text(emoji, style: const TextStyle(fontSize: 26)),
            ),
          );
        }
        final item =
            _customEmojiSearchResults[index - _emojiSearchResults.length];
        return GestureDetector(
          key: ValueKey('customEmojiSearch-${item.customEmojiId}'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (item.customEmojiId != 0) {
              _controller.insertCustomEmoji(item.customEmojiId, item.emoji);
            } else if (item.emoji.isNotEmpty) {
              _controller.insertText(item.emoji);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: item.customEmojiId != 0
                ? CustomEmojiView(
                    id: item.customEmojiId,
                    size: 34,
                    color: context.colors.textPrimary,
                  )
                : StickerPreview(item: item),
          ),
        );
      },
    );
  }

  Widget _panelSearchState() => Center(
    child: _panelSearchLoading
        ? const AppActivityIndicator(size: 23)
        : Text(
            AppStringKeys.composerMediaSearchEmpty.l10n(context),
            style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
          ),
  );

  Widget _emojiTabStrip() {
    final c = context.colors;
    final packs = EmojiStore.shared.customPacks;
    return Container(
      key: const ValueKey('emojiPanelTabs'),
      decoration: BoxDecoration(
        color: c.inputBarBackground,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          children: [
            _emojiTabButton(
              key: const ValueKey('emojiSearchTab'),
              selected: _emojiTab == _emojiSearchTab,
              onTap: () => _selectEmojiTab(_emojiSearchTab),
              child: AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: 20,
                color: _emojiTab == _emojiSearchTab
                    ? AppTheme.brand
                    : c.textSecondary,
              ),
            ),
            _emojiTabButton(
              selected: _emojiTab == 'standard',
              onTap: () => _selectEmojiTab('standard'),
              child: AppIcon(
                HeroAppIcons.solidFaceSmile,
                size: 20,
                color: _emojiTab == 'standard'
                    ? AppTheme.brand
                    : c.textSecondary,
              ),
            ),
            for (final pack in packs)
              _emojiTabButton(
                selected: _emojiTab == pack.id.toString(),
                onTap: () => _selectEmojiTab(pack.id.toString()),
                child:
                    pack.emoji.isNotEmpty && pack.emoji.first.customEmojiId != 0
                    ? CustomEmojiView(
                        id: pack.emoji.first.customEmojiId,
                        size: 28,
                        color: c.textPrimary,
                      )
                    : (pack.cover != null
                          ? TDImage(photo: pack.cover, cornerRadius: 4)
                          : Text(
                              pack.title.isEmpty
                                  ? ''
                                  : pack.title.characters.first,
                              style: TextStyle(color: c.textPrimary),
                            )),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emojiTabButton({
    Key? key,
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: selected ? context.colors.searchFill : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: SizedBox(width: 28, height: 28, child: Center(child: child)),
      ),
    );
  }

  Widget _voicePanel() {
    final c = context.colors;
    final granted = _recorder != null;
    final label = !granted
        ? AppStrings.t(AppStringKeys.composerMicrophonePermissionRequired)
        : !_recording
        ? AppStrings.t(AppStringKeys.composerHoldToTalk)
        : _recordingLocked
        ? (_recordingPaused
              ? 'Recording paused'
              : 'Recording locked · pause or stop')
        : (_recordCancelled
              ? AppStrings.t(AppStringKeys.composerReleaseFingerToCancel)
              : 'Release to preview · slide up to lock · left to cancel');
    return Container(
      height: 318,
      width: double.infinity,
      color: c.panelBackground,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            height: 42,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: c.searchFill,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _voiceModeButton(
                    key: const ValueKey('voicePanelVoiceMessage'),
                    selected: true,
                    icon: HeroAppIcons.microphone,
                    label: AppStrings.t(
                      AppStringKeys.voiceNotePreviewVoiceMessage,
                    ),
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _voiceModeButton(
                    key: const ValueKey('voicePanelVideoMessage'),
                    selected: false,
                    icon: HeroAppIcons.solidFileVideo,
                    label: AppStrings.t(
                      AppStringKeys.videoNotePreviewVideoMessage,
                    ),
                    onTap: _recording
                        ? null
                        : () {
                            _setPanel(_Panel.none);
                            unawaited(_recordVideoNote());
                          },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: _recordCancelled ? AppTheme.tagRed : c.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          if (_recording) ...[
            SizedBox(
              width: 220,
              height: 28,
              child: ValueListenableBuilder<_RecTick>(
                valueListenable: _recTick,
                builder: (context, tick, _) => Row(
                  children: [
                    for (final level in tick.levels)
                      Expanded(
                        child: Align(
                          child: Container(
                            width: 2,
                            height:
                                (4 + ((level.clamp(-60.0, 0.0) + 60) / 60) * 24)
                                    .toDouble(),
                            decoration: BoxDecoration(
                              color: _recordingPaused
                                  ? c.textTertiary
                                  : AppTheme.brand,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Opacity(
            opacity: _recording ? 1 : 0.3,
            child: ValueListenableBuilder<_RecTick>(
              valueListenable: _recTick,
              builder: (context, tick, _) => Text(
                _recTime(tick.elapsed),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Listener(
            onPointerDown: (e) {
              _pressStartX = e.position.dx;
              _pressStartY = e.position.dy;
              // Check the recorder live (not the build-time `granted`) so a press
              // right after the panel opens still records; otherwise prime it.
              if (_recorder != null) {
                _startRec();
              } else {
                _prepareRecorder();
              }
            },
            onPointerMove: (e) {
              if (!_recording || _recordingLocked) return;
              final cancel = e.position.dx - _pressStartX < -70;
              final lock = e.position.dy - _pressStartY < -70;
              if (lock) {
                setState(() {
                  _recordingLocked = true;
                  _recordCancelled = false;
                });
                return;
              }
              if (cancel != _recordCancelled) {
                setState(() => _recordCancelled = cancel);
              }
            },
            onPointerUp: (_) {
              if (_recorder != null) {
                if (!_recordingLocked) unawaited(_stopRec());
              } else {
                _prepareRecorder();
              }
            },
            child: AnimatedScale(
              scale: _recording ? 1.12 : 1,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _recordCancelled ? AppTheme.tagRed : AppTheme.brand,
                  shape: BoxShape.circle,
                ),
                child: const AppIcon(
                  HeroAppIcons.microphone,
                  size: 32,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          if (_recordingLocked) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _voiceRecordingAction(
                  icon: HeroAppIcons.trash,
                  color: AppTheme.tagRed,
                  onTap: _cancelLockedRecording,
                ),
                const SizedBox(width: 22),
                _voiceRecordingAction(
                  icon: _recordingPaused
                      ? HeroAppIcons.play
                      : HeroAppIcons.pause,
                  color: AppTheme.brand,
                  onTap: () => unawaited(_toggleRecPause()),
                ),
                const SizedBox(width: 22),
                _voiceRecordingAction(
                  icon: HeroAppIcons.square,
                  color: AppTheme.brand,
                  onTap: () => unawaited(_stopRec()),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _voiceModeButton({
    required Key key,
    required bool selected,
    required AppIconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        height: 36,
        decoration: BoxDecoration(
          color: selected ? c.card : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.control),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              icon,
              size: 17,
              color: selected ? AppTheme.brand : c.textSecondary,
            ),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? c.textPrimary : c.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voiceRecordingAction({
    required AppIconData icon,
    required Color color,
    required VoidCallback onTap,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: AppIcon(icon, size: 20, color: color),
    ),
  );

  Widget _stickerPanel({double height = 326, bool popover = false}) {
    final c = context.colors;
    return Container(
      key: popover ? const ValueKey('desktopStickerPopoverContent') : null,
      height: height,
      color: c.panelBackground,
      child: Column(
        children: [
          _stickerTabStrip(),
          if (_stickerPack == _stickerSearchTabId) _panelSearchField(),
          Expanded(child: _stickerContent()),
        ],
      ),
    );
  }

  Widget _stickerContent() {
    final store = StickerStore.shared;
    final packs = store.packs;
    final activeId =
        _stickerPack ??
        (packs.isNotEmpty ? packs.first.id : StickerStore.recentPackId);
    if (activeId == _stickerSearchTabId) return _stickerSearchContent();
    if (activeId == _gifTabId) return _gifContent();
    if (packs.isEmpty) {
      return Center(
        child: Text(
          store.loading
              ? AppStrings.t(AppStringKeys.composerLoadingEmoji)
              : AppStrings.t(AppStringKeys.composerNoEmoji),
          style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
        ),
      );
    }
    StickerPack? pack;
    for (final p in packs) {
      if (p.id == activeId) {
        pack = p;
        break;
      }
    }
    pack ??= packs.first;
    if (!pack.loaded && pack.stickers.isEmpty) {
      store.loadPack(pack.id);
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
        ),
      );
    }
    final stickers = pack.stickers;
    // Lazy builder so only on-screen stickers spin up an animation/decoder.
    return _stickerGrid(stickers);
  }

  Widget _stickerGrid(List<StickerItem> stickers, {bool search = false}) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, i) => _stickerTile(stickers[i], search: search),
    );
  }

  Future<void> _sendStickerItem(StickerItem item) async {
    widget.onMediaSendTapped?.call();
    final sent = await widget.vm.sendSticker(item);
    if (!mounted) return;
    if (sent) {
      _finishPanelSend();
    } else {
      showToast(
        context,
        AppStrings.t(AppStringKeys.stickerSetDetailActionFailed),
      );
    }
  }

  Widget _gifContent() {
    final store = GifStore.shared;
    final items = store.items;
    if (items.isEmpty) {
      return Center(
        child: Text(
          store.loading
              ? AppStrings.t(AppStringKeys.composerLoadingGifs)
              : AppStrings.t(AppStringKeys.composerNoGifs),
          style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.2,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: items.length,
      itemBuilder: (_, index) => _gifTile(items[index]),
    );
  }

  Widget _stickerSearchContent() {
    if (_panelSearch.text.trim().isEmpty) return const SizedBox.shrink();
    if (_stickerSearchResults.isEmpty && _gifSearchResults.isEmpty) {
      return _panelSearchState();
    }
    return CustomScrollView(
      slivers: [
        if (_stickerSearchResults.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _stickerTile(_stickerSearchResults[index], search: true),
                childCount: _stickerSearchResults.length,
              ),
            ),
          ),
        if (_gifSearchResults.isNotEmpty || _gifSearchNextOffset.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.all(8),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 1.2,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == _gifSearchResults.length) {
                    return _gifSearchLoadMoreTile();
                  }
                  return _gifTile(_gifSearchResults[index], search: true);
                },
                childCount:
                    _gifSearchResults.length +
                    (_gifSearchNextOffset.isNotEmpty ? 1 : 0),
              ),
            ),
          ),
      ],
    );
  }

  Widget _stickerTile(StickerItem item, {bool search = false}) =>
      GestureDetector(
        key: ValueKey(
          search ? 'stickerSearch-${item.id}' : 'sticker-${item.id}',
        ),
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_sendStickerItem(item)),
        child: StickerPreview(item: item),
      );

  Widget _gifTile(GifItem item, {bool search = false}) => GestureDetector(
    key: ValueKey(search ? 'gifSearch-${item.id}' : 'gif-${item.id}'),
    behavior: HitTestBehavior.opaque,
    onTap: () => unawaited(_sendGifItem(item)),
    child: widget.gifPreviewBuilder?.call(item) ?? GifPreview(item: item),
  );

  Widget _gifSearchLoadMoreTile() => Semantics(
    button: true,
    label: AppStrings.t(AppStringKeys.chatInputBarLoadMoreGIFResults),
    child: GestureDetector(
      key: const ValueKey('gifSearchLoadMore'),
      behavior: HitTestBehavior.opaque,
      onTap: _gifSearchLoadingMore
          ? null
          : () => unawaited(_loadMoreGifSearch()),
      child: Center(
        child: _gifSearchLoadingMore
            ? const AppActivityIndicator(size: 22)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppIcon(
                    HeroAppIcons.chevronDown,
                    size: 22,
                    color: context.colors.textSecondary,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.t(AppStringKeys.momentsMore),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
      ),
    ),
  );

  Future<void> _sendGifItem(GifItem item) async {
    widget.onMediaSendTapped?.call();
    final sent = await widget.vm.sendGif(item);
    if (!mounted) return;
    if (sent) {
      _finishPanelSend();
    } else {
      showToast(context, AppStrings.t(AppStringKeys.composerGifSendFailed));
    }
  }

  Widget _stickerTabStrip() {
    final c = context.colors;
    final packs = StickerStore.shared.packs;
    final activeId =
        _stickerPack ??
        (packs.isNotEmpty ? packs.first.id : StickerStore.recentPackId);
    final installed = packs.where((p) => p.id != StickerStore.recentPackId);
    return Container(
      key: const ValueKey('stickerPanelTabs'),
      decoration: BoxDecoration(
        color: c.inputBarBackground,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          children: [
            _emojiTabButton(
              key: const ValueKey('stickerSearchTab'),
              selected: activeId == _stickerSearchTabId,
              onTap: () => _selectStickerTab(_stickerSearchTabId),
              child: AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: 20,
                color: activeId == _stickerSearchTabId
                    ? AppTheme.brand
                    : c.textSecondary,
              ),
            ),
            _emojiTabButton(
              selected: activeId == StickerStore.recentPackId,
              onTap: () => _selectStickerTab(StickerStore.recentPackId),
              child: AppIcon(
                HeroAppIcons.clock,
                size: 20,
                color: activeId == StickerStore.recentPackId
                    ? AppTheme.brand
                    : c.textSecondary,
              ),
            ),
            _emojiTabButton(
              selected: activeId == _gifTabId,
              onTap: () => _selectStickerTab(_gifTabId),
              child: AppIcon(
                HeroAppIcons.gif,
                size: 22,
                color: activeId == _gifTabId ? AppTheme.brand : c.textSecondary,
              ),
            ),
            for (final pack in installed)
              _emojiTabButton(
                selected: pack.id == activeId,
                onTap: () => _selectStickerTab(pack.id),
                child: pack.cover != null
                    ? StickerTabPreview(item: pack.cover!)
                    : Text(
                        pack.title.isEmpty ? '' : pack.title.characters.first,
                        style: TextStyle(color: c.textPrimary),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  // Kept for re-exposing the studio from a more appropriate surface later.
  // ignore: unused_element
  Future<void> _openStickerStudio() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const StickerSetStudioView()),
    );
    StickerStore.shared.reset();
    EmojiStore.shared.reset();
    StickerStore.shared.loadIfNeeded();
    EmojiStore.shared.loadIfNeeded();
  }
}

class _AiReplyThinkingIndicator extends StatefulWidget {
  const _AiReplyThinkingIndicator({super.key});

  @override
  State<_AiReplyThinkingIndicator> createState() =>
      _AiReplyThinkingIndicatorState();
}

class _AiReplyThinkingIndicatorState extends State<_AiReplyThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    builder: (context, _) {
      final pulse = (math.sin(_animation.value * math.pi * 2) + 1) / 2;
      return Transform.scale(
        scale: 0.96 + pulse * 0.05,
        child: SizedBox(
          width: 24,
          height: 24,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.brand.withValues(alpha: 0.10 + pulse * 0.06),
              border: Border.all(
                color: AppTheme.brand.withValues(alpha: 0.24),
                width: 0.75,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AppIcon(
                  HeroAppIcons.wandMagicSparkles,
                  size: 14,
                  color: AppTheme.brand,
                ),
                Positioned.fill(
                  child: Transform.rotate(
                    key: const ValueKey('composerAiReplyOrbit'),
                    angle: _animation.value * math.pi * 2,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.only(top: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.brand,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.brand.withValues(alpha: 0.36),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _RelaySendingOverlay extends StatefulWidget {
  const _RelaySendingOverlay({required this.progress});

  final RichMessageRelayProgress progress;

  @override
  State<_RelaySendingOverlay> createState() => _RelaySendingOverlayState();
}

class _RelaySendingOverlayState extends State<_RelaySendingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = widget.progress;
    final percent = (progress.fraction * 100).round().clamp(0, 100);
    final label = switch (progress.stage) {
      RichMessageRelayStage.upload => AppStrings.t(
        AppStringKeys.richTextRelayProgressUpload,
        {'value1': progress.mediaIndex, 'value2': progress.mediaCount},
      ),
      RichMessageRelayStage.compose =>
        AppStringKeys.richTextRelayProgressCompose.l10n(context),
      RichMessageRelayStage.waitForMessage =>
        AppStringKeys.richTextRelayProgressWait.l10n(context),
      RichMessageRelayStage.forward =>
        AppStringKeys.richTextRelayProgressForward.l10n(context),
    };
    return Positioned.fill(
      child: AbsorbPointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.24),
          child: Center(
            child: Container(
              width: 210,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.divider, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (_, _) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var index = 0; index < 3; index++) ...[
                          if (index > 0) const SizedBox(width: 7),
                          _relayProgressDot(index),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 9),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: c.divider),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress.fraction,
                            child: ColoredBox(color: AppTheme.brand),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${progress.step}/${progress.totalSteps} · $percent%',
                    style: TextStyle(
                      fontSize: 12,
                      color: c.textSecondary,
                      decoration: TextDecoration.none,
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

  Widget _relayProgressDot(int index) {
    final phase = (_animation.value - index * 0.16) * math.pi * 2;
    final strength = (math.sin(phase) + 1) / 2;
    return Transform.scale(
      scale: 0.78 + strength * 0.28,
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: AppTheme.brand.withValues(alpha: 0.35 + strength * 0.65),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _LongMessageRichTextPrompt extends StatelessWidget {
  const _LongMessageRichTextPrompt({
    required this.onCancel,
    required this.onConfirm,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: SafeArea(
        minimum: const EdgeInsets.all(24),
        child: Container(
          width: math.min(360, MediaQuery.sizeOf(context).width - 48),
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: c.divider, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                AppStringKeys.composerLongMessageTitle.l10n(context),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                AppStringKeys.composerLongMessageRichTextPrompt.l10n(context),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: c.textSecondary,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _LongMessagePromptAction(
                      label: AppStringKeys.countryPickerCancel.l10n(context),
                      onTap: onCancel,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LongMessagePromptAction(
                      label: AppStringKeys.composerSendAsRichText.l10n(context),
                      onTap: onConfirm,
                      primary: true,
                    ),
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

class _LongMessagePromptAction extends StatelessWidget {
  const _LongMessagePromptAction({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? AppTheme.brand : c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: primary ? Colors.white : c.textPrimary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

enum _ComposerFormatAction {
  quote('textEntityTypeBlockQuote'),
  spoiler('textEntityTypeSpoiler'),
  bold('textEntityTypeBold'),
  italic('textEntityTypeItalic'),
  monospace('textEntityTypeCode'),
  link(''),
  strikethrough('textEntityTypeStrikethrough'),
  underline('textEntityTypeUnderline'),
  codeBlock('textEntityTypePre');

  const _ComposerFormatAction(this.entityType);

  final String entityType;

  String get labelKey => switch (this) {
    quote => AppStringKeys.messageActionQuote,
    spoiler => AppStringKeys.richTextComposerFormatSpoiler,
    bold => AppStringKeys.richTextComposerFormatBold,
    italic => AppStringKeys.richTextComposerFormatItalic,
    monospace => AppStringKeys.composerFormatMonospace,
    link => AppStringKeys.composerFormatLink,
    strikethrough => AppStringKeys.richTextComposerFormatStrikethrough,
    underline => AppStringKeys.richTextComposerFormatUnderline,
    codeBlock => AppStringKeys.composerFormatCodeBlock,
  };
}

class _ComposerFormatMenu extends StatelessWidget {
  const _ComposerFormatMenu({required this.anchor});

  static const _width = 232.0;
  static const _rowHeight = 44.0;
  static const _padding = 8.0;

  final Offset anchor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = MediaQuery.of(context);
    final screen = media.size;
    final menuHeight =
        _ComposerFormatAction.values.length * _rowHeight + _padding * 2;
    final safeTop = media.padding.top + 8;
    final safeBottom = screen.height - media.viewInsets.bottom - 8;
    final left = (anchor.dx - _width / 2)
        .clamp(12.0, math.max(12.0, screen.width - _width - 12))
        .toDouble();
    final below = anchor.dy + 10;
    final top = below + menuHeight <= safeBottom
        ? below
        : math.max(safeTop, anchor.dy - menuHeight - 10);
    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: _width,
          child: TextFieldTapRegion(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: _padding),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: c.divider, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in _ComposerFormatAction.values)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(action),
                      child: SizedBox(
                        height: _rowHeight,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              action.labelKey.l10n(context),
                              style: TextStyle(
                                fontSize: 16,
                                color: c.textPrimary,
                                decoration: TextDecoration.none,
                              ),
                            ),
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
}

class _ComposerLinkDialog extends StatefulWidget {
  const _ComposerLinkDialog();

  @override
  State<_ComposerLinkDialog> createState() => _ComposerLinkDialogState();
}

class _ComposerLinkDialogState extends State<_ComposerLinkDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Container(
        width: math.min(360, MediaQuery.sizeOf(context).width - 40),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStringKeys.composerFormatLink.l10n(context),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: _submit,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: AppStringKeys.composerFormatLinkPlaceholder.l10n(
                    context,
                  ),
                  hintStyle: TextStyle(color: c.textTertiary),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _dialogAction(
                  context,
                  AppStringKeys.countryPickerCancel,
                  () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                _dialogAction(
                  context,
                  AppStringKeys.composerFormatApply,
                  () => _submit(_controller.text),
                  primary: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogAction(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool primary = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          label.l10n(context),
          style: TextStyle(
            fontSize: 15,
            fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
            color: primary ? AppTheme.brand : context.colors.textSecondary,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  void _submit(String value) {
    final url = value.trim();
    if (url.isEmpty) return;
    Navigator.of(context).pop(url);
  }
}
