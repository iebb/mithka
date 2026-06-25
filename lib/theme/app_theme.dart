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
  static const double rowHeight = 64;
  static const double avatarSize = 48;
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
    listHeaderTint: _hex(0xEDF1F8),
    card: _hex(0xFFFFFF),
    navBar: _hex(0xFFFFFF),
    groupedBackground: _hex(0xF2F3F5),
    chatBackground: _hex(0xEDEDED),
    searchFill: _hex(0xEFF1F4),
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
    background: _hex(0x1A1A1C),
    pinnedRow: _hex(0x202024),
    listHeaderTint: _hex(0x202024),
    card: _hex(0x242427),
    navBar: _hex(0x1E1E20),
    groupedBackground: _hex(0x121214),
    chatBackground: _hex(0x161618),
    searchFill: _hex(0x2A2A2E),
    inputBarBackground: _hex(0x202022),
    panelBackground: _hex(0x1C1C1E),
    bubbleIncoming: _hex(0x2A2A2E),
    bubbleIncomingText: _hex(0xEDEDED),
    textPrimary: _hex(0xE8E8EA),
    textSecondary: _hex(0x98989D),
    textTertiary: _hex(0x6A6A6E),
    divider: _hex(0x35353A),
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
