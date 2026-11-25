//
//  platform_font_defaults.dart
//
//  Platform- and locale-aware default font chains, monospace defaults, emoji
//  fallbacks, BCP-47 typography locale normalization, and local font ranking.
//

import 'dart:ui' show Locale;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

enum CjkScriptPreference {
  simplifiedChinese,
  traditionalChinese,
  japanese,
  korean,
}

class PlatformFontDefaults {
  PlatformFontDefaults._();

  static TargetPlatform get _currentPlatform => defaultTargetPlatform;

  static Locale? normalizeTypographyLocale(Locale? locale) {
    if (locale == null) return null;
    var language = locale.languageCode.trim();
    if (language.isEmpty) return null;

    var rawScript = locale.scriptCode?.trim() ?? '';
    var rawCountry = locale.countryCode?.trim() ?? '';

    // Handle callers that pass an unsplit tag inside languageCode, such as Locale('zh_CN').
    if (rawScript.isEmpty &&
        rawCountry.isEmpty &&
        (language.contains('_') || language.contains('-'))) {
      final parts = language
          .replaceAll('_', '-')
          .split('-')
          .where((part) => part.trim().isNotEmpty)
          .toList();
      if (parts.isEmpty) return null;
      language = parts.first;
      for (final part in parts.skip(1)) {
        if (part.length == 4 && rawScript.isEmpty) {
          rawScript = part;
        } else if ((part.length == 2 || part.length == 3) &&
            rawCountry.isEmpty) {
          rawCountry = part;
        }
      }
    }

    language = language.toLowerCase();
    if (language.isEmpty || language == 'und') return null;

    var script = rawScript.isEmpty
        ? null
        : rawScript.substring(0, 1).toUpperCase() +
              rawScript.substring(1).toLowerCase();

    final country = rawCountry.isEmpty ? null : rawCountry.toUpperCase();

    // Bare "zh" causes Windows DirectWrite MapCharacters to fall back to
    // Yu Gothic UI instead of Microsoft YaHei UI. Supply an explicit
    // Hans/Hant script subtag unless another explicit script (e.g. Latn) was given.
    if (language == 'zh' &&
        (script == null || script == 'Hans' || script == 'Hant')) {
      final isTraditional =
          script == 'Hant' ||
          (script == null && const {'TW', 'HK', 'MO'}.contains(country));
      script = isTraditional ? 'Hant' : 'Hans';
    }

    return Locale.fromSubtags(
      languageCode: language,
      scriptCode: script,
      countryCode: country,
    );
  }

  static Locale? effectiveTypographyLocale({
    Locale? appLocale,
    Locale? systemLocale,
  }) =>
      normalizeTypographyLocale(appLocale) ??
      normalizeTypographyLocale(systemLocale);

  static CjkScriptPreference? _cjkPreferenceFromLocale(Locale? locale) {
    final normalized = normalizeTypographyLocale(locale);
    if (normalized == null) return null;
    return switch (normalized.languageCode) {
      'zh' =>
        normalized.scriptCode == 'Hant'
            ? CjkScriptPreference.traditionalChinese
            : CjkScriptPreference.simplifiedChinese,
      'ja' => CjkScriptPreference.japanese,
      'ko' => CjkScriptPreference.korean,
      _ => null,
    };
  }

  static CjkScriptPreference cjkPreferenceFor({
    Locale? appLocale,
    Locale? systemLocale,
  }) =>
      _cjkPreferenceFromLocale(appLocale) ??
      _cjkPreferenceFromLocale(systemLocale) ??
      CjkScriptPreference.simplifiedChinese;

  static String primaryFontFamily({TargetPlatform? platform}) {
    final target = platform ?? _currentPlatform;
    return switch (target) {
      TargetPlatform.iOS || TargetPlatform.macOS => '.AppleSystemUIFont',
      TargetPlatform.android => 'Roboto',
      TargetPlatform.windows => 'Segoe UI',
      TargetPlatform.linux => 'Noto Sans',
      _ => 'Noto Sans',
    };
  }

  static List<String> fallbackFontChain({
    TargetPlatform? platform,
    Locale? appLocale,
    Locale? systemLocale,
  }) {
    final target = platform ?? _currentPlatform;
    final cjkPref = cjkPreferenceFor(
      appLocale: appLocale,
      systemLocale: systemLocale,
    );
    return switch (target) {
      TargetPlatform.iOS || TargetPlatform.macOS => _appleFallback(cjkPref),
      TargetPlatform.android => _androidFallback(cjkPref),
      TargetPlatform.windows => _windowsFallback(cjkPref),
      TargetPlatform.linux => _linuxFallback(cjkPref),
      _ => _windowsFallback(cjkPref),
    };
  }

  static List<String> effectiveFontChain({
    TargetPlatform? platform,
    Locale? appLocale,
    Locale? systemLocale,
  }) {
    final target = platform ?? _currentPlatform;
    final seen = <String>{};
    return [
      for (final family in [
        primaryFontFamily(platform: target),
        ...fallbackFontChain(
          platform: target,
          appLocale: appLocale,
          systemLocale: systemLocale,
        ),
        ...emojiFontFallback(platform: target),
      ])
        if (family.isNotEmpty && seen.add(family)) family,
    ];
  }

  static String monospaceFontFamily({TargetPlatform? platform}) {
    final target = platform ?? _currentPlatform;
    return switch (target) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'Menlo',
      TargetPlatform.windows => 'Consolas',
      TargetPlatform.android => 'monospace',
      TargetPlatform.linux => 'Noto Sans Mono',
      _ => 'monospace',
    };
  }

  static List<String> monospaceFontFallback({TargetPlatform? platform}) {
    final target = platform ?? _currentPlatform;
    return switch (target) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        'SF Mono',
        'Menlo',
        'Monaco',
        'Courier New',
      ],
      TargetPlatform.windows => const [
        'Cascadia Mono',
        'Cascadia Code',
        'Consolas',
        'Courier New',
        'Lucida Console',
      ],
      TargetPlatform.android => const [
        'monospace',
        'Roboto Mono',
        'Noto Sans Mono',
      ],
      TargetPlatform.linux => const [
        'Noto Sans Mono',
        'DejaVu Sans Mono',
        'Liberation Mono',
        'Ubuntu Mono',
        'monospace',
      ],
      _ => const ['monospace', 'Courier New'],
    };
  }

  static List<String> emojiFontFallback({TargetPlatform? platform}) {
    final target = platform ?? _currentPlatform;
    return switch (target) {
      TargetPlatform.iOS || TargetPlatform.macOS => const ['Apple Color Emoji'],
      TargetPlatform.android => const ['Noto Color Emoji'],
      TargetPlatform.windows => const [
        'Segoe UI Emoji',
        'Segoe UI Symbol',
        'Noto Color Emoji',
      ],
      TargetPlatform.linux => const [
        'Noto Color Emoji',
        'Twitter Color Emoji',
        'EmojiOne Color',
      ],
      _ => const ['Noto Color Emoji', 'Apple Color Emoji'],
    };
  }

  static Map<String, int> popularSystemFontPriority({
    TargetPlatform? platform,
    Locale? appLocale,
    Locale? systemLocale,
  }) {
    final target = platform ?? _currentPlatform;
    final cjkPref = cjkPreferenceFor(
      appLocale: appLocale,
      systemLocale: systemLocale,
    );
    final ordered = switch (target) {
      TargetPlatform.iOS || TargetPlatform.macOS => [
        '.AppleSystemUIFont',
        ..._orderedCjkGroups(
          cjkPref,
          sc: const ['PingFang SC'],
          tc: const ['PingFang TC', 'PingFang HK'],
          ja: const ['Hiragino Sans'],
          ko: const ['Apple SD Gothic Neo'],
        ),
        'SF Pro',
        'SF Pro Text',
        'SF Pro Display',
        'Helvetica Neue',
        'Helvetica',
        'Avenir Next',
        'Avenir',
        'Futura',
        'Gill Sans',
        'Optima',
        'Palatino',
        'Georgia',
        'Times New Roman',
        'Didot',
        'American Typewriter',
        'Courier New',
        'Menlo',
        'SF Mono',
        'Inter',
        'Roboto',
        'Arial',
      ],
      TargetPlatform.windows => [
        'Segoe UI',
        'Segoe UI Variable',
        ..._orderedCjkGroups(
          cjkPref,
          sc: const [
            'Microsoft YaHei UI',
            'Microsoft YaHei',
            'DengXian',
            'Noto Sans SC',
            'Source Han Sans SC',
            'Noto Sans CJK SC',
            'HarmonyOS Sans SC',
            'MiSans',
            'PingFang SC',
            'SimHei',
            'SimSun',
            'KaiTi',
            'FangSong',
          ],
          tc: const [
            'Microsoft JhengHei UI',
            'Microsoft JhengHei',
            'Noto Sans TC',
            'Source Han Sans TC',
            'Noto Sans CJK TC',
            'PingFang TC',
            'PMingLiU',
          ],
          ja: const [
            'Yu Gothic UI',
            'Yu Gothic',
            'Meiryo UI',
            'Meiryo',
            'Noto Sans JP',
          ],
          ko: const ['Malgun Gothic', 'Noto Sans KR'],
        ),
        'Cascadia Mono',
        'Cascadia Code',
        'Consolas',
        'Courier New',
        'Inter',
        'Roboto',
        'Calibri',
        'Arial',
        'Cambria',
        'Georgia',
        'Times New Roman',
        'Verdana',
      ],
      TargetPlatform.android => [
        'Roboto',
        ..._orderedCjkGroups(
          cjkPref,
          sc: const ['Noto Sans CJK SC', 'Noto Sans SC'],
          tc: const ['Noto Sans CJK TC', 'Noto Sans TC'],
          ja: const ['Noto Sans CJK JP', 'Noto Sans JP'],
          ko: const ['Noto Sans CJK KR', 'Noto Sans KR'],
        ),
        'Noto Sans',
        'Noto Serif',
        'Droid Sans',
        'sans',
        'sans-serif',
        'monospace',
        'serif',
      ],
      TargetPlatform.linux => [
        'Ubuntu',
        'Cantarell',
        ..._orderedCjkGroups(
          cjkPref,
          sc: const [
            'Noto Sans CJK SC',
            'Noto Sans SC',
            'Source Han Sans SC',
            'WenQuanYi Micro Hei',
          ],
          tc: const ['Noto Sans CJK TC', 'Noto Sans TC', 'Source Han Sans TC'],
          ja: const ['Noto Sans CJK JP', 'Noto Sans JP'],
          ko: const ['Noto Sans CJK KR', 'Noto Sans KR'],
        ),
        'Noto Sans',
        'DejaVu Sans',
        'Liberation Sans',
        'Noto Serif',
        'DejaVu Serif',
        'DejaVu Sans Mono',
        'Liberation Mono',
        'Ubuntu Mono',
        'monospace',
        'sans-serif',
        'serif',
      ],
      _ => [
        'Roboto',
        ..._orderedCjkGroups(
          cjkPref,
          sc: const ['Noto Sans CJK SC', 'Noto Sans SC', 'Source Han Sans SC'],
          tc: const ['Noto Sans CJK TC', 'Noto Sans TC', 'Source Han Sans TC'],
          ja: const ['Noto Sans CJK JP', 'Noto Sans JP'],
          ko: const ['Noto Sans CJK KR', 'Noto Sans KR'],
        ),
        'Noto Sans',
        'Arial',
        'Georgia',
        'Times New Roman',
        'Courier New',
        'monospace',
        'sans-serif',
        'serif',
      ],
    };
    return <String, int>{
      for (var i = 0; i < ordered.length; i++) ordered[i]: i,
    };
  }

  /// Ranks [family] using [popularSystemFontPriority], matching exact names first
  /// and then optical/weight variants (without promoting unrelated icon/emoji
  /// families such as `Segoe UI Emoji` ahead of body text fonts).
  static int rankSystemFontFamily(
    String family, {
    TargetPlatform? platform,
    Locale? appLocale,
    Locale? systemLocale,
  }) {
    final priorities = popularSystemFontPriority(
      platform: platform,
      appLocale: appLocale,
      systemLocale: systemLocale,
    );
    final normalized = family.trim().toLowerCase();
    for (final entry in priorities.entries) {
      if (entry.key.toLowerCase() == normalized) return entry.value;
    }
    if (normalized.contains('emoji') ||
        normalized.contains('symbol') ||
        normalized.contains('historic') ||
        normalized.contains('icons') ||
        normalized.contains('assets')) {
      return priorities.length + 1;
    }
    for (final entry in priorities.entries) {
      final candidate = entry.key.toLowerCase();
      if (normalized.startsWith('$candidate ') ||
          normalized.startsWith('$candidate-')) {
        return entry.value;
      }
    }
    return priorities.length + 1;
  }

  static List<String> _appleFallback(CjkScriptPreference pref) => [
    ..._orderedCjkGroups(
      pref,
      sc: const ['PingFang SC'],
      tc: const ['PingFang TC'],
      ja: const ['Hiragino Sans'],
      ko: const ['Apple SD Gothic Neo'],
    ),
    'Helvetica Neue',
    'Arial',
  ];

  static List<String> _androidFallback(CjkScriptPreference pref) => [
    ..._orderedCjkGroups(
      pref,
      sc: const ['Noto Sans CJK SC'],
      tc: const ['Noto Sans CJK TC'],
      ja: const ['Noto Sans CJK JP'],
      ko: const ['Noto Sans CJK KR'],
    ),
    'Noto Sans',
    'sans-serif',
  ];

  static List<String> _windowsFallback(CjkScriptPreference pref) => [
    ..._orderedCjkGroups(
      pref,
      sc: const [
        'Microsoft YaHei UI',
        'Microsoft YaHei',
        'Noto Sans SC',
        'Noto Sans CJK SC',
        'Source Han Sans SC',
        'DengXian',
        'SimSun',
        'SimSun-ExtB',
      ],
      tc: const [
        'Microsoft JhengHei UI',
        'Microsoft JhengHei',
        'Noto Sans TC',
        'Noto Sans CJK TC',
        'Source Han Sans TC',
        'PMingLiU',
      ],
      ja: const [
        'Yu Gothic UI',
        'Yu Gothic',
        'Meiryo UI',
        'Meiryo',
        'Noto Sans JP',
        'Noto Sans CJK JP',
        'MS PGothic',
      ],
      ko: const ['Malgun Gothic', 'Noto Sans KR', 'Noto Sans CJK KR'],
    ),
    'Segoe UI',
    'Arial',
  ];

  static List<String> _linuxFallback(CjkScriptPreference pref) => [
    ..._orderedCjkGroups(
      pref,
      sc: const [
        'Noto Sans CJK SC',
        'Noto Sans SC',
        'Source Han Sans SC',
        'WenQuanYi Micro Hei',
      ],
      tc: const ['Noto Sans CJK TC', 'Noto Sans TC', 'Source Han Sans TC'],
      ja: const ['Noto Sans CJK JP', 'Noto Sans JP'],
      ko: const ['Noto Sans CJK KR', 'Noto Sans KR'],
    ),
    'Noto Sans',
    'Ubuntu',
    'DejaVu Sans',
    'sans-serif',
  ];

  static List<String> _orderedCjkGroups(
    CjkScriptPreference pref, {
    required List<String> sc,
    required List<String> tc,
    required List<String> ja,
    required List<String> ko,
  }) => switch (pref) {
    CjkScriptPreference.simplifiedChinese => [...sc, ...tc, ...ja, ...ko],
    CjkScriptPreference.traditionalChinese => [...tc, ...sc, ...ja, ...ko],
    CjkScriptPreference.japanese => [...ja, ...sc, ...tc, ...ko],
    CjkScriptPreference.korean => [...ko, ...sc, ...tc, ...ja],
  };
}
