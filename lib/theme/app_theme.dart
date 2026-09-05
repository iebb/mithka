//
//  app_theme.dart
//
//  Reference design tokens calibrated from the reference screenshots: vivid
//  azure accent, lavender-tinted 消息 header, white list rows, gray chat canvas,
//  blue/white bubbles. Surface/text tokens are adaptive (light/dark) and live in
//  [AppColors] — a [ThemeExtension] so flipping the scheme re-resolves every
//  surface automatically (the Flutter equivalent of the dynamic UIColor tokens).
//

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../platform/adaptive_platform.dart';

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

  /// Compact chat typography for native desktop windows while preserving the
  /// existing touch layouts and every user-selected font family.
  static double chatListTitle([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform) ? callout : body;
  static double chatListPreview([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform) ? caption : footnote;
  static double chatListTimestamp([TargetPlatform? platform]) => caption;

  /// The folder-tag line a chat row draws between its name and its preview.
  static double chatListFolderTag([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform) ? tiny : caption - 1;

  static double messageBody([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform) ? callout : body;
}

abstract final class AppTextWeight {
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w600;

  /// The only weights Mithka's own styles use. Anything heavier reads as a
  /// different typeface at the sizes the app draws at.
  ///
  /// [forSystemBoldText] is exempt — it answers a system accessibility
  /// setting rather than a design choice.
  static const allowed = <FontWeight>[
    FontWeight.w300,
    FontWeight.w400,
    FontWeight.w500,
    FontWeight.w600,
  ];

  /// Mirrors the platform Bold Text accessibility setting without making
  /// explicitly regular labels bold in the normal system configuration.
  ///
  /// This ladder deliberately climbs past [allowed]: the user asked the system
  /// for heavier text, and honouring that matters more than the app's own
  /// typographic range.
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
        // Aspect-scoped: MediaQuery.of would rebuild every caller on each
        // keyboard-inset and window-resize frame to read one bool.
        boldText: MediaQuery.boldTextOf(this),
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

/// Corner radii. Every rounded surface picks a step here rather than a
/// literal — the literals had drifted across every value from 1 to 28, so the
/// same kind of element was a different shape depending on the screen.
///
/// The lower steps keep their original values, so adopting them moved nothing.
abstract final class AppRadius {
  static const double sm = 4;
  static const double md = 6;
  static const double control = 9;
  static const double card = 12;

  /// Sheets, previews, and panels that want more roundness than a card.
  static const double lg = 16;

  /// The most prominent surfaces — modals, large overlays.
  static const double xl = 20;

  /// Full-height sheets and the story composer, which read as softer than a
  /// modal at the sizes they draw at.
  static const double xxl = 24;

  /// Fully rounded. On a square box this is a circle, on a wide one a stadium,
  /// and unlike a hardcoded half-of-the-height it stays right when the size
  /// changes.
  static const double pill = 999;
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

  static double chatListRowHeight([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform) ? 58 : listRowHeight;

  /// Rough line box of a text run relative to its font size. Only used to
  /// grow fixed-extent rows, so it errs generous rather than exact.
  static const double _textLineHeight = 1.3;

  /// Height a row drawn at a fixed extent needs so the text stacked inside it
  /// still fits once the ambient text scale is applied.
  ///
  /// Some rows cannot simply size to their content — a virtualized list needs
  /// a known extent, and a swipe-action row positions its layers against a
  /// bounded box. [lines] are the font sizes stacked inside such a row; the
  /// avatar and padding around them keep their size, so only those lines'
  /// growth is added. That keeps the row tight at 100% and tall enough at
  /// 200%, where scaling the whole box would leave the avatar swimming in
  /// empty space.
  static double rowExtentFor(
    BuildContext context, {
    required double base,
    required List<double> lines,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    if (scale <= 1) return base;
    final stacked = lines.fold<double>(0, (total, size) => total + size);
    return base + stacked * _textLineHeight * (scale - 1);
  }

  /// The extent a chat list row draws at and the list virtualizes against.
  ///
  /// [folderTagLine] adds the 文件夹标签 line to the stack. The nominal row is
  /// already tall enough to hold it, so this changes nothing at 100% text —
  /// it only keeps the row growing by three lines instead of two once the
  /// ambient scale is turned up.
  static double chatListRowExtent(
    BuildContext context, [
    TargetPlatform? platform,
    bool folderTagLine = false,
  ]) => rowExtentFor(
    context,
    base: chatListRowHeight(platform),
    lines: [
      AppTextSize.chatListTitle(platform),
      AppTextSize.chatListPreview(platform),
      if (folderTagLine) AppTextSize.chatListFolderTag(platform),
    ],
  );

  static double chatListAvatarSize([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform) ? 44 : avatarSize;
  static const double headerAvatarSize = 36;
  static const double hitTarget = 36;
  static const double searchHeight = 36;
  static const double searchIcon = 16;
  static const double onlineDot = 7;
  static const double menuWidth = 220;
  static const double menuRowHeight = 50;
  static const double menuIconSlot = 24;

  // Anchored popup menus. The touch sizes above are built for a fingertip; on
  // a pointer they read as oversized next to the title bar they hang from.
  static double popupMenuWidth([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform) ? 196 : menuWidth;
  static double popupMenuRowHeight([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform) ? 32 : menuRowHeight;
  static double popupMenuIconSlot([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform) ? 18 : menuIconSlot;
  static double popupMenuTextSize([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform)
      ? AppTextSize.footnote
      : AppTextSize.bodyLarge;
  static double popupMenuInset([TargetPlatform? platform]) =>
      isDesktopTargetPlatform(platform) ? AppSpacing.lg : AppSpacing.xxl;
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
  static const double settingsTextDividerInset = AppSpacing.xxl;
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
  static Color onBrand = const Color(0xFFFFFFFF);
  static Color brandDeep = _hex(0x0A84E0);
  static LinearGradient brandGradient = LinearGradient(
    colors: [_hex(0x33ADFF), _hex(0x0099FF)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Re-derives the brand accent + its shades and the outgoing-bubble color
  /// from a user-chosen base color. Call before/at theme rebuilds.
  ///
  /// [onAccent] is the palette's stored on-accent token, and is what a themed
  /// accent must pass in. Without one — a brand colour the user picked, which
  /// no theme author wrote ink for — this falls back to [accentForeground],
  /// never to [readableForeground]: maximising raw contrast against a
  /// saturated mid-tone flips to near-black, which is how azure came out with
  /// dark ink on its own bubble where every other client draws white.
  static void applyBrand(Color base, {Color? onAccent}) {
    brand = base;
    onBrand = onAccent ?? accentForeground(base);
    bubbleOutgoing = base;
    bubbleOutgoingText = onBrand;
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
  static Color bubbleOutgoingText = const Color(0xFFFFFFFF);

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
    required this.bubbleOutgoingText,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.divider,
    required this.linkBlue,
    required this.onAccent,
    required this.dialogButton,
    required this.dialogText,
    required this.badgeBackground,
    required this.badgeText,
    required this.accentButton,
    required this.accentButtonText,
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

  /// Ink on an outgoing bubble, for themes that name no chat_messageTextOut.
  /// Stored per brightness rather than measured off the fill.
  final Color bubbleOutgoingText;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color divider;
  final Color linkBlue;
  final Color onAccent;

  /// Dialog action label. Telegram's dialog buttons are flat text, so this is
  /// a text colour (key_dialogButton), not a fill.
  final Color dialogButton;

  /// Primary text inside a dialog (key_dialogTextBlack). Separate from
  /// [textPrimary] because a theme may tint the dialog surface on its own.
  final Color dialogText;

  /// Unread counter pill (key_chats_unreadCounter / ...unreadCounterText).
  final Color badgeBackground;
  final Color badgeText;

  /// Filled accent button and its label. Telegram keys the pair separately
  /// (key_featuredStickers_addButton / ...buttonText) — the fill is the accent
  /// and the label defaults to white, but a theme may move either alone.
  final Color accentButton;
  final Color accentButtonText;

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
    bubbleOutgoingText: _hex(0xFFFFFF),
    textPrimary: _hex(0x1A1A1A),
    textSecondary: _hex(0x8A8A8F),
    textTertiary: _hex(0xB0B3B8),
    divider: _hex(0xECECEC),
    linkBlue: _hex(0x4B8DEE),
    onAccent: _hex(0xFFFFFF),
    dialogButton: _hex(0x4B8DEE),
    dialogText: _hex(0x1A1D21),
    badgeBackground: _hex(0x4B8DEE),
    badgeText: _hex(0xFFFFFF),
    accentButton: _hex(0x4B8DEE),
    accentButtonText: _hex(0xFFFFFF),
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
    bubbleOutgoingText: _hex(0xFFFFFF),
    textPrimary: _hex(0xEDEDED),
    textSecondary: _hex(0x9A9A9A),
    textTertiary: _hex(0x707276),
    divider: _hex(0x303234),
    linkBlue: _hex(0x5EA0FF),
    onAccent: _hex(0xFFFFFF),
    dialogButton: _hex(0x5EA0FF),
    dialogText: _hex(0xEDEDED),
    badgeBackground: _hex(0x5EA0FF),
    badgeText: _hex(0xFFFFFF),
    accentButton: _hex(0x5EA0FF),
    accentButtonText: _hex(0xFFFFFF),
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
    Color? bubbleOutgoingText,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? divider,
    Color? linkBlue,
    Color? onAccent,
    Color? dialogButton,
    Color? dialogText,
    Color? badgeBackground,
    Color? badgeText,
    Color? accentButton,
    Color? accentButtonText,
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
      bubbleOutgoingText: bubbleOutgoingText ?? this.bubbleOutgoingText,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      divider: divider ?? this.divider,
      linkBlue: linkBlue ?? this.linkBlue,
      onAccent: onAccent ?? this.onAccent,
      dialogButton: dialogButton ?? this.dialogButton,
      dialogText: dialogText ?? this.dialogText,
      badgeBackground: badgeBackground ?? this.badgeBackground,
      badgeText: badgeText ?? this.badgeText,
      accentButton: accentButton ?? this.accentButton,
      accentButtonText: accentButtonText ?? this.accentButtonText,
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
      bubbleOutgoingText: Color.lerp(
        bubbleOutgoingText,
        other.bubbleOutgoingText,
        t,
      )!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      linkBlue: Color.lerp(linkBlue, other.linkBlue, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      dialogButton: Color.lerp(dialogButton, other.dialogButton, t)!,
      dialogText: Color.lerp(dialogText, other.dialogText, t)!,
      badgeBackground: Color.lerp(badgeBackground, other.badgeBackground, t)!,
      badgeText: Color.lerp(badgeText, other.badgeText, t)!,
      accentButton: Color.lerp(accentButton, other.accentButton, t)!,
      accentButtonText: Color.lerp(
        accentButtonText,
        other.accentButtonText,
        t,
      )!,
    );
  }

  // A cloud theme rebuilds its palette on every read, so without value equality
  // two byte-identical palettes compare unequal, ThemeData.== fails on its
  // extensions map, and every `context.colors` dependent in the tree rebuilds.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppColors &&
        other.background == background &&
        other.pinnedRow == pinnedRow &&
        other.listHeaderTint == listHeaderTint &&
        other.card == card &&
        other.navBar == navBar &&
        other.groupedBackground == groupedBackground &&
        other.chatBackground == chatBackground &&
        other.searchFill == searchFill &&
        other.inputBarBackground == inputBarBackground &&
        other.panelBackground == panelBackground &&
        other.bubbleIncoming == bubbleIncoming &&
        other.bubbleIncomingText == bubbleIncomingText &&
        other.bubbleOutgoingText == bubbleOutgoingText &&
        other.textPrimary == textPrimary &&
        other.textSecondary == textSecondary &&
        other.textTertiary == textTertiary &&
        other.divider == divider &&
        other.linkBlue == linkBlue &&
        other.onAccent == onAccent &&
        other.dialogButton == dialogButton &&
        other.dialogText == dialogText &&
        other.badgeBackground == badgeBackground &&
        other.badgeText == badgeText &&
        other.accentButton == accentButton &&
        other.accentButtonText == accentButtonText;
  }

  @override
  int get hashCode => Object.hashAll([
    background,
    pinnedRow,
    listHeaderTint,
    card,
    navBar,
    groupedBackground,
    chatBackground,
    searchFill,
    inputBarBackground,
    panelBackground,
    bubbleIncoming,
    bubbleIncomingText,
    bubbleOutgoingText,
    textPrimary,
    textSecondary,
    textTertiary,
    divider,
    linkBlue,
    onAccent,
    dialogButton,
    dialogText,
    badgeBackground,
    badgeText,
    accentButton,
    accentButtonText,
  ]);
}

const Color _neutralDarkInk = Color(0xFF171717);
const Color _neutralLightInk = Color(0xFFFFFFFF);

/// WCAG contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}

/// Returns whichever neutral text color has the stronger WCAG contrast.
///
/// Do not reach for this to decide what sits on an accent fill — use the
/// stored [AppColors.onAccent] token, or [accentForeground] where there is no
/// token because the fill is a colour the user picked. Maximising the raw
/// ratio flips to near black on any saturated mid-tone, which is how a green
/// accent once came out black-on-green where every other client draws white.
Color readableForeground(Color background) =>
    contrastRatio(background, _neutralDarkInk) >=
        contrastRatio(background, _neutralLightInk)
    ? _neutralDarkInk
    : _neutralLightInk;

/// White, and only not white when the fill is light enough that white stops
/// being readable on it.
///
/// This is what sits on an accent that nobody authored a token for — the
/// brand colour the user picked in 外观. Telegram itself always draws white
/// here, and [readableForeground] cannot stand in: maximising the raw ratio
/// prefers near-black on every saturated mid-tone, azure and green included,
/// which is what put dark ink on the outgoing bubble. The floor is well below
/// a normal accent's ratio against white, so it only catches a fill so pale
/// that white would be invisible on it.
Color accentForeground(Color fill) =>
    contrastRatio(fill, _neutralLightInk) >= _minimumAccentContrast
    ? _neutralLightInk
    : _neutralDarkInk;

/// Azure sits at 3.0 against white and a saturated green at 2.4; a near-white
/// pick sits near 1.05. Anything in between is a judgement call, and this errs
/// toward the white every other client draws.
const double _minimumAccentContrast = 2.0;

/// Keeps a body-sized link readable against [background] while retaining as
/// much of the owned [preferred] link hue as the contrast threshold permits.
///
/// This surface-only primitive is used by [readableLinkStyle], which also
/// accounts for the surrounding body text and supplies a non-colour fallback.
Color readableLinkColor({
  required Color background,
  required Color preferred,
  double minimumContrast = 4.5,
}) {
  assert(minimumContrast > 1);

  double contrast(Color first, Color second) {
    final firstLuminance = first.computeLuminance();
    final secondLuminance = second.computeLuminance();
    final lighter = math.max(firstLuminance, secondLuminance);
    final darker = math.min(firstLuminance, secondLuminance);
    return (lighter + 0.05) / (darker + 0.05);
  }

  Color opaque(Color color) => Color(color.toARGB32() | 0xFF000000);

  final surface = opaque(background);
  final desired = opaque(Color.alphaBlend(preferred, surface));
  if (contrast(desired, surface) >= minimumContrast) return desired;

  const dark = Color(0xFF000000);
  const light = Color(0xFFFFFFFF);
  final anchor = contrast(dark, surface) >= contrast(light, surface)
      ? dark
      : light;
  if (contrast(anchor, surface) < minimumContrast) return anchor;

  var valid = anchor;
  var lower = 0.0;
  var upper = 1.0;
  for (var iteration = 0; iteration < 16; iteration++) {
    final amount = (lower + upper) / 2;
    final candidate = opaque(Color.lerp(anchor, desired, amount)!);
    if (contrast(candidate, surface) >= minimumContrast) {
      valid = candidate;
      lower = amount;
    } else {
      upper = amount;
    }
  }
  return valid;
}

@immutable
class ReadableLinkStyle {
  const ReadableLinkStyle({required this.color, required this.underline});

  final Color color;
  final bool underline;
}

/// Resolves a message-link treatment that remains readable on its surface and
/// distinguishable from adjacent body copy.
///
/// Body-sized text needs 4.5:1 contrast against its surface. When that safest
/// palette colour is less than 3:1 from [body], a solid underline provides the
/// second visual cue without introducing another derived colour policy.
ReadableLinkStyle readableLinkStyle({
  required Color background,
  required Color body,
  required Color preferred,
}) {
  Color opaque(Color color) => Color(color.toARGB32() | 0xFF000000);

  final surface = opaque(background);
  final bodyColor = opaque(Color.alphaBlend(body, surface));
  final preferredColor = opaque(Color.alphaBlend(preferred, surface));
  final color = readableLinkColor(
    background: surface,
    preferred: preferredColor,
  );
  final colorLuminance = color.computeLuminance();
  final bodyLuminance = bodyColor.computeLuminance();
  final lighter = math.max(colorLuminance, bodyLuminance);
  final darker = math.min(colorLuminance, bodyLuminance);
  final bodyContrast = (lighter + 0.05) / (darker + 0.05);
  return ReadableLinkStyle(color: color, underline: bodyContrast < 3.0);
}

extension AppColorsContext on BuildContext {
  /// Resolved adaptive tokens for the active brightness.
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
