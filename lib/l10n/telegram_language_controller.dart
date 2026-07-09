import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/td_client.dart';
import 'app_localizations.dart';

String? _tdType(Map<String, dynamic>? object) => _tdString(object, '@type');

String? _tdString(Map<String, dynamic>? object, String key) {
  final value = object?[key];
  return value is String ? value : null;
}

bool? _tdBool(Map<String, dynamic>? object, String key) {
  final value = object?[key];
  if (value is bool) return value;
  if (value is num) return value != 0;
  return null;
}

Map<String, dynamic>? _tdObject(Map<String, dynamic>? object, String key) {
  final value = object?[key];
  return value is Map<String, dynamic> ? value : null;
}

List<Map<String, dynamic>>? _tdObjects(
  Map<String, dynamic>? object,
  String key,
) {
  final value = object?[key];
  if (value is! List) return null;
  return value.whereType<Map<String, dynamic>>().toList();
}

String telegramText(
  String appFallbackKey, [
  Map<String, Object?> placeholders = const {},
]) {
  return TelegramLanguageController.shared.text(
    appFallbackKey,
    placeholders: placeholders,
  );
}

class TelegramLanguagePackOption {
  const TelegramLanguagePackOption({
    required this.id,
    required this.baseLanguagePackId,
    required this.name,
    required this.nativeName,
    required this.pluralCode,
    required this.isOfficial,
    required this.isRtl,
    required this.isBeta,
    required this.isInstalled,
  });

  factory TelegramLanguagePackOption.fromJson(Map<String, dynamic> json) {
    return TelegramLanguagePackOption(
      id: _tdString(json, 'id') ?? '',
      baseLanguagePackId: _tdString(json, 'base_language_pack_id') ?? '',
      name: _tdString(json, 'name') ?? '',
      nativeName: _tdString(json, 'native_name') ?? '',
      pluralCode: _tdString(json, 'plural_code') ?? '',
      isOfficial: _tdBool(json, 'is_official') ?? false,
      isRtl: _tdBool(json, 'is_rtl') ?? false,
      isBeta: _tdBool(json, 'is_beta') ?? false,
      isInstalled: _tdBool(json, 'is_installed') ?? false,
    );
  }

  final String id;
  final String baseLanguagePackId;
  final String name;
  final String nativeName;
  final String pluralCode;
  final bool isOfficial;
  final bool isRtl;
  final bool isBeta;
  final bool isInstalled;

  String get displayName => nativeName.trim().isNotEmpty
      ? nativeName.trim()
      : name.trim().isNotEmpty
      ? name.trim()
      : id;
}

class TelegramLanguageController extends ChangeNotifier {
  TelegramLanguageController._();

  static final shared = TelegramLanguageController._();
  static const _selectedPackKey = 'telegram.language_pack_id';
  static const _targetOption = 'localization_target';
  static const _packOption = 'language_pack_id';
  static const _queryTimeout = Duration(seconds: 20);
  static const _retryDelays = <Duration>[
    Duration(seconds: 15),
    Duration(seconds: 45),
    Duration(minutes: 2),
  ];

  SharedPreferences? _prefs;
  Locale? _appLocale;
  bool _initialized = false;
  bool _loading = false;
  String? _selectedPackId;
  String? _activePackId;
  String? _errorText;
  bool _refreshAgain = false;
  int _retryAttempt = 0;
  Timer? _retryTimer;
  StreamSubscription<Map<String, dynamic>>? _languageUpdates;
  List<TelegramLanguagePackOption> _packs = const [];
  final Map<String, String> _strings = {};

  bool get followsAppLanguage => _selectedPackId == null;
  bool get isLoading => _loading;
  String? get errorText => _errorText;
  String? get activePackId => _activePackId;
  List<TelegramLanguagePackOption> get packs => List.unmodifiable(_packs);

  Future<void> initialize(SharedPreferences prefs) async {
    if (_initialized) return;
    _initialized = true;
    _prefs = prefs;
    AppStrings.telegramStringResolver = resolveMappedText;
    final stored = prefs.getString(_selectedPackKey)?.trim();
    if (_legacyPackMigrations.containsKey(stored)) {
      _selectedPackId = _legacyPackMigrations[stored];
      if (_selectedPackId == null) {
        await prefs.remove(_selectedPackKey);
      } else {
        await prefs.setString(_selectedPackKey, _selectedPackId!);
      }
    } else {
      _selectedPackId = stored == null || stored.isEmpty ? null : stored;
    }
    _languageUpdates ??= TdClient.shared.subscribe().listen(_handleTdUpdate);
    await refresh();
  }

  Future<void> syncAppLocale(Locale? locale) async {
    final resolved = locale == null ? null : AppLocalizations.resolve(locale);
    if (_sameLocale(_appLocale, resolved)) return;
    _appLocale = resolved;
    if (followsAppLanguage) {
      await refresh();
    }
  }

  Future<void> setSelectedPack(String? packId) async {
    final normalized = packId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_selectedPackId == next) return;
    _selectedPackId = next;
    final prefs = _prefs;
    if (prefs != null) {
      if (next == null) {
        await prefs.remove(_selectedPackKey);
      } else {
        await prefs.setString(_selectedPackKey, next);
      }
    }
    await refresh();
  }

  Future<void> refresh() async {
    if (!_initialized) return;
    if (_loading) {
      _refreshAgain = true;
      return;
    }
    do {
      _refreshAgain = false;
      _loading = true;
      _errorText = null;
      notifyListeners();
      try {
        await _applyLocalizationTarget();
        await _loadAvailablePacks();
        final packId = _selectedPackId ?? _packIdForLocale(_appLocale);
        await _applyPack(packId);
        await _loadStringsForPack(packId);
        _activePackId = packId;
        _retryAttempt = 0;
        _retryTimer?.cancel();
        _retryTimer = null;
      } catch (error) {
        if (error is TimeoutException) {
          _scheduleRetry();
        } else {
          _errorText = error.toString();
          if (kDebugMode) debugPrint('Telegram language pack failed: $error');
        }
      } finally {
        _loading = false;
        notifyListeners();
      }
    } while (_refreshAgain);
  }

  String text(
    String appFallbackKey, {
    Map<String, Object?> placeholders = const {},
  }) {
    return resolveMappedText(appFallbackKey, placeholders) ??
        AppStrings.tLocal(appFallbackKey, placeholders);
  }

  String? resolveMappedText(
    String appFallbackKey,
    Map<String, Object?> placeholders,
  ) {
    final telegramKey = _telegramKeyForAppKey[appFallbackKey];
    final template = telegramKey == null ? null : _strings[telegramKey];
    if (template == null || template.trim().isEmpty) return null;
    return _interpolate(template, placeholders);
  }

  String raw(String telegramKey, String fallback) {
    final value = _strings[telegramKey];
    return value == null || value.trim().isEmpty ? fallback : value;
  }

  void _handleTdUpdate(Map<String, dynamic> update) {
    if (_tdType(update) != 'updateLanguagePackStrings') return;
    final packId = _tdString(update, 'language_pack_id');
    final activePack = _packs
        .where((pack) => pack.id == _activePackId)
        .firstOrNull;
    final isActivePack =
        packId == _activePackId ||
        (activePack?.baseLanguagePackId.isNotEmpty == true &&
            packId == activePack?.baseLanguagePackId);
    if (!isActivePack) return;

    final changed = _tdObjects(update, 'strings');
    if (changed == null || changed.isEmpty) {
      unawaited(refresh());
      return;
    }
    final allowedKeys = _telegramKeyForAppKey.values.toSet();
    var touched = false;
    for (final item in changed) {
      final key = _tdString(item, 'key');
      if (key == null || !allowedKeys.contains(key)) continue;
      final value = _languagePackStringValue(_tdObject(item, 'value'));
      if (value == null) {
        _strings.remove(key);
      } else {
        _strings[key] = value;
      }
      touched = true;
    }
    if (touched) notifyListeners();
  }

  Future<void> _applyLocalizationTarget() async {
    await _query({
      '@type': 'setOption',
      'name': _targetOption,
      'value': {'@type': 'optionValueString', 'value': _localizationTarget()},
    }).ignoreTimeout();
  }

  Future<void> _loadAvailablePacks() async {
    _packs = _knownRemotePacks;
    final response = await _query({
      '@type': 'getLocalizationTargetInfo',
      'only_local': false,
    });
    final packs =
        _tdObjects(response, 'language_packs')
            ?.map(TelegramLanguagePackOption.fromJson)
            .where((pack) => pack.id.isNotEmpty && !pack.isBeta)
            .toList() ??
        <TelegramLanguagePackOption>[];
    if (packs.isEmpty) {
      _packs = _knownRemotePacks;
      return;
    }
    packs.sort((a, b) {
      final official = (b.isOfficial ? 1 : 0) - (a.isOfficial ? 1 : 0);
      if (official != 0) return official;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    final knownIds = _knownRemotePacks.map((pack) => pack.id).toSet();
    _packs = [
      ..._knownRemotePacks,
      ...packs.where((pack) => !knownIds.contains(pack.id)),
    ];
  }

  Future<void> _applyPack(String packId) async {
    await _query({
      '@type': 'setOption',
      'name': _packOption,
      'value': {'@type': 'optionValueString', 'value': packId},
    }).ignoreTimeout();
  }

  Future<void> _loadStringsForPack(String packId) async {
    final merged = <String, String>{};
    final pack = _packs.where((pack) => pack.id == packId).firstOrNull;
    final baseId = pack?.baseLanguagePackId.trim();
    if (baseId != null && baseId.isNotEmpty) {
      merged.addAll(await _fetchPackStrings(baseId));
    }
    merged.addAll(await _fetchPackStrings(packId));
    _strings
      ..clear()
      ..addAll(merged);
  }

  Future<Map<String, String>> _fetchPackStrings(String packId) async {
    final response = await _query({
      '@type': 'getLanguagePackStrings',
      'language_pack_id': packId,
      'keys': _telegramKeyForAppKey.values.toSet().toList(),
    });
    final result = <String, String>{};
    for (final item in _tdObjects(response, 'strings') ?? const []) {
      final key = _tdString(item, 'key');
      final value = _languagePackStringValue(_tdObject(item, 'value'));
      if (key != null && value != null) result[key] = value;
    }
    return result;
  }

  Future<Map<String, dynamic>> _query(Map<String, dynamic> request) {
    return _waitForTdClient().then(
      (_) => TdClient.shared.query(request).timeout(_queryTimeout),
    );
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive == true) return;
    final index = _retryAttempt < _retryDelays.length
        ? _retryAttempt
        : _retryDelays.length - 1;
    _retryAttempt += 1;
    _retryTimer = Timer(_retryDelays[index], () {
      _retryTimer = null;
      unawaited(refresh());
    });
  }

  Future<void> _waitForTdClient() async {
    for (var attempt = 0; attempt < 40; attempt += 1) {
      if (TdClient.shared.hasActiveClient) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('TDLib client is not active yet');
  }

  String _packIdForLocale(Locale? locale) {
    final resolved =
        locale ?? AppLocalizations.resolve(PlatformDispatcher.instance.locale);
    final candidates = _candidatePackIds(resolved);
    for (final candidate in candidates) {
      if (_packs.any((pack) => pack.id == candidate)) return candidate;
    }
    for (final candidate in candidates) {
      final lower = candidate.toLowerCase();
      final match = _packs.where((pack) {
        return pack.id.toLowerCase() == lower ||
            pack.pluralCode.toLowerCase() == lower;
      }).firstOrNull;
      if (match != null) return match.id;
    }
    return 'en';
  }

  List<String> _candidatePackIds(Locale locale) {
    if (locale.languageCode == 'zh') {
      final traditional =
          locale.scriptCode == 'Hant' ||
          locale.countryCode == 'TW' ||
          locale.countryCode == 'HK' ||
          locale.countryCode == 'MO';
      return traditional
          ? const ['zh-hant', 'zh-tw', 'zh-hk', 'zh']
          : const ['zh-hans', 'zh-cn', 'zh'];
    }
    return [locale.languageCode.toLowerCase()];
  }

  static String? _languagePackStringValue(Map<String, dynamic>? value) {
    switch (_tdType(value)) {
      case 'languagePackStringValueOrdinary':
        return _tdString(value, 'value');
      case 'languagePackStringValuePluralized':
        return _tdString(value, 'other_value') ??
            _tdString(value, 'many_value') ??
            _tdString(value, 'few_value') ??
            _tdString(value, 'two_value') ??
            _tdString(value, 'one_value') ??
            _tdString(value, 'zero_value');
      default:
        return null;
    }
  }

  static String _localizationTarget() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows || Platform.isLinux) return 'tdesktop';
    return 'web';
  }

  static String _interpolate(
    String template,
    Map<String, Object?> placeholders,
  ) {
    var result = template;
    placeholders.forEach((key, value) {
      final replacement = '$value';
      result = result
          .replaceAll('{$key}', replacement)
          .replaceAll('%$key%', replacement);
      final indexMatch = RegExp(r'^value(\d+)$').firstMatch(key);
      if (indexMatch != null) {
        final index = indexMatch.group(1)!;
        result = result
            .replaceAll('%$index\$@', replacement)
            .replaceAll('%$index\$s', replacement)
            .replaceAll('%$index\$d', replacement);
      }
    });
    final value1 = placeholders['value1'];
    if (value1 != null) {
      result = result
          .replaceAll('{user}', '$value1')
          .replaceAll('{name}', '$value1')
          .replaceAll('%1\$@', '$value1')
          .replaceAll('%1\$s', '$value1')
          .replaceAll('%1\$d', '$value1')
          .replaceAll('%s', '$value1')
          .replaceAll('%d', '$value1')
          .replaceAll('%@', '$value1');
    }
    return result;
  }

  static bool _sameLocale(Locale? a, Locale? b) =>
      a?.languageCode == b?.languageCode &&
      a?.scriptCode == b?.scriptCode &&
      a?.countryCode == b?.countryCode;

  @override
  void dispose() {
    _retryTimer?.cancel();
    _languageUpdates?.cancel();
    super.dispose();
  }
}

extension _IgnoreTimeout<T> on Future<T> {
  Future<void> ignoreTimeout() async {
    try {
      await this;
    } on TimeoutException {
      // Language-pack options are best-effort. The app can still localize with
      // Mithka strings and retry fetching Telegram pack strings later.
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}

const _knownRemotePacks = <TelegramLanguagePackOption>[
  TelegramLanguagePackOption(
    id: 'zhhanscn-qq',
    baseLanguagePackId: 'zh-hans',
    name: 'Familiar Chinese Glossary',
    nativeName: '简体中文（熟悉术语）',
    pluralCode: 'zh',
    isOfficial: false,
    isRtl: false,
    isBeta: false,
    isInstalled: true,
  ),
];

const _legacyPackMigrations = <String?, String?>{
  'mithka-zh-hans-glossary': 'zhhanscn-qq',
  'mithka-zh-hant-glossary': null,
};

const _telegramKeyForAppKey = <String, String>{
  AppStringKeys.aboutTelegramChannel: 'Channel',
  AppStringKeys.accentColorPickerSave: 'Save',
  AppStringKeys.accountBackupLoadPyrogramPaste: 'Paste',
  AppStringKeys.accountBackupRestore: 'Restore',
  AppStringKeys.addMembersDone: 'Done',
  AppStringKeys.addMembersInviteMembersTitle: 'VoipGroupInviteMember',
  AppStringKeys.appIconDefault: 'AppIconDefault',
  AppStringKeys.appIconTitle: 'AppIcon',
  AppStringKeys.appearanceDownloadFailed: 'ErrorOccurred',
  AppStringKeys.appearanceFontLoadFailed: 'ErrorOccurred',
  AppStringKeys.appearanceFontSize: 'FontSize',
  AppStringKeys.appearanceNoMatchingFonts: 'NoResult',
  AppStringKeys.appearanceSearchFont: 'Search',
  AppStringKeys.appearanceSystem: 'AutoNightSystemDefault',
  AppStringKeys.appearanceTitle: 'ChangeChannelNameColor2',
  AppStringKeys.audioSearchChatTab: 'SearchAllChatsShort',
  AppStringKeys.audioSearchFailed: 'NoAudioFound',
  AppStringKeys.audioSearchFetchingSource: 'Loading',
  AppStringKeys.audioSearchNoResults: 'NoAudioFound',
  AppStringKeys.audioSearchPlaceholder: 'Search',
  AppStringKeys.audioSearchSendAudioFailed: 'ErrorOccurred',
  AppStringKeys.audioSearchTelegramAudioTitle: 'AttachAudio',
  AppStringKeys.authCodeExpiredRetry: 'CodeExpired',
  AppStringKeys.authInvalidPassword: 'CheckPasswordWrong',
  AppStringKeys.authInvalidPhoneNumber: 'InvalidPhoneNumber',
  AppStringKeys.authInvalidVerificationCode: 'SMSWordError',
  AppStringKeys.autoDeleteAfterOneDay: 'AutoDelete1Day',
  AppStringKeys.autoDeleteAfterOneMonth: 'AutoDelete1Month',
  AppStringKeys.autoDeleteAfterOneWeek: 'AutoDelete7Days',
  AppStringKeys.callAccept: 'AcceptCall',
  AppStringKeys.callCamera: 'VoipCamera',
  AppStringKeys.callConnecting: 'VoipConnecting',
  AppStringKeys.callDecline: 'VoipDeclineCall',
  AppStringKeys.callEndToEndEncrypted: 'ConferenceEncrypted',
  AppStringKeys.callEnded: 'VoipCallEnded',
  AppStringKeys.callFrontCamera: 'VoipFrontCamera',
  AppStringKeys.callHangUp: 'VoipEndCall',
  AppStringKeys.callMute: 'VoipMute',
  AppStringKeys.callRearCamera: 'VoipBackCamera',
  AppStringKeys.callSelectCamera: 'AccDescrSwitchCamera',
  AppStringKeys.callSpeakerphone: 'VoipSpeaker',
  AppStringKeys.channelsFileAttachment: 'AttachDocument',
  AppStringKeys.channelsLoading: 'Loading',
  AppStringKeys.channelsNoTopicChannels: 'NoTopics',
  AppStringKeys.chatActionChoosingContact: 'SelectingContact',
  AppStringKeys.chatActionChoosingLocation: 'SelectingLocation',
  AppStringKeys.chatActionChoosingSticker: 'ChoosingSticker',
  AppStringKeys.chatActionPlayingGame: 'SendingGame',
  AppStringKeys.chatActionRecordingVideo: 'RecordingVideoStatus',
  AppStringKeys.chatActionRecordingVideoNote: 'RecordingRound',
  AppStringKeys.chatActionRecordingVoice: 'RecordingAudio',
  AppStringKeys.chatActionUploadingFile: 'SendingFile',
  AppStringKeys.chatActionUploadingPhoto: 'SendingPhoto',
  AppStringKeys.chatActionUploadingVideo: 'SendingVideoStatus',
  AppStringKeys.chatActionUploadingVideoNote: 'SendingVideoStatus',
  AppStringKeys.chatActionUploadingVoice: 'SendingAudio',
  AppStringKeys.chatAutoDeleteCountdown: 'AutoDeleteIn',
  AppStringKeys.chatBlockUserConfirm: 'BlockUser',
  AppStringKeys.chatBlockUserDone: 'UserBlocked',
  AppStringKeys.chatBlockUserFailed: 'ErrorOccurred',
  AppStringKeys.chatBlockUserTitle: 'BlockUser',
  AppStringKeys.chatButtonUnsupported: 'UnsupportedAttachment',
  AppStringKeys.chatCannotSendMessages: 'ChannelCantSendMessage',
  AppStringKeys.chatDelete: 'Delete',
  AppStringKeys.chatDeleteActionsDone: 'Done',
  AppStringKeys.chatDeleteActionsFailed: 'ErrorOccurred',
  AppStringKeys.chatDeleteMessagesQuestion: 'DeleteMessagesTitle',
  AppStringKeys.chatDeleteOptionBlockSender: 'DeleteBanUser',
  AppStringKeys.chatDeleteOptionDeleteAllFromSender: 'DeleteAllFrom',
  AppStringKeys.chatDeleteOptionDeleteMessage: 'AreYouSureDeleteSingleMessage',
  AppStringKeys.chatDeleteOptionReportSpam: 'DeleteReportSpam',
  AppStringKeys.chatDeleteSingleMessageQuestion:
      'AreYouSureDeleteSingleMessage',
  AppStringKeys.chatEditMessageTitle: 'EditMessage',
  AppStringKeys.chatForwardFailed: 'ErrorOccurred',
  AppStringKeys.chatForwardToTitle: 'ForwardTo',
  AppStringKeys.chatInfoAlbum: 'Album',
  AppStringKeys.chatInfoAutoDeleteMessages: 'AutoDeleteMessages',
  AppStringKeys.chatInfoAutoDeleteOff: 'AutoDownloadOff',
  AppStringKeys.chatInfoAutoDeleteOneDay: 'AutoDelete1Day',
  AppStringKeys.chatInfoAutoDeleteOneMonth: 'AutoDelete1Month',
  AppStringKeys.chatInfoAutoDeleteSevenDays: 'AutoDelete7Days',
  AppStringKeys.chatInfoChatFolders: 'SettingsFolders',
  AppStringKeys.chatInfoClear: 'ClearHistory',
  AppStringKeys.chatInfoClearHistory: 'ClearHistory',
  AppStringKeys.chatInfoClearHistoryQuestion: 'AreYouSureClearHistory',
  AppStringKeys.chatInfoConfirmClearHistory: 'ClearHistory',
  AppStringKeys.chatInfoCreate: 'Create',
  AppStringKeys.chatInfoCreateFolderFailed: 'ErrorOccurred',
  AppStringKeys.chatInfoCreateFolderTitle: 'FilterNew',
  AppStringKeys.chatInfoFolderNameLabel: 'FilterNameHeader',
  AppStringKeys.chatInfoGroupFiles: 'SharedFilesTab',
  AppStringKeys.chatInfoGroupMembers: 'Members',
  AppStringKeys.chatInfoGroupVideos: 'AttachVideo',
  AppStringKeys.chatInfoLeaveGroup: 'LeaveMegaMenu',
  AppStringKeys.chatInfoLoadFoldersFailed: 'ErrorOccurred',
  AppStringKeys.chatInfoManageGroup: 'ManageGroup',
  AppStringKeys.chatInfoNewFolder: 'FilterNew',
  AppStringKeys.chatInfoNoFolders: 'FilterNoChatsToDisplay',
  AppStringKeys.chatInfoNotSearchable: 'NoResult',
  AppStringKeys.chatInfoPin: 'PinToTop',
  AppStringKeys.chatInfoPinChat: 'PinToTop',
  AppStringKeys.chatInfoPinFailed: 'ErrorOccurred',
  AppStringKeys.chatInfoPinFailedWithReason: 'ErrorOccurred',
  AppStringKeys.chatInfoPinLimit: 'LimitReached',
  AppStringKeys.chatInfoPinLimitReachedError: 'PinFolderLimitReached',
  AppStringKeys.chatInfoPinnedHighlights: 'PinnedMessages',
  AppStringKeys.chatInfoRemove: 'Delete',
  AppStringKeys.chatInfoSearchHistory: 'Search',
  AppStringKeys.chatInlineSwitchButtonUnsupported: 'UnsupportedAttachment',
  AppStringKeys.chatJoinGroup: 'JoinGroup',
  AppStringKeys.chatJoinRequestPending: 'ChannelJoinRequestSent',
  AppStringKeys.chatJoinRequestSent: 'ChannelJoinRequestSent',
  AppStringKeys.chatListChannelName: 'EnterChannelName',
  AppStringKeys.chatListCreateChannel: 'ChannelAlertCreate2',
  AppStringKeys.chatListCreateChannelFailed: 'ErrorOccurred',
  AppStringKeys.chatListCreateGroup: 'NewGroup',
  AppStringKeys.chatListDeleteChatQuestion: 'DeleteChatUser',
  AppStringKeys.chatListLeaveAndDeleteGroupConfirmation: 'MegaLeaveAlert',
  AppStringKeys.chatListMarkUnread: 'MarkAsUnread',
  AppStringKeys.chatListNoChats: 'NoChats',
  AppStringKeys.chatListUnpin: 'UnpinFromTop',
  AppStringKeys.chatLoadingTopics: 'Loading',
  AppStringKeys.chatMembersRemoveFailedPermission: 'ErrorOccurred',
  AppStringKeys.chatMembersTitleWithCount: 'Members',
  AppStringKeys.chatMenu: 'BotsMenuTitle',
  AppStringKeys.chatMessageInputPlaceholder: 'SendMessage',
  AppStringKeys.chatMessagesForwardedCount: 'ForwardedMessageCount',
  AppStringKeys.chatMoreActionsUnsupported: 'UnsupportedAttachment',
  AppStringKeys.chatNewMessagesCount: 'NewMessages',
  AppStringKeys.chatNewMessagesDivider: 'NewMessages',
  AppStringKeys.chatNoTopics: 'NoTopics',
  AppStringKeys.chatOffline: 'Offline',
  AppStringKeys.chatOnline: 'Online',
  AppStringKeys.chatOnlineWithinMonth: 'WithinAMonth',
  AppStringKeys.chatOnlineWithinWeek: 'WithinAWeek',
  AppStringKeys.chatPickerChooseChat: 'SelectChat',
  AppStringKeys.chatRecentlyOnline: 'Lately',
  AppStringKeys.chatReportConfirm: 'ReportChat',
  AppStringKeys.chatReportFailed: 'ErrorOccurred',
  AppStringKeys.chatReportSent: 'ReportChatSent',
  AppStringKeys.chatReportTitle: 'ReportChat',
  AppStringKeys.chatRequestToJoin: 'RequestToJoin',
  AppStringKeys.chatRestrictedAcknowledge: 'OK',
  AppStringKeys.chatRestrictedLeaveFailed: 'ErrorOccurred',
  AppStringKeys.chatSaveFailed: 'ErrorOccurred',
  AppStringKeys.chatSearchHistoryTitle: 'Search',
  AppStringKeys.chatSearchMessagePlaceholder: 'SearchMessages',
  AppStringKeys.chatSearchMessageResultLabel: 'Message',
  AppStringKeys.chatSearchNoMessagesFound: 'NoResult',
  AppStringKeys.chatSelectUntilHere: 'Select',
  AppStringKeys.chatTodoSetFailed: 'ErrorOccurred',
  AppStringKeys.chatTodoSetSuccess: 'MessagePinnedHint',
  AppStringKeys.chatTodoUnsetFailed: 'ErrorOccurred',
  AppStringKeys.chatTodoUnsetSuccess: 'MessageUnpinnedHint',
  AppStringKeys.chatTranslateFailed: 'TranslationFailedAlert1',
  AppStringKeys.chatTyping: 'Typing',
  AppStringKeys.chatUnmute: 'ChatsUnmute',
  AppStringKeys.chatUserTyping: 'IsTypingGroup',
  AppStringKeys.chatVideoPlaceholder: 'AttachVideo',
  AppStringKeys.chatsSearchBots: 'ChannelBots',
  AppStringKeys.chatsSearchNoResults: 'FilterNoChatsToDisplay',
  AppStringKeys.chatsSearchPlaceholder: 'Search',
  AppStringKeys.checklistComposerAddTask: 'AddTasks',
  AppStringKeys.checklistComposerNewChecklistTitle: 'TodoTitle',
  AppStringKeys.commonUiDraftBadge: 'Draft',
  AppStringKeys.composerAnimatedEmojiPreview: 'AttachGif',
  AppStringKeys.composerAudio: 'AttachMusic',
  AppStringKeys.composerCamera: 'Camera',
  AppStringKeys.composerChecklist: 'Todo',
  AppStringKeys.composerImage: 'AttachPhoto',
  AppStringKeys.composerImagePreview: 'AttachPhoto',
  AppStringKeys.composerLoadingEmoji: 'Loading',
  AppStringKeys.composerLocation: 'AttachLocation',
  AppStringKeys.composerLocationPreview: 'AttachLocation',
  AppStringKeys.composerOpenAttachmentFailed: 'ErrorOccurred',
  AppStringKeys.composerOpenMenu: 'AccDescrOpenMenu2',
  AppStringKeys.composerPastedImageReadFailed: 'ErrorOccurred',
  AppStringKeys.composerPoll: 'Poll',
  AppStringKeys.composerReleaseFingerToCancel: 'Cancel',
  AppStringKeys.composerReleaseToSendSlideToCancel: 'Cancel',
  AppStringKeys.composerSend: 'SendMessage',
  AppStringKeys.composerVideoCall: 'VideoCall',
  AppStringKeys.composerVoiceCall: 'Call',
  AppStringKeys.composerVoicePreview: 'AttachAudio',
  AppStringKeys.confirmOk: 'OK',
  AppStringKeys.contactsLoading: 'Loading',
  AppStringKeys.contactsNoBots: 'ChannelBots',
  AppStringKeys.contactsNoChannels: 'Channel',
  AppStringKeys.contactsNoContacts: 'NoContacts',
  AppStringKeys.countryPickerCancel: 'Cancel',
  AppStringKeys.countryPickerSearchPlaceholder: 'Search',
  AppStringKeys.countryPickerSelectCountryOrRegion: 'ChooseCountry',
  AppStringKeys.createGroupFailed: 'ErrorOccurred',
  AppStringKeys.createGroupOptionalLabel: 'DescriptionOptionalPlaceholder',
  AppStringKeys.editProfileAnimatedAvatar: 'PremiumPreviewAnimatedProfiles',
  AppStringKeys.editProfileAvatarUpdateFailed: 'ErrorOccurred',
  AppStringKeys.editProfileAvatarUpdated: 'ApplyAvatarHintTitle',
  AppStringKeys.editProfileBio: 'UserBio',
  AppStringKeys.editProfileBioPlaceholder: 'UserBioDetail',
  AppStringKeys.editProfileChangeAvatar: 'SetProfilePhoto',
  AppStringKeys.editProfileChangeBio: 'ProfileEditBio',
  AppStringKeys.editProfileChangeName: 'EditName',
  AppStringKeys.editProfileChangeUsername: 'ProfileActionsEditUsername',
  AppStringKeys.editProfileClearBirthday: 'BirthdayClearTitle',
  AppStringKeys.editProfileDefault: 'Default',
  AppStringKeys.editProfileInvalidAvatarFile: 'ErrorOccurred',
  AppStringKeys.editProfileNotBound: 'NumberUnknown',
  AppStringKeys.editProfilePhone: 'Phone',
  AppStringKeys.editProfileSaveFailed: 'ErrorOccurred',
  AppStringKeys.editProfileSetUsername: 'SetUsernameHeader',
  AppStringKeys.editProfileStaticAvatar: 'SetProfilePhoto',
  AppStringKeys.editProfileTapToFillBio: 'TapToAddBio',
  AppStringKeys.editProfileTapToSet: 'Add',
  AppStringKeys.editProfileUsername: 'Username',
  AppStringKeys.emojiCategoryActivitiesAndSports: 'Emoji4',
  AppStringKeys.emojiCategoryAnimalsAndNature: 'Emoji2',
  AppStringKeys.emojiCategoryFoodAndDrink: 'Emoji3',
  AppStringKeys.emojiCategoryObjects: 'Emoji6',
  AppStringKeys.emojiCategoryPeopleAndBody: 'Emoji1',
  AppStringKeys.emojiCategorySmileysAndEmotion: 'Emoji1',
  AppStringKeys.emojiCategorySymbols: 'Emoji7',
  AppStringKeys.emojiCategoryTravelAndPlaces: 'Emoji5',
  AppStringKeys.emojiFontCatalogSystemDefault: 'AutoNightSystemDefault',
  AppStringKeys.emojiStatusClear: 'Clear',
  AppStringKeys.emojiStatusNoAvailableStatusesPremiumRequired:
      'TelegramPremiumShort',
  AppStringKeys.emojiStatusSetRequiresPremiumFailed: 'ErrorOccurred',
  AppStringKeys.emojiStatusSetTitle: 'SetEmojiStatus',
  AppStringKeys.featureTitle: 'FeaturesBtn',
  AppStringKeys.fileDetailNoAppCanOpenFile: 'Open',
  AppStringKeys.fileDetailOpen: 'Open',
  AppStringKeys.generalAutoDownloadDisabled: 'AutoDownloadOff',
  AppStringKeys.generalAutoDownloadFailed: 'ErrorOccurred',
  AppStringKeys.generalAutoDownloadHighResImages: 'AutoDownloadHigh',
  AppStringKeys.generalAutoDownloadMedia: 'AutoDownloadMedia',
  AppStringKeys.generalAutoDownloadMobileData: 'NetworkUsageMobileTab',
  AppStringKeys.generalAutoDownloadWifi: 'NetworkUsageWiFiTab',
  AppStringKeys.generalClearCache: 'ClearCache',
  AppStringKeys.generalClearingCache: 'Loading',
  AppStringKeys.generalStorage: 'StorageUsage',
  AppStringKeys.generalTitle: 'General',
  AppStringKeys.groupManagementEditFailed: 'ErrorOccurred',
  AppStringKeys.groupManagementGroupName: 'GroupName',
  AppStringKeys.groupManagementInviteLinkQr: 'InviteLink',
  AppStringKeys.groupManagementLoadFailed: 'ErrorOccurred',
  AppStringKeys.groupManagementLogAdmin: 'ChannelAdmin',
  AppStringKeys.groupManagementLogEndedVideoChat: 'VoipGroupVoiceChatEnded',
  AppStringKeys.groupManagementLogPinnedMessage: 'PinnedMessage',
  AppStringKeys.groupManagementLogStartedVideoChat: 'VoipGroupVoiceChatStarted',
  AppStringKeys.groupManagementLogTitle: 'EventLog',
  AppStringKeys.groupManagementLogUnpinnedMessage: 'EventLogUnpinnedMessages',
  AppStringKeys.groupManagementMembers: 'Members',
  AppStringKeys.groupManagementNoEditInfoPermission: 'EditCantEditPermissions',
  AppStringKeys.groupManagementPermissionCreateTopics: 'CreateTopicsPermission',
  AppStringKeys.groupManagementPermissionLinkPreviews: 'SecretWebPage',
  AppStringKeys.groupManagementPermissionPinMessages:
      'UserRestrictionsPinMessages',
  AppStringKeys.groupManagementPermissionSendMessages: 'UserRestrictionsSend',
  AppStringKeys.groupManagementPermissionSendPolls:
      'UserRestrictionsSendPollsShort',
  AppStringKeys.groupManagementPermissionSendStickersAndGifs:
      'UserRestrictionsSendStickers',
  AppStringKeys.groupManagementPermissionSetFailed: 'ErrorOccurred',
  AppStringKeys.groupManagementPublicUsername: 'Username',
  AppStringKeys.groupManagementReadOnly: 'AccountFrozen2Title',
  AppStringKeys.groupManagementSetFailed: 'ErrorOccurred',
  AppStringKeys.groupManagementUsernameUnavailableOrForbidden:
      'UsernameInvalidShort',
  AppStringKeys.imageEditAdd: 'Add',
  AppStringKeys.imageEditAddText: 'TextPlaceholder',
  AppStringKeys.imageEditBrush: 'AccDescrBrushType',
  AppStringKeys.imageEditCaptionInputPlaceholder: 'AddCaption',
  AppStringKeys.imageEditCrop: 'Crop',
  AppStringKeys.imageEditCropAvatar: 'Crop',
  AppStringKeys.imageEditDescriptionPlaceholder: 'AddCaption',
  AppStringKeys.imageEditProcessing: 'Loading',
  AppStringKeys.imageEditResetCrop: 'Crop',
  AppStringKeys.imageEditRotate: 'AccDescrRotate',
  AppStringKeys.imageEditTextTool: 'PhotoEditorText',
  AppStringKeys.keywordBlockerDownload: 'Download',
  AppStringKeys.keywordBlockerDownloadFailed: 'ErrorOccurred',
  AppStringKeys.languageTelegramLoadFailed: 'ErrorOccurred',
  AppStringKeys.languageTelegramLoading: 'Loading',
  AppStringKeys.languageTitle: 'SettingsLanguage',
  AppStringKeys.linkHandlerGroupLabel: 'AccDescrGroup',
  AppStringKeys.linkHandlerJoin: 'JoinGroup',
  AppStringKeys.linkHandlerJoinNamedGroupQuestion: 'JoinGroup',
  AppStringKeys.linkHandlerOpenTelegramLinkFailed: 'ErrorOccurred',
  AppStringKeys.linkHandlerUnsupportedTelegramLink: 'UnsupportedMedia2',
  AppStringKeys.locationDetailFetchingLocation: 'ChatLocation',
  AppStringKeys.locationPickerDragMapToChoose: 'SelectingLocation',
  AppStringKeys.loginCodeSentFallback: 'VerificationCode',
  AppStringKeys.loginCodeSentToTelegramDevices: 'SentAppCodeTitle',
  AppStringKeys.loginFirstName: 'FirstNameSmall',
  AppStringKeys.loginLastNameOptional: 'LastName',
  AppStringKeys.loginQrCodeTitle: 'QrCode',
  AppStringKeys.loginRefreshQrCode: 'GetQRCode',
  AppStringKeys.loginResendVerificationCode: 'ResendCode',
  AppStringKeys.loginSubmit: 'BotAuthLogin',
  AppStringKeys.loginTermsAccept: 'BotWebAppDisclaimerCheck',
  AppStringKeys.loginTermsButton: 'TermsOfService',
  AppStringKeys.loginTermsOpenTelegram: 'TermsOfService',
  AppStringKeys.loginTermsTitle: 'TermsOfUse',
  AppStringKeys.loginVerificationCode: 'VerificationCode',
  AppStringKeys.loginWithQrCode: 'AuthAnotherClient',
  AppStringKeys.messageActionBlock: 'ReportSpamUser',
  AppStringKeys.messageActionCopy: 'Copy',
  AppStringKeys.messageActionEdit: 'Edit',
  AppStringKeys.messageActionFavorite: 'AddToFavorites',
  AppStringKeys.messageActionForward: 'Forward',
  AppStringKeys.messageActionMultiSelect: 'Select',
  AppStringKeys.messageActionQuote: 'QuoteMessage',
  AppStringKeys.messageActionReplies: 'RepliesTitle',
  AppStringKeys.messageActionReport: 'ReportChat',
  AppStringKeys.messageActionSelectText: 'SelectText',
  AppStringKeys.messageActionSetTodo: 'PinMessage',
  AppStringKeys.messageActionSticker: 'AttachSticker',
  AppStringKeys.messageActionTranslate: 'TranslateMessage',
  AppStringKeys.messageActionUnsetTodo: 'UnpinMessage',
  AppStringKeys.messageBubbleCallCanceled: 'CallMessageOutgoingMissed',
  AppStringKeys.messageBubbleCallDeclined: 'CallMessageIncomingDeclined',
  AppStringKeys.messageBubbleCallDeclinedByOther: 'CallMessageIncomingDeclined',
  AppStringKeys.messageBubbleCallMissed: 'CallMessageIncomingMissed',
  AppStringKeys.messageBubbleCallNoAnswer: 'CallMessageIncomingMissed',
  AppStringKeys.messageBubbleCollapse: 'PollCollapse',
  AppStringKeys.messageBubbleForwardedFrom: 'ForwardedFrom',
  AppStringKeys.messageBubbleTranslating: 'TranslateMessage',
  AppStringKeys.messageRepliesEmpty: 'NoReplies',
  AppStringKeys.messageRepliesTitle: 'RepliesTitle',
  AppStringKeys.momentsCommentCount: 'CommentsCount',
  AppStringKeys.momentsDetails: 'AccDescrIVDetails',
  AppStringKeys.momentsLikeFailed: 'ErrorOccurred',
  AppStringKeys.momentsLoadingPosts: 'Loading',
  AppStringKeys.momentsMore: 'DescriptionMore',
  AppStringKeys.momentsNoChannelContent: 'NoChannelsTitle',
  AppStringKeys.momentsNoComments: 'NoComments',
  AppStringKeys.momentsNoPostsFound: 'NoPublicStoriesTitle2',
  AppStringKeys.momentsOpenOriginalMessage: 'OpenMessage',
  AppStringKeys.momentsPickPhotoFailed: 'ErrorOccurred',
  AppStringKeys.momentsPostFailed: 'ErrorOccurred',
  AppStringKeys.momentsReplyFailed: 'ErrorOccurred',
  AppStringKeys.momentsReplyUnavailable: 'NoReplies',
  AppStringKeys.momentsSearching: 'Search',
  AppStringKeys.momentsSelectChannel: 'ChooseChannel',
  AppStringKeys.momentsSending: 'AccDescrMsgSending',
  AppStringKeys.momentsStories: 'NotificationsStories',
  AppStringKeys.momentsUnknown: 'NumberUnknown',
  AppStringKeys.musicPlayerAdd: 'Add',
  AppStringKeys.musicPlayerAddToPlaylist: 'ProfilePlaylistTitleMine',
  AppStringKeys.musicPlayerClear: 'ClearHistory',
  AppStringKeys.musicPlayerClose: 'Close',
  AppStringKeys.musicPlayerDownload: 'Download',
  AppStringKeys.musicPlayerEmptyPlaylist: 'NoAudioFilesInfo',
  AppStringKeys.musicPlayerModeRepeatOne: 'RepeatSong',
  AppStringKeys.musicPlayerModeSequence: 'RepeatList',
  AppStringKeys.musicPlayerModeShuffle: 'ShuffleList',
  AppStringKeys.musicPlayerNextTrack: 'Next',
  AppStringKeys.musicPlayerPause: 'Pause',
  AppStringKeys.musicPlayerPlay: 'Play',
  AppStringKeys.musicPlayerRemoveFromPlaylist: 'Delete',
  AppStringKeys.musicPlayerRemovedFromPlaylist: 'Delete',
  AppStringKeys.musicPlayerShowPlaylist: 'ProfilePlaylistTitleMine',
  AppStringKeys.myAlbumNoPhotos: 'NoPhotos',
  AppStringKeys.notificationPreview: 'MessagePreview',
  AppStringKeys.notificationPrivateMessages: 'NotificationsPrivateChats',
  AppStringKeys.notificationSound: 'Sound',
  AppStringKeys.notificationTitle: 'Notifications',
  AppStringKeys.pinnedMessagesEmpty: 'NoPinnedMessages',
  AppStringKeys.pinnedMessagesSentBy: 'SentBy',
  AppStringKeys.pollComposerAddOption: 'AddAnOption',
  AppStringKeys.pollComposerCreatePollTitle: 'NewPoll',
  AppStringKeys.pollComposerOptionLabel: 'OptionHint',
  AppStringKeys.premiumLabel: 'TelegramPremiumShort',
  AppStringKeys.privacyBlockedUsers: 'BlockedUsers',
  AppStringKeys.privacyBlockedUsersEmpty: 'NoBlocked',
  AppStringKeys.privacyCurrentDevice: 'CurrentSession',
  AppStringKeys.privacyDeleteTelegramAccount: 'DeleteAccountTitle',
  AppStringKeys.privacyDisabled: 'Disabled',
  AppStringKeys.privacyEnabled: 'Enabled',
  AppStringKeys.privacyLastSeen: 'LastSeen',
  AppStringKeys.privacyLoggedInDevices: 'Devices',
  AppStringKeys.privacyLoginQrAcceptFailed: 'ErrorOccurred',
  AppStringKeys.privacyOtherDevices: 'OtherSessions',
  AppStringKeys.privacyProfilePhoto: 'PrivacyProfilePhoto',
  AppStringKeys.privacyScanLoginQr: 'AuthAnotherClient',
  AppStringKeys.privacySectionTitle: 'PrivacyTitle',
  AppStringKeys.privacySecuritySectionTitle: 'SecurityTitle',
  AppStringKeys.privacySecurityTitle: 'PrivacySettings',
  AppStringKeys.privacyTerminateAllOtherSessions: 'TerminateAllSessions',
  AppStringKeys.privacyTerminateSession: 'Terminate',
  AppStringKeys.privacyTerminateSessionQuestion: 'TerminateSessionText',
  AppStringKeys.privacyTwoStepVerification: 'TwoStepVerification',
  AppStringKeys.privacyUnblock: 'Unblock',
  AppStringKeys.privacyVisibilityContacts: 'LastSeenContacts',
  AppStringKeys.privacyVisibilityEveryone: 'LastSeenEverybody',
  AppStringKeys.privacyVisibilityNobody: 'LastSeenNobody',
  AppStringKeys.profileAddAccount: 'AddAccount',
  AppStringKeys.profileDayMode: 'ThemeDay',
  AppStringKeys.profileDetailAddFriend: 'AddContactChat',
  AppStringKeys.profileDetailAddFriendDone: 'AddContactChat',
  AppStringKeys.profileDetailAddFriendFailed: 'ErrorOccurred',
  AppStringKeys.profileDetailBio: 'UserBio',
  AppStringKeys.profileDetailBirthday: 'ContactBirthday',
  AppStringKeys.profileDetailLocation: 'AttachLocation',
  AppStringKeys.profileDetailMediaFiles: 'SharedMedia',
  AppStringKeys.profileDetailMusic: 'SharedMusicTab',
  AppStringKeys.profileDetailSendMessage: 'SendMessage',
  AppStringKeys.profileLogOutAccount: 'LogOut',
  AppStringKeys.profileNightMode: 'ThemeNight',
  AppStringKeys.profileRemoveAccount: 'Delete',
  AppStringKeys.profileSettings: 'Settings',
  AppStringKeys.proxyAddFailed: 'ErrorOccurred',
  AppStringKeys.proxyAddProxy: 'AddProxy',
  AppStringKeys.proxyDeleteProxy: 'DeleteProxyTitle',
  AppStringKeys.proxyDisabled: 'MenuProxyDisabled',
  AppStringKeys.proxyHostOrIp: 'UseProxyAddress',
  AppStringKeys.proxyOptional: 'DescriptionOptionalPlaceholder',
  AppStringKeys.proxyPassword: 'UseProxyPassword',
  AppStringKeys.proxyPort: 'UseProxyPort',
  AppStringKeys.proxySecret: 'UseProxySecret',
  AppStringKeys.proxyServer: 'UseProxyAddress',
  AppStringKeys.proxyTitle: 'Proxy',
  AppStringKeys.qrCodeGroupTitle: 'InviteLink',
  AppStringKeys.qrCodeMineTitle: 'QrCode',
  AppStringKeys.qrCodeScanToJoinGroup: 'JoinGroup',
  AppStringKeys.richTextComposerFormatBold: 'Bold',
  AppStringKeys.richTextComposerFormatCode: 'Code',
  AppStringKeys.richTextComposerFormatItalic: 'Italic',
  AppStringKeys.richTextComposerFormatSpoiler: 'Spoiler',
  AppStringKeys.richTextComposerFormatStrikethrough: 'Strike',
  AppStringKeys.richTextComposerFormatUnderline: 'Underline',
  AppStringKeys.richTextComposerInsertTable: 'AccDescrIVTable',
  AppStringKeys.richTextComposerPhotoVideo: 'SharedMediaTab',
  AppStringKeys.richTextComposerRemoveColumn: 'Delete',
  AppStringKeys.richTextComposerRemoveRow: 'Delete',
  AppStringKeys.richTextComposerRemoveTable: 'Delete',
  AppStringKeys.settingsLogOut: 'LogOut',
  AppStringKeys.sharedMediaCacheDeleteFailed: 'ErrorOccurred',
  AppStringKeys.sharedMediaChatFiles: 'SharedFilesTab',
  AppStringKeys.sharedMediaDeleteLocalCache: 'ClearHistoryCache',
  AppStringKeys.sharedMediaEmpty: 'NoMedia',
  AppStringKeys.sharedMediaFilterAll: 'AllMedia',
  AppStringKeys.sharedMediaFilterDownloaded: 'Downloaded',
  AppStringKeys.sharedMediaFilterNotDownloaded: 'NotDownloaded',
  AppStringKeys.sharedMediaLinks: 'SharedLinksTab',
  AppStringKeys.sharedMediaNoMatches: 'NoResult',
  AppStringKeys.sharedMediaPhotosAndVideos: 'SharedMediaTab',
  AppStringKeys.sharedMediaSearchFilesHint: 'Search',
  AppStringKeys.sharedMediaSearchVideosHint: 'Search',
  AppStringKeys.sharedMediaVideoTitleWithDate: 'AttachVideo',
  AppStringKeys.sharedMediaVideos: 'AttachVideo',
  AppStringKeys.sharedMediaVoice: 'AttachAudio',
  AppStringKeys.sharedMediaVoiceMessages: 'VoiceMessages',
  AppStringKeys.startButton: 'Start',
  AppStringKeys.stickerSetDetailActionFailed: 'ErrorOccurred',
  AppStringKeys.stickerSetDetailStickerCount: 'AttachSticker',
  AppStringKeys.stickerStoreRecent: 'Recent',
  AppStringKeys.stickerViewerInCollection: 'Added',
  AppStringKeys.stickerViewerView: 'ViewPackPreview',
  AppStringKeys.storyLoadFailed: 'ErrorOccurred',
  AppStringKeys.storyUnsupported: 'StoryUnsupported',
  AppStringKeys.tabChannels: 'Channel',
  AppStringKeys.tabContacts: 'Contacts',
  AppStringKeys.tabMessages: 'SearchAllChatsShort',
  AppStringKeys.tabSelectChannelContent: 'Channel',
  AppStringKeys.tabSelectContact: 'SelectContact',
  AppStringKeys.tdMessageAutoDeleteTimerChanged: 'AutoDeleteTimerSet',
  AppStringKeys.tdMessageAutoDeleteTimerDisabled: 'AutoDeleteTimerDisabled',
  AppStringKeys.tdMessageChecklist: 'AttachChecklist',
  AppStringKeys.tdMessageContactCard: 'AttachContact',
  AppStringKeys.tdMessageDaysDuration: 'Days',
  AppStringKeys.tdMessageDice: 'DiceInfo2',
  AppStringKeys.tdMessageExpiredPhoto: 'AttachDestructingPhotoExpired',
  AppStringKeys.tdMessageExpiredVideo: 'AttachDestructingVideoExpired',
  AppStringKeys.tdMessageFileWithName: 'AttachDocument',
  AppStringKeys.tdMessageForwardedStory: 'ForwardedStory',
  AppStringKeys.tdMessageGame: 'AttachGame',
  AppStringKeys.tdMessageGift: 'ActionGift',
  AppStringKeys.tdMessageGiveaway: 'BoostingGiveaway',
  AppStringKeys.tdMessageGroupCreated: 'ActionCreateGroup',
  AppStringKeys.tdMessageGroupNameChanged: 'ActionChangedTitle',
  AppStringKeys.tdMessageGroupPhotoDeleted: 'ActionRemovedPhoto',
  AppStringKeys.tdMessageGroupPhotoUpdated: 'ActionChangedPhoto',
  AppStringKeys.tdMessageGroupVideoChatEnded: 'VoipGroupVoiceChatEnded',
  AppStringKeys.tdMessageGroupVideoChatStarted: 'VoipGroupVoiceChatStarted',
  AppStringKeys.tdMessageHoursDuration: 'Hours',
  AppStringKeys.tdMessageJoinedGroupByLink: 'ActionInviteUser',
  AppStringKeys.tdMessageLastSeenUnknown: 'LastSeen',
  AppStringKeys.tdMessageMemberLeftGroup: 'ActionKickUser',
  AppStringKeys.tdMessageMessagePinned: 'ActionPinnedText',
  AppStringKeys.tdMessageMinutesDuration: 'Minutes',
  AppStringKeys.tdMessageMusic: 'AttachMusic',
  AppStringKeys.tdMessageNewMemberJoinedGroup: 'ActionAddUser',
  AppStringKeys.tdMessageNoAudio: 'NoAudioFiles',
  AppStringKeys.tdMessageNoFiles: 'NoSharedFiles',
  AppStringKeys.tdMessageNoLinks: 'NoSharedLinks',
  AppStringKeys.tdMessageNoMembers: 'NoMembers',
  AppStringKeys.tdMessageNoPhotoVideo: 'NoMedia',
  AppStringKeys.tdMessageNoStickers: 'NoStickers',
  AppStringKeys.tdMessageNoVoice: 'NoVoiceMessages',
  AppStringKeys.tdMessagePaidContent: 'PaidMedia',
  AppStringKeys.tdMessagePhotoVideo: 'SharedMediaTab2',
  AppStringKeys.tdMessagePoll: 'Poll',
  AppStringKeys.tdMessageProduct: 'PaymentInvoice',
  AppStringKeys.tdMessageSecondsDuration: 'Seconds',
  AppStringKeys.tdMessageSticker: 'AttachSticker',
  AppStringKeys.tdMessageStickerPreview: 'AttachSticker',
  AppStringKeys.tdMessageStickerWithEmoji: 'AttachSticker',
  AppStringKeys.tdMessageSubmission: 'ActionSuggestedPost',
  AppStringKeys.tdMessageSystemMessage: 'SystemMessage',
  AppStringKeys.tdMessageUnsupportedCurrentVersion: 'UnsupportedAttachment',
  AppStringKeys.tdMessageUserJoinedTelegram: 'NotificationContactJoined',
  AppStringKeys.tdMessageVideoCall: 'CallMessageVideoIncoming',
  AppStringKeys.tdMessageVideoMessage: 'AttachRound',
  AppStringKeys.tdMessageVoiceCall: 'CallMessageIncoming',
  AppStringKeys.themeModeDark: 'ThemeDark',
  AppStringKeys.themeModeLight: 'ThemeDay',
  AppStringKeys.themeUnreadMessageCount: 'UnreadMessages',
  AppStringKeys.topicChatAllFilter: 'All',
  AppStringKeys.topicChatAllTopics: 'Topics',
  AppStringKeys.topicChatBrowseCount: 'Views',
  AppStringKeys.topicChatChannelMembers: 'ChannelMembers',
  AppStringKeys.topicChatChannelMessages: 'ChannelMessages',
  AppStringKeys.topicChatChannelSettings: 'ChannelSettings',
  AppStringKeys.topicChatCommentCount: 'CommentsNoNumber',
  AppStringKeys.topicChatExpand: 'PollExpand',
  AppStringKeys.topicChatInvite: 'AddMember',
  AppStringKeys.topicChatLeave: 'LeaveMegaMenu',
  AppStringKeys.topicChatLeaveChannel: 'LeaveChannel',
  AppStringKeys.topicChatLeaveChannelFailed: 'ErrorOccurred',
  AppStringKeys.topicChatLoading: 'Loading',
  AppStringKeys.topicChatMemberCount: 'Members',
  AppStringKeys.topicChatMuteFailed: 'ErrorOccurred',
  AppStringKeys.topicChatMyProfile: 'MyProfile',
  AppStringKeys.topicChatPinToggle: 'PinMessage',
  AppStringKeys.topicChatPublish: 'SendMessage',
  AppStringKeys.topicChatReplyCount: 'RepliesTitle',
  AppStringKeys.topicChatSearch: 'Search',
  AppStringKeys.topicChatSelectSection: 'SelectChat',
  AppStringKeys.topicChatSelectTime: 'JumpToDate',
  AppStringKeys.topicChatSetPinnedFailed: 'ErrorOccurred',
  AppStringKeys.topicChatShare: 'ShareFile',
  AppStringKeys.topicChatTopicCount: 'Topics',
  AppStringKeys.topicChatTopicTitle: 'Topics',
  AppStringKeys.topicChatUsers: 'Members',
  AppStringKeys.topicPostContentActionFailed: 'ErrorOccurred',
  AppStringKeys.topicPostContentCopied: 'TextCopied',
  AppStringKeys.topicPostContentCopiedQuery: 'TextCopied',
  AppStringKeys.topicPostContentFile: 'AttachDocument',
  AppStringKeys.translationLibreTranslateNoResult: 'TranslationFailedAlert2',
  AppStringKeys.translationLingvaNoResult: 'TranslationFailedAlert2',
  AppStringKeys.translationMyMemoryNoResult: 'TranslationFailedAlert2',
  AppStringKeys.translationNativeNoResult: 'TranslationFailedAlert2',
  AppStringKeys.translationSettingsTitle: 'TranslateMessage',
  AppStringKeys.updateAction: 'Update',
  AppStringKeys.updateLater: 'AppUpdateRemindMeLater',
  AppStringKeys.updateVersionPrompt: 'AppUpdateVersionAndSize',
  AppStringKeys.videoPlayerCachedLocally: 'Downloaded',
  AppStringKeys.videoPlayerCannotPlay: 'UnsupportedMedia2',
  AppStringKeys.videoPlayerForwardUnsupported: 'UnsupportedMedia2',
  AppStringKeys.videoPlayerFullscreen: 'AccSwitchToFullscreen',
  AppStringKeys.videoPlayerLoadFailed: 'ErrorOccurred',
  AppStringKeys.videoPlayerLoading: 'Loading',
  AppStringKeys.videoPlayerPictureInPictureFailed: 'ErrorOccurred',
  AppStringKeys.videoPlayerPlaybackSpeed: 'VideoPlayerSpeed',
  AppStringKeys.videoPlayerWaitingForFile: 'BotFileDownloading',
};
