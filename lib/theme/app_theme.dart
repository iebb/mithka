//
//  app_theme.dart
//
//  Reference design tokens calibrated from the reference screenshots: vivid
//  azure accent, lavender-tinted 消息 header, white list rows, gray chat canvas,
//  blue/white bubbles. Surface/text tokens are adaptive (light/dark) and live in
//  [AppColors] — a [ThemeExtension] so flipping the scheme re-resolves every
//  surface automatically (the Flutter equivalent of the dynamic UIColor tokens).
//

import 'package:flutter/material.dart';

Color _hex(int rgb, [double opacity = 1]) =>
    Color((rgb & 0xFFFFFF) | 0xFF000000).withValues(alpha: opacity);

abstract final class AppTextSize {
  static const double tiny = 10;
  static const double caption = 12;
  static const double footnote = 13;
  static const double callout = 14;
  static const double body = 15;
  static const double bodyLarge = 16;
  static const double title = 17;
  static const double display = 22;
  static const double largeDisplay = 24;
}

abstract final class AppTextWeight {
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;

  /// Mirrors the platform Bold Text accessibility setting without making
  /// explicitly regular labels bold in the normal system configuration.
  static FontWeight forSystemBoldText(
    FontWeight weight, {
    required bool boldText,
  }) {
    if (!boldText) return weight;
    return switch (weight) {
      FontWeight.w100 => FontWeight.w400,
      FontWeight.w200 => FontWeight.w500,
      FontWeight.w300 => FontWeight.w500,
      FontWeight.w400 => FontWeight.w600,
      FontWeight.w500 => FontWeight.w700,
      FontWeight.w600 => FontWeight.w800,
      _ => FontWeight.w900,
    };
  }
}

extension AppTextWeightContext on BuildContext {
  FontWeight appFontWeight(FontWeight weight) =>
      AppTextWeight.forSystemBoldText(
        weight,
        boldText: MediaQuery.of(this).boldText,
      );
}

abstract final class AppTextStyle {
  static TextStyle tiny(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: AppTextSize.tiny,
    fontWeight: weight ?? AppTextWeight.regular,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle caption(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: AppTextSize.caption,
    fontWeight: weight ?? AppTextWeight.regular,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle footnote(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: AppTextSize.footnote,
    fontWeight: weight ?? AppTextWeight.regular,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle callout(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: AppTextSize.callout,
    fontWeight: weight ?? AppTextWeight.regular,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle body(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: AppTextSize.body,
    fontWeight: weight ?? AppTextWeight.regular,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle bodyLarge(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: AppTextSize.bodyLarge,
    fontWeight: weight ?? AppTextWeight.regular,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle title(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: AppTextSize.title,
    fontWeight: weight ?? AppTextWeight.medium,
    color: color,
    decoration: TextDecoration.none,
  );

  static TextStyle display(Color color, {FontWeight? weight}) => TextStyle(
    fontSize: AppTextSize.display,
    fontWeight: weight ?? AppTextWeight.semibold,
    color: color,
    decoration: TextDecoration.none,
  );
}

abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 8;
  static const double lg = 12;
  static const double xl = 14;
  static const double xxl = 16;
  static const double section = 24;
}

abstract final class AppInsets {
  static const EdgeInsets screen = EdgeInsets.fromLTRB(
    AppSpacing.lg,
    AppSpacing.xl,
    AppSpacing.lg,
    AppSpacing.section,
  );
  static const EdgeInsets row = EdgeInsets.symmetric(
    horizontal: AppSpacing.xxl,
  );
  static const EdgeInsets navHeader = EdgeInsets.symmetric(
    horizontal: AppSpacing.xl,
  );
  static const EdgeInsets card = EdgeInsets.all(AppSpacing.xxl);
  static const EdgeInsets search = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
  );
  static const EdgeInsets pill = EdgeInsets.symmetric(
    horizontal: AppSpacing.lg,
    vertical: AppSpacing.xs + 1,
  );
  static const EdgeInsets composerScreen = EdgeInsets.fromLTRB(
    AppSpacing.xxl,
    AppSpacing.xl,
    AppSpacing.xxl,
    AppSpacing.section,
  );
}

abstract final class AppRadius {
  static const double sm = 4;
  static const double md = 6;
  static const double control = 9;
  static const double card = 12;
  static const double lg = 12;
}

abstract final class AppIconSize {
  static const double xs = 12;
  static const double sm = 13;
  static const double md = 16;
  static const double lg = 18;
  static const double xl = 20;
  static const double nav = 22;
  static const double toolbar = 24;
  static const double add = 25;
  static const double chevron = 17;
}

abstract final class AppMetric {
  static const double navHeaderHeight = 44;
  static const double listRowHeight = 64;
  static const double settingsRowHeight = 56;
  static const double compactSettingsRowHeight = 52;
  static const double avatarSize = 48;
  static const double headerAvatarSize = 40;
  static const double hitTarget = 36;
  static const double searchHeight = 36;
  static const double searchIcon = 16;
  static const double onlineDot = 7;
  static const double menuWidth = 220;
  static const double menuRowHeight = 50;
  static const double menuIconSlot = 24;
  static const double splashPenguinSize = 192;
  static const double splashSpinnerSize = 24;
  static const double divider = 0.5;
  static const double selectedBorder = 2.5;
  static const double badgeOutlinePadding = 1.5;
  static const double unreadBadgeMin = 18;
  static const double unreadDot = 11;
  static const double settingsLeadingInset = AppSpacing.xxl;
  static const double settingsTrailingInset = AppSpacing.xl;
  static const double settingsIconDividerInset = 56;
  static const double maxBannerWidth = 300;
  static const double composerHeaderHeight = 64;
  static const double composerPublishButtonHeight = 38;
  static const double composerFormatButtonWidth = 32;
  static const double composerFormatButtonHeight = 28;
  static const double mediaTile = 92;
  static const double overlayCloseButton = 22;
}

/// Constants that read well on both light and dark, so they stay fixed.
abstract final class AppTheme {
  // MARK: Brand (mutable — driven by the user's chosen theme color via
  // [applyBrand]; defaults to azure).
  static const int defaultBrand = 0x0099FF;
  static Color brand = _hex(defaultBrand);
  static Color brandDeep = _hex(0x0A84E0);
  static LinearGradient brandGradient = LinearGradient(
    colors: [_hex(0x33ADFF), _hex(0x0099FF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Re-derives the brand accent + its shades and the outgoing-bubble color
  /// from a user-chosen base color. Call before/at theme rebuilds.
  static void applyBrand(Color base) {
    brand = base;
    bubbleOutgoing = base;
    final hsl = HSLColor.fromColor(base);
    brandDeep = hsl
        .withLightness((hsl.lightness - 0.08).clamp(0.0, 1.0))
        .toColor();
    final lighter = hsl
        .withLightness((hsl.lightness + 0.12).clamp(0.0, 1.0))
        .toColor();
    brandGradient = LinearGradient(
      colors: [lighter, base],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
  }

  // MARK: Bubbles (outgoing tracks the brand color)
  static Color bubbleOutgoing = _hex(defaultBrand);
  static const Color bubbleOutgoingText = Colors.white;

  // MARK: Accents (constant)
  static final Color unreadBadge = _hex(0xFF4D4F);
  static final Color tagRed = _hex(0xFA5151);
  static final Color onlineDot = _hex(0x1AC81A);
  static final Color cloverGreen = _hex(0x2DBE60);

  // MARK: Metrics
  static const double rowHeight = AppMetric.listRowHeight;
  static const double avatarSize = AppMetric.avatarSize;
  static const double avatarCorner = 12; // legacy (rounded-square)
  static const double groupAvatarCornerRatio = 0.30; // groups: rounded square
  static const double bubbleCorner = 9;

  /// Deterministic monogram palette (stable across launches).
  static final List<Color> avatarPalette = [
    _hex(0x0099FF),
    _hex(0x2DC100),
    _hex(0xFF9D2E),
    _hex(0xFF5E7D),
    _hex(0x8E7BFF),
    _hex(0x00C4B3),
    _hex(0xFFB300),
    _hex(0x4A90E2),
  ];

  static Color avatarColor(String title) {
    final seed = title.runes.fold<int>(0, (a, c) => a + c);
    return avatarPalette[seed % avatarPalette.length];
  }
}

/// Adaptive surface/text tokens, resolved by the active brightness.
/// Read via `context.colors` (see the extension at the bottom).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.pinnedRow,
    required this.listHeaderTint,
    required this.card,
    required this.navBar,
    required this.groupedBackground,
    required this.chatBackground,
    required this.searchFill,
    required this.inputBarBackground,
    required this.panelBackground,
    required this.bubbleIncoming,
    required this.bubbleIncomingText,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.linkBlue,
  });

  final Color background; // list row background
  final Color pinnedRow; // pinned chat row tint
  final Color listHeaderTint; // 消息 header wash
  final Color card;
  final Color navBar; // custom NavHeader bar
  final Color groupedBackground;
  final Color chatBackground; // conversation canvas
  final Color searchFill;
  final Color inputBarBackground;
  final Color panelBackground;
  final Color bubbleIncoming;
  final Color bubbleIncomingText;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color linkBlue;

  static final AppColors light = AppColors(
    background: _hex(0xFFFFFF),
    pinnedRow: _hex(0xF3F4F7),
    listHeaderTint: _hex(0xEFF5FF),
    card: _hex(0xFFFFFF),
    navBar: _hex(0xFFFFFF),
    groupedBackground: _hex(0xF2F2F2),
    chatBackground: _hex(0xF2F2F2),
    searchFill: _hex(0xFFFFFF),
    inputBarBackground: _hex(0xF7F7F7),
    panelBackground: _hex(0xF2F3F5),
    bubbleIncoming: _hex(0xFFFFFF),
    bubbleIncomingText: _hex(0x1A1A1A),
    textPrimary: _hex(0x1A1A1A),
    textSecondary: _hex(0x8A8A8F),
    textTertiary: _hex(0xB0B3B8),
    divider: _hex(0xECECEC),
    linkBlue: _hex(0x4B8DEE),
  );

  static final AppColors dark = AppColors(
    background: _hex(0x202324),
    pinnedRow: _hex(0x252829),
    listHeaderTint: _hex(0x202324),
    card: _hex(0x202324),
    navBar: _hex(0x2B2D2E),
    groupedBackground: _hex(0x151718),
    chatBackground: _hex(0x000000),
    searchFill: _hex(0x36383A),
    inputBarBackground: _hex(0x202324),
    panelBackground: _hex(0x151718),
    bubbleIncoming: _hex(0x292D30),
    bubbleIncomingText: _hex(0xEDEDED),
    textPrimary: _hex(0xEDEDED),
    textSecondary: _hex(0x9A9A9A),
    textTertiary: _hex(0x707276),
    divider: _hex(0x303234),
    linkBlue: _hex(0x5EA0FF),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? pinnedRow,
    Color? listHeaderTint,
    Color? card,
    Color? navBar,
    Color? groupedBackground,
    Color? chatBackground,
    Color? searchFill,
    Color? inputBarBackground,
    Color? panelBackground,
    Color? bubbleIncoming,
    Color? bubbleIncomingText,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? divider,
    Color? linkBlue,
  }) {
    return AppColors(
      background: background ?? this.background,
      pinnedRow: pinnedRow ?? this.pinnedRow,
      listHeaderTint: listHeaderTint ?? this.listHeaderTint,
      card: card ?? this.card,
      navBar: navBar ?? this.navBar,
      groupedBackground: groupedBackground ?? this.groupedBackground,
      chatBackground: chatBackground ?? this.chatBackground,
      searchFill: searchFill ?? this.searchFill,
      inputBarBackground: inputBarBackground ?? this.inputBarBackground,
      panelBackground: panelBackground ?? this.panelBackground,
      bubbleIncoming: bubbleIncoming ?? this.bubbleIncoming,
      bubbleIncomingText: bubbleIncomingText ?? this.bubbleIncomingText,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      divider: divider ?? this.divider,
      linkBlue: linkBlue ?? this.linkBlue,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      pinnedRow: Color.lerp(pinnedRow, other.pinnedRow, t)!,
      listHeaderTint: Color.lerp(listHeaderTint, other.listHeaderTint, t)!,
      card: Color.lerp(card, other.card, t)!,
      navBar: Color.lerp(navBar, other.navBar, t)!,
      groupedBackground: Color.lerp(
        groupedBackground,
        other.groupedBackground,
        t,
      )!,
      chatBackground: Color.lerp(chatBackground, other.chatBackground, t)!,
      searchFill: Color.lerp(searchFill, other.searchFill, t)!,
      inputBarBackground: Color.lerp(
        inputBarBackground,
        other.inputBarBackground,
        t,
      )!,
      panelBackground: Color.lerp(panelBackground, other.panelBackground, t)!,
      bubbleIncoming: Color.lerp(bubbleIncoming, other.bubbleIncoming, t)!,
      bubbleIncomingText: Color.lerp(
        bubbleIncomingText,
        other.bubbleIncomingText,
        t,
      )!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      linkBlue: Color.lerp(linkBlue, other.linkBlue, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  /// Resolved adaptive tokens for the active brightness.
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
