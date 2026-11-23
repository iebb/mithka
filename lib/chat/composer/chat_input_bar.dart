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
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:logger/logger.dart' show Level;
import 'package:mithka/components/app_text_selection_toolbar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart' as desktop_record;

import '../../app/desktop_utility_window.dart';
import '../../app/diagnostic_breadcrumbs.dart';
import '../../components/app_dialog.dart';
import '../../components/app_icons.dart';
import '../../components/app_interactive_surface.dart';
import '../../components/confirm_dialog.dart';
import '../../components/icon_grid.dart';
import '../../components/photo_avatar.dart';
import '../../components/toast.dart';
import '../../components/ui_components.dart';
import '../../media/app_asset_picker.dart';
import '../../media/camera_capture.dart';
import '../../media/media_metadata.dart';
import '../../platform/adaptive_platform.dart';
import '../../platform/desktop_clipboard_images.dart';
import '../../platform/desktop_screenshot.dart';
import '../../platform/keyboard_image_paste.dart';
import '../../platform/keyboard_modifiers.dart';
import '../../platform/ohos_support.dart';
import '../../settings/ai_settings_controller.dart';
import '../../settings/ai_settings_view.dart';
import '../../settings/apple_pcc_api.dart';
import '../../settings/business_service.dart';
import '../../settings/desktop_hotkey_controller.dart';
import '../../settings/rich_message_relay_config.dart';
import '../../settings/rich_message_relay_view.dart';
import '../../tdlib/json_helpers.dart';
import '../../tdlib/td_client.dart';
import '../../tdlib/td_image_loader.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/content_size.dart';
import '../../theme/theme_controller.dart';
import '../admin/channel_direct_messages_service.dart';
import '../admin/channel_direct_messages_view.dart';
import '../ai_translation/ai_reply_service.dart';
import '../ai_translation/telegram_ai_editor_view.dart';
import '../ai_translation/telegram_ai_service.dart';
import '../chat_view_model.dart';
import '../composer_reply_options_sheet.dart';
import '../favorite_sticker_store.dart';
import '../forward_handoff.dart';
import '../links_search/link_handler.dart';
import '../media/audio_search_view.dart';
import '../media/image_edit_view.dart';
import '../media/media_download_service.dart';
import '../media/media_library_saver.dart';
import '../media_tile_action_sheet.dart';
import '../messages/bot_button_presentation.dart';
import '../messages/forward_options.dart' show isForwardProtectedError;
import '../mini_apps/bot_platform_service.dart';
import '../mini_apps/telegram_mini_app_view.dart';
import '../stickers/custom_emoji.dart';
import '../stickers/emoji_catalog.dart';
import '../stickers/emoji_panel.dart';
import '../stickers/emoji_panel_layout.dart';
import '../stickers/emoji_recents_store.dart';
import '../stickers/emoji_store.dart';
import '../stickers/emoji_text_controller.dart';
import '../stickers/gif_item.dart';
import '../stickers/gif_preview.dart';
import '../stickers/gif_store.dart';
import '../stickers/sticker_export_service.dart';
import '../stickers/sticker_item.dart';
import '../stickers/sticker_preview.dart';
import '../stickers/sticker_set_detail_view.dart';
import '../stickers/sticker_store.dart';
import 'checklist_composer_view.dart';
import 'contact_share_picker_view.dart';
import 'desktop_composer_height.dart';
import 'desktop_voice_message_controller.dart';
import 'desktop_voice_waveform.dart';
import 'location_picker_view.dart';
import 'media_send_preview_view.dart';
import 'message_send_options.dart';
import 'outgoing_attachment.dart';
import 'poll_composer_view.dart';
import 'rich_message_bot_relay.dart';
import 'rich_message_source.dart';
import 'rich_text_composer_view.dart';
import 'scheduled_messages_view.dart';
import 'video_note_preview_view.dart';
import 'video_note_recorder_view.dart';
import 'voice_draft_card.dart';
import 'voice_note_trimmer.dart';
import 'voice_recording_clock.dart';
import 'voice_recording_session.dart';

part 'chat_input_bar_overlays_dialogs.dart';
part 'chat_input_bar_voice.dart';
part 'chat_input_bar_bots_mentions.dart';
part 'chat_input_bar_ai_send.dart';
part 'chat_input_bar_attachments_pickers.dart';
part 'chat_input_bar_panels_rows.dart';

enum _Panel { none, function, emoji, sticker, voice }

/// A desktop microphone the system refused to hand to this app.
///
/// Not a recorder exception: `record` reports it as `hasPermission() == false`,
/// and on macOS the system prompt never appears again once it was refused.
class DesktopMicrophoneRefused implements Exception {
  const DesktopMicrophoneRefused();

  @override
  String toString() => 'desktop microphone refused';
}

/// A preparation failure whose cause was already reported to the user.
///
/// Opening the voice panel prepares the recorder in the background, and every
/// press waits on that same preparation. Without this marker the open's single
/// prompt would be repeated verbatim on each press until the panel is reopened.
class _ReportedCaptureFailure implements Exception {
  const _ReportedCaptureFailure(this.cause);

  final Object cause;

  @override
  String toString() => 'reported capture failure: $cause';
}

/// The kind of media the unified composer panel is showing. Both
/// `_Panel.emoji` and `_Panel.sticker` render the same unified media panel;
/// this picks which segment (and secondary strip) is active.
enum _MediaKind { emoji, sticker, gif }

/// A failure the mobile voice panel shows in its own status line instead of a
/// toast, which would land over the record button and vanish.
enum _VoiceInlineError { none, failed, microphoneRequired, microphoneSettings }

/// One segment of the composer's shared segmented switcher. A null [onTap]
/// draws the segment disabled.
typedef _ComposerSegment = ({
  Key key,
  AppIconData icon,
  String label,
  bool selected,
  VoidCallback? onTap,
});

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
  // Suggestions belong to the caret, not merely to an @ token somewhere
  // before it. In particular, do not keep an old query active while the caret
  // is in the middle of a token or immediately before punctuation.
  if (cursor < text.length && text[cursor].trim().isNotEmpty) return null;
  final beforeCursor = text.substring(0, cursor);
  final match = RegExp(
    r'(^|\s)@([\p{L}\p{M}\p{N}_]*)$',
    unicode: true,
  ).firstMatch(beforeCursor);
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
  bool altPressed = false,
  bool metaPressed = false,
}) {
  if (shiftPressed || controlPressed || altPressed || metaPressed) return false;
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
      altPressed: keyboard.isAltPressed,
      metaPressed: keyboard.isMetaPressed,
    )) {
      return newValue;
    }
    onSend();
    return oldValue;
  }
}

/// The view-model state the composer draws itself. See
/// [_ChatInputBarState._renderedVmState].
typedef _ComposerVmState = ({
  int autoDeleteTime,
  Object? selectedSender,
  bool canChooseSender,
  bool peerIsBot,
  int? replyToId,
  int? replyToChatId,
  int? replyQuoteRevision,
});

/// Incoming chat updates are frequent while a user is typing. Rebuilding the
/// editable field for each one can make Flutter tear down and recreate the
/// platform input connection, which presents as a blinking keyboard (and is
/// especially visible with third-party IMEs). While focused, only rebuild for
/// state that actually affects the composer; when unfocused, keep the previous
/// revision-driven refresh behavior.
@visibleForTesting
bool shouldRebuildComposerForVmUpdate({
  required bool revisionChanged,
  required bool localChanged,
  required bool hasFocus,
}) => localChanged || (revisionChanged && !hasFocus);

/// Whether the attachment strip offers the camera entry beside the image one.
///
/// The camera entry (which opens the in-app camera, and whose capture is sent
/// as a photo) is rendered on Android, iOS and HarmonyOS (which captures
/// through the system camera); a desktop or web composer shows the screenshot
/// entry instead. Exposed as a pure predicate so a widget test can pin the
/// strip order on any host without overriding the target platform.
bool composerShowsCameraIcon([TargetPlatform? platform, bool? onOhos]) {
  if (platform == null && (onOhos ?? isOhos)) return true;
  final target = platform ?? defaultTargetPlatform;
  return target == TargetPlatform.android || target == TargetPlatform.iOS;
}

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.vm,
    required this.onStartCall,
    required this.onMessageSent,
    this.onPanelGeometryChanged,
    this.onInputHeightChanged,
    this.onMediaSendTapped,
    this.gifPreviewBuilder,
    this.requestInitialFocus = false,
    this.enterToSend = false,
    this.quickRepliesEnabled = true,
    this.showCallAction = true,
    this.simpleMode = false,
    this.initialMediaKind,
    this.onMediaKindChanged,
    this.onBotTopicCreated,
    this.onReplyOptionsRequested,
    this.onForwardOptionsRequested,
    this.onReplySourceJump,
    this.quickReplyLoader,
    this.quickReplySender,
    this.onVoicePanelOpenedForTesting,
    this.desktopVoiceRecorderFactory,
    this.mobileVoiceRecorderFactory,
    this.microphonePermissionForTesting,
    this.voiceRecordingSession,
    this.openAppSettingsForTesting,
    this.onRecordingIssueForTesting,
    this.desktopScreenshotCapture,
    this.desktopClipboardAttachmentReader,
    this.desktopUtilityWindowLauncher,
    this.mediaSendPreviewLauncher,
    this.aiReplyGenerator,
    this.aiReplyStreamingGenerator,
    this.aiReplyHistoryLoader,
    this.desktopComposerHeightLoader,
    this.desktopComposerHeightSaver,
    this.botPlatformForTesting,
    this.phoneStripForTesting = false,
  });
  final ChatViewModel vm;
  final FutureOr<void> Function(bool isVideo) onStartCall;
  final VoidCallback onMessageSent;
  final VoidCallback? onPanelGeometryChanged;

  /// The text field's own height changed as text wrapped or was removed.
  final VoidCallback? onInputHeightChanged;
  final VoidCallback? onMediaSendTapped;
  @visibleForTesting
  final Widget Function(GifItem item)? gifPreviewBuilder;
  final bool requestInitialFocus;
  final bool enterToSend;
  final bool quickRepliesEnabled;
  final bool showCallAction;

  /// Simple mode (简洁模式): the phone composer collapses to one row (Mic ·
  /// field · Emoji · More, plus Send while there is something to send) and
  /// the strip's other tools move into the More panel. The native desktop
  /// composer ignores it.
  final bool simpleMode;

  /// The media panel segment ('emoji'/'sticker'/'gif') the panel should open
  /// on; chat_view restores the last-used segment from preferences. Null (and
  /// any unrecognized value) means emoji.
  final String? initialMediaKind;

  /// Reports every segment switch so the caller can persist the last-used
  /// segment. Fires only on real changes, never on restore.
  final ValueChanged<String>? onMediaKindChanged;
  final ValueChanged<int>? onBotTopicCreated;

  /// Tapping the reply banner's body asks the host to present the reply
  /// options sheet (quote selection, reply in another chat). Null leaves the
  /// banner body inert; hosts that cannot present options keep tap-to-nothing.
  final VoidCallback? onReplyOptionsRequested;

  /// Tapping the pending-forward banner's body asks the host to present the
  /// forward options sheet (hide sender, remove caption, render markdown).
  final VoidCallback? onForwardOptionsRequested;

  /// Long-pressing the reply banner jumps to the original message.
  final ValueChanged<ChatMessage>? onReplySourceJump;
  @visibleForTesting
  final Future<List<BusinessQuickReplyShortcut>> Function()? quickReplyLoader;
  @visibleForTesting
  final Future<void> Function(int chatId, int shortcutId)? quickReplySender;
  @visibleForTesting
  final VoidCallback? onVoicePanelOpenedForTesting;
  @visibleForTesting
  final desktop_record.AudioRecorder Function()? desktopVoiceRecorderFactory;
  @visibleForTesting
  final FlutterSoundRecorder Function()? mobileVoiceRecorderFactory;
  @visibleForTesting
  final Future<PermissionStatus> Function()? microphonePermissionForTesting;

  /// Owns the shared audio session while the mobile recorder captures.
  ///
  /// Defaults to [SharedVoiceRecordingAudioSession]; a test passes a recorder
  /// that throws the way an occupied native session does.
  @visibleForTesting
  final VoiceRecordingAudioSession? voiceRecordingSession;

  /// Opens the platform's app-settings page for the microphone prompt.
  ///
  /// Defaults to `openAppSettings`; injectable so a widget test can assert the
  /// prompt routed there without a live platform channel.
  @visibleForTesting
  final Future<bool> Function()? openAppSettingsForTesting;

  /// Observes each user-facing recording problem, with the stage it came from.
  ///
  /// A toast is inserted into the root overlay, so counting renders cannot tell
  /// one report from two; this seam pins that each tap reports exactly once.
  @visibleForTesting
  final void Function(String stage, Object? error)? onRecordingIssueForTesting;
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
  @visibleForTesting
  final BotPlatformService? botPlatformForTesting;

  /// Renders the phone attachment strip (which includes the camera entry)
  /// even when the widget test runs on a desktop host. Defaults to the
  /// [defaultTargetPlatform] behaviour.
  @visibleForTesting
  final bool phoneStripForTesting;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar>
    with WidgetsBindingObserver {
  void _updateState(VoidCallback fn) => setState(fn);

  static const _clipboardChannel = MethodChannel('mithka/clipboard');

  static const _maximumPendingClipboardAttachments = 10;

  static const _gifTabId = -2;

  static const _stickerSearchTabId = -3;

  /// Strip pseudo-id for the favorites section (not a real pack id).

  static const _favoritesTabId = -4;

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

  /// Simple mode's More panel. It never keeps an offset, so the panel always

  /// opens scrolled to the top.

  final _simpleMorePanelScroll = ScrollController(keepScrollOffset: false);

  final List<OutgoingAttachment> _pendingClipboardAttachments = [];

  final _desktopActionOwner = Object();
  DesktopHotkeyRegistration? _desktopScreenshotHotkeyRegistration;

  final _desktopSenderPopoverLink = LayerLink();

  final _desktopSendOptionsLink = LayerLink();

  final _desktopSendOptionsTargetKey = GlobalKey();

  // Single anchor for the unified emoji/sticker/GIF media popover.

  final _desktopMediaPopoverLink = LayerLink();

  final _desktopSenderPopoverController = OverlayPortalController();

  final _desktopMediaPopoverController = OverlayPortalController();
  MessageSendOptionsContextMenuHandle? _desktopSendOptionsMenu;

  bool _desktopSenderPopoverVisible = false;

  bool _desktopMediaPopoverVisible = false;

  bool _wasEditingMessage = false;
  int? _syncedEditingMessageId;

  int _syncedComposerRevision = -1;

  int _syncedComposerFocusTick = 0;

  int _syncedComposerDismissTick = 0;

  _Panel _panel = _Panel.none;

  /// Reply banner hint alternation (reference client parity): until the user

  /// has opened the reply-options panel once, the banner's preview line

  /// periodically swaps with a "tap for reply options" hint so the tap

  /// affordance is discoverable.
  bool? _replyHintSeen;
  Timer? _replyHintTimer;

  bool _replyHintShowing = false;

  int _replyHintTick = 0;

  _MediaKind _mediaKind = _MediaKind.emoji;

  String _emojiTab = 'standard'; // 'standard' or a custom-emoji pack id
  int? _stickerPack; // active sticker pack id

  /// The sticker panel's own vertical scroller: favorites, the recents

  /// pseudo-pack and every installed pack stack in one continuous list, with

  /// the pack strip above anchoring into it.

  final _stickerPanelScroll = ScrollController();

  /// The emoji panel's own vertical scroller: the standard catalog categories

  /// and the custom-emoji packs stack in one continuous list.

  final _emojiPanelScroll = ScrollController();

  /// Guards the sticker strip's scroll-following tab highlight against

  /// re-entrancy: a tab tap animates the panel scroll to that pack, and the

  /// resulting ScrollEnd must not be re-read as the user scrolling.

  bool _stickerPanelAnimatingToPack = false;

  /// The sticker pack header the panel scroll currently anchors to, kept as

  /// a stable pack id so rebuilds (store loads, search toggles) never lose

  /// the selection.

  int _stickerAnchorPackId = StickerStore.recentPackId;

  /// Guards the emoji strip's scroll-following highlight the same way a tab

  /// tap animates the panel scroll to a category.

  bool _emojiPanelAnimatingToSection = false;

  /// The offset the active panel scroller sat at when search replaced it,

  /// restored on cancel so leaving search never loses the user's place.
  double? _panelScrollRestoreOffset;

  /// Sticker pack loads this panel session already started, keyed by pack id

  /// and cleared when the load settles, so a rebuild storm over an unloaded

  /// section cannot re-issue the same getStickerSet query.

  final Map<int, Future<void>> _stickerPackLoads = {};
  Timer? _panelSearchTimer;

  int _panelSearchGeneration = 0;

  bool _panelSearchLoading = false;

  List<String> _emojiSearchResults = const [];

  List<StickerItem> _customEmojiSearchResults = const [];

  List<StickerItem> _stickerSearchResults = const [];

  List<GifItem> _gifSearchResults = const [];

  String _gifSearchNextOffset = '';

  bool _gifSearchLoadingMore = false;

  // Mobile uses flutter_sound/Opus; all native desktops use record/AAC.
  FlutterSoundRecorder? _recorder;

  /// The category this composer's capture put on the shared audio session.

  ///

  /// Non-null only while a capture owns it, so releasing is idempotent even

  /// when a stop, a cancel and dispose all run for one recording.
  VoiceRecordingAudioSession? _captureSession;

  /// The cause of the last preparation that could not get the microphone.

  ///

  /// The panel opening prepares once and every press waits on that same

  /// preparation, so without this a single failure would report itself again on

  /// each press. Opening the panel again clears it and retries.
  Object? _recorderPreparationFailure;
  desktop_record.AudioRecorder? _desktopRecorder;
  Future<void>? _recorderPreparation;
  Future<void>? _desktopRecorderPreparation;
  Future<void>? _voiceStart;
  Future<void>? _voiceStop;

  bool _voiceDisposed = false;

  bool _voiceUsesDesktopRecorder = false;

  bool _startingRecording = false;

  bool _stoppingRecording = false;

  bool _sendingVoice = false;

  bool _changingRecordingPause = false;

  bool _mobilePointerHeld = false;
  int? _voicePointerId;

  // A press on the big button while a locked recording runs: its release

  // stops the recording and leaves it as a draft above the field.
  int? _lockedStopPointerId;

  Offset _lockedStopDownPosition = Offset.zero;

  _VoiceInlineError _voiceInlineError = _VoiceInlineError.none;
  VoiceNoteDraft? _desktopVoiceDraft;

  /// The phone's finished recording, waiting above the field to be sent with

  /// the field's text as its caption, or deleted.
  ComposerVoiceDraft? _voiceDraft;
  StreamSubscription<desktop_record.Amplitude>? _desktopRecProgress;

  final _desktopVoiceFocus = FocusNode(debugLabel: 'desktopVoiceMessage');

  bool _desktopSpaceHeld = false;

  bool _desktopPointerHeld = false;

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

  /// Assigned in [initState], never lazily: a `late` initializer would first

  /// run inside the very [_syncFromVm] call it exists to compare against, and

  /// so record the new value as the old one.
  late _ComposerVmState _syncedVmState;

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
  late final BotPlatformService _botPlatform;
  StreamSubscription<Map<String, dynamic>>? _botPlatformUpdates;

  final List<BotGuestQuery> _guestQueries = [];
  Timer? _inlineBotTimer;

  int _inlineBotGeneration = 0;

  bool _inlineBotLoading = false;

  bool _inlineBotLoadingMore = false;
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

  bool get _canSendVoiceNotes => vm.canSendMessages && vm.canSendVoiceNotes;

  /// The one surface colour every panel docked to the composer bar paints, so

  /// a panel reads as a continuation of the bar instead of a recessed block.

  /// The bar itself paints `AppColors.inputBarBackground`; the darker

  /// `AppColors.panelBackground` is for surfaces that sit on an opaque pane

  /// (settings lists, desk panes), not for anything attached to the composer.

  Color get _composerDockedSurfaceColor => context.colors.inputBarBackground;

  @override
  void initState() {
    super.initState();
    // The panel reopens on the last-used segment; anything unknown (including
    // null) keeps the emoji default set on the field above.
    switch (widget.initialMediaKind) {
      case 'sticker':
        _mediaKind = _MediaKind.sticker;
      case 'gif':
        _mediaKind = _MediaKind.gif;
      case 'emoji' || null:
        _mediaKind = _MediaKind.emoji;
    }
    WidgetsBinding.instance.addObserver(this);
    _syncedVmState = _renderedVmState;
    _botPlatform =
        widget.botPlatformForTesting ??
        // The composer belongs to one transcript, and every inline query it
        // sends is scoped to that chat's account: a foreground switch while a
        // result page or an inline send is in flight must not retarget the
        // request at the replacement account's chat id.
        BotPlatformService(queryForSlot: vm.accountSlot);
    DesktopChatComposerActions._register(
      _desktopActionOwner,
      captureScreenshot: _captureDesktopScreenshot,
      hasFocus: () => _focus.hasFocus,
      isVisible: _isDesktopComposerVisible,
    );
    KeyboardImagePaste.register(
      _desktopActionOwner,
      hasFocus: () => _focus.hasFocus,
      onImage: _queueKeyboardPastedImage,
    );
    _desktopScreenshotHotkeyRegistration = DesktopHotkeyRegistry.instance
        .register(
          DesktopHotkeyAction.screenshot,
          _captureDesktopScreenshot,
          isEnabled: () =>
              _isDesktopComposerVisible() &&
              vm.canSendMessages &&
              vm.editingMessage == null,
        );
    _wasEditingMessage = vm.editingMessage != null;
    _syncedEditingMessageId = vm.editingMessage?.id;
    _syncedComposerFocusTick = vm.composerFocusTick;
    _syncedComposerDismissTick = vm.composerDismissTick;
    _controller.setFormattedText(
      vm.composerFormattedDraft,
      vm.composerDraftEntities,
    );
    _controller.addListener(_onTextChanged);
    _panelSearch.addListener(_queuePanelSearch);
    _replyHintTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      // Stop alternating once the flag loads as seen; otherwise flip only
      // while a reply banner is actually showing.
      if (_replyHintSeen != false || vm.replyTo == null) return;
      if (!mounted) return;
      setState(() {
        _replyHintShowing = !_replyHintShowing;
        _replyHintTick++;
      });
    });
    composerReplyOptionsHintSeen().then((seen) {
      if (!mounted) return;
      setState(() => _replyHintSeen = seen);
    });
    _focus.addListener(() {
      var needsRebuild = false;
      var panelChanged = false;
      if (_focus.hasFocus && _panel != _Panel.none) {
        if (_panel == _Panel.voice) _cancelVoiceRecording();
        _panel = _Panel.none;
        needsRebuild = true;
        panelChanged = true;
      }
      if (!_focus.hasFocus) {
        _mentionSearchTimer?.cancel();
        _mentionSearchGeneration++;
        if (_mentionQuery != null || _mentionCandidates.isNotEmpty) {
          _mentionQuery = null;
          _mentionCandidates = const [];
          needsRebuild = true;
        }
      }
      if (needsRebuild && mounted) {
        setState(() {});
        if (panelChanged) widget.onPanelGeometryChanged?.call();
      }
      if (_focus.hasFocus) _updateMentionSuggestions();
    });
    vm.addListener(_syncFromVm);
    EmojiStore.shared.addListener(_onStore);
    EmojiRecentsStore.shared.addListener(_onStore);
    StickerStore.shared.addListener(_onStore);
    GifStore.shared.addListener(_onStore);
    FavoriteStickerStore.shared.addListener(_onStore);
    _botPlatformUpdates = TdClient.shared
        .updatesOf('updateNewGuestQuery')
        .listen(_handleBotPlatformUpdate);
    if (widget.quickReplyLoader == null) {
      BusinessQuickReplyService.shared.addListener(_syncQuickReplyCache);
      _adoptQuickReplyCache(rebuild: false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestInitialFocusIfReady();
      if (mounted &&
          !_controller.startsWithIdBackedMention &&
          BotInlineInvocation.fromText(_controller.text) != null) {
        _focus.requestFocus();
        _queueInlineBotResults();
      }
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

  /// The touch field grows and shrinks with its text. Report it once the

  /// frame is laid out so the transcript can follow the resized viewport;

  /// the desktop editor's height only changes by drag, reported above.

  void _onInputFieldResized({required bool desktop}) {
    if (desktop || widget.onInputHeightChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onInputHeightChanged?.call();
    });
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
      _inlineBotLoadingMore = false;
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

  bool get _mentionSuggestionsVisible {
    if (!_focus.hasFocus || _mentionCandidates.isEmpty) return false;
    final expected = _mentionQuery;
    final active = activeMentionQuery(_controller.text, _controller.selection);
    return expected != null &&
        active != null &&
        active.start == expected.start &&
        active.end == expected.end &&
        active.query == expected.query;
  }

  /// The view-model state the composer draws itself.

  ///

  /// [shouldRebuildComposerForVmUpdate] stops rebuilding on bare revision

  /// bumps while the field has focus, so anything rendered from the view model

  /// has to be compared here or it silently stops updating mid-typing — which

  /// is how the auto-delete indicator got stuck on screen after the chat's

  /// timer was turned off. Add to this record when the composer starts drawing

  /// another view-model value.

  _ComposerVmState get _renderedVmState => (
    autoDeleteTime: vm.messageAutoDeleteTime,
    selectedSender: vm.selectedMessageSender,
    canChooseSender: vm.canChooseMessageSender,
    peerIsBot: vm.peerIsBot,
    replyToId: vm.replyTo?.id,
    replyToChatId: vm.replyToChatId,
    replyQuoteRevision: vm.replyQuote?.position,
  );

  /// Raises the caret for a reply target picked on the transcript. Skipped

  /// where nothing can be sent: a keyboard over a composer that cannot speak

  /// only hides the conversation.

  void _focusComposerForTranscriptReply() {
    final owner = vm;
    if (!mounted || !owner.canSendMessages) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(vm, owner) && owner.canSendMessages) {
        _focus.requestFocus();
      }
    });
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
      _syncedComposerFocusTick = widget.vm.composerFocusTick;
      _syncedComposerDismissTick = widget.vm.composerDismissTick;
      _cancelVoiceRecording();
      _discardDesktopVoiceDraft();
      _discardVoiceDraft(rebuild: false);
      if (_panel == _Panel.voice) _panel = _Panel.none;
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
    WidgetsBinding.instance.removeObserver(this);
    _replyHintTimer?.cancel();
    _voiceDisposed = true;
    _recordCancelled = true;
    _clearVoicePresses();
    _desktopComposerHeightLoadGeneration++;
    _desktopScreenshotHotkeyRegistration?.dispose();
    DesktopChatComposerActions._unregister(_desktopActionOwner);
    KeyboardImagePaste.unregister(_desktopActionOwner);
    // OverlayPortal tears its overlay down with this element. Calling hide()
    // while the portal is already being unmounted asserts because it no
    // longer has a z-order slot, so only clear our logical state here.
    _desktopSenderPopoverVisible = false;
    _desktopMediaPopoverVisible = false;
    _desktopSendOptionsMenu?.dismiss();
    _desktopSendOptionsMenu = null;
    _discardPendingClipboardAttachments();
    _discardVoiceDraft(rebuild: false);
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
    EmojiRecentsStore.shared.removeListener(_onStore);
    StickerStore.shared.removeListener(_onStore);
    GifStore.shared.removeListener(_onStore);
    FavoriteStickerStore.shared.removeListener(_onStore);
    if (widget.quickReplyLoader == null) {
      BusinessQuickReplyService.shared.removeListener(_syncQuickReplyCache);
    }
    _controller.dispose();
    _stickerPanelScroll.dispose();
    _emojiPanelScroll.dispose();
    _panelSearch
      ..removeListener(_queuePanelSearch)
      ..dispose();
    _simpleMorePanelScroll.dispose();
    _focus.dispose();
    _recTimer?.cancel();
    _recProgress?.cancel();
    _desktopRecProgress?.cancel();
    _recTick.dispose();
    _desktopVoiceFocus.dispose();
    _mentionSearchTimer?.cancel();
    _panelSearchTimer?.cancel();
    _inlineBotTimer?.cancel();
    _botPlatformUpdates?.cancel();
    _hideRelayProgress();
    unawaited(_disposeVoiceRecorders());
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

  /// True when the unified emoji/sticker/GIF panel is open, either inline or

  /// as the desktop media popover.

  bool get _mediaPanelOpen =>
      _panel == _Panel.emoji ||
      _panel == _Panel.sticker ||
      _desktopMediaPopoverVisible;

  /// The GIF segment's secondary strip is a search bar plus the saved-GIFs

  /// tab, mirroring the emoji and sticker search tabs.

  bool get _gifSearchSelected => _stickerPack == _stickerSearchTabId;

  bool get _isPanelSearchSelected {
    if (!_mediaPanelOpen) return false;
    return switch (_mediaKind) {
      _MediaKind.emoji => _emojiTab == _emojiSearchTab,
      _MediaKind.sticker => _stickerPack == _stickerSearchTabId,
      _MediaKind.gif => _gifSearchSelected,
    };
  }

  /// The sticker tab the panel anchors to: an explicit pick while it still

  /// names a tab in the loaded list, otherwise the first installed set, and

  /// recents when no set is installed at all.

  int get _activeStickerTab {
    final selected = _stickerPack;
    if (selected == _stickerSearchTabId) return _stickerSearchTabId;
    if (selected != null) {
      for (final pack in StickerStore.shared.packs) {
        if (pack.id == selected) return selected;
      }
    }
    return StickerStore.shared.defaultPackId;
  }

  /// Finds a pack by id in the loaded list, or null.

  StickerPack? _findStickerPack(int id) {
    for (final pack in StickerStore.shared.packs) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  /// Selecting a sticker tab scrolls the panel's continuous pack list to that

  /// pack (the strip and the list stay in sync in both directions).

  /// Toggles the media panel from the composer's media button.

  ///

  /// Opening keeps the last-used segment (emoji until the user picks

  /// another); tapping again closes the panel. Switching segments inside an

  /// open panel goes through [_selectMediaKind] instead. Each kind renders

  /// its own content area, so a persisted non-emoji segment needs no scroll

  /// restoration: the panel simply builds that kind's panel first.

  // MARK: - Voice recording

  /// Claims the capture audio session for this composer.

  ///

  /// Failures propagate: a session that cannot be claimed is exactly the state

  /// that used to end in an unexplained "could not record" toast, so the caller

  /// reports it instead of opening a recorder that captures nothing. The mobile

  /// recorder and this session share one platform decision, so a composer

  /// already using the desktop recorder never touches the session.

  /// Hands the shared session back to playback, once per capture.

  bool get _voicePressHeld => _voiceUsesDesktopRecorder
      ? _desktopSpaceHeld || _desktopPointerHeld
      : _mobilePointerHeld;

  bool get _canStartHeldRecording =>
      mounted &&
      !_voiceDisposed &&
      _panel == _Panel.voice &&
      _canSendVoiceNotes &&
      !_recordCancelled &&
      _voicePressHeld;

  bool get _showsMobileVoicePanel =>
      _panel == _Panel.voice && !_voiceUsesDesktopRecorder;

  /// Shows [error] in the mobile panel's status line until the next press on

  /// the record button, a panel switch, or the composer closing.

  /// Re-shows the inline row for a failure that was already reported while the

  /// panel opened, after a press cleared the row. `PermissionStatus` names map

  /// to their settings/required variants; anything else is the generic failure.

  /// Whether a voice draft or pasted pictures wait above the field. Only one

  /// attachment kind waits at a time.

  bool get _composerAttachmentWaiting =>
      _voiceDraft != null || _pendingClipboardAttachments.isNotEmpty;

  /// Deletes the waiting phone recording: playback stops, its file goes and

  /// the card collapses. The caption text stays.

  /// Sends the waiting recording as one voice message with the field's text

  /// as its caption: the length and paid-message checks, the trim export,

  /// then [ChatViewModel.sendVoice]. A failure keeps the recording for a

  /// retry and says so under the card.

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_voiceDraft?.pause());
    }
    // Returning from the system settings page is the other way to retry a
    // microphone the last attempt could not get.
    if (state == AppLifecycleState.resumed) {
      _recorderPreparationFailure = null;
    }
    // A held gesture can lose its release when the app loses focus. A locked
    // mobile recording is intentional and must not be discarded by a system
    // permission sheet, notification, or brief app switch.
    if (_recordingLocked && state != AppLifecycleState.detached) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached ||
        (state == AppLifecycleState.inactive && _recording)) {
      _cancelVoiceRecording();
    }
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
    if (desktopComposer) {
      // Hidden tabs and covered routes must release their native screenshot key.
      TickerMode.valuesOf(context);
      ModalRoute.isCurrentOf(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _desktopScreenshotHotkeyRegistration?.refresh();
      });
    }
    final editingMessage = vm.editingMessage;
    final replyKeyboard = _activeReplyKeyboard();
    final replyKeyboardPanelVisible =
        editingMessage == null &&
        replyKeyboard != null &&
        _replyKeyboardVisible &&
        !_hasText &&
        _pendingClipboardAttachments.isEmpty &&
        _voiceDraft == null;
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    final mediaPanelVisible =
        _panel == _Panel.emoji || _panel == _Panel.sticker;
    final simpleComposer = !desktopComposer && widget.simpleMode;
    final panelSurfaceVisible =
        editingMessage == null &&
        !mediaPanelVisible &&
        (_panel != _Panel.none || replyKeyboardPanelVisible);
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
                else if (vm.pendingForward != null)
                  _forwardBanner(vm.pendingForward!)
                else if (vm.replyTo != null)
                  _replyBanner(vm.replyTo!),
                if (editingMessage == null)
                  if (_inlineBotResults != null)
                    _inlineBotResultMenu()
                  else if (_botCommandCandidates.isNotEmpty)
                    _botCommandMenu()
                  else if (_mentionSuggestionsVisible)
                    _mentionMenu()
                  else if (_quickReplyContextVisible &&
                      _quickReplies.isNotEmpty)
                    _quickReplyContextMenu(),
                if (editingMessage == null &&
                    _pendingClipboardAttachments.isNotEmpty)
                  _clipboardAttachmentStrip(desktop: desktopComposer),
                if (!desktopComposer)
                  _voiceDraftSlot(visible: editingMessage == null),
                if (desktopComposer) ...[
                  if (editingMessage == null)
                    _desktopIconStrip(
                      aiSettings: aiSettings,
                      replyKeyboard: replyKeyboard,
                    ),
                  if (!(editingMessage == null && _panel == _Panel.voice))
                    _inputRow(
                      replyKeyboard,
                      aiSettings: aiSettings,
                      desktop: true,
                    ),
                  if (replyKeyboardPanelVisible)
                    _replyKeyboardPanel(replyKeyboard),
                ] else if (simpleComposer) ...[
                  // One row replaces the input row and the icon strip.
                  _inputRow(
                    replyKeyboard,
                    aiSettings: aiSettings,
                    simple: true,
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
                if (editingMessage == null && !desktopComposer)
                  _animatedDockedPanel(
                    visible: _panel == _Panel.function,
                    builder: simpleComposer ? _simpleMorePanel : _functionPanel,
                  ),
                if (editingMessage == null && !desktopComposer)
                  _animatedDockedPanel(
                    visible: _panel == _Panel.emoji || _panel == _Panel.sticker,
                    builder: _mediaPanel,
                  ),
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
          // composer. The media panel uses that same surface, so it needs no
          // inset layer; the panels that paint their own surface extend it
          // through the system inset with one overlay. This keeps translucent
          // cloud-theme colors identical above and below the home indicator.
          // The overlay extends a docked panel through the home indicator, so
          // it paints that panel's surface, not a second, recessed colour.
          if (panelSurfaceVisible && bottomSafeArea > 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomSafeArea,
              child: IgnorePointer(
                child: ColoredBox(
                  key: const ValueKey('chat-input-panel-safe-area-background'),
                  color: _composerDockedSurfaceColor,
                ),
              ),
            ),
        ],
      ),
    );
    // Without its own layer the composer shares one with the chat wallpaper, so
    // a keystroke or a typing update re-records the full-screen gradient too.
    // On a phone the whole bar joins the field's tap region group: taps on the
    // send button, attachments entry or panel strips count as inside, so the
    // app-wide outside-tap keyboard dismissal leaves the keyboard open.
    // Keep the framework's default group so selection handles and the
    // selection toolbar remain inside the same region too.
    return RepaintBoundary(
      child: desktopComposer ? bar : TextFieldTapRegion(child: bar),
    );
  }

  Widget _inlineBotResultMenu() {
    final c = context.colors;
    final page = _inlineBotResults;
    final results = page?.results ?? const <BotInlineResult>[];
    final headerButton = page?.button;
    final headerText = _inlineBot?.inlinePlaceholder.trim() ?? '';
    Widget body;
    if (_inlineBotLoading && page == null) {
      body = const SizedBox(
        key: ValueKey('inlineBotLoadingIndicator'),
        height: 58,
        child: Center(child: AppActivityIndicator(size: 20)),
      );
    } else if (results.isEmpty) {
      body = SizedBox(
        height: 54,
        child: Center(
          child: Text(
            AppStrings.t(AppStringKeys.chatInputBarNoInlineResults),
            style: TextStyle(color: c.textSecondary, fontSize: 14),
          ),
        ),
      );
    } else if (page != null && page.rendersAsGallery) {
      body = GridView.builder(
        key: const ValueKey('inlineBotGalleryGrid'),
        shrinkWrap: true,
        padding: const EdgeInsets.all(6),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemCount: results.length,
        itemBuilder: (_, index) => _inlineGalleryTile(results[index]),
      );
    } else {
      body = ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: results.length,
        separatorBuilder: (_, _) => const InsetDivider(leadingInset: 60),
        itemBuilder: (_, index) => _inlineListRow(results[index]),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 120) {
          unawaited(_loadMoreInlineBotResults());
        }
        return false;
      },
      child: Container(
        key: const ValueKey('inlineBotResultMenu'),
        constraints: const BoxConstraints(maxHeight: 280),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (headerButton != null)
              GestureDetector(
                key: const ValueKey('inlineBotResultsHeaderButton'),
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    unawaited(_activateInlineResultsButton(headerButton)),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: c.divider, width: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          headerButton.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.brand,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      AppIcon(
                        headerButton.isWebApp
                            ? HeroAppIcons.globe
                            : HeroAppIcons.arrowTopRight,
                        size: 13,
                        color: AppTheme.brand,
                      ),
                    ],
                  ),
                ),
              )
            else if (headerText.isNotEmpty && results.isNotEmpty)
              Container(
                key: const ValueKey('inlineBotPlaceholderHeader'),
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 6),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: c.divider, width: 0.5),
                  ),
                ),
                child: Text(
                  '@${_inlineBot!.username} · $headerText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
              ),
            Flexible(child: body),
            if (_inlineBotLoadingMore)
              const SizedBox(
                key: ValueKey('inlineBotLoadingMoreIndicator'),
                height: 36,
                child: Center(child: AppActivityIndicator(size: 16)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inlineListRow(BotInlineResult result) {
    final c = context.colors;
    return GestureDetector(
      key: ValueKey('inlineBotResult-${result.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_sendInlineBotResult(result)),
      onLongPress: () => unawaited(_sendInlineBotResultWithOptions(result)),
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _inlineResultLeading(result),
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
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
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

  Widget _inlineGalleryTile(BotInlineResult result) {
    final c = context.colors;
    final thumb = result.thumbnail;
    return GestureDetector(
      key: ValueKey('inlineBotResult-${result.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_sendInlineBotResult(result)),
      onLongPress: () => unawaited(_sendInlineBotResultWithOptions(result)),
      child: Container(
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        clipBehavior: Clip.antiAlias,
        child: thumb != null
            ? TDImage(
                photo: thumb,
                fit: result.type == 'inlineQueryResultSticker'
                    ? BoxFit.contain
                    : BoxFit.cover,
              )
            : Center(
                child: result.emoji.isNotEmpty
                    ? Text(result.emoji, style: const TextStyle(fontSize: 28))
                    : AppIcon(
                        _inlineResultIcon(result.type),
                        size: 26,
                        color: AppTheme.brand,
                      ),
              ),
      ),
    );
  }

  Widget _inlineResultLeading(BotInlineResult result) {
    final c = context.colors;
    final thumb = result.thumbnail;
    if (thumb != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(width: 40, height: 40, child: TDImage(photo: thumb)),
      );
    }
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: result.emoji.isNotEmpty
          ? Text(result.emoji, style: const TextStyle(fontSize: 20))
          : AppIcon(
              _inlineResultIcon(result.type),
              size: 21,
              color: AppTheme.brand,
            ),
    );
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
    return TextFieldTapRegion(
      child: Padding(
        key: const ValueKey('mentionSuggestions'),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _mentionCandidates.length,
            separatorBuilder: (_, _) => const InsetDivider(leadingInset: 54),
            itemBuilder: (context, index) {
              final candidate = _mentionCandidates[index];
              return GestureDetector(
                key: ValueKey('mentionCandidate-${candidate.userId}'),
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
                          isDeleted: candidate.isDeleted,
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
        ),
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

  /// The waiting voice draft's slot above the field. The card grows and fades

  /// in, and collapses when it is sent or deleted; instantly with Reduce

  /// Motion. It hides while a message is being edited and returns afterwards.

  Widget _voiceDraftSlot({required bool visible}) {
    final draft = visible ? _voiceDraft : null;
    final reduceMotion = AppMotion.isReduced(context);
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      reverseDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.bottomCenter,
        children: [...previous, ?current],
      ),
      child: draft == null
          ? const SizedBox(width: double.infinity)
          : ComposerVoiceDraftCard(
              draft: draft,
              onDelete: () {
                if (!draft.sending) _discardVoiceDraft();
              },
            ),
    );
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
    final externalChatId = vm.replyToChatId;
    final quote = vm.replyQuote;
    final name = m.isOutgoing
        ? vm.meName
        : (m.senderName?.isNotEmpty ?? false)
        ? m.senderName!
        : vm.peerTitle;
    final preview = quote?.text ?? _replyPreview(m);
    final title = externalChatId == null
        ? (quote != null
              ? AppStrings.t(AppStringKeys.composerReplyToQuoteName, {
                  'value1': name,
                })
              : AppStrings.t(AppStringKeys.composerReplyToName, {
                  'value1': name,
                }))
        : AppStrings.t(AppStringKeys.composerReplyToExternalName, {
            'value1': name,
          });
    final thumb = m.image?.thumbnail ?? m.image;
    return SizedBox(
      key: const ValueKey('composerReplyBanner'),
      height: 46,
      child: Row(
        children: [
          // Leading icon block: 52x46, matching the reference client's
          // reply-panel icon slot so the banner reads as one strip.
          SizedBox(
            width: 52,
            height: 46,
            child: Center(
              child: AppIcon(
                quote != null ? HeroAppIcons.quoteLeft : HeroAppIcons.reply,
                size: 19,
                color: c.linkBlue,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onReplyOptionsRequested,
              onLongPress: () => widget.onReplySourceJump?.call(m),
              child: SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.body(
                          c.linkBlue,
                          weight: AppTextWeight.semibold,
                        ),
                      ),
                      if (preview.isNotEmpty)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: _replyHintShowing && _replyHintSeen == false
                              ? Text(
                                  key: ValueKey(
                                    'composerReplyHint-$_replyHintTick',
                                  ),
                                  AppStrings.t(
                                    AppStringKeys.composerReplyTapHint,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.body(c.textSecondary),
                                )
                              : Text(
                                  key: ValueKey(
                                    'composerReplyPreview-$_replyHintTick',
                                  ),
                                  preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyle.body(c.textSecondary),
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (thumb != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 34,
                height: 34,
                child: TDImage(photo: thumb, cacheWidth: 68, cacheHeight: 68),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // Close: 52x46 with a circular ripple, mirroring the reference
          // client's reply-close hit target.
          SizedBox(
            width: 52,
            height: 46,
            child: AppInteractiveSurface(
              key: const ValueKey('composerReplyClose'),
              semanticLabel: AppStringKeys.confirmCancel.l10n(context),
              onTap: () => vm.setReply(null),
              borderRadius: BorderRadius.circular(19),
              child: Center(
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: 17,
                  color: c.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The pending-forward banner (forward-to-chat, the reference client parity): the

  /// same strip language as the reply banner, with the option toggles the

  /// reference client's forward preview panel carries. Tapping the body

  /// opens the forward options sheet; the close button cancels the forward.

  Widget _forwardBanner(PendingForward forward) {
    final c = context.colors;
    final first = forward.messages.first;
    final count = forward.messages.length;
    final title = count > 1
        ? AppStrings.t(AppStringKeys.chatForwardPendingCount, {'value1': count})
        : AppStrings.t(AppStringKeys.chatForwardPending);
    final previewLines = <String>[
      for (final message in forward.messages.take(2))
        if (_forwardPreviewLine(message).isNotEmpty)
          _forwardPreviewLine(message),
      if (count > 2)
        AppStrings.t(AppStringKeys.chatForwardPendingMore, {
          'value1': count - 2,
        }),
    ];
    final thumb = first.image?.thumbnail ?? first.image;
    return SizedBox(
      key: const ValueKey('composerForwardBanner'),
      height: 46,
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 46,
            child: Center(
              child: AppIcon(HeroAppIcons.forward, size: 19, color: c.linkBlue),
            ),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onForwardOptionsRequested,
              child: SizedBox(
                height: 46,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.body(
                          c.linkBlue,
                          weight: AppTextWeight.semibold,
                        ),
                      ),
                      if (previewLines.isNotEmpty)
                        Text(
                          previewLines.join('  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.body(c.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (thumb != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 34,
                height: 34,
                child: TDImage(photo: thumb, cacheWidth: 68, cacheHeight: 68),
              ),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 52,
            height: 46,
            child: AppInteractiveSurface(
              key: const ValueKey('composerForwardClose'),
              semanticLabel: AppStringKeys.confirmCancel.l10n(context),
              onTap: () => vm.clearPendingForward(),
              borderRadius: BorderRadius.circular(19),
              child: Center(
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: 17,
                  color: c.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _forwardPreviewLine(ChatMessage m) => _replyPreview(m);

  void _showForwardFailureFromComposer(Object error) {
    showToast(
      context,
      isForwardProtectedError(error)
          ? AppStringKeys.chatForwardProtected
          : AppStrings.t(AppStringKeys.chatForwardFailed, {'value1': error}),
    );
  }

  // MARK: - Input row

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
                    // A floating popover anchored above the composer, not a
                    // docked panel: it carries its own 0.7pt outline and 24pt
                    // drop shadow, so it keeps the recessed surface to read as
                    // a separate card over the composer bar it hangs from.
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

  Widget _desktopMediaPopover(BuildContext overlayContext) {
    final size = MediaQuery.sizeOf(overlayContext);
    final width = math.max(300.0, math.min(420.0, size.width - 24));
    final height = math.max(220.0, math.min(360.0, size.height - 88));
    return _desktopPopoverOverlay(
      overlayContext: overlayContext,
      link: _desktopMediaPopoverLink,
      surfaceKey: const ValueKey('desktopMediaPopover'),
      width: width,
      onDismiss: _hideDesktopPopovers,
      child: _mediaPanel(height: height),
    );
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

  /// The phone input row, or the desktop editor row when [desktop].

  ///

  /// With [simple] it is simple mode's single row: the Mic cell leads, and

  /// the Emoji and More cells and the Send button trail the field. In a bot

  /// chat the bot's menu cell takes the Mic's place, and voice opens from

  /// the More panel instead.

  Widget _inputRow(
    _ReplyKeyboard? replyKeyboard, {
    required AiSettingsController? aiSettings,
    bool desktop = false,
    bool simple = false,
  }) {
    final c = context.colors;
    final editing = vm.editingMessage != null;
    final voiceDraft = editing ? null : _voiceDraft;
    final sendingVoiceDraft = voiceDraft?.sending ?? false;
    final hasText =
        _hasText ||
        editing ||
        _pendingClipboardAttachments.isNotEmpty ||
        voiceDraft != null ||
        vm.pendingForward != null;
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
    final simpleBot = simple && vm.peerIsBot;
    Widget rowFor({required bool showLeadingCell}) => Padding(
      key: desktop ? const ValueKey('desktopComposerInput') : null,
      padding: desktop
          ? const EdgeInsets.fromLTRB(18, 2, 18, 12)
          : simple
          ? const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppMetric.simpleComposerBarInset,
            )
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
              if (simpleBot)
                _simpleBotMenuSlot(visible: showLeadingCell, editing: editing)
              else if (simple)
                _simpleMicSlot(visible: showLeadingCell, editing: editing),
              // Desktop utility actions live in the toolbar so the editor
              // keeps the entire composer width.
              if (!desktop &&
                  webAppButton != null &&
                  replyKeyboard != null) ...[
                _replyKeyboardMiniAppAction(replyKeyboard, webAppButton),
                const SizedBox(width: 8),
              ] else if (!desktop &&
                  !simpleBot &&
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
                        constraints: const BoxConstraints(minHeight: 44),
                        decoration: desktop
                            ? const BoxDecoration()
                            : BoxDecoration(
                                color: c.searchFill,
                                borderRadius: BorderRadius.circular(
                                  simple ? AppRadius.control : AppRadius.lg,
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
                                  child: ContentSizeScope(
                                    child: NotificationListener<SizeChangedLayoutNotification>(
                                      onNotification: (_) {
                                        _onInputFieldResized(desktop: desktop);
                                        return true;
                                      },
                                      child: SizeChangedLayoutNotifier(
                                        child: ConstrainedBox(
                                          constraints: desktop
                                              ? const BoxConstraints()
                                              : BoxConstraints(
                                                  maxHeight:
                                                      _touchTextFieldMaxHeight(),
                                                ),
                                          child: TextField(
                                            controller: _controller,
                                            focusNode: _focus,
                                            // The caption is fixed while its
                                            // voice message is on the way.
                                            readOnly: sendingVoiceDraft,
                                            onTap: _handleEmptyInputTap,
                                            // Submit from editing completion without
                                            // onSubmitted: Flutter restarts the input
                                            // connection after a completion action
                                            // whenever onSubmitted is present, even
                                            // when onEditingComplete retains focus.
                                            onEditingComplete: () {
                                              _controller.clearComposing();
                                              if (!desktop &&
                                                  widget.enterToSend) {
                                                unawaited(_sendCurrentText());
                                              }
                                            },
                                            minLines: desktop ? null : 1,
                                            maxLines: null,
                                            expands: desktop,
                                            keyboardType:
                                                TextInputType.multiline,
                                            textInputAction: desktop
                                                ? TextInputAction.newline
                                                : widget.enterToSend
                                                ? TextInputAction.send
                                                : TextInputAction.newline,
                                            inputFormatters:
                                                widget.enterToSend &&
                                                    Theme.of(
                                                          context,
                                                        ).platform ==
                                                        TargetPlatform.android
                                                ? [
                                                    _ComposerEnterToSendFormatter(
                                                      onSend:
                                                          _scheduleKeyboardSend,
                                                    ),
                                                  ]
                                                : null,
                                            style: TextStyle(
                                              fontSize: AppTextSize.messageBody(
                                                Theme.of(context).platform,
                                              ),
                                              color: c.textPrimary,
                                            ),
                                            contentInsertionConfiguration:
                                                editing
                                                ? null
                                                : ContentInsertionConfiguration(
                                                    allowedMimeTypes:
                                                        _imageMimeTypes,
                                                    onContentInserted:
                                                        _handleInsertedContent,
                                                  ),
                                            contextMenuBuilder:
                                                (
                                                  BuildContext context,
                                                  EditableTextState
                                                  editableTextState,
                                                ) {
                                                  ContextMenuButtonItem?
                                                  originalPaste;
                                                  final items =
                                                      <ContextMenuButtonItem>[];
                                                  for (final item
                                                      in editableTextState
                                                          .contextMenuButtonItems) {
                                                    if (item.type ==
                                                        ContextMenuButtonType
                                                            .paste) {
                                                      originalPaste = item;
                                                    } else {
                                                      items.add(item);
                                                    }
                                                  }
                                                  final paste =
                                                      ContextMenuButtonItem(
                                                        type:
                                                            ContextMenuButtonType
                                                                .paste,
                                                        label:
                                                            originalPaste
                                                                ?.label ??
                                                            AppStringKeys
                                                                .accountBackupLoadSessionPaste
                                                                .l10n(context),
                                                        onPressed: () =>
                                                            unawaited(
                                                              _handlePaste(
                                                                originalPaste,
                                                              ),
                                                            ),
                                                      );
                                                  final copyIndex = items
                                                      .indexWhere(
                                                        (item) =>
                                                            item.type ==
                                                            ContextMenuButtonType
                                                                .copy,
                                                      );
                                                  final pasteIndex =
                                                      copyIndex < 0
                                                      ? 0
                                                      : copyIndex + 1;
                                                  items.insert(
                                                    pasteIndex,
                                                    paste,
                                                  );
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
                                                  return MediaQuery(
                                                    data: MediaQuery.of(context)
                                                        .copyWith(
                                                          textScaler:
                                                              ContentSizeScope.of(
                                                                context,
                                                              ).systemTextScaler,
                                                        ),
                                                    child: AppTextSelectionToolbar.fromButtonItems(
                                                      context: context,
                                                      anchors: editableTextState
                                                          .contextMenuAnchors,
                                                      items: items,
                                                    ),
                                                  );
                                                },
                                            decoration: InputDecoration(
                                              hintText:
                                                  (voiceDraft != null
                                                          ? AppStringKeys
                                                                .composerVoiceCaptionPlaceholder
                                                          : AppStringKeys
                                                                .chatMessageInputPlaceholder)
                                                      .l10n(context),
                                              border: InputBorder.none,
                                              isCollapsed: true,
                                              contentPadding: desktop && hasText
                                                  ? const EdgeInsets.only(
                                                      bottom: 42,
                                                    )
                                                  : EdgeInsets.zero,
                                            ),
                                          ),
                                        ),
                                      ),
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
                            if (!desktop &&
                                !simple &&
                                !editing &&
                                voiceDraft == null &&
                                _hasText &&
                                _pendingClipboardAttachments.isEmpty) ...[
                              const SizedBox(width: 4),
                              _richTextConvertButton(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (simple)
                _simpleTrailingCells(
                  editing: editing,
                  voiceInMore: simpleBot,
                  send: hasText
                      ? _phoneSendButton(
                          editing: editing,
                          sendingVoiceDraft: sendingVoiceDraft,
                        )
                      : null,
                )
              else if (hasText && !desktop) ...[
                const SizedBox(width: 8),
                _phoneSendButton(
                  editing: editing,
                  sendingVoiceDraft: sendingVoiceDraft,
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
    if (!simple) return rowFor(showLeadingCell: false);
    final leadingActionWidth = webAppButton != null && replyKeyboard != null
        ? _replyKeyboardMiniAppActionMaxWidth + AppSpacing.md
        : !simpleBot && !editing && (vm.peerIsBot || _guestQueries.isNotEmpty)
        ? AppMetric.hitTarget + AppSpacing.md
        : 0.0;
    return LayoutBuilder(
      builder: (_, constraints) => rowFor(
        showLeadingCell:
            (simpleBot || _canSendVoiceNotes) &&
            _simpleComposerFitsLeadingCell(
              width: constraints.maxWidth,
              hasText: hasText,
              leadingActionWidth: leadingActionWidth,
            ),
      ),
    );
  }

  /// The phone Send button, with the AI-style prefix stacked above it when

  /// the draft is eligible. Shared unchanged by the standard and simple rows.

  Widget _phoneSendButton({
    required bool editing,
    required bool sendingVoiceDraft,
  }) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!editing && vm.canUseAiComposition && _aiDraftEligible) ...[
          Semantics(
            button: true,
            label: AppStringKeys.telegramAiEditorTelegramAIEditor.l10n(context),
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
        Semantics(
          // The long press as an action VoiceOver can reach.
          customSemanticsActions:
              _aiReplyWorkingTargetId != null || editing || sendingVoiceDraft
              ? null
              : {
                  CustomSemanticsAction(
                    label: AppStringKeys.messageSendOptionsTitle.l10n(context),
                  ): () =>
                      unawaited(_showTextSendOptions()),
                },
          child: AppInteractiveSurface(
            key: const ValueKey('composerSendButton'),
            semanticLabel:
                (editing
                        ? AppStringKeys.messageActionEdit
                        : AppStringKeys.composerSend)
                    .l10n(context),
            enabled: _aiReplyWorkingTargetId == null,
            onTap: () => unawaited(_sendCurrentText()),
            onLongPress:
                _aiReplyWorkingTargetId != null || editing || sendingVoiceDraft
                ? null
                : () => unawaited(_showTextSendOptions()),
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              width: _phoneSendSlotWidth,
              height: 44,
              child: Center(
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
                      : sendingVoiceDraft
                      ? AppActivityIndicator(size: 16, color: c.onAccent)
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
            ),
          ),
        ),
      ],
    );
  }

  /// Width of the phone Send button's slot: wider for a paid message, whose

  /// button also shows the price.

  double get _phoneSendSlotWidth => vm.requiresPaidMessage ? 58 : 44;

  bool get _hasActiveTextComposition {
    final composing = _controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  Widget _desktopSendButton() {
    final editing = vm.editingMessage != null;
    final disabled = _aiReplyWorkingTargetId != null;
    final shortcut = widget.enterToSend ? 'Enter' : 'Ctrl+Enter';
    final sendLabel =
        (editing ? AppStringKeys.messageActionEdit : AppStringKeys.composerSend)
            .l10n(context);
    final color = disabled
        ? AppTheme.brand.withValues(alpha: 0.42)
        : editing
        ? AppTheme.cloverGreen
        : AppTheme.brand;
    const splitRadius = Radius.circular(AppRadius.md);
    final primaryRadius = editing
        ? const BorderRadius.all(splitRadius)
        : const BorderRadius.only(
            topLeft: splitRadius,
            bottomLeft: splitRadius,
          );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppInteractiveSurface(
          key: const ValueKey('composerSendButton'),
          semanticLabel: '$sendLabel ($shortcut)',
          enabled: !disabled,
          onTap: disabled ? null : () => unawaited(_sendCurrentText()),
          onLongPress: disabled || editing
              ? null
              : () => unawaited(_showTextSendOptions()),
          borderRadius: primaryRadius,
          child: Container(
            key: const ValueKey('desktopComposerSendButton'),
            constraints: const BoxConstraints(minWidth: 112),
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: primaryRadius,
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
        ),
        if (!editing)
          CompositedTransformTarget(
            key: _desktopSendOptionsTargetKey,
            link: _desktopSendOptionsLink,
            child: AppInteractiveSurface(
              key: const ValueKey('desktopComposerSendOptionsButton'),
              semanticLabel: AppStringKeys.messageSendOptionsTitle.l10n(
                context,
              ),
              enabled: !disabled,
              onTap: disabled ? null : () => unawaited(_showTextSendOptions()),
              borderRadius: const BorderRadius.only(
                topRight: splitRadius,
                bottomRight: splitRadius,
              ),
              child: Container(
                key: const ValueKey('desktopComposerSendOptionsControl'),
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  border: Border(
                    left: BorderSide(
                      color: Colors.white.withValues(alpha: 0.28),
                    ),
                  ),
                  borderRadius: const BorderRadius.only(
                    topRight: splitRadius,
                    bottomRight: splitRadius,
                  ),
                ),
                child: const AppIcon(
                  HeroAppIcons.chevronDown,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
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

  /// Converts the typed draft, formatting included, into the rich-text

  /// editor, which now holds the composer's formatting tools.

  Widget _richTextConvertButton() {
    return Semantics(
      button: true,
      label: AppStringKeys.composerRichText.l10n(context),
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('composerRichTextConvertButton'),
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_openRichTextComposer()),
        child: SizedBox(
          width: 32,
          height: 28,
          child: Center(
            child: AppIcon(
              HeroAppIcons.penToSquare,
              size: 20,
              color: context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
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

  static const double _replyKeyboardMiniAppActionMaxWidth = 156;

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
          constraints: const BoxConstraints(
            maxWidth: _replyKeyboardMiniAppActionMaxWidth,
          ),
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
      key: const ValueKey('composerReplyKeyboardPanel'),
      constraints: const BoxConstraints(maxHeight: 330),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: _composerDockedSurfaceColor,
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
      height: 51,
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
                    link: _desktopMediaPopoverLink,
                    child: OverlayPortal(
                      controller: _desktopMediaPopoverController,
                      overlayChildBuilder: _desktopMediaPopover,
                      child: _desktopIcon(
                        key: const ValueKey('desktopComposerMediaAction'),
                        icon: HeroAppIcons.solidFaceSmile,
                        semanticLabel: AppStrings.t(
                          AppStringKeys.composerMediaPicker,
                        ),
                        active: _desktopMediaPopoverVisible,
                        onTap: _toggleDesktopMediaPopover,
                      ),
                    ),
                  ),
                  if (_canSendVoiceNotes)
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
                  if (!Platform.isMacOS)
                    _desktopIcon(
                      key: const ValueKey('desktopComposerLocationAction'),
                      icon: HeroAppIcons.locationDot,
                      semanticLabel: AppStringKeys.composerLocation.l10n(
                        context,
                      ),
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
                height: 44,
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
            dimension: 44,
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
          if (_canSendVoiceNotes)
            _icon(
              HeroAppIcons.microphone,
              AppStrings.t(AppStringKeys.composerHoldToTalk),
              _panel == _Panel.voice,
              _toggleVoice,
            ),
          if (widget.phoneStripForTesting || composerShowsCameraIcon())
            _icon(
              HeroAppIcons.camera,
              AppStrings.t(AppStringKeys.composerCamera),
              false,
              _takePhoto,
            ),
          _icon(
            HeroAppIcons.image,
            AppStrings.t(AppStringKeys.composerImage),
            false,
            _pickPhotos,
          ),
          _icon(
            HeroAppIcons.solidFaceSmile,
            AppStrings.t(AppStringKeys.composerMediaPicker),
            _panel == _Panel.emoji || _panel == _Panel.sticker,
            _toggleMediaPanel,
          ),
          _icon(
            _panel != _Panel.none
                ? HeroAppIcons.circleXmark
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
    return _iconStripButton(
      semanticLabel,
      active,
      onTap,
      (color) => AppIcon(icon, size: 24, color: color),
    );
  }

  Widget _iconStripButton(
    String semanticLabel,
    bool active,
    VoidCallback onTap,
    Widget Function(Color color) glyph,
  ) {
    return Expanded(
      child: AppInteractiveSurface(
        semanticLabel: semanticLabel,
        selected: active,
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: SizedBox(
          height: 44,
          child: Center(
            child: glyph(
              active ? AppTheme.brand : context.colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // MARK: - Simple mode row

  /// Scale a simple-mode control grows from as it appears or swaps glyphs.

  static const double _simpleComposerEnterScale = 0.85;

  /// The narrow rule: while there is something to send, the leading cell

  /// (the Mic, or a bot chat's menu cell) gives its room to the field once the

  /// typing field would fall under [AppMetric.simpleComposerNarrowField]. The

  /// empty row never drops it.

  /// The simple row's leading slot: [cell] and its gap to the field or,

  /// without the cell, the extra inset that keeps the field 12pt from the

  /// edge. The narrow rule collapses and restores it in place.

  Widget _simpleLeadingSlot({required bool visible, required Widget cell}) {
    return AnimatedSize(
      duration: AppMotion.duration(context, AppMotion.swap),
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.bottomEnd,
      child: visible
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                cell,
                const SizedBox(width: AppSpacing.xxs),
              ],
            )
          : const SizedBox(width: AppSpacing.lg - AppSpacing.xs),
    );
  }

  /// The Mic cell in the leading slot.

  Widget _simpleMicSlot({required bool visible, required bool editing}) {
    final voiceOpen = !editing && _panel == _Panel.voice;
    return _simpleLeadingSlot(
      visible: visible,
      cell: _simpleComposerCell(
        key: const ValueKey('composerSimpleVoiceButton'),
        semanticLabel:
            (voiceOpen
                    ? AppStringKeys.composerShowKeyboard
                    : AppStringKeys.voiceNotePreviewVoiceMessage)
                .l10n(context),
        open: voiceOpen,
        enabled: !editing,
        onTap: voiceOpen ? _showKeyboardFromSimplePanel : _openSimpleVoicePanel,
        glyph: (color) => voiceOpen
            ? AppKeyboardIcon(
                key: const ValueKey('composerSimpleKeyboardGlyph'),
                size: AppIconSize.simpleComposer,
                color: color,
              )
            : AppIcon(
                HeroAppIcons.microphone,
                key: const ValueKey('composerSimpleVoiceGlyph'),
                size: AppIconSize.simpleComposer,
                color: color,
              ),
      ),
    );
  }

  /// A bot chat's menu cell in the leading slot, where other chats have the

  /// Mic: a slash for the command sheet, or a globe when the bot's menu

  /// button is a Mini App. Tap and long press do what the bot button does.

  Widget _simpleBotMenuSlot({required bool visible, required bool editing}) {
    final menu = vm.botMenu;
    final opensMiniApp = menu?.isWebApp ?? false;
    return _simpleLeadingSlot(
      visible: visible,
      cell: _simpleComposerCell(
        key: const ValueKey('composerSimpleBotMenuButton'),
        semanticLabel: opensMiniApp && menu!.text.trim().isNotEmpty
            ? menu.actionTitle
            : AppStringKeys.chatInputBarOpenBotMenu.l10n(context),
        open: false,
        enabled: !editing,
        onTap: _showBotMenu,
        onLongPress: () => _showBotMenu(forceMenu: true),
        glyph: (color) => AppIcon(
          opensMiniApp ? HeroAppIcons.globe : HeroAppIcons.slash,
          key: ValueKey(
            opensMiniApp
                ? 'composerSimpleBotMiniAppGlyph'
                : 'composerSimpleBotCommandsGlyph',
          ),
          size: AppIconSize.simpleComposer,
          color: color,
        ),
      ),
    );
  }

  /// Emoji and More, always present, then [send] in its own slot while there

  /// is something to send. The group resizes as Send comes and goes, so the

  /// field's trailing edge moves instead of jumping. With [voiceInMore] the

  /// voice panel opens from More, so while it is docked More carries its

  /// keyboard glyph, as the Mic cell does elsewhere.

  Widget _simpleTrailingCells({
    required bool editing,
    required Widget? send,
    bool voiceInMore = false,
  }) {
    final reduceMotion = AppMotion.isReduced(context);
    final mediaOpen =
        !editing && (_panel == _Panel.emoji || _panel == _Panel.sticker);
    final moreOpen = !editing && _panel == _Panel.function;
    final voiceOpen = voiceInMore && !editing && _panel == _Panel.voice;
    return AnimatedSize(
      duration: AppMotion.duration(context, AppMotion.swap),
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.bottomStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const SizedBox(width: AppSpacing.xxs),
          _simpleComposerCell(
            key: const ValueKey('composerSimpleEmojiButton'),
            semanticLabel:
                (mediaOpen
                        ? AppStringKeys.composerShowKeyboard
                        : AppStringKeys.composerEmoji)
                    .l10n(context),
            open: mediaOpen,
            enabled: !editing,
            onTap: mediaOpen
                ? _showKeyboardFromSimplePanel
                : _openSimpleMediaPanel,
            glyph: (color) => mediaOpen
                ? AppKeyboardIcon(
                    key: const ValueKey('composerSimpleKeyboardGlyph'),
                    size: AppIconSize.simpleComposer,
                    color: color,
                  )
                : AppIcon(
                    HeroAppIcons.faceSmile,
                    key: const ValueKey('composerSimpleEmojiGlyph'),
                    size: AppIconSize.simpleComposer,
                    color: color,
                  ),
          ),
          _simpleComposerCell(
            key: const ValueKey('composerSimpleMoreButton'),
            semanticLabel:
                (voiceOpen
                        ? AppStringKeys.composerShowKeyboard
                        : moreOpen
                        ? AppStringKeys.composerCloseMenu
                        : AppStringKeys.composerMoreActions)
                    .l10n(context),
            open: moreOpen || voiceOpen,
            enabled: !editing,
            onTap: voiceOpen
                ? _showKeyboardFromSimplePanel
                : _toggleSimpleMorePanel,
            glyph: (color) => voiceOpen
                ? AppKeyboardIcon(
                    key: const ValueKey('composerSimpleKeyboardGlyph'),
                    size: AppIconSize.simpleComposer,
                    color: color,
                  )
                : AppIcon(
                    moreOpen
                        ? HeroAppIcons.circleXmark
                        : HeroAppIcons.circlePlus,
                    key: ValueKey(
                      moreOpen ? 'composerSimpleClose' : 'composerSimpleMore',
                    ),
                    size: AppIconSize.simpleComposer,
                    color: color,
                  ),
          ),
          if (send != null)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: AppMotion.swap,
              curve: Curves.easeOutCubic,
              builder: (_, progress, child) => Opacity(
                opacity: progress,
                child: reduceMotion
                    ? child
                    : Transform.scale(
                        scale:
                            _simpleComposerEnterScale +
                            (1 - _simpleComposerEnterScale) * progress,
                        child: child,
                      ),
              ),
              child: send,
            ),
        ],
      ),
    );
  }

  /// One square cell of the simple row. Its glyph is the cell's state cue:

  /// while the cell's panel is docked the glyph swaps (to the keyboard, or to

  /// a close mark) and the cell reports itself selected.

  Widget _simpleComposerCell({
    required Key key,
    required String semanticLabel,
    required bool open,
    required bool enabled,
    required VoidCallback onTap,
    required Widget Function(Color color) glyph,
    VoidCallback? onLongPress,
  }) {
    final c = context.colors;
    final reduceMotion = AppMotion.isReduced(context);
    final cell = AppInteractiveSurface(
      key: key,
      semanticLabel: semanticLabel,
      selected: open,
      enabled: enabled,
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: SizedBox.square(
        dimension: AppMetric.simpleComposerCell,
        child: Center(
          child: AnimatedSwitcher(
            duration: AppMotion.swap,
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeOutCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: reduceMotion
                  ? child
                  : ScaleTransition(
                      scale: Tween<double>(
                        begin: _simpleComposerEnterScale,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
            ),
            // Editing has no docked panels, so the cells rest while it lasts.
            child: glyph(enabled ? c.textPrimary : c.textTertiary),
          ),
        ),
      ),
    );
    if (onLongPress == null) return cell;
    // The long press as an action screen readers can reach.
    return Semantics(onLongPress: enabled ? onLongPress : null, child: cell);
  }

  /// A simple-mode cell's keyboard glyph: closes its docked panel and brings

  /// the keyboard back to the same draft.

  // The simple row stays visible above the bot reply keyboard, so opening a

  // panel from it folds that keyboard away: only one panel is ever docked.

  // MARK: - Media pickers

  /// 图片: pick one or more photos/videos and preserve their album order.

  /// 相机: capture a photo and send it.

  /// Delivers the composer's text as an ordinary formatted message when the

  /// account has no rich send path. Block structure has no representation in

  /// `inputMessageText`, so it is dropped with one toast; when nothing at all

  /// can be sent (a document containing media, or a rejected send) the draft

  /// is reopened instead of silently sending only its caption and losing media.

  /// Resolves how this account can deliver a rich message, without asking the

  /// user for anything. A null result means the account has no rich send path;

  /// callers may then offer [RichMessageRelayConfig] setup once and fall back

  /// to a plain formatted message.

  /// 文件: pick an arbitrary document and send it.

  /// 位置: open a map picker centred on the GPS fix; send the chosen point.

  /// 投票: collect a question + options and send a poll.

  /// 音频: pick a local audio file and send it as a music message.

  /// 音频: search Telegram audio first; local files remain available inside.

  /// 清单: collect a title + tasks and send a checklist (to-do list).

  // MARK: - Function panel

  Widget _functionPanel() {
    final items = [
      if (widget.showCallAction && !Platform.isMacOS)
        (
          HeroAppIcons.phone.data,
          AppStrings.t(
            vm.isGroup
                ? AppStringKeys.composerGroupVoiceCall
                : AppStringKeys.composerVoiceCall,
          ),
          () => widget.onStartCall(false),
        ),
      if (!Platform.isMacOS)
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
      color: _composerDockedSurfaceColor,
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

  /// Simple mode's More panel: the strip's tools and the function panel's in

  /// one vertically scrolling grid, with no paging. Every row is as tall as

  /// its tallest label, so long translations and large text wrap instead of

  /// truncating; at extreme text sizes the grid becomes a one-column list.

  Widget _simpleMorePanel() {
    final items = <(AppIconData, String, VoidCallback)>[
      (HeroAppIcons.image, AppStringKeys.composerImage, _pickPhotos),
      if (widget.phoneStripForTesting || composerShowsCameraIcon())
        (HeroAppIcons.camera, AppStringKeys.composerCamera, _takePhoto),
      // A bot chat's leading cell is its menu button, so voice opens here.
      if (vm.peerIsBot && _canSendVoiceNotes)
        (
          HeroAppIcons.microphone,
          AppStringKeys.voiceNotePreviewVoiceMessage,
          _openSimpleVoicePanel,
        ),
      if (widget.showCallAction && !Platform.isMacOS)
        (
          HeroAppIcons.phone,
          vm.isGroup
              ? AppStringKeys.composerGroupVoiceCall
              : AppStringKeys.composerVoiceCall,
          () => widget.onStartCall(false),
        ),
      if (!Platform.isMacOS)
        (
          HeroAppIcons.locationDot,
          AppStringKeys.composerLocation,
          _sendLocation,
        ),
      (HeroAppIcons.folder, AppStringKeys.topicPostContentFile, _pickFile),
      (HeroAppIcons.idBadge, AppStringKeys.composerContact, _sendContact),
      if (!vm.isDirectMessagesGroup)
        (HeroAppIcons.grip, AppStringKeys.composerPoll, _createPoll),
      (
        HeroAppIcons.clock,
        AppStringKeys.messageSendOptionsScheduledMessages,
        _openScheduledMessages,
      ),
      (HeroAppIcons.music, AppStringKeys.composerAudio, _pickAudio),
      (
        HeroAppIcons.penToSquare,
        AppStringKeys.composerRichText,
        _openRichTextComposer,
      ),
      if (!vm.isDirectMessagesGroup)
        (
          HeroAppIcons.listCheck,
          AppStringKeys.composerChecklist,
          _createChecklist,
        ),
      if (vm.isDirectMessagesGroup && !vm.isAdministeredDirectMessagesGroup)
        (
          HeroAppIcons.penToSquare,
          AppStringKeys.suggestedPostComposerTitle,
          _createSuggestedPost,
        ),
    ];
    final c = context.colors;
    final labelStyle = AppTextStyle.footnote(c.textPrimary).copyWith(
      height:
          AppMetric.simpleComposerPanelLabelLineHeight / AppTextSize.footnote,
    );
    final textScale =
        MediaQuery.textScalerOf(context).scale(AppTextSize.footnote) /
        AppTextSize.footnote;
    final screenSize = MediaQuery.sizeOf(context);
    // Large text grows the panel up to its share of the screen; the standard
    // height stays the floor, so a short landscape screen keeps it too.
    final panelHeight = math.max(
      AppMetric.simpleComposerPanelHeight,
      math.min(
        AppMetric.simpleComposerPanelHeight * textScale,
        screenSize.height * AppMetric.simpleComposerPanelMaxScreenFraction,
      ),
    );
    return Container(
      key: const ValueKey('composerSimpleMorePanel'),
      width: double.infinity,
      height: panelHeight,
      color: _composerDockedSurfaceColor,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : screenSize.width;
          final columns =
              ((width - 2 * AppSpacing.lg) /
                      (AppMetric.simpleComposerPanelCellMinWidth * textScale))
                  .floor()
                  .clamp(1, AppMetric.simpleComposerPanelMaxColumns);
          return Scrollbar(
            controller: _simpleMorePanelScroll,
            child: SingleChildScrollView(
              controller: _simpleMorePanelScroll,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xxl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (
                    var start = 0;
                    start < items.length;
                    start += columns
                  ) ...[
                    if (start > 0) const SizedBox(height: AppSpacing.lg),
                    if (columns == 1)
                      _simpleMorePanelItem(
                        items[start],
                        labelStyle: labelStyle,
                        listRow: true,
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var column = 0; column < columns; column++)
                            Expanded(
                              child: start + column < items.length
                                  ? _simpleMorePanelItem(
                                      items[start + column],
                                      labelStyle: labelStyle,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// One More-panel tool: a bare line glyph over its full label, or, as a

  /// [listRow], the glyph leading a left-aligned label.

  Widget _simpleMorePanelItem(
    (AppIconData, String, VoidCallback) item, {
    required TextStyle labelStyle,
    bool listRow = false,
  }) {
    final (icon, labelKey, action) = item;
    final label = labelKey.l10n(context);
    final glyph = SizedBox.square(
      dimension: AppMetric.simpleComposerCell,
      child: Center(
        child: AppIcon(
          icon,
          size: AppIconSize.simpleComposerPanel,
          color: context.colors.textPrimary,
        ),
      ),
    );
    return AppInteractiveSurface(
      semanticLabel: label,
      onTap: () {
        _setPanel(_Panel.none);
        action();
      },
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: listRow
            ? ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppMetric.simpleComposerPanelListRowHeight,
                ),
                child: Row(
                  children: [
                    glyph,
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: Text(label, style: labelStyle)),
                  ],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  glyph,
                  const SizedBox(height: AppSpacing.xs),
                  Text(label, textAlign: TextAlign.center, style: labelStyle),
                ],
              ),
      ),
    );
  }

  /// A docked panel slot that grows and shrinks with the house motion

  /// language instead of swapping instantly: opening (button tap) and

  /// collapsing (toggle, transcript-drag dismiss, send) both animate. The

  /// outgoing child stays in the tree while the slot collapses, so its state

  /// (scroll offsets, store subscriptions) survives a same-panel reopen only

  /// through the panel's own persistence — never through this animation.

  Widget _animatedDockedPanel({
    required bool visible,
    required Widget Function() builder,
  }) {
    final reduceMotion = AppMotion.isReduced(context);
    // Collapse runs on the accelerate curve (content leaving gets out of the
    // way quickly — the drag-dismiss the user called "not clean"), expansion
    // keeps the standard decelerate. AnimatedSize has no reverseCurve, so the
    // snappier collapse comes from the shorter reverseDuration alone.
    return AnimatedSize(
      duration: reduceMotion
          ? Duration.zero
          : AppMotion.duration(context, AppMotion.responsive),
      reverseDuration: reduceMotion
          ? Duration.zero
          : AppMotion.duration(context, AppMotion.quick),
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      clipBehavior: Clip.none,
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : AppMotion.duration(context, AppMotion.quick),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: visible
            ? KeyedSubtree(
                key: const ValueKey('dockedPanelContent'),
                child: builder(),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }

  // MARK: - Media panel (emoji / stickers / GIF)

  /// One picker with a segmented selector (Emoji | Stickers | GIF) above the

  /// active kind's own strip and content, painted on the composer's own

  /// surface so it continues the input bar instead of reading as a separate

  /// block. The kinds switch instantly — there is no inter-kind scrolling.

  /// Rendered for both `_Panel.emoji` and `_Panel.sticker`, and by the

  /// desktop media popover.

  Widget _mediaPanel({double height = 376}) {
    final searchSelected = _isPanelSearchSelected;
    return Container(
      key: const ValueKey('composerMediaPanel'),
      height: height,
      color: _composerDockedSurfaceColor,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _mediaKindSegmentControl()),
              _mediaPanelSearchButton(active: searchSelected),
            ],
          ),
          if (searchSelected) ...[
            _panelSearchField(),
            Expanded(child: _panelSearchContent()),
          ] else ...[
            _mediaSecondaryStrip(),
            Expanded(child: _mediaContent()),
          ],
        ],
      ),
    );
  }

  Widget _mediaSecondaryStrip() => switch (_mediaKind) {
    _MediaKind.emoji => _emojiTabStrip(),
    _MediaKind.sticker => _stickerTabStrip(),
    _MediaKind.gif => _gifTabStrip(),
  };

  Widget _mediaContent() {
    return switch (_mediaKind) {
      _MediaKind.emoji => _emojiContent(),
      _MediaKind.sticker => _stickerContent(),
      _MediaKind.gif =>
        _gifSearchSelected ? _gifSearchContent() : _gifContent(),
    };
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
      key: const ValueKey('gifPanelGrid'),
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

  // MARK: Sticker panel

  /// The packs the sticker panel lists vertically, in strip order: recents

  /// first when non-empty, then every installed pack. Favorites render as

  /// their own leading section inside the list.

  List<StickerPack> _stickerPanelPacks() {
    final packs = StickerStore.shared.packs
        .where((p) => p.id != StickerStore.recentPackId)
        .toList(growable: false);
    final recents = StickerStore.shared.packs
        .where((p) => p.id == StickerStore.recentPackId)
        .toList(growable: false);
    return [...recents, ...packs];
  }

  /// The sticker panel: favorites + every pack stacked in ONE continuously

  /// scrollable list (a pack's grid flows into the next pack's header), with

  /// the pack strip on top anchoring into it in both directions.

  Widget _stickerContent() {
    final store = StickerStore.shared;
    final packs = _stickerPanelPacks();
    final favorites = FavoriteStickerStore.shared.items;
    if (packs.isEmpty && favorites.isEmpty) {
      return Center(
        child: Text(
          store.loading
              ? AppStrings.t(AppStringKeys.composerLoadingEmoji)
              : AppStrings.t(AppStringKeys.composerNoEmoji),
          style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onStickerPanelScrollNotification,
      child: CustomScrollView(
        key: const ValueKey('stickerPanelScroll'),
        controller: _stickerPanelScroll,
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          if (favorites.isNotEmpty) ...[
            Builder(
              builder: (context) {
                _favoritesHeaderContext = context;
                return SliverToBoxAdapter(
                  child: _mediaSubsectionHeader(
                    const ValueKey('mediaStickerPack-favorites'),
                    AppStrings.t(AppStringKeys.mediaFavorites),
                  ),
                );
              },
            ),
            SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _stickerTile(favorites[index]),
                  childCount: favorites.length,
                ),
              ),
            ),
          ],
          for (final pack in packs) ...[
            SliverToBoxAdapter(child: _mediaStickerPackHeader(pack)),
            if (!pack.loaded && pack.stickers.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: SizedBox(
                    height: 24,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _stickerTile(
                      pack.stickers[index],
                      recent: pack.id == StickerStore.recentPackId,
                    ),
                    childCount: pack.stickers.length,
                  ),
                ),
              ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
    );
  }

  /// Scroll-follow for the sticker strip: the highlighted tab is the pack

  /// whose header last crossed the viewport top, exactly the anchor logic the

  /// unified panel used scoped to packs.

  bool _onStickerPanelScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollEndNotification &&
        notification is! ScrollUpdateNotification) {
      return false;
    }
    if (_stickerPanelAnimatingToPack) {
      if (notification is ScrollEndNotification) {
        _stickerPanelAnimatingToPack = false;
      }
      return false;
    }
    if (!_stickerPanelScroll.hasClients) return false;
    if (_isPanelSearchSelected) return false;
    final packId = _stickerPackAtViewportTop();
    if (packId == null || packId == _stickerAnchorPackId) return false;
    if (packId == _stickerSearchTabId || packId == _gifTabId) return false;
    setState(() => _stickerAnchorPackId = packId);
    return false;
  }

  /// The pack whose header sits at (or just above) the viewport top.

  int? _stickerPackAtViewportTop() {
    final position = _stickerPanelScroll.position;
    // Favorites render ahead of every pack: while the favorites header is
    // above the viewport top (and the first pack's header is not), the strip
    // highlights the favorites pseudo-tab.
    if (FavoriteStickerStore.shared.items.isNotEmpty) {
      final favoritesOffset = _packHeaderContextOffset(_favoritesHeaderContext);
      final firstPack = _stickerPanelPacks().firstOrNull;
      final firstPackOffset = firstPack == null
          ? null
          : _packHeaderScrollOffset(firstPack.id, position);
      if (favoritesOffset != null &&
          position.pixels + 2.0 >= favoritesOffset &&
          (firstPackOffset == null ||
              position.pixels + 2.0 < firstPackOffset)) {
        return _favoritesTabId;
      }
    }
    final packs = _stickerPanelPacks();
    if (packs.isEmpty) return null;
    // The scroll cannot advance past maxScrollExtent, so the last packs'
    // headers may never reach the top. At the end of the scroll the tail is
    // what the user is looking at: the last pack wins.
    if (position.pixels >= position.maxScrollExtent - 0.5) {
      return packs.last.id;
    }
    int? best;
    for (final pack in packs) {
      final offset = _packHeaderScrollOffset(pack.id, position);
      if (offset != null && position.pixels + 2.0 >= offset) best = pack.id;
    }
    return best ?? packs.first.id;
  }

  /// The scroll offset that puts a pack header at the viewport top, measured

  /// through the header's live render box so it stays exact even while

  /// earlier packs load or resize.

  double? _packHeaderScrollOffset(int packId, ScrollPosition position) {
    return _packHeaderContextOffset(_packHeaderContexts[packId]);
  }

  double? _packHeaderContextOffset(BuildContext? context) {
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;
    return viewport.getOffsetToReveal(box, 0).offset;
  }

  /// Pack header BuildContexts registered as the list builds, keyed by pack

  /// id, so the strip's anchor math can measure any pack's header — even ones

  /// scrolled far off-screen stay registered once built (forward slivers all

  /// lay out in a CustomScrollView).

  final Map<int, BuildContext> _packHeaderContexts = {};

  /// Tab tapped (or the panel reopened on a persisted pack): scroll so that

  /// pack's header sits at the top of the viewport.

  void _scrollStickerPanelToPack(int packId) {
    if (!_stickerPanelScroll.hasClients) {
      // The search overlay can still be unwinding from this same tap: retry
      // once the panel scroll has rebuilt and attached.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_isPanelSearchSelected &&
            _stickerPanelScroll.hasClients) {
          _scrollStickerPanelToPack(packId);
        }
      });
      return;
    }
    final position = _stickerPanelScroll.position;
    final target = _packHeaderScrollOffset(packId, position);
    if (target == null) return;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() < 0.5) return;
    _stickerPanelAnimatingToPack = true;
    _stickerPanelScroll.animateTo(
      clamped,
      duration: AppMotion.duration(context, AppMotion.routeReverse),
      curve: AppMotion.standard,
    );
  }

  /// Starts the pack's first load the moment its section builds without

  /// contents; one in-flight load per pack per session, retried after a

  /// failure because the entry is removed when the future settles.

  void _ensureStickerPackLoaded(StickerPack? pack) {
    if (pack == null || pack.loaded || pack.stickers.isNotEmpty) return;
    if (_stickerPackLoads.containsKey(pack.id)) return;
    final load = StickerStore.shared
        .loadPack(pack.id)
        .whenComplete(() => _stickerPackLoads.remove(pack.id));
    _stickerPackLoads[pack.id] = load;
  }

  /// A sticker pack's header row; lazily starts the pack's first load the

  /// moment the section builds without contents and registers its context

  /// for the strip's anchor math.

  Widget _mediaStickerPackHeader(StickerPack pack) {
    _ensureStickerPackLoaded(pack);
    final title = pack.id == StickerStore.recentPackId
        ? AppStrings.t(AppStringKeys.stickerStoreRecent)
        : pack.title;
    return Builder(
      builder: (context) {
        _packHeaderContexts[pack.id] = context;
        return _mediaSubsectionHeader(
          ValueKey('mediaStickerPack-${pack.id}'),
          title,
        );
      },
    );
  }

  /// The horizontally scrollable pack strip above the sticker panel: the

  /// search entry, recents, favorites when any exist, then one thumbnail per

  /// installed pack. Tapping a tab scrolls the panel list to that pack;

  /// scrolling the list highlights the pack at the top.

  Widget _stickerTabStrip() {
    final c = context.colors;
    final packs = StickerStore.shared.packs;
    final activeId = _activeStickerTab;
    final installed = packs.where((p) => p.id != StickerStore.recentPackId);
    final hasFavorites = FavoriteStickerStore.shared.items.isNotEmpty;
    final hasRecents = packs.any((p) => p.id == StickerStore.recentPackId);
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
            if (hasFavorites)
              _emojiTabButton(
                key: const ValueKey('stickerFavoritesTab'),
                selected: _stickerAnchorPackId == _favoritesTabId,
                onTap: _scrollStickerPanelToFavorites,
                child: AppIcon(
                  HeroAppIcons.solidStar,
                  size: 20,
                  color: _stickerAnchorPackId == _favoritesTabId
                      ? AppTheme.brand
                      : c.textSecondary,
                ),
              ),
            if (hasRecents)
              _emojiTabButton(
                key: const ValueKey('stickerRecentsTab'),
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
            for (final pack in installed)
              _emojiTabButton(
                key: ValueKey('stickerPackTab-${pack.id}'),
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

  /// The favorites pseudo-tab scrolls the panel list to the favorites

  /// section header (it is not a real pack, so it has no pack id).

  void _scrollStickerPanelToFavorites() {
    final ctx = _favoritesHeaderContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.attached || !_stickerPanelScroll.hasClients) {
      return;
    }
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final position = _stickerPanelScroll.position;
    final target = viewport
        .getOffsetToReveal(box, 0)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    setState(() => _stickerAnchorPackId = _favoritesTabId);
    if ((target - position.pixels).abs() < 0.5) return;
    _stickerPanelAnimatingToPack = true;
    _stickerPanelScroll.animateTo(
      target,
      duration: AppMotion.duration(context, AppMotion.routeReverse),
      curve: AppMotion.standard,
    );
  }

  BuildContext? _favoritesHeaderContext;

  // MARK: Emoji panel

  /// The emoji panel: the standard catalog categories plus one section per

  /// custom-emoji pack, stacked in ONE continuously scrollable list under the

  /// panel's own category strip.

  Widget _emojiContent() {
    return NotificationListener<ScrollNotification>(
      onNotification: _onEmojiPanelScrollNotification,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = emojiPanelColumnCount(constraints.maxWidth);
          _emojiPanelColumns = columns;
          return CustomScrollView(
            key: const ValueKey('emojiPanelScroll'),
            controller: _emojiPanelScroll,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ...standardEmojiSectionSlivers(
                context: context,
                columns: columns,
                hasRecents:
                    EmojiRecentsStore.shared.renderableEntries.isNotEmpty,
                insert: _controller.insertText,
                insertCustom: _controller.insertCustomEmoji,
              ),
              for (final pack in EmojiStore.shared.customPacks) ...[
                SliverToBoxAdapter(
                  child: _mediaSubsectionHeader(
                    ValueKey('mediaEmojiPack-${pack.id}'),
                    pack.title,
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: emojiPanelCellExtent,
                    ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final item = pack.emoji[index];
                      return item.customEmojiId != 0
                          ? EmojiPanelCell(
                              customItem: item,
                              onTap: () => _controller.insertCustomEmoji(
                                item.customEmojiId,
                                item.emoji,
                              ),
                            )
                          : const SizedBox();
                    }, childCount: pack.emoji.length),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
            ],
          );
        },
      ),
    );
  }

  /// The horizontally scrollable strip above the emoji panel: the search

  /// entry, then the recents and standard category icons, then one thumbnail

  /// per custom-emoji pack. Tapping an entry scrolls the panel to it.

  Widget _emojiTabStrip() {
    final c = context.colors;
    final packs = EmojiStore.shared.customPacks;
    final hasRecents = EmojiRecentsStore.shared.renderableEntries.isNotEmpty;
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
            if (hasRecents)
              _emojiTabButton(
                key: const ValueKey('emojiRecentsTab'),
                selected: _emojiTab == 'recent',
                onTap: () => _scrollEmojiPanelTo('recent'),
                child: AppIcon(
                  HeroAppIcons.clock,
                  size: 20,
                  color: _emojiTab == 'recent'
                      ? AppTheme.brand
                      : c.textSecondary,
                ),
              ),
            for (var i = 0; i < EmojiCatalog.categories.length; i++)
              _emojiTabButton(
                key: ValueKey('emojiCategoryTab-$i'),
                selected: _emojiTab == _emojiCategoryTabId(i),
                onTap: () => _scrollEmojiPanelTo(_emojiCategoryTabId(i)),
                child: AppIcon(
                  _emojiCategoryIcons[i],
                  size: 20,
                  color: _emojiTab == _emojiCategoryTabId(i)
                      ? AppTheme.brand
                      : c.textSecondary,
                ),
              ),
            for (final pack in packs)
              _emojiTabButton(
                key: ValueKey('emojiPackTab-${pack.id}'),
                selected: _emojiTab == 'pack-${pack.id}',
                onTap: () => _scrollEmojiPanelTo('pack-${pack.id}'),
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

  /// One icon per catalog category, mirroring the standalone pane's strip.

  static const List<AppIconData> _emojiCategoryIcons = [
    HeroAppIcons.faceSmile,
    HeroAppIcons.user,
    HeroAppIcons.bug,
    HeroAppIcons.cake,
    HeroAppIcons.trophy,
    HeroAppIcons.locationPin,
    HeroAppIcons.lightbulb,
    HeroAppIcons.hashtag,
  ];

  String _emojiCategoryTabId(int index) => 'category-$index';

  /// Scrolls the emoji panel so the named section's header sits at the top:

  /// 'recent', 'category-i' or 'pack-id'.

  void _scrollEmojiPanelTo(String sectionId) {
    if (_emojiTab != sectionId) {
      setState(() => _emojiTab = sectionId);
    }
    final target = _emojiSectionTarget(sectionId);
    if (target == null) return;
    if (!_emojiPanelScroll.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _emojiPanelScroll.hasClients) {
          _scrollEmojiPanelTo(sectionId);
        }
      });
      return;
    }
    final position = _emojiPanelScroll.position;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() < 0.5) return;
    _emojiPanelAnimatingToSection = true;
    _emojiPanelScroll.animateTo(
      clamped,
      duration: AppMotion.duration(context, AppMotion.routeReverse),
      curve: AppMotion.standard,
    );
  }

  /// Analytic offset of an emoji section header, exactly like the standalone

  /// pane computes them: headers and grid rows both have fixed extents, so

  /// the sum is exact however far off-screen the section is.

  double? _emojiSectionTarget(String sectionId) {
    final columns = _emojiPanelColumns;
    if (columns == null) return null;
    var offset = 8.0; // top spacer
    if (EmojiRecentsStore.shared.renderableEntries.isNotEmpty) {
      if (sectionId == 'recent') return offset;
      offset +=
          emojiSectionHeaderExtent +
          (EmojiRecentsStore.shared.renderableEntries.length / columns)
                  .ceilToDouble() *
              emojiPanelCellExtent;
    }
    for (var i = 0; i < EmojiCatalog.categories.length; i++) {
      if (sectionId == _emojiCategoryTabId(i)) return offset;
      offset +=
          emojiSectionHeaderExtent +
          (EmojiCatalog.categories[i].emojis.length / columns).ceilToDouble() *
              emojiPanelCellExtent;
    }
    for (final pack in EmojiStore.shared.customPacks) {
      if (sectionId == 'pack-${pack.id}') {
        return offset;
      }
      offset +=
          _emojiPackHeaderExtent +
          (pack.emoji.length / columns).ceilToDouble() * emojiPanelCellExtent;
    }
    return null;
  }

  /// Column count for the emoji panel's analytic offset math, captured from

  /// the live layout so the strip and the grid agree.
  int? _emojiPanelColumns;

  static const double _emojiPackHeaderExtent = 26;

  /// Scroll-follow for the emoji strip: the highlighted entry is the section

  /// whose header last crossed the viewport top.

  bool _onEmojiPanelScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollEndNotification &&
        notification is! ScrollUpdateNotification) {
      return false;
    }
    if (_emojiPanelAnimatingToSection) {
      if (notification is ScrollEndNotification) {
        _emojiPanelAnimatingToSection = false;
      }
      return false;
    }
    if (!_emojiPanelScroll.hasClients) return false;
    if (_isPanelSearchSelected) return false;
    final pixels = _emojiPanelScroll.position.pixels;
    final sectionId = _emojiSectionAt(pixels);
    if (sectionId == null || sectionId == _emojiTab) return false;
    if (sectionId == _emojiSearchTab) return false;
    setState(() => _emojiTab = sectionId);
    return false;
  }

  /// The section id whose header last scrolled to (or past) the viewport top.

  String? _emojiSectionAt(double pixels) {
    final columns = _emojiPanelColumns;
    if (columns == null) return null;
    var offset = 8.0;
    String? best;
    bool sawAny = false;
    if (EmojiRecentsStore.shared.renderableEntries.isNotEmpty) {
      sawAny = true;
      best = 'recent';
      offset +=
          emojiSectionHeaderExtent +
          (EmojiRecentsStore.shared.renderableEntries.length / columns)
                  .ceilToDouble() *
              emojiPanelCellExtent;
    }
    for (var i = 0; i < EmojiCatalog.categories.length; i++) {
      if (pixels + 2.0 >= offset) {
        best = _emojiCategoryTabId(i);
      }
      offset +=
          emojiSectionHeaderExtent +
          (EmojiCatalog.categories[i].emojis.length / columns).ceilToDouble() *
              emojiPanelCellExtent;
    }
    for (final pack in EmojiStore.shared.customPacks) {
      if (pixels + 2.0 >= offset) {
        best = 'pack-${pack.id}';
      }
      offset +=
          _emojiPackHeaderExtent +
          (pack.emoji.length / columns).ceilToDouble() * emojiPanelCellExtent;
    }
    return sawAny || best != null ? best : null;
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

  /// The GIF segment's secondary strip is a search bar plus the saved-GIFs

  /// tab, mirroring the emoji and sticker search tabs.

  Widget _gifTabStrip() {
    final c = context.colors;
    return Container(
      key: const ValueKey('gifPanelTabs'),
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
              key: const ValueKey('gifSearchTab'),
              selected: _gifSearchSelected,
              onTap: () => _selectStickerTab(_stickerSearchTabId),
              child: AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: 20,
                color: _gifSearchSelected ? AppTheme.brand : c.textSecondary,
              ),
            ),
            _emojiTabButton(
              key: const ValueKey('gifSavedTab'),
              selected: !_gifSearchSelected,
              onTap: () => _selectStickerTab(_gifTabId),
              child: AppIcon(
                HeroAppIcons.gif,
                size: 22,
                color: !_gifSearchSelected ? AppTheme.brand : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A lighter-weight sub-header for a subsection (sticker pack, custom-emoji

  /// pack) inside a section.

  Widget _mediaSubsectionHeader(Key key, String label) {
    final c = context.colors;
    return SizedBox(
      key: key,
      height: 26,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 14, top: 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  /// The trailing search affordance on the segment-control row. Tapping it

  /// enters the existing panel-search mode for the active section kind and

  /// swaps the unified scroll for the search results; tapping it again leaves

  /// search and restores the previous scroll offset.

  Widget _mediaPanelSearchButton({required bool active}) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: AppStringKeys.composerMediaSearch.l10n(context),
      child: GestureDetector(
        key: const ValueKey('mediaPanelSearchButton'),
        behavior: HitTestBehavior.opaque,
        onTap: _togglePanelSearch,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(
            child: AppIcon(
              HeroAppIcons.magnifyingGlass,
              size: 19,
              color: active ? AppTheme.brand : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  /// The search content replacing the unified scroll while search is active:

  /// the existing per-kind search result grids, unchanged.

  Widget _panelSearchContent() {
    return switch (_mediaKind) {
      _MediaKind.emoji => _emojiSearchContent(),
      _MediaKind.sticker => _stickerSearchContent(),
      _MediaKind.gif => _gifSearchContent(),
    };
  }

  /// The active kind's panel scroller, whose offset the search overlay

  /// remembers and restores. GIF keeps no panel scroll (its content is a

  /// plain grid at the top).

  ScrollController? get _activePanelScroll => switch (_mediaKind) {
    _MediaKind.emoji => _emojiPanelScroll,
    _MediaKind.sticker => _stickerPanelScroll,
    _MediaKind.gif => null,
  };

  /// Enters/leaves the panel-search overlay, remembering where the active

  /// kind's panel scroll sat so leaving restores the user's place.

  void _togglePanelSearch() {
    if (_isPanelSearchSelected) {
      final restore = _panelScrollRestoreOffset;
      setState(() {
        _exitPanelSearchTabs();
        _panelScrollRestoreOffset = null;
      });
      final controller = _activePanelScroll;
      if (restore != null && controller != null && controller.hasClients) {
        final position = controller.position;
        // correctBy never animates and never throws overscroll notifications;
        // clamping to the live extents keeps a shrunken content height
        // (a pack list that reloads, for example) from restoring past the end.
        final target = restore.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        position.correctBy(target - position.pixels);
      }
      return;
    }
    setState(() {
      final controller = _activePanelScroll;
      _panelScrollRestoreOffset = controller != null && controller.hasClients
          ? controller.position.pixels
          : null;
      switch (_mediaKind) {
        case _MediaKind.emoji:
          _emojiTab = _emojiSearchTab;
        case _MediaKind.sticker:
          _stickerPack = _stickerSearchTabId;
        case _MediaKind.gif:
          _stickerPack = _stickerSearchTabId;
      }
    });
    if (_panelSearch.text.trim().isNotEmpty) {
      _queuePanelSearch();
    }
  }

  /// Returns the tab selectors to their non-search values (called from inside

  /// a setState block).

  void _exitPanelSearchTabs() {
    switch (_mediaKind) {
      case _MediaKind.emoji:
        if (_emojiTab == _emojiSearchTab) _emojiTab = 'standard';
      case _MediaKind.sticker:
        if (_stickerPack == _stickerSearchTabId) _stickerPack = null;
      case _MediaKind.gif:
        if (_stickerPack == _stickerSearchTabId) _stickerPack = _gifTabId;
    }
  }

  Widget _mediaKindSegmentControl() {
    _ComposerSegment segment(_MediaKind kind, AppIconData icon, String label) =>
        (
          key: ValueKey('mediaSegment-${kind.name}'),
          icon: icon,
          label: label,
          selected: _mediaKind == kind,
          onTap: () => _selectMediaKind(kind),
        );
    return _composerSegmentSwitcher(
      key: const ValueKey('mediaKindSegments'),
      segments: [
        segment(
          _MediaKind.emoji,
          HeroAppIcons.solidFaceSmile,
          AppStrings.t(AppStringKeys.composerEmoji),
        ),
        segment(
          _MediaKind.sticker,
          HeroAppIcons.grip,
          AppStrings.t(AppStringKeys.composerStickers),
        ),
        segment(
          _MediaKind.gif,
          HeroAppIcons.gif,
          AppStrings.t(AppStringKeys.downloadsMediaAnimation),
        ),
      ],
    );
  }

  /// The segmented switcher docked panels share (Emoji | Stickers | GIF, and

  /// Voice | Video message), so every panel draws the same control.

  Widget _composerSegmentSwitcher({
    required Key key,
    required List<_ComposerSegment> segments,
  }) {
    final c = context.colors;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    // A brand tint over the track, as on the format panel's selected cell. The
    // light track is as white as a card, so a card-coloured fill would vanish.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highlight = Color.alphaBlend(
      AppTheme.brand.withValues(alpha: dark ? 0.28 : 0.14),
      c.searchFill,
    );
    Widget buildSegment(_ComposerSegment item) {
      final selected = item.selected;
      final enabled = item.onTap != null;
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            item.icon,
            size: 16,
            color: !enabled
                ? c.textTertiary
                : selected
                ? AppTheme.brand
                : c.textSecondary,
          ),
          const SizedBox(width: 5),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: !enabled
                  ? c.textTertiary
                  : selected
                  ? c.textPrimary
                  : c.textSecondary,
            ),
          ),
        ],
      );
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          enabled: enabled ? null : false,
          label: item.label,
          child: GestureDetector(
            key: item.key,
            behavior: HitTestBehavior.opaque,
            onTap: item.onTap,
            // The highlight always fills the whole segment. Unselected
            // segments have no colour at all, so a change fades the tint
            // itself instead of passing through grey on the way to
            // transparent black.
            child: AnimatedContainer(
              key: selected
                  ? ValueKey(
                      'mediaSegmentSelected-${_segmentKindLabel(item.key)}',
                    )
                  : null,
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? highlight : null,
                // Concentric with the 9pt track inside its 2pt padding.
                borderRadius: BorderRadius.circular(7),
              ),
              // Large text scales shrink the content, never the highlight.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: content,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      key: key,
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(children: [for (final item in segments) buildSegment(item)]),
    );
  }

  /// Maps a segment key like `mediaSegment-gif` to its kind label, so the

  /// selected segment's highlight carries an assertable

  /// `mediaSegmentSelected-<kind>` key.

  String _segmentKindLabel(Key? key) {
    if (key is ValueKey<String>) {
      final value = key.value;
      final dash = value.lastIndexOf('-');
      if (dash >= 0 && dash + 1 < value.length) {
        return value.substring(dash + 1);
      }
      return value;
    }
    return key?.toString() ?? '';
  }

  Widget _gifSearchContent() {
    if (_panelSearch.text.trim().isEmpty) return const SizedBox.shrink();
    if (_gifSearchResults.isEmpty && _gifSearchNextOffset.isEmpty) {
      return _panelSearchState();
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.2,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount:
          _gifSearchResults.length + (_gifSearchNextOffset.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _gifSearchResults.length) {
          return _gifSearchLoadMoreTile();
        }
        return _gifTile(_gifSearchResults[index], search: true);
      },
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
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: emojiPanelColumnCount(constraints.maxWidth),
        ),
        itemCount: count,
        itemBuilder: (context, index) {
          if (index < _emojiSearchResults.length) {
            final emoji = _emojiSearchResults[index];
            return EmojiPanelCell(
              key: ValueKey('emojiSearch-$emoji'),
              emoji: emoji,
              onTap: () {
                EmojiRecentsStore.shared.record(emoji);
                _controller.insertText(emoji);
              },
            );
          }
          final item =
              _customEmojiSearchResults[index - _emojiSearchResults.length];
          return GestureDetector(
            key: ValueKey('customEmojiSearch-${item.customEmojiId}'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (item.customEmojiId != 0) {
                EmojiRecentsStore.shared.recordCustom(
                  item.customEmojiId,
                  item.emoji,
                );
                _controller.insertCustomEmoji(item.customEmojiId, item.emoji);
              } else if (item.emoji.isNotEmpty) {
                EmojiRecentsStore.shared.record(item.emoji);
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
      ),
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

  Widget _voicePanel() {
    if (_usesNativeDesktopComposer(context)) return _desktopVoicePanel();
    return _mobileVoicePanel();
  }

  Widget _desktopVoicePanel() {
    final c = context.colors;
    final draft = _desktopVoiceDraft;
    final busy = _startingRecording || _stoppingRecording || _sendingVoice;
    final label = _sendingVoice
        ? AppStrings.t(AppStringKeys.feedbackReportSending)
        : _stoppingRecording
        ? AppStrings.t(AppStringKeys.composerRecordingFinishing)
        : _startingRecording
        ? AppStrings.t(AppStringKeys.composerRecordingPreparing)
        : draft != null
        ? AppStrings.t(AppStringKeys.composerRecordingSendFailed)
        : _recording
        ? AppStrings.t(AppStringKeys.composerDesktopVoiceRelease)
        : AppStrings.t(AppStringKeys.composerDesktopVoiceHoldSpace);
    return Focus(
      focusNode: _desktopVoiceFocus,
      autofocus: true,
      onKeyEvent: _handleDesktopVoiceKeyEvent,
      onFocusChange: (focused) {
        if (!focused && _recording) _cancelVoiceRecording();
      },
      child: Container(
        key: const ValueKey('desktopVoiceMessagePanel'),
        width: double.infinity,
        color: _composerDockedSurfaceColor,
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.t(AppStringKeys.voiceNotePreviewVoiceMessage),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _desktopVoiceAction(
                  key: const ValueKey('desktopVoicePanelClose'),
                  icon: HeroAppIcons.xmark,
                  label: AppStrings.t(AppStringKeys.composerCloseMenu),
                  onTap: _closeDesktopVoicePanel,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    label: label,
                    child: MouseRegion(
                      cursor: busy || draft != null
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.click,
                      child: Listener(
                        key: const ValueKey('desktopVoiceRecordButton'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: _desktopVoicePointerDown,
                        onPointerUp: _desktopVoicePointerUp,
                        onPointerCancel: _desktopVoicePointerCancel,
                        child: Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: c.card,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(
                              color: _recording
                                  ? AppTheme.brand.withValues(alpha: 0.45)
                                  : c.divider,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (busy && !_recording)
                                const AppActivityIndicator(size: 18)
                              else
                                AppIcon(
                                  HeroAppIcons.microphone,
                                  size: 20,
                                  color: _recording
                                      ? AppTheme.brand
                                      : c.textSecondary,
                                ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: SizedBox(
                                  height: 30,
                                  child: ValueListenableBuilder<_RecTick>(
                                    valueListenable: _recTick,
                                    builder: (context, tick, _) =>
                                        DesktopVoiceWaveform(
                                          key: const ValueKey(
                                            'desktopVoiceWaveform',
                                          ),
                                          levels: tick.levels,
                                          color: _recordingPaused
                                              ? c.textTertiary
                                              : AppTheme.brand,
                                          baselineColor: c.textTertiary
                                              .withValues(alpha: 0.3),
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              ValueListenableBuilder<_RecTick>(
                                valueListenable: _recTick,
                                builder: (context, tick, _) => Text(
                                  formatMediaDuration(tick.elapsed.floor()),
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 14,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (draft != null) ...[
                  const SizedBox(width: 8),
                  _desktopVoiceAction(
                    key: const ValueKey('desktopVoiceDiscard'),
                    icon: HeroAppIcons.trash,
                    label: AppStrings.t(AppStringKeys.composerRecordingDiscard),
                    onTap: busy ? null : _discardDesktopVoiceDraft,
                  ),
                  _desktopVoiceAction(
                    key: const ValueKey('desktopVoiceRetrySend'),
                    icon: HeroAppIcons.paperPlane,
                    label: AppStrings.t(AppStringKeys.composerSend),
                    onTap: busy
                        ? null
                        : () => unawaited(_sendDesktopVoiceDraft()),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: draft != null && !_sendingVoice
                    ? AppTheme.tagRed
                    : c.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _desktopVoiceAction({
    required Key key,
    required AppIconData icon,
    required String label,
    required VoidCallback? onTap,
  }) => AppInteractiveSurface(
    key: key,
    semanticLabel: label,
    onTap: onTap,
    enabled: onTap != null,
    borderRadius: BorderRadius.circular(AppRadius.control),
    child: SizedBox.square(
      dimension: 36,
      child: Center(
        child: AppIcon(
          icon,
          size: 18,
          color: onTap != null
              ? context.colors.textSecondary
              : context.colors.textTertiary,
        ),
      ),
    ),
  );

  /// Fixed slots inside the 318pt panel, so nothing moves between states:

  /// switcher 8–42, status line 82–126, record button 142–226 (centre 184,

  /// halo 128–240), helper line centred on 260.

  Widget _mobileVoicePanel() {
    final recordingBusy =
        _recording || _startingRecording || _stoppingRecording;
    return Container(
      key: const ValueKey('composerMobileVoicePanel'),
      height: 318,
      width: double.infinity,
      color: _composerDockedSurfaceColor,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _composerSegmentSwitcher(
              key: const ValueKey('voicePanelSegments'),
              segments: [
                (
                  key: const ValueKey('voicePanelVoiceMessage'),
                  icon: HeroAppIcons.microphone,
                  label: AppStrings.t(
                    AppStringKeys.voiceNotePreviewVoiceMessage,
                  ),
                  selected: true,
                  onTap: () {},
                ),
                (
                  key: const ValueKey('voicePanelVideoMessage'),
                  icon: HeroAppIcons.solidFileVideo,
                  label: AppStrings.t(
                    AppStringKeys.videoNotePreviewVideoMessage,
                  ),
                  selected: false,
                  onTap: recordingBusy
                      ? null
                      : () {
                          _setPanel(_Panel.none);
                          unawaited(_recordVideoNote());
                        },
                ),
              ],
            ),
          ),
          Positioned(
            top: 82,
            height: 44,
            left: 24,
            right: 24,
            child: _mobileVoiceStatusLine(),
          ),
          Positioned(
            // The 112pt halo's box, centred on the record button.
            top: 128,
            height: 112,
            left: 0,
            right: 0,
            child: _mobileVoiceRecordControls(),
          ),
          Positioned(
            // The 242–278 helper slot, grown by 4pt each way so the Settings
            // button keeps a 44pt hit area; its text stays centred on 260.
            top: 238,
            height: 44,
            left: 24,
            right: 24,
            child: _mobileVoiceHelperLine(),
          ),
        ],
      ),
    );
  }

  /// The error the mobile panel shows, if any. A live recording always keeps

  /// its timer and waveform.

  _VoiceInlineError get _visibleVoiceInlineError =>
      _recording ? _VoiceInlineError.none : _voiceInlineError;

  Widget _mobileVoiceStatusLine() {
    final c = context.colors;
    Widget message(String key) => Text(
      AppStrings.t(key),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: c.textSecondary,
      ),
    );
    // The icon leads the first line inside the text, so a message that wraps
    // stays one centred block. Red stays on the icon: tagRed text on the
    // light panel is below 4.5:1 at 14pt.
    Widget error(AppIconData icon, String key) => Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 6),
              child: AppIcon(icon, size: 18, color: AppTheme.tagRed),
            ),
          ),
          TextSpan(text: AppStrings.t(key)),
        ],
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        height: 18 / 14,
        fontWeight: FontWeight.w500,
        color: c.textPrimary,
      ),
    );
    final content = _recording
        // The record button reports the elapsed time; a live region reading
        // every tick of the timer would talk over everything else.
        ? ExcludeSemantics(child: _mobileVoiceRecordingRow())
        : _composerAttachmentWaiting
        ? message(AppStringKeys.composerAttachmentWaiting)
        : switch (_visibleVoiceInlineError) {
            _VoiceInlineError.failed => error(
              HeroAppIcons.triangleExclamation,
              AppStringKeys.composerRecordingFailed,
            ),
            _VoiceInlineError.microphoneRequired => error(
              HeroAppIcons.microphoneSlash,
              AppStringKeys.composerMicrophonePermissionRequired,
            ),
            _VoiceInlineError.microphoneSettings => error(
              HeroAppIcons.microphoneSlash,
              AppStringKeys.composerMicrophonePermissionSettings,
            ),
            _VoiceInlineError.none => message(
              _stoppingRecording
                  ? AppStringKeys.composerRecordingFinishing
                  : _startingRecording
                  ? AppStringKeys.composerRecordingPreparing
                  : AppStringKeys.composerHoldToTalk,
            ),
          };
    // A live region, so VoiceOver reads an error as soon as it appears.
    return Semantics(
      container: true,
      liveRegion: true,
      child: Center(child: content),
    );
  }

  /// The live recording's status row: the timer on the panel's centre line,

  /// the red dot to its left balanced by a blank on its right, and the newest

  /// meter levels mirrored on both sides, newest next to the timer.

  Widget _mobileVoiceRecordingRow() {
    final c = context.colors;
    final paused = _recordingPaused;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Widget meter(List<double> levels, {required bool mirrored}) {
      final empty = _mobileMeterBars - levels.length;
      final bars = <Widget>[
        for (var index = 0; index < _mobileMeterBars; index++)
          if (index < empty)
            _mobileMeterBar(4, c.textTertiary)
          else
            _mobileMeterBar(
              4 + (levels[index - empty].clamp(-60.0, 0.0) + 60) / 60 * 24,
              paused ? c.textTertiary : AppTheme.brand,
            ),
      ];
      final ordered = mirrored ? bars.reversed.toList() : bars;
      return SizedBox(
        width: 62,
        height: 28,
        child: Row(
          children: [
            for (var index = 0; index < ordered.length; index++) ...[
              if (index > 0) const SizedBox(width: 2),
              ordered[index],
            ],
          ],
        ),
      );
    }

    return ValueListenableBuilder<_RecTick>(
      valueListenable: _recTick,
      builder: (context, tick, _) {
        final levels = tick.levels.length > _mobileMeterBars
            ? tick.levels.sublist(tick.levels.length - _mobileMeterBars)
            : tick.levels;
        return Directionality(
          // Mirrored around the record button's centre in every locale.
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              meter(levels, mirrored: false),
              const SizedBox(width: 12),
              _RecordingDot(
                color: paused ? c.textTertiary : AppTheme.tagRed,
                blinking: !paused && !reduceMotion,
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 56,
                child: Text(
                  formatMediaDuration(tick.elapsed.floor()),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: paused ? c.textSecondary : c.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // Balances the dot so the timer, not the dot and timer, sits
              // on the centre line.
              const SizedBox(width: 6 + 8),
              const SizedBox(width: 12),
              meter(levels, mirrored: true),
            ],
          ),
        );
      },
    );
  }

  static const _mobileMeterBars = 16;

  Widget _mobileMeterBar(double height, Color color) => SizedBox(
    width: 2,
    height: 28,
    child: Center(
      child: Container(
        width: 2,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    ),
  );

  Widget _mobileVoiceRecordControls() {
    final c = context.colors;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final motion = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 150);
    final locked = _recording && _recordingLocked;
    final held = _recording && !_recordingLocked;
    final cancelZone = held && _recordCancelled;
    // A draft or pasted pictures already wait: send or remove them first.
    final blocked = !_recording && _composerAttachmentWaiting;
    final busy =
        !_recording &&
        _visibleVoiceInlineError == _VoiceInlineError.none &&
        (_startingRecording || _stoppingRecording);
    final accent = cancelZone ? AppTheme.tagRed : AppTheme.brand;
    final Widget glyph = busy
        ? AppActivityIndicator(size: 24, color: c.onAccent)
        : cancelZone
        ? AppIcon(HeroAppIcons.trash, size: 30, color: c.onAccent)
        : locked
        ? AppIcon(HeroAppIcons.solidStop, size: 26, color: c.onAccent)
        : AppIcon(HeroAppIcons.microphone, size: 32, color: c.onAccent);
    final button = Listener(
      key: const ValueKey('mobileVoiceRecordButton'),
      onPointerDown: (e) {
        if (_recording && _recordingLocked) {
          // Tapping the locked button stops and leaves the recording as a
          // draft; it never starts another recording.
          if (_voiceStop == null && _lockedStopPointerId == null) {
            _lockedStopPointerId = e.pointer;
            _lockedStopDownPosition = e.position;
          }
          return;
        }
        if (_recording || _voiceStop != null || _mobilePointerHeld) {
          return;
        }
        _clearVoiceInlineError();
        _voicePointerId = e.pointer;
        _mobilePointerHeld = true;
        _pressStartX = e.position.dx;
        _pressStartY = e.position.dy;
        unawaited(_beginVoiceRecording());
      },
      onPointerMove: (e) {
        if (_lockedStopPointerId == e.pointer) {
          // A drag is not a tap.
          if ((e.position - _lockedStopDownPosition).distance > kTouchSlop) {
            _lockedStopPointerId = null;
          }
          return;
        }
        if (_voicePointerId != e.pointer || _recordingLocked) return;
        final cancel = e.position.dx - _pressStartX < -70;
        final lock = _recording && e.position.dy - _pressStartY < -70;
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
      onPointerUp: (e) {
        if (_lockedStopPointerId == e.pointer) {
          _lockedStopPointerId = null;
          if (_recording && _recordingLocked) unawaited(_stopRec());
          return;
        }
        if (_voicePointerId != e.pointer) return;
        _voicePointerId = null;
        _mobilePointerHeld = false;
        if (!_recordingLocked) unawaited(_stopRec());
      },
      onPointerCancel: (e) {
        if (_lockedStopPointerId == e.pointer) {
          _lockedStopPointerId = null;
          return;
        }
        if (_voicePointerId == e.pointer) _cancelVoiceRecording();
      },
      child: AnimatedScale(
        scale: held ? 1.12 : 1,
        duration: motion,
        child: Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          child: glyph,
        ),
      ),
    );
    return SizedBox(
      width: double.infinity,
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: held && !blocked ? 1 : 0,
              duration: motion,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: dark ? 0.24 : 0.16),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          ValueListenableBuilder<_RecTick>(
            valueListenable: _recTick,
            child: IgnorePointer(
              ignoring: blocked,
              child: AnimatedOpacity(
                opacity: blocked ? 0.4 : 1,
                duration: motion,
                child: button,
              ),
            ),
            builder: (context, tick, child) => Semantics(
              button: true,
              enabled: blocked ? false : null,
              label: AppStrings.t(
                locked
                    ? AppStringKeys.composerRecordingStop
                    : AppStringKeys.composerHoldToTalk,
              ),
              value: _recording
                  ? formatMediaDuration(tick.elapsed.floor())
                  : null,
              onTap: locked ? () => unawaited(_stopRec()) : null,
              excludeSemantics: true,
              child: child,
            ),
          ),
          // Side buttons sit 28pt off the button's edge (centres ±92pt), in
          // the same stack, so they never shift the record button.
          if (locked) ...[
            Transform.translate(
              offset: const Offset(-92, 0),
              child: _mobileVoiceSideButton(
                key: const ValueKey('mobileVoiceDiscard'),
                icon: HeroAppIcons.trash,
                color: AppTheme.tagRed,
                label: AppStrings.t(AppStringKeys.composerRecordingDiscard),
                onTap: _cancelLockedRecording,
              ),
            ),
            Transform.translate(
              offset: const Offset(92, 0),
              child: _mobileVoiceSideButton(
                key: const ValueKey('mobileVoicePauseResume'),
                icon: _recordingPaused
                    ? HeroAppIcons.solidPlay
                    : HeroAppIcons.solidPause,
                color: AppTheme.brand,
                label: AppStrings.t(
                  _recordingPaused
                      ? AppStringKeys.composerRecordingResume
                      : AppStringKeys.musicPlayerPause,
                ),
                onTap: () => unawaited(_toggleRecPause()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _mobileVoiceSideButton({
    required Key key,
    required AppIconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) => AppInteractiveSurface(
    key: key,
    semanticLabel: label,
    onTap: onTap,
    borderRadius: BorderRadius.circular(22),
    child: Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: AppIcon(icon, size: 20, color: color),
    ),
  );

  Widget _mobileVoiceHelperLine() {
    final c = context.colors;
    if (_visibleVoiceInlineError == _VoiceInlineError.microphoneSettings) {
      // Settings opens only on this press, never on its own.
      return Center(
        child: AppInteractiveSurface(
          key: const ValueKey('mobileVoiceOpenSettings'),
          semanticLabel: AppStrings.t(AppStringKeys.storyOpenSettings),
          onTap: () => unawaited(openAppSettings()),
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                widthFactor: 1,
                child: Text(
                  AppStrings.t(AppStringKeys.storyOpenSettings),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.brand,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (!_recording || _composerAttachmentWaiting) {
      return const SizedBox.shrink();
    }
    final cancelZone = !_recordingLocked && _recordCancelled;
    final key = _recordingLocked
        ? (_recordingPaused
              ? AppStringKeys.composerRecordingPaused
              : AppStringKeys.composerRecordingLocked)
        : cancelZone
        ? AppStringKeys.composerReleaseFingerToCancel
        : AppStringKeys.composerRecordingReleasePreview;
    return Center(
      child: Text(
        AppStrings.t(key),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: cancelZone ? FontWeight.w600 : FontWeight.w400,
          color: cancelZone ? c.textPrimary : c.textSecondary,
        ),
      ),
    );
  }

  Future<void> _sendStickerItem(
    StickerItem item, {
    MessageSendConfiguration? config,
  }) async {
    widget.onMediaSendTapped?.call();
    final sent = await widget.vm.sendSticker(item, sendConfiguration: config);
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

  Future<void> _sendGifItem(
    GifItem item, {
    MessageSendConfiguration? config,
  }) async {
    widget.onMediaSendTapped?.call();
    final sent = await widget.vm.sendGif(item, sendConfiguration: config);
    if (!mounted) return;
    if (sent) {
      _finishPanelSend();
    } else {
      showToast(context, AppStrings.t(AppStringKeys.composerGifSendFailed));
    }
  }

  /// Long-press haptic matching the emoji cell's pattern: a light selection

  /// tick on touch platforms only.

  void _mediaTileLongPressHaptic() {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  /// The composer side of the media-tile action sheet: descriptor plus the

  /// actions each row performs. A row the caller passes null for is hidden.

  void _showStickerTileActions(StickerItem item, {required bool isRecentTile}) {
    _mediaTileLongPressHaptic();
    unawaited(
      showMediaTileActionSheet(
        context,
        MediaTileDescriptor.sticker(
          item,
          FavoriteStickerStore.shared.isFavorite(item.id),
          isRecentTile,
        ),
        MediaTileActions(
          send: () => unawaited(_sendStickerItem(item)),
          sendWithoutSound: () => unawaited(
            _sendStickerItem(
              item,
              config: const MessageSendConfiguration(disableNotification: true),
            ),
          ),
          schedule: () => unawaited(_scheduleStickerSend(item)),
          toggleFavorite: () => unawaited(_toggleStickerFavorite(item)),
          viewSet: () => _openStickerSet(item.setId),
          save: () => unawaited(_exportStickerTile(item)),
          copy: () => unawaited(_copyStickerFile(item)),
          removeFromRecent: isRecentTile
              ? () => widget.vm.removeRecentSticker(item.id)
              : null,
        ),
      ),
    );
  }

  void _showGifTileActions(GifItem item) {
    _mediaTileLongPressHaptic();
    unawaited(
      showMediaTileActionSheet(
        context,
        MediaTileDescriptor.gif(item, false),
        MediaTileActions(
          send: () => unawaited(_sendGifItem(item)),
          sendWithoutSound: () => unawaited(
            _sendGifItem(
              item,
              config: const MessageSendConfiguration(disableNotification: true),
            ),
          ),
          schedule: () => unawaited(_scheduleGifSend(item)),
          save: () => unawaited(_saveGifTile(item)),
        ),
      ),
    );
  }

  /// The tile menu's Schedule: the same owned picker the send-options sheet

  /// opens, pre-armed to send this sticker once a future date is confirmed.

  Future<void> _scheduleStickerSend(StickerItem item) async {
    final config = await _pickTileScheduleConfiguration();
    if (config == null) return;
    await _sendStickerItem(item, config: config);
  }

  Future<void> _scheduleGifSend(GifItem item) async {
    final config = await _pickTileScheduleConfiguration();
    if (config == null) return;
    await _sendGifItem(item, config: config);
  }

  /// Opens the app's owned schedule picker (the one showMessageSendOptionsSheet

  /// uses) and turns the picked date into a send configuration.

  Future<MessageSendConfiguration?> _pickTileScheduleConfiguration() async {
    final now = DateTime.now();
    final selected = await showOwnedSchedulePicker(
      context: context,
      initial: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 366)),
    );
    if (selected == null || !selected.isAfter(now)) return null;
    return MessageSendConfiguration(scheduleAt: selected);
  }

  Future<void> _toggleStickerFavorite(StickerItem item) async {
    final store = FavoriteStickerStore.shared;
    if (store.isFavorite(item.id)) {
      await store.remove(item);
    } else {
      await store.add(item);
    }
  }

  void _openStickerSet(int setId) {
    if (setId == 0) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.stickerSetDetailActionFailed),
      );
      return;
    }
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => StickerSetDetailView(setId: setId),
        ),
      ),
    );
  }

  /// Save/export a panel sticker tile. There is no message to anchor on, so

  /// the tile's file is wrapped in a synthetic one the way the set export

  /// already wraps set entries internally.

  Future<void> _exportStickerTile(StickerItem item) async {
    final file = TdFileRef(id: item.id);
    final message = ChatMessage(
      id: item.id,
      isOutgoing: false,
      text: '',
      date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      image: item.isAnimated || item.isVideo ? null : file,
      animatedSticker: item.isAnimated ? file : null,
      videoSticker: item.isVideo ? file : null,
    );
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    final result = await StickerExportService.export(
      message,
      format: StickerExportFormat.png,
      destination: desktop
          ? StickerExportDestination.files
          : StickerExportDestination.photos,
    );
    if (!mounted) return;
    if (result != StickerExportResult.cancelled) {
      showToast(
        context,
        AppStrings.t(
          result == StickerExportResult.saved
              ? (desktop
                    ? AppStringKeys.stickerExportSavedToFiles
                    : AppStringKeys.chatSavedToPhotos)
              : result == StickerExportResult.permissionDenied
              ? AppStringKeys.chatSaveToPhotosPermissionDenied
              : AppStringKeys.stickerExportFailed,
        ),
      );
    }
  }

  /// Desktop webp sticker copy: puts the resolved local file path on the

  /// clipboard. The sheet gates the row to static desktop stickers; a vanished

  /// file reports instead of throwing into the zone.

  Future<void> _copyStickerFile(StickerItem item) async {
    try {
      final path = await TdFileCenter.shared.pathFor(
        item.thumb ?? TdFileRef(id: item.id),
      );
      if (path == null || path.isEmpty) throw StateError('no local file');
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) return;
      showToast(context, AppStrings.t(AppStringKeys.profileDetailCopied));
    } catch (_) {
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.stickerSetDetailActionFailed),
      );
    }
  }

  /// Save a panel GIF tile. Mobile adds the downloaded mp4 to the photo

  /// library like a chat GIF message; a desktop host has no album, so the

  /// file goes through the same save panel MediaDownloadService already

  /// uses for chat media.

  Future<void> _saveGifTile(GifItem item) async {
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
    if (desktop) {
      final outcome = await MediaDownloadService.saveMedia(
        file: item.file,
        isVideo: true,
      );
      if (!mounted) return;
      final feedback = MediaDownloadService.feedbackFor(outcome);
      if (feedback != null) showToast(context, feedback);
      return;
    }
    try {
      final path = await TdFileCenter.shared.pathFor(item.file);
      if (path == null || path.isEmpty) {
        throw StateError('no local file');
      }
      final file = File(path);
      if (!await file.exists()) throw StateError('file missing');
      final result = await MediaLibrarySaver.savePreparedFile(
        file,
        isVideo: true,
      );
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(switch (result) {
          MediaLibrarySaveResult.saved => AppStringKeys.chatSavedToPhotos,
          MediaLibrarySaveResult.permissionDenied =>
            AppStringKeys.chatSaveToPhotosPermissionDenied,
          MediaLibrarySaveResult.unsupported ||
          MediaLibrarySaveResult.failed => AppStringKeys.chatSaveToPhotosFailed,
        }),
      );
    } catch (_) {
      if (!mounted) return;
      showToast(context, AppStrings.t(AppStringKeys.chatSaveToPhotosFailed));
    }
  }

  Widget _stickerSearchContent() {
    if (_panelSearch.text.trim().isEmpty) return const SizedBox.shrink();
    if (_stickerSearchResults.isEmpty) {
      return _panelSearchState();
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: _stickerSearchResults.length,
      itemBuilder: (context, index) =>
          _stickerTile(_stickerSearchResults[index], search: true),
    );
  }

  Widget _stickerTile(
    StickerItem item, {
    bool search = false,
    bool recent = false,
  }) => GestureDetector(
    key: ValueKey(search ? 'stickerSearch-${item.id}' : 'sticker-${item.id}'),
    behavior: HitTestBehavior.opaque,
    onTap: () => unawaited(_sendStickerItem(item)),
    // Search results are not recents, so only the pack grid passes
    // recent: true; favorites tiles know their state through the store.
    onLongPress: () => _showStickerTileActions(item, isRecentTile: recent),
    child: StickerPreview(item: item),
  );

  Widget _gifTile(GifItem item, {bool search = false}) => GestureDetector(
    key: ValueKey(search ? 'gifSearch-${item.id}' : 'gif-${item.id}'),
    behavior: HitTestBehavior.opaque,
    onTap: () => unawaited(_sendGifItem(item)),
    onLongPress: () => _showGifTileActions(item),
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

  // Kept for re-exposing the studio from a more appropriate surface later.

  // ignore: unused_element
}
