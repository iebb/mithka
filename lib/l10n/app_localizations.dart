import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'country_names.dart';
import 'messages/de.dart';
import 'messages/en.dart';
import 'messages/es.dart';
import 'messages/fr.dart';
import 'messages/ja.dart';
import 'messages/ko.dart';
import 'messages/zh_hans.dart';
import 'messages/zh_hant.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const fallbackLocale = Locale('en');
  static const supportedLocales = [
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ja'),
    Locale('ko'),
    Locale('en'),
    Locale('fr'),
    Locale('es'),
    Locale('de'),
  ];

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static bool isSupportedLocale(Locale locale) =>
      supportedLocales.any((supported) {
        if (supported.languageCode != locale.languageCode) return false;
        if (supported.scriptCode == null) return true;
        return supported.scriptCode == locale.scriptCode ||
            (supported.scriptCode == 'Hans' &&
                locale.languageCode == 'zh' &&
                locale.scriptCode == null);
      });

  static Locale resolve(Locale locale) {
    if (locale.languageCode == 'zh') {
      final isTraditional =
          locale.scriptCode == 'Hant' ||
          locale.countryCode == 'TW' ||
          locale.countryCode == 'HK' ||
          locale.countryCode == 'MO';
      return isTraditional
          ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')
          : const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
    }
    return supportedLocales.firstWhere(
      (supported) => supported.languageCode == locale.languageCode,
      orElse: () => fallbackLocale,
    );
  }

  static Locale? localeFromTag(String? tag) {
    final normalized = tag?.trim().replaceAll('_', '-');
    if (normalized == null || normalized.isEmpty || normalized == 'system') {
      return null;
    }
    final parts = normalized
        .split('-')
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;

    final language = parts.first.toLowerCase();
    String? script;
    String? country;
    for (final part in parts.skip(1)) {
      if (part.length == 4 && script == null) {
        script =
            part.substring(0, 1).toUpperCase() +
            part.substring(1).toLowerCase();
      } else if ((part.length == 2 || part.length == 3) && country == null) {
        country = part.toUpperCase();
      }
    }

    return Locale.fromSubtags(
      languageCode: language,
      scriptCode: script,
      countryCode: country,
    );
  }

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(fallbackLocale);

  static String localeKeyFor(Locale locale) {
    if (locale.languageCode == 'zh') {
      return locale.scriptCode == 'Hant' ||
              locale.countryCode == 'TW' ||
              locale.countryCode == 'HK' ||
              locale.countryCode == 'MO'
          ? 'zhHant'
          : 'zhHans';
    }
    return locale.languageCode;
  }

  String get _key => localeKeyFor(locale);

  String t(String key, [Map<String, Object?> placeholders = const {}]) =>
      AppStrings.tForLocaleWithTelegram(_key, key, placeholders);

  String format(String key, String value) =>
      t(key, {'value1': value, 'value': value});
}

extension LocalizedString on String {
  String l10n(BuildContext context) => AppLocalizations.of(context).t(this);
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

abstract final class AppStringKeys {
  static const aboutReportProblem = 'aboutReportProblem';
  static const aboutReportProblemDetail = 'aboutReportProblemDetail';
  static const aboutTelegramChannel = 'aboutTelegramChannel';
  static const aboutTitle = 'aboutTitle';
  static const aboutVersion = 'aboutVersion';
  static const aboutWebsite = 'aboutWebsite';
  static const feedbackReportDescription = 'feedbackReportDescription';
  static const feedbackReportFailed = 'feedbackReportFailed';
  static const feedbackReportPlaceholder = 'feedbackReportPlaceholder';
  static const feedbackReportPrivacy = 'feedbackReportPrivacy';
  static const feedbackReportSend = 'feedbackReportSend';
  static const feedbackReportSending = 'feedbackReportSending';
  static const feedbackReportSent = 'feedbackReportSent';
  static const feedbackReportTitle = 'feedbackReportTitle';
  static const accentColorPickerSave = 'accentColorPickerSave';
  static const accountBackupCopied = 'accountBackupCopied';
  static const accountBackupCopyPyrogramMessage =
      'accountBackupCopyPyrogramMessage';
  static const accountBackupCopyPyrogramSession =
      'accountBackupCopyPyrogramSession';
  static const accountBackupCopyPyrogramTitle =
      'accountBackupCopyPyrogramTitle';
  static const accountBackupCreate = 'accountBackupCreate';
  static const accountBackupDeleteInvalidSession =
      'accountBackupDeleteInvalidSession';
  static const accountBackupDeleteMessage = 'accountBackupDeleteMessage';
  static const accountBackupDeleteTitle = 'accountBackupDeleteTitle';
  static const accountBackupEmpty = 'accountBackupEmpty';
  static const accountBackupEnabled = 'accountBackupEnabled';
  static const accountBackupFreshSessionCreate =
      'accountBackupFreshSessionCreate';
  static const accountBackupFreshSessionInteractive =
      'accountBackupFreshSessionInteractive';
  static const accountBackupFreshSessionMessage =
      'accountBackupFreshSessionMessage';
  static const accountBackupFreshSessionReady =
      'accountBackupFreshSessionReady';
  static const accountBackupFreshSessionTitle =
      'accountBackupFreshSessionTitle';
  static const accountBackupFreshSessionUseRestored =
      'accountBackupFreshSessionUseRestored';
  static const accountBackupFreshSessionWaiting =
      'accountBackupFreshSessionWaiting';
  static const accountBackupImported = 'accountBackupImported';
  static const accountBackupInvalidImportedMessage =
      'accountBackupInvalidImportedMessage';
  static const accountBackupInvalidMessage = 'accountBackupInvalidMessage';
  static const accountBackupInvalidTitle = 'accountBackupInvalidTitle';
  static const accountBackupIOSOnly = 'accountBackupIOSOnly';
  static const accountBackupLoginAndroid = 'accountBackupLoginAndroid';
  static const accountBackupLoginDescription = 'accountBackupLoginDescription';
  static const accountBackupLoginICloud = 'accountBackupLoginICloud';
  static const accountBackupLoadPyrogramConfirm =
      'accountBackupLoadPyrogramConfirm';
  static const accountBackupLoadPyrogramMessage =
      'accountBackupLoadPyrogramMessage';
  static const accountBackupLoadPyrogramPaste =
      'accountBackupLoadPyrogramPaste';
  static const accountBackupLoadPyrogramPlaceholder =
      'accountBackupLoadPyrogramPlaceholder';
  static const accountBackupLoadPyrogramSession =
      'accountBackupLoadPyrogramSession';
  static const accountBackupLoadPyrogramTitle =
      'accountBackupLoadPyrogramTitle';
  static const accountBackupNotice = 'accountBackupNotice';
  static const accountBackupNoticeAndroid = 'accountBackupNoticeAndroid';
  static const accountBackupNoticeICloud = 'accountBackupNoticeICloud';
  static const accountBackupRestore = 'accountBackupRestore';
  static const accountBackupRestoreAccount = 'accountBackupRestoreAccount';
  static const accountBackupRestored = 'accountBackupRestored';
  static const accountBackupRestoreMessage = 'accountBackupRestoreMessage';
  static const accountBackupRestoreTitle = 'accountBackupRestoreTitle';
  static const accountBackupSaved = 'accountBackupSaved';
  static const accountBackupSessions = 'accountBackupSessions';
  static const accountBackupTitle = 'accountBackupTitle';
  static const accountBackupUnavailable = 'accountBackupUnavailable';
  static const accountBackupUserId = 'accountBackupUserId';
  static const mithkaProActive = 'mithkaProActive';
  static const mithkaProActiveUntil = 'mithkaProActiveUntil';
  static const mithkaProBackupLimitReached = 'mithkaProBackupLimitReached';
  static const mithkaProBestValue = 'mithkaProBestValue';
  static const mithkaProBillingNotice = 'mithkaProBillingNotice';
  static const mithkaProContinue = 'mithkaProContinue';
  static const mithkaProFreePlan = 'mithkaProFreePlan';
  static const mithkaProLimitExempt = 'mithkaProLimitExempt';
  static const mithkaProManagePlan = 'mithkaProManagePlan';
  static const mithkaProMonthly = 'mithkaProMonthly';
  static const mithkaProNothingToRestore = 'mithkaProNothingToRestore';
  static const mithkaProPerMonth = 'mithkaProPerMonth';
  static const mithkaProPerYear = 'mithkaProPerYear';
  static const mithkaProPurchaseFailed = 'mithkaProPurchaseFailed';
  static const mithkaProPrivacy = 'mithkaProPrivacy';
  static const mithkaProRestore = 'mithkaProRestore';
  static const mithkaProRestoreFailed = 'mithkaProRestoreFailed';
  static const mithkaProStoreUnavailable = 'mithkaProStoreUnavailable';
  static const mithkaProTerms = 'mithkaProTerms';
  static const mithkaProTitle = 'mithkaProTitle';
  static const mithkaProUnlimitedCloudSessionSyncs =
      'mithkaProUnlimitedCloudSessionSyncs';
  static const mithkaProUnlimitedCloudSessionSyncsDescription =
      'mithkaProUnlimitedCloudSessionSyncsDescription';
  static const mithkaProYearly = 'mithkaProYearly';
  static const addMembersDone = 'addMembersDone';
  static const addMembersDoneWithCount = 'addMembersDoneWithCount';
  static const addMembersInviteMembersTitle = 'addMembersInviteMembersTitle';
  static const addMembersInvitePermissionError =
      'addMembersInvitePermissionError';
  static const addPeopleFindGroups = 'addPeopleFindGroups';
  static const addPeopleFindPeople = 'addPeopleFindPeople';
  static const addPeopleGroupNameOrLinkPlaceholder =
      'addPeopleGroupNameOrLinkPlaceholder';
  static const addPeopleNoGroupsOrChannelsFound =
      'addPeopleNoGroupsOrChannelsFound';
  static const addPeopleNoUsersFound = 'addPeopleNoUsersFound';
  static const addPeopleUsernameOrPhonePlaceholder =
      'addPeopleUsernameOrPhonePlaceholder';
  static const advancedInput = 'advancedInput';
  static const advancedNetwork = 'advancedNetwork';
  static const advancedTitle = 'advancedTitle';
  static const apiCredentialsCustomClientApi = 'apiCredentialsCustomClientApi';
  static const apiCredentialsDescription = 'apiCredentialsDescription';
  static const apiCredentialsTitle = 'apiCredentialsTitle';
  static const appearanceAddFont = 'appearanceAddFont';
  static const appearanceAddTextFont = 'appearanceAddTextFont';
  static const appearanceAlwaysShowMessageTime =
      'appearanceAlwaysShowMessageTime';
  static const appearanceAnimateAvatars = 'appearanceAnimateAvatars';
  static const appearanceArchivedChats = 'appearanceArchivedChats';
  static const appearanceArchivedChatsHidden = 'appearanceArchivedChatsHidden';
  static const appearanceArchivedChatsPullDown =
      'appearanceArchivedChatsPullDown';
  static const appearanceCacheCleaned = 'appearanceCacheCleaned';
  static const appearanceCacheFiles = 'appearanceCacheFiles';
  static const appearanceCacheRefreshed = 'appearanceCacheRefreshed';
  static const appearanceCapUnreadCountAt99 = 'appearanceCapUnreadCountAt99';
  static const appearanceChatFolders = 'appearanceChatFolders';
  static const appearanceChatFoldersHidden = 'appearanceChatFoldersHidden';
  static const appearanceChatFoldersMenu = 'appearanceChatFoldersMenu';
  static const appearanceChatFoldersTabs = 'appearanceChatFoldersTabs';
  static const appearanceChatList = 'appearanceChatList';
  static const appearanceChatListFolderSwipeSwitching =
      'appearanceChatListFolderSwipeSwitching';
  static const appearanceChatView = 'appearanceChatView';
  static const appearanceCleanableSize = 'appearanceCleanableSize';
  static const appearanceCleanUnusedFonts = 'appearanceCleanUnusedFonts';
  static const appearanceClearTextFonts = 'appearanceClearTextFonts';
  static const appearanceColor = 'appearanceColor';
  static const appearanceDisableChatListSwipeActions =
      'appearanceDisableChatListSwipeActions';
  static const appearanceDisplay = 'appearanceDisplay';
  static const appearanceSavedMessagesBookmarkView =
      'appearanceSavedMessagesBookmarkView';
  static const appearanceGestures = 'appearanceGestures';
  static const appearanceDownloadFailed = 'appearanceDownloadFailed';
  static const appearanceEmojiFont = 'appearanceEmojiFont';
  static const appearanceEmojiFontCatalogDescription =
      'appearanceEmojiFontCatalogDescription';
  static const appearanceEnableTheming = 'appearanceEnableTheming';
  static const appearancePerAccountTheming = 'appearancePerAccountTheming';
  static const appearanceFileCount = 'appearanceFileCount';
  static const appearanceFont = 'appearanceFont';
  static const appearanceFontCache = 'appearanceFontCache';
  static const appearanceFontCacheDescription =
      'appearanceFontCacheDescription';
  static const appearanceFontChainDescription =
      'appearanceFontChainDescription';
  static const appearanceFontDownloadFailedName =
      'appearanceFontDownloadFailedName';
  static const appearanceFontInUse = 'appearanceFontInUse';
  static const appearanceFontLoadFailed = 'appearanceFontLoadFailed';
  static const appearanceFontSize = 'appearanceFontSize';
  static const appearanceFontUnused = 'appearanceFontUnused';
  static const appearanceGoogleDownloaded = 'appearanceGoogleDownloaded';
  static const gesturesChatActions = 'gesturesChatActions';
  static const gesturesChatListSwipe = 'gesturesChatListSwipe';
  static const gesturesDoNothing = 'gesturesDoNothing';
  static const gesturesHoldSwipeActions = 'gesturesHoldSwipeActions';
  static const gesturesSwitchAccounts = 'gesturesSwitchAccounts';
  static const gesturesSwitchFolders = 'gesturesSwitchFolders';
  static const gesturesThreeFingerSwipe = 'gesturesThreeFingerSwipe';
  static const appearanceGroupAssistantPosition =
      'appearanceGroupAssistantPosition';
  static const appearanceHideBlockedUserMessages =
      'appearanceHideBlockedUserMessages';
  static const appearanceHidePhoneInSidebar = 'appearanceHidePhoneInSidebar';
  static const appearanceInterfaceSize = 'appearanceInterfaceSize';
  static const appearanceInUseSize = 'appearanceInUseSize';
  static const appearanceManage = 'appearanceManage';
  static const appearanceMergeConsecutiveImages =
      'appearanceMergeConsecutiveImages';
  static const appearanceMode = 'appearanceMode';
  static const appearanceMonospaceFont = 'appearanceMonospaceFont';
  static const appearanceNoCleanableFonts = 'appearanceNoCleanableFonts';
  static const appearanceNoDownloadedFontCache =
      'appearanceNoDownloadedFontCache';
  static const appearanceNoMatchingFonts = 'appearanceNoMatchingFonts';
  static const appearanceRefreshCacheList = 'appearanceRefreshCacheList';
  static const appearanceRoundGroupAvatars = 'appearanceRoundGroupAvatars';
  static const appearanceSearchFont = 'appearanceSearchFont';
  static const appearanceSenderNameBackground =
      'appearanceSenderNameBackground';
  static const appearanceShowChatListSearch = 'appearanceShowChatListSearch';
  static const appearanceShowEditAndReadMarks =
      'appearanceShowEditAndReadMarks';
  static const appearanceShowGroupMemberTitles =
      'appearanceShowGroupMemberTitles';
  static const appearanceShowPlainMemberRoleTags =
      'appearanceShowPlainMemberRoleTags';
  static const appearanceShowPremiumNameColor =
      'appearanceShowPremiumNameColor';
  static const appearanceShowPremiumStatusEmoji =
      'appearanceShowPremiumStatusEmoji';
  static const appearanceShowUnreadChatCount = 'appearanceShowUnreadChatCount';
  static const appearanceSize = 'appearanceSize';
  static const appearanceSystem = 'appearanceSystem';
  static const appearanceSystemEmojiFont = 'appearanceSystemEmojiFont';
  static const appearanceTextFont = 'appearanceTextFont';
  static const appearanceTextFontOrderHint = 'appearanceTextFontOrderHint';
  static const appearanceTextFontUnsetHint = 'appearanceTextFontUnsetHint';
  static const appearanceTheme = 'appearanceTheme';
  static const appearanceTitle = 'appearanceTitle';
  static const appearanceTotalSize = 'appearanceTotalSize';
  static const appearanceUnreadBadge = 'appearanceUnreadBadge';
  static const appearanceUseChatThemeForUi = 'appearanceUseChatThemeForUi';
  static const appIconBlueGradient = 'appIconBlueGradient';
  static const appIconChangeFailed = 'appIconChangeFailed';
  static const appIconDefault = 'appIconDefault';
  static const appIconPixel = 'appIconPixel';
  static const appIconPurpleGradient = 'appIconPurpleGradient';
  static const appIconTitle = 'appIconTitle';
  static const appIconUnsupported = 'appIconUnsupported';
  static const appIconWhite = 'appIconWhite';
  static const appLockBiometricDescription = 'appLockBiometricDescription';
  static const appLockBiometricEnableReason = 'appLockBiometricEnableReason';
  static const appLockBiometricFailed = 'appLockBiometricFailed';
  static const appLockBiometricLockedOut = 'appLockBiometricLockedOut';
  static const appLockBiometricReason = 'appLockBiometricReason';
  static const appLockBiometricUnavailable = 'appLockBiometricUnavailable';
  static const appLockBiometrics = 'appLockBiometrics';
  static const appLockChangePin = 'appLockChangePin';
  static const appLockChooseMethod = 'appLockChooseMethod';
  static const appLockChooseMethodDescription =
      'appLockChooseMethodDescription';
  static const appLockConfirmGesture = 'appLockConfirmGesture';
  static const appLockConfirmPin = 'appLockConfirmPin';
  static const appLockCreateGesture = 'appLockCreateGesture';
  static const appLockCreatePin = 'appLockCreatePin';
  static const appLockDescription = 'appLockDescription';
  static const appLockDrawGesture = 'appLockDrawGesture';
  static const appLockEnabled = 'appLockEnabled';
  static const appLockEnterPin = 'appLockEnterPin';
  static const appLockFaceId = 'appLockFaceId';
  static const appLockFingerprint = 'appLockFingerprint';
  static const appLockFingerprintUnlock = 'appLockFingerprintUnlock';
  static const appLockForgotGesture = 'appLockForgotGesture';
  static const appLockForgotPin = 'appLockForgotPin';
  static const appLockFaceUnlock = 'appLockFaceUnlock';
  static const appLockGesture = 'appLockGesture';
  static const appLockGestureDescription = 'appLockGestureDescription';
  static const appLockGestureGrid = 'appLockGestureGrid';
  static const appLockGestureMismatch = 'appLockGestureMismatch';
  static const appLockGestureTooShort = 'appLockGestureTooShort';
  static const appLockPin = 'appLockPin';
  static const appLockPinDescription = 'appLockPinDescription';
  static const appLockPinMismatch = 'appLockPinMismatch';
  static const appLockResetGesture = 'appLockResetGesture';
  static const appLockSetupFailed = 'appLockSetupFailed';
  static const appLockTitle = 'appLockTitle';
  static const appLockTryBiometric = 'appLockTryBiometric';
  static const appLockBiometricUnlock = 'appLockBiometricUnlock';
  static const appLockUnlockMethod = 'appLockUnlockMethod';
  static const appLockUnlockTitle = 'appLockUnlockTitle';
  static const appLockUseBiometric = 'appLockUseBiometric';
  static const appLockVerifyTitle = 'appLockVerifyTitle';
  static const appLockWrongGesture = 'appLockWrongGesture';
  static const appLockWrongPin = 'appLockWrongPin';
  static const appLocaleArabic = 'appLocaleArabic';
  static const appLocaleEnglish = 'appLocaleEnglish';
  static const appLocaleFollowSystem = 'appLocaleFollowSystem';
  static const appLocaleFrench = 'appLocaleFrench';
  static const appLocaleGerman = 'appLocaleGerman';
  static const appLocaleHindi = 'appLocaleHindi';
  static const appLocaleIndonesian = 'appLocaleIndonesian';
  static const appLocaleItalian = 'appLocaleItalian';
  static const appLocaleJapanese = 'appLocaleJapanese';
  static const appLocaleKorean = 'appLocaleKorean';
  static const appLocaleMalay = 'appLocaleMalay';
  static const appLocalePortuguese = 'appLocalePortuguese';
  static const appLocaleRussian = 'appLocaleRussian';
  static const appLocaleSimplifiedChinese = 'appLocaleSimplifiedChinese';
  static const appLocaleSpanish = 'appLocaleSpanish';
  static const appLocaleThai = 'appLocaleThai';
  static const appLocaleTraditionalChinese = 'appLocaleTraditionalChinese';
  static const appLocaleTurkish = 'appLocaleTurkish';
  static const appLocaleUkrainian = 'appLocaleUkrainian';
  static const appLocaleVietnamese = 'appLocaleVietnamese';
  static const archivedChatsGroupAssistant = 'archivedChatsGroupAssistant';
  static const audioSearchChatTab = 'audioSearchChatTab';
  static const audioSearchFailed = 'audioSearchFailed';
  static const audioSearchFetchingSource = 'audioSearchFetchingSource';
  static const audioSearchNoResults = 'audioSearchNoResults';
  static const audioSearchPlaceholder = 'audioSearchPlaceholder';
  static const audioSearchSendAudioFailed = 'audioSearchSendAudioFailed';
  static const audioSearchTelegramAudioTitle = 'audioSearchTelegramAudioTitle';
  static const authCodeExpiredRetry = 'authCodeExpiredRetry';
  static const authCodeSent = 'authCodeSent';
  static const authCodeSentByFlashCall = 'authCodeSentByFlashCall';
  static const authCodeSentByPhoneCall = 'authCodeSentByPhoneCall';
  static const authCodeSentBySms = 'authCodeSentBySms';
  static const authCodeSentToTelegramDevices = 'authCodeSentToTelegramDevices';
  static const authInvalidPassword = 'authInvalidPassword';
  static const authInvalidPhoneNumber = 'authInvalidPhoneNumber';
  static const authInvalidVerificationCode = 'authInvalidVerificationCode';
  static const autoDeleteAfterOneDay = 'autoDeleteAfterOneDay';
  static const autoDeleteAfterOneMonth = 'autoDeleteAfterOneMonth';
  static const autoDeleteAfterOneWeek = 'autoDeleteAfterOneWeek';
  static const autoDeleteDescription = 'autoDeleteDescription';
  static const blockByCountrySearchHint = 'blockByCountrySearchHint';
  static const blockByCountryTitle = 'blockByCountryTitle';
  static const businessSettingsAlwaysOpen = 'businessSettingsAlwaysOpen';
  static const businessSettingsChatLink = 'businessSettingsChatLink';
  static const businessSettingsChatLinks = 'businessSettingsChatLinks';
  static const businessSettingsChatLinksEmpty =
      'businessSettingsChatLinksEmpty';
  static const businessSettingsChatLinksSubtitle =
      'businessSettingsChatLinksSubtitle';
  static const businessSettingsDeleteLink = 'businessSettingsDeleteLink';
  static const businessSettingsEmojiStatus = 'businessSettingsEmojiStatus';
  static const businessSettingsEmojiStatusSet =
      'businessSettingsEmojiStatusSet';
  static const businessSettingsEntry = 'businessSettingsEntry';
  static const businessSettingsFriday = 'businessSettingsFriday';
  static const businessSettingsHoursSet = 'businessSettingsHoursSet';
  static const businessSettingsLinkDraft = 'businessSettingsLinkDraft';
  static const businessSettingsLinkDraftHint = 'businessSettingsLinkDraftHint';
  static const businessSettingsLinkTitle = 'businessSettingsLinkTitle';
  static const businessSettingsLinkTitleHint = 'businessSettingsLinkTitleHint';
  static const businessSettingsLocation = 'businessSettingsLocation';
  static const businessSettingsLocationAddressHint =
      'businessSettingsLocationAddressHint';
  static const businessSettingsLocationAddressRequired =
      'businessSettingsLocationAddressRequired';
  static const businessSettingsMonday = 'businessSettingsMonday';
  static const businessSettingsNotSet = 'businessSettingsNotSet';
  static const businessSettingsOpeningHours = 'businessSettingsOpeningHours';
  static const businessSettingsProfile = 'businessSettingsProfile';
  static const businessSettingsRemoveHours = 'businessSettingsRemoveHours';
  static const businessSettingsRemoveLocation =
      'businessSettingsRemoveLocation';
  static const businessSettingsRemoveStartPage =
      'businessSettingsRemoveStartPage';
  static const businessSettingsSaturday = 'businessSettingsSaturday';
  static const businessSettingsSaveFailed = 'businessSettingsSaveFailed';
  static const businessSettingsSetOnMap = 'businessSettingsSetOnMap';
  static const businessSettingsStartPage = 'businessSettingsStartPage';
  static const businessSettingsStartPageMessage =
      'businessSettingsStartPageMessage';
  static const businessSettingsStartPageMessageHint =
      'businessSettingsStartPageMessageHint';
  static const businessSettingsStartPageRequired =
      'businessSettingsStartPageRequired';
  static const businessSettingsStartPageTitle =
      'businessSettingsStartPageTitle';
  static const businessSettingsStartPageTitleHint =
      'businessSettingsStartPageTitleHint';
  static const businessSettingsSummary = 'businessSettingsSummary';
  static const businessSettingsSunday = 'businessSettingsSunday';
  static const businessSettingsThursday = 'businessSettingsThursday';
  static const businessSettingsTimeZone = 'businessSettingsTimeZone';
  static const businessSettingsTitle = 'businessSettingsTitle';
  static const businessSettingsTools = 'businessSettingsTools';
  static const businessSettingsTuesday = 'businessSettingsTuesday';
  static const businessSettingsWednesday = 'businessSettingsWednesday';
  static const callAccept = 'callAccept';
  static const callCamera = 'callCamera';
  static const callConnecting = 'callConnecting';
  static const callDecline = 'callDecline';
  static const callEnded = 'callEnded';
  static const callEndToEndEncrypted = 'callEndToEndEncrypted';
  static const callFrontCamera = 'callFrontCamera';
  static const callHangUp = 'callHangUp';
  static const callIncomingCallInvite = 'callIncomingCallInvite';
  static const callMute = 'callMute';
  static const callRearCamera = 'callRearCamera';
  static const callSelectCamera = 'callSelectCamera';
  static const callSpeakerphone = 'callSpeakerphone';
  static const callWaitingForInviteAccept = 'callWaitingForInviteAccept';
  static const callsEmpty = 'callsEmpty';
  static const callsIncoming = 'callsIncoming';
  static const callsLoadFailed = 'callsLoadFailed';
  static const callsOutgoing = 'callsOutgoing';
  static const callsRetry = 'callsRetry';
  static const callsTitle = 'callsTitle';
  static const callsUnknownConversation = 'callsUnknownConversation';
  static const channelsFileAttachment = 'channelsFileAttachment';
  static const channelsLoading = 'channelsLoading';
  static const channelsNoTopicChannels = 'channelsNoTopicChannels';
  static const chatActionChoosingContact = 'chatActionChoosingContact';
  static const chatActionChoosingLocation = 'chatActionChoosingLocation';
  static const chatActionChoosingSticker = 'chatActionChoosingSticker';
  static const chatActionPlayingGame = 'chatActionPlayingGame';
  static const chatActionRecordingVideo = 'chatActionRecordingVideo';
  static const chatActionRecordingVideoNote = 'chatActionRecordingVideoNote';
  static const chatActionRecordingVoice = 'chatActionRecordingVoice';
  static const chatActionUploadingFile = 'chatActionUploadingFile';
  static const chatActionUploadingPhoto = 'chatActionUploadingPhoto';
  static const chatActionUploadingVideo = 'chatActionUploadingVideo';
  static const chatActionUploadingVideoNote = 'chatActionUploadingVideoNote';
  static const chatActionUploadingVoice = 'chatActionUploadingVoice';
  static const chatActionWatchingAnimations = 'chatActionWatchingAnimations';
  static const chatAdminAnonymous = 'chatAdminAnonymous';
  static const chatAdminDeleteMessages = 'chatAdminDeleteMessages';
  static const chatAdminManageChat = 'chatAdminManageChat';
  static const chatAdminManageVideoChats = 'chatAdminManageVideoChats';
  static const chatAdminPromoteMembers = 'chatAdminPromoteMembers';
  static const chatAdminRestrictMembers = 'chatAdminRestrictMembers';
  static const chatAdminsOnlyPosting = 'chatAdminsOnlyPosting';
  static const chatAllMembersMuted = 'chatAllMembersMuted';
  static const chatAndOthersCount = 'chatAndOthersCount';
  static const chatAutoDeleteCountdown = 'chatAutoDeleteCountdown';
  static const chatBlockUserConfirm = 'chatBlockUserConfirm';
  static const chatBlockUserDone = 'chatBlockUserDone';
  static const chatBlockUserFailed = 'chatBlockUserFailed';
  static const chatBlockUserMessage = 'chatBlockUserMessage';
  static const chatBlockUserTitle = 'chatBlockUserTitle';
  static const chatButtonUnsupported = 'chatButtonUnsupported';
  static const chatCannotSendMessages = 'chatCannotSendMessages';
  static const chatContactCallsOnly = 'chatContactCallsOnly';
  static const chatFirstContactNotContact = 'chatFirstContactNotContact';
  static const chatFirstContactNotOfficial = 'chatFirstContactNotOfficial';
  static const chatFirstContactOfficial = 'chatFirstContactOfficial';
  static const chatFirstContactPhoneCountry = 'chatFirstContactPhoneCountry';
  static const chatFirstContactRegistration = 'chatFirstContactRegistration';
  static const chatDelete = 'chatDelete';
  static const chatDeleteActionsDone = 'chatDeleteActionsDone';
  static const chatDeleteActionsFailed = 'chatDeleteActionsFailed';
  static const chatDeleteAllMembersDescription =
      'chatDeleteAllMembersDescription';
  static const chatDeleteBothSidesDescription =
      'chatDeleteBothSidesDescription';
  static const chatDeleteForAllMembers = 'chatDeleteForAllMembers';
  static const chatDeleteForBothSides = 'chatDeleteForBothSides';
  static const chatDeleteForMe = 'chatDeleteForMe';
  static const chatDeleteMessagesQuestion = 'chatDeleteMessagesQuestion';
  static const chatDeleteOptionBlockSender = 'chatDeleteOptionBlockSender';
  static const chatDeleteOptionDeleteAllFromSender =
      'chatDeleteOptionDeleteAllFromSender';
  static const chatDeleteOptionDeleteMessage = 'chatDeleteOptionDeleteMessage';
  static const chatDeleteOptionReportSpam = 'chatDeleteOptionReportSpam';
  static const chatDeleteScopeGroupDescription =
      'chatDeleteScopeGroupDescription';
  static const chatDeleteScopePrivateDescription =
      'chatDeleteScopePrivateDescription';
  static const chatDeleteSelectedMessagesConfirmation =
      'chatDeleteSelectedMessagesConfirmation';
  static const chatDeleteSingleMessageQuestion =
      'chatDeleteSingleMessageQuestion';
  static const chatDeleteUnavailable = 'chatDeleteUnavailable';
  static const chatEditMessageTitle = 'chatEditMessageTitle';
  static const chatEditPlainText = 'chatEditPlainText';
  static const chatForwardedToName = 'chatForwardedToName';
  static const chatForwardFailed = 'chatForwardFailed';
  static const chatForwardProtected = 'chatForwardProtected';
  static const chatForwardRemoveCaption = 'chatForwardRemoveCaption';
  static const chatForwardRemoveSender = 'chatForwardRemoveSender';
  static const chatForwardToTitle = 'chatForwardToTitle';
  static const chatInfoAlbum = 'chatInfoAlbum';
  static const chatInfoAutoDeleteMessages = 'chatInfoAutoDeleteMessages';
  static const chatInfoAutoDeleteOff = 'chatInfoAutoDeleteOff';
  static const chatInfoAutoDeleteOneDay = 'chatInfoAutoDeleteOneDay';
  static const chatInfoAutoDeleteOneMonth = 'chatInfoAutoDeleteOneMonth';
  static const chatInfoAutoDeleteSevenDays = 'chatInfoAutoDeleteSevenDays';
  static const chatInfoChatFolders = 'chatInfoChatFolders';
  static const chatInfoClear = 'chatInfoClear';
  static const chatInfoClearHistory = 'chatInfoClearHistory';
  static const chatInfoClearHistoryDescription =
      'chatInfoClearHistoryDescription';
  static const chatInfoClearHistoryIrreversibleWarning =
      'chatInfoClearHistoryIrreversibleWarning';
  static const chatInfoClearHistoryQuestion = 'chatInfoClearHistoryQuestion';
  static const chatInfoConfirmAgain = 'chatInfoConfirmAgain';
  static const chatInfoConfirmClearHistory = 'chatInfoConfirmClearHistory';
  static const chatInfoCreate = 'chatInfoCreate';
  static const chatInfoCreateFolderFailed = 'chatInfoCreateFolderFailed';
  static const chatInfoCreateFolderTitle = 'chatInfoCreateFolderTitle';
  static const chatInfoDisableExplicitFolderWarning =
      'chatInfoDisableExplicitFolderWarning';
  static const chatInfoFolderName = 'chatInfoFolderName';
  static const chatInfoFolderNameLabel = 'chatInfoFolderNameLabel';
  static const chatInfoGroupAlbum = 'chatInfoGroupAlbum';
  static const chatInfoGroupApps = 'chatInfoGroupApps';
  static const chatInfoGroupChat = 'chatInfoGroupChat';
  static const chatInfoGroupFiles = 'chatInfoGroupFiles';
  static const chatInfoGroupId = 'chatInfoGroupId';
  static const chatInfoGroupMembers = 'chatInfoGroupMembers';
  static const chatInfoGroupVideos = 'chatInfoGroupVideos';
  static const chatInfoLeaveGroup = 'chatInfoLeaveGroup';
  static const chatInfoLoadFoldersFailed = 'chatInfoLoadFoldersFailed';
  static const chatInfoManageGroup = 'chatInfoManageGroup';
  static const chatInfoMoveToGroupAssistant = 'chatInfoMoveToGroupAssistant';
  static const chatInfoNewFolder = 'chatInfoNewFolder';
  static const chatInfoNoFolders = 'chatInfoNoFolders';
  static const chatInfoNotSearchable = 'chatInfoNotSearchable';
  static const chatInfoPin = 'chatInfoPin';
  static const chatInfoPinChat = 'chatInfoPinChat';
  static const chatInfoPinFailed = 'chatInfoPinFailed';
  static const chatInfoPinFailedWithReason = 'chatInfoPinFailedWithReason';
  static const chatInfoPinLimit = 'chatInfoPinLimit';
  static const chatInfoPinLimitReachedError = 'chatInfoPinLimitReachedError';
  static const chatInfoPinnedHighlights = 'chatInfoPinnedHighlights';
  static const chatInfoRemove = 'chatInfoRemove';
  static const chatInfoSearchHistory = 'chatInfoSearchHistory';
  static const chatInfoTitle = 'chatInfoTitle';
  static const chatInlineSwitchButtonUnsupported =
      'chatInlineSwitchButtonUnsupported';
  static const chatJoinGroup = 'chatJoinGroup';
  static const chatJoinRequestPending = 'chatJoinRequestPending';
  static const chatJoinRequestSent = 'chatJoinRequestSent';
  static const chatListAddFriendOrGroup = 'chatListAddFriendOrGroup';
  static const chatListBlockedPlaceholder = 'chatListBlockedPlaceholder';
  static const chatListChannelName = 'chatListChannelName';
  static const chatListCreateChannel = 'chatListCreateChannel';
  static const chatListCreateChannelFailed = 'chatListCreateChannelFailed';
  static const chatListCreateGroup = 'chatListCreateGroup';
  static const chatListDeleteChatQuestion = 'chatListDeleteChatQuestion';
  static const chatListLeaveAndDeleteGroupConfirmation =
      'chatListLeaveAndDeleteGroupConfirmation';
  static const chatListMarkUnread = 'chatListMarkUnread';
  static const chatListNoChats = 'chatListNoChats';
  static const chatListScanQrCode = 'chatListScanQrCode';
  static const chatListUnpin = 'chatListUnpin';
  static const chatLoadingTopics = 'chatLoadingTopics';
  static const chatMediaDelete = 'chatMediaDelete';
  static const chatMediaReplace = 'chatMediaReplace';
  static const chatMeLabel = 'chatMeLabel';
  static const chatMemberCount = 'chatMemberCount';
  static const chatMembersAdministratorsTitle =
      'chatMembersAdministratorsTitle';
  static const chatMembersAdminPermissions = 'chatMembersAdminPermissions';
  static const chatMembersAdminSave = 'chatMembersAdminSave';
  static const chatMembersDemote = 'chatMembersDemote';
  static const chatMembersDemoteConfirmation = 'chatMembersDemoteConfirmation';
  static const chatMembersPromote = 'chatMembersPromote';
  static const chatMembersPromoteFirst = 'chatMembersPromoteFirst';
  static const chatMembersRemoveFailedPermission =
      'chatMembersRemoveFailedPermission';
  static const chatMembersRemoveMemberConfirmation =
      'chatMembersRemoveMemberConfirmation';
  static const chatMembersRemoveMemberTitle = 'chatMembersRemoveMemberTitle';
  static const chatMembersSetTitle = 'chatMembersSetTitle';
  static const chatMembersTitleWithCount = 'chatMembersTitleWithCount';
  static const chatMembersUpdateFailed = 'chatMembersUpdateFailed';
  static const chatMenu = 'chatMenu';
  static const chatMessageInputPlaceholder = 'chatMessageInputPlaceholder';
  static const chatMessageRequired = 'chatMessageRequired';
  static const chatMessagesForwardedCount = 'chatMessagesForwardedCount';
  static const chatMessagesSavedCount = 'chatMessagesSavedCount';
  static const chatMoreActionsUnsupported = 'chatMoreActionsUnsupported';
  static const chatNewMessagesCount = 'chatNewMessagesCount';
  static const chatNewMessagesDivider = 'chatNewMessagesDivider';
  static const chatNoTopics = 'chatNoTopics';
  static const chatPeopleDoingAction = 'chatPeopleDoingAction';
  static const chatPeopleTyping = 'chatPeopleTyping';
  static const chatPickerChooseChat = 'chatPickerChooseChat';
  static const chatReportConfirm = 'chatReportConfirm';
  static const chatReportFailed = 'chatReportFailed';
  static const chatReportMessage = 'chatReportMessage';
  static const chatReportSent = 'chatReportSent';
  static const chatReportTitle = 'chatReportTitle';
  static const chatRequestToJoin = 'chatRequestToJoin';
  static const chatRestrictedAcknowledge = 'chatRestrictedAcknowledge';
  static const chatRestrictedLeaveFailed = 'chatRestrictedLeaveFailed';
  static const chatRestrictedTelegramTosMessage =
      'chatRestrictedTelegramTosMessage';
  static const chatRestrictedTitle = 'chatRestrictedTitle';
  static const chatSavedToPhotos = 'chatSavedToPhotos';
  static const chatSavedToSavedMessages = 'chatSavedToSavedMessages';
  static const chatSaveFailed = 'chatSaveFailed';
  static const chatSaveToPhotosFailed = 'chatSaveToPhotosFailed';
  static const chatSaveToPhotosPermissionDenied =
      'chatSaveToPhotosPermissionDenied';
  static const chatSavingToPhotos = 'chatSavingToPhotos';
  static const chatSearchHistoryTitle = 'chatSearchHistoryTitle';
  static const chatSearchMessagePlaceholder = 'chatSearchMessagePlaceholder';
  static const chatSearchMessageResultLabel = 'chatSearchMessageResultLabel';
  static const chatSearchNoMessagesFound = 'chatSearchNoMessagesFound';
  static const chatSelectedMessagesCount = 'chatSelectedMessagesCount';
  static const chatSelectUntilHere = 'chatSelectUntilHere';
  static const chatsSearchBots = 'chatsSearchBots';
  static const chatsSearchNoResults = 'chatsSearchNoResults';
  static const chatsSearchPlaceholder = 'chatsSearchPlaceholder';
  static const chatsSearchPublicGroupsAndChannels =
      'chatsSearchPublicGroupsAndChannels';
  static const chatStickerAddSuccess = 'chatStickerAddSuccess';
  static const chatThemeApply = 'chatThemeApply';
  static const chatThemeChanged = 'chatThemeChanged';
  static const chatThemeChoose = 'chatThemeChoose';
  static const chatThemeSaveFailed = 'chatThemeSaveFailed';
  static const chatThemeTitle = 'chatThemeTitle';
  static const chatTodoSetFailed = 'chatTodoSetFailed';
  static const chatTodoSetSuccess = 'chatTodoSetSuccess';
  static const chatTodoUnsetFailed = 'chatTodoUnsetFailed';
  static const chatTodoUnsetSuccess = 'chatTodoUnsetSuccess';
  static const chatTranslateFailed = 'chatTranslateFailed';
  static const chatTyping = 'chatTyping';
  static const chatUnmute = 'chatUnmute';
  static const chatUserDoingAction = 'chatUserDoingAction';
  static const chatUserFallbackName = 'chatUserFallbackName';
  static const chatUserLeftGroup = 'chatUserLeftGroup';
  static const chatUsersJoinedGroup = 'chatUsersJoinedGroup';
  static const chatUserTyping = 'chatUserTyping';
  static const chatVideoPlaceholder = 'chatVideoPlaceholder';
  static const chatWallpaperApply = 'chatWallpaperApply';
  static const chatWallpaperApplyForBoth = 'chatWallpaperApplyForBoth';
  static const chatWallpaperApplyForMe = 'chatWallpaperApplyForMe';
  static const chatWallpaperBlur = 'chatWallpaperBlur';
  static const chatWallpaperBoostLevel = 'chatWallpaperBoostLevel';
  static const chatWallpaperBoostRequired = 'chatWallpaperBoostRequired';
  static const chatWallpaperChanged = 'chatWallpaperChanged';
  static const chatWallpaperChoose = 'chatWallpaperChoose';
  static const chatWallpaperColor = 'chatWallpaperColor';
  static const chatWallpaperColorTitle = 'chatWallpaperColorTitle';
  static const chatWallpaperCurrentTheme = 'chatWallpaperCurrentTheme';
  static const chatWallpaperDefault = 'chatWallpaperDefault';
  static const chatWallpaperGlobalPreview = 'chatWallpaperGlobalPreview';
  static const chatWallpaperGlobalTitle = 'chatWallpaperGlobalTitle';
  static const chatWallpaperGradient = 'chatWallpaperGradient';
  static const chatWallpaperIntensity = 'chatWallpaperIntensity';
  static const chatWallpaperMotion = 'chatWallpaperMotion';
  static const chatWallpaperNoTheme = 'chatWallpaperNoTheme';
  static const chatWallpaperPattern = 'chatWallpaperPattern';
  static const chatWallpaperPhoto = 'chatWallpaperPhoto';
  static const chatWallpaperPickFailed = 'chatWallpaperPickFailed';
  static const chatWallpaperPreviewIncoming = 'chatWallpaperPreviewIncoming';
  static const chatWallpaperPreviewOutgoing = 'chatWallpaperPreviewOutgoing';
  static const chatWallpaperSaveFailed = 'chatWallpaperSaveFailed';
  static const chatWallpaperSearch = 'chatWallpaperSearch';
  static const chatWallpaperSearchEmpty = 'chatWallpaperSearchEmpty';
  static const chatWallpaperSearchFailed = 'chatWallpaperSearchFailed';
  static const chatWallpaperSearchHint = 'chatWallpaperSearchHint';
  static const chatWallpaperSearchPowered = 'chatWallpaperSearchPowered';
  static const chatWallpaperSearchTitle = 'chatWallpaperSearchTitle';
  static const chatWallpaperSectionCommunity = 'chatWallpaperSectionCommunity';
  static const chatWallpaperSectionCustomize = 'chatWallpaperSectionCustomize';
  static const chatWallpaperSectionOfficial = 'chatWallpaperSectionOfficial';
  static const chatWallpaperSectionPatterns = 'chatWallpaperSectionPatterns';
  static const chatWallpaperSectionSaved = 'chatWallpaperSectionSaved';
  static const chatWallpaperTelegramCurrent = 'chatWallpaperTelegramCurrent';
  static const chatWallpaperTelegramThemes = 'chatWallpaperTelegramThemes';
  static const chatWallpaperThemesShared = 'chatWallpaperThemesShared';
  static const chatWallpaperThemesSharedWithChat =
      'chatWallpaperThemesSharedWithChat';
  static const chatWallpaperTitle = 'chatWallpaperTitle';
  static const chatYouAreMuted = 'chatYouAreMuted';
  static const chatYouWereRemovedFromGroup = 'chatYouWereRemovedFromGroup';
  static const checklistComposerAddTask = 'checklistComposerAddTask';
  static const checklistComposerNewChecklistTitle =
      'checklistComposerNewChecklistTitle';
  static const checklistComposerPremiumLimitHint =
      'checklistComposerPremiumLimitHint';
  static const checklistComposerTaskLabel = 'checklistComposerTaskLabel';
  static const checklistComposerTitleLabel = 'checklistComposerTitleLabel';
  static const cloudThemeApply = 'cloudThemeApply';
  static const cloudThemeLoadFailed = 'cloudThemeLoadFailed';
  static const cloudThemeOfficialDescription = 'cloudThemeOfficialDescription';
  static const cloudThemePreviewTitle = 'cloudThemePreviewTitle';
  static const communityChatAddedService = 'communityChatAddedService';
  static const communityChatCount = 'communityChatCount';
  static const communityChatRemovedService = 'communityChatRemovedService';
  static const communityChatsYouAreIn = 'communityChatsYouAreIn';
  static const communityChatsYouCanView = 'communityChatsYouCanView';
  static const communityNoChats = 'communityNoChats';
  static const communityShowAsOneChat = 'communityShowAsOneChat';
  static const communityShowAsOneChatDescription =
      'communityShowAsOneChatDescription';
  static const communityTitle = 'communityTitle';
  static const commonUiDraftBadge = 'commonUiDraftBadge';
  static const commonUiGroupOwner = 'commonUiGroupOwner';
  static const commonUiMentionedBySomeoneBadge =
      'commonUiMentionedBySomeoneBadge';
  static const commonUiMentionMeBadge = 'commonUiMentionMeBadge';
  static const commonUiNewFileBadge = 'commonUiNewFileBadge';
  static const composerAnimatedEmojiPreview = 'composerAnimatedEmojiPreview';
  static const composerAudio = 'composerAudio';
  static const composerCamera = 'composerCamera';
  static const composerChecklist = 'composerChecklist';
  static const composerClipboardNoImage = 'composerClipboardNoImage';
  static const composerEditInRichText = 'composerEditInRichText';
  static const composerFilePreview = 'composerFilePreview';
  static const composerFormat = 'composerFormat';
  static const composerFormatApply = 'composerFormatApply';
  static const composerFormatCodeBlock = 'composerFormatCodeBlock';
  static const composerFormatLink = 'composerFormatLink';
  static const composerFormatLinkPlaceholder = 'composerFormatLinkPlaceholder';
  static const composerFormatMonospace = 'composerFormatMonospace';
  static const composerGifSendFailed = 'composerGifSendFailed';
  static const composerGroupVideoCall = 'composerGroupVideoCall';
  static const composerGroupVoiceCall = 'composerGroupVoiceCall';
  static const composerHoldToTalk = 'composerHoldToTalk';
  static const composerImage = 'composerImage';
  static const composerImagePreview = 'composerImagePreview';
  static const composerLoadingEmoji = 'composerLoadingEmoji';
  static const composerLoadingGifs = 'composerLoadingGifs';
  static const composerLocation = 'composerLocation';
  static const composerLocationPreview = 'composerLocationPreview';
  static const composerLongMessageRichTextPrompt =
      'composerLongMessageRichTextPrompt';
  static const composerLongMessageTitle = 'composerLongMessageTitle';
  static const composerMarkdownSupportHint = 'composerMarkdownSupportHint';
  static const composerMessageExceedsRichTextLimit =
      'composerMessageExceedsRichTextLimit';
  static const composerMicrophonePermissionRequired =
      'composerMicrophonePermissionRequired';
  static const composerMicrophonePermissionSettings =
      'composerMicrophonePermissionSettings';
  static const composerNoEmoji = 'composerNoEmoji';
  static const composerNoGifs = 'composerNoGifs';
  static const composerOpenAttachmentFailed = 'composerOpenAttachmentFailed';
  static const composerOpenMenu = 'composerOpenMenu';
  static const composerPaidMessageCost = 'composerPaidMessageCost';
  static const composerPastedImageReadFailed = 'composerPastedImageReadFailed';
  static const composerPoll = 'composerPoll';
  static const composerReleaseFingerToCancel = 'composerReleaseFingerToCancel';
  static const composerReleaseToSendSlideToCancel =
      'composerReleaseToSendSlideToCancel';
  static const composerRichText = 'composerRichText';
  static const composerRichTextMessageTitle = 'composerRichTextMessageTitle';
  static const composerRichTextSendFailed = 'composerRichTextSendFailed';
  static const composerSend = 'composerSend';
  static const composerSendAsFile = 'composerSendAsFile';
  static const composerSendAsFileDescription = 'composerSendAsFileDescription';
  static const composerSendAsMedia = 'composerSendAsMedia';
  static const composerSendAsRichText = 'composerSendAsRichText';
  static const composerSendPaidMessageQuestion =
      'composerSendPaidMessageQuestion';
  static const composerVideoCall = 'composerVideoCall';
  static const composerVoiceCall = 'composerVoiceCall';
  static const composerVoicePreview = 'composerVoicePreview';
  static const confirmCancel = 'confirmCancel';
  static const confirmContinue = 'confirmContinue';
  static const confirmOk = 'confirmOk';
  static const contactsFriends = 'contactsFriends';
  static const contactsLoading = 'contactsLoading';
  static const contactsNoBots = 'contactsNoBots';
  static const contactsNoChannels = 'contactsNoChannels';
  static const contactsNoContacts = 'contactsNoContacts';
  static const contactsNoGroupChats = 'contactsNoGroupChats';
  static const countryAD = 'countryAD';
  static const countryAE = 'countryAE';
  static const countryAF = 'countryAF';
  static const countryAL = 'countryAL';
  static const countryAM = 'countryAM';
  static const countryAO = 'countryAO';
  static const countryAR = 'countryAR';
  static const countryAT = 'countryAT';
  static const countryAU = 'countryAU';
  static const countryAZ = 'countryAZ';
  static const countryBA = 'countryBA';
  static const countryBD = 'countryBD';
  static const countryBE = 'countryBE';
  static const countryBF = 'countryBF';
  static const countryBG = 'countryBG';
  static const countryBH = 'countryBH';
  static const countryBJ = 'countryBJ';
  static const countryBN = 'countryBN';
  static const countryBO = 'countryBO';
  static const countryBR = 'countryBR';
  static const countryBT = 'countryBT';
  static const countryBW = 'countryBW';
  static const countryBY = 'countryBY';
  static const countryBZ = 'countryBZ';
  static const countryCA = 'countryCA';
  static const countryCD = 'countryCD';
  static const countryCG = 'countryCG';
  static const countryCH = 'countryCH';
  static const countryCI = 'countryCI';
  static const countryCL = 'countryCL';
  static const countryCM = 'countryCM';
  static const countryCN = 'countryCN';
  static const countryCO = 'countryCO';
  static const countryCR = 'countryCR';
  static const countryCU = 'countryCU';
  static const countryCY = 'countryCY';
  static const countryCZ = 'countryCZ';
  static const countryDE = 'countryDE';
  static const countryDK = 'countryDK';
  static const countryDZ = 'countryDZ';
  static const countryEC = 'countryEC';
  static const countryEE = 'countryEE';
  static const countryEG = 'countryEG';
  static const countryES = 'countryES';
  static const countryET = 'countryET';
  static const countryFI = 'countryFI';
  static const countryFJ = 'countryFJ';
  static const countryFR = 'countryFR';
  static const countryGA = 'countryGA';
  static const countryGB = 'countryGB';
  static const countryGE = 'countryGE';
  static const countryGH = 'countryGH';
  static const countryGN = 'countryGN';
  static const countryGR = 'countryGR';
  static const countryGT = 'countryGT';
  static const countryGY = 'countryGY';
  static const countryHK = 'countryHK';
  static const countryHN = 'countryHN';
  static const countryHR = 'countryHR';
  static const countryHT = 'countryHT';
  static const countryHU = 'countryHU';
  static const countryID = 'countryID';
  static const countryIE = 'countryIE';
  static const countryIL = 'countryIL';
  static const countryIN = 'countryIN';
  static const countryIQ = 'countryIQ';
  static const countryIR = 'countryIR';
  static const countryIS = 'countryIS';
  static const countryIT = 'countryIT';
  static const countryJO = 'countryJO';
  static const countryJP = 'countryJP';
  static const countryKE = 'countryKE';
  static const countryKG = 'countryKG';
  static const countryKH = 'countryKH';
  static const countryKP = 'countryKP';
  static const countryKR = 'countryKR';
  static const countryKW = 'countryKW';
  static const countryKZ = 'countryKZ';
  static const countryLA = 'countryLA';
  static const countryLB = 'countryLB';
  static const countryLI = 'countryLI';
  static const countryLK = 'countryLK';
  static const countryLT = 'countryLT';
  static const countryLU = 'countryLU';
  static const countryLV = 'countryLV';
  static const countryLY = 'countryLY';
  static const countryMA = 'countryMA';
  static const countryMC = 'countryMC';
  static const countryMD = 'countryMD';
  static const countryME = 'countryME';
  static const countryMG = 'countryMG';
  static const countryMK = 'countryMK';
  static const countryML = 'countryML';
  static const countryMM = 'countryMM';
  static const countryMN = 'countryMN';
  static const countryMO = 'countryMO';
  static const countryMR = 'countryMR';
  static const countryMT = 'countryMT';
  static const countryMU = 'countryMU';
  static const countryMV = 'countryMV';
  static const countryMW = 'countryMW';
  static const countryMX = 'countryMX';
  static const countryMY = 'countryMY';
  static const countryMZ = 'countryMZ';
  static const countryNA = 'countryNA';
  static const countryNE = 'countryNE';
  static const countryNG = 'countryNG';
  static const countryNI = 'countryNI';
  static const countryNL = 'countryNL';
  static const countryNO = 'countryNO';
  static const countryNP = 'countryNP';
  static const countryNZ = 'countryNZ';
  static const countryOM = 'countryOM';
  static const countryPA = 'countryPA';
  static const countryPE = 'countryPE';
  static const countryPG = 'countryPG';
  static const countryPH = 'countryPH';
  static const countryPickerCancel = 'countryPickerCancel';
  static const countryPickerSearchPlaceholder =
      'countryPickerSearchPlaceholder';
  static const countryPickerSelectCountryOrRegion =
      'countryPickerSelectCountryOrRegion';
  static const countryPK = 'countryPK';
  static const countryPL = 'countryPL';
  static const countryPS = 'countryPS';
  static const countryPT = 'countryPT';
  static const countryPY = 'countryPY';
  static const countryQA = 'countryQA';
  static const countryRO = 'countryRO';
  static const countryRS = 'countryRS';
  static const countryRU = 'countryRU';
  static const countryRW = 'countryRW';
  static const countrySA = 'countrySA';
  static const countrySB = 'countrySB';
  static const countrySD = 'countrySD';
  static const countrySE = 'countrySE';
  static const countrySG = 'countrySG';
  static const countrySI = 'countrySI';
  static const countrySK = 'countrySK';
  static const countrySM = 'countrySM';
  static const countrySN = 'countrySN';
  static const countrySO = 'countrySO';
  static const countrySR = 'countrySR';
  static const countrySS = 'countrySS';
  static const countrySV = 'countrySV';
  static const countrySY = 'countrySY';
  static const countryTD = 'countryTD';
  static const countryTG = 'countryTG';
  static const countryTH = 'countryTH';
  static const countryTJ = 'countryTJ';
  static const countryTL = 'countryTL';
  static const countryTM = 'countryTM';
  static const countryTN = 'countryTN';
  static const countryTO = 'countryTO';
  static const countryTR = 'countryTR';
  static const countryTW = 'countryTW';
  static const countryTZ = 'countryTZ';
  static const countryUA = 'countryUA';
  static const countryUG = 'countryUG';
  static const countryUS = 'countryUS';
  static const countryUY = 'countryUY';
  static const countryUZ = 'countryUZ';
  static const countryVE = 'countryVE';
  static const countryVN = 'countryVN';
  static const countryVU = 'countryVU';
  static const countryWS = 'countryWS';
  static const countryXK = 'countryXK';
  static const countryYE = 'countryYE';
  static const countryZA = 'countryZA';
  static const countryZM = 'countryZM';
  static const countryZW = 'countryZW';
  static const createGroupFailed = 'createGroupFailed';
  static const createGroupOptionalLabel = 'createGroupOptionalLabel';
  static const createGroupStartGroupChat = 'createGroupStartGroupChat';
  static const developerModePiPBoundsOverlay = 'developerModePiPBoundsOverlay';
  static const developerModePiPBoundsOverlayDescription =
      'developerModePiPBoundsOverlayDescription';
  static const developerModeTitle = 'developerModeTitle';
  static const developerModeUnlocked = 'developerModeUnlocked';
  static const editProfileAnimatedAvatar = 'editProfileAnimatedAvatar';
  static const editProfileAnimatedAvatarDescription =
      'editProfileAnimatedAvatarDescription';
  static const editProfileAnimatedAvatarPremiumRequired =
      'editProfileAnimatedAvatarPremiumRequired';
  static const editProfileAvatarUpdated = 'editProfileAvatarUpdated';
  static const editProfileAvatarUpdateFailed = 'editProfileAvatarUpdateFailed';
  static const editProfileBio = 'editProfileBio';
  static const editProfileBioPlaceholder = 'editProfileBioPlaceholder';
  static const editProfileBirthDay = 'editProfileBirthDay';
  static const editProfileBirthMonth = 'editProfileBirthMonth';
  static const editProfileBirthYear = 'editProfileBirthYear';
  static const editProfileChangeAvatar = 'editProfileChangeAvatar';
  static const editProfileChangeBio = 'editProfileChangeBio';
  static const editProfileChangeName = 'editProfileChangeName';
  static const editProfileChangeUsername = 'editProfileChangeUsername';
  static const editProfileChooseAvatarType = 'editProfileChooseAvatarType';
  static const editProfileClearBirthday = 'editProfileClearBirthday';
  static const editProfileDefault = 'editProfileDefault';
  static const editProfileInvalidAvatarFile = 'editProfileInvalidAvatarFile';
  static const editProfileLastName = 'editProfileLastName';
  static const editProfileNameColor = 'editProfileNameColor';
  static const editProfileNameColorDescription =
      'editProfileNameColorDescription';
  static const editProfileNoBirthYear = 'editProfileNoBirthYear';
  static const editProfileNotBound = 'editProfileNotBound';
  static const editProfilePhone = 'editProfilePhone';
  static const editProfileProfileColor = 'editProfileProfileColor';
  static const editProfileProfileColorDescription =
      'editProfileProfileColorDescription';
  static const editProfileProfileIcon = 'editProfileProfileIcon';
  static const editProfileProfileIconEmpty = 'editProfileProfileIconEmpty';
  static const editProfileSaveFailed = 'editProfileSaveFailed';
  static const editProfileSetUsername = 'editProfileSetUsername';
  static const editProfileStaticAvatar = 'editProfileStaticAvatar';
  static const editProfileStaticAvatarDescription =
      'editProfileStaticAvatarDescription';
  static const editProfileTapToFillBio = 'editProfileTapToFillBio';
  static const editProfileTapToSet = 'editProfileTapToSet';
  static const editProfileTitle = 'editProfileTitle';
  static const editProfileUsername = 'editProfileUsername';
  static const editProfileUsernameUnavailable =
      'editProfileUsernameUnavailable';
  static const editProfileUsernameUnsetHandle =
      'editProfileUsernameUnsetHandle';
  static const emojiCategoryActivitiesAndSports =
      'emojiCategoryActivitiesAndSports';
  static const emojiCategoryAnimalsAndNature = 'emojiCategoryAnimalsAndNature';
  static const emojiCategoryFoodAndDrink = 'emojiCategoryFoodAndDrink';
  static const emojiCategoryObjects = 'emojiCategoryObjects';
  static const emojiCategoryPeopleAndBody = 'emojiCategoryPeopleAndBody';
  static const emojiCategorySmileysAndEmotion =
      'emojiCategorySmileysAndEmotion';
  static const emojiCategorySymbols = 'emojiCategorySymbols';
  static const emojiCategoryTravelAndPlaces = 'emojiCategoryTravelAndPlaces';
  static const emojiFontCatalogSystemDefault = 'emojiFontCatalogSystemDefault';
  static const emojiPreviewFaceWithTearsOfJoy =
      'emojiPreviewFaceWithTearsOfJoy';
  static const emojiStatusClear = 'emojiStatusClear';
  static const emojiStatusNoAvailableStatuses =
      'emojiStatusNoAvailableStatuses';
  static const emojiStatusNoAvailableStatusesPremiumRequired =
      'emojiStatusNoAvailableStatusesPremiumRequired';
  static const emojiStatusSetRequiresPremiumFailed =
      'emojiStatusSetRequiresPremiumFailed';
  static const emojiStatusSetTitle = 'emojiStatusSetTitle';
  static const featureBottomTabs = 'featureBottomTabs';
  static const featureCommunitiesEnabled = 'featureCommunitiesEnabled';
  static const featureDisableSafetyNotice = 'featureDisableSafetyNotice';
  static const featureSafety = 'featureSafety';
  static const featureTitle = 'featureTitle';
  static const fileDetailDownloadProgress = 'fileDetailDownloadProgress';
  static const fileDetailNoAppCanOpenFile = 'fileDetailNoAppCanOpenFile';
  static const fileDetailOpen = 'fileDetailOpen';
  static const generalAutoDownloadDisabled = 'generalAutoDownloadDisabled';
  static const generalAutoDownloadFailed = 'generalAutoDownloadFailed';
  static const generalAutoDownloadHighResImages =
      'generalAutoDownloadHighResImages';
  static const generalAutoDownloadMedia = 'generalAutoDownloadMedia';
  static const generalAutoDownloadMobileData = 'generalAutoDownloadMobileData';
  static const generalAutoDownloadWifi = 'generalAutoDownloadWifi';
  static const generalAdvancedAutomaticDownload =
      'generalAdvancedAutomaticDownload';
  static const generalCacheSize = 'generalCacheSize';
  static const generalClearCache = 'generalClearCache';
  static const generalClearingCache = 'generalClearingCache';
  static const generalDetailedStorageUsage = 'generalDetailedStorageUsage';
  static const generalDownloads = 'generalDownloads';
  static const generalNetworkUsage = 'generalNetworkUsage';
  static const generalOpenChatAtLatestMessage =
      'generalOpenChatAtLatestMessage';
  static const generalRepeatPreserveSender = 'generalRepeatPreserveSender';
  static const generalSendMessageWithEnter = 'generalSendMessageWithEnter';
  static const generalStorage = 'generalStorage';
  static const generalTitle = 'generalTitle';
  static const globalThemeColors = 'globalThemeColors';
  static const globalThemeColorsFrom = 'globalThemeColorsFrom';
  static const globalThemeCommunity = 'globalThemeCommunity';
  static const globalThemeCommunityEmpty = 'globalThemeCommunityEmpty';
  static const globalThemeCustomize = 'globalThemeCustomize';
  static const globalThemeDay = 'globalThemeDay';
  static const globalThemeDefault = 'globalThemeDefault';
  static const globalThemeDescription = 'globalThemeDescription';
  static const globalThemeImport = 'globalThemeImport';
  static const globalThemeInstalled = 'globalThemeInstalled';
  static const globalThemeLoading = 'globalThemeLoading';
  static const globalThemeNight = 'globalThemeNight';
  static const globalThemeOfficial = 'globalThemeOfficial';
  static const globalThemePreview = 'globalThemePreview';
  static const globalThemeReset = 'globalThemeReset';
  static const globalThemeSwitchModeAction = 'globalThemeSwitchModeAction';
  static const globalThemeSwitchToDark = 'globalThemeSwitchToDark';
  static const globalThemeSwitchToLight = 'globalThemeSwitchToLight';
  static const globalThemeWallpaperApply = 'globalThemeWallpaperApply';
  static const globalThemeWallpaperKeep = 'globalThemeWallpaperKeep';
  static const globalThemeWallpaperPrompt = 'globalThemeWallpaperPrompt';
  static const globalThemeTitle = 'globalThemeTitle';
  static const globalThemeUseForUi = 'globalThemeUseForUi';
  static const globalThemeUseForUiDescription =
      'globalThemeUseForUiDescription';
  static const globalWallpaperTitle = 'globalWallpaperTitle';
  static const gallerySendHdSubtitle = 'gallerySendHdSubtitle';
  static const gallerySendHdTitle = 'gallerySendHdTitle';
  static const gallerySendMediaSubtitle = 'gallerySendMediaSubtitle';
  static const gallerySendMotionSubtitle = 'gallerySendMotionSubtitle';
  static const gallerySendMotionTitle = 'gallerySendMotionTitle';
  static const groupAdminAddPhoto = 'groupAdminAddPhoto';
  static const groupAdminAdvancedTitle = 'groupAdminAdvancedTitle';
  static const groupAdminAggressiveAntiSpam = 'groupAdminAggressiveAntiSpam';
  static const groupAdminAutomaticTranslation =
      'groupAdminAutomaticTranslation';
  static const groupAdminAvailableReactions = 'groupAdminAvailableReactions';
  static const groupAdminChangePhoto = 'groupAdminChangePhoto';
  static const groupAdminCommunitySection = 'groupAdminCommunitySection';
  static const groupAdminDescription = 'groupAdminDescription';
  static const groupAdminDescriptionHint = 'groupAdminDescriptionHint';
  static const groupAdminDiscussionGroup = 'groupAdminDiscussionGroup';
  static const groupAdminErrorAntiSpam = 'groupAdminErrorAntiSpam';
  static const groupAdminErrorDescription = 'groupAdminErrorDescription';
  static const groupAdminErrorForum = 'groupAdminErrorForum';
  static const groupAdminErrorHistory = 'groupAdminErrorHistory';
  static const groupAdminErrorLoad = 'groupAdminErrorLoad';
  static const groupAdminErrorMemberVisibility =
      'groupAdminErrorMemberVisibility';
  static const groupAdminErrorPhoto = 'groupAdminErrorPhoto';
  static const groupAdminErrorPhotoEmpty = 'groupAdminErrorPhotoEmpty';
  static const groupAdminErrorPhotoRemove = 'groupAdminErrorPhotoRemove';
  static const groupAdminErrorProtection = 'groupAdminErrorProtection';
  static const groupAdminErrorSenderProfiles = 'groupAdminErrorSenderProfiles';
  static const groupAdminErrorSignatures = 'groupAdminErrorSignatures';
  static const groupAdminErrorSlowMode = 'groupAdminErrorSlowMode';
  static const groupAdminErrorTopicLayout = 'groupAdminErrorTopicLayout';
  static const groupAdminErrorTranslation = 'groupAdminErrorTranslation';
  static const groupAdminHideMembers = 'groupAdminHideMembers';
  static const groupAdminHistoryForNewMembers =
      'groupAdminHistoryForNewMembers';
  static const groupAdminHour = 'groupAdminHour';
  static const groupAdminLinked = 'groupAdminLinked';
  static const groupAdminMinute = 'groupAdminMinute';
  static const groupAdminMinutes = 'groupAdminMinutes';
  static const groupAdminMessagesSection = 'groupAdminMessagesSection';
  static const groupAdminNotLinked = 'groupAdminNotLinked';
  static const groupAdminNotSet = 'groupAdminNotSet';
  static const groupAdminOff = 'groupAdminOff';
  static const groupAdminProfileSection = 'groupAdminProfileSection';
  static const groupAdminProtectContent = 'groupAdminProtectContent';
  static const groupAdminRefresh = 'groupAdminRefresh';
  static const groupAdminRemovePhoto = 'groupAdminRemovePhoto';
  static const groupAdminRemovePhotoConfirm = 'groupAdminRemovePhotoConfirm';
  static const groupAdminShowSenderProfiles = 'groupAdminShowSenderProfiles';
  static const groupAdminSignMessages = 'groupAdminSignMessages';
  static const groupAdminSlowMode = 'groupAdminSlowMode';
  static const groupAdminAllReactions = 'groupAdminAllReactions';
  static const groupAdminReactionCount = 'groupAdminReactionCount';
  static const groupAdminSeconds = 'groupAdminSeconds';
  static const groupAdminTopicTabs = 'groupAdminTopicTabs';
  static const groupAdminTopics = 'groupAdminTopics';
  static const groupAppearanceBoostLevel = 'groupAppearanceBoostLevel';
  static const groupAppearanceDescription = 'groupAppearanceDescription';
  static const groupAppearanceEmojiPack = 'groupAppearanceEmojiPack';
  static const groupAppearanceEmojiStatus = 'groupAppearanceEmojiStatus';
  static const groupAppearanceNone = 'groupAppearanceNone';
  static const groupAppearanceProfileIcon = 'groupAppearanceProfileIcon';
  static const groupAppearanceStickers = 'groupAppearanceStickers';
  static const groupAppearanceTitle = 'groupAppearanceTitle';
  static const groupAppearanceWallpaper = 'groupAppearanceWallpaper';
  static const groupManagementAdminApprovalRequired =
      'groupManagementAdminApprovalRequired';
  static const groupManagementBasicSection = 'groupManagementBasicSection';
  static const groupManagementEditable = 'groupManagementEditable';
  static const groupManagementEditFailed = 'groupManagementEditFailed';
  static const groupManagementGroupName = 'groupManagementGroupName';
  static const groupManagementInviteLinkQr = 'groupManagementInviteLinkQr';
  static const groupManagementJoinBeforePosting =
      'groupManagementJoinBeforePosting';
  static const groupManagementJoinSection = 'groupManagementJoinSection';
  static const groupManagementLoadFailed = 'groupManagementLoadFailed';
  static const groupManagementLogAdmin = 'groupManagementLogAdmin';
  static const groupManagementLogApprovedJoinRequest =
      'groupManagementLogApprovedJoinRequest';
  static const groupManagementLogChangedAdmin =
      'groupManagementLogChangedAdmin';
  static const groupManagementLogChangedGroupDescription =
      'groupManagementLogChangedGroupDescription';
  static const groupManagementLogChangedGroupName =
      'groupManagementLogChangedGroupName';
  static const groupManagementLogChangedGroupPhoto =
      'groupManagementLogChangedGroupPhoto';
  static const groupManagementLogChangedLinkedChat =
      'groupManagementLogChangedLinkedChat';
  static const groupManagementLogChangedMemberPermissions =
      'groupManagementLogChangedMemberPermissions';
  static const groupManagementLogChangedPostingPermissions =
      'groupManagementLogChangedPostingPermissions';
  static const groupManagementLogChangedPublicUsername =
      'groupManagementLogChangedPublicUsername';
  static const groupManagementLogChangedSlowMode =
      'groupManagementLogChangedSlowMode';
  static const groupManagementLogCreatedTopic =
      'groupManagementLogCreatedTopic';
  static const groupManagementLogDeletedInviteLink =
      'groupManagementLogDeletedInviteLink';
  static const groupManagementLogDeletedMessage =
      'groupManagementLogDeletedMessage';
  static const groupManagementLogDeletedTopic =
      'groupManagementLogDeletedTopic';
  static const groupManagementLogEditedInviteLink =
      'groupManagementLogEditedInviteLink';
  static const groupManagementLogEditedMessage =
      'groupManagementLogEditedMessage';
  static const groupManagementLogEditedTopic = 'groupManagementLogEditedTopic';
  static const groupManagementLogEmpty = 'groupManagementLogEmpty';
  static const groupManagementLogEndedVideoChat =
      'groupManagementLogEndedVideoChat';
  static const groupManagementLogGenericAdminAction =
      'groupManagementLogGenericAdminAction';
  static const groupManagementLogInvitedMember =
      'groupManagementLogInvitedMember';
  static const groupManagementLogJoinedByInviteLink =
      'groupManagementLogJoinedByInviteLink';
  static const groupManagementLogJoinedGroup = 'groupManagementLogJoinedGroup';
  static const groupManagementLogLeftGroup = 'groupManagementLogLeftGroup';
  static const groupManagementLogNoPermission =
      'groupManagementLogNoPermission';
  static const groupManagementLogPinnedMessage =
      'groupManagementLogPinnedMessage';
  static const groupManagementLogRevokedInviteLink =
      'groupManagementLogRevokedInviteLink';
  static const groupManagementLogStartedVideoChat =
      'groupManagementLogStartedVideoChat';
  static const groupManagementLogTitle = 'groupManagementLogTitle';
  static const groupManagementLogUnknownActor =
      'groupManagementLogUnknownActor';
  static const groupManagementLogUnpinnedMessage =
      'groupManagementLogUnpinnedMessage';
  static const groupManagementMembers = 'groupManagementMembers';
  static const groupManagementMembersSection = 'groupManagementMembersSection';
  static const groupManagementNoEditInfoPermission =
      'groupManagementNoEditInfoPermission';
  static const groupManagementNotSet = 'groupManagementNotSet';
  static const groupManagementPermissionCreateTopics =
      'groupManagementPermissionCreateTopics';
  static const groupManagementPermissionEditGroupInfo =
      'groupManagementPermissionEditGroupInfo';
  static const groupManagementPermissionLinkPreviews =
      'groupManagementPermissionLinkPreviews';
  static const groupManagementPermissionPinMessages =
      'groupManagementPermissionPinMessages';
  static const groupManagementPermissionSendFiles =
      'groupManagementPermissionSendFiles';
  static const groupManagementPermissionSendMessages =
      'groupManagementPermissionSendMessages';
  static const groupManagementPermissionSendMusic =
      'groupManagementPermissionSendMusic';
  static const groupManagementPermissionSendPhotos =
      'groupManagementPermissionSendPhotos';
  static const groupManagementPermissionSendPolls =
      'groupManagementPermissionSendPolls';
  static const groupManagementPermissionSendStickersAndGifs =
      'groupManagementPermissionSendStickersAndGifs';
  static const groupManagementPermissionSendVideoMessages =
      'groupManagementPermissionSendVideoMessages';
  static const groupManagementPermissionSendVideos =
      'groupManagementPermissionSendVideos';
  static const groupManagementPermissionSendVoice =
      'groupManagementPermissionSendVoice';
  static const groupManagementPermissionSetFailed =
      'groupManagementPermissionSetFailed';
  static const groupManagementPostingPermissions =
      'groupManagementPostingPermissions';
  static const groupManagementPublicUsername = 'groupManagementPublicUsername';
  static const groupManagementReadOnly = 'groupManagementReadOnly';
  static const groupManagementSetFailed = 'groupManagementSetFailed';
  static const groupManagementUsernameUnavailableOrForbidden =
      'groupManagementUsernameUnavailableOrForbidden';
  static const imageEditAdd = 'imageEditAdd';
  static const imageEditAddText = 'imageEditAddText';
  static const imageEditBrush = 'imageEditBrush';
  static const imageEditCaptionInputPlaceholder =
      'imageEditCaptionInputPlaceholder';
  static const imageEditCrop = 'imageEditCrop';
  static const imageEditCropAvatar = 'imageEditCropAvatar';
  static const imageEditDescriptionPlaceholder =
      'imageEditDescriptionPlaceholder';
  static const imageEditObscure = 'imageEditObscure';
  static const imageEditProcessing = 'imageEditProcessing';
  static const imageEditResetCrop = 'imageEditResetCrop';
  static const imageEditRotate = 'imageEditRotate';
  static const imageEditTextTool = 'imageEditTextTool';
  static const imageEditTitle = 'imageEditTitle';
  static const keywordBlockerAddFromMessageTitle =
      'keywordBlockerAddFromMessageTitle';
  static const keywordBlockerDescription = 'keywordBlockerDescription';
  static const keywordBlockerDownload = 'keywordBlockerDownload';
  static const keywordBlockerDownloadFailed = 'keywordBlockerDownloadFailed';
  static const keywordBlockerInputPlaceholder =
      'keywordBlockerInputPlaceholder';
  static const keywordBlockerListUrl = 'keywordBlockerListUrl';
  static const keywordBlockerRuleAdded = 'keywordBlockerRuleAdded';
  static const keywordBlockerRulesAdded = 'keywordBlockerRulesAdded';
  static const keywordBlockerRulesUpToDate = 'keywordBlockerRulesUpToDate';
  static const keywordBlockerTitle = 'keywordBlockerTitle';
  static const languageMithkaLanguage = 'languageMithkaLanguage';
  static const languageTelegramFollowMithka = 'languageTelegramFollowMithka';
  static const languageTelegramLanguage = 'languageTelegramLanguage';
  static const languageTelegramLoadFailed = 'languageTelegramLoadFailed';
  static const languageTelegramLoading = 'languageTelegramLoading';
  static const languageTelegramOfficial = 'languageTelegramOfficial';
  static const languageTelegramUsing = 'languageTelegramUsing';
  static const languageTitle = 'languageTitle';
  static const linkHandlerGroupLabel = 'linkHandlerGroupLabel';
  static const linkHandlerJoin = 'linkHandlerJoin';
  static const linkHandlerJoinNamedGroupQuestion =
      'linkHandlerJoinNamedGroupQuestion';
  static const linkHandlerOpenTelegramLinkFailed =
      'linkHandlerOpenTelegramLinkFailed';
  static const linkHandlerQrLoginWarning = 'linkHandlerQrLoginWarning';
  static const linkHandlerUnsupportedTelegramLink =
      'linkHandlerUnsupportedTelegramLink';
  static const listSeparator = 'listSeparator';
  static const locationDetailFetchingLocation =
      'locationDetailFetchingLocation';
  static const locationPickerDragMapToChoose = 'locationPickerDragMapToChoose';
  static const loginBackToAccount = 'loginBackToAccount';
  static const loginBackToPreviousAccount = 'loginBackToPreviousAccount';
  static const loginCodeSentByEmail = 'loginCodeSentByEmail';
  static const loginCodeSentByFirebase = 'loginCodeSentByFirebase';
  static const loginCodeSentByFlashCall = 'loginCodeSentByFlashCall';
  static const loginCodeSentByFragment = 'loginCodeSentByFragment';
  static const loginCodeSentByMissedCall = 'loginCodeSentByMissedCall';
  static const loginCodeSentByPhoneCall = 'loginCodeSentByPhoneCall';
  static const loginCodeSentBySms = 'loginCodeSentBySms';
  static const loginCodeSentFallback = 'loginCodeSentFallback';
  static const loginCodeSentToTelegramDevices =
      'loginCodeSentToTelegramDevices';
  static const loginCodeWillBeSentToNumber = 'loginCodeWillBeSentToNumber';
  static const loginCompleteRegistration = 'loginCompleteRegistration';
  static const loginConfigureCustomApi = 'loginConfigureCustomApi';
  static const loginFirstName = 'loginFirstName';
  static const loginGetVerificationCode = 'loginGetVerificationCode';
  static const loginLastNameOptional = 'loginLastNameOptional';
  static const loginNewAccountNicknamePrompt = 'loginNewAccountNicknamePrompt';
  static const loginPasswordHint = 'loginPasswordHint';
  static const loginPhoneNumberWithCountryCode =
      'loginPhoneNumberWithCountryCode';
  static const loginQrCodeSubtitle = 'loginQrCodeSubtitle';
  static const loginQrCodeTitle = 'loginQrCodeTitle';
  static const loginReenterPhoneNumber = 'loginReenterPhoneNumber';
  static const loginRefreshQrCode = 'loginRefreshQrCode';
  static const loginResendVerificationCode = 'loginResendVerificationCode';
  static const loginSubmit = 'loginSubmit';
  static const loginSwitchAccount = 'loginSwitchAccount';
  static const loginTelegramAccountTitle = 'loginTelegramAccountTitle';
  static const loginTelegramApiCredentialsMissing =
      'loginTelegramApiCredentialsMissing';
  static const loginTelegramApiPortalInstructions =
      'loginTelegramApiPortalInstructions';
  static const loginTelegramApiSecretsInstructions =
      'loginTelegramApiSecretsInstructions';
  static const loginTermsAccept = 'loginTermsAccept';
  static const loginTermsBody = 'loginTermsBody';
  static const loginTermsButton = 'loginTermsButton';
  static const loginTermsOpenTelegram = 'loginTermsOpenTelegram';
  static const loginTermsTitle = 'loginTermsTitle';
  static const loginTwoStepPassword = 'loginTwoStepPassword';
  static const loginVerificationCode = 'loginVerificationCode';
  static const loginVerify = 'loginVerify';
  static const loginWithQrCode = 'loginWithQrCode';
  static const loginWithPasskey = 'loginWithPasskey';
  static const markdownLabel = 'markdownLabel';
  static const mediaSendPreviewTitle = 'mediaSendPreviewTitle';
  static const messageActionBlock = 'messageActionBlock';
  static const messageActionBlockKeyword = 'messageActionBlockKeyword';
  static const messageActionCopy = 'messageActionCopy';
  static const messageActionEdit = 'messageActionEdit';
  static const messageActionFavorite = 'messageActionFavorite';
  static const messageActionForward = 'messageActionForward';
  static const messageActionInfo = 'messageActionInfo';
  static const messageActionMultiSelect = 'messageActionMultiSelect';
  static const messageActionPlayMuted = 'messageActionPlayMuted';
  static const messageActionQuote = 'messageActionQuote';
  static const messageActionRepeat = 'messageActionRepeat';
  static const messageActionReplies = 'messageActionReplies';
  static const messageActionReport = 'messageActionReport';
  static const messageActionSaveToPhotos = 'messageActionSaveToPhotos';
  static const messageActionSelectText = 'messageActionSelectText';
  static const messageActionSetTodo = 'messageActionSetTodo';
  static const messageActionSticker = 'messageActionSticker';
  static const messageActionTranslate = 'messageActionTranslate';
  static const messageActionUnsetTodo = 'messageActionUnsetTodo';
  static const messageBubbleCallCanceled = 'messageBubbleCallCanceled';
  static const messageBubbleCallDeclined = 'messageBubbleCallDeclined';
  static const messageBubbleCallDeclinedByOther =
      'messageBubbleCallDeclinedByOther';
  static const messageBubbleCallDuration = 'messageBubbleCallDuration';
  static const messageBubbleCallMissed = 'messageBubbleCallMissed';
  static const messageBubbleCallNoAnswer = 'messageBubbleCallNoAnswer';
  static const messageInformationTitle = 'messageInformationTitle';
  static const messageInfoForwards = 'messageInfoForwards';
  static const messageInfoLoadFailed = 'messageInfoLoadFailed';
  static const messageInfoRead = 'messageInfoRead';
  static const messageInfoReadDateHidden = 'messageInfoReadDateHidden';
  static const messageInfoReadDatePrivate = 'messageInfoReadDatePrivate';
  static const messageInfoReadDateTooOld = 'messageInfoReadDateTooOld';
  static const messageInfoReadDateUnavailable =
      'messageInfoReadDateUnavailable';
  static const messageInfoSender = 'messageInfoSender';
  static const messageInfoSent = 'messageInfoSent';
  static const messageInfoText = 'messageInfoText';
  static const messageInfoType = 'messageInfoType';
  static const messageInfoUnknownViewer = 'messageInfoUnknownViewer';
  static const messageInfoUnread = 'messageInfoUnread';
  static const messageInfoViewers = 'messageInfoViewers';
  static const messageInfoViews = 'messageInfoViews';
  static const messageBubbleCollapse = 'messageBubbleCollapse';
  static const messageBubbleExpandQuote = 'messageBubbleExpandQuote';
  static const messageBubbleForwardedFrom = 'messageBubbleForwardedFrom';
  static const messageBubbleTranslating = 'messageBubbleTranslating';
  static const messageRepliesEmpty = 'messageRepliesEmpty';
  static const messageRepliesTitle = 'messageRepliesTitle';
  static const messageRepliesUnavailable = 'messageRepliesUnavailable';
  static const miniAppCannotStart = 'miniAppCannotStart';
  static const miniAppClose = 'miniAppClose';
  static const miniAppNoMatches = 'miniAppNoMatches';
  static const miniAppOpenInBrowser = 'miniAppOpenInBrowser';
  static const miniAppRecentEmpty = 'miniAppRecentEmpty';
  static const miniAppRecentSection = 'miniAppRecentSection';
  static const miniAppReload = 'miniAppReload';
  static const momentsCommentCount = 'momentsCommentCount';
  static const momentsCommentPlaceholder = 'momentsCommentPlaceholder';
  static const momentsCreatePostTitle = 'momentsCreatePostTitle';
  static const momentsDetails = 'momentsDetails';
  static const momentsLiked = 'momentsLiked';
  static const momentsLikedByCount = 'momentsLikedByCount';
  static const momentsLikedByListWithOthers = 'momentsLikedByListWithOthers';
  static const momentsLikeFailed = 'momentsLikeFailed';
  static const momentsLoadingPosts = 'momentsLoadingPosts';
  static const momentsMore = 'momentsMore';
  static const momentsNewPostsCount = 'momentsNewPostsCount';
  static const momentsNoChannelContent = 'momentsNoChannelContent';
  static const momentsNoComments = 'momentsNoComments';
  static const momentsNoFriendPosts = 'momentsNoFriendPosts';
  static const momentsNoPostableChannels = 'momentsNoPostableChannels';
  static const momentsNoPostsFound = 'momentsNoPostsFound';
  static const momentsNoSearchableChannels = 'momentsNoSearchableChannels';
  static const momentsNotifySubscribers = 'momentsNotifySubscribers';
  static const momentsOpenOriginalMessage = 'momentsOpenOriginalMessage';
  static const momentsPickPhotoFailed = 'momentsPickPhotoFailed';
  static const momentsPostAction = 'momentsPostAction';
  static const momentsPostedTo = 'momentsPostedTo';
  static const momentsPostFailed = 'momentsPostFailed';
  static const momentsPublishTo = 'momentsPublishTo';
  static const momentsReplied = 'momentsReplied';
  static const momentsReplyFailed = 'momentsReplyFailed';
  static const momentsReplyPrefix = 'momentsReplyPrefix';
  static const momentsReplyToPlaceholder = 'momentsReplyToPlaceholder';
  static const momentsReplyToUser = 'momentsReplyToUser';
  static const momentsReplyToUserPlaceholder = 'momentsReplyToUserPlaceholder';
  static const momentsReplyUnavailable = 'momentsReplyUnavailable';
  static const momentsSearchChannelPosts = 'momentsSearchChannelPosts';
  static const momentsSearching = 'momentsSearching';
  static const momentsSearchJoinedChannelPosts =
      'momentsSearchJoinedChannelPosts';
  static const momentsSelectChannel = 'momentsSelectChannel';
  static const momentsSending = 'momentsSending';
  static const momentsShareSomethingPlaceholder =
      'momentsShareSomethingPlaceholder';
  static const momentsStories = 'momentsStories';
  static const storiesActiveCount = 'storiesActiveCount';
  static const storiesAdd = 'storiesAdd';
  static const storiesCountNew = 'storiesCountNew';
  static const storiesCountViewed = 'storiesCountViewed';
  static const storiesCreate = 'storiesCreate';
  static const storiesEmptyDescription = 'storiesEmptyDescription';
  static const storiesEmptyTitle = 'storiesEmptyTitle';
  static const storiesMy = 'storiesMy';
  static const storiesNew = 'storiesNew';
  static const storiesOpenFailed = 'storiesOpenFailed';
  static const storiesPhotoVideo = 'storiesPhotoVideo';
  static const storiesProfileArchive = 'storiesProfileArchive';
  static const storiesRecent = 'storiesRecent';
  static const storiesSeeAll = 'storiesSeeAll';
  static const storiesYourActive = 'storiesYourActive';
  static const storyManagementActions = 'storyManagementActions';
  static const storyManagementActive = 'storyManagementActive';
  static const storyManagementAlbumCount = 'storyManagementAlbumCount';
  static const storyManagementAlbumOpenFailed =
      'storyManagementAlbumOpenFailed';
  static const storyManagementAlbums = 'storyManagementAlbums';
  static const storyManagementArchive = 'storyManagementArchive';
  static const storyManagementArchivedCount = 'storyManagementArchivedCount';
  static const storyManagementEmptyActiveDescription =
      'storyManagementEmptyActiveDescription';
  static const storyManagementEmptyActiveTitle =
      'storyManagementEmptyActiveTitle';
  static const storyManagementEmptyArchiveDescription =
      'storyManagementEmptyArchiveDescription';
  static const storyManagementEmptyArchiveTitle =
      'storyManagementEmptyArchiveTitle';
  static const storyManagementHoursLeft = 'storyManagementHoursLeft';
  static const storyManagementLive = 'storyManagementLive';
  static const storyManagementLoadFailed = 'storyManagementLoadFailed';
  static const storyManagementNewAlbum = 'storyManagementNewAlbum';
  static const storyManagementNoAlbums = 'storyManagementNoAlbums';
  static const momentsUnknown = 'momentsUnknown';
  static const momentsUserLiked = 'momentsUserLiked';
  static const musicPlayerAdd = 'musicPlayerAdd';
  static const musicPlayerAddedToPlaylist = 'musicPlayerAddedToPlaylist';
  static const musicPlayerAddToPlaylist = 'musicPlayerAddToPlaylist';
  static const musicPlayerAlreadyInPlaylist = 'musicPlayerAlreadyInPlaylist';
  static const musicPlayerClear = 'musicPlayerClear';
  static const musicPlayerClose = 'musicPlayerClose';
  static const musicPlayerCreatePlaylist = 'musicPlayerCreatePlaylist';
  static const musicPlayerDownload = 'musicPlayerDownload';
  static const musicPlayerEmptyPlaylist = 'musicPlayerEmptyPlaylist';
  static const musicPlayerModeRepeatOne = 'musicPlayerModeRepeatOne';
  static const musicPlayerModeSequence = 'musicPlayerModeSequence';
  static const musicPlayerModeShuffle = 'musicPlayerModeShuffle';
  static const musicPlayerNextTrack = 'musicPlayerNextTrack';
  static const musicPlayerNoPlaylists = 'musicPlayerNoPlaylists';
  static const musicPlayerPause = 'musicPlayerPause';
  static const musicPlayerPlay = 'musicPlayerPlay';
  static const musicPlayerPlayedChats = 'musicPlayerPlayedChats';
  static const musicPlayerPlaylistAddFailed = 'musicPlayerPlaylistAddFailed';
  static const musicPlayerPlaylistCreated = 'musicPlayerPlaylistCreated';
  static const musicPlayerPlaylistCreateFailed =
      'musicPlayerPlaylistCreateFailed';
  static const musicPlayerPlaylistLoadFailed = 'musicPlayerPlaylistLoadFailed';
  static const musicPlayerPlaylistName = 'musicPlayerPlaylistName';
  static const musicPlayerPlaylists = 'musicPlayerPlaylists';
  static const musicPlayerQueueTitleWithCount =
      'musicPlayerQueueTitleWithCount';
  static const musicPlayerRemovedFromPlaylist =
      'musicPlayerRemovedFromPlaylist';
  static const musicPlayerRemoveFromPlaylist = 'musicPlayerRemoveFromPlaylist';
  static const musicPlayerShowPlaylist = 'musicPlayerShowPlaylist';
  static const musicPlayerTrackCount = 'musicPlayerTrackCount';
  static const myAlbumNoPhotos = 'myAlbumNoPhotos';
  static const netemoMusicLabel = 'netemoMusicLabel';
  static const notificationAllAccounts = 'notificationAllAccounts';
  static const notificationAllAccountsDescription =
      'notificationAllAccountsDescription';
  static const notificationAllAccountsDescriptionOff =
      'notificationAllAccountsDescriptionOff';
  static const notificationAllStories = 'notificationAllStories';
  static const notificationChannels = 'notificationChannels';
  static const notificationException = 'notificationException';
  static const notificationExceptions = 'notificationExceptions';
  static const notificationGroupMessages = 'notificationGroupMessages';
  static const notificationInAppBanners = 'notificationInAppBanners';
  static const notificationInAppPreview = 'notificationInAppPreview';
  static const notificationInAppSection = 'notificationInAppSection';
  static const notificationInAppSounds = 'notificationInAppSounds';
  static const notificationInAppVibrate = 'notificationInAppVibrate';
  static const notificationMentions = 'notificationMentions';
  static const notificationMessageNotifications =
      'notificationMessageNotifications';
  static const notificationNamesOnLockScreen = 'notificationNamesOnLockScreen';
  static const notificationNamesOnLockScreenDescription =
      'notificationNamesOnLockScreenDescription';
  static const notificationNewMessage = 'notificationNewMessage';
  static const notificationNoStories = 'notificationNoStories';
  static const notificationNotifications = 'notificationNotifications';
  static const notificationOptions = 'notificationOptions';
  static const notificationPinnedMessages = 'notificationPinnedMessages';
  static const notificationPreview = 'notificationPreview';
  static const notificationPrivateMessages = 'notificationPrivateMessages';
  static const notificationReactionMessages = 'notificationReactionMessages';
  static const notificationReactions = 'notificationReactions';
  static const notificationShowNotificationsFrom =
      'notificationShowNotificationsFrom';
  static const notificationSound = 'notificationSound';
  static const notificationStories = 'notificationStories';
  static const notificationStoryPoster = 'notificationStoryPoster';
  static const notificationTitle = 'notificationTitle';
  static const notificationTopFive = 'notificationTopFive';
  static const notificationTopFiveDescription =
      'notificationTopFiveDescription';
  static const pinnedMessagesEmpty = 'pinnedMessagesEmpty';
  static const pinnedMessagesSentBy = 'pinnedMessagesSentBy';
  static const pollComposerAddOption = 'pollComposerAddOption';
  static const pollComposerCreatePollTitle = 'pollComposerCreatePollTitle';
  static const pollComposerOptionLabel = 'pollComposerOptionLabel';
  static const pollComposerQuestionRequired = 'pollComposerQuestionRequired';
  static const pollComposerSingleChoiceLimitHint =
      'pollComposerSingleChoiceLimitHint';
  static const premiumLabel = 'premiumLabel';
  static const passkeysAdded = 'passkeysAdded';
  static const passkeysCreatedOn = 'passkeysCreatedOn';
  static const passkeysDelete = 'passkeysDelete';
  static const passkeysDeleteMessage = 'passkeysDeleteMessage';
  static const passkeysDeleteTitle = 'passkeysDeleteTitle';
  static const passkeysDescription = 'passkeysDescription';
  static const passkeysEmpty = 'passkeysEmpty';
  static const passkeysErrorAlreadySignedIn = 'passkeysErrorAlreadySignedIn';
  static const passkeysErrorGeneric = 'passkeysErrorGeneric';
  static const passkeysErrorNoCredential = 'passkeysErrorNoCredential';
  static const passkeysErrorNotAllowed = 'passkeysErrorNotAllowed';
  static const passkeysErrorUnavailable = 'passkeysErrorUnavailable';
  static const passkeysLastUsedOn = 'passkeysLastUsedOn';
  static const passkeysRemoved = 'passkeysRemoved';
  static const passkeysTitle = 'passkeysTitle';
  static const passkeysUnknownName = 'passkeysUnknownName';
  static const privacyAddExceptions = 'privacyAddExceptions';
  static const privacyAddUsers = 'privacyAddUsers';
  static const privacyAlwaysShareWith = 'privacyAlwaysShareWith';
  static const privacyBio = 'privacyBio';
  static const privacyBirthDate = 'privacyBirthDate';
  static const privacyBlockedUsers = 'privacyBlockedUsers';
  static const privacyBlockedUsersEmpty = 'privacyBlockedUsersEmpty';
  static const privacyCalls = 'privacyCalls';
  static const privacyCurrentDevice = 'privacyCurrentDevice';
  static const privacyDeleteTelegramAccount = 'privacyDeleteTelegramAccount';
  static const privacyDeleteTelegramAccountMessage =
      'privacyDeleteTelegramAccountMessage';
  static const privacyDeleteTelegramAccountOpen =
      'privacyDeleteTelegramAccountOpen';
  static const privacyDeviceApp = 'privacyDeviceApp';
  static const privacyDisabled = 'privacyDisabled';
  static const privacyEnabled = 'privacyEnabled';
  static const privacyExceptionsHint = 'privacyExceptionsHint';
  static const privacyForwardedMessages = 'privacyForwardedMessages';
  static const privacyGroupsAndChannels = 'privacyGroupsAndChannels';
  static const privacyLastSeen = 'privacyLastSeen';
  static const privacyLoadFailed = 'privacyLoadFailed';
  static const privacyLoggedInDevices = 'privacyLoggedInDevices';
  static const privacyLoginQrAccepted = 'privacyLoginQrAccepted';
  static const privacyLoginQrAcceptFailed = 'privacyLoginQrAcceptFailed';
  static const privacyLoginQrInvalid = 'privacyLoginQrInvalid';
  static const privacyNeverShareWith = 'privacyNeverShareWith';
  static const privacyNoOtherDevices = 'privacyNoOtherDevices';
  static const privacyOtherDevices = 'privacyOtherDevices';
  static const privacyPeerToPeerCalls = 'privacyPeerToPeerCalls';
  static const privacyPeerToPeerHint = 'privacyPeerToPeerHint';
  static const privacyPhoneDiscoveryHint = 'privacyPhoneDiscoveryHint';
  static const privacyPhoneNumber = 'privacyPhoneNumber';
  static const privacyProfileAudio = 'privacyProfileAudio';
  static const privacyProfilePhoto = 'privacyProfilePhoto';
  static const privacyProfilePhotoVisibilityHint =
      'privacyProfilePhotoVisibilityHint';
  static const privacyPublicPhotoHint = 'privacyPublicPhotoHint';
  static const privacyPublicPhotoRemoved = 'privacyPublicPhotoRemoved';
  static const privacyPublicPhotoUpdated = 'privacyPublicPhotoUpdated';
  static const privacyPublicPhotoUpdateFailed =
      'privacyPublicPhotoUpdateFailed';
  static const privacyRemovePublicPhoto = 'privacyRemovePublicPhoto';
  static const privacyRemovePublicPhotoQuestion =
      'privacyRemovePublicPhotoQuestion';
  static const privacyRetry = 'privacyRetry';
  static const privacyScanLoginQr = 'privacyScanLoginQr';
  static const privacyScanLoginQrSubtitle = 'privacyScanLoginQrSubtitle';
  static const privacySectionTitle = 'privacySectionTitle';
  static const privacySecuritySectionTitle = 'privacySecuritySectionTitle';
  static const privacySecurityTitle = 'privacySecurityTitle';
  static const privacySensitiveContent = 'privacySensitiveContent';
  static const privacyShowReadDate = 'privacyShowReadDate';
  static const privacyShowReadDateHint = 'privacyShowReadDateHint';
  static const privacyTerminateAllOtherSessions =
      'privacyTerminateAllOtherSessions';
  static const privacyTerminateSession = 'privacyTerminateSession';
  static const privacyTerminateSessionMessage =
      'privacyTerminateSessionMessage';
  static const privacyTerminateSessionQuestion =
      'privacyTerminateSessionQuestion';
  static const privacyTwoStepVerification = 'privacyTwoStepVerification';
  static const privacyUnblock = 'privacyUnblock';
  static const privacyUpdatePublicPhoto = 'privacyUpdatePublicPhoto';
  static const privacyVisibilityContacts = 'privacyVisibilityContacts';
  static const privacyVisibilityEveryone = 'privacyVisibilityEveryone';
  static const privacyVisibilityNobody = 'privacyVisibilityNobody';
  static const privacyVoiceMessages = 'privacyVoiceMessages';
  static const privacyWhoCanFindByPhone = 'privacyWhoCanFindByPhone';
  static const privacyWhoCanSeeProfilePhoto = 'privacyWhoCanSeeProfilePhoto';
  static const profileAddAccount = 'profileAddAccount';
  static const profileDayMode = 'profileDayMode';
  static const profileDetailAddFriend = 'profileDetailAddFriend';
  static const profileDetailAddFriendDone = 'profileDetailAddFriendDone';
  static const profileDetailAddFriendFailed = 'profileDetailAddFriendFailed';
  static const profileDetailArchivedPosts = 'profileDetailArchivedPosts';
  static const profileDetailAudioVideoCall = 'profileDetailAudioVideoCall';
  static const profileDetailBio = 'profileDetailBio';
  static const profileDetailBirthday = 'profileDetailBirthday';
  static const profileDetailBusinessHours = 'profileDetailBusinessHours';
  static const profileDetailCardLinkCopied = 'profileDetailCardLinkCopied';
  static const profileDetailCopyLink = 'profileDetailCopyLink';
  static const profileDetailFeaturedPhotos = 'profileDetailFeaturedPhotos';
  static const profileDetailGifts = 'profileDetailGifts';
  static const profileDetailLocation = 'profileDetailLocation';
  static const profileDetailMediaFiles = 'profileDetailMediaFiles';
  static const profileDetailMonthDayDate = 'profileDetailMonthDayDate';
  static const profileDetailMusic = 'profileDetailMusic';
  static const profileDetailPosts = 'profileDetailPosts';
  static const profileDetailSendMessage = 'profileDetailSendMessage';
  static const profileDetailYearMonthDate = 'profileDetailYearMonthDate';
  static const profileToolsAcceptGiftsFromChannels =
      'profileToolsAcceptGiftsFromChannels';
  static const profileToolsAcceptGiftsFromChannelsDescription =
      'profileToolsAcceptGiftsFromChannelsDescription';
  static const profileToolsAcceptLimitedGifts =
      'profileToolsAcceptLimitedGifts';
  static const profileToolsAcceptPremiumGifts =
      'profileToolsAcceptPremiumGifts';
  static const profileToolsAcceptPremiumGiftsDescription =
      'profileToolsAcceptPremiumGiftsDescription';
  static const profileToolsAcceptUnlimitedGifts =
      'profileToolsAcceptUnlimitedGifts';
  static const profileToolsAcceptUpgradedGifts =
      'profileToolsAcceptUpgradedGifts';
  static const profileToolsAcceptUpgradedGiftsDescription =
      'profileToolsAcceptUpgradedGiftsDescription';
  static const profileToolsActionFailed = 'profileToolsActionFailed';
  static const profileToolsChooseProfileChat = 'profileToolsChooseProfileChat';
  static const profileToolsCurrentPublicPhotoHistory =
      'profileToolsCurrentPublicPhotoHistory';
  static const profileToolsGiftsSection = 'profileToolsGiftsSection';
  static const profileToolsGiftSettingsUpdated =
      'profileToolsGiftSettingsUpdated';
  static const profileToolsKeepGiftActionsVisible =
      'profileToolsKeepGiftActionsVisible';
  static const profileToolsLimitedGiftsDescription =
      'profileToolsLimitedGiftsDescription';
  static const profileToolsLoadFailed = 'profileToolsLoadFailed';
  static const profileToolsManageProfilePhotos =
      'profileToolsManageProfilePhotos';
  static const profileToolsPersonalChatSection =
      'profileToolsPersonalChatSection';
  static const profileToolsPhotoChatSummary = 'profileToolsPhotoChatSummary';
  static const profileToolsPremiumRequired = 'profileToolsPremiumRequired';
  static const profileToolsProfileChatId = 'profileToolsProfileChatId';
  static const profileToolsProfileChatRemoved =
      'profileToolsProfileChatRemoved';
  static const profileToolsProfileChatUpdated =
      'profileToolsProfileChatUpdated';
  static const profileToolsProfilePhotosSection =
      'profileToolsProfilePhotosSection';
  static const profileToolsRefresh = 'profileToolsRefresh';
  static const profileToolsRegularGiftsWithoutSupplyLimit =
      'profileToolsRegularGiftsWithoutSupplyLimit';
  static const profileToolsRemoveProfileChat = 'profileToolsRemoveProfileChat';
  static const profileToolsShowChatOnProfile = 'profileToolsShowChatOnProfile';
  static const profileToolsShowGiftButton = 'profileToolsShowGiftButton';
  static const profileToolsStopShowingProfileChat =
      'profileToolsStopShowingProfileChat';
  static const profileToolsTitle = 'profileToolsTitle';
  static const profilePhotoDeleteFailed = 'profilePhotoDeleteFailed';
  static const profilePhotoDeleteMessage = 'profilePhotoDeleteMessage';
  static const profilePhotoDeleteTitle = 'profilePhotoDeleteTitle';
  static const profilePhotoDeleted = 'profilePhotoDeleted';
  static const profilePhotoSetAsAvatar = 'profilePhotoSetAsAvatar';
  static const profileLogOutAccount = 'profileLogOutAccount';
  static const profileLogOutAccountConfirm = 'profileLogOutAccountConfirm';
  static const profileNightMode = 'profileNightMode';
  static const profileRemoveAccount = 'profileRemoveAccount';
  static const profileRemoveAccountConfirm = 'profileRemoveAccountConfirm';
  static const profileSettings = 'profileSettings';
  static const proxyAddFailed = 'proxyAddFailed';
  static const proxyAddFromLink = 'proxyAddFromLink';
  static const proxyAddFromLinkHint = 'proxyAddFromLinkHint';
  static const proxyAddFromLinkTitle = 'proxyAddFromLinkTitle';
  static const proxyAddProxy = 'proxyAddProxy';
  static const proxyDeleteProxy = 'proxyDeleteProxy';
  static const proxyDescription = 'proxyDescription';
  static const proxyDisabled = 'proxyDisabled';
  static const proxyHostOrIp = 'proxyHostOrIp';
  static const proxyOptional = 'proxyOptional';
  static const proxyPassword = 'proxyPassword';
  static const proxyPort = 'proxyPort';
  static const proxySecret = 'proxySecret';
  static const proxyServer = 'proxyServer';
  static const proxyTitle = 'proxyTitle';
  static const qrCodeGroupTitle = 'qrCodeGroupTitle';
  static const qrCodeMineTitle = 'qrCodeMineTitle';
  static const qrCodeNoGroupQrCode = 'qrCodeNoGroupQrCode';
  static const qrCodeScanToAddFriend = 'qrCodeScanToAddFriend';
  static const qrCodeScanToJoinGroup = 'qrCodeScanToJoinGroup';
  static const qrScannerCameraUnavailable = 'qrScannerCameraUnavailable';
  static const qrScannerCopied = 'qrScannerCopied';
  static const qrScannerCopy = 'qrScannerCopy';
  static const qrScannerDetailsTitle = 'qrScannerDetailsTitle';
  static const qrScannerHint = 'qrScannerHint';
  static const qrScannerLink = 'qrScannerLink';
  static const qrScannerMultipleHint = 'qrScannerMultipleHint';
  static const qrScannerMultipleTitle = 'qrScannerMultipleTitle';
  static const qrScannerOpen = 'qrScannerOpen';
  static const qrScannerText = 'qrScannerText';
  static const qrScannerTitle = 'qrScannerTitle';
  static const quickReactionsAvailable = 'quickReactionsAvailable';
  static const quickReactionsCount = 'quickReactionsCount';
  static const quickReactionsHint = 'quickReactionsHint';
  static const quickReactionsKeepOne = 'quickReactionsKeepOne';
  static const quickReactionsLimit = 'quickReactionsLimit';
  static const quickReactionsSelected = 'quickReactionsSelected';
  static const quickReactionsTitle = 'quickReactionsTitle';
  static const richTextBlockAnchor = 'richTextBlockAnchor';
  static const richTextBlockAnimation = 'richTextBlockAnimation';
  static const richTextBlockAudio = 'richTextBlockAudio';
  static const richTextBlockBlockQuotation = 'richTextBlockBlockQuotation';
  static const richTextBlockCollage = 'richTextBlockCollage';
  static const richTextBlockDetails = 'richTextBlockDetails';
  static const richTextBlockDivider = 'richTextBlockDivider';
  static const richTextBlockFooter = 'richTextBlockFooter';
  static const richTextBlockHeading = 'richTextBlockHeading';
  static const richTextBlockList = 'richTextBlockList';
  static const richTextBlockMap = 'richTextBlockMap';
  static const richTextBlockMathematicalExpression =
      'richTextBlockMathematicalExpression';
  static const richTextBlockParagraph = 'richTextBlockParagraph';
  static const richTextBlockPhoto = 'richTextBlockPhoto';
  static const richTextBlockPreformatted = 'richTextBlockPreformatted';
  static const richTextBlockPullQuotation = 'richTextBlockPullQuotation';
  static const richTextBlockSlideshow = 'richTextBlockSlideshow';
  static const richTextBlockTable = 'richTextBlockTable';
  static const richTextBlockThinking = 'richTextBlockThinking';
  static const richTextBlockVideo = 'richTextBlockVideo';
  static const richTextBlockVoiceNote = 'richTextBlockVoiceNote';
  static const richTextComposerAddColumn = 'richTextComposerAddColumn';
  static const richTextComposerAddRow = 'richTextComposerAddRow';
  static const richTextComposerAnchorName = 'richTextComposerAnchorName';
  static const richTextComposerContentPlaceholder =
      'richTextComposerContentPlaceholder';
  static const richTextComposerDetailsContent =
      'richTextComposerDetailsContent';
  static const richTextComposerDetailsOpen = 'richTextComposerDetailsOpen';
  static const richTextComposerDetailsSummary =
      'richTextComposerDetailsSummary';
  static const richTextComposerFormatBold = 'richTextComposerFormatBold';
  static const richTextComposerFormatBoldMark =
      'richTextComposerFormatBoldMark';
  static const richTextComposerFormatCode = 'richTextComposerFormatCode';
  static const richTextComposerFormatItalic = 'richTextComposerFormatItalic';
  static const richTextComposerFormatItalicMark =
      'richTextComposerFormatItalicMark';
  static const richTextComposerFormatMarked = 'richTextComposerFormatMarked';
  static const richTextComposerFormatSpoiler = 'richTextComposerFormatSpoiler';
  static const richTextComposerFormatStrikethrough =
      'richTextComposerFormatStrikethrough';
  static const richTextComposerFormatStrikethroughMark =
      'richTextComposerFormatStrikethroughMark';
  static const richTextComposerFormatSubscript =
      'richTextComposerFormatSubscript';
  static const richTextComposerFormatSuperscript =
      'richTextComposerFormatSuperscript';
  static const richTextComposerFormatUnderline =
      'richTextComposerFormatUnderline';
  static const richTextComposerFormatUnderlineMark =
      'richTextComposerFormatUnderlineMark';
  static const richTextComposerInsert = 'richTextComposerInsert';
  static const richTextComposerInsertTable = 'richTextComposerInsertTable';
  static const richTextComposerLimitExceeded = 'richTextComposerLimitExceeded';
  static const richTextComposerMapLatitude = 'richTextComposerMapLatitude';
  static const richTextComposerMapLongitude = 'richTextComposerMapLongitude';
  static const richTextComposerMapZoom = 'richTextComposerMapZoom';
  static const richTextComposerMoveDown = 'richTextComposerMoveDown';
  static const richTextComposerMoveUp = 'richTextComposerMoveUp';
  static const richTextComposerPhotoVideo = 'richTextComposerPhotoVideo';
  static const richTextComposerRemoveBlock = 'richTextComposerRemoveBlock';
  static const richTextComposerRemoveColumn = 'richTextComposerRemoveColumn';
  static const richTextComposerRemoveRow = 'richTextComposerRemoveRow';
  static const richTextComposerRemoveTable = 'richTextComposerRemoveTable';
  static const richTextRelayBotConfigure = 'richTextRelayBotConfigure';
  static const richTextRelayBotConfigured = 'richTextRelayBotConfigured';
  static const richTextRelayBotConnected = 'richTextRelayBotConnected';
  static const richTextRelayBotCreateDescription =
      'richTextRelayBotCreateDescription';
  static const richTextRelayBotDescription = 'richTextRelayBotDescription';
  static const richTextRelayBotNotConfigured = 'richTextRelayBotNotConfigured';
  static const richTextRelayBotOpenBotFather = 'richTextRelayBotOpenBotFather';
  static const richTextRelayBotRemove = 'richTextRelayBotRemove';
  static const richTextRelayBotRemoved = 'richTextRelayBotRemoved';
  static const richTextRelayBotSave = 'richTextRelayBotSave';
  static const richTextRelayBotSaved = 'richTextRelayBotSaved';
  static const richTextRelayBotSetupDescription =
      'richTextRelayBotSetupDescription';
  static const richTextRelayBotSetupTitle = 'richTextRelayBotSetupTitle';
  static const richTextRelayBotStartRequired = 'richTextRelayBotStartRequired';
  static const richTextRelayBotTitle = 'richTextRelayBotTitle';
  static const richTextRelayForwardedWithSender =
      'richTextRelayForwardedWithSender';
  static const richTextRelayMediaPremiumRequired =
      'richTextRelayMediaPremiumRequired';
  static const richTextRelayPremiumOrBotRequired =
      'richTextRelayPremiumOrBotRequired';
  static const richTextRelayProgressCompose = 'richTextRelayProgressCompose';
  static const richTextRelayProgressForward = 'richTextRelayProgressForward';
  static const richTextRelayProgressUpload = 'richTextRelayProgressUpload';
  static const richTextRelayProgressWait = 'richTextRelayProgressWait';
  static const richTextTableAddColumnLeft = 'richTextTableAddColumnLeft';
  static const richTextTableAddColumnRight = 'richTextTableAddColumnRight';
  static const richTextTableAddRowAbove = 'richTextTableAddRowAbove';
  static const richTextTableAddRowBelow = 'richTextTableAddRowBelow';
  static const richTextTableAlignBottom = 'richTextTableAlignBottom';
  static const richTextTableAlignCenter = 'richTextTableAlignCenter';
  static const richTextTableAlignLeft = 'richTextTableAlignLeft';
  static const richTextTableAlignMiddle = 'richTextTableAlignMiddle';
  static const richTextTableAlignRight = 'richTextTableAlignRight';
  static const richTextTableAlignTop = 'richTextTableAlignTop';
  static const richTextTableBordered = 'richTextTableBordered';
  static const richTextTableBorderless = 'richTextTableBorderless';
  static const richTextTableChange = 'richTextTableChange';
  static const richTextTableHeader = 'richTextTableHeader';
  static const richTextTableStriped = 'richTextTableStriped';
  static const savedMessages = 'savedMessages';
  static const secretChatClosed = 'secretChatClosed';
  static const secretChatStart = 'secretChatStart';
  static const secretChatStartFailed = 'secretChatStartFailed';
  static const secretChatStartMessage = 'secretChatStartMessage';
  static const secretChatStartTitle = 'secretChatStartTitle';
  static const secretChatWaiting = 'secretChatWaiting';
  static const sensitiveContentUnblockConfirm =
      'sensitiveContentUnblockConfirm';
  static const sensitiveContentUnblockDone = 'sensitiveContentUnblockDone';
  static const sensitiveContentUnblockFailed = 'sensitiveContentUnblockFailed';
  static const sensitiveContentUnblockMessage =
      'sensitiveContentUnblockMessage';
  static const sensitiveContentUnblockTitle = 'sensitiveContentUnblockTitle';
  static const settingsAboutMithka = 'settingsAboutMithka';
  static const settingsLogOut = 'settingsLogOut';
  static const sharedMediaCacheDeleted = 'sharedMediaCacheDeleted';
  static const sharedMediaCacheDeleteFailed = 'sharedMediaCacheDeleteFailed';
  static const sharedMediaChatFiles = 'sharedMediaChatFiles';
  static const sharedMediaDeleteLocalCache = 'sharedMediaDeleteLocalCache';
  static const sharedMediaDownloadedSize = 'sharedMediaDownloadedSize';
  static const sharedMediaDownloadProgress = 'sharedMediaDownloadProgress';
  static const sharedMediaEmpty = 'sharedMediaEmpty';
  static const sharedMediaFilterAll = 'sharedMediaFilterAll';
  static const sharedMediaFilterDownloaded = 'sharedMediaFilterDownloaded';
  static const sharedMediaFilterNotDownloaded =
      'sharedMediaFilterNotDownloaded';
  static const sharedMediaFromSource = 'sharedMediaFromSource';
  static const sharedMediaLinks = 'sharedMediaLinks';
  static const sharedMediaNoMatches = 'sharedMediaNoMatches';
  static const sharedMediaNotDownloadedSize = 'sharedMediaNotDownloadedSize';
  static const sharedMediaPhotos = 'sharedMediaPhotos';
  static const sharedMediaPhotosAndVideos = 'sharedMediaPhotosAndVideos';
  static const sharedMediaSearchFilesHint = 'sharedMediaSearchFilesHint';
  static const sharedMediaSearchVideosHint = 'sharedMediaSearchVideosHint';
  static const sharedMediaVideos = 'sharedMediaVideos';
  static const sharedMediaVideoTitleWithDate = 'sharedMediaVideoTitleWithDate';
  static const sharedMediaVoice = 'sharedMediaVoice';
  static const sharedMediaVoiceMessages = 'sharedMediaVoiceMessages';
  static const startButton = 'startButton';
  static const stickerExportFailed = 'stickerExportFailed';
  static const stickerExportPreparing = 'stickerExportPreparing';
  static const stickerExportSavedToFiles = 'stickerExportSavedToFiles';
  static const stickerExportSaveToFiles = 'stickerExportSaveToFiles';
  static const stickerExportUnsupported = 'stickerExportUnsupported';
  static const stickerSetDetailActionFailed = 'stickerSetDetailActionFailed';
  static const stickerSetDetailAddSuccess = 'stickerSetDetailAddSuccess';
  static const stickerSetDetailRemoved = 'stickerSetDetailRemoved';
  static const stickerSetDetailStickerCount = 'stickerSetDetailStickerCount';
  static const stickerSetDetailTitle = 'stickerSetDetailTitle';
  static const stickerStoreRecent = 'stickerStoreRecent';
  static const stickerStudioActionEditEmoji = 'stickerStudioActionEditEmoji';
  static const stickerStudioActionEditKeywords =
      'stickerStudioActionEditKeywords';
  static const stickerStudioActionEditMask = 'stickerStudioActionEditMask';
  static const stickerStudioActionMoveEarlier =
      'stickerStudioActionMoveEarlier';
  static const stickerStudioActionMoveLater = 'stickerStudioActionMoveLater';
  static const stickerStudioActionRemove = 'stickerStudioActionRemove';
  static const stickerStudioActionReplace = 'stickerStudioActionReplace';
  static const stickerStudioActionUseThumbnail =
      'stickerStudioActionUseThumbnail';
  static const stickerStudioAddSource = 'stickerStudioAddSource';
  static const stickerStudioAnchorMask = 'stickerStudioAnchorMask';
  static const stickerStudioChoose = 'stickerStudioChoose';
  static const stickerStudioChooseSourceFirst =
      'stickerStudioChooseSourceFirst';
  static const stickerStudioCreate = 'stickerStudioCreate';
  static const stickerStudioCreateFailed = 'stickerStudioCreateFailed';
  static const stickerStudioCreateSubtitle = 'stickerStudioCreateSubtitle';
  static const stickerStudioCustomEmojiThumbnailRemove =
      'stickerStudioCustomEmojiThumbnailRemove';
  static const stickerStudioDelete = 'stickerStudioDelete';
  static const stickerStudioDeleteFailed = 'stickerStudioDeleteFailed';
  static const stickerStudioDeleteMessage = 'stickerStudioDeleteMessage';
  static const stickerStudioDeleteTitle = 'stickerStudioDeleteTitle';
  static const stickerStudioEmpty = 'stickerStudioEmpty';
  static const stickerStudioEmptySet = 'stickerStudioEmptySet';
  static const stickerStudioFieldKeywords = 'stickerStudioFieldKeywords';
  static const stickerStudioFieldMatchingEmoji =
      'stickerStudioFieldMatchingEmoji';
  static const stickerStudioFieldShortName = 'stickerStudioFieldShortName';
  static const stickerStudioFieldTitle = 'stickerStudioFieldTitle';
  static const stickerStudioFormatFile = 'stickerStudioFormatFile';
  static const stickerStudioFormatTgs = 'stickerStudioFormatTgs';
  static const stickerStudioFormatVideo = 'stickerStudioFormatVideo';
  static const stickerStudioFormatWebp = 'stickerStudioFormatWebp';
  static const stickerStudioHorizontalShift = 'stickerStudioHorizontalShift';
  static const stickerStudioItemCount = 'stickerStudioItemCount';
  static const stickerStudioKeywordsHint = 'stickerStudioKeywordsHint';
  static const stickerStudioLoadFailed = 'stickerStudioLoadFailed';
  static const stickerStudioLoadOwnedFailed = 'stickerStudioLoadOwnedFailed';
  static const stickerStudioMaskPlacement = 'stickerStudioMaskPlacement';
  static const stickerStudioMaskPlacementValue =
      'stickerStudioMaskPlacementValue';
  static const stickerStudioMatchingEmojiHint =
      'stickerStudioMatchingEmojiHint';
  static const stickerStudioNameUnavailable = 'stickerStudioNameUnavailable';
  static const stickerStudioNewSet = 'stickerStudioNewSet';
  static const stickerStudioNoFile = 'stickerStudioNoFile';
  static const stickerStudioRemove = 'stickerStudioRemove';
  static const stickerStudioRefresh = 'stickerStudioRefresh';
  static const stickerStudioRemoveMessage = 'stickerStudioRemoveMessage';
  static const stickerStudioRemoveSticker = 'stickerStudioRemoveSticker';
  static const stickerStudioRemoveThumbnail = 'stickerStudioRemoveThumbnail';
  static const stickerStudioRename = 'stickerStudioRename';
  static const stickerStudioRepaint = 'stickerStudioRepaint';
  static const stickerStudioSave = 'stickerStudioSave';
  static const stickerStudioScale = 'stickerStudioScale';
  static const stickerStudioSetLimit = 'stickerStudioSetLimit';
  static const stickerStudioSetThumbnail = 'stickerStudioSetThumbnail';
  static const stickerStudioSetTitle = 'stickerStudioSetTitle';
  static const stickerStudioSetTitleHint = 'stickerStudioSetTitleHint';
  static const stickerStudioSetType = 'stickerStudioSetType';
  static const stickerStudioShortNameSuggest = 'stickerStudioShortNameSuggest';
  static const stickerStudioSourceGenericNote =
      'stickerStudioSourceGenericNote';
  static const stickerStudioSourceNeedsChanges =
      'stickerStudioSourceNeedsChanges';
  static const stickerStudioSourceSpecNote = 'stickerStudioSourceSpecNote';
  static const stickerStudioSourceTitle = 'stickerStudioSourceTitle';
  static const stickerStudioSourceWebmNote = 'stickerStudioSourceWebmNote';
  static const stickerStudioSuggestFailed = 'stickerStudioSuggestFailed';
  static const stickerStudioTitle = 'stickerStudioTitle';
  static const stickerStudioTitleInvalid = 'stickerStudioTitleInvalid';
  static const stickerStudioTypeCustomEmoji = 'stickerStudioTypeCustomEmoji';
  static const stickerStudioTypeCustomEmojiDetail =
      'stickerStudioTypeCustomEmojiDetail';
  static const stickerStudioTypeMask = 'stickerStudioTypeMask';
  static const stickerStudioTypeMaskDetail = 'stickerStudioTypeMaskDetail';
  static const stickerStudioTypeRegular = 'stickerStudioTypeRegular';
  static const stickerStudioTypeRegularDetail =
      'stickerStudioTypeRegularDetail';
  static const stickerStudioUntitled = 'stickerStudioUntitled';
  static const stickerStudioUpdateFailed = 'stickerStudioUpdateFailed';
  static const stickerStudioValidationAddSticker =
      'stickerStudioValidationAddSticker';
  static const stickerStudioValidationAnimatedCanvas =
      'stickerStudioValidationAnimatedCanvas';
  static const stickerStudioValidationAnimatedDuration =
      'stickerStudioValidationAnimatedDuration';
  static const stickerStudioValidationAnimatedSize =
      'stickerStudioValidationAnimatedSize';
  static const stickerStudioValidationExtension =
      'stickerStudioValidationExtension';
  static const stickerStudioValidationFileMissing =
      'stickerStudioValidationFileMissing';
  static const stickerStudioValidationImage = 'stickerStudioValidationImage';
  static const stickerStudioValidationKeywordsCharacters =
      'stickerStudioValidationKeywordsCharacters';
  static const stickerStudioValidationKeywordsCount =
      'stickerStudioValidationKeywordsCount';
  static const stickerStudioValidationMaskFormat =
      'stickerStudioValidationMaskFormat';
  static const stickerStudioValidationMaskOnly =
      'stickerStudioValidationMaskOnly';
  static const stickerStudioValidationMaskScale =
      'stickerStudioValidationMaskScale';
  static const stickerStudioValidationMatchingEmoji =
      'stickerStudioValidationMatchingEmoji';
  static const stickerStudioValidationMatchingEmojiCount =
      'stickerStudioValidationMatchingEmojiCount';
  static const stickerStudioValidationStaticDimensions =
      'stickerStudioValidationStaticDimensions';
  static const stickerStudioValidationStaticSize =
      'stickerStudioValidationStaticSize';
  static const stickerStudioValidationTgs = 'stickerStudioValidationTgs';
  static const stickerStudioValidationVideo = 'stickerStudioValidationVideo';
  static const stickerStudioValidationVideoSize =
      'stickerStudioValidationVideoSize';
  static const stickerStudioVerticalShift = 'stickerStudioVerticalShift';
  static const stickerViewerInCollection = 'stickerViewerInCollection';
  static const stickerViewerView = 'stickerViewerView';
  static const storyLoadFailed = 'storyLoadFailed';
  static const storyAdd = 'storyAdd';
  static const storyAddedCount = 'storyAddedCount';
  static const storyCamera = 'storyCamera';
  static const storyCameraAccessTitle = 'storyCameraAccessTitle';
  static const storyCameraAccessDescription = 'storyCameraAccessDescription';
  static const storyCameraUnavailable = 'storyCameraUnavailable';
  static const storyCaptionHint = 'storyCaptionHint';
  static const storyChoose = 'storyChoose';
  static const storyChooseDestination = 'storyChooseDestination';
  static const storyChooseMedia = 'storyChooseMedia';
  static const storyChooseMediaHint = 'storyChooseMediaHint';
  static const storyClickableAreas = 'storyClickableAreas';
  static const storyClickableAreasHint = 'storyClickableAreasHint';
  static const storyGallery = 'storyGallery';
  static const storyHours = 'storyHours';
  static const storyKeepOnProfile = 'storyKeepOnProfile';
  static const storyNewTitle = 'storyNewTitle';
  static const storyNext = 'storyNext';
  static const storyOpenSettings = 'storyOpenSettings';
  static const storyPostAs = 'storyPostAs';
  static const storyPrivacy = 'storyPrivacy';
  static const storyPrivacyEveryone = 'storyPrivacyEveryone';
  static const storyPrivacyContacts = 'storyPrivacyContacts';
  static const storyPrivacyCloseFriends = 'storyPrivacyCloseFriends';
  static const storyPrivacySelected = 'storyPrivacySelected';
  static const storyProtectSharing = 'storyProtectSharing';
  static const storyAllowScreenshots = 'storyAllowScreenshots';
  static const storyPublish = 'storyPublish';
  static const storyPublishing = 'storyPublishing';
  static const storySelectedCount = 'storySelectedCount';
  static const storyVisibleFor = 'storyVisibleFor';
  static const storyWhoCanView = 'storyWhoCanView';
  static const storyUnsupported = 'storyUnsupported';
  static const tabChannels = 'tabChannels';
  static const tabContacts = 'tabContacts';
  static const tabFriendMoments = 'tabFriendMoments';
  static const tabMessages = 'tabMessages';
  static const tabMoments = 'tabMoments';
  static const tabSelectChannelContent = 'tabSelectChannelContent';
  static const tabSelectContact = 'tabSelectContact';
  static const tdMessageAutoDeleteTimerChanged =
      'tdMessageAutoDeleteTimerChanged';
  static const tdMessageAutoDeleteTimerDisabled =
      'tdMessageAutoDeleteTimerDisabled';
  static const tdMessageBoostedGroup = 'tdMessageBoostedGroup';
  static const tdMessageChecklist = 'tdMessageChecklist';
  static const tdMessageContactCard = 'tdMessageContactCard';
  static const tdMessageDaysDuration = 'tdMessageDaysDuration';
  static const tdMessageDice = 'tdMessageDice';
  static const tdMessageExpiredPhoto = 'tdMessageExpiredPhoto';
  static const tdMessageExpiredVideo = 'tdMessageExpiredVideo';
  static const tdMessageFileWithName = 'tdMessageFileWithName';
  static const tdMessageForwardedStory = 'tdMessageForwardedStory';
  static const tdMessageGame = 'tdMessageGame';
  static const tdMessageGift = 'tdMessageGift';
  static const tdMessageGiveaway = 'tdMessageGiveaway';
  static const tdMessageGroupCreated = 'tdMessageGroupCreated';
  static const tdMessageGroupNameChanged = 'tdMessageGroupNameChanged';
  static const tdMessageGroupPhotoDeleted = 'tdMessageGroupPhotoDeleted';
  static const tdMessageGroupPhotoUpdated = 'tdMessageGroupPhotoUpdated';
  static const tdMessageGroupVideoChatEnded = 'tdMessageGroupVideoChatEnded';
  static const tdMessageGroupVideoChatStarted =
      'tdMessageGroupVideoChatStarted';
  static const tdMessageHoursDuration = 'tdMessageHoursDuration';
  static const tdMessageJoinedGroupByLink = 'tdMessageJoinedGroupByLink';
  static const tdMessageLastSeenMonthDay = 'tdMessageLastSeenMonthDay';
  static const tdMessageLastSeenTodayTime = 'tdMessageLastSeenTodayTime';
  static const tdMessageLastSeenUnknown = 'tdMessageLastSeenUnknown';
  static const tdMessageLastSeenYearMonthDay = 'tdMessageLastSeenYearMonthDay';
  static const tdMessageLastSeenYesterdayTime =
      'tdMessageLastSeenYesterdayTime';
  static const tdMessageMemberLeftGroup = 'tdMessageMemberLeftGroup';
  static const tdMessageMessagePinned = 'tdMessageMessagePinned';
  static const tdMessageMinutesDuration = 'tdMessageMinutesDuration';
  static const tdMessageMusic = 'tdMessageMusic';
  static const tdMessageNewMemberJoinedGroup = 'tdMessageNewMemberJoinedGroup';
  static const tdMessageNoAudio = 'tdMessageNoAudio';
  static const tdMessageNoFiles = 'tdMessageNoFiles';
  static const tdMessageNoLinks = 'tdMessageNoLinks';
  static const tdMessageNoMembers = 'tdMessageNoMembers';
  static const tdMessageNoPhotoVideo = 'tdMessageNoPhotoVideo';
  static const tdMessageNoStickers = 'tdMessageNoStickers';
  static const tdMessageNoVoice = 'tdMessageNoVoice';
  static const tdMessagePaidContent = 'tdMessagePaidContent';
  static const tdMessagePaidMessagePriceChanged =
      'tdMessagePaidMessagePriceChanged';
  static const tdMessagePaidMessagesDisabled = 'tdMessagePaidMessagesDisabled';
  static const tdMessagePaidMessageSettingsChanged =
      'tdMessagePaidMessageSettingsChanged';
  static const tdMessagePhotoVideo = 'tdMessagePhotoVideo';
  static const tdMessagePoll = 'tdMessagePoll';
  static const tdMessageProduct = 'tdMessageProduct';
  static const tdMessageSecondsDuration = 'tdMessageSecondsDuration';
  static const tdMessageSticker = 'tdMessageSticker';
  static const tdMessageStickerPreview = 'tdMessageStickerPreview';
  static const tdMessageStickerWithEmoji = 'tdMessageStickerWithEmoji';
  static const tdMessageSubmission = 'tdMessageSubmission';
  static const tdMessageSystemMessage = 'tdMessageSystemMessage';
  static const tdMessageUnsupportedCurrentVersion =
      'tdMessageUnsupportedCurrentVersion';
  static const tdMessageUserJoinedTelegram = 'tdMessageUserJoinedTelegram';
  static const tdMessageVideoCall = 'tdMessageVideoCall';
  static const tdMessageVideoMessage = 'tdMessageVideoMessage';
  static const tdMessageVoiceCall = 'tdMessageVoiceCall';
  static const themeApplePingFangFamily = 'themeApplePingFangFamily';
  static const themeClassicName = 'themeClassicName';
  static const themeDarkName = 'themeDarkName';
  static const themeDayName = 'themeDayName';
  static const themeEnablePromptAction = 'themeEnablePromptAction';
  static const themeEnablePromptMessage = 'themeEnablePromptMessage';
  static const themeEnablePromptTitle = 'themeEnablePromptTitle';
  static const themeGroupAssistantSecondPageFirst =
      'themeGroupAssistantSecondPageFirst';
  static const themeGroupAssistantSortByTime = 'themeGroupAssistantSortByTime';
  static const themeGroupAssistantTopCollapsed =
      'themeGroupAssistantTopCollapsed';
  static const themeModeDark = 'themeModeDark';
  static const themeModeLight = 'themeModeLight';
  static const themeNightName = 'themeNightName';
  static const themePingFangHongKong = 'themePingFangHongKong';
  static const themePingFangSimplifiedChinese =
      'themePingFangSimplifiedChinese';
  static const themePingFangTraditionalChinese =
      'themePingFangTraditionalChinese';
  static const themeSystemMonospace = 'themeSystemMonospace';
  static const themeUnreadChatCount = 'themeUnreadChatCount';
  static const themeUnreadCountCapAt99 = 'themeUnreadCountCapAt99';
  static const themeUnreadCountShowActual = 'themeUnreadCountShowActual';
  static const themeUnreadMessageCount = 'themeUnreadMessageCount';
  static const topicChatAllFilter = 'topicChatAllFilter';
  static const topicChatAllTopics = 'topicChatAllTopics';
  static const topicChatAwaitingYourPost = 'topicChatAwaitingYourPost';
  static const topicChatBeKindPrompt = 'topicChatBeKindPrompt';
  static const topicChatBrowseCount = 'topicChatBrowseCount';
  static const topicChatChannelMembers = 'topicChatChannelMembers';
  static const topicChatChannelMessages = 'topicChatChannelMessages';
  static const topicChatChannelNumber = 'topicChatChannelNumber';
  static const topicChatChannelSettings = 'topicChatChannelSettings';
  static const topicChatCommentCount = 'topicChatCommentCount';
  static const topicChatComposerPlaceholder = 'topicChatComposerPlaceholder';
  static const topicChatExpand = 'topicChatExpand';
  static const topicChatGroupChatTitle = 'topicChatGroupChatTitle';
  static const topicChatInvite = 'topicChatInvite';
  static const topicChatLeave = 'topicChatLeave';
  static const topicChatLeaveChannel = 'topicChatLeaveChannel';
  static const topicChatLeaveChannelConfirm = 'topicChatLeaveChannelConfirm';
  static const topicChatLeaveChannelFailed = 'topicChatLeaveChannelFailed';
  static const topicChatLikeCommentSummary = 'topicChatLikeCommentSummary';
  static const topicChatLoading = 'topicChatLoading';
  static const topicChatMemberCount = 'topicChatMemberCount';
  static const topicChatMostRelevant = 'topicChatMostRelevant';
  static const topicChatMuteFailed = 'topicChatMuteFailed';
  static const topicChatMuteMessagesToggle = 'topicChatMuteMessagesToggle';
  static const topicChatMyProfile = 'topicChatMyProfile';
  static const topicChatNoMoreContent = 'topicChatNoMoreContent';
  static const topicChatPinnedPrefix = 'topicChatPinnedPrefix';
  static const topicChatPinToggle = 'topicChatPinToggle';
  static const topicChatPublish = 'topicChatPublish';
  static const topicChatReplyCount = 'topicChatReplyCount';
  static const topicChatSearch = 'topicChatSearch';
  static const topicChatSelectSection = 'topicChatSelectSection';
  static const topicChatSelectTime = 'topicChatSelectTime';
  static const topicChatSetPinnedFailed = 'topicChatSetPinnedFailed';
  static const topicChatShare = 'topicChatShare';
  static const topicChatTopicCount = 'topicChatTopicCount';
  static const topicChatTopicTitle = 'topicChatTopicTitle';
  static const topicChatUsers = 'topicChatUsers';
  static const topicPostContentActionFailed = 'topicPostContentActionFailed';
  static const topicPostContentCopied = 'topicPostContentCopied';
  static const topicPostContentCopiedQuery = 'topicPostContentCopiedQuery';
  static const topicPostContentFile = 'topicPostContentFile';
  static const transferBoostChunkSize = 'transferBoostChunkSize';
  static const transferBoostDescription = 'transferBoostDescription';
  static const transferBoostDisabled = 'transferBoostDisabled';
  static const transferBoostDownload = 'transferBoostDownload';
  static const transferBoostDownloadSection = 'transferBoostDownloadSection';
  static const transferBoostEnabled = 'transferBoostEnabled';
  static const transferBoostMaximum = 'transferBoostMaximum';
  static const transferBoostMedium = 'transferBoostMedium';
  static const transferBoostParallelism = 'transferBoostParallelism';
  static const transferBoostRestartRequired = 'transferBoostRestartRequired';
  static const transferBoostTitle = 'transferBoostTitle';
  static const transferBoostUpload = 'transferBoostUpload';
  static const transferBoostUploadSection = 'transferBoostUploadSection';
  static const translationInternalNoExternalApi =
      'translationInternalNoExternalApi';
  static const translationLibreTranslateNoResult =
      'translationLibreTranslateNoResult';
  static const translationLibreTranslateUrlRequired =
      'translationLibreTranslateUrlRequired';
  static const translationLingvaNoResult = 'translationLingvaNoResult';
  static const translationMlKitLocal = 'translationMlKitLocal';
  static const translationMyMemoryNoResult = 'translationMyMemoryNoResult';
  static const translationNativeCancelledOrTimedOut =
      'translationNativeCancelledOrTimedOut';
  static const translationNativeNoExternalApi =
      'translationNativeNoExternalApi';
  static const translationNativeNoResult = 'translationNativeNoResult';
  static const translationServiceInvalidResponse =
      'translationServiceInvalidResponse';
  static const translationServiceReturnedStatus =
      'translationServiceReturnedStatus';
  static const translationServiceUrlInvalid = 'translationServiceUrlInvalid';
  static const translationSettingsService = 'translationSettingsService';
  static const translationSettingsTargetLanguage =
      'translationSettingsTargetLanguage';
  static const translationSettingsTitle = 'translationSettingsTitle';
  static const translationSystem = 'translationSystem';
  static const translationTelegram = 'translationTelegram';
  static const updateAction = 'updateAction';
  static const updateLater = 'updateLater';
  static const updateNewVersionFound = 'updateNewVersionFound';
  static const updateVersionPrompt = 'updateVersionPrompt';
  static const videoPlaybackFinishedAsk = 'videoPlaybackFinishedAsk';
  static const videoPlaybackFinishedAutoplayNext =
      'videoPlaybackFinishedAutoplayNext';
  static const videoPlaybackFinishedReplay = 'videoPlaybackFinishedReplay';
  static const videoPlaybackFinishedReturnToChat =
      'videoPlaybackFinishedReturnToChat';
  static const videoPlaybackHorizontalSwipe = 'videoPlaybackHorizontalSwipe';
  static const videoPlaybackSettingsTitle = 'videoPlaybackSettingsTitle';
  static const videoPlaybackSwipeAdjustProgress =
      'videoPlaybackSwipeAdjustProgress';
  static const videoPlaybackSwipeChangeVideo = 'videoPlaybackSwipeChangeVideo';
  static const videoPlaybackSwipeDisabled = 'videoPlaybackSwipeDisabled';
  static const videoPlaybackSwipeSkipTenSeconds =
      'videoPlaybackSwipeSkipTenSeconds';
  static const videoPlaybackWhenFinished = 'videoPlaybackWhenFinished';
  static const videoPlayerCachedLocally = 'videoPlayerCachedLocally';
  static const videoPlayerCannotPlay = 'videoPlayerCannotPlay';
  static const videoPlayerFinished = 'videoPlayerFinished';
  static const videoPlayerForwardUnsupported = 'videoPlayerForwardUnsupported';
  static const videoPlayerFullscreen = 'videoPlayerFullscreen';
  static const videoPlayerLoadFailed = 'videoPlayerLoadFailed';
  static const videoPlayerLoading = 'videoPlayerLoading';
  static const videoPlayerNextVideo = 'videoPlayerNextVideo';
  static const videoPlayerNoNextVideo = 'videoPlayerNoNextVideo';
  static const videoPlayerNoPreviousVideo = 'videoPlayerNoPreviousVideo';
  static const videoPlayerPictureInPicture = 'videoPlayerPictureInPicture';
  static const videoPlayerPictureInPictureFailed =
      'videoPlayerPictureInPictureFailed';
  static const videoPlayerPlaybackSpeed = 'videoPlayerPlaybackSpeed';
  static const videoPlayerPlayNext = 'videoPlayerPlayNext';
  static const videoPlayerPreviousVideo = 'videoPlayerPreviousVideo';
  static const videoPlayerReplay = 'videoPlayerReplay';
  static const videoPlayerReturnToChat = 'videoPlayerReturnToChat';
  static const videoPlayerSplitScreen = 'videoPlayerSplitScreen';
  static const videoPlayerStreamingWhileDownloading =
      'videoPlayerStreamingWhileDownloading';
  static const videoPlayerSwipeFurther = 'videoPlayerSwipeFurther';
  static const videoPlayerToggleDisplayMode = 'videoPlayerToggleDisplayMode';
  static const videoPlayerUpNext = 'videoPlayerUpNext';
  static const videoPlayerWaitingForFile = 'videoPlayerWaitingForFile';
  static const vipBadgeLabel = 'vipBadgeLabel';
  static const blockingBlocklist = 'blockingBlocklist';
  static const blockingCountry = 'blockingCountry';
  static const blockingCountryDescription = 'blockingCountryDescription';
  static const blockingCountryOff = 'blockingCountryOff';
  static const blockingCountrySearch = 'blockingCountrySearch';
  static const blockingCountrySelected = 'blockingCountrySelected';
  static const blockingExemptCommonPrivateGroup =
      'blockingExemptCommonPrivateGroup';
  static const blockingExemptNonDefaultAvatar =
      'blockingExemptNonDefaultAvatar';
  static const blockingExemptPlainText = 'blockingExemptPlainText';
  static const blockingExemptThreeCommonGroups =
      'blockingExemptThreeCommonGroups';
  static const blockingExemptions = 'blockingExemptions';
  static const blockingTitle = 'blockingTitle';
  static const messagePollVotes = 'messagePollVotes';
  static const messagePollClosed = 'messagePollClosed';
  static const messagePollStop = 'messagePollStop';
  static const messagePollStopConfirm = 'messagePollStopConfirm';
  static const messageChecklistProgress = 'messageChecklistProgress';
  static const messageChecklistAdd = 'messageChecklistAdd';
  static const messageChecklistNewTask = 'messageChecklistNewTask';
  static const messageChecklistTaskHint = 'messageChecklistTaskHint';
  static const messageStoryShared = 'messageStoryShared';
  static const messageStoryMention = 'messageStoryMention';
  static const messageStoryOpen = 'messageStoryOpen';
  static const sharedContactViewProfile = 'sharedContactViewProfile';
  static const sharedContactMessage = 'sharedContactMessage';
  static const sharedContactCall = 'sharedContactCall';
  static const sharedContactCopyNumber = 'sharedContactCopyNumber';
  static const sharedContactAdd = 'sharedContactAdd';
  static const sharedContactAdded = 'sharedContactAdded';
  static const sharedContactAddFailed = 'sharedContactAddFailed';
  static const composerVenue = 'composerVenue';
  static const composerVenueName = 'composerVenueName';
  static const composerVenueAddress = 'composerVenueAddress';
  static const composerContact = 'composerContact';
  static const contactShareTitle = 'contactShareTitle';
  static const contactShareSearch = 'contactShareSearch';
  static const contactShareEmpty = 'contactShareEmpty';
  static const composerMediaSearch = 'composerMediaSearch';
  static const composerMediaSearchEmpty = 'composerMediaSearchEmpty';
  static const storyReplyHint = 'storyReplyHint';
  static const storyReplySent = 'storyReplySent';
  static const storyShare = 'storyShare';
  static const storyShared = 'storyShared';
  static const storyReport = 'storyReport';
  static const storyReported = 'storyReported';
  static const storyReportDetails = 'storyReportDetails';
  static const storyActionFailed = 'storyActionFailed';
  static const channelDirectMessages = 'channelDirectMessages';
  static const channelDirectMessagesEmpty = 'channelDirectMessagesEmpty';
  static const channelDirectMessagesReload = 'channelDirectMessagesReload';
  static const channelDirectMessagesUnknownSender =
      'channelDirectMessagesUnknownSender';
  static const channelDirectMessagesDraft = 'channelDirectMessagesDraft';
  static const channelDirectMessagesNoMessages =
      'channelDirectMessagesNoMessages';
  static const channelDirectMessagesLoadMore = 'channelDirectMessagesLoadMore';
  static const channelDirectMessagesStartConversation =
      'channelDirectMessagesStartConversation';
  static const channelDirectMessagesReplyHint =
      'channelDirectMessagesReplyHint';
  static const channelDirectMessagesReplying = 'channelDirectMessagesReplying';
  static const channelDirectMessagesOlder = 'channelDirectMessagesOlder';
  static const channelDirectMessagesRevenueLoading =
      'channelDirectMessagesRevenueLoading';
  static const channelDirectMessagesRevenue = 'channelDirectMessagesRevenue';
  static const channelDirectMessagesRequirePayment =
      'channelDirectMessagesRequirePayment';
  static const channelDirectMessagesAllowFree =
      'channelDirectMessagesAllowFree';
  static const channelDirectMessagesMarkRead = 'channelDirectMessagesMarkRead';
  static const channelDirectMessagesMarkUnread =
      'channelDirectMessagesMarkUnread';
  static const channelDirectMessagesReadReactions =
      'channelDirectMessagesReadReactions';
  static const channelDirectMessagesUnpinAll = 'channelDirectMessagesUnpinAll';
  static const channelDirectMessagesClear = 'channelDirectMessagesClear';
  static const channelDirectMessagesClearRange =
      'channelDirectMessagesClearRange';
  static const channelDirectMessagesRangeStart =
      'channelDirectMessagesRangeStart';
  static const channelDirectMessagesRangeEnd = 'channelDirectMessagesRangeEnd';
  static const channelDirectMessagesClearRangeConfirm =
      'channelDirectMessagesClearRangeConfirm';
  static const channelDirectMessagesRefundTitle =
      'channelDirectMessagesRefundTitle';
  static const channelDirectMessagesRefundMessage =
      'channelDirectMessagesRefundMessage';
  static const channelDirectMessagesAllowAndRefund =
      'channelDirectMessagesAllowAndRefund';
  static const channelDirectMessagesAllowOnly =
      'channelDirectMessagesAllowOnly';
  static const channelDirectMessagesClearConfirm =
      'channelDirectMessagesClearConfirm';
  static const suggestedPostPending = 'suggestedPostPending';
  static const suggestedPostApproved = 'suggestedPostApproved';
  static const suggestedPostApprovalFailed = 'suggestedPostApprovalFailed';
  static const suggestedPostDeclined = 'suggestedPostDeclined';
  static const suggestedPostPaid = 'suggestedPostPaid';
  static const suggestedPostRefunded = 'suggestedPostRefunded';
  static const suggestedPostRefundDeleted = 'suggestedPostRefundDeleted';
  static const suggestedPostRefundPayment = 'suggestedPostRefundPayment';
  static const suggestedPostOffer = 'suggestedPostOffer';
  static const suggestedPostOfferUnavailable = 'suggestedPostOfferUnavailable';
  static const suggestedPostApprove = 'suggestedPostApprove';
  static const suggestedPostDecline = 'suggestedPostDecline';
  static const suggestedPostEditOffer = 'suggestedPostEditOffer';
  static const suggestedPostSuggestChanges = 'suggestedPostSuggestChanges';
  static const suggestedPostEditText = 'suggestedPostEditText';
  static const suggestedPostDeclineTitle = 'suggestedPostDeclineTitle';
  static const suggestedPostDeclineComment = 'suggestedPostDeclineComment';
  static const suggestedPostComposerTitle = 'suggestedPostComposerTitle';
  static const suggestedPostTextHint = 'suggestedPostTextHint';
  static const suggestedPostAddMedia = 'suggestedPostAddMedia';
  static const suggestedPostPrice = 'suggestedPostPrice';
  static const suggestedPostFree = 'suggestedPostFree';
  static const suggestedPostStars = 'suggestedPostStars';
  static const suggestedPostTon = 'suggestedPostTon';
  static const suggestedPostStarAmount = 'suggestedPostStarAmount';
  static const suggestedPostTonAmount = 'suggestedPostTonAmount';
  static const suggestedPostAnyTime = 'suggestedPostAnyTime';
  static const suggestedPostSubmitOffer = 'suggestedPostSubmitOffer';
  static const suggestedPostSubmit = 'suggestedPostSubmit';
  static const suggestedPostTextRequired = 'suggestedPostTextRequired';
  static const suggestedPostInvalidAmount = 'suggestedPostInvalidAmount';
  static const suggestedPostAmountRange = 'suggestedPostAmountRange';
  static const suggestedPostScheduleRange = 'suggestedPostScheduleRange';
}

typedef TelegramStringResolver =
    String? Function(String key, Map<String, Object?> placeholders);

abstract final class AppStrings {
  // t() runs for every localized string render; re-parsing the Intl tag each
  // call is measurable in list scrolling, so the resolved locale key is cached
  // until the tag changes.
  static String? _cachedTag;
  static String _cachedLocaleKey = 'en';
  static TelegramStringResolver? telegramStringResolver;

  static String t(String key, [Map<String, Object?> placeholders = const {}]) {
    return tForLocaleWithTelegram(_currentLocaleKey, key, placeholders);
  }

  static String tLocal(
    String key, [
    Map<String, Object?> placeholders = const {},
  ]) {
    return tForLocale(_currentLocaleKey, key, placeholders);
  }

  static String get _currentLocaleKey {
    final tag = Intl.getCurrentLocale();
    if (tag != _cachedTag) {
      final locale =
          AppLocalizations.localeFromTag(tag) ??
          AppLocalizations.fallbackLocale;
      _cachedLocaleKey = AppLocalizations.localeKeyFor(
        AppLocalizations.resolve(locale),
      );
      _cachedTag = tag;
    }
    return _cachedLocaleKey;
  }

  static String tForLocaleWithTelegram(
    String localeKey,
    String key, [
    Map<String, Object?> placeholders = const {},
  ]) {
    final telegram = telegramStringResolver?.call(key, placeholders);
    if (telegram != null && telegram.trim().isNotEmpty) {
      final result = _interpolatePlaceholders(telegram, placeholders);
      if (!_hasUnresolvedPlaceholder(result)) return result;
    }
    return tForLocale(localeKey, key, placeholders);
  }

  static String tForLocale(
    String localeKey,
    String key, [
    Map<String, Object?> placeholders = const {},
  ]) {
    // Message keys and country keys are disjoint (the checker forbids
    // country* message keys), so the common message-table hit short-circuits
    // before the country lookup.
    final localeMessages = _messages[localeKey] ?? _messages['en'];
    final value =
        localeMessages?[key] ??
        countryNameForLocale(localeKey, key) ??
        _messages['en']?[key] ??
        key;
    if (placeholders.isEmpty) return value;
    return _interpolatePlaceholders(value, placeholders);
  }

  static String _interpolatePlaceholders(
    String value,
    Map<String, Object?> placeholders,
  ) {
    if (placeholders.isEmpty) return value;
    // Normalise fullwidth ％／＄ used in some CJK Telegram language
    // packs so the replacement patterns below can match.
    var result = value.replaceAll('％', '%').replaceAll('＄', '\$');
    placeholders.forEach((placeholder, replacement) {
      final replacementText = '$replacement';
      result = result.replaceAll('{$placeholder}', replacementText);
      final indexMatch = RegExp(r'^value(\d+)$').firstMatch(placeholder);
      if (indexMatch != null) {
        final index = indexMatch.group(1)!;
        result = result
            .replaceAll('%$index\$@', replacementText)
            .replaceAll('%$index\$s', replacementText)
            .replaceAll('%$index\$d', replacementText);
      }
    });
    return result;
  }

  static final _unresolvedPlaceholderPattern = RegExp(
    r'\{value\d+\}|[%％]\d+[\$＄][@sd]|[%％][sd@]',
  );

  static bool _hasUnresolvedPlaceholder(String value) =>
      _unresolvedPlaceholderPattern.hasMatch(value);
}

const _messages = <String, Map<String, String>>{
  'zhHans': zhHansMessages,
  'zhHant': zhHantMessages,
  'ja': jaMessages,
  'ko': koMessages,
  'en': enMessages,
  'fr': frMessages,
  'es': esMessages,
  'de': deMessages,
};

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.isSupportedLocale(locale);

  @override
  Future<AppLocalizations> load(Locale locale) {
    final resolved = AppLocalizations.resolve(locale);
    Intl.defaultLocale = resolved.toLanguageTag();
    return SynchronousFuture(AppLocalizations(resolved));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) =>
      false;
}
