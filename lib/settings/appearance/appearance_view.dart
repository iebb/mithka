//
//  appearance_view.dart
//

//  外观 is the hub for theme, interface, font, and app-icon settings. Each
//  interface surface owns its controls and a live account-backed preview.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/preview_texts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../app/ipad_window_chrome.dart';
import '../../chat/appearance/chat_appearance_preview.dart';
import '../../chat/appearance/chat_wallpaper.dart';
import '../../chat/appearance/chat_wallpaper_view.dart';
import '../../chat/messages/image_media_album_bubble.dart';
import '../../chat/messages/message_action_menu.dart';
import '../../chat/messages/message_bubble.dart';
import '../../chat/messages/message_bubble_chat_preview.dart';
import '../../chat/messages/quick_reaction_choice.dart';
import '../../chat/stickers/emoji_store.dart';
import '../../components/app_icons.dart';
import '../../components/app_interactive_surface.dart';
import '../../components/toast.dart';
import '../../components/ui_components.dart';
import '../../platform/adaptive_platform.dart';
import '../../platform/system_ui.dart';
import '../../pro/mithka_pro_view.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/emoji_font_catalog.dart';
import '../../theme/global_theme_view.dart';
import '../../theme/message_bubble_background.dart';
import '../../theme/message_name_colors.dart';
import '../../theme/platform_font_defaults.dart';
import '../../theme/system_font_catalog.dart';
import '../../theme/theme_controller.dart';
import '../quick_reaction_settings_view.dart';
import 'app_icon_controller.dart';
import 'content_size_settings_view.dart';
import 'interface_scale_control.dart';
import 'message_bubble_settings_view.dart';

part 'appearance_app_icon_view.dart';
part 'appearance_display_views.dart';
part 'appearance_font_views.dart';

class AppearanceView extends StatelessWidget {
  const AppearanceView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final platform = Theme.of(context).platform;
    final showAppIconPicker = appIconPickerAvailableForPlatform(platform);
    final appIcons = showAppIconPicker
        ? context.watch<AppIconController>()
        : null;
    final currentIcon = appIcons?.currentVariant;
    // Picker artwork is pre-sized to 256px; decode the row preview at its
    // actual physical width rather than retaining the full bitmap.
    final appIconPreviewPx =
        (AppIconSize.nav * MediaQuery.devicePixelRatioOf(context)).ceil();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceTitle),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          // What the app looks like as a whole. No heading: it is the
          // first card, and a "Theme" heading over a "Theme" row only
          // says it twice.
          if (showAppIconPicker)
            _card(context, [
              _navigationRow(
                context,
                AppStrings.t(AppStringKeys.appIconTitle),
                null,
                () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => const AppIconSettingsView(),
                  ),
                ),
                preview: currentIcon == null
                    ? null
                    // Standard icons preview their real background, as in
                    // the picker; penguins keep their background-free art.
                    : currentIcon.isStandard
                    ? _StandardAppIconImage(
                        key: const ValueKey('appearance-app-icon-preview'),
                        variant: currentIcon,
                        size: AppIconSize.nav,
                      )
                    : Image.asset(
                        currentIcon.pickerAsset,
                        key: const ValueKey('appearance-app-icon-preview'),
                        width: AppIconSize.nav,
                        height: AppIconSize.nav,
                        cacheWidth: appIconPreviewPx,
                        fit: BoxFit.contain,
                        filterQuality:
                            currentIcon.freeMotif ==
                                AppIconFreeMotif.pixelPenguin
                            ? FilterQuality.none
                            : FilterQuality.medium,
                      ),
              ),
            ]),
          SettingsSection(
            titleKey: AppStringKeys.featureBottomTabs,
            rows: [
              SettingsSwitchRow(
                key: const ValueKey('settings-liquid-glass-bottom-bar'),
                title: AppStringKeys.featureLiquidGlassBottomBar,
                subtitle: AppStringKeys.featureLiquidGlassBottomBarHint,
                value: theme.liquidGlassBottomBar,
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.wandMagicSparkles,
                ),
                onChanged: (value) => theme.liquidGlassBottomBar = value,
              ),
            ],
          ),
          _label(context, AppStrings.t(AppStringKeys.appearanceSectionText)),
          _card(context, [
            KeyedSubtree(
              key: const ValueKey('appearance-scaling-settings-row'),
              child: _navigationRow(
                context,
                AppStrings.t(AppStringKeys.appearanceInterfaceSize),
                InterfaceScaleSteps.percent(theme.interfaceScale),
                () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => const InterfaceSizeSettingsView(),
                  ),
                ),
                icon: HeroAppIcons.expand.data,
                minimumTapExtent: InterfaceScaleSteps.targetExtent(
                  theme.renderedInterfaceScale,
                ),
              ),
            ),
            KeyedSubtree(
              key: const ValueKey('appearance-font-settings-row'),
              child: _navigationRow(
                context,
                AppStrings.t(AppStringKeys.appearanceFont),
                theme.effectiveFontChainLabel,
                () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => const FontSettingsView(),
                  ),
                ),
                icon: HeroAppIcons.font.data,
              ),
            ),
          ]),
          _label(context, AppStrings.t(AppStringKeys.appearanceSectionChat)),
          // Message Bubbles used to sit alone in an unlabelled card;
          // it belongs with the rest of what a conversation looks like.
          _card(context, [
            // Simple mode only reshapes the phone composer; the desktop
            // composer never changes, so the switch would do nothing there.
            if (!isDesktopTargetPlatform(Theme.of(context).platform))
              SettingsSwitchRow(
                key: const ValueKey('settings-simple-mode'),
                title: AppStringKeys.appearanceSimpleMode,
                subtitle: AppStringKeys.appearanceSimpleModeDescription,
                value: theme.simpleMode,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.comment),
                onChanged: (value) => theme.simpleMode = value,
              ),
            _chatViewNavigationRow(context),
            KeyedSubtree(
              key: const ValueKey('appearance-message-bubbles-row'),
              child: _navigationRow(
                context,
                AppStrings.t(AppStringKeys.appearanceMessageBubbles),
                _messageBubbleBackgroundLabel(theme),
                () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => const MessageBubbleSettingsView(),
                  ),
                ),
                icon: HeroAppIcons.message.data,
              ),
            ),
          ]),
          _label(
            context,
            AppStrings.t(AppStringKeys.appearanceSectionChatList),
          ),
          _card(context, _chatListNavigationRows(context)),
          _label(
            context,
            AppStrings.t(AppStringKeys.appearanceAvatarsAndSidebar),
          ),
          _avatarsAndSidebarControls(context),
        ],
      ),
    );
  }
}

class ThemeSettingsView extends StatelessWidget {
  const ThemeSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    const appearance = AppearanceView();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceTheme),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          appearance._card(context, [
            appearance._toggleRow(
              context,
              HeroAppIcons.wandMagicSparkles.data,
              AppStrings.t(AppStringKeys.appearanceEnableTheming),
              theme.themingEnabled,
              (value) => theme.themingEnabled = value,
            ),
            appearance._toggleRow(
              context,
              HeroAppIcons.users.data,
              AppStrings.t(AppStringKeys.appearancePerAccountTheming),
              theme.usePerAccountTheming,
              (value) => theme.usePerAccountTheming = value,
            ),
          ]),
          if (theme.themingEnabled) ...[
            appearance._label(
              context,
              AppStrings.t(AppStringKeys.appearanceTheme),
            ),
            // Theme and background are judged together, so they preview
            // together — the same call Telegram makes, where the chat
            // preview sits between the theme picker and the background
            // row rather than each hiding behind its own screen.
            AnimatedBuilder(
              animation: ChatWallpaperController.shared,
              builder: (context, _) {
                final dark = Theme.of(context).brightness == Brightness.dark;
                final bubbles = context.watch<ThemeController>();
                final wallpaperController = ChatWallpaperController.shared;
                final selectedWallpaper = selectGlobalChatWallpaper(
                  defaultWallpaper: wallpaperController.defaultWallpaper(
                    dark: dark,
                  ),
                  cloudThemeWallpaper: bubbles
                      .cloudThemeFor(dark ? Brightness.dark : Brightness.light)
                      ?.wallpaper,
                  globalThemeWallpaper: wallpaperController
                      .globalThemeWallpaperFor(dark: dark),
                );
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  child: MessageBubbleChatPreview(
                    incomingBackground: bubbles
                        .effectiveMessageBubbleBackgroundSpecFor(
                          outgoing: false,
                        ),
                    outgoingBackground: bubbles
                        .effectiveMessageBubbleBackgroundSpecFor(
                          outgoing: true,
                        ),
                    wallpaper: selectedWallpaper == null
                        ? null
                        : wallpaperController.resolvedWallpaper(
                            selectedWallpaper,
                          ),
                  ),
                );
              },
            ),
            appearance._card(context, [
              appearance._navigationRow(
                context,
                AppStrings.t(AppStringKeys.appearanceTheme),
                theme.cloudTheme?.displayTitle ??
                    AppStrings.t(AppStringKeys.globalThemeDefault),
                () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => const GlobalThemeView(),
                  ),
                ),
                icon: HeroAppIcons.palette.data,
              ),
              appearance._navigationRow(
                context,
                AppStrings.t(AppStringKeys.groupAppearanceWallpaper),
                null,
                () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => ChatWallpaperView.global(
                      chatTitle: AppStrings.t(
                        AppStringKeys.chatWallpaperGlobalPreview,
                      ),
                      forDarkTheme:
                          Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                ),
                icon: HeroAppIcons.image.data,
              ),
            ]),
          ],
          appearance._label(
            context,
            AppStrings.t(AppStringKeys.appearanceMode),
          ),
          appearance._card(context, [
            for (final mode in AppearanceMode.values)
              appearance._choiceRow(
                context,
                mode.icon,
                mode.label,
                theme.mode == mode,
                () => theme.mode = mode,
              ),
          ]),
        ],
      ),
    );
  }
}

class InterfaceSizeSettingsView extends StatelessWidget {
  const InterfaceSizeSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final colors = context.colors;
    final target = InterfaceScaleSteps.targetExtent(
      theme.renderedInterfaceScale,
    );
    final navigator = Navigator.of(context);
    final pointerDense = isDesktopTargetPlatform();
    final canGoBack =
        navigator.canPop() && !SettingsSplitPaneScope.isRootRoute(context);
    // Only this adjustment page needs a scale-aware header. The shared header's
    // 44 virtual-point back target shrinks below 44 screen points at 50%.
    return AnnotatedRegion(
      value: systemUiOverlayStyleForSurface(colors.navBar),
      child: Scaffold(
        backgroundColor: colors.groupedBackground,
        body: Column(
          children: [
            Container(
              constraints: BoxConstraints(
                minHeight: theme.navHeaderHeight + topChromeInsetOf(context),
              ),
              padding: headerChromePaddingOf(context),
              decoration: BoxDecoration(
                color: colors.navBar,
                border: Border(
                  bottom: BorderSide(
                    color: colors.divider,
                    width: AppMetric.divider,
                  ),
                ),
              ),
              child: Padding(
                padding: AppInsets.navHeader,
                child: Row(
                  children: [
                    if (canGoBack)
                      AppInteractiveSurface(
                        key: const ValueKey('interface-scale-back'),
                        semanticLabel: AppStrings.t(
                          AppStringKeys.navigationBack,
                        ),
                        onTap: navigator.pop,
                        child: SizedBox(
                          width: target,
                          height: target,
                          child: Center(
                            child: AppIcon(
                              HeroAppIcons.chevronLeft,
                              size: pointerDense
                                  ? AppIconSize.lg
                                  : AppIconSize.nav,
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        child: Text(
                          AppStrings.t(AppStringKeys.appearanceInterfaceSize),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: pointerDense
                              ? AppTextStyle.bodyLarge(
                                  colors.textPrimary,
                                  weight: AppTextWeight.medium,
                                )
                              : AppTextStyle.title(colors.textPrimary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SettingsListView(
                children: [
                  const AppearanceView()._interfaceSizeCard(context, theme),
                  const SizedBox(height: AppSpacing.xl),
                  const AppearanceView()._interfaceSizePreview(context, theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SenderNameReadabilitySettingsView extends StatelessWidget {
  const SenderNameReadabilitySettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceSenderNameReadability),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          const _SenderNameReadabilityPreview(),
          const SizedBox(height: AppSpacing.xl),
          const AppearanceView()._card(context, [
            for (final mode in SenderNameReadabilityMode.values)
              const AppearanceView()._choiceRow(
                context,
                switch (mode) {
                  SenderNameReadabilityMode.background =>
                    HeroAppIcons.idBadge.data,
                  SenderNameReadabilityMode.blend => HeroAppIcons.droplet.data,
                  SenderNameReadabilityMode.none => HeroAppIcons.eyeSlash.data,
                },
                switch (mode) {
                  SenderNameReadabilityMode.background =>
                    AppStringKeys.appearanceSenderNameReadabilityBackground,
                  SenderNameReadabilityMode.blend =>
                    AppStringKeys.appearanceSenderNameReadabilityBlend,
                  SenderNameReadabilityMode.none =>
                    AppStringKeys.appearanceSenderNameReadabilityNone,
                },
                theme.senderNameReadabilityMode == mode,
                () => theme.senderNameReadabilityMode = mode,
              ),
          ]),
        ],
      ),
    );
  }
}

/// Every name colour a sender can be assigned, over the background they will
/// actually be read on.
///
/// One treatment can be legible on the palette's dark blue and lost on its
/// yellow, so the choice is only answerable by seeing all of them at once
/// against the current wallpaper rather than one sample name.
class _SenderNameReadabilityPreview extends StatelessWidget {
  const _SenderNameReadabilityPreview();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: ChatWallpaperController.shared,
      builder: (context, _) {
        final wallpaperController = ChatWallpaperController.shared;
        final cloudTheme = theme.cloudThemeFor(
          dark ? Brightness.dark : Brightness.light,
        );
        final selected = selectGlobalChatWallpaper(
          defaultWallpaper: wallpaperController.defaultWallpaper(dark: dark),
          cloudThemeWallpaper: cloudTheme?.wallpaper,
          globalThemeWallpaper: wallpaperController.globalThemeWallpaperFor(
            dark: dark,
          ),
        );
        final incomingBackground = theme
            .effectiveMessageBubbleBackgroundSpecFor(outgoing: false);
        final bubbleColor =
            incomingBackground.backgroundColor ??
            cloudTheme?.incomingColor ??
            c.bubbleIncoming;
        // Blend meets this halfway, so the preview has to read it from the
        // same place a real incoming bubble does.
        final bubbleTextColor =
            incomingBackground.foregroundColor ?? c.bubbleIncomingText;
        final colors = messageNameColorsForTheme(cloudTheme);
        final sample = AppStrings.t(AppStringKeys.appearancePreviewUsersSample);
        // The wallpaper expands to its constraints, and a settings list gives
        // its children unbounded height, so wrapping the names in it forces an
        // infinite height and the page lays out blank. It fills behind them
        // instead, leaving the names to decide how tall the preview is.
        return ClipRRect(
          key: const ValueKey('senderNameReadabilityPreview'),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Stack(
            children: [
              Positioned.fill(
                child: ChatWallpaperBackground(
                  wallpaper: selected == null
                      ? null
                      : wallpaperController.resolvedWallpaper(selected),
                  fallbackColor: c.chatBackground,
                  brightness: Theme.of(context).brightness,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.xxl,
                ),
                child: Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.lg,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final color in colors)
                      SenderIdentityPills(
                        readabilityMode: theme.senderNameReadabilityMode,
                        bubbleColor: bubbleColor,
                        textColor: bubbleTextColor,
                        name: sample,
                        nameStyle: TextStyle(fontSize: 12, color: color),
                        // The background treatment is a tag joined to the name,
                        // so previewing it without a tag would hide half of what
                        // is being chosen.
                        role:
                            theme.senderNameReadabilityMode ==
                                SenderNameReadabilityMode.background
                            ? MemberRole.admin
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DisplaySettingsView extends StatelessWidget {
  const DisplaySettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    const appearance = AppearanceView();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceSize),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          appearance._card(context, [
            appearance._chatViewNavigationRow(context),
          ]),
          appearance._label(
            context,
            AppStrings.t(AppStringKeys.appearanceSectionChatList),
          ),
          appearance._card(
            context,
            appearance._chatListNavigationRows(context),
          ),
          appearance._label(
            context,
            AppStrings.t(AppStringKeys.appearanceAvatarsAndSidebar),
          ),
          appearance._avatarsAndSidebarControls(context),
        ],
      ),
    );
  }
}

class MobileMessageActionMenuSettingsView extends StatelessWidget {
  const MobileMessageActionMenuSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    const appearance = AppearanceView();
    return SettingsPageScaffold(
      key: const ValueKey('mobile-message-action-menu-style-page'),
      title: AppStrings.t(AppStringKeys.appearanceMessageActionMenu),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          appearance._card(context, [
            for (final style in MobileMessageActionMenuStyle.values)
              KeyedSubtree(
                key: ValueKey('mobile-message-action-menu-style-${style.name}'),
                child: appearance._choiceRow(
                  context,
                  style.icon.data,
                  AppStrings.t(style.label),
                  theme.mobileMessageActionMenuStyle == style,
                  () => theme.mobileMessageActionMenuStyle = style,
                ),
              ),
          ]),
        ],
      ),
    );
  }
}
