//
//  theme_controller.dart
//
//  Drives the app-wide appearance (跟随系统 / 浅色 / 深色), text scale, and chat
//  appearance preferences. Values are persisted in SharedPreferences and
//  applied through providers at the app root.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/preview_texts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/quick_reaction_choice.dart';
import '../components/app_icons.dart';
import 'app_theme.dart';
import 'emoji_font_catalog.dart';
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

enum ChatListSwipeBehavior {
  chatActions(AppStringKeys.gesturesChatActions, HeroAppIcons.message),
  switchFolders(AppStringKeys.gesturesSwitchFolders, HeroAppIcons.folder);

  const ChatListSwipeBehavior(this.label, this._icon);
  final String label;
  final AppIconData _icon;

  IconData get icon => _icon.data;
}

enum ThreeFingerSwipeBehavior {
  switchFolders(AppStringKeys.gesturesSwitchFolders, HeroAppIcons.folder),
  switchAccounts(AppStringKeys.gesturesSwitchAccounts, HeroAppIcons.users),
  disabled(AppStringKeys.gesturesDoNothing, HeroAppIcons.ban);

  const ThreeFingerSwipeBehavior(this.label, this._icon);
  final String label;
  final AppIconData _icon;

  IconData get icon => _icon.data;
}

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

class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs, {int initialAccountSlot = 0})
    : _activeAccountSlot = initialAccountSlot {
    // Theming existed unconditionally before this preference was introduced,
    // so both new installs and migrated users retain the established behavior.
    _themingEnabled = _prefs.getBool(_themingEnabledKey) ?? true;
    _mode = AppearanceMode.values.firstWhere(
      (m) => m.name == _prefs.getString(_modeKey),
      orElse: () => AppearanceMode.system,
    );
    _brandColor = Color(
      _prefs.getInt(_brandKey) ?? (0xFF000000 | AppTheme.defaultBrand),
    );
    _usePerAccountTheming = _prefs.getBool(_usePerAccountThemingKey) ?? false;
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
    try {
      final encodedThemes = _prefs.getString(_installedCloudThemesKey);
      final decodedThemes = encodedThemes == null
          ? const <Object?>[]
          : jsonDecode(encodedThemes) as List;
      for (final value in decodedThemes) {
        final theme = TelegramCloudTheme.fromJson(value);
        if (theme != null) _addInstalledCloudTheme(theme);
      }
    } catch (_) {}
    for (final theme in [legacyCloudTheme, _lightCloudTheme, _darkCloudTheme]) {
      if (theme != null) _addInstalledCloudTheme(theme);
    }
    if (legacyCloudTheme != null) {
      _prefs.remove(_scopedThemeKey(_cloudThemeKey));
      _persistCloudThemes();
    }
    final hadTelegramUiPreference = _prefs.containsKey(
      _scopedThemeKey(_useTelegramThemeForUiKey),
    );
    _useTelegramThemeForUi =
        _prefs.getBool(_scopedThemeKey(_useTelegramThemeForUiKey)) ?? false;
    if (!hasCloudTheme) {
      _useTelegramThemeForUi = false;
      _prefs.setBool(_scopedThemeKey(_useTelegramThemeForUiKey), false);
    } else if (!hadTelegramUiPreference &&
        (_prefs.containsKey(_preCloudThemeModeKey) ||
            _prefs.containsKey(_preCloudThemeBrandKey))) {
      // Themes installed by older builds always replaced the app palette.
      // Migrate those users to the new, explicitly disabled-by-default mode.
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
    final emojiFontKey = _normalizeEmojiFontKey(
      _prefs.getString(_emojiFontChoiceKey),
    );
    _emojiFontChoice = EmojiFontChoice(
      key: emojiFontKey,
      label: emojiFontKey == EmojiFontChoice.system.key
          ? EmojiFontChoice.system.label
          : _prefs.getString(_emojiFontLabelKey) ?? emojiFontKey,
      license: _prefs.getString(_emojiFontLicenseKey),
    );
    _fontFallbackChain = dedupeFontFamilies(
      _prefs.getStringList(_fontFallbackChainKey) ?? const <String>[],
    );
    unawaited(_normalizeStoredPlatformFontFamilies());
    _fontScale = _prefs.getDouble(_fontKey) ?? 1.0;
    _interfaceScale = _prefs.getDouble(_interfaceScaleKey) ?? 1.0;
    _circularGroupAvatars = _prefs.getBool(_groupAvatarCircleKey) ?? true;
    _animateAvatars = _prefs.getBool(_animateAvatarsKey) ?? true;
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
    _showChatListSearch = _prefs.getBool(_chatListSearchKey) ?? true;
    final storedSwipeBehavior = _prefs.getString(_chatListSwipeBehaviorKey);
    _chatListSwipeBehavior = ChatListSwipeBehavior.values.firstWhere(
      (behavior) => behavior.name == storedSwipeBehavior,
      orElse: () {
        final legacySwitchesFolders =
            (_prefs.getBool(_disableChatListSwipeActionsKey) ?? false) &&
            (_prefs.getBool(_chatListFolderSwipeSwitchingKey) ?? false);
        return legacySwitchesFolders
            ? ChatListSwipeBehavior.switchFolders
            : ChatListSwipeBehavior.chatActions;
      },
    );
    if (storedSwipeBehavior == null) {
      _prefs.setString(_chatListSwipeBehaviorKey, _chatListSwipeBehavior.name);
    }
    _chatListHoldSwipeActions =
        _prefs.getBool(_chatListHoldSwipeActionsKey) ?? false;
    final storedThreeFingerBehavior = _prefs.getString(
      _threeFingerSwipeBehaviorKey,
    );
    _threeFingerSwipeBehavior = ThreeFingerSwipeBehavior.values.firstWhere(
      (behavior) => behavior.name == storedThreeFingerBehavior,
      orElse: () => ThreeFingerSwipeBehavior.switchFolders,
    );
    _displayOwnChatAsFavorites =
        _prefs.getBool(_displayOwnChatAsFavoritesKey) ?? false;
    _hideSidebarPhone = _prefs.getBool(_hideSidebarPhoneKey) ?? false;
    _showMemberTags = _prefs.getBool(_memberTagsKey) ?? false;
    _showPlainMemberRoleTags = _prefs.getBool(_plainMemberRoleTagsKey) ?? false;
    _showPremiumNameColors = _prefs.getBool(_premiumNameColorsKey) ?? true;
    _showPremiumEmojiStatus = _prefs.getBool(_premiumEmojiStatusKey) ?? true;
    _showChatPremiumNameColors =
        _prefs.getBool(_chatPremiumNameColorsKey) ?? true;
    _showChatPremiumEmojiStatus =
        _prefs.getBool(_chatPremiumEmojiStatusKey) ?? true;
    _showSenderNameReadabilityPlate =
        _prefs.getBool(_senderNameReadabilityPlateKey) ?? false;
    _showMessageMetaIndicators =
        _prefs.getBool(_messageMetaIndicatorsKey) ?? false;
    _alwaysShowMessageTime = _prefs.getBool(_alwaysShowMessageTimeKey) ?? false;
    _openChatsAtLatest = _prefs.getBool(_openChatsAtLatestKey) ?? false;
    _preserveSenderWhenRepeating =
        _prefs.getBool(_preserveSenderWhenRepeatingKey) ?? true;
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
  static const _useTelegramThemeForUiKey = 'useTelegramThemeForUi';
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
  static const _fontFallbackChainKey = 'fontFallbackChain';
  static const _fontKey = 'fontScale';
  static const _interfaceScaleKey = 'interfaceScale';
  static const _groupAvatarCircleKey = 'circularGroupAvatars';
  static const _animateAvatarsKey = 'animateAvatars';
  static const _chatFolderDisplayModeKey = 'chatFolderDisplayMode';
  // Retained only to migrate the former show/hide toggle.
  static const _chatFolderFilterKey = 'showChatFolderFilter';
  static const _chatListSearchKey = 'showChatListSearch';
  static const _disableChatListSwipeActionsKey = 'disableChatListSwipeActions';
  static const _chatListFolderSwipeSwitchingKey =
      'chatListFolderSwipeSwitching';
  static const _chatListSwipeBehaviorKey = 'chatListSwipeBehavior';
  static const _chatListHoldSwipeActionsKey = 'chatListHoldSwipeActions';
  static const _threeFingerSwipeBehaviorKey = 'threeFingerSwipeBehavior';
  static const _displayOwnChatAsFavoritesKey = 'displayOwnChatAsFavorites';
  static const _hideSidebarPhoneKey = 'hideSidebarPhone';
  static const _memberTagsKey = 'showMemberTags';
  static const _plainMemberRoleTagsKey = 'showPlainMemberRoleTags';
  static const _premiumNameColorsKey = 'showPremiumNameColors';
  static const _premiumEmojiStatusKey = 'showPremiumEmojiStatus';
  static const _chatPremiumNameColorsKey = 'showChatPremiumNameColors';
  static const _chatPremiumEmojiStatusKey = 'showChatPremiumEmojiStatus';
  static const _senderNameReadabilityPlateKey =
      'showSenderNameReadabilityPlate';
  static const _messageMetaIndicatorsKey = 'showMessageMetaIndicators';
  static const _alwaysShowMessageTimeKey = 'alwaysShowMessageTime';
  static const _openChatsAtLatestKey = 'openChatsAtLatest';
  static const _preserveSenderWhenRepeatingKey = 'preserveSenderWhenRepeating';
  static const _quickReactionsKey = 'quickReactions';
  static const _groupImageMessagesKey = 'groupImageMessages';
  static const _hideBlockedUserMessagesKey = 'hideBlockedUserMessages';
  static const _showChannelsTabKey = 'showChannelsTab';
  static const _showMomentsTabKey = 'showMomentsTab';
  static const _archivedChatsDisplayModeKey = 'archivedChatsDisplayMode';
  static const _unreadBadgeModeKey = 'unreadBadgeMode';
  static const _unreadBadgeOverflowModeKey = 'unreadBadgeOverflowMode';

  static const double minFontScale = 0.8;
  static const double maxFontScale = 1.4;
  static const double minInterfaceScale = 0.66;
  static const double maxInterfaceScale = 1.50;

  final SharedPreferences _prefs;
  int _activeAccountSlot;
  late bool _usePerAccountTheming;
  late bool _themingEnabled;
  late AppearanceMode _mode;
  late Color _brandColor;
  TelegramCloudTheme? _lightCloudTheme;
  TelegramCloudTheme? _darkCloudTheme;
  late List<TelegramCloudTheme> _installedCloudThemes;
  late bool _useTelegramThemeForUi;
  late AppFontChoice _fontChoice;
  late AppFontChoice _cjkFontChoice;
  late String _customPrimaryFontFamily;
  late String _customCjkFontFamily;
  late AppMonospaceFontChoice _monospaceFontChoice;
  late String _customMonospaceFontFamily;
  late EmojiFontChoice _emojiFontChoice;
  late List<String> _fontFallbackChain;
  late double _fontScale;
  late double _interfaceScale;
  late bool _circularGroupAvatars;
  late bool _animateAvatars;
  late ChatFolderDisplayMode _chatFolderDisplayMode;
  bool _showChatListSearch = true;
  late ChatListSwipeBehavior _chatListSwipeBehavior;
  bool _chatListHoldSwipeActions = false;
  late ThreeFingerSwipeBehavior _threeFingerSwipeBehavior;
  bool _displayOwnChatAsFavorites = false;
  bool _hideSidebarPhone = false;
  bool _showMemberTags = false;
  bool _showPlainMemberRoleTags = false;
  bool _showPremiumNameColors = true;
  bool _showPremiumEmojiStatus = true;
  bool _showChatPremiumNameColors = true;
  bool _showChatPremiumEmojiStatus = true;
  bool _showSenderNameReadabilityPlate = false;
  bool _showMessageMetaIndicators = false;
  bool _alwaysShowMessageTime = false;
  bool _openChatsAtLatest = false;
  bool _preserveSenderWhenRepeating = true;
  late List<QuickReactionChoice> _quickReactions;
  bool _groupImageMessages = true;
  bool _hideBlockedUserMessages = false;
  bool _showChannelsTab = false;
  bool _showMomentsTab = true;
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
  bool get useTelegramThemeForUi => _themingEnabled && _useTelegramThemeForUi;
  bool get usePerAccountTheming => _usePerAccountTheming;

  String _scopedThemeKey(String key, [int? accountSlot]) =>
      _usePerAccountTheming
      ? '$key.account.${accountSlot ?? _activeAccountSlot}'
      : key;

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

  void _loadScopedThemeSelection() {
    _lightCloudTheme = _decodeTheme(_scopedThemeKey(_lightCloudThemeKey));
    _darkCloudTheme = _decodeTheme(_scopedThemeKey(_darkCloudThemeKey));
    _useTelegramThemeForUi =
        _prefs.getBool(_scopedThemeKey(_useTelegramThemeForUiKey)) ?? false;
    if (!hasCloudTheme) _useTelegramThemeForUi = false;
  }

  void setActiveAccountSlot(int value) {
    if (_activeAccountSlot == value) return;
    _activeAccountSlot = value;
    if (!_usePerAccountTheming) return;
    _loadScopedThemeSelection();
    notifyListeners();
  }

  set usePerAccountTheming(bool value) {
    if (_usePerAccountTheming == value) return;
    final light = _lightCloudTheme;
    final dark = _darkCloudTheme;
    final useForUi = _useTelegramThemeForUi;
    _usePerAccountTheming = value;
    _prefs.setBool(_usePerAccountThemingKey, value);
    if (value) {
      final accountHasSelection =
          _prefs.containsKey(_scopedThemeKey(_lightCloudThemeKey)) ||
          _prefs.containsKey(_scopedThemeKey(_darkCloudThemeKey)) ||
          _prefs.containsKey(_scopedThemeKey(_useTelegramThemeForUiKey));
      if (!accountHasSelection) {
        _lightCloudTheme = light;
        _darkCloudTheme = dark;
        _useTelegramThemeForUi = useForUi;
        _persistCloudThemes();
      } else {
        _loadScopedThemeSelection();
      }
    } else {
      _loadScopedThemeSelection();
    }
    notifyListeners();
  }

  /// The reusable semantic palette for every app surface at [brightness].
  /// Chat wallpaper and bubble theming remain independent of this UI opt-in.
  AppColors uiColorsFor(Brightness brightness) {
    final theme = cloudThemeFor(brightness);
    if (useTelegramThemeForUi && theme != null) return theme.uiColors;
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
  ChatFolderDisplayMode get chatFolderDisplayMode => _chatFolderDisplayMode;
  bool get showChatListSearch => _showChatListSearch;
  ChatListSwipeBehavior get chatListSwipeBehavior => _chatListSwipeBehavior;
  bool get chatListHoldSwipeActions => _chatListHoldSwipeActions;
  ThreeFingerSwipeBehavior get threeFingerSwipeBehavior =>
      _threeFingerSwipeBehavior;
  bool get disableChatListSwipeActions =>
      _chatListSwipeBehavior == ChatListSwipeBehavior.switchFolders;
  bool get chatListFolderSwipeSwitching =>
      _chatListSwipeBehavior == ChatListSwipeBehavior.switchFolders;
  bool get displayOwnChatAsFavorites => _displayOwnChatAsFavorites;
  bool get hideSidebarPhone => _hideSidebarPhone;
  bool get showMemberTags => _showMemberTags;
  bool get showPlainMemberRoleTags => _showPlainMemberRoleTags;
  bool get showPremiumNameColors => _showPremiumNameColors;
  bool get showPremiumEmojiStatus => _showPremiumEmojiStatus;
  bool get showChatPremiumNameColors => _showChatPremiumNameColors;
  bool get showChatPremiumEmojiStatus => _showChatPremiumEmojiStatus;
  bool get showSenderNameReadabilityPlate => _showSenderNameReadabilityPlate;
  bool get showMessageMetaIndicators => _showMessageMetaIndicators;
  bool get alwaysShowMessageTime => _alwaysShowMessageTime;
  bool get openChatsAtLatest => _openChatsAtLatest;
  bool get preserveSenderWhenRepeating => _preserveSenderWhenRepeating;
  List<QuickReactionChoice> get quickReactions =>
      List.unmodifiable(_quickReactions);
  bool get groupImageMessages => _groupImageMessages;
  bool get hideBlockedUserMessages => _hideBlockedUserMessages;
  bool get showChannelsTab => _showChannelsTab;
  bool get showMomentsTab => _showMomentsTab;
  ArchivedChatsDisplayMode get archivedChatsDisplayMode =>
      _archivedChatsDisplayMode;
  UnreadBadgeMode get unreadBadgeMode => _unreadBadgeMode;
  bool get unreadBadgeShowsChatCount =>
      _unreadBadgeMode == UnreadBadgeMode.chats;
  UnreadBadgeOverflowMode get unreadBadgeOverflowMode =>
      _unreadBadgeOverflowMode;
  bool get capUnreadBadgeAt99 =>
      _unreadBadgeOverflowMode == UnreadBadgeOverflowMode.capped;

  /// App-wide text scale factor, applied at the root via MediaQuery.textScaler.
  double get fontScale => _fontScale;
  double chatTextSize(double base) =>
      base * _fontScale.clamp(minFontScale, maxFontScale).toDouble();
  double get interfaceScale => _interfaceScale;
  double get rowHeight => AppMetric.listRowHeight;
  double get avatarSize => AppMetric.avatarSize;
  double get navHeaderHeight => AppMetric.navHeaderHeight;
  double scaled(double base) => base;
  List<String> _normalFontFamilyChain([TextStyle? base]) {
    final textFamilies = _fontFallbackChain.isNotEmpty
        ? _fontFallbackChain
        : [AppFontChoice._platformFontFamily()];
    return dedupeFontFamilies([
      ...textFamilies,
      ...AppFontChoice._platformFontFallback(),
    ]);
  }

  List<String> effectiveFontFamilyChain([TextStyle? base]) {
    final textFamilies = _normalFontFamilyChain(base);
    return dedupeFontFamilies([
      textFamilies.first,
      ..._emojiFontChoice.fontFamilies,
      ...textFamilies.skip(1),
    ]);
  }

  TextStyle applyAppTextStyle(TextStyle base, {bool boldText = false}) {
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

  static String? _googleFamilyFor(String family) {
    final storedGoogleFamily = decodeGoogleFontFamily(family);
    if (storedGoogleFamily != null) return storedGoogleFamily;
    for (final font in AppFontChoice.values) {
      if (font.googleFamily == family || font.fontFamily == family) {
        return font.googleFamily;
      }
    }
    for (final font in AppMonospaceFontChoice.values) {
      if (font.googleFamily == family || font.fontFamily == family) {
        return font.googleFamily;
      }
    }
    return null;
  }

  set mode(AppearanceMode value) {
    _mode = value;
    _prefs.setString(_modeKey, value.name);
    notifyListeners();
  }

  /// The app's accent / brand color. Persisted and applied app-wide.
  set brandColor(Color value) {
    _brandColor = value;
    _prefs.setInt(_brandKey, value.toARGB32());
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

  set useTelegramThemeForUi(bool value) {
    _setUseTelegramThemeForUi(value, notify: true);
  }

  void _setUseTelegramThemeForUi(bool value, {required bool notify}) {
    if (value && !hasCloudTheme) return;
    if (_useTelegramThemeForUi == value) return;
    _useTelegramThemeForUi = value;
    _prefs.setBool(_scopedThemeKey(_useTelegramThemeForUiKey), value);
    if (notify) notifyListeners();
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
    if (!hasCloudTheme) {
      _useTelegramThemeForUi = false;
      _prefs.setBool(_scopedThemeKey(_useTelegramThemeForUiKey), false);
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
      _installedCloudThemesKey,
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
    _prefs.setString(_modeKey, _mode.name);
    _prefs.setInt(_brandKey, _brandColor.toARGB32());
    _prefs.remove(_preCloudThemeModeKey);
    _prefs.remove(_preCloudThemeBrandKey);
    AppTheme.applyBrand(_brandColor);
  }

  set fontChoice(AppFontChoice value) {
    _fontChoice = value;
    _prefs.setString(_fontChoiceKey, value.name);
    notifyListeners();
  }

  set cjkFontChoice(AppFontChoice value) {
    if (!value.isCjk) return;
    _cjkFontChoice = value;
    _prefs.setString(_cjkFontChoiceKey, value.name);
    notifyListeners();
  }

  set customPrimaryFontFamily(String value) {
    _customPrimaryFontFamily = value.trim();
    _prefs.setString(_customPrimaryFontFamilyKey, _customPrimaryFontFamily);
    notifyListeners();
  }

  set customCjkFontFamily(String value) {
    _customCjkFontFamily = value.trim();
    _prefs.setString(_customCjkFontFamilyKey, _customCjkFontFamily);
    notifyListeners();
  }

  set monospaceFontChoice(AppMonospaceFontChoice value) {
    _monospaceFontChoice = value;
    _prefs.setString(_monospaceFontChoiceKey, value.name);
    notifyListeners();
  }

  set customMonospaceFontFamily(String value) {
    _customMonospaceFontFamily = value.trim();
    _prefs.setString(_customMonospaceFontFamilyKey, _customMonospaceFontFamily);
    notifyListeners();
  }

  void useSystemEmojiFont() {
    _emojiFontChoice = EmojiFontChoice.system;
    _prefs.setString(_emojiFontChoiceKey, EmojiFontChoice.system.key);
    _prefs.remove(_emojiFontLabelKey);
    _prefs.remove(_emojiFontLicenseKey);
    notifyListeners();
  }

  Future<void> loadSelectedEmojiFontIfAvailable() async {
    final key = _emojiFontChoice.key;
    if (key == EmojiFontChoice.system.key) return;
    final family = await EmojiFontCatalog.shared.loadCached(key);
    if (family == null) return;
    _emojiFontChoice = EmojiFontChoice(
      key: key,
      label: _emojiFontChoice.label,
      license: _emojiFontChoice.license,
      fontFamily: family,
    );
    notifyListeners();
  }

  Future<void> setEmojiFont(EmojiFontManifestEntry entry) async {
    final family = await EmojiFontCatalog.shared.downloadAndLoad(entry);
    _emojiFontChoice = EmojiFontChoice(
      key: entry.key,
      label: entry.label,
      license: entry.license,
      fontFamily: family,
    );
    unawaited(_prefs.setString(_emojiFontChoiceKey, entry.key));
    unawaited(_prefs.setString(_emojiFontLabelKey, entry.label));
    unawaited(_prefs.setString(_emojiFontLicenseKey, entry.license));
    notifyListeners();
  }

  static String _normalizeEmojiFontKey(String? value) {
    return switch (value?.trim()) {
      null || '' || 'system' => EmojiFontChoice.system.key,
      'notoColor' => 'noto',
      'noto' => 'noto-mono',
      'blobmoji' => 'blobmoji',
      'fluent' => 'fluent',
      'fluentMono' => 'fluent-mono',
      'fluentFlat' => 'fluent-flat',
      'twemoji' => 'twemoji',
      'openMoji' => 'openmoji',
      'emojiTwo' => 'emojitwo',
      'tossFace' => 'tossface',
      final key => key,
    };
  }

  void setFontFallbackChain(List<String> value) {
    _fontFallbackChain = dedupeFontFamilies(value);
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
    if (changed) notifyListeners();
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
    _fontScale = value.clamp(minFontScale, maxFontScale);
    _prefs.setDouble(_fontKey, _fontScale);
    notifyListeners();
  }

  set interfaceScale(double value) {
    _interfaceScale = value.clamp(minInterfaceScale, maxInterfaceScale);
    _prefs.setDouble(_interfaceScaleKey, _interfaceScale);
    notifyListeners();
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

  set chatFolderDisplayMode(ChatFolderDisplayMode value) {
    if (_chatFolderDisplayMode == value) return;
    _chatFolderDisplayMode = value;
    _prefs.setString(_chatFolderDisplayModeKey, value.name);
    notifyListeners();
  }

  set displayOwnChatAsFavorites(bool value) {
    _displayOwnChatAsFavorites = value;
    _prefs.setBool(_displayOwnChatAsFavoritesKey, value);
    notifyListeners();
  }

  set showChatListSearch(bool value) {
    _showChatListSearch = value;
    _prefs.setBool(_chatListSearchKey, value);
    notifyListeners();
  }

  set disableChatListSwipeActions(bool value) {
    chatListSwipeBehavior = value
        ? ChatListSwipeBehavior.switchFolders
        : ChatListSwipeBehavior.chatActions;
  }

  set chatListFolderSwipeSwitching(bool value) {
    chatListSwipeBehavior = value
        ? ChatListSwipeBehavior.switchFolders
        : ChatListSwipeBehavior.chatActions;
  }

  set chatListSwipeBehavior(ChatListSwipeBehavior value) {
    if (_chatListSwipeBehavior == value) return;
    _chatListSwipeBehavior = value;
    _prefs.setString(_chatListSwipeBehaviorKey, value.name);
    notifyListeners();
  }

  set chatListHoldSwipeActions(bool value) {
    if (_chatListHoldSwipeActions == value) return;
    _chatListHoldSwipeActions = value;
    _prefs.setBool(_chatListHoldSwipeActionsKey, value);
    notifyListeners();
  }

  set threeFingerSwipeBehavior(ThreeFingerSwipeBehavior value) {
    if (_threeFingerSwipeBehavior == value) return;
    _threeFingerSwipeBehavior = value;
    _prefs.setString(_threeFingerSwipeBehaviorKey, value.name);
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

  set showPremiumNameColors(bool value) {
    _showPremiumNameColors = value;
    _prefs.setBool(_premiumNameColorsKey, value);
    notifyListeners();
  }

  set showPremiumEmojiStatus(bool value) {
    _showPremiumEmojiStatus = value;
    _prefs.setBool(_premiumEmojiStatusKey, value);
    notifyListeners();
  }

  set showChatPremiumNameColors(bool value) {
    _showChatPremiumNameColors = value;
    _prefs.setBool(_chatPremiumNameColorsKey, value);
    notifyListeners();
  }

  set showChatPremiumEmojiStatus(bool value) {
    _showChatPremiumEmojiStatus = value;
    _prefs.setBool(_chatPremiumEmojiStatusKey, value);
    notifyListeners();
  }

  set showSenderNameReadabilityPlate(bool value) {
    if (_showSenderNameReadabilityPlate == value) return;
    _showSenderNameReadabilityPlate = value;
    _prefs.setBool(_senderNameReadabilityPlateKey, value);
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
