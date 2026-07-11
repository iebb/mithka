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

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/icon_grid.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../media/app_asset_picker.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'audio_search_view.dart';
import 'chat_view_model.dart';
import 'checklist_composer_view.dart';
import 'custom_emoji.dart';
import 'emoji_catalog.dart';
import 'emoji_store.dart';
import 'emoji_text_controller.dart';
import 'gif_preview.dart';
import 'gif_store.dart';
import 'image_edit_view.dart';
import 'link_handler.dart';
import 'location_picker_view.dart';
import 'media_send_preview_view.dart';
import 'outgoing_attachment.dart';
import 'poll_composer_view.dart';
import 'rich_text_composer_view.dart';
import 'sticker_preview.dart';
import 'sticker_store.dart';

enum _Panel { none, function, emoji, sticker, voice }

enum _ClipboardImageAction { cancel, edit, richText, send }

typedef _ClipboardImage = ({Uint8List data, String mimeType});

class _SendComposerIntent extends Intent {
  const _SendComposerIntent();
}

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.vm,
    required this.onStartCall,
    required this.onMessageSent,
  });
  final ChatViewModel vm;
  final FutureOr<void> Function(bool isVideo) onStartCall;
  final VoidCallback onMessageSent;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  static const _clipboardChannel = MethodChannel('mithka/clipboard');
  static const _gifTabId = -2;
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
  _Panel _panel = _Panel.none;
  String _emojiTab = 'standard'; // 'standard' or a custom-emoji pack id
  int? _stickerPack; // active sticker pack id

  // Voice recording (flutter_sound, Opus).
  FlutterSoundRecorder? _recorder;
  bool _recording = false;
  bool _recordCancelled = false;
  double _elapsed = 0;
  double _pressStartY = 0;
  Timer? _recTimer;
  String? _recPath;
  late bool _hasText = vm.draft.trim().isNotEmpty;

  ChatViewModel get vm => widget.vm;

  @override
  void initState() {
    super.initState();
    _controller.text = vm.draft;
    _controller.addListener(_onTextChanged);
    _focus.addListener(() {
      var needsRebuild = false;
      if (_focus.hasFocus && _panel != _Panel.none) {
        _panel = _Panel.none;
        needsRebuild = true;
      }
      if (needsRebuild && mounted) setState(() {});
    });
    vm.addListener(_syncFromVm);
    EmojiStore.shared.addListener(_onStore);
    StickerStore.shared.addListener(_onStore);
    GifStore.shared.addListener(_onStore);
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  DateTime? _lastTyping;
  void _onTextChanged() {
    final (text, entities) = _controller.toFormatted();
    vm.setDraft(_controller.text, formattedText: text, entities: entities);
    // setDraft doesn't notify (it would rebuild the whole chat per keystroke), so
    // rebuild just the composer here — otherwise `hasText` stays stale and the
    // send button never appears while typing.
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      _hasText = hasText;
      if (mounted) setState(() {});
    }
    final now = DateTime.now();
    if (_controller.text.isNotEmpty &&
        (_lastTyping == null || now.difference(_lastTyping!).inSeconds >= 4)) {
      _lastTyping = now;
      vm.sendTyping();
    }
  }

  void _syncFromVm() {
    final composing = _controller.value.composing;
    final editing = _focus.hasFocus || composing.isValid;
    if (!editing && vm.draft != _controller.text) {
      _controller.value = TextEditingValue(
        text: vm.draft,
        selection: TextSelection.collapsed(offset: vm.draft.length),
      );
    }
    _hasText = _controller.text.trim().isNotEmpty;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    vm.removeListener(_syncFromVm);
    EmojiStore.shared.removeListener(_onStore);
    StickerStore.shared.removeListener(_onStore);
    GifStore.shared.removeListener(_onStore);
    _controller.dispose();
    _focus.dispose();
    _recTimer?.cancel();
    _recorder?.closeRecorder();
    super.dispose();
  }

  // MARK: - Voice recording

  void _toggleVoice() {
    _focus.unfocus();
    setState(
      () => _panel = _panel == _Panel.voice ? _Panel.none : _Panel.voice,
    );
    if (_panel == _Panel.voice) _prepareRecorder();
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
    _elapsed = 0;
    try {
      await r.startRecorder(toFile: _recPath, codec: codec, sampleRate: 48000);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _recording = true);
    _recTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() => _elapsed += 0.1);
    });
  }

  Future<void> _stopRec() async {
    final r = _recorder;
    _recTimer?.cancel();
    _recTimer = null;
    if (r == null || !_recording) return;
    final secs = _elapsed.round();
    final cancelled = _recordCancelled;
    String? url;
    try {
      url = await r.stopRecorder();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _recording = false);
    if (cancelled || secs < 1 || url == null) return;
    vm.sendVoice(url, secs);
    widget.onMessageSent();
    setState(() => _panel = _Panel.none);
  }

  static String _recTime(double seconds) {
    final s = seconds.floor();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  void _toggle(_Panel panel) {
    _focus.unfocus();
    setState(() => _panel = _panel == panel ? _Panel.none : panel);
  }

  void _pickFailed(String what) {
    setState(() => _panel = _Panel.none);
    showToast(
      context,
      AppStrings.t(AppStringKeys.composerOpenAttachmentFailed, {
        'value1': what,
      }),
    );
  }

  Future<void> _sendCurrentText() async {
    if (_controller.text.trim().isEmpty) return;
    if (vm.requiresPaidMessage) {
      final ok = await confirmDialog(
        context,
        title: AppStrings.t(AppStringKeys.composerSendPaidMessageQuestion),
        message: AppStrings.t(AppStringKeys.composerPaidMessageCost, {
          'value1': vm.paidMessageStarCount,
        }),
        confirmText: AppStrings.t(AppStringKeys.composerSend),
      );
      if (!mounted || !ok) return;
    }
    final (text, entities) = _controller.toFormatted();
    vm.sendFormatted(text, entities);
    widget.onMessageSent();
    _controller.clear();
    _focus.requestFocus();
  }

  Future<void> _openRichTextComposer() async {
    final result = await showRichTextComposerSheet(
      context,
      initialText: _controller.text,
      title: AppStringKeys.composerRichTextMessageTitle,
      submitText: AppStringKeys.composerSend,
    );
    if (result == null || !mounted) return;
    if (result.text.trim().isEmpty && result.attachments.isEmpty) return;
    if (vm.requiresPaidMessage) {
      final ok = await confirmDialog(
        context,
        title: AppStrings.t(AppStringKeys.composerSendPaidMessageQuestion),
        message: AppStrings.t(AppStringKeys.composerPaidMessageCost, {
          'value1': vm.paidMessageStarCount,
        }),
        confirmText: AppStrings.t(AppStringKeys.composerSend),
      );
      if (!mounted || !ok) return;
    }
    await _sendRichTextResult(result);
  }

  Future<void> _handlePaste([ContextMenuButtonItem? pasteItem]) async {
    final image = await _readClipboardImage();
    if (image != null) {
      _focus.unfocus();
      await _handlePastedImage(image.data, image.mimeType);
      _restoreKeyboardFocus();
      return;
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

  void _restoreKeyboardFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: c.inputBarBackground,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (vm.replyTo != null) _replyBanner(vm.replyTo!),
            _inputRow(),
            _iconStrip(),
            if (_panel == _Panel.function) _functionPanel(),
            if (_panel == _Panel.emoji) _emojiPanel(),
            if (_panel == _Panel.sticker) _stickerPanel(),
            if (_panel == _Panel.voice) _voicePanel(),
          ],
        ),
      ),
    );
  }

  // MARK: - Reply banner

  Widget _replyBanner(ChatMessage m) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 8),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(8),
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
      return telegramText(AppStringKeys.composerVoicePreview);
    }
    if (m.location != null) {
      return telegramText(AppStringKeys.composerLocationPreview);
    }
    if (m.isDice) {
      return m.diceEmoji ?? m.text;
    }
    if (m.isAnimatedEmoji) {
      return m.text;
    }
    if (m.animatedSticker != null) {
      return telegramText(AppStringKeys.composerAnimatedEmojiPreview);
    }
    if (m.image != null) {
      return m.text.isEmpty
          ? telegramText(AppStringKeys.composerImagePreview)
          : m.text;
    }
    return m.text;
  }

  // MARK: - Input row

  void _showSenderPicker() {
    final options = vm.availableMessageSenders;
    if (options.length <= 1) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
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

  void _showBotMenu() {
    final commands = vm.botCommands;
    final menu = vm.botMenu;
    if ((menu?.isWebApp ?? false) && commands.isEmpty) {
      unawaited(openLink(context, menu!.url));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                if (menu?.isWebApp ?? false) ...[
                  _botMenuRow(
                    icon: HeroAppIcons.tableCells.data,
                    title: menu!.text.isEmpty
                        ? AppStrings.t(AppStringKeys.composerOpenMenu)
                        : menu.text,
                    subtitle: menu.url,
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(openLink(context, menu.url));
                    },
                  ),
                  if (commands.isNotEmpty) const InsetDivider(leadingInset: 56),
                ],
                for (var i = 0; i < commands.length; i++) ...[
                  _botMenuRow(
                    icon: HeroAppIcons.ban.data,
                    title: '/${commands[i].command}',
                    subtitle: commands[i].description,
                    onTap: () {
                      Navigator.of(context).pop();
                      _insertBotCommand(commands[i].command);
                    },
                  ),
                  if (i < commands.length - 1)
                    const InsetDivider(leadingInset: 56),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _botMenuRow({
    required IconData icon,
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
              Icon(icon, size: 22, color: AppTheme.brand),
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

  Widget _senderOptionRow(MessageSenderOption option) {
    final c = context.colors;
    final selected =
        vm.selectedMessageSender?.sameSender(option.sender) == true;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: option.needsPremium
          ? null
          : () {
              Navigator.of(context).pop();
              vm.selectMessageSender(option);
            },
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              PhotoAvatar(title: option.title, photo: option.photo, size: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ),
              if (option.needsPremium)
                Text(
                  AppStringKeys.premiumLabel.l10n(context),
                  style: TextStyle(fontSize: 13, color: AppTheme.brand),
                )
              else if (selected)
                AppIcon(HeroAppIcons.check, size: 18, color: AppTheme.brand),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputRow() {
    final c = context.colors;
    final hasText = _hasText;
    final sender = vm.selectedMessageSender;
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (vm.peerIsBot &&
              (vm.botCommands.isNotEmpty ||
                  (vm.botMenu?.isWebApp ?? false))) ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _showBotMenu,
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: c.searchFill,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: AppIcon(
                  HeroAppIcons.tableCells,
                  size: 20,
                  color: c.textSecondary,
                ),
              ),
            ),
          ],
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(18),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  if (vm.canChooseMessageSender && sender != null) ...[
                    GestureDetector(
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
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.enter):
                            _SendComposerIntent(),
                        SingleActivator(LogicalKeyboardKey.numpadEnter):
                            _SendComposerIntent(),
                      },
                      child: Actions(
                        actions: {
                          _SendComposerIntent:
                              CallbackAction<_SendComposerIntent>(
                                onInvoke: (_) {
                                  unawaited(_sendCurrentText());
                                  return null;
                                },
                              ),
                        },
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 4,
                          keyboardType: TextInputType.multiline,
                          textInputAction: Platform.isIOS
                              ? TextInputAction.newline
                              : TextInputAction.send,
                          onSubmitted: Platform.isIOS
                              ? null
                              : (_) => unawaited(_sendCurrentText()),
                          style: TextStyle(fontSize: 16, color: c.textPrimary),
                          contentInsertionConfiguration:
                              ContentInsertionConfiguration(
                                allowedMimeTypes: _imageMimeTypes,
                                onContentInserted: _handleInsertedContent,
                              ),
                          contextMenuBuilder:
                              (
                                BuildContext context,
                                EditableTextState editableTextState,
                              ) {
                                var hasPasteAction = false;
                                final items = editableTextState
                                    .contextMenuButtonItems
                                    .map((item) {
                                      if (item.type !=
                                          ContextMenuButtonType.paste) {
                                        return item;
                                      }
                                      hasPasteAction = true;
                                      return ContextMenuButtonItem(
                                        type: item.type,
                                        label: item.label,
                                        onPressed: () =>
                                            unawaited(_handlePaste(item)),
                                      );
                                    })
                                    .toList();
                                if (!hasPasteAction) {
                                  items.add(
                                    ContextMenuButtonItem(
                                      type: ContextMenuButtonType.paste,
                                      label: AppStringKeys
                                          .accountBackupLoadPyrogramPaste
                                          .l10n(context),
                                      onPressed: () =>
                                          unawaited(_handlePaste()),
                                    ),
                                  );
                                }
                                return AdaptiveTextSelectionToolbar.buttonItems(
                                  anchors: editableTextState.contextMenuAnchors,
                                  buttonItems: items,
                                );
                              },
                          decoration: InputDecoration(
                            hintText: vm.inputPlaceholder,
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (hasText) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => unawaited(_sendCurrentText()),
              child: Container(
                width: vm.requiresPaidMessage ? 58 : 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  shape: BoxShape.circle,
                ),
                child: vm.requiresPaidMessage
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
        ],
      ),
    );
  }

  // MARK: - Icon strip

  Widget _iconStrip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          _icon(
            HeroAppIcons.microphone.data,
            _panel == _Panel.voice,
            _toggleVoice,
          ),
          _icon(HeroAppIcons.image.data, false, _pickPhotos),
          _icon(HeroAppIcons.camera.data, false, _takePhoto),
          _icon(HeroAppIcons.grip.data, _panel == _Panel.sticker, () {
            _toggle(_Panel.sticker);
            if (_panel == _Panel.sticker) {
              StickerStore.shared.loadIfNeeded();
              GifStore.shared.loadIfNeeded();
            }
          }),
          _icon(HeroAppIcons.solidFaceSmile.data, _panel == _Panel.emoji, () {
            _toggle(_Panel.emoji);
            if (_panel == _Panel.emoji) EmojiStore.shared.loadIfNeeded();
          }),
          _icon(
            _panel != _Panel.none
                ? HeroAppIcons.xmark.data
                : HeroAppIcons.circlePlus.data,
            _panel == _Panel.function,
            () => _toggle(_Panel.function),
          ),
        ],
      ),
    );
  }

  Widget _icon(IconData name, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Icon(
          name,
          size: 24,
          color: active ? AppTheme.brand : context.colors.textSecondary,
        ),
      ),
    );
  }

  // MARK: - Media pickers

  /// 图片: pick one or more photos/videos and preserve their album order.
  Future<void> _pickPhotos() async {
    try {
      final selection = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.imageAndVideo,
        maxAssets: 10,
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
            final kind = isPickedAssetVideo(file)
                ? OutgoingAttachmentKind.video
                : isPickedAssetGif(file)
                ? OutgoingAttachmentKind.animation
                : OutgoingAttachmentKind.photo;
            return OutgoingAttachment(
              path: file.path,
              kind: kind,
              previewBytes: asset.thumbnailBytes,
            );
          })
          .toList(growable: false);
      if (attachments.isEmpty) return;
      final preview = await Navigator.of(context).push<MediaSendPreviewResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MediaSendPreviewView(attachments: attachments),
        ),
      );
      if (!mounted || preview == null || preview.attachments.isEmpty) return;
      await widget.vm.sendAttachments(
        preview.attachments,
        caption: preview.caption,
      );
      widget.onMessageSent();
    } catch (error, stackTrace) {
      debugPrint('Failed to send selected media: $error\n$stackTrace');
      _pickFailed(AppStrings.t(AppStringKeys.composerImage));
    }
  }

  /// 相机: capture a photo and send it.
  Future<void> _takePhoto() async {
    try {
      final shot = await ImagePicker().pickImage(source: ImageSource.camera);
      if (shot == null) return;
      final edited = await _editImage(shot.path);
      if (edited != null) {
        widget.vm.sendPhoto(edited.path, caption: edited.caption);
        widget.onMessageSent();
      }
    } catch (_) {
      _pickFailed(AppStrings.t(AppStringKeys.composerCamera));
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
    final data = content.data;
    if (data == null || data.isEmpty) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.composerPastedImageReadFailed),
        );
      }
      return;
    }
    _focus.unfocus();
    await _handlePastedImage(data, content.mimeType);
    _restoreKeyboardFocus();
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

  Future<void> _handlePastedImage(Uint8List data, String mimeType) async {
    final dir = await getTemporaryDirectory();
    final ext = _extensionForMime(mimeType);
    final file = File(
      '${dir.path}/mithka-paste-${DateTime.now().microsecondsSinceEpoch}.$ext',
    );
    await file.writeAsBytes(data, flush: true);
    if (!mounted) return;
    var path = file.path;
    var caption = '';
    while (mounted) {
      final action = await _showClipboardImagePreview(path, caption);
      if (!mounted ||
          action == null ||
          action == _ClipboardImageAction.cancel) {
        return;
      }
      if (action == _ClipboardImageAction.edit) {
        final edited = await _editImage(path, initialCaption: caption);
        if (edited != null) {
          path = edited.path;
          caption = edited.caption;
        }
        continue;
      }
      if (action == _ClipboardImageAction.richText) {
        final result = await showRichTextComposerSheet(
          context,
          initialText: caption,
          initialMedia: [XFile(path)],
          title: AppStringKeys.composerRichTextMessageTitle,
          submitText: AppStringKeys.composerSend,
        );
        if (result != null && mounted) {
          await _sendRichTextResult(result);
        }
        return;
      }
      if (_isGifPath(path)) {
        widget.vm.sendAnimation(path, caption: caption);
      } else {
        widget.vm.sendPhoto(path, caption: caption);
      }
      widget.onMessageSent();
      return;
    }
  }

  Future<_ClipboardImageAction?> _showClipboardImagePreview(
    String path,
    String caption,
  ) {
    return showGeneralDialog<_ClipboardImageAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.black.withValues(alpha: 0.38),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, _) {
        final c = dialogContext.colors;
        final previewHeight = (MediaQuery.sizeOf(dialogContext).height * 0.42)
            .clamp(180.0, 360.0);
        return SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      key: const ValueKey('clipboardImagePreview'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(
                        dialogContext,
                      ).pop(_ClipboardImageAction.edit),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            SizedBox(
                              width: double.infinity,
                              height: previewHeight,
                              child: Image.file(
                                File(path),
                                fit: BoxFit.contain,
                              ),
                            ),
                            Container(
                              width: 34,
                              height: 34,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.58),
                                shape: BoxShape.circle,
                              ),
                              child: const AppIcon(
                                HeroAppIcons.pen,
                                size: 17,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (caption.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            caption,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: c.textPrimary,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    Divider(height: 1, color: c.divider),
                    Row(
                      children: [
                        _clipboardPreviewAction(
                          dialogContext,
                          AppStringKeys.countryPickerCancel.l10n(dialogContext),
                          _ClipboardImageAction.cancel,
                        ),
                        _clipboardPreviewAction(
                          dialogContext,
                          AppStringKeys.composerEditInRichText.l10n(
                            dialogContext,
                          ),
                          _ClipboardImageAction.richText,
                        ),
                        _clipboardPreviewAction(
                          dialogContext,
                          AppStringKeys.composerSend.l10n(dialogContext),
                          _ClipboardImageAction.send,
                          primary: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  Widget _clipboardPreviewAction(
    BuildContext dialogContext,
    String label,
    _ClipboardImageAction action, {
    bool primary = false,
  }) {
    final c = dialogContext.colors;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(dialogContext).pop(action),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
              color: primary ? AppTheme.brand : c.textPrimary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _sendRichTextResult(RichTextComposerResult result) async {
    try {
      if (!await widget.vm.canSendRichMessages()) {
        var sentAny = false;
        if (result.text.trim().isNotEmpty) {
          widget.vm.sendFormatted(result.text, result.entities);
          sentAny = true;
        }
        if (result.attachments.isNotEmpty) {
          await widget.vm.sendAttachments(result.attachments);
          sentAny = true;
        }
        if (!sentAny) return;
        if (mounted) {
          showToast(
            context,
            AppStringKeys.composerRichTextPremiumRequired.l10n(context),
          );
        }
        widget.onMessageSent();
        _controller.clear();
        _focus.requestFocus();
        return;
      }
      var sentAny = false;
      for (final segment in result.segments) {
        if (segment.isHtml) {
          await widget.vm.sendRichMessageHtml(
            segment.html,
            files: segment.richFiles,
          );
          sentAny = true;
        } else if (segment.attachments.isNotEmpty) {
          await widget.vm.sendAttachments(segment.attachments);
          sentAny = true;
        }
      }
      if (!sentAny) return;
      widget.onMessageSent();
      _controller.clear();
      _focus.requestFocus();
    } catch (_) {
      if (mounted) {
        _pickFailed(AppStringKeys.composerRichText.l10n(context));
      }
    }
  }

  String _extensionForMime(String mimeType) {
    switch (mimeType.toLowerCase()) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/heic':
        return 'heic';
      case 'image/heif':
        return 'heif';
      default:
        return 'png';
    }
  }

  bool _isGifPath(String path) => path.toLowerCase().endsWith('.gif');

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
      _pickFailed(telegramText(AppStringKeys.topicPostContentFile));
    }
  }

  /// 位置: open a map picker centred on the GPS fix; send the chosen point.
  Future<void> _sendLocation() async {
    // Fallback centre when location is unavailable — user can pan to choose.
    var start = const LatLng(39.9087, 116.3975);
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition();
        start = LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {}
    if (!mounted) return;
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => LocationPickerView(initial: start)),
    );
    if (picked != null) {
      widget.vm.sendLocation(picked.latitude, picked.longitude);
      widget.onMessageSent();
    }
  }

  /// 投票: collect a question + options and send a poll.
  Future<void> _createPoll() async {
    final result = await Navigator.of(context).push<(String, List<String>)>(
      MaterialPageRoute(builder: (_) => const PollComposerView()),
    );
    if (result == null) return;
    final (question, options) = result;
    if (question.isEmpty || options.length < 2) return;
    widget.vm.sendPoll(question, options);
    widget.onMessageSent();
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
      _pickFailed(telegramText(AppStringKeys.composerAudio));
    }
  }

  /// 音频: search Telegram audio first; local files remain available inside.
  Future<void> _pickAudio() async {
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
    final result = await Navigator.of(context).push<(String, List<String>)>(
      MaterialPageRoute(builder: (_) => const ChecklistComposerView()),
    );
    if (result == null) return;
    final (title, tasks) = result;
    if (title.isEmpty || tasks.isEmpty) return;
    widget.vm.sendChecklist(title, tasks);
    widget.onMessageSent();
  }

  // MARK: - Function panel

  Widget _functionPanel() {
    final items = [
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
        HeroAppIcons.video.data,
        AppStrings.t(
          vm.isGroup
              ? AppStringKeys.composerGroupVideoCall
              : AppStringKeys.composerVideoCall,
        ),
        () => widget.onStartCall(true),
      ),
      (
        HeroAppIcons.locationDot.data,
        AppStrings.t(AppStringKeys.composerLocation),
        _sendLocation,
      ),
      (
        HeroAppIcons.solidFolder.data,
        telegramText(AppStringKeys.topicPostContentFile),
        _pickFile,
      ),
      (
        HeroAppIcons.grip.data,
        AppStrings.t(AppStringKeys.composerPoll),
        _createPoll,
      ),
      (
        HeroAppIcons.music.data,
        telegramText(AppStringKeys.composerAudio),
        _pickAudio,
      ),
      (
        HeroAppIcons.penToSquare.data,
        AppStrings.t(AppStringKeys.composerRichText),
        _openRichTextComposer,
      ),
      (
        HeroAppIcons.listCheck.data,
        AppStrings.t(AppStringKeys.composerChecklist),
        _createChecklist,
      ),
    ];
    final c = context.colors;
    return Container(
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
                setState(() => _panel = _Panel.none);
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

  Widget _emojiPanel() {
    final c = context.colors;
    return Container(
      height: 286,
      color: c.panelBackground,
      child: Column(
        children: [
          Expanded(child: _emojiContent()),
          _emojiTabStrip(),
        ],
      ),
    );
  }

  Widget _emojiContent() {
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

  Widget _emojiTabStrip() {
    final c = context.colors;
    final packs = EmojiStore.shared.customPacks;
    return Container(
      decoration: BoxDecoration(
        color: c.inputBarBackground,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          children: [
            _emojiTabButton(
              selected: _emojiTab == 'standard',
              onTap: () => setState(() => _emojiTab = 'standard'),
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
                onTap: () => setState(() => _emojiTab = pack.id.toString()),
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
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: selected ? context.colors.searchFill : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
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
        : (_recordCancelled
              ? AppStrings.t(AppStringKeys.composerReleaseFingerToCancel)
              : AppStrings.t(AppStringKeys.composerReleaseToSendSlideToCancel));
    return Container(
      height: 240,
      width: double.infinity,
      color: c.panelBackground,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: _recordCancelled ? AppTheme.tagRed : c.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Opacity(
            opacity: _recording ? 1 : 0.3,
            child: Text(
              _recTime(_elapsed),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: c.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Listener(
            onPointerDown: (e) {
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
              if (!_recording) return;
              final cancel = e.position.dy - _pressStartY < -70;
              if (cancel != _recordCancelled) {
                setState(() => _recordCancelled = cancel);
              }
            },
            onPointerUp: (_) {
              if (_recorder != null) {
                _stopRec();
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
        ],
      ),
    );
  }

  Widget _stickerPanel() {
    final c = context.colors;
    return Container(
      height: 286,
      color: c.panelBackground,
      child: Column(
        children: [
          Expanded(child: _stickerContent()),
          _stickerTabStrip(),
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
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: stickers.length,
      itemBuilder: (context, i) {
        final item = stickers[i];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            widget.vm.sendSticker(item);
            widget.onMessageSent();
            setState(() => _panel = _Panel.none);
          },
          child: StickerPreview(item: item),
        );
      },
    );
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
      itemBuilder: (_, index) {
        final item = items[index];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () async {
            final sent = await widget.vm.sendGif(item);
            if (!mounted) return;
            if (sent) {
              widget.onMessageSent();
              setState(() => _panel = _Panel.none);
            } else {
              showToast(
                context,
                AppStrings.t(AppStringKeys.composerGifSendFailed),
              );
            }
          },
          child: GifPreview(item: item),
        );
      },
    );
  }

  Widget _stickerTabStrip() {
    final c = context.colors;
    final packs = StickerStore.shared.packs;
    final activeId =
        _stickerPack ??
        (packs.isNotEmpty ? packs.first.id : StickerStore.recentPackId);
    final installed = packs.where((p) => p.id != StickerStore.recentPackId);
    return Container(
      decoration: BoxDecoration(
        color: c.inputBarBackground,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          children: [
            _emojiTabButton(
              selected: activeId == StickerStore.recentPackId,
              onTap: () {
                setState(() => _stickerPack = StickerStore.recentPackId);
                StickerStore.shared.loadIfNeeded();
              },
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
              onTap: () {
                setState(() => _stickerPack = _gifTabId);
                GifStore.shared.loadIfNeeded();
              },
              child: AppIcon(
                HeroAppIcons.gif,
                size: 22,
                color: activeId == _gifTabId ? AppTheme.brand : c.textSecondary,
              ),
            ),
            for (final pack in installed)
              _emojiTabButton(
                selected: pack.id == activeId,
                onTap: () {
                  setState(() => _stickerPack = pack.id);
                  StickerStore.shared.loadPack(pack.id);
                },
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
}
