import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../call/call_manager.dart';
import '../call/call_overlay_host.dart';
import '../call/calls_view.dart';
import '../chat/audio_search_view.dart';
import '../chat/chat_info_view.dart';
import '../chat/chat_view.dart';
import '../chat/chat_view_model.dart';
import '../chat/checklist_composer_view.dart';
import '../chat/contact_share_picker_view.dart';
import '../chat/group_remark_controller.dart';
import '../chat/location_picker_view.dart';
import '../chat/music_player_controller.dart';
import '../chat/outgoing_attachment.dart';
import '../chat/poll_composer_view.dart';
import '../chat/rich_message_bot_relay.dart';
import '../chat/rich_message_source.dart';
import '../chat/rich_text_composer_view.dart';
import '../chat/scheduled_messages_view.dart';
import '../chat/shared_media_view.dart';
import '../chat/telegram_ai_editor_view.dart';
import '../chat/telegram_ai_service.dart';
import '../chats/search_view.dart';
import '../components/confirm_dialog.dart';
import '../components/keyboard_dismiss_on_tap.dart';
import '../components/toast.dart';
import '../l10n/app_locale_controller.dart';
import '../l10n/app_localizations.dart';
import '../l10n/telegram_language_controller.dart';
import '../pro/mithka_pro_service.dart';
import '../profile/profile_detail_view.dart';
import '../security/local_app_lock_controller.dart';
import '../settings/ai_settings_controller.dart';
import '../settings/app_icon_controller.dart';
import '../settings/auto_download_media_controller.dart';
import '../settings/blocked_user_service.dart';
import '../settings/country_message_filter.dart';
import '../settings/desktop_hotkey_controller.dart';
import '../settings/developer_mode_controller.dart';
import '../settings/keyword_blocker.dart';
import '../settings/rich_message_relay_config.dart';
import '../settings/safety_notice_controller.dart';
import '../settings/sensitive_content_controller.dart';
import '../settings/settings_view.dart';
import '../settings/translation_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'app_navigator.dart';
import 'app_performance_controller.dart';
import 'chat_deep_link_controller.dart';
import 'desktop_utility_window_models.dart';
import 'desktop_utility_window_stub.dart'
    if (dart.library.io) 'desktop_utility_window_io.dart'
    as implementation;
import 'global_video_split_host.dart';

export 'desktop_utility_window_models.dart';

class DesktopUtilityWindowService {
  DesktopUtilityWindowService._();

  static final DesktopUtilityWindowService instance =
      DesktopUtilityWindowService._();

  bool get isSupported => implementation.supportsDesktopUtilityWindows;

  void attachMainProxy({
    Future<void> Function()? onSettingsChanged,
    int? Function(int accountSlot)? accountUserIdForSlot,
  }) => implementation.attachDesktopUtilityMainProxy(
    onSettingsChanged: onSettingsChanged,
    accountUserIdForSlot: accountUserIdForSlot,
  );

  void detachMainProxy() => implementation.detachDesktopUtilityMainProxy();

  void notifyAccountIdentityChanged() =>
      implementation.notifyDesktopUtilityAccountIdentityChanged();

  Future<bool> open(DesktopUtilityWindowArguments arguments) =>
      implementation.openDesktopUtilityWindow(arguments);

  /// Hands a conversation selected in a registered utility child back to the
  /// primary window. Returns false in the primary engine and on mobile so the
  /// caller can use normal in-window navigation.
  Future<bool> openChatInPrimaryWindow(ChatDeepLinkRequest request) =>
      implementation.openChatInPrimaryWindowFromDesktopUtility(request);

  Future<void> configureChildProxy(DesktopUtilityWindowArguments arguments) =>
      implementation.configureDesktopUtilityChildProxy(arguments);

  void attachChildPresentationReload(Future<void> Function() callback) =>
      implementation.attachDesktopUtilityChildPresentationReload(callback);

  void detachChildPresentationReload() =>
      implementation.detachDesktopUtilityChildPresentationReload();

  Future<void> notifyPresentationChanged() =>
      implementation.notifyDesktopUtilityPresentationChanged();

  Future<void> closeCurrentWindow() =>
      implementation.closeCurrentDesktopUtilityWindow();

  Future<void> notifySettingsChanged(DesktopUtilityWindowArguments arguments) =>
      implementation.notifyDesktopUtilitySettingsChanged(arguments);
}

/// Secondary-engine shell for production utility, chat-info, and profile
/// surfaces.
///
/// The child creates presentation controllers only. [TdClient] is configured
/// as a proxy before this widget is mounted, so the primary engine remains the
/// sole owner of native TDLib clients and their databases.
class DesktopUtilityWindowApp extends StatefulWidget {
  const DesktopUtilityWindowApp({
    super.key,
    required this.arguments,
    required this.prefs,
  });

  final DesktopUtilityWindowArguments arguments;
  final SharedPreferences prefs;

  @override
  State<DesktopUtilityWindowApp> createState() =>
      _DesktopUtilityWindowAppState();
}

class _DesktopUtilityWindowAppState extends State<DesktopUtilityWindowApp> {
  late final AuthManager _auth = AuthManager();
  late final AccountStore _accounts = AccountStore(widget.prefs);
  late ThemeController _theme = ThemeController(
    widget.prefs,
    initialAccountSlot: widget.arguments.accountSlot,
  );
  late TranslationController _translation = TranslationController(widget.prefs);
  late final AiSettingsController _ai = AiSettingsController(widget.prefs);
  late AppLocaleController _locale = AppLocaleController(widget.prefs);
  late final TelegramLanguageController _telegramLanguage =
      TelegramLanguageController.shared;
  late final GroupRemarkController _groupRemarks = GroupRemarkController(
    widget.prefs,
    initialAccountUserId: widget.arguments.accountUserId,
  );
  late final MithkaProService _mithkaPro = MithkaProService.shared;
  late final AppIconController _appIcons = AppIconController(widget.prefs);
  late final AutoDownloadMediaController _autoDownload =
      AutoDownloadMediaController.shared;
  late final DeveloperModeController _developer = DeveloperModeController(
    widget.prefs,
  );
  late final AppPerformanceController _performance = AppPerformanceController(
    widget.prefs,
  );
  late final SafetyNoticeController _safetyNotice = SafetyNoticeController(
    widget.prefs,
  );
  late final SensitiveContentController _sensitiveContent =
      SensitiveContentController.shared;
  late final LocalAppLockController _appLock = LocalAppLockController.shared;
  late final CallManager _calls = CallManager()..start();
  DesktopHotkeyController? _desktopHotkeys;
  final Map<ChangeNotifier, VoidCallback> _settingsSyncSources = {};
  Timer? _settingsSyncDebounce;
  late bool _lastPerformanceProfilingEnabled = _performance.profilingEnabled;
  bool _presentationReloading = false;
  bool _presentationReloadQueued = false;
  bool _applyingPresentationReload = false;
  ChatViewModel? _composerPickerViewModel;

  ChatViewModel get _pickerViewModel {
    final existing = _composerPickerViewModel;
    if (existing != null) return existing;
    final created = ChatViewModel(
      chatId: widget.arguments.chatId!,
      title: widget.arguments.title,
      markReadOnOpen: false,
    )..onAppear();
    _composerPickerViewModel = created;
    return created;
  }

  @override
  void initState() {
    super.initState();
    KeywordBlocker.shared.initialize(widget.prefs);
    CountryMessageFilter.shared.initialize(widget.prefs);
    MusicPlayerController.shared.initialize(widget.prefs);
    _autoDownload.initialize(widget.prefs);
    _performance.start();
    _theme.setActiveAccountSlot(
      widget.arguments.accountSlot,
      userId: widget.arguments.accountUserId,
    );
    DesktopUtilityWindowService.instance.attachChildPresentationReload(
      _reloadPresentationPreferences,
    );
    _auth.start();
    _auth.reloadAuthState();
    unawaited(_accounts.refresh());
    unawaited(_sensitiveContent.initialize());
    unawaited(BlockedUserService.shared.loadBlockedUsers());
    if (widget.arguments.kind == DesktopUtilityWindowKind.settings) {
      _desktopHotkeys = DesktopHotkeyController.initializeShared(widget.prefs);
      for (final source in <ChangeNotifier>[
        _theme,
        _translation,
        _locale,
        _autoDownload,
        _developer,
        _safetyNotice,
        KeywordBlocker.shared,
        CountryMessageFilter.shared,
        _desktopHotkeys!,
      ]) {
        _attachSettingsSyncSource(source);
      }
      _attachSettingsSyncSource(
        _performance,
        listener: _handlePerformanceSettingsChanged,
      );
      unawaited(_initializeAndAttachSettingsSource(_ai.initialize, _ai));
      unawaited(
        _initializeAndAttachSettingsSource(_mithkaPro.initialize, _mithkaPro),
      );
      // Attach before TDLib finishes loading remote packs so a fast language
      // choice still reaches the primary engine and every open child window.
      _attachSettingsSyncSource(_telegramLanguage);
      unawaited(_telegramLanguage.initialize(widget.prefs));
      unawaited(
        _initializeAndAttachSettingsSource(_appIcons.initialize, _appIcons),
      );
      unawaited(
        _initializeAndAttachSettingsSource(_appLock.initialize, _appLock),
      );
    } else {
      unawaited(_ai.initialize());
      unawaited(_mithkaPro.initialize());
      unawaited(_telegramLanguage.initialize(widget.prefs));
      unawaited(_appIcons.initialize());
      unawaited(_appLock.initialize());
    }
  }

  Future<void> _initializeAndAttachSettingsSource(
    Future<void> Function() initialize,
    ChangeNotifier source,
  ) async {
    try {
      await initialize();
    } on Object {
      // A platform-backed settings controller can be unavailable in a child
      // engine. The rest of Settings remains live through the TD proxy.
    }
    if (mounted) _attachSettingsSyncSource(source);
  }

  void _attachSettingsSyncSource(
    ChangeNotifier source, {
    VoidCallback? listener,
  }) {
    if (_settingsSyncSources.containsKey(source)) return;
    final callback = listener ?? _scheduleSettingsSync;
    _settingsSyncSources[source] = callback;
    source.addListener(callback);
  }

  void _detachSettingsSyncSource(ChangeNotifier source) {
    final callback = _settingsSyncSources.remove(source);
    if (callback != null) source.removeListener(callback);
  }

  Future<void> _reloadPresentationPreferences() async {
    if (_presentationReloading) {
      _presentationReloadQueued = true;
      return;
    }
    _presentationReloading = true;
    _applyingPresentationReload = true;
    try {
      do {
        _presentationReloadQueued = false;
        try {
          await widget.prefs.reload();
          final desktopHotkeys = DesktopHotkeyController.maybeShared;
          if (desktopHotkeys != null) await desktopHotkeys.reload();
        } on Object {
          // A transient platform-preferences failure must not unregister an
          // otherwise healthy TD proxy window from the primary bridge.
          return;
        }
        if (!mounted) return;

        final previousTheme = _theme;
        final previousTranslation = _translation;
        final previousLocale = _locale;
        final nextTheme =
            ThemeController(
              widget.prefs,
              initialAccountSlot: widget.arguments.accountSlot,
            )..setActiveAccountSlot(
              widget.arguments.accountSlot,
              userId: widget.arguments.accountUserId,
            );
        final nextTranslation = TranslationController(widget.prefs);
        final nextLocale = AppLocaleController(widget.prefs);
        unawaited(_telegramLanguage.reloadPreferences(widget.prefs));

        if (widget.arguments.kind == DesktopUtilityWindowKind.settings) {
          _settingsSyncDebounce?.cancel();
          _settingsSyncDebounce = null;
          _detachSettingsSyncSource(previousTheme);
          _detachSettingsSyncSource(previousTranslation);
          _detachSettingsSyncSource(previousLocale);
        }

        setState(() {
          _theme = nextTheme;
          _translation = nextTranslation;
          _locale = nextLocale;
        });
        unawaited(nextTheme.loadSelectedEmojiFontIfAvailable());

        if (widget.arguments.kind == DesktopUtilityWindowKind.settings) {
          _attachSettingsSyncSource(nextTheme);
          _attachSettingsSyncSource(nextTranslation);
          _attachSettingsSyncSource(nextLocale);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          previousLocale.dispose();
          previousTranslation.dispose();
          previousTheme.dispose();
        });
      } while (_presentationReloadQueued && mounted);
    } finally {
      _applyingPresentationReload = false;
      _presentationReloading = false;
    }
  }

  void _handlePerformanceSettingsChanged() {
    final enabled = _performance.profilingEnabled;
    if (enabled == _lastPerformanceProfilingEnabled) return;
    _lastPerformanceProfilingEnabled = enabled;
    _scheduleSettingsSync();
  }

  void _scheduleSettingsSync() {
    if (widget.arguments.kind != DesktopUtilityWindowKind.settings ||
        _applyingPresentationReload) {
      return;
    }
    _settingsSyncDebounce?.cancel();
    // Most preference setters notify immediately and persist asynchronously.
    // Give the platform store time to commit before asking the primary engine
    // to reload its cached preferences and presentation controllers.
    _settingsSyncDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(
        DesktopUtilityWindowService.instance.notifySettingsChanged(
          widget.arguments,
        ),
      );
    });
  }

  @override
  void dispose() {
    DesktopUtilityWindowService.instance.detachChildPresentationReload();
    _settingsSyncDebounce?.cancel();
    for (final entry in _settingsSyncSources.entries) {
      entry.key.removeListener(entry.value);
    }
    _settingsSyncSources.clear();
    _composerPickerViewModel
      ?..onDisappear()
      ..dispose();
    unawaited(TdClient.shared.closeProxy());
    _calls.dispose();
    _performance.dispose();
    _groupRemarks.dispose();
    _appIcons.dispose();
    _developer.dispose();
    _safetyNotice.dispose();
    _locale.dispose();
    _ai.dispose();
    _translation.dispose();
    _theme.dispose();
    _accounts.dispose();
    _auth.dispose();
    super.dispose();
  }

  ThemeData _themeData(Brightness brightness) {
    final colors = _theme.uiColorsFor(brightness);
    final families = _theme.effectiveFontFamilyChain();
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      fontFamily: families.isEmpty ? null : families.first,
      fontFamilyFallback: families.length > 1
          ? families.skip(1).toList()
          : null,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _theme.usesCloudThemeForUi(brightness)
            ? colors.linkBlue
            : _theme.brandColor,
        brightness: brightness,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: AppPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
          TargetPlatform.iOS: AppPageTransitionsBuilder(),
          TargetPlatform.linux: AppPageTransitionsBuilder(),
          TargetPlatform.macOS: AppPageTransitionsBuilder(),
          TargetPlatform.windows: AppPageTransitionsBuilder(),
        },
      ),
      extensions: [colors],
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
    return base.copyWith(
      textTheme: _theme.applyAppTextTheme(base.textTheme),
      primaryTextTheme: _theme.applyAppTextTheme(base.primaryTextTheme),
    );
  }

  Locale _effectiveLocale() => _telegramLanguage.mithkaLocale;

  Future<void> _sendSearchedAudio(int sourceChatId, ChatMessage message) =>
      _pickerViewModel.sendAudioFromMessage(sourceChatId, message);

  Future<bool> _pickAndSendLocalAudio() async {
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
    final attachments = result?.files
        .map((file) => file.path)
        .whereType<String>()
        .take(10)
        .map(
          (path) => OutgoingAttachment(
            path: path,
            kind: OutgoingAttachmentKind.audio,
          ),
        )
        .toList(growable: false);
    if (attachments == null || attachments.isEmpty) return false;
    await _pickerViewModel.sendAttachments(attachments);
    return true;
  }

  Future<void> _sendPickedLocation(LocationShareResult result) =>
      TdClient.shared.query({
        '@type': 'sendMessage',
        'chat_id': widget.arguments.chatId,
        'input_message_content': {
          '@type': 'inputMessageLocation',
          'location': {
            '@type': 'location',
            'latitude': result.center.latitude,
            'longitude': result.center.longitude,
            'horizontal_accuracy': 0,
          },
        },
      });

  Future<void> _sendPickedContact(MessageContactCard contact) async {
    if (await _pickerViewModel.sendContact(contact)) {
      await _closePickerWindow();
    }
  }

  Future<void> _sendPoll(PollComposerResult result) async {
    if (await _pickerViewModel.sendPoll(result)) {
      await _closePickerWindow();
    }
  }

  Future<void> _sendChecklist(ChecklistComposerResult result) async {
    if (result.title.trim().isEmpty || result.tasks.isEmpty) return;
    _pickerViewModel.sendChecklist(result);
    await _closePickerWindow();
  }

  Future<TelegramAiFormattedText> _loadComposerDraft() async {
    final chat = await TdClient.shared.query({
      '@type': 'getChat',
      'chat_id': widget.arguments.chatId,
    });
    final formatted = chat
        .obj('draft_message')
        ?.obj('input_message_text')
        ?.obj('text');
    return TelegramAiFormattedText(
      text: formatted?.str('text') ?? '',
      entities: formatted?.objects('entities') ?? const [],
    );
  }

  Future<TelegramAiFormattedText> _loadAiEditorDraft() async {
    await _pickerViewModel.telegramAi.capabilities();
    return _loadComposerDraft();
  }

  Future<void> _applyAiDraft(TelegramAiFormattedText result) async {
    _pickerViewModel.setDraft(
      result.text,
      formattedText: result.text,
      entities: result.entities,
    );
    await _pickerViewModel.persistComposerDraft();
    await _closePickerWindow();
  }

  Future<void> _sendRichText(RichTextComposerResult result) async {
    if (result.text.trim().isEmpty && result.attachments.isEmpty) return;
    try {
      if (!await _pickerViewModel.prepareMessageSend() || !mounted) return;
      if (_pickerViewModel.requiresPaidMessage) {
        final confirmed = await confirmDialog(
          context,
          title: AppStrings.t(AppStringKeys.composerSendPaidMessageQuestion),
          message: AppStrings.t(AppStringKeys.composerPaidMessageCost, {
            'value1': _pickerViewModel.paidMessageStarCount,
          }),
          confirmText: AppStrings.t(AppStringKeys.composerSend),
        );
        if (!confirmed || !mounted) return;
      }
      var sentAny = false;
      if (await _pickerViewModel.currentUserIsPremium()) {
        for (final segment in result.segments) {
          if (segment.isHtml) {
            final files = await Future.wait(
              segment.richFiles.map((file) async {
                final attachment = await resolveAttachmentDimensions(
                  file.attachment,
                );
                return RichMessageSendFile(id: file.id, attachment: attachment);
              }),
            );
            await _pickerViewModel.sendRichMessageHtml(
              segment.html,
              files: files,
              blocks: segment.blocks,
            );
            sentAny = true;
          } else if (segment.attachments.isNotEmpty) {
            await _pickerViewModel.sendAttachments(segment.attachments);
            sentAny = true;
          }
        }
      } else {
        final token = await RichMessageRelayConfig.readToken();
        if (token == null) {
          throw StateError('Rich message relay is not configured');
        }
        final relay = RichMessageBotRelay();
        try {
          final currentUserId = await _pickerViewModel.currentUserId();
          for (final segment in result.segments) {
            if (segment.isHtml) {
              final files = await Future.wait(
                segment.richFiles.map((file) async {
                  final attachment = await resolveAttachmentDimensions(
                    file.attachment,
                  );
                  return RichMessageSendFile(
                    id: file.id,
                    attachment: attachment,
                  );
                }),
              );
              await relay.sendAndCopy(
                token: token,
                html: segment.html,
                currentUserId: currentUserId,
                targetChatId: widget.arguments.chatId!,
                tdClient: TdClient.shared,
                files: files,
              );
              sentAny = true;
            } else if (segment.attachments.isNotEmpty) {
              await _pickerViewModel.sendAttachments(segment.attachments);
              sentAny = true;
            }
          }
        } finally {
          relay.close();
        }
      }
      if (!sentAny && result.text.trim().isNotEmpty) {
        sentAny = await _pickerViewModel.sendFormatted(
          result.text,
          result.entities,
        );
      }
      if (sentAny) await _closePickerWindow();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  Future<void> _closePickerWindow() =>
      DesktopUtilityWindowService.instance.closeCurrentWindow();

  Widget _rootSurface() => switch (widget.arguments.kind) {
    DesktopUtilityWindowKind.calls => const CallsView(showBackButton: false),
    DesktopUtilityWindowKind.savedMessages => ChatView(
      key: ValueKey(
        'desktop-utility-saved-${widget.arguments.accountSlot}-${widget.arguments.chatId}',
      ),
      chatId: widget.arguments.chatId!,
      title: widget.arguments.title,
      showBackButton: false,
      requestComposerFocusOnReady: true,
    ),
    DesktopUtilityWindowKind.files => SharedMediaView(
      chatId: 0,
      title: widget.arguments.title,
      initialTab: 1,
      displayTitle: AppStringKeys.topicPostContentFile,
      showBackButton: false,
    ),
    DesktopUtilityWindowKind.videos => SharedMediaView(
      chatId: 0,
      title: widget.arguments.title,
      initialTab: 4,
      displayTitle: AppStringKeys.sharedMediaVideos,
      lockedTab: true,
      showBackButton: false,
    ),
    DesktopUtilityWindowKind.search => SearchView(
      initialQuery: widget.arguments.initialQuery ?? '',
      showBackButton: false,
    ),
    DesktopUtilityWindowKind.settings => SettingsView(
      showBackButton: false,
      allowSessionLifecycleActions: false,
      initialCategoryId: widget.arguments.initialSettingsCategoryId,
    ),
    DesktopUtilityWindowKind.chatInfo => ChatInfoView(
      chatId: widget.arguments.chatId!,
      title: widget.arguments.title,
      showBackButton: false,
    ),
    DesktopUtilityWindowKind.userProfile => ProfileDetailView(
      userId: widget.arguments.userId!,
      name: widget.arguments.title,
      showBackButton: false,
    ),
    DesktopUtilityWindowKind.audioPicker => AudioSearchView(
      showBackButton: false,
      onClose: _closePickerWindow,
      onSend: _sendSearchedAudio,
      onPickLocalInWindow: _pickAndSendLocalAudio,
    ),
    DesktopUtilityWindowKind.locationPicker => _DesktopLocationPickerRoot(
      onClose: _closePickerWindow,
      onSend: _sendPickedLocation,
    ),
    DesktopUtilityWindowKind.contactPicker => ContactSharePickerView(
      showBackButton: false,
      onClose: _closePickerWindow,
      onSelect: _sendPickedContact,
    ),
    DesktopUtilityWindowKind.pollComposer => _DesktopPollComposerRoot(
      viewModel: _pickerViewModel,
      onClose: _closePickerWindow,
      onSubmit: _sendPoll,
    ),
    DesktopUtilityWindowKind.checklistComposer => ChecklistComposerView(
      showBackButton: false,
      onClose: _closePickerWindow,
      onSubmit: _sendChecklist,
    ),
    DesktopUtilityWindowKind.scheduledMessages => ScheduledMessagesView(
      chatId: widget.arguments.chatId!,
      chatTitle: widget.arguments.title,
      showBackButton: false,
    ),
    DesktopUtilityWindowKind.richTextComposer => _DesktopDraftUtilityRoot(
      loadDraft: _loadComposerDraft,
      builder: (draft) => RichTextComposerView(
        initialText: draft.text,
        initialEntities: draft.entities,
        title: AppStringKeys.composerRichTextMessageTitle,
        submitText: AppStringKeys.composerSend,
        showCloseAction: false,
        onClose: _closePickerWindow,
        onSubmit: _sendRichText,
      ),
    ),
    DesktopUtilityWindowKind.aiEditor => _DesktopDraftUtilityRoot(
      loadDraft: _loadAiEditorDraft,
      builder: (draft) => TelegramAiEditorView(
        service: _pickerViewModel.telegramAi,
        source: draft,
        showBackButton: false,
        onClose: _closePickerWindow,
        onSubmit: _applyAiDraft,
      ),
    ),
  };

  @override
  Widget build(BuildContext context) => MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: _auth),
      ChangeNotifierProvider.value(value: _accounts),
      ChangeNotifierProvider.value(value: _theme),
      ChangeNotifierProvider.value(value: _translation),
      ChangeNotifierProvider.value(value: _ai),
      ChangeNotifierProvider.value(value: _locale),
      ChangeNotifierProvider.value(value: _telegramLanguage),
      ChangeNotifierProvider.value(value: _groupRemarks),
      ChangeNotifierProvider.value(value: _mithkaPro),
      ChangeNotifierProvider.value(value: _appIcons),
      ChangeNotifierProvider.value(value: _autoDownload),
      ChangeNotifierProvider.value(value: _developer),
      ChangeNotifierProvider.value(value: _performance),
      ChangeNotifierProvider.value(value: _safetyNotice),
      ChangeNotifierProvider.value(value: _sensitiveContent),
      ChangeNotifierProvider.value(value: _appLock),
      ChangeNotifierProvider.value(value: _calls),
    ],
    child: AnimatedBuilder(
      animation: Listenable.merge([_theme, _locale, _telegramLanguage]),
      builder: (context, _) {
        final locale = _effectiveLocale();
        unawaited(_telegramLanguage.syncAppLocale(locale));
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: widget.arguments.title,
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          scrollBehavior: const AppScrollBehavior(),
          theme: _themeData(Brightness.light),
          darkTheme: _themeData(Brightness.dark),
          themeMode: _theme.themeMode,
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final currentTheme = Theme.of(context);
            AppTheme.applyBrand(
              _theme.usesCloudThemeForUi(currentTheme.brightness)
                  ? context.colors.linkBlue
                  : _theme.brandColor,
            );
            final themedChild = Theme(
              data: currentTheme.copyWith(
                textTheme: _theme.applyAppTextTheme(
                  currentTheme.textTheme,
                  boldText: media.boldText,
                ),
                primaryTextTheme: _theme.applyAppTextTheme(
                  currentTheme.primaryTextTheme,
                  boldText: media.boldText,
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
            final appSurface = Stack(
              children: [
                Positioned.fill(
                  child: GlobalVideoSplitHost(child: themedChild),
                ),
                Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => const GlobalMusicPlayerOverlay(),
                    ),
                  ],
                ),
                const Positioned.fill(child: GlobalCallOverlayHost()),
              ],
            );
            if (!desktopUtilityWindowHasUsableMetrics(media.size)) {
              return ColoredBox(color: currentTheme.scaffoldBackgroundColor);
            }
            return _DesktopUtilityScaledView(
              fontScale: _theme.fontScale,
              interfaceScale: _theme.renderedInterfaceScale,
              child: appSurface,
            );
          },
          home: _rootSurface(),
        );
      },
    ),
  );
}

@visibleForTesting
bool desktopUtilityWindowHasUsableMetrics(Size size) =>
    size.width >= 320 && size.height >= 200;

class _DesktopPollComposerRoot extends StatefulWidget {
  const _DesktopPollComposerRoot({
    required this.viewModel,
    required this.onClose,
    required this.onSubmit,
  });

  final ChatViewModel viewModel;
  final Future<void> Function() onClose;
  final Future<void> Function(PollComposerResult result) onSubmit;

  @override
  State<_DesktopPollComposerRoot> createState() =>
      _DesktopPollComposerRootState();
}

class _DesktopPollComposerRootState extends State<_DesktopPollComposerRoot> {
  late final Future<int> _maximumOptions = widget.viewModel
      .pollAnswerCountMax();

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _maximumOptions,
    builder: (context, snapshot) {
      final maximumOptions = snapshot.data;
      if (maximumOptions == null) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
          ),
        );
      }
      return PollComposerView(
        maxOptions: maximumOptions,
        showBackButton: false,
        onClose: widget.onClose,
        onSubmit: widget.onSubmit,
      );
    },
  );
}

class _DesktopDraftUtilityRoot extends StatefulWidget {
  const _DesktopDraftUtilityRoot({
    required this.loadDraft,
    required this.builder,
  });

  final Future<TelegramAiFormattedText> Function() loadDraft;
  final Widget Function(TelegramAiFormattedText draft) builder;

  @override
  State<_DesktopDraftUtilityRoot> createState() =>
      _DesktopDraftUtilityRootState();
}

class _DesktopDraftUtilityRootState extends State<_DesktopDraftUtilityRoot> {
  late final Future<TelegramAiFormattedText> _draft = widget.loadDraft();

  @override
  Widget build(BuildContext context) => FutureBuilder<TelegramAiFormattedText>(
    future: _draft,
    builder: (context, snapshot) {
      final draft = snapshot.data;
      if (draft == null) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: Center(
            child: snapshot.hasError
                ? Text(
                    snapshot.error.toString(),
                    style: TextStyle(color: context.colors.textSecondary),
                  )
                : const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                  ),
          ),
        );
      }
      return widget.builder(draft);
    },
  );
}

class _DesktopLocationPickerRoot extends StatefulWidget {
  const _DesktopLocationPickerRoot({
    required this.onSend,
    required this.onClose,
  });

  final Future<void> Function(LocationShareResult result) onSend;
  final Future<void> Function() onClose;

  @override
  State<_DesktopLocationPickerRoot> createState() =>
      _DesktopLocationPickerRootState();
}

class _DesktopLocationPickerRootState
    extends State<_DesktopLocationPickerRoot> {
  late final Future<LatLng> _initial = resolveLocationPickerStart();

  @override
  Widget build(BuildContext context) => FutureBuilder<LatLng>(
    future: _initial,
    builder: (context, snapshot) {
      final initial = snapshot.data;
      if (initial == null) {
        return Scaffold(
          backgroundColor: context.colors.background,
          body: const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
          ),
        );
      }
      return LocationPickerView(
        initial: initial,
        showBackButton: false,
        onClose: widget.onClose,
        onSend: widget.onSend,
      );
    },
  );
}

class _DesktopUtilityScaledView extends StatelessWidget {
  const _DesktopUtilityScaledView({
    required this.fontScale,
    required this.interfaceScale,
    required this.child,
  });

  final double fontScale;
  final double interfaceScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = interfaceScale;
    final virtualSize = Size(
      media.size.width / scale,
      media.size.height / scale,
    );
    final scaledMedia = media.copyWith(
      size: virtualSize,
      padding: _unscale(media.padding, scale),
      viewPadding: _unscale(media.viewPadding, scale),
      viewInsets: _unscale(media.viewInsets, scale),
      systemGestureInsets: _unscale(media.systemGestureInsets, scale),
      textScaler: TextScaler.linear(fontScale),
    );
    return AppKeyboardDismissOnTap(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: virtualSize.width,
          maxWidth: virtualSize.width,
          minHeight: virtualSize.height,
          maxHeight: virtualSize.height,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: virtualSize.width,
              height: virtualSize.height,
              child: MediaQuery(data: scaledMedia, child: child),
            ),
          ),
        ),
      ),
    );
  }

  EdgeInsets _unscale(EdgeInsets insets, double scale) => EdgeInsets.fromLTRB(
    insets.left / scale,
    insets.top / scale,
    insets.right / scale,
    insets.bottom / scale,
  );
}
