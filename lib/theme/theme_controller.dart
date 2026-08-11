//
//  theme_controller.dart
//
//  Drives the app-wide appearance (跟随系统 / 浅色 / 深色), text scale, and chat
//  appearance preferences. Values are persisted in SharedPreferences and
//  applied through providers at the app root.
//

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/preview_texts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/quick_reaction_choice.dart';
import '../components/app_icons.dart';
import '../platform/adaptive_platform.dart';
import 'app_theme.dart';
import 'custom_message_bubble_background.dart';
import 'emoji_font_catalog.dart';
import 'message_bubble_background.dart';
import 'system_font_catalog.dart';
import 'telegram_cloud_theme.dart';

enum AppearanceMode {
  system(AppStringKeys.appLocaleFollowSystem, HeroAppIcons.circleHalfStroke),
  light(AppStringKeys.themeModeLight, HeroAppIcons.solidSun),
  dark(AppStringKeys.themeModeDark, HeroAppIcons.solidMoon);

  const AppearanceMode(this.label, this._icon);
  final String label;
  final AppIconData _icon;

  IconData get icon => _icon.data;

  ThemeMode get themeMode => switch (this) {
    AppearanceMode.system => ThemeMode.system,
    AppearanceMode.light => ThemeMode.light,
    AppearanceMode.dark => ThemeMode.dark,
  };
}

enum UnreadBadgeMode {
  messages(AppStringKeys.themeUnreadMessageCount, HeroAppIcons.solidMessage),
  chats(AppStringKeys.themeUnreadChatCount, HeroAppIcons.comments);

  const UnreadBadgeMode(this.label, this._icon);
  final String label;
  final AppIconData _icon;

  IconData get icon => _icon.data;
}

enum UnreadBadgeOverflowMode {
  capped(AppStringKeys.themeUnreadCountCapAt99, HeroAppIcons.solidBell),
  exact(AppStringKeys.themeUnreadCountShowActual, HeroAppIcons.thumbtack);

  const UnreadBadgeOverflowMode(this.label, this._icon);
  final String label;
  final AppIconData _icon;

  IconData get icon => _icon.data;

  String format(int count) => switch (this) {
    UnreadBadgeOverflowMode.capped => count > 99 ? '99+' : '$count',
    UnreadBadgeOverflowMode.exact => '$count',
  };
}

enum ArchivedChatsDisplayMode {
  pullDown(
    AppStringKeys.appearanceArchivedChatsPullDown,
    HeroAppIcons.arrowDown,
  ),
  firstPosition(
    AppStringKeys.themeGroupAssistantTopCollapsed,
    HeroAppIcons.arrowUp,
  ),
  nextPage(
    AppStringKeys.themeGroupAssistantSecondPageFirst,
    HeroAppIcons.arrowDown,
  ),
  hidden(AppStringKeys.appearanceArchivedChatsHidden, HeroAppIcons.eyeSlash);

  const ArchivedChatsDisplayMode(this.label, this._icon);
  final String label;
  final AppIconData _icon;

  IconData get icon => _icon.data;

  bool get isInline =>
      this == ArchivedChatsDisplayMode.firstPosition ||
      this == ArchivedChatsDisplayMode.nextPage;

  ArchivedChatsDisplayMode effectiveForPlatform({
    TargetPlatform? platform,
    bool isWeb = kIsWeb,
  }) {
    if (!isWeb &&
        isDesktopTargetPlatform(platform) &&
        this == ArchivedChatsDisplayMode.pullDown) {
      return ArchivedChatsDisplayMode.firstPosition;
    }
    return this;
  }

  int insertionIndex({required int chatCount, required int visibleRows}) {
    return switch (this) {
      ArchivedChatsDisplayMode.firstPosition => 0,
      ArchivedChatsDisplayMode.nextPage =>
        chatCount < visibleRows ? chatCount : visibleRows,
      _ => -1,
    };
  }
}

enum ChatFolderDisplayMode {
  hidden(AppStringKeys.appearanceChatFoldersHidden, HeroAppIcons.eyeSlash),
  menu(AppStringKeys.appearanceChatFoldersMenu, HeroAppIcons.folder),
  tabs(AppStringKeys.appearanceChatFoldersTabs, HeroAppIcons.tableColumns);

  const ChatFolderDisplayMode(this.label, this._icon);
  final String label;
  final AppIconData _icon;

  IconData get icon => _icon.data;
}

enum ChatListSwipeMode {
  chatActions(
    AppStringKeys.gesturesChatActions,
    AppStringKeys.gesturesChatActionsModeDescription,
    HeroAppIcons.message,
  ),
  switchFolders(
    AppStringKeys.gesturesSwitchFolders,
    AppStringKeys.gesturesSwitchFoldersModeDescription,
    HeroAppIcons.folder,
  );

  const ChatListSwipeMode(this.label, this.description, this.icon);

  final String label;
  final String description;
  final AppIconData icon;
}

enum MobileMessageActionMenuStyle {
  grid(AppStringKeys.appearanceMessageActionMenuGrid, HeroAppIcons.grip),
  dropdown(
    AppStringKeys.appearanceMessageActionMenuDropdown,
    HeroAppIcons.listCheck,
  );

  const MobileMessageActionMenuStyle(this.label, this.icon);

  final String label;
  final AppIconData icon;
}

enum NameColorAudience {
  premium(AppStringKeys.appearanceNameColorPremium, HeroAppIcons.star),
  allUsers(AppStringKeys.appearanceNameColorAllUsers, HeroAppIcons.users),
  nobody(AppStringKeys.appearanceNameColorNobody, HeroAppIcons.eyeSlash);

  const NameColorAudience(this.label, this._icon);

  final String label;
  final AppIconData _icon;

  IconData get icon => _icon.data;

  bool shows({required bool isPremium}) => switch (this) {
    NameColorAudience.premium => isPremium,
    NameColorAudience.allUsers => true,
    NameColorAudience.nobody => false,
  };
}

enum StatusEmojiDisplayMode {
  animated(AppStringKeys.appearanceStatusAnimated, HeroAppIcons.play),
  static(AppStringKeys.appearanceStatusStatic, HeroAppIcons.image),
  none(AppStringKeys.appearanceStatusNone, HeroAppIcons.eyeSlash);

  const StatusEmojiDisplayMode(this.label, this._icon);

  final String label;
  final AppIconData _icon;

  IconData get icon => _icon.data;
  bool get visible => this != StatusEmojiDisplayMode.none;
  bool get animate => this == StatusEmojiDisplayMode.animated;
}

/// How a sender's name is kept legible over a wallpaper.
///
/// [blend] pulls the sender colour halfway to the bubble's text colour, which
/// holds contrast without the halo a shadow leaves around the glyphs.
enum SenderNameReadabilityMode { background, blend, none }

enum AppFontChoice {
  system(
    AppStringKeys.emojiFontCatalogSystemDefault,
    appFontPreviewText,
    cjk: true,
  ),
  apple(AppStringKeys.themeApplePingFangFamily, appFontPreviewText, cjk: true),
  pingFang(
    AppStringKeys.themePingFangSimplifiedChinese,
    appFontPreviewText,
    cjk: true,
  ),
  pingFangHk(
    AppStringKeys.themePingFangHongKong,
    appFontPreviewText,
    cjk: true,
  ),
  pingFangTw(
    AppStringKeys.themePingFangTraditionalChinese,
    appFontPreviewText,
    cjk: true,
  ),
  hiraginoSansJp('Hiragino [JP]', appFontPreviewText, cjk: true),
  customCjk('Custom Font', appFontPreviewText, cjk: true),
  helvetica('Helvetica Neue', appFontPreviewText),
  avenirNext('Avenir Next', appFontPreviewText),
  avenir('Avenir', appFontPreviewText),
  futura('Futura', appFontPreviewText),
  optima('Optima', appFontPreviewText),
  palatino('Palatino', appFontPreviewText),
  georgia('Georgia', appFontPreviewText),
  timesNewRoman('Times New Roman', appFontPreviewText),
  verdana('Verdana', appFontPreviewText),
  trebuchetMs('Trebuchet MS', appFontPreviewText),
  gillSans('Gill Sans', appFontPreviewText),
  didot('Didot', appFontPreviewText),
  americanTypewriter('American Typewriter', appFontPreviewText),
  menlo('Menlo', appFontPreviewText),
  courierNew('Courier New', appFontPreviewText),
  custom('Custom Font', appFontPreviewText),
  noteworthy('Noteworthy', appFontPreviewText),
  markerFelt('Marker Felt', appFontPreviewText),
  roboto('Roboto', appFontPreviewText),
  notoSans('Noto Sans', appFontPreviewText),
  notoSansCjk('Noto Sans CJK [CN]', appFontPreviewText, cjk: true),
  googleInter('Inter', appFontPreviewText, googleFamily: 'Inter'),
  googleOpenSans('Open Sans', appFontPreviewText, googleFamily: 'Open Sans'),
  googleLato('Lato', appFontPreviewText, googleFamily: 'Lato'),
  googleMontserrat(
    'Montserrat',
    appFontPreviewText,
    googleFamily: 'Montserrat',
  ),
  googlePoppins('Poppins', appFontPreviewText, googleFamily: 'Poppins'),
  googleNunito('Nunito', appFontPreviewText, googleFamily: 'Nunito'),
  googleRaleway('Raleway', appFontPreviewText, googleFamily: 'Raleway'),
  googleSourceSans3(
    'Source Sans 3',
    appFontPreviewText,
    googleFamily: 'Source Sans 3',
  ),
  googleMerriweather(
    'Merriweather',
    appFontPreviewText,
    googleFamily: 'Merriweather',
  ),
  googlePlayfairDisplay(
    'Playfair Display',
    appFontPreviewText,
    googleFamily: 'Playfair Display',
  ),
  googleNotoSerif('Noto Serif', appFontPreviewText, googleFamily: 'Noto Serif'),
  googleKleeOne(
    'Klee One [JP]',
    appFontPreviewText,
    googleFamily: 'Klee One',
    cjk: true,
  ),
  googleDotGothic16(
    'DotGothic16 [JP]',
    appFontPreviewText,
    googleFamily: 'DotGothic16',
    cjk: true,
  ),
  googleStick(
    'Stick [JP]',
    appFontPreviewText,
    googleFamily: 'Stick',
    cjk: true,
  ),
  googleMPlus1p(
    'M PLUS 1p [JP]',
    appFontPreviewText,
    googleFamily: 'M PLUS 1p',
    cjk: true,
  ),
  lineSeedJp('LINE Seed JP [JP]', appFontPreviewText, cjk: true),
  googleChocolateClassicalSans(
    'Chocolate Classical Sans [TW]',
    appFontPreviewText,
    googleFamily: 'Chocolate Classical Sans',
    cjk: true,
  ),
  googleNotoSansSc(
    'Noto Sans SC [CN]',
    appFontPreviewText,
    googleFamily: 'Noto Sans SC',
    cjk: true,
  ),
  googleNotoSansHk(
    'Noto Sans HK [HK]',
    appFontPreviewText,
    googleFamily: 'Noto Sans HK',
    cjk: true,
  ),
  googleNotoSansTc(
    'Noto Sans TC [TW]',
    appFontPreviewText,
    googleFamily: 'Noto Sans TC',
    cjk: true,
  ),
  googleNotoSansJp(
    'Noto Sans JP [JP]',
    appFontPreviewText,
    googleFamily: 'Noto Sans JP',
    cjk: true,
  ),
  googleLxgwWenKaiTc(
    'LXGW WenKai TC [TW]',
    appFontPreviewText,
    googleFamily: 'LXGW WenKai TC',
    cjk: true,
  ),
  googleZcoolXiaoWei(
    'ZCOOL XiaoWei [CN]',
    appFontPreviewText,
    googleFamily: 'ZCOOL XiaoWei',
    cjk: true,
  );

  const AppFontChoice(
    this.label,
    this.previewText, {
    this.googleFamily,
    this.cjk = false,
  });

  final String label;
  final String previewText;
  final String? googleFamily;
  final bool cjk;

  static List<AppFontChoice> get primaryOptions => [
    ...AppFontChoice.values.where((font) => font.cjk && !font.isCustom),
    ...AppFontChoice.values.where((font) => !font.cjk),
  ];

  static List<AppFontChoice> get cjkOptions => AppFontChoice.values
      .where((font) => font.cjk && font != AppFontChoice.system)
      .toList(growable: false);

  bool get isGoogleFont => googleFamily != null;
  bool get isCjk => cjk;
  bool get isCustom =>
      this == AppFontChoice.custom || this == AppFontChoice.customCjk;

  String get fontFamily {
    return switch (this) {
      AppFontChoice.system => _platformFontFamily(),
      AppFontChoice.apple => '.AppleSystemUIFont',
      AppFontChoice.pingFang => 'PingFang SC',
      AppFontChoice.pingFangHk => 'PingFang HK',
      AppFontChoice.pingFangTw => 'PingFang TC',
      AppFontChoice.hiraginoSansJp => 'Hiragino Sans',
      AppFontChoice.customCjk => _platformFontFamily(),
      AppFontChoice.helvetica => 'Helvetica Neue',
      AppFontChoice.avenirNext => 'Avenir Next',
      AppFontChoice.avenir => 'Avenir',
      AppFontChoice.futura => 'Futura',
      AppFontChoice.optima => 'Optima',
      AppFontChoice.palatino => 'Palatino',
      AppFontChoice.georgia => 'Georgia',
      AppFontChoice.timesNewRoman => 'Times New Roman',
      AppFontChoice.verdana => 'Verdana',
      AppFontChoice.trebuchetMs => 'Trebuchet MS',
      AppFontChoice.gillSans => 'Gill Sans',
      AppFontChoice.didot => 'Didot',
      AppFontChoice.americanTypewriter => 'American Typewriter',
      AppFontChoice.menlo => 'Menlo',
      AppFontChoice.courierNew => 'Courier New',
      AppFontChoice.custom => _platformFontFamily(),
      AppFontChoice.noteworthy => 'Noteworthy',
      AppFontChoice.markerFelt => 'Marker Felt',
      AppFontChoice.roboto => 'Roboto',
      AppFontChoice.notoSans => 'Noto Sans',
      AppFontChoice.notoSansCjk => 'Noto Sans CJK SC',
      AppFontChoice.lineSeedJp => 'LINE Seed Sans JP',
      _ => googleFamily!.replaceAll(' ', ''),
    };
  }

  List<String> get fontFamilyFallback {
    return switch (this) {
      AppFontChoice.system => _platformFontFallback(),
      AppFontChoice.apple => const [
        'PingFang SC',
        'PingFang TC',
        'Hiragino Sans',
        'Helvetica Neue',
        'Arial',
      ],
      AppFontChoice.pingFang => const [
        'PingFang HK',
        'PingFang TC',
        'Hiragino Sans',
        'Helvetica Neue',
        'Arial',
      ],
      AppFontChoice.pingFangHk => const [
        'PingFang TC',
        'PingFang SC',
        'Hiragino Sans',
        'Helvetica Neue',
        'Arial',
      ],
      AppFontChoice.pingFangTw => const [
        'PingFang HK',
        'PingFang SC',
        'Hiragino Sans',
        'Helvetica Neue',
        'Arial',
      ],
      AppFontChoice.hiraginoSansJp => const [
        'Hiragino Sans GB',
        'PingFang SC',
        'PingFang TC',
        'Helvetica Neue',
        'Arial',
      ],
      AppFontChoice.customCjk => _platformFontFallback(),
      AppFontChoice.helvetica => const ['PingFang SC', 'PingFang TC', 'Arial'],
      AppFontChoice.avenirNext ||
      AppFontChoice.avenir ||
      AppFontChoice.futura ||
      AppFontChoice.optima ||
      AppFontChoice.palatino ||
      AppFontChoice.georgia ||
      AppFontChoice.timesNewRoman ||
      AppFontChoice.verdana ||
      AppFontChoice.trebuchetMs ||
      AppFontChoice.gillSans ||
      AppFontChoice.didot ||
      AppFontChoice.americanTypewriter ||
      AppFontChoice.menlo ||
      AppFontChoice.courierNew ||
      AppFontChoice.custom ||
      AppFontChoice.noteworthy ||
      AppFontChoice.markerFelt => const [
        'PingFang SC',
        'PingFang HK',
        'PingFang TC',
        'Hiragino Sans',
        'Arial',
      ],
      AppFontChoice.roboto => const [
        'Noto Sans CJK SC',
        'Noto Sans CJK TC',
        'Noto Sans',
        'sans-serif',
      ],
      AppFontChoice.notoSans => const [
        'Noto Sans CJK SC',
        'Noto Sans CJK TC',
        'Arial',
      ],
      AppFontChoice.notoSansCjk => const [
        'Noto Sans CJK TC',
        'Noto Sans',
        'Arial',
      ],
      AppFontChoice.lineSeedJp => const [
        'LINE Seed Sans JP',
        'LINE Seed JP',
        'Hiragino Sans',
        'PingFang SC',
        'PingFang TC',
        'Arial',
      ],
      AppFontChoice.googleNotoSansSc => const [
        'PingFang SC',
        'PingFang TC',
        'Hiragino Sans',
        'Arial',
      ],
      AppFontChoice.googleNotoSansHk => const [
        'PingFang HK',
        'PingFang TC',
        'PingFang SC',
        'Arial',
      ],
      AppFontChoice.googleNotoSansTc => const [
        'PingFang TC',
        'PingFang HK',
        'PingFang SC',
        'Arial',
      ],
      AppFontChoice.googleNotoSansJp => const [
        'Hiragino Sans',
        'PingFang SC',
        'Arial',
      ],
      AppFontChoice.googleLxgwWenKaiTc => const [
        'PingFang TC',
        'PingFang SC',
        'Hiragino Sans',
        'Arial',
      ],
      AppFontChoice.googleZcoolXiaoWei => const [
        'PingFang SC',
        'PingFang TC',
        'Arial',
      ],
      _ => const ['PingFang SC', 'PingFang TC', 'Hiragino Sans', 'Arial'],
    };
  }

  List<String> effectiveFallback(
    AppFontChoice cjkFallback, [
    TextStyle? base,
    String? customCjkFamily,
  ]) {
    if (isCjk) {
      final ownGoogleFallback = isGoogleFont
          ? _googleFamiliesForStyle(base)
          : const <String>[];
      return _dedupe([
        ...ownGoogleFallback,
        ...fontFamilyFallback,
        ..._platformFontFallback(),
      ]);
    }
    final customCjk = customCjkFamily?.trim();
    if (cjkFallback.isCustom) {
      return _dedupe([
        if (customCjk != null && customCjk.isNotEmpty) customCjk,
        if (customCjk == null || customCjk.isEmpty)
          ...AppFontChoice.pingFang.familiesForStyle(base),
        ..._platformFontFallback(),
      ]);
    }
    return _dedupe([
      ...cjkFallback.familiesForStyle(base),
      ..._platformFontFallback(),
    ]);
  }

  TextTheme applyTextTheme(
    TextTheme textTheme, {
    required AppFontChoice cjkFallback,
    String? customPrimaryFamily,
    String? customCjkFamily,
  }) {
    return textTheme.copyWith(
      displayLarge: _applyNullableStyle(
        textTheme.displayLarge,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      displayMedium: _applyNullableStyle(
        textTheme.displayMedium,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      displaySmall: _applyNullableStyle(
        textTheme.displaySmall,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      headlineLarge: _applyNullableStyle(
        textTheme.headlineLarge,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      headlineMedium: _applyNullableStyle(
        textTheme.headlineMedium,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      headlineSmall: _applyNullableStyle(
        textTheme.headlineSmall,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      titleLarge: _applyNullableStyle(
        textTheme.titleLarge,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      titleMedium: _applyNullableStyle(
        textTheme.titleMedium,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      titleSmall: _applyNullableStyle(
        textTheme.titleSmall,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      bodyLarge: _applyNullableStyle(
        textTheme.bodyLarge,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      bodyMedium: _applyNullableStyle(
        textTheme.bodyMedium,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      bodySmall: _applyNullableStyle(
        textTheme.bodySmall,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      labelLarge: _applyNullableStyle(
        textTheme.labelLarge,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      labelMedium: _applyNullableStyle(
        textTheme.labelMedium,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
      labelSmall: _applyNullableStyle(
        textTheme.labelSmall,
        cjkFallback,
        customPrimaryFamily,
        customCjkFamily,
      ),
    );
  }

  TextStyle previewStyle(TextStyle base) {
    return applyTextStyle(base, cjkFallback: this);
  }

  TextStyle applyTextStyle(
    TextStyle base, {
    required AppFontChoice cjkFallback,
    String? customPrimaryFamily,
    String? customCjkFamily,
  }) {
    final customPrimary = customPrimaryFamily?.trim();
    final withPrimary =
        isCustom && customPrimary != null && customPrimary.isNotEmpty
        ? base.copyWith(fontFamily: customPrimary)
        : isGoogleFont
        ? GoogleFonts.getFont(googleFamily!, textStyle: base)
        : base.copyWith(fontFamily: fontFamily);
    return withPrimary.copyWith(
      fontFamilyFallback: effectiveFallback(cjkFallback, base, customCjkFamily),
    );
  }

  TextStyle? _applyNullableStyle(
    TextStyle? style,
    AppFontChoice cjkFallback,
    String? customPrimaryFamily,
    String? customCjkFamily,
  ) {
    if (style == null) return null;
    return applyTextStyle(
      style,
      cjkFallback: cjkFallback,
      customPrimaryFamily: customPrimaryFamily,
      customCjkFamily: customCjkFamily,
    );
  }

  List<String> familiesForStyle(TextStyle? base) {
    if (isGoogleFont) {
      return _dedupe([..._googleFamiliesForStyle(base), ...fontFamilyFallback]);
    }
    return _dedupe([fontFamily, ...fontFamilyFallback]);
  }

  List<String> _googleFamiliesForStyle(TextStyle? base) {
    final family = googleFamily;
    if (family == null) return const <String>[];
    final style = GoogleFonts.getFont(
      family,
      textStyle: base ?? const TextStyle(),
    );
    return [
      if (style.fontFamily != null) style.fontFamily!,
      ...?style.fontFamilyFallback,
    ];
  }

  static List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (value.isNotEmpty && seen.add(value)) value,
    ];
  }

  static String _platformFontFamily() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => '.AppleSystemUIFont',
      TargetPlatform.android => 'Roboto',
      _ => 'system-ui',
    };
  }

  static List<String> _platformFontFallback() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        'PingFang SC',
        'PingFang TC',
        'Hiragino Sans',
        'Helvetica Neue',
        'Arial',
      ],
      TargetPlatform.android => const [
        'Noto Sans CJK SC',
        'Noto Sans CJK TC',
        'Noto Sans',
        'sans-serif',
      ],
      _ => const ['Noto Sans CJK SC', 'Noto Sans', 'Arial'],
    };
  }
}

List<String> dedupeFontFamilies(Iterable<String> values) {
  final seen = <String>{};
  return [
    for (final value in values)
      if (value.trim().isNotEmpty && seen.add(value.trim())) value.trim(),
  ];
}

const googleFontFamilyStoragePrefix = 'google:';

String encodeGoogleFontFamily(String family) =>
    '$googleFontFamilyStoragePrefix$family';

String? decodeGoogleFontFamily(String value) {
  final trimmed = value.trim();
  if (!trimmed.startsWith(googleFontFamilyStoragePrefix)) return null;
  final family = trimmed.substring(googleFontFamilyStoragePrefix.length).trim();
  return family.isEmpty ? null : family;
}

String displayStoredFontFamily(String value) =>
    decodeGoogleFontFamily(value) ?? value.trim();

enum AppMonospaceFontChoice {
  system(AppStringKeys.themeSystemMonospace, appMonospaceFontPreviewText),
  sfMono('SF Mono', appMonospaceFontPreviewText),
  menlo('Menlo', appMonospaceFontPreviewText),
  monaco('Monaco', appMonospaceFontPreviewText),
  courierNew('Courier New', appMonospaceFontPreviewText),
  googleRobotoMono(
    'Roboto Mono',
    appMonospaceFontPreviewText,
    googleFamily: 'Roboto Mono',
  ),
  googleSourceCodePro(
    'Source Code Pro',
    appMonospaceFontPreviewText,
    googleFamily: 'Source Code Pro',
  ),
  googleJetBrainsMono(
    'JetBrains Mono',
    appMonospaceFontPreviewText,
    googleFamily: 'JetBrains Mono',
  ),
  custom('Custom Font', appMonospaceFontPreviewText);

  const AppMonospaceFontChoice(
    this.label,
    this.previewText, {
    this.googleFamily,
  });

  final String label;
  final String previewText;
  final String? googleFamily;

  bool get isGoogleFont => googleFamily != null;
  bool get isCustom => this == AppMonospaceFontChoice.custom;

  String get fontFamily {
    return switch (this) {
      AppMonospaceFontChoice.system => _platformMonospaceFontFamily(),
      AppMonospaceFontChoice.sfMono => 'SF Mono',
      AppMonospaceFontChoice.menlo => 'Menlo',
      AppMonospaceFontChoice.monaco => 'Monaco',
      AppMonospaceFontChoice.courierNew => 'Courier New',
      AppMonospaceFontChoice.custom => _platformMonospaceFontFamily(),
      _ => googleFamily!.replaceAll(' ', ''),
    };
  }

  TextStyle applyTextStyle(TextStyle base, {String? customFamily}) {
    final custom = customFamily?.trim();
    final customGoogleFamily = custom == null
        ? null
        : decodeGoogleFontFamily(custom);
    final withFamily = isCustom && customGoogleFamily != null
        ? GoogleFonts.getFont(customGoogleFamily, textStyle: base)
        : isCustom && custom != null && custom.isNotEmpty
        ? base.copyWith(fontFamily: custom)
        : isGoogleFont
        ? GoogleFonts.getFont(googleFamily!, textStyle: base)
        : base.copyWith(fontFamily: fontFamily);
    final selectedCustomFamily = customGoogleFamily ?? custom;
    final primaryFamily = withFamily.fontFamily?.trim();
    return withFamily.copyWith(
      // ThemeController appends emoji and normal-text fallbacks after this
      // monospace-only portion of the chain.
      fontFamilyFallback: _dedupe([
        if (isCustom &&
            selectedCustomFamily != null &&
            selectedCustomFamily.isNotEmpty)
          selectedCustomFamily,
        fontFamily,
        ..._platformMonospaceFontFallback(),
      ]).where((family) => family != primaryFamily).toList(growable: false),
    );
  }

  static List<String> _dedupe(List<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (value.isNotEmpty && seen.add(value)) value,
    ];
  }

  static String _platformMonospaceFontFamily() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'Menlo',
      TargetPlatform.android => 'monospace',
      _ => 'monospace',
    };
  }

  static List<String> _platformMonospaceFontFallback() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        'SF Mono',
        'Menlo',
        'Monaco',
        'Courier New',
      ],
      TargetPlatform.android => const [
        'monospace',
        'Roboto Mono',
        'Noto Sans Mono',
      ],
      _ => const ['monospace', 'Courier New'],
    };
  }
}

enum MessageBubbleApplicationScope { ownMessages, allMessages }

class ThemeController extends ChangeNotifier {
  ThemeController(
    this._prefs, {
    int initialAccountSlot = 0,
    int? initialAccountUserId,
    EmojiFontCatalog? emojiFontCatalog,
  }) : _emojiFontCatalog = emojiFontCatalog ?? EmojiFontCatalog.shared,
       _activeAccountSlot = initialAccountSlot,
       _activeAccountUserId = initialAccountUserId {
    // Theming existed unconditionally before this preference was introduced,
    // so both new installs and migrated users retain the established behavior.
    _themingEnabled = _prefs.getBool(_themingEnabledKey) ?? true;
    _usePerAccountTheming = _prefs.getBool(_usePerAccountThemingKey) ?? false;
    final initialUserId = _activeAccountUserId;
    if (_usePerAccountTheming && initialUserId != null) {
      _migrateLegacyAccountTheme(_activeAccountSlot, initialUserId);
    }
    _mode = AppearanceMode.values.firstWhere(
      (m) => m.name == _prefs.getString(_scopedThemeKey(_modeKey)),
      orElse: () => AppearanceMode.system,
    );
    _brandColor = Color(
      _prefs.getInt(_scopedThemeKey(_brandKey)) ??
          (0xFF000000 | AppTheme.defaultBrand),
    );
    final legacyCloudTheme = _decodeTheme(_scopedThemeKey(_cloudThemeKey));
    _lightCloudTheme = _decodeTheme(_scopedThemeKey(_lightCloudThemeKey));
    _darkCloudTheme = _decodeTheme(_scopedThemeKey(_darkCloudThemeKey));
    if (legacyCloudTheme != null) {
      if (legacyCloudTheme.isDark) {
        _darkCloudTheme ??= legacyCloudTheme;
      } else {
        _lightCloudTheme ??= legacyCloudTheme;
      }
    }
    _installedCloudThemes = [];
    _loadInstalledCloudThemeCache(migrateLegacy: true);
    // Shared appearance selections may have been chosen by another Telegram
    // account. They remain valid shared selections, but must never be injected
    // into this account's installed-theme membership cache. Per-account
    // selections are already bound to the same stable identity and can repair
    // a cache from an older build that stored only the active selection.
    if (_usePerAccountTheming) {
      for (final theme in [
        legacyCloudTheme,
        _lightCloudTheme,
        _darkCloudTheme,
      ]) {
        if (theme != null) _addInstalledCloudTheme(theme);
      }
    }
    if (legacyCloudTheme != null) {
      _prefs.remove(_scopedThemeKey(_cloudThemeKey));
      _persistCloudThemes();
    }
    // Cloud themes now own the app palette whenever they are installed. Drop
    // the retired opt-out preference so an older `false` value cannot keep a
    // selected theme from applying to the interface.
    _prefs.remove(_scopedThemeKey(_legacyUseTelegramThemeForUiKey));
    _customMessageBubbleBackground = _decodeCustomMessageBubbleBackground(
      _scopedThemeKey(_customMessageBubbleBackgroundKey),
    );
    _messageBubblesEnabled =
        _prefs.getBool(_scopedThemeKey(_messageBubblesEnabledKey)) ?? true;
    _messageBubbleBackground = MessageBubbleBackground.fromStorage(
      _prefs.getString(_scopedThemeKey(_messageBubbleBackgroundKey)),
    );
    _messageBubbleApplicationScope = MessageBubbleApplicationScope.values
        .firstWhere(
          (scope) =>
              scope.name ==
              _prefs.getString(
                _scopedThemeKey(_messageBubbleApplicationScopeKey),
              ),
          orElse: () => MessageBubbleApplicationScope.allMessages,
        );
    _repairMissingCustomMessageBubble();
    if (hasCloudTheme &&
        (_prefs.containsKey(_preCloudThemeModeKey) ||
            _prefs.containsKey(_preCloudThemeBrandKey))) {
      // Older builds coupled theme installation to mode and brand changes.
      // Restore those independent choices while retaining the selected theme.
      _restoreUiBeforeCloudTheme();
    }
    _fontChoice = AppFontChoice.values.firstWhere(
      (m) => m.name == _prefs.getString(_fontChoiceKey),
      orElse: () => AppFontChoice.system,
    );
    _cjkFontChoice = AppFontChoice.cjkOptions.firstWhere(
      (m) => m.name == _prefs.getString(_cjkFontChoiceKey),
      orElse: () => AppFontChoice.pingFang,
    );
    _customPrimaryFontFamily =
        _prefs.getString(_customPrimaryFontFamilyKey)?.trim() ?? '';
    _customCjkFontFamily =
        _prefs.getString(_customCjkFontFamilyKey)?.trim() ?? '';
    _monospaceFontChoice = AppMonospaceFontChoice.values.firstWhere(
      (m) => m.name == _prefs.getString(_monospaceFontChoiceKey),
      orElse: () => AppMonospaceFontChoice.menlo,
    );
    _customMonospaceFontFamily =
        _prefs.getString(_customMonospaceFontFamilyKey)?.trim() ?? '';
    final storedEmojiFontKey = _prefs.getString(_emojiFontChoiceKey);
    final emojiFontKey = _normalizeEmojiFontKey(
      storedEmojiFontKey,
      migrated: _emojiFontKeysAreMigrated,
    );
    if (emojiFontKey != storedEmojiFontKey?.trim()) {
      unawaited(_prefs.setString(_emojiFontChoiceKey, emojiFontKey));
    }
    unawaited(_prefs.setInt(_emojiFontSchemaKey, _emojiFontSchemaVersion));
    _emojiFontChoice = EmojiFontChoice(
      key: emojiFontKey,
      label: emojiFontKey == EmojiFontChoice.system.key
          ? EmojiFontChoice.system.label
          : _prefs.getString(_emojiFontLabelKey) ?? emojiFontKey,
      license: _prefs.getString(_emojiFontLicenseKey),
      fontFamily: _emojiFontCatalog.loadedFamilyForKey(emojiFontKey),
    );
    _fontFallbackChain = dedupeFontFamilies(
      _prefs.getStringList(_fontFallbackChainKey) ?? const <String>[],
    );
    _invalidateFontCaches();
    unawaited(_normalizeStoredPlatformFontFamilies());
    _fontScale = _prefs.getDouble(_fontKey) ?? 1.0;
    _interfaceScale = _prefs.getDouble(_interfaceScaleKey) ?? 1.0;
    _circularGroupAvatars = _prefs.getBool(_groupAvatarCircleKey) ?? true;
    _animateAvatars = _prefs.getBool(_animateAvatarsKey) ?? true;
    _animateStatusEmoji = _prefs.getBool(_animateStatusEmojiKey) ?? true;
    final storedChatFolderMode = _prefs.getString(_chatFolderDisplayModeKey);
    _chatFolderDisplayMode = ChatFolderDisplayMode.values.firstWhere(
      (mode) => mode.name == storedChatFolderMode,
      orElse: () {
        final legacyFolderFilter = _prefs.getBool(_chatFolderFilterKey);
        if (legacyFolderFilter == null) return ChatFolderDisplayMode.tabs;
        return legacyFolderFilter
            ? ChatFolderDisplayMode.menu
            : ChatFolderDisplayMode.hidden;
      },
    );
    final storedChatListSwipeMode = _prefs.getString(_chatListSwipeModeKey);
    final hasStoredChatListSwipeMode = ChatListSwipeMode.values.any(
      (mode) => mode.name == storedChatListSwipeMode,
    );
    _chatListSwipeMode = ChatListSwipeMode.values.firstWhere(
      (mode) => mode.name == storedChatListSwipeMode,
      orElse: () {
        final legacyBehavior = _prefs.getString(
          _legacyChatListSwipeBehaviorKey,
        );
        final legacySwitchesFolders =
            legacyBehavior == ChatListSwipeMode.switchFolders.name ||
            (legacyBehavior == null &&
                (_prefs.getBool(_legacyDisableChatListSwipeActionsKey) ??
                    false) &&
                (_prefs.getBool(_legacyChatListFolderSwipeSwitchingKey) ??
                    false));
        return legacySwitchesFolders
            ? ChatListSwipeMode.switchFolders
            : ChatListSwipeMode.chatActions;
      },
    );
    if (!hasStoredChatListSwipeMode) {
      _prefs.setString(_chatListSwipeModeKey, _chatListSwipeMode.name);
    }
    _showChatListSearch = _prefs.getBool(_chatListSearchKey) ?? true;
    _hideSidebarPhone = _prefs.getBool(_hideSidebarPhoneKey) ?? false;
    _showMemberTags = _prefs.getBool(_memberTagsKey) ?? false;
    _showPlainMemberRoleTags = _prefs.getBool(_plainMemberRoleTagsKey) ?? false;
    _chatListNameColorAudience = _storedNameColorAudience(
      _chatListNameColorAudienceKey,
      fallback: _prefs.getBool(_nameColorsKey) == false
          ? NameColorAudience.nobody
          : NameColorAudience.premium,
    );
    _chatNameColorAudience = _storedNameColorAudience(
      _chatNameColorAudienceKey,
      fallback: _prefs.getBool(_chatNameColorsKey) == false
          ? NameColorAudience.nobody
          : NameColorAudience.allUsers,
    );
    final legacyStatusAnimation = _prefs.getBool(_animateStatusEmojiKey);
    _chatListStatusEmojiMode = _storedStatusEmojiMode(
      _chatListStatusEmojiModeKey,
      fallback: _prefs.getBool(_premiumEmojiStatusKey) == false
          ? StatusEmojiDisplayMode.none
          : legacyStatusAnimation == true
          ? StatusEmojiDisplayMode.animated
          : StatusEmojiDisplayMode.static,
    );
    _chatStatusEmojiMode = _storedStatusEmojiMode(
      _chatStatusEmojiModeKey,
      fallback: _prefs.getBool(_chatPremiumEmojiStatusKey) == false
          ? StatusEmojiDisplayMode.none
          : legacyStatusAnimation == true
          ? StatusEmojiDisplayMode.animated
          : StatusEmojiDisplayMode.static,
    );
    final storedSenderNameReadability = _prefs.getString(
      _senderNameReadabilityModeKey,
    );
    _senderNameReadabilityMode = SenderNameReadabilityMode.values.firstWhere(
      (mode) => mode.name == storedSenderNameReadability,
      // 'shadow' is what this mode was called before it became a colour blend;
      // a stored preference still names it.
      orElse: () => storedSenderNameReadability == 'shadow'
          ? SenderNameReadabilityMode.blend
          : switch (_prefs.getBool(_senderNameReadabilityPlateKey)) {
              true => SenderNameReadabilityMode.background,
              false => SenderNameReadabilityMode.none,
              null => SenderNameReadabilityMode.blend,
            },
    );
    _showMessageMetaIndicators =
        _prefs.getBool(_messageMetaIndicatorsKey) ?? false;
    _alwaysShowMessageTime = _prefs.getBool(_alwaysShowMessageTimeKey) ?? false;
    _mobileMessageActionMenuStyle = MobileMessageActionMenuStyle.values
        .firstWhere(
          (style) =>
              style.name == _prefs.getString(_mobileMessageActionMenuStyleKey),
          orElse: () => MobileMessageActionMenuStyle.grid,
        );
    _enterToSend = _prefs.getBool(_enterToSendKey) ?? false;
    _openChatsAtLatest = _prefs.getBool(_openChatsAtLatestKey) ?? false;
    _preserveSenderWhenRepeating =
        _prefs.getBool(_preserveSenderWhenRepeatingKey) ?? true;
    _quickRepliesEnabled = _prefs.getBool(_quickRepliesEnabledKey) ?? true;
    final storedQuickReactions = _prefs.getStringList(_quickReactionsKey);
    _quickReactions = storedQuickReactions == null
        ? [...defaultQuickReactions]
        : _normalizeQuickReactions(
            storedQuickReactions
                .map(QuickReactionChoice.fromStorage)
                .whereType<QuickReactionChoice>(),
          );
    if (_quickReactions.isEmpty) _quickReactions = [...defaultQuickReactions];
    _groupImageMessages = _prefs.getBool(_groupImageMessagesKey) ?? true;
    _hideBlockedUserMessages =
        _prefs.getBool(_hideBlockedUserMessagesKey) ?? false;
    _showChannelsTab = _prefs.getBool(_showChannelsTabKey) ?? false;
    _showMomentsTab = _prefs.getBool(_showMomentsTabKey) ?? true;
    _showShortVideos = _prefs.getBool(_showShortVideosKey) ?? true;
    _communitiesEnabled = _prefs.getBool(_communitiesEnabledKey) ?? true;
    final storedArchivedChatsMode = _prefs.getString(
      _archivedChatsDisplayModeKey,
    );
    _archivedChatsDisplayMode = switch (storedArchivedChatsMode) {
      'always' || 'top' => ArchivedChatsDisplayMode.firstPosition,
      'secondScreen' => ArchivedChatsDisplayMode.nextPage,
      _ => ArchivedChatsDisplayMode.values.firstWhere(
        (mode) => mode.name == storedArchivedChatsMode,
        orElse: () => ArchivedChatsDisplayMode.pullDown,
      ),
    };
    _unreadBadgeMode = UnreadBadgeMode.values.firstWhere(
      (m) => m.name == _prefs.getString(_unreadBadgeModeKey),
      orElse: () => UnreadBadgeMode.messages,
    );
    _unreadBadgeOverflowMode = UnreadBadgeOverflowMode.values.firstWhere(
      (m) => m.name == _prefs.getString(_unreadBadgeOverflowModeKey),
      orElse: () => UnreadBadgeOverflowMode.capped,
    );
    AppTheme.applyBrand(_brandColor); // before the first MaterialApp build
  }

  static const _modeKey = 'appearanceMode';
  static const _themingEnabledKey = 'appearanceThemingEnabled';
  static const _brandKey = 'brandColor';
  static const _cloudThemeKey = 'telegramCloudTheme';
  static const _lightCloudThemeKey = 'telegramCloudThemeLight';
  static const _darkCloudThemeKey = 'telegramCloudThemeDark';
  static const _installedCloudThemesKey = 'installedTelegramCloudThemes';
  static const _legacyUseTelegramThemeForUiKey = 'useTelegramThemeForUi';
  static const _messageBubblesEnabledKey = 'messageBubblesEnabled.v1';
  static const _messageBubbleBackgroundKey = 'messageBubbleBackground.v1';
  static const _messageBubbleApplicationScopeKey =
      'messageBubbleApplicationScope.v1';
  static const _customMessageBubbleBackgroundKey =
      'customMessageBubbleBackground.v1';
  static const _usePerAccountThemingKey = 'usePerAccountTheming';
  static const _preCloudThemeModeKey = 'preTelegramCloudThemeMode';
  static const _preCloudThemeBrandKey = 'preTelegramCloudThemeBrand';
  static const _fontChoiceKey = 'fontChoice';
  static const _cjkFontChoiceKey = 'cjkFontChoice';
  static const _customPrimaryFontFamilyKey = 'customPrimaryFontFamily';
  static const _customCjkFontFamilyKey = 'customCjkFontFamily';
  static const _monospaceFontChoiceKey = 'monospaceFontChoice';
  static const _customMonospaceFontFamilyKey = 'customMonospaceFontFamily';
  static const _emojiFontChoiceKey = 'emojiFontChoice';
  static const _emojiFontLabelKey = 'emojiFontLabel';
  static const _emojiFontLicenseKey = 'emojiFontLicense';
  static const _emojiFontSchemaKey = 'emojiFontChoiceSchema';
  static const _fontFallbackChainKey = 'fontFallbackChain';
  static const _fontKey = 'fontScale';
  static const _interfaceScaleKey = 'interfaceScale';
  static const _groupAvatarCircleKey = 'circularGroupAvatars';
  static const _animateAvatarsKey = 'animateAvatars';
  static const _animateStatusEmojiKey = 'animateStatusEmoji';
  static const _chatFolderDisplayModeKey = 'chatFolderDisplayMode';
  static const _chatListSwipeModeKey = 'chatListSwipeMode.v1';
  static const _legacyChatListSwipeBehaviorKey = 'chatListSwipeBehavior';
  static const _legacyDisableChatListSwipeActionsKey =
      'disableChatListSwipeActions';
  static const _legacyChatListFolderSwipeSwitchingKey =
      'chatListFolderSwipeSwitching';
  // Retained only to migrate the former show/hide toggle.
  static const _chatFolderFilterKey = 'showChatFolderFilter';
  static const _chatListSearchKey = 'showChatListSearch';
  static const _hideSidebarPhoneKey = 'hideSidebarPhone';
  static const _memberTagsKey = 'showMemberTags';
  static const _plainMemberRoleTagsKey = 'showPlainMemberRoleTags';
  // Storage names are retained so existing appearance preferences survive the
  // user-facing rename from Premium name colors to name colors.
  static const _nameColorsKey = 'showPremiumNameColors';
  static const _premiumEmojiStatusKey = 'showPremiumEmojiStatus';
  static const _chatNameColorsKey = 'showChatPremiumNameColors';
  static const _chatPremiumEmojiStatusKey = 'showChatPremiumEmojiStatus';
  static const _chatListNameColorAudienceKey = 'chatListNameColorAudience.v1';
  static const _chatNameColorAudienceKey = 'chatNameColorAudience.v1';
  static const _chatListStatusEmojiModeKey = 'chatListStatusEmojiMode.v1';
  static const _chatStatusEmojiModeKey = 'chatStatusEmojiMode.v1';
  static const _senderNameReadabilityPlateKey =
      'showSenderNameReadabilityPlate';
  static const _senderNameReadabilityModeKey = 'senderNameReadabilityMode.v1';
  static const _messageMetaIndicatorsKey = 'showMessageMetaIndicators';
  static const _alwaysShowMessageTimeKey = 'alwaysShowMessageTime';
  static const _mobileMessageActionMenuStyleKey =
      'mobileMessageActionMenuStyle.v1';
  static const _enterToSendKey = 'enterToSend';
  static const _openChatsAtLatestKey = 'openChatsAtLatest';
  static const _preserveSenderWhenRepeatingKey = 'preserveSenderWhenRepeating';
  static const _quickRepliesEnabledKey = 'quickRepliesEnabled';
  static const _quickReactionsKey = 'quickReactions';
  static const _groupImageMessagesKey = 'groupImageMessages';
  static const _hideBlockedUserMessagesKey = 'hideBlockedUserMessages';
  static const _showChannelsTabKey = 'showChannelsTab';
  static const _showMomentsTabKey = 'showMomentsTab';
  static const _showShortVideosKey = 'showShortVideos';
  static const _communitiesEnabledKey = 'communitiesEnabled';
  static const _archivedChatsDisplayModeKey = 'archivedChatsDisplayMode';
  static const _unreadBadgeModeKey = 'unreadBadgeMode';
  static const _unreadBadgeOverflowModeKey = 'unreadBadgeOverflowMode';

  static const double minFontScale = 0.8;
  static const double maxFontScale = 1.4;
  static const double minInterfaceScale = 0.66 * 0.66;
  static const double maxInterfaceScale = 1.50 * 1.50;

  final SharedPreferences _prefs;
  final EmojiFontCatalog _emojiFontCatalog;
  int _activeAccountSlot;
  int? _activeAccountUserId;
  late bool _usePerAccountTheming;
  late bool _themingEnabled;
  late AppearanceMode _mode;
  late Color _brandColor;
  TelegramCloudTheme? _lightCloudTheme;
  TelegramCloudTheme? _darkCloudTheme;
  late List<TelegramCloudTheme> _installedCloudThemes;
  int _installedCloudThemeRevision = 0;
  late bool _messageBubblesEnabled;
  late MessageBubbleBackground _messageBubbleBackground;
  late MessageBubbleApplicationScope _messageBubbleApplicationScope;
  CustomMessageBubbleBackground? _customMessageBubbleBackground;
  late AppFontChoice _fontChoice;
  late AppFontChoice _cjkFontChoice;
  late String _customPrimaryFontFamily;
  late String _customCjkFontFamily;
  late AppMonospaceFontChoice _monospaceFontChoice;
  late String _customMonospaceFontFamily;
  late EmojiFontChoice _emojiFontChoice;
  int _emojiFontSelectionRevision = 0;
  late List<String> _fontFallbackChain;

  // The font chain is rebuilt from scratch on every applyAppTextStyle call
  // (three dedupe passes each), and applyAppTextTheme runs 15 of those per
  // TextTheme. Nothing here changes between builds, so memoize until a font
  // preference actually moves — see _invalidateFontCaches.
  List<String>? _normalFontFamilyChainCache;
  List<String>? _effectiveFontFamilyChainCache;
  final Map<(TextStyle, bool), TextStyle> _appTextStyleCache = {};
  late double _fontScale;
  late double _interfaceScale;
  Timer? _scalePersistTimer;
  bool _fontScaleNeedsPersist = false;
  bool _interfaceScaleNeedsPersist = false;
  late bool _circularGroupAvatars;
  late bool _animateAvatars;
  late bool _animateStatusEmoji;
  late ChatFolderDisplayMode _chatFolderDisplayMode;
  late ChatListSwipeMode _chatListSwipeMode;
  bool _showChatListSearch = true;
  bool _hideSidebarPhone = false;
  bool _showMemberTags = false;
  bool _showPlainMemberRoleTags = false;
  NameColorAudience _chatListNameColorAudience = NameColorAudience.premium;
  NameColorAudience _chatNameColorAudience = NameColorAudience.allUsers;
  StatusEmojiDisplayMode _chatListStatusEmojiMode =
      StatusEmojiDisplayMode.static;
  StatusEmojiDisplayMode _chatStatusEmojiMode = StatusEmojiDisplayMode.static;
  SenderNameReadabilityMode _senderNameReadabilityMode =
      SenderNameReadabilityMode.blend;
  bool _showMessageMetaIndicators = false;
  bool _alwaysShowMessageTime = false;
  late MobileMessageActionMenuStyle _mobileMessageActionMenuStyle;
  bool _enterToSend = false;
  bool _openChatsAtLatest = false;
  bool _preserveSenderWhenRepeating = true;
  bool _quickRepliesEnabled = true;
  late List<QuickReactionChoice> _quickReactions;
  bool _groupImageMessages = true;
  bool _hideBlockedUserMessages = false;
  bool _showChannelsTab = false;
  bool _showMomentsTab = true;
  bool _showShortVideos = true;
  bool _communitiesEnabled = true;
  late ArchivedChatsDisplayMode _archivedChatsDisplayMode;
  late UnreadBadgeMode _unreadBadgeMode;
  late UnreadBadgeOverflowMode _unreadBadgeOverflowMode;

  AppearanceMode get mode => _mode;
  bool get themingEnabled => _themingEnabled;
  ThemeMode get themeMode => _mode.themeMode;
  Color get brandColor => _brandColor;
  TelegramCloudTheme? get lightCloudTheme => _lightCloudTheme;
  TelegramCloudTheme? get darkCloudTheme => _darkCloudTheme;
  bool get hasCloudTheme => _lightCloudTheme != null || _darkCloudTheme != null;
  List<TelegramCloudTheme> get installedCloudThemes =>
      List.unmodifiable(_installedCloudThemes);
  String get installedCloudThemeCacheScope => _installedCloudThemeCacheKey();
  int get installedCloudThemeRevision => _installedCloudThemeRevision;
  TelegramCloudTheme? cloudThemeFor(Brightness brightness) => !_themingEnabled
      ? null
      : brightness == Brightness.dark
      ? _darkCloudTheme
      : _lightCloudTheme;
  TelegramCloudTheme? get cloudTheme => cloudThemeFor(switch (_mode) {
    AppearanceMode.light => Brightness.light,
    AppearanceMode.dark => Brightness.dark,
    AppearanceMode.system =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  });
  bool usesCloudThemeForUi(Brightness brightness) =>
      cloudThemeFor(brightness) != null;
  bool get messageBubblesEnabled => _messageBubblesEnabled;
  MessageBubbleBackground get messageBubbleBackground =>
      _messageBubbleBackground;
  MessageBubbleBackground get effectiveMessageBubbleBackground =>
      _themingEnabled
      ? _messageBubbleBackground
      : MessageBubbleBackground.standard;
  CustomMessageBubbleBackground? get customMessageBubbleBackground =>
      _customMessageBubbleBackground;
  MessageBubbleBackgroundSpec get messageBubbleBackgroundSpec =>
      MessageBubbleBackgroundSpec.resolve(
        _messageBubbleBackground,
        custom: _customMessageBubbleBackground,
      );
  MessageBubbleBackgroundSpec get effectiveMessageBubbleBackgroundSpec =>
      _themingEnabled
      ? messageBubbleBackgroundSpec
      : MessageBubbleBackgroundSpec.standard;
  MessageBubbleApplicationScope get messageBubbleApplicationScope =>
      _messageBubbleApplicationScope;
  MessageBubbleBackgroundSpec effectiveMessageBubbleBackgroundSpecFor({
    required bool outgoing,
  }) {
    // Turning the preference off drops the custom image and falls back to the
    // theme's own bubble; the selection is kept so re-enabling restores it.
    if (!_messageBubblesEnabled ||
        !_themingEnabled ||
        (!outgoing &&
            _messageBubbleApplicationScope ==
                MessageBubbleApplicationScope.ownMessages)) {
      return MessageBubbleBackgroundSpec.standard;
    }
    return messageBubbleBackgroundSpec;
  }

  bool shouldRenderMessageBubbleSurface({
    required bool outgoing,
    required Brightness brightness,
    bool hasCustomChatTheme = false,
  }) {
    // Messages always sit on a bubble. The preference chooses whether that
    // bubble is the custom image or the theme's own default fill — see
    // [effectiveMessageBubbleBackgroundSpecFor] — it does not remove the
    // surface. Dropping it left incoming messages as bare text on the
    // wallpaper while outgoing kept a bubble.
    return true;
  }

  MessageBubbleBackgroundSpec messageBubbleBackgroundSpecFor(
    MessageBubbleBackground selection,
  ) => MessageBubbleBackgroundSpec.resolve(
    selection,
    custom: _customMessageBubbleBackground,
  );
  bool get usePerAccountTheming => _usePerAccountTheming;

  String _scopedThemeKey(String key) {
    if (!_usePerAccountTheming) return key;
    final userId = _activeAccountUserId;
    return userId == null
        ? '$key.account.$_activeAccountSlot'
        : '$key.account.user.$userId';
  }

  /// Installed Telegram themes belong to the signed-in Telegram account even
  /// when appearance selections themselves are shared between accounts. Keep
  /// their cache isolated by stable user identity (falling back to the local
  /// slot until TDLib has resolved the user).
  String _installedCloudThemeCacheKey() {
    final userId = _activeAccountUserId;
    return userId == null
        ? _installedCloudThemeSlotCacheKey(_activeAccountSlot)
        : _installedCloudThemeIdentityCacheKey(userId);
  }

  String _installedCloudThemeSlotCacheKey(int slot) =>
      '$_installedCloudThemesKey.account.$slot';

  String _installedCloudThemeIdentityCacheKey(int userId) =>
      '$_installedCloudThemesKey.account.user.$userId';

  void _loadInstalledCloudThemeCache({bool migrateLegacy = false}) {
    final cacheKey = _installedCloudThemeCacheKey();
    if (migrateLegacy) {
      final candidates = <String>[
        if (_activeAccountUserId != null)
          _installedCloudThemeSlotCacheKey(_activeAccountSlot),
        _installedCloudThemesKey,
      ];
      if (!_prefs.containsKey(cacheKey)) {
        for (final candidate in candidates) {
          if (candidate == cacheKey) continue;
          final encoded = _prefs.getString(candidate);
          if (encoded == null) continue;
          _prefs.setString(cacheKey, encoded);
          break;
        }
      }
      // Migration sources are provisional, not shared stores. Clear them
      // even when the identity cache already exists so a later account cannot
      // inherit stale membership while its own identity is resolving.
      for (final candidate in candidates) {
        if (candidate != cacheKey) _prefs.remove(candidate);
      }
    }

    _installedCloudThemes = [];
    try {
      final encodedThemes = _prefs.getString(cacheKey);
      final decodedThemes = encodedThemes == null
          ? const <Object?>[]
          : jsonDecode(encodedThemes) as List;
      for (final value in decodedThemes) {
        final theme = TelegramCloudTheme.fromJson(value);
        if (theme != null) _addInstalledCloudTheme(theme);
      }
    } catch (_) {
      // A malformed or partially-written cache must not prevent Appearance
      // from opening. The next successful refresh replaces it.
    }
  }

  void _migrateInstalledCloudThemeCache(int slot, int userId) {
    final slotKey = _installedCloudThemeSlotCacheKey(slot);
    final identityKey = _installedCloudThemeIdentityCacheKey(userId);
    if (!_prefs.containsKey(identityKey)) {
      final encoded = _prefs.getString(slotKey);
      if (encoded != null) _prefs.setString(identityKey, encoded);
    }
    // Once TDLib resolves a stable user identity, the slot fallback has
    // completed its job. Remove it even when an identity cache already exists
    // so a later account reusing this slot cannot briefly see another user's
    // themes while its own identity is still resolving.
    _prefs.remove(slotKey);
  }

  void _migrateLegacyAccountTheme(int slot, int userId) {
    for (final key in const [
      _modeKey,
      _brandKey,
      _cloudThemeKey,
      _lightCloudThemeKey,
      _darkCloudThemeKey,
      _legacyUseTelegramThemeForUiKey,
      _messageBubblesEnabledKey,
      _messageBubbleBackgroundKey,
      _messageBubbleApplicationScopeKey,
      _customMessageBubbleBackgroundKey,
    ]) {
      final legacyKey = '$key.account.$slot';
      final identityKey = '$key.account.user.$userId';
      final value = _prefs.get(legacyKey);
      if (value == null) continue;
      if (!_prefs.containsKey(identityKey)) {
        if (value is bool) {
          _prefs.setBool(identityKey, value);
        } else if (value is int) {
          _prefs.setInt(identityKey, value);
        } else if (value is String) {
          _prefs.setString(identityKey, value);
        }
      }
      _prefs.remove(legacyKey);
    }
  }

  TelegramCloudTheme? _decodeTheme(String key) {
    try {
      final encoded = _prefs.getString(key);
      return encoded == null
          ? null
          : TelegramCloudTheme.fromJson(jsonDecode(encoded));
    } catch (_) {
      return null;
    }
  }

  CustomMessageBubbleBackground? _decodeCustomMessageBubbleBackground(
    String key,
  ) {
    try {
      final encoded = _prefs.getString(key);
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return CustomMessageBubbleBackground.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } catch (_) {
      return null;
    }
  }

  void _repairMissingCustomMessageBubble() {
    final custom = _customMessageBubbleBackground;
    if (custom == null) {
      _prefs.remove(_scopedThemeKey(_customMessageBubbleBackgroundKey));
    } else if (!custom.fileExists) {
      _customMessageBubbleBackground = null;
      _prefs.remove(_scopedThemeKey(_customMessageBubbleBackgroundKey));
    }
    if (_messageBubbleBackground == MessageBubbleBackground.custom &&
        _customMessageBubbleBackground == null) {
      _messageBubbleBackground = MessageBubbleBackground.standard;
      _prefs.setString(
        _scopedThemeKey(_messageBubbleBackgroundKey),
        MessageBubbleBackground.standard.name,
      );
    }
  }

  void _loadScopedThemeSettings() {
    _mode = AppearanceMode.values.firstWhere(
      (mode) => mode.name == _prefs.getString(_scopedThemeKey(_modeKey)),
      orElse: () => AppearanceMode.system,
    );
    _brandColor = Color(
      _prefs.getInt(_scopedThemeKey(_brandKey)) ??
          (0xFF000000 | AppTheme.defaultBrand),
    );
    _lightCloudTheme = _decodeTheme(_scopedThemeKey(_lightCloudThemeKey));
    _darkCloudTheme = _decodeTheme(_scopedThemeKey(_darkCloudThemeKey));
    _prefs.remove(_scopedThemeKey(_legacyUseTelegramThemeForUiKey));
    _customMessageBubbleBackground = _decodeCustomMessageBubbleBackground(
      _scopedThemeKey(_customMessageBubbleBackgroundKey),
    );
    _messageBubblesEnabled =
        _prefs.getBool(_scopedThemeKey(_messageBubblesEnabledKey)) ?? true;
    _messageBubbleBackground = MessageBubbleBackground.fromStorage(
      _prefs.getString(_scopedThemeKey(_messageBubbleBackgroundKey)),
    );
    _messageBubbleApplicationScope = MessageBubbleApplicationScope.values
        .firstWhere(
          (scope) =>
              scope.name ==
              _prefs.getString(
                _scopedThemeKey(_messageBubbleApplicationScopeKey),
              ),
          orElse: () => MessageBubbleApplicationScope.allMessages,
        );
    _repairMissingCustomMessageBubble();
    AppTheme.applyBrand(_brandColor);
  }

  void _persistScopedThemeSettings() {
    _prefs.setString(_scopedThemeKey(_modeKey), _mode.name);
    _prefs.setInt(_scopedThemeKey(_brandKey), _brandColor.toARGB32());
    _prefs.setBool(
      _scopedThemeKey(_messageBubblesEnabledKey),
      _messageBubblesEnabled,
    );
    _prefs.setString(
      _scopedThemeKey(_messageBubbleBackgroundKey),
      _messageBubbleBackground.name,
    );
    _prefs.setString(
      _scopedThemeKey(_messageBubbleApplicationScopeKey),
      _messageBubbleApplicationScope.name,
    );
    final custom = _customMessageBubbleBackground;
    if (custom == null) {
      _prefs.remove(_scopedThemeKey(_customMessageBubbleBackgroundKey));
    } else {
      _prefs.setString(
        _scopedThemeKey(_customMessageBubbleBackgroundKey),
        jsonEncode(custom.toJson()),
      );
    }
    _persistCloudThemes();
  }

  void setActiveAccountSlot(int value, {int? userId}) {
    if (_activeAccountSlot == value && _activeAccountUserId == userId) return;
    _activeAccountSlot = value;
    _activeAccountUserId = userId;
    if (userId != null) {
      _migrateInstalledCloudThemeCache(value, userId);
    }
    _loadInstalledCloudThemeCache(migrateLegacy: true);
    if (!_usePerAccountTheming) {
      notifyListeners();
      return;
    }
    if (userId != null) _migrateLegacyAccountTheme(value, userId);
    _loadScopedThemeSettings();
    notifyListeners();
  }

  set usePerAccountTheming(bool value) {
    if (_usePerAccountTheming == value) return;
    final mode = _mode;
    final brand = _brandColor;
    final light = _lightCloudTheme;
    final dark = _darkCloudTheme;
    final messageBubblesEnabled = _messageBubblesEnabled;
    final bubbleBackground = _messageBubbleBackground;
    final bubbleApplicationScope = _messageBubbleApplicationScope;
    final customBubbleBackground = _customMessageBubbleBackground;
    _usePerAccountTheming = value;
    _prefs.setBool(_usePerAccountThemingKey, value);
    if (value) {
      final accountHasSelection =
          _prefs.containsKey(_scopedThemeKey(_modeKey)) ||
          _prefs.containsKey(_scopedThemeKey(_brandKey)) ||
          _prefs.containsKey(_scopedThemeKey(_lightCloudThemeKey)) ||
          _prefs.containsKey(_scopedThemeKey(_darkCloudThemeKey)) ||
          _prefs.containsKey(_scopedThemeKey(_messageBubblesEnabledKey)) ||
          _prefs.containsKey(_scopedThemeKey(_messageBubbleBackgroundKey)) ||
          _prefs.containsKey(
            _scopedThemeKey(_messageBubbleApplicationScopeKey),
          ) ||
          _prefs.containsKey(
            _scopedThemeKey(_customMessageBubbleBackgroundKey),
          );
      if (!accountHasSelection) {
        _mode = mode;
        _brandColor = brand;
        _lightCloudTheme = light;
        _darkCloudTheme = dark;
        _messageBubblesEnabled = messageBubblesEnabled;
        _messageBubbleBackground = bubbleBackground;
        _messageBubbleApplicationScope = bubbleApplicationScope;
        _customMessageBubbleBackground = customBubbleBackground;
        _persistScopedThemeSettings();
      } else {
        _loadScopedThemeSettings();
      }
    } else {
      _loadScopedThemeSettings();
    }
    notifyListeners();
  }

  /// The reusable semantic palette for every app surface at [brightness].
  /// A selected cloud theme always owns the matching interface palette.
  AppColors uiColorsFor(Brightness brightness) {
    final theme = cloudThemeFor(brightness);
    if (theme != null) return theme.uiColors;
    return brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  }

  AppColors appColorsFor(Brightness brightness) => uiColorsFor(brightness);

  set themingEnabled(bool value) {
    if (_themingEnabled == value) return;
    _themingEnabled = value;
    _prefs.setBool(_themingEnabledKey, value);
    notifyListeners();
  }

  AppFontChoice get fontChoice => _fontChoice;
  AppFontChoice get cjkFontChoice => _cjkFontChoice;
  String get customPrimaryFontFamily => _customPrimaryFontFamily;
  String get customCjkFontFamily => _customCjkFontFamily;
  AppMonospaceFontChoice get monospaceFontChoice => _monospaceFontChoice;
  String get customMonospaceFontFamily => _customMonospaceFontFamily;
  EmojiFontChoice get emojiFontChoice => _emojiFontChoice;
  List<String> get fontFallbackChain => List.unmodifiable(_fontFallbackChain);
  bool get usesCustomFontFallbackChain => _fontFallbackChain.isNotEmpty;
  String get effectivePrimaryFontLabel =>
      _fontChoice.isCustom && _customPrimaryFontFamily.isNotEmpty
      ? displayStoredFontFamily(_customPrimaryFontFamily)
      : AppStrings.t(_fontChoice.label);
  String get effectiveCjkFontLabel =>
      _cjkFontChoice.isCustom && _customCjkFontFamily.isNotEmpty
      ? displayStoredFontFamily(_customCjkFontFamily)
      : AppStrings.t(_cjkFontChoice.label);
  String get effectiveMonospaceFontLabel =>
      _monospaceFontChoice.isCustom && _customMonospaceFontFamily.isNotEmpty
      ? displayStoredFontFamily(_customMonospaceFontFamily)
      : AppStrings.t(_monospaceFontChoice.label);
  String get effectiveFontChainLabel {
    if (_fontFallbackChain.isEmpty) {
      return AppStrings.t(AppStringKeys.groupManagementNotSet);
    }
    final displayChain = _fontFallbackChain
        .map(displayStoredFontFamily)
        .toList();
    if (displayChain.length == 1) return displayChain.first;
    final head = displayChain.take(2).join(' / ');
    return _fontFallbackChain.length > 2
        ? '$head / +${_fontFallbackChain.length - 2}'
        : head;
  }

  bool get circularGroupAvatars => _circularGroupAvatars;
  bool get animateAvatars => _animateAvatars;
  bool get animateStatusEmoji => _animateStatusEmoji;
  ChatFolderDisplayMode get chatFolderDisplayMode => _chatFolderDisplayMode;
  ChatListSwipeMode get chatListSwipeMode => _chatListSwipeMode;
  bool get showChatListSearch => _showChatListSearch;
  bool get hideSidebarPhone => _hideSidebarPhone;
  bool get showMemberTags => _showMemberTags;
  bool get showPlainMemberRoleTags => _showPlainMemberRoleTags;
  NameColorAudience get chatListNameColorAudience => _chatListNameColorAudience;
  NameColorAudience get chatNameColorAudience => _chatNameColorAudience;
  StatusEmojiDisplayMode get chatListStatusEmojiMode =>
      _chatListStatusEmojiMode;
  StatusEmojiDisplayMode get chatStatusEmojiMode => _chatStatusEmojiMode;
  bool get showNameColors =>
      _chatListNameColorAudience != NameColorAudience.nobody;
  bool get showPremiumEmojiStatus => _chatListStatusEmojiMode.visible;
  bool get showChatNameColors =>
      _chatNameColorAudience != NameColorAudience.nobody;
  bool get showChatPremiumEmojiStatus => _chatStatusEmojiMode.visible;
  SenderNameReadabilityMode get senderNameReadabilityMode =>
      _senderNameReadabilityMode;
  bool get showMessageMetaIndicators => _showMessageMetaIndicators;
  bool get alwaysShowMessageTime => _alwaysShowMessageTime;
  MobileMessageActionMenuStyle get mobileMessageActionMenuStyle =>
      _mobileMessageActionMenuStyle;
  bool get enterToSend => _enterToSend;
  bool get openChatsAtLatest => _openChatsAtLatest;
  bool get preserveSenderWhenRepeating => _preserveSenderWhenRepeating;
  bool get quickRepliesEnabled => _quickRepliesEnabled;
  List<QuickReactionChoice> get quickReactions =>
      List.unmodifiable(_quickReactions);
  bool get groupImageMessages => _groupImageMessages;
  bool get hideBlockedUserMessages => _hideBlockedUserMessages;
  bool get showChannelsTab => _showChannelsTab;
  bool get showMomentsTab => _showMomentsTab;
  bool get showShortVideos => _showShortVideos;
  bool get communitiesEnabled => _communitiesEnabled;
  ArchivedChatsDisplayMode get archivedChatsDisplayMode =>
      _archivedChatsDisplayMode;
  UnreadBadgeMode get unreadBadgeMode => _unreadBadgeMode;
  bool get unreadBadgeShowsChatCount =>
      _unreadBadgeMode == UnreadBadgeMode.chats;
  UnreadBadgeOverflowMode get unreadBadgeOverflowMode =>
      _unreadBadgeOverflowMode;
  bool get capUnreadBadgeAt99 =>
      _unreadBadgeOverflowMode == UnreadBadgeOverflowMode.capped;

  NameColorAudience _storedNameColorAudience(
    String key, {
    required NameColorAudience fallback,
  }) {
    final stored = _prefs.getString(key);
    final value = NameColorAudience.values.firstWhere(
      (audience) => audience.name == stored,
      orElse: () => fallback,
    );
    if (stored != value.name) {
      _prefs.setString(key, value.name);
    }
    return value;
  }

  StatusEmojiDisplayMode _storedStatusEmojiMode(
    String key, {
    required StatusEmojiDisplayMode fallback,
  }) {
    final stored = _prefs.getString(key);
    final value = StatusEmojiDisplayMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => fallback,
    );
    if (stored != value.name) {
      _prefs.setString(key, value.name);
    }
    return value;
  }

  /// App-wide text scale factor, applied at the root via MediaQuery.textScaler.
  double get fontScale => _fontScale;
  // Font scaling is applied once by the root MediaQuery. Returning an already
  // scaled size here made chat typography grow twice while navigation text
  // grew once.
  double chatTextSize(double base) => base;

  /// Squared value shown by the Interface Size control. For example, the
  /// historical 1.5 render scale is presented as 225%.
  double get interfaceScale => _interfaceScale * _interfaceScale;
  double get renderedInterfaceScale => math.sqrt(interfaceScale);
  double get rowHeight => AppMetric.listRowHeight;
  double get avatarSize => AppMetric.avatarSize;
  double get navHeaderHeight => AppMetric.navHeaderHeight;
  double scaled(double base) => base;

  /// Drops every derived font cache. Called from anywhere a font preference is
  /// assigned, including the preference reload — a setter-only sweep would
  /// serve a stale TextTheme after an account switch.
  void _invalidateFontCaches() {
    _normalFontFamilyChainCache = null;
    _effectiveFontFamilyChainCache = null;
    _appTextStyleCache.clear();
  }

  /// The cached chains are shared with every caller; treat them as read-only.
  List<String> _normalFontFamilyChain([TextStyle? base]) {
    return _normalFontFamilyChainCache ??= dedupeFontFamilies([
      ...(_fontFallbackChain.isNotEmpty
          ? _fontFallbackChain
          : [AppFontChoice._platformFontFamily()]),
      ...AppFontChoice._platformFontFallback(),
    ]);
  }

  List<String> effectiveFontFamilyChain([TextStyle? base]) {
    final cached = _effectiveFontFamilyChainCache;
    if (cached != null) return cached;
    final textFamilies = _normalFontFamilyChain(base);
    return _effectiveFontFamilyChainCache = dedupeFontFamilies([
      textFamilies.first,
      ..._emojiFontChoice.fontFamilies,
      ...textFamilies.skip(1),
    ]);
  }

  TextStyle applyAppTextStyle(TextStyle base, {bool boldText = false}) {
    final cacheKey = (base, boldText);
    final cached = _appTextStyleCache[cacheKey];
    if (cached != null) return cached;
    final styled = _computeAppTextStyle(base, boldText: boldText);
    // The distinct base styles are the ~30 entries of two TextThemes plus the
    // root body style; the guard only exists so an unexpected caller cannot
    // grow this without bound.
    if (_appTextStyleCache.length >= 128) _appTextStyleCache.clear();
    _appTextStyleCache[cacheKey] = styled;
    return styled;
  }

  TextStyle _computeAppTextStyle(TextStyle base, {bool boldText = false}) {
    final families = effectiveFontFamilyChain(base);
    final weightedBase = base.copyWith(
      fontWeight: AppTextWeight.forSystemBoldText(
        base.fontWeight ?? FontWeight.w400,
        boldText: boldText,
      ),
    );
    if (families.isEmpty) return weightedBase;
    final first = families.first;
    final googleFamily = _googleFamilyFor(first);
    final withPrimary = googleFamily == null
        ? weightedBase.copyWith(fontFamily: first)
        : GoogleFonts.getFont(googleFamily, textStyle: weightedBase);
    return withPrimary.copyWith(
      fontFamilyFallback: dedupeFontFamilies([
        ..._emojiFontChoice.fontFamilies,
        ...?withPrimary.fontFamilyFallback,
        ...families.skip(1),
      ]),
    );
  }

  TextTheme applyAppTextTheme(TextTheme textTheme, {bool boldText = false}) {
    TextStyle? apply(TextStyle? style) =>
        style == null ? null : applyAppTextStyle(style, boldText: boldText);
    return textTheme.copyWith(
      displayLarge: apply(textTheme.displayLarge),
      displayMedium: apply(textTheme.displayMedium),
      displaySmall: apply(textTheme.displaySmall),
      headlineLarge: apply(textTheme.headlineLarge),
      headlineMedium: apply(textTheme.headlineMedium),
      headlineSmall: apply(textTheme.headlineSmall),
      titleLarge: apply(textTheme.titleLarge),
      titleMedium: apply(textTheme.titleMedium),
      titleSmall: apply(textTheme.titleSmall),
      bodyLarge: apply(textTheme.bodyLarge),
      bodyMedium: apply(textTheme.bodyMedium),
      bodySmall: apply(textTheme.bodySmall),
      labelLarge: apply(textTheme.labelLarge),
      labelMedium: apply(textTheme.labelMedium),
      labelSmall: apply(textTheme.labelSmall),
    );
  }

  TextStyle codeTextStyle(TextStyle base) {
    final code = _monospaceFontChoice.applyTextStyle(
      base,
      customFamily: _customMonospaceFontFamily,
    );
    return code.copyWith(
      fontFamilyFallback: dedupeFontFamilies([
        ...?code.fontFamilyFallback,
        ..._emojiFontChoice.fontFamilies,
        ..._normalFontFamilyChain(base),
      ]),
    );
  }

  /// Google-hosted families indexed by every name they answer to. The linear
  /// scan this replaces walked 60 enum entries and evaluated `fontFamily` on
  /// each, allocating a `replaceAll` String per Google entry.
  ///
  /// Only Google entries are indexed: a non-Google entry resolved to its own
  /// null `googleFamily`, which is what a miss returns anyway, and no
  /// non-Google family name collides with a Google one.
  static final Map<String, String> _googleFamilyByFamilyName = {
    for (final font in AppFontChoice.values)
      if (font.googleFamily case final google?) ...{
        google: google,
        font.fontFamily: google,
      },
    for (final font in AppMonospaceFontChoice.values)
      if (font.googleFamily case final google?) ...{
        google: google,
        font.fontFamily: google,
      },
  };

  static String? _googleFamilyFor(String family) {
    final storedGoogleFamily = decodeGoogleFontFamily(family);
    if (storedGoogleFamily != null) return storedGoogleFamily;
    return _googleFamilyByFamilyName[family];
  }

  set mode(AppearanceMode value) {
    if (_mode == value) return;
    _mode = value;
    _prefs.setString(_scopedThemeKey(_modeKey), value.name);
    notifyListeners();
  }

  /// The active scope's accent / brand color.
  set brandColor(Color value) {
    if (_brandColor == value) return;
    _brandColor = value;
    _prefs.setInt(_scopedThemeKey(_brandKey), value.toARGB32());
    AppTheme.applyBrand(value);
    notifyListeners();
  }

  void installCloudTheme(TelegramCloudTheme theme, {Brightness? brightness}) {
    final target =
        brightness ?? (theme.isDark ? Brightness.dark : Brightness.light);
    if (target == Brightness.dark) {
      _darkCloudTheme = theme;
    } else {
      _lightCloudTheme = theme;
    }
    _addInstalledCloudTheme(theme);
    _persistCloudThemes();
    notifyListeners();
  }

  set messageBubblesEnabled(bool value) {
    if (_messageBubblesEnabled == value) return;
    _messageBubblesEnabled = value;
    _prefs.setBool(_scopedThemeKey(_messageBubblesEnabledKey), value);
    notifyListeners();
  }

  set messageBubbleBackground(MessageBubbleBackground value) {
    if (value == MessageBubbleBackground.custom &&
        _customMessageBubbleBackground == null) {
      return;
    }
    if (_messageBubbleBackground == value) return;
    _messageBubbleBackground = value;
    _prefs.setString(_scopedThemeKey(_messageBubbleBackgroundKey), value.name);
    notifyListeners();
  }

  set messageBubbleApplicationScope(MessageBubbleApplicationScope value) {
    if (_messageBubbleApplicationScope == value) return;
    _messageBubbleApplicationScope = value;
    _prefs.setString(
      _scopedThemeKey(_messageBubbleApplicationScopeKey),
      value.name,
    );
    notifyListeners();
  }

  void installCustomMessageBubbleBackground(
    CustomMessageBubbleBackground value,
  ) {
    _customMessageBubbleBackground = value;
    _messageBubblesEnabled = true;
    _messageBubbleBackground = MessageBubbleBackground.custom;
    _prefs.setBool(_scopedThemeKey(_messageBubblesEnabledKey), true);
    _prefs.setString(
      _scopedThemeKey(_customMessageBubbleBackgroundKey),
      jsonEncode(value.toJson()),
    );
    _prefs.setString(
      _scopedThemeKey(_messageBubbleBackgroundKey),
      MessageBubbleBackground.custom.name,
    );
    notifyListeners();
  }

  void clearCustomMessageBubbleBackground() {
    if (_customMessageBubbleBackground == null &&
        _messageBubbleBackground != MessageBubbleBackground.custom) {
      return;
    }
    _customMessageBubbleBackground = null;
    _prefs.remove(_scopedThemeKey(_customMessageBubbleBackgroundKey));
    if (_messageBubbleBackground == MessageBubbleBackground.custom) {
      _messageBubbleBackground = MessageBubbleBackground.standard;
      _prefs.setString(
        _scopedThemeKey(_messageBubbleBackgroundKey),
        MessageBubbleBackground.standard.name,
      );
    }
    notifyListeners();
  }

  void clearCloudTheme([Brightness? brightness]) {
    if (brightness == Brightness.light) {
      _lightCloudTheme = null;
    } else if (brightness == Brightness.dark) {
      _darkCloudTheme = null;
    } else {
      _lightCloudTheme = null;
      _darkCloudTheme = null;
    }
    _persistCloudThemes();
    notifyListeners();
  }

  void _addInstalledCloudTheme(TelegramCloudTheme theme) {
    _installedCloudThemes.removeWhere((item) => item.slug == theme.slug);
    _installedCloudThemes.add(theme);
  }

  /// Replaces cached cloud-theme payloads with freshly hydrated Telegram
  /// copies. This also refreshes active light/dark selections with the same
  /// slug, which is important because persisted wallpaper paths point into an
  /// app container that may no longer exist after reinstalling the app.
  void synchronizeInstalledCloudThemes(Iterable<TelegramCloudTheme> themes) {
    final refreshed = <String, TelegramCloudTheme>{};
    for (final theme in themes) {
      if (theme.slug.isEmpty || theme.slug.startsWith('builtin:')) continue;
      refreshed[theme.slug] = theme;
    }
    _installedCloudThemes = refreshed.values.toList(growable: true);
    _installedCloudThemeRevision += 1;
    final light = _lightCloudTheme;
    if (light != null && refreshed.containsKey(light.slug)) {
      _lightCloudTheme = refreshed[light.slug];
    }
    final dark = _darkCloudTheme;
    if (dark != null && refreshed.containsKey(dark.slug)) {
      _darkCloudTheme = refreshed[dark.slug];
    }
    _persistCloudThemes();
    notifyListeners();
  }

  void _persistCloudThemes() {
    void persist(String key, TelegramCloudTheme? theme) {
      if (theme == null) {
        _prefs.remove(key);
      } else {
        _prefs.setString(key, jsonEncode(theme.toJson()));
      }
    }

    persist(_scopedThemeKey(_lightCloudThemeKey), _lightCloudTheme);
    persist(_scopedThemeKey(_darkCloudThemeKey), _darkCloudTheme);
    _prefs.setString(
      _installedCloudThemeCacheKey(),
      jsonEncode(_installedCloudThemes.map((theme) => theme.toJson()).toList()),
    );
  }

  void _restoreUiBeforeCloudTheme() {
    _mode = AppearanceMode.values.firstWhere(
      (value) => value.name == _prefs.getString(_preCloudThemeModeKey),
      orElse: () => AppearanceMode.system,
    );
    _brandColor = Color(
      _prefs.getInt(_preCloudThemeBrandKey) ??
          (0xFF000000 | AppTheme.defaultBrand),
    );
    _prefs.setString(_scopedThemeKey(_modeKey), _mode.name);
    _prefs.setInt(_scopedThemeKey(_brandKey), _brandColor.toARGB32());
    _prefs.remove(_preCloudThemeModeKey);
    _prefs.remove(_preCloudThemeBrandKey);
    AppTheme.applyBrand(_brandColor);
  }

  set fontChoice(AppFontChoice value) {
    _fontChoice = value;
    _invalidateFontCaches();
    _prefs.setString(_fontChoiceKey, value.name);
    notifyListeners();
  }

  set cjkFontChoice(AppFontChoice value) {
    if (!value.isCjk) return;
    _cjkFontChoice = value;
    _invalidateFontCaches();
    _prefs.setString(_cjkFontChoiceKey, value.name);
    notifyListeners();
  }

  set customPrimaryFontFamily(String value) {
    _customPrimaryFontFamily = value.trim();
    _invalidateFontCaches();
    _prefs.setString(_customPrimaryFontFamilyKey, _customPrimaryFontFamily);
    notifyListeners();
  }

  set customCjkFontFamily(String value) {
    _customCjkFontFamily = value.trim();
    _invalidateFontCaches();
    _prefs.setString(_customCjkFontFamilyKey, _customCjkFontFamily);
    notifyListeners();
  }

  set monospaceFontChoice(AppMonospaceFontChoice value) {
    _monospaceFontChoice = value;
    _invalidateFontCaches();
    _prefs.setString(_monospaceFontChoiceKey, value.name);
    notifyListeners();
  }

  set customMonospaceFontFamily(String value) {
    _customMonospaceFontFamily = value.trim();
    _invalidateFontCaches();
    _prefs.setString(_customMonospaceFontFamilyKey, _customMonospaceFontFamily);
    notifyListeners();
  }

  void useSystemEmojiFont() {
    _emojiFontSelectionRevision++;
    _emojiFontChoice = EmojiFontChoice.system;
    _invalidateFontCaches();
    _prefs.setString(_emojiFontChoiceKey, EmojiFontChoice.system.key);
    _prefs.remove(_emojiFontLabelKey);
    _prefs.remove(_emojiFontLicenseKey);
    notifyListeners();
  }

  Future<void> loadSelectedEmojiFontIfAvailable() async {
    final key = _emojiFontChoice.key;
    if (key == EmojiFontChoice.system.key ||
        _emojiFontChoice.fontFamily != null) {
      return;
    }
    final revision = _emojiFontSelectionRevision;
    final family = await _emojiFontCatalog.loadCachedOrDownload(key);
    if (family == null ||
        revision != _emojiFontSelectionRevision ||
        _emojiFontChoice.key != key) {
      return;
    }
    _emojiFontChoice = EmojiFontChoice(
      key: key,
      label: _emojiFontChoice.label,
      license: _emojiFontChoice.license,
      fontFamily: family,
    );
    _invalidateFontCaches();
    notifyListeners();
  }

  Future<void> setEmojiFont(EmojiFontManifestEntry entry) async {
    final revision = ++_emojiFontSelectionRevision;
    final family = await _emojiFontCatalog.downloadAndLoad(entry);
    if (revision != _emojiFontSelectionRevision) return;
    _emojiFontChoice = EmojiFontChoice(
      key: entry.key,
      label: entry.label,
      license: entry.license,
      fontFamily: family,
    );
    _invalidateFontCaches();
    unawaited(_prefs.setString(_emojiFontChoiceKey, entry.key));
    unawaited(_prefs.setString(_emojiFontLabelKey, entry.label));
    unawaited(_prefs.setString(_emojiFontLicenseKey, entry.license));
    notifyListeners();
  }

  /// Registers an already-cached selected emoji font before the first frame.
  /// Missing cache entries are intentionally not downloaded on the launch
  /// path; the normal idle loader can fetch those without delaying startup.
  static Future<void> preloadCachedEmojiFont(SharedPreferences prefs) async {
    final storedKey = prefs.getString(_emojiFontChoiceKey);
    final migrated =
        (prefs.getInt(_emojiFontSchemaKey) ?? 0) >= _emojiFontSchemaVersion ||
        prefs.getString(_emojiFontLabelKey) != null;
    final key = _normalizeEmojiFontKey(storedKey, migrated: migrated);
    if (key == EmojiFontChoice.system.key) return;
    try {
      await EmojiFontCatalog.shared.loadCached(key);
    } catch (error) {
      debugPrint(
        '[theme_controller] cached emoji font preload failed '
        'type=${error.runtimeType}',
      );
    }
  }

  /// Bumped when stored emoji font keys need another one-shot migration.
  static const _emojiFontSchemaVersion = 1;

  /// Names of the pre-catalog `EmojiFontChoice` enum mapped onto catalog keys.
  /// `noto` meant the monochrome font back then and means the color one in the
  /// catalog, so this may only ever be applied to a pre-catalog preference —
  /// see [_emojiFontKeysAreMigrated].
  static const _legacyEmojiFontKeys = {
    'notoColor': 'noto',
    'noto': 'noto-mono',
  };

  /// Whether the stored emoji font key already uses catalog keys. Only the
  /// catalog writes a label alongside the key, so its presence identifies a
  /// preference that must be left alone even before the schema was stamped.
  bool get _emojiFontKeysAreMigrated =>
      (_prefs.getInt(_emojiFontSchemaKey) ?? 0) >= _emojiFontSchemaVersion ||
      _prefs.getString(_emojiFontLabelKey) != null;

  static String _normalizeEmojiFontKey(String? value, {bool migrated = true}) {
    final key = value?.trim() ?? '';
    if (key.isEmpty || key == EmojiFontChoice.system.key) {
      return EmojiFontChoice.system.key;
    }
    return migrated ? key : _legacyEmojiFontKeys[key] ?? key;
  }

  void setFontFallbackChain(List<String> value) {
    _fontFallbackChain = dedupeFontFamilies(value);
    _invalidateFontCaches();
    _prefs.setStringList(_fontFallbackChainKey, _fontFallbackChain);
    notifyListeners();
  }

  Future<void> _normalizeStoredPlatformFontFamilies() async {
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    final beforePrimary = _customPrimaryFontFamily;
    final beforeCjk = _customCjkFontFamily;
    final beforeMono = _customMonospaceFontFamily;
    final beforeChain = [..._fontFallbackChain];
    final values = [beforePrimary, beforeCjk, beforeMono, ...beforeChain];
    final normalized = await SystemFontCatalog.normalizeFamilies(values);
    if (normalized.length != values.length) return;
    if (_customPrimaryFontFamily != beforePrimary ||
        _customCjkFontFamily != beforeCjk ||
        _customMonospaceFontFamily != beforeMono ||
        !listEquals(_fontFallbackChain, beforeChain)) {
      return;
    }

    final nextPrimary = normalized[0];
    final nextCjk = normalized[1];
    final nextMono = normalized[2];
    final nextChain = dedupeFontFamilies(normalized.skip(3));
    var changed = false;
    if (nextPrimary != _customPrimaryFontFamily) {
      _customPrimaryFontFamily = nextPrimary;
      unawaited(_prefs.setString(_customPrimaryFontFamilyKey, nextPrimary));
      changed = true;
    }
    if (nextCjk != _customCjkFontFamily) {
      _customCjkFontFamily = nextCjk;
      unawaited(_prefs.setString(_customCjkFontFamilyKey, nextCjk));
      changed = true;
    }
    if (nextMono != _customMonospaceFontFamily) {
      _customMonospaceFontFamily = nextMono;
      unawaited(_prefs.setString(_customMonospaceFontFamilyKey, nextMono));
      changed = true;
    }
    if (!listEquals(nextChain, _fontFallbackChain)) {
      _fontFallbackChain = nextChain;
      unawaited(_prefs.setStringList(_fontFallbackChainKey, nextChain));
      changed = true;
    }
    if (changed) {
      _invalidateFontCaches();
      notifyListeners();
    }
  }

  void addFontToFallbackChain(String family) {
    setFontFallbackChain([..._fontFallbackChain, family]);
  }

  void removeFontFromFallbackChainAt(int index) {
    if (index < 0 || index >= _fontFallbackChain.length) return;
    final next = [..._fontFallbackChain]..removeAt(index);
    setFontFallbackChain(next);
  }

  void moveFontInFallbackChain(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _fontFallbackChain.length) return;
    final next = [..._fontFallbackChain];
    newIndex = newIndex.clamp(0, next.length - 1);
    final item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    setFontFallbackChain(next);
  }

  set fontScale(double value) {
    final next = value.clamp(minFontScale, maxFontScale);
    if (_fontScale == next) return;
    _fontScale = next;
    _fontScaleNeedsPersist = true;
    _scheduleScalePersist();
    notifyListeners();
  }

  set interfaceScale(double value) {
    // Guard the stored value, not the argument: the getter squares it back, so
    // a round-tripped double would never compare equal to what came in.
    final next = math.sqrt(value.clamp(minInterfaceScale, maxInterfaceScale));
    if (_interfaceScale == next) return;
    _interfaceScale = next;
    _interfaceScaleNeedsPersist = true;
    _scheduleScalePersist();
    notifyListeners();
  }

  /// The appearance sliders assign at pointer rate and every SharedPreferences
  /// write rewrites the whole store (which also holds the cloud-theme blobs),
  /// so the in-memory value moves now and the disk write waits for the drag.
  /// The delay stays under the desktop settings-window sync debounce (350 ms),
  /// which reloads the primary engine's preferences from the store.
  void _scheduleScalePersist() {
    _scalePersistTimer?.cancel();
    _scalePersistTimer = Timer(
      const Duration(milliseconds: 200),
      _persistScales,
    );
  }

  /// Only the scale that actually moved is written: on desktop the settings
  /// window runs its own engine with its own controller, so writing back a
  /// scale this instance never changed can push a stale cached value over one
  /// the other window just stored.
  void _persistScales() {
    _scalePersistTimer = null;
    if (_fontScaleNeedsPersist) {
      _fontScaleNeedsPersist = false;
      _prefs.setDouble(_fontKey, _fontScale);
    }
    if (_interfaceScaleNeedsPersist) {
      _interfaceScaleNeedsPersist = false;
      _prefs.setDouble(_interfaceScaleKey, _interfaceScale);
    }
  }

  @override
  void dispose() {
    if (_scalePersistTimer != null) {
      _scalePersistTimer!.cancel();
      _persistScales();
    }
    super.dispose();
  }

  set circularGroupAvatars(bool value) {
    _circularGroupAvatars = value;
    _prefs.setBool(_groupAvatarCircleKey, value);
    notifyListeners();
  }

  set animateAvatars(bool value) {
    if (_animateAvatars == value) return;
    _animateAvatars = value;
    _prefs.setBool(_animateAvatarsKey, value);
    notifyListeners();
  }

  set animateStatusEmoji(bool value) {
    if (_animateStatusEmoji == value) return;
    _animateStatusEmoji = value;
    _prefs.setBool(_animateStatusEmojiKey, value);
    notifyListeners();
  }

  set chatFolderDisplayMode(ChatFolderDisplayMode value) {
    if (_chatFolderDisplayMode == value) return;
    _chatFolderDisplayMode = value;
    _prefs.setString(_chatFolderDisplayModeKey, value.name);
    notifyListeners();
  }

  set chatListSwipeMode(ChatListSwipeMode value) {
    if (_chatListSwipeMode == value) return;
    _chatListSwipeMode = value;
    _prefs.setString(_chatListSwipeModeKey, value.name);
    notifyListeners();
  }

  set showChatListSearch(bool value) {
    _showChatListSearch = value;
    _prefs.setBool(_chatListSearchKey, value);
    notifyListeners();
  }

  set hideSidebarPhone(bool value) {
    _hideSidebarPhone = value;
    _prefs.setBool(_hideSidebarPhoneKey, value);
    notifyListeners();
  }

  set showMemberTags(bool value) {
    _showMemberTags = value;
    _prefs.setBool(_memberTagsKey, value);
    notifyListeners();
  }

  set showPlainMemberRoleTags(bool value) {
    if (_showPlainMemberRoleTags == value) return;
    _showPlainMemberRoleTags = value;
    _prefs.setBool(_plainMemberRoleTagsKey, value);
    notifyListeners();
  }

  set showNameColors(bool value) {
    chatListNameColorAudience = value
        ? NameColorAudience.allUsers
        : NameColorAudience.nobody;
  }

  set showPremiumEmojiStatus(bool value) {
    chatListStatusEmojiMode = value
        ? StatusEmojiDisplayMode.static
        : StatusEmojiDisplayMode.none;
  }

  set showChatNameColors(bool value) {
    chatNameColorAudience = value
        ? NameColorAudience.allUsers
        : NameColorAudience.nobody;
  }

  set showChatPremiumEmojiStatus(bool value) {
    chatStatusEmojiMode = value
        ? StatusEmojiDisplayMode.static
        : StatusEmojiDisplayMode.none;
  }

  set chatListNameColorAudience(NameColorAudience value) {
    if (_chatListNameColorAudience == value) return;
    _chatListNameColorAudience = value;
    _prefs.setString(_chatListNameColorAudienceKey, value.name);
    notifyListeners();
  }

  set chatNameColorAudience(NameColorAudience value) {
    if (_chatNameColorAudience == value) return;
    _chatNameColorAudience = value;
    _prefs.setString(_chatNameColorAudienceKey, value.name);
    notifyListeners();
  }

  set chatListStatusEmojiMode(StatusEmojiDisplayMode value) {
    if (_chatListStatusEmojiMode == value) return;
    _chatListStatusEmojiMode = value;
    _prefs.setString(_chatListStatusEmojiModeKey, value.name);
    notifyListeners();
  }

  set chatStatusEmojiMode(StatusEmojiDisplayMode value) {
    if (_chatStatusEmojiMode == value) return;
    _chatStatusEmojiMode = value;
    _prefs.setString(_chatStatusEmojiModeKey, value.name);
    notifyListeners();
  }

  set senderNameReadabilityMode(SenderNameReadabilityMode value) {
    if (_senderNameReadabilityMode == value) return;
    _senderNameReadabilityMode = value;
    _prefs.setString(_senderNameReadabilityModeKey, value.name);
    notifyListeners();
  }

  set showMessageMetaIndicators(bool value) {
    _showMessageMetaIndicators = value;
    _prefs.setBool(_messageMetaIndicatorsKey, value);
    notifyListeners();
  }

  set alwaysShowMessageTime(bool value) {
    if (_alwaysShowMessageTime == value) return;
    _alwaysShowMessageTime = value;
    _prefs.setBool(_alwaysShowMessageTimeKey, value);
    notifyListeners();
  }

  set mobileMessageActionMenuStyle(MobileMessageActionMenuStyle value) {
    if (_mobileMessageActionMenuStyle == value) return;
    _mobileMessageActionMenuStyle = value;
    _prefs.setString(_mobileMessageActionMenuStyleKey, value.name);
    notifyListeners();
  }

  set enterToSend(bool value) {
    if (_enterToSend == value) return;
    _enterToSend = value;
    _prefs.setBool(_enterToSendKey, value);
    notifyListeners();
  }

  set openChatsAtLatest(bool value) {
    _openChatsAtLatest = value;
    _prefs.setBool(_openChatsAtLatestKey, value);
    notifyListeners();
  }

  set preserveSenderWhenRepeating(bool value) {
    if (_preserveSenderWhenRepeating == value) return;
    _preserveSenderWhenRepeating = value;
    _prefs.setBool(_preserveSenderWhenRepeatingKey, value);
    notifyListeners();
  }

  set quickRepliesEnabled(bool value) {
    if (_quickRepliesEnabled == value) return;
    _quickRepliesEnabled = value;
    _prefs.setBool(_quickRepliesEnabledKey, value);
    notifyListeners();
  }

  void setQuickReactions(Iterable<QuickReactionChoice> value) {
    final normalized = _normalizeQuickReactions(value);
    if (normalized.isEmpty || listEquals(normalized, _quickReactions)) return;
    _quickReactions = normalized;
    _prefs.setStringList(
      _quickReactionsKey,
      normalized.map((reaction) => reaction.storageValue).toList(),
    );
    notifyListeners();
  }

  static List<QuickReactionChoice> _normalizeQuickReactions(
    Iterable<QuickReactionChoice> value,
  ) {
    final result = <QuickReactionChoice>[];
    for (final reaction in value) {
      if ((!reaction.isCustom && reaction.emoji.isEmpty) ||
          result.contains(reaction)) {
        continue;
      }
      result.add(reaction);
      if (result.length == 9) break;
    }
    return result;
  }

  set groupImageMessages(bool value) {
    _groupImageMessages = value;
    _prefs.setBool(_groupImageMessagesKey, value);
    notifyListeners();
  }

  set hideBlockedUserMessages(bool value) {
    _hideBlockedUserMessages = value;
    _prefs.setBool(_hideBlockedUserMessagesKey, value);
    notifyListeners();
  }

  set showChannelsTab(bool value) {
    _showChannelsTab = value;
    _prefs.setBool(_showChannelsTabKey, value);
    notifyListeners();
  }

  set showMomentsTab(bool value) {
    _showMomentsTab = value;
    _prefs.setBool(_showMomentsTabKey, value);
    notifyListeners();
  }

  set showShortVideos(bool value) {
    _showShortVideos = value;
    _prefs.setBool(_showShortVideosKey, value);
    notifyListeners();
  }

  set communitiesEnabled(bool value) {
    if (_communitiesEnabled == value) return;
    _communitiesEnabled = value;
    _prefs.setBool(_communitiesEnabledKey, value);
    notifyListeners();
  }

  set archivedChatsDisplayMode(ArchivedChatsDisplayMode value) {
    _archivedChatsDisplayMode = value;
    _prefs.setString(_archivedChatsDisplayModeKey, value.name);
    notifyListeners();
  }

  set unreadBadgeMode(UnreadBadgeMode value) {
    _unreadBadgeMode = value;
    _prefs.setString(_unreadBadgeModeKey, value.name);
    notifyListeners();
  }

  set unreadBadgeShowsChatCount(bool value) {
    unreadBadgeMode = value ? UnreadBadgeMode.chats : UnreadBadgeMode.messages;
  }

  set unreadBadgeOverflowMode(UnreadBadgeOverflowMode value) {
    _unreadBadgeOverflowMode = value;
    _prefs.setString(_unreadBadgeOverflowModeKey, value.name);
    notifyListeners();
  }

  set capUnreadBadgeAt99(bool value) {
    unreadBadgeOverflowMode = value
        ? UnreadBadgeOverflowMode.capped
        : UnreadBadgeOverflowMode.exact;
  }
}
