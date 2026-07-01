//
//  theme_controller.dart
//
//  Drives the app-wide appearance (跟随系统 / 浅色 / 深色), text scale, and chat
//  appearance preferences. Values are persisted in SharedPreferences and
//  applied through providers at the app root.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../components/app_icons.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'emoji_font_catalog.dart';
import 'system_font_catalog.dart';
import 'package:mithka/l10n/app_localizations.dart';

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

enum GroupAssistantPlacement {
  top(AppStringKeys.themeGroupAssistantTopCollapsed, HeroAppIcons.arrowUp),
  chronological(
    AppStringKeys.themeGroupAssistantSortByTime,
    HeroAppIcons.clock,
  ),
  secondScreen(
    AppStringKeys.themeGroupAssistantSecondPageFirst,
    HeroAppIcons.arrowDown,
  );

  const GroupAssistantPlacement(this.label, this._icon);
  final String label;
  final AppIconData _icon;

  IconData get icon => _icon.data;
}

enum AppFontChoice {
  system(
    AppStringKeys.emojiFontCatalogSystemDefault,
    AppStringKeys.themeMessagePreviewSample,
    cjk: true,
  ),
  apple(
    AppStringKeys.themeApplePingFangFamily,
    AppStringKeys.themeMessagePreviewSample,
    cjk: true,
  ),
  pingFang(
    AppStringKeys.themePingFangSimplifiedChinese,
    AppStringKeys.themeSimplifiedChinesePreview,
    cjk: true,
  ),
  pingFangHk(
    AppStringKeys.themePingFangHongKong,
    AppStringKeys.themeTraditionalHongKongPreview,
    cjk: true,
  ),
  pingFangTw(
    AppStringKeys.themePingFangTraditionalChinese,
    AppStringKeys.themeTraditionalTaiwanPreview,
    cjk: true,
  ),
  hiraginoSansJp(
    'Hiragino [JP]',
    AppStringKeys.themeJapanesePreview,
    cjk: true,
  ),
  customCjk('Custom Font', AppStringKeys.themeCustomHanFontPreview, cjk: true),
  helvetica('Helvetica Neue', 'Message preview Aa 123'),
  avenirNext('Avenir Next', 'Avenir Next Aa 123'),
  avenir('Avenir', 'Avenir Aa 123'),
  futura('Futura', 'Futura Aa 123'),
  optima('Optima', 'Optima Aa 123'),
  palatino('Palatino', 'Palatino Aa 123'),
  georgia('Georgia', 'Georgia Aa 123'),
  timesNewRoman('Times New Roman', 'Times New Roman Aa 123'),
  verdana('Verdana', 'Verdana Aa 123'),
  trebuchetMs('Trebuchet MS', 'Trebuchet MS Aa 123'),
  gillSans('Gill Sans', 'Gill Sans Aa 123'),
  didot('Didot', 'Didot Aa 123'),
  americanTypewriter('American Typewriter', 'American Typewriter Aa 123'),
  menlo('Menlo', AppStringKeys.themeMenloCodePreview),
  courierNew('Courier New', AppStringKeys.themeCourierNewCodePreview),
  custom('Custom Font', 'Custom Font Aa 123'),
  noteworthy('Noteworthy', 'Noteworthy Aa 123'),
  markerFelt('Marker Felt', 'Marker Felt Aa 123'),
  roboto('Roboto', 'Message preview Aa 123'),
  notoSans('Noto Sans', AppStringKeys.themeMessagePreviewSample),
  notoSansCjk(
    'Noto Sans CJK [CN]',
    AppStringKeys.themeCjkVariantPreview,
    cjk: true,
  ),
  googleInter('Inter', 'Inter Aa 123', googleFamily: 'Inter'),
  googleOpenSans('Open Sans', 'Open Sans Aa 123', googleFamily: 'Open Sans'),
  googleLato('Lato', 'Lato Aa 123', googleFamily: 'Lato'),
  googleMontserrat(
    'Montserrat',
    'Montserrat Aa 123',
    googleFamily: 'Montserrat',
  ),
  googlePoppins('Poppins', 'Poppins Aa 123', googleFamily: 'Poppins'),
  googleNunito('Nunito', 'Nunito Aa 123', googleFamily: 'Nunito'),
  googleRaleway('Raleway', 'Raleway Aa 123', googleFamily: 'Raleway'),
  googleSourceSans3(
    'Source Sans 3',
    'Source Sans 3 Aa 123',
    googleFamily: 'Source Sans 3',
  ),
  googleMerriweather(
    'Merriweather',
    'Merriweather Aa 123',
    googleFamily: 'Merriweather',
  ),
  googlePlayfairDisplay(
    'Playfair Display',
    'Playfair Display Aa 123',
    googleFamily: 'Playfair Display',
  ),
  googleNotoSerif(
    'Noto Serif',
    'Noto Serif Aa 123',
    googleFamily: 'Noto Serif',
  ),
  googleKleeOne(
    'Klee One [JP]',
    AppStringKeys.themeKleeOnePreview,
    googleFamily: 'Klee One',
    cjk: true,
  ),
  googleDotGothic16(
    'DotGothic16 [JP]',
    AppStringKeys.themeDotGothic16Preview,
    googleFamily: 'DotGothic16',
    cjk: true,
  ),
  googleStick(
    'Stick [JP]',
    AppStringKeys.themeStickPreview,
    googleFamily: 'Stick',
    cjk: true,
  ),
  googleMPlus1p(
    'M PLUS 1p [JP]',
    AppStringKeys.themeMPlus1pPreview,
    googleFamily: 'M PLUS 1p',
    cjk: true,
  ),
  lineSeedJp(
    'LINE Seed JP [JP]',
    AppStringKeys.themeAa123JapanesePreview,
    cjk: true,
  ),
  googleChocolateClassicalSans(
    'Chocolate Classical Sans [TW]',
    AppStringKeys.themeChocolateClassicalSansPreview,
    googleFamily: 'Chocolate Classical Sans',
    cjk: true,
  ),
  googleNotoSansSc(
    'Noto Sans SC [CN]',
    AppStringKeys.themeSimplifiedChinesePreview,
    googleFamily: 'Noto Sans SC',
    cjk: true,
  ),
  googleNotoSansHk(
    'Noto Sans HK [HK]',
    AppStringKeys.themeTraditionalHongKongPreview,
    googleFamily: 'Noto Sans HK',
    cjk: true,
  ),
  googleNotoSansTc(
    'Noto Sans TC [TW]',
    AppStringKeys.themeTraditionalTaiwanPreview,
    googleFamily: 'Noto Sans TC',
    cjk: true,
  ),
  googleNotoSansJp(
    'Noto Sans JP [JP]',
    AppStringKeys.themeJapanesePreview,
    googleFamily: 'Noto Sans JP',
    cjk: true,
  ),
  googleLxgwWenKaiTc(
    'LXGW WenKai TC [TW]',
    AppStringKeys.themeLXGWWenKaiPreview,
    googleFamily: 'LXGW WenKai TC',
    cjk: true,
  ),
  googleZcoolXiaoWei(
    'ZCOOL XiaoWei [CN]',
    AppStringKeys.themeZcoolXiaoWeiPreview,
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
  system(AppStringKeys.themeSystemMonospace, 'final count = 123;'),
  sfMono('SF Mono', 'final count = 123;'),
  menlo('Menlo', 'final count = 123;'),
  monaco('Monaco', 'final count = 123;'),
  courierNew('Courier New', 'final count = 123;'),
  googleRobotoMono(
    'Roboto Mono',
    'final count = 123;',
    googleFamily: 'Roboto Mono',
  ),
  googleSourceCodePro(
    'Source Code Pro',
    'final count = 123;',
    googleFamily: 'Source Code Pro',
  ),
  googleJetBrainsMono(
    'JetBrains Mono',
    'final count = 123;',
    googleFamily: 'JetBrains Mono',
  ),
  custom('Custom Font', 'final count = 123;');

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
    return withFamily.copyWith(
      fontFamilyFallback: _dedupe([
        if (isCustom &&
            selectedCustomFamily != null &&
            selectedCustomFamily.isNotEmpty)
          selectedCustomFamily,
        ...?withFamily.fontFamilyFallback,
        fontFamily,
        ..._platformMonospaceFontFallback(),
        ...AppFontChoice._platformFontFallback(),
      ]),
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
  ThemeController(this._prefs) {
    _mode = AppearanceMode.values.firstWhere(
      (m) => m.name == _prefs.getString(_modeKey),
      orElse: () => AppearanceMode.system,
    );
    _brandColor = Color(
      _prefs.getInt(_brandKey) ?? (0xFF000000 | AppTheme.defaultBrand),
    );
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
    _showChatFolderFilter = _prefs.getBool(_chatFolderFilterKey) ?? true;
    _showChatListSearch = _prefs.getBool(_chatListSearchKey) ?? true;
    _hideSidebarPhone = _prefs.getBool(_hideSidebarPhoneKey) ?? false;
    _showMemberTags = _prefs.getBool(_memberTagsKey) ?? false;
    _showPremiumNameColors = _prefs.getBool(_premiumNameColorsKey) ?? true;
    _showPremiumEmojiStatus = _prefs.getBool(_premiumEmojiStatusKey) ?? true;
    _showChatPremiumNameColors =
        _prefs.getBool(_chatPremiumNameColorsKey) ?? true;
    _showChatPremiumEmojiStatus =
        _prefs.getBool(_chatPremiumEmojiStatusKey) ?? true;
    _showMessageMetaIndicators =
        _prefs.getBool(_messageMetaIndicatorsKey) ?? false;
    _openChatsAtLatest = _prefs.getBool(_openChatsAtLatestKey) ?? false;
    _groupImageMessages = _prefs.getBool(_groupImageMessagesKey) ?? true;
    _showChannelsTab = _prefs.getBool(_showChannelsTabKey) ?? false;
    _showMomentsTab = _prefs.getBool(_showMomentsTabKey) ?? true;
    _groupAssistantPlacement = GroupAssistantPlacement.values.firstWhere(
      (m) => m.name == _prefs.getString(_groupAssistantPlacementKey),
      orElse: () => GroupAssistantPlacement.secondScreen,
    );
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
  static const _brandKey = 'brandColor';
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
  static const _chatFolderFilterKey = 'showChatFolderFilter';
  static const _chatListSearchKey = 'showChatListSearch';
  static const _hideSidebarPhoneKey = 'hideSidebarPhone';
  static const _memberTagsKey = 'showMemberTags';
  static const _premiumNameColorsKey = 'showPremiumNameColors';
  static const _premiumEmojiStatusKey = 'showPremiumEmojiStatus';
  static const _chatPremiumNameColorsKey = 'showChatPremiumNameColors';
  static const _chatPremiumEmojiStatusKey = 'showChatPremiumEmojiStatus';
  static const _messageMetaIndicatorsKey = 'showMessageMetaIndicators';
  static const _openChatsAtLatestKey = 'openChatsAtLatest';
  static const _groupImageMessagesKey = 'groupImageMessages';
  static const _showChannelsTabKey = 'showChannelsTab';
  static const _showMomentsTabKey = 'showMomentsTab';
  static const _groupAssistantPlacementKey = 'groupAssistantPlacement';
  static const _unreadBadgeModeKey = 'unreadBadgeMode';
  static const _unreadBadgeOverflowModeKey = 'unreadBadgeOverflowMode';

  static const double minFontScale = 0.8;
  static const double maxFontScale = 1.4;
  static const double minInterfaceScale = 0.66;
  static const double maxInterfaceScale = 1.50;

  final SharedPreferences _prefs;
  late AppearanceMode _mode;
  late Color _brandColor;
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
  bool _showChatFolderFilter = true;
  bool _showChatListSearch = true;
  bool _hideSidebarPhone = false;
  bool _showMemberTags = false;
  bool _showPremiumNameColors = true;
  bool _showPremiumEmojiStatus = true;
  bool _showChatPremiumNameColors = true;
  bool _showChatPremiumEmojiStatus = true;
  bool _showMessageMetaIndicators = false;
  bool _openChatsAtLatest = false;
  bool _groupImageMessages = true;
  bool _showChannelsTab = false;
  bool _showMomentsTab = true;
  late GroupAssistantPlacement _groupAssistantPlacement;
  late UnreadBadgeMode _unreadBadgeMode;
  late UnreadBadgeOverflowMode _unreadBadgeOverflowMode;

  AppearanceMode get mode => _mode;
  ThemeMode get themeMode => _mode.themeMode;
  Color get brandColor => _brandColor;
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
      ? _customPrimaryFontFamily
      : AppStrings.t(_fontChoice.label);
  String get effectiveCjkFontLabel =>
      _cjkFontChoice.isCustom && _customCjkFontFamily.isNotEmpty
      ? _customCjkFontFamily
      : AppStrings.t(_cjkFontChoice.label);
  String get effectiveMonospaceFontLabel =>
      _monospaceFontChoice.isCustom && _customMonospaceFontFamily.isNotEmpty
      ? displayStoredFontFamily(_customMonospaceFontFamily)
      : AppStrings.t(_monospaceFontChoice.label);
  String get effectiveFontChainLabel {
    if (_fontFallbackChain.isEmpty) {
      return AppStrings.t(AppStringKeys.groupManagementNotSet);
    }
    if (_fontFallbackChain.length == 1) return _fontFallbackChain.first;
    final head = _fontFallbackChain.take(2).join(' / ');
    return _fontFallbackChain.length > 2
        ? '$head / +${_fontFallbackChain.length - 2}'
        : head;
  }

  bool get circularGroupAvatars => _circularGroupAvatars;
  bool get showChatFolderFilter => _showChatFolderFilter;
  bool get showChatListSearch => _showChatListSearch;
  bool get hideSidebarPhone => _hideSidebarPhone;
  bool get showMemberTags => _showMemberTags;
  bool get showPremiumNameColors => _showPremiumNameColors;
  bool get showPremiumEmojiStatus => _showPremiumEmojiStatus;
  bool get showChatPremiumNameColors => _showChatPremiumNameColors;
  bool get showChatPremiumEmojiStatus => _showChatPremiumEmojiStatus;
  bool get showMessageMetaIndicators => _showMessageMetaIndicators;
  bool get openChatsAtLatest => _openChatsAtLatest;
  bool get groupImageMessages => _groupImageMessages;
  bool get showChannelsTab => _showChannelsTab;
  bool get showMomentsTab => _showMomentsTab;
  GroupAssistantPlacement get groupAssistantPlacement =>
      _groupAssistantPlacement;
  UnreadBadgeMode get unreadBadgeMode => _unreadBadgeMode;
  bool get unreadBadgeShowsChatCount =>
      _unreadBadgeMode == UnreadBadgeMode.chats;
  UnreadBadgeOverflowMode get unreadBadgeOverflowMode =>
      _unreadBadgeOverflowMode;
  bool get capUnreadBadgeAt99 =>
      _unreadBadgeOverflowMode == UnreadBadgeOverflowMode.capped;

  /// App-wide text scale factor, applied at the root via MediaQuery.textScaler.
  double get fontScale => _fontScale;
  double get interfaceScale => _interfaceScale;
  double get rowHeight => AppMetric.listRowHeight;
  double get avatarSize => AppMetric.avatarSize;
  double get navHeaderHeight => AppMetric.navHeaderHeight;
  double scaled(double base) => base;
  List<String> effectiveFontFamilyChain([TextStyle? base]) {
    final textFamilies = _fontFallbackChain.isNotEmpty
        ? _fontFallbackChain
        : [AppFontChoice._platformFontFamily()];
    return dedupeFontFamilies([
      textFamilies.first,
      ..._emojiFontChoice.fontFamilies,
      ...textFamilies.skip(1),
      ...AppFontChoice._platformFontFallback(),
    ]);
  }

  TextStyle applyAppTextStyle(TextStyle base, {bool boldText = false}) {
    final families = effectiveFontFamilyChain(base);
    final weightedBase = boldText ? _applyBoldTextWeight(base) : base;
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

  TextStyle _applyBoldTextWeight(TextStyle style) {
    final current = style.fontWeight ?? FontWeight.w400;
    final next = switch (current) {
      FontWeight.w100 => FontWeight.w400,
      FontWeight.w200 => FontWeight.w500,
      FontWeight.w300 => FontWeight.w500,
      FontWeight.w400 => FontWeight.w600,
      FontWeight.w500 => FontWeight.w700,
      FontWeight.w600 => FontWeight.w800,
      _ => FontWeight.w900,
    };
    return style.copyWith(fontWeight: next);
  }

  TextStyle codeTextStyle(TextStyle base) => _monospaceFontChoice
      .applyTextStyle(base, customFamily: _customMonospaceFontFamily);

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
    _prefs.setString(_emojiFontChoiceKey, entry.key);
    _prefs.setString(_emojiFontLabelKey, entry.label);
    _prefs.setString(_emojiFontLicenseKey, entry.license);
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
      _prefs.setString(_customPrimaryFontFamilyKey, nextPrimary);
      changed = true;
    }
    if (nextCjk != _customCjkFontFamily) {
      _customCjkFontFamily = nextCjk;
      _prefs.setString(_customCjkFontFamilyKey, nextCjk);
      changed = true;
    }
    if (nextMono != _customMonospaceFontFamily) {
      _customMonospaceFontFamily = nextMono;
      _prefs.setString(_customMonospaceFontFamilyKey, nextMono);
      changed = true;
    }
    if (!listEquals(nextChain, _fontFallbackChain)) {
      _fontFallbackChain = nextChain;
      _prefs.setStringList(_fontFallbackChainKey, nextChain);
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

  set showChatFolderFilter(bool value) {
    _showChatFolderFilter = value;
    _prefs.setBool(_chatFolderFilterKey, value);
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

  set showMessageMetaIndicators(bool value) {
    _showMessageMetaIndicators = value;
    _prefs.setBool(_messageMetaIndicatorsKey, value);
    notifyListeners();
  }

  set openChatsAtLatest(bool value) {
    _openChatsAtLatest = value;
    _prefs.setBool(_openChatsAtLatestKey, value);
    notifyListeners();
  }

  set groupImageMessages(bool value) {
    _groupImageMessages = value;
    _prefs.setBool(_groupImageMessagesKey, value);
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

  set groupAssistantPlacement(GroupAssistantPlacement value) {
    _groupAssistantPlacement = value;
    _prefs.setString(_groupAssistantPlacementKey, value.name);
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
