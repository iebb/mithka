//
//  appearance_view.dart
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

//  外观 is the hub for theme, interface, font, and app-icon settings. Each
//  interface surface owns its controls and a live account-backed preview.
//

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/preview_texts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../chat/chat_appearance_preview.dart';
import '../chat/chat_wallpaper.dart';
import '../chat/chat_wallpaper_view.dart';
import '../chat/emoji_store.dart';
import '../chat/image_media_album_bubble.dart';
import '../chat/message_action_menu.dart';
import '../chat/message_bubble.dart';
import '../chat/message_bubble_chat_preview.dart';
import '../chat/quick_reaction_choice.dart';
import '../components/app_icons.dart';
import '../components/desktop_content_constraint.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../platform/adaptive_platform.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/emoji_font_catalog.dart';
import '../theme/global_theme_view.dart';
import '../theme/message_bubble_background.dart';
import '../theme/message_name_colors.dart';
import '../theme/system_font_catalog.dart';
import '../theme/theme_controller.dart';
import 'app_icon_controller.dart';
import 'message_bubble_settings_view.dart';
import 'quick_reaction_settings_view.dart';

class AppearanceView extends StatelessWidget {
  const AppearanceView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final appIcons = context.watch<AppIconController>();
    // The icon assets are 1024x1024; the row preview is 22 px wide, so the
    // undecoded-size default would hold a 4 MiB bitmap in the image cache.
    final appIconPreviewPx =
        (AppIconSize.nav * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: DesktopContentConstraint(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.section,
                ),
                children: [
                  // What the app looks like as a whole. No heading: it is the
                  // first card, and a "Theme" heading over a "Theme" row only
                  // says it twice.
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
                      preview: Image.asset(
                        appIcons.variant.asset,
                        width: AppIconSize.nav,
                        height: AppIconSize.nav,
                        cacheWidth: appIconPreviewPx,
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.xl),
                  _label(
                    context,
                    AppStrings.t(AppStringKeys.appearanceSectionText),
                  ),
                  _card(context, [
                    KeyedSubtree(
                      key: const ValueKey('appearance-scaling-settings-row'),
                      child: _navigationRow(
                        context,
                        AppStrings.t(AppStringKeys.appearanceInterfaceSize),
                        '${(theme.interfaceScale * 100).round()}%',
                        () => Navigator.of(context).push(
                          AppPageRoute<void>(
                            pageBuilder: (_, _, _) =>
                                const InterfaceSizeSettingsView(),
                          ),
                        ),
                        icon: HeroAppIcons.expand.data,
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
                  const SizedBox(height: AppSpacing.xl),
                  _label(
                    context,
                    AppStrings.t(AppStringKeys.appearanceSectionChat),
                  ),
                  // Message Bubbles used to sit alone in an unlabelled card;
                  // it belongs with the rest of what a conversation looks like.
                  _card(context, [
                    _chatViewNavigationRow(context),
                    KeyedSubtree(
                      key: const ValueKey('appearance-message-bubbles-row'),
                      child: _navigationRow(
                        context,
                        AppStrings.t(AppStringKeys.appearanceMessageBubbles),
                        _messageBubbleBackgroundLabel(theme),
                        () => Navigator.of(context).push(
                          AppPageRoute<void>(
                            pageBuilder: (_, _, _) =>
                                const MessageBubbleSettingsView(),
                          ),
                        ),
                        icon: HeroAppIcons.message.data,
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.xl),
                  _label(
                    context,
                    AppStrings.t(AppStringKeys.appearanceSectionChatList),
                  ),
                  _card(context, _chatListNavigationRows(context)),
                  const SizedBox(height: AppSpacing.xl),
                  _label(
                    context,
                    AppStrings.t(AppStringKeys.appearanceAvatarsAndSidebar),
                  ),
                  _avatarsAndSidebarControls(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ThemeSettingsView extends StatelessWidget {
  const ThemeSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    const appearance = AppearanceView();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceTheme),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
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
                  const SizedBox(height: AppSpacing.xl),
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
                      final dark =
                          Theme.of(context).brightness == Brightness.dark;
                      final bubbles = context.watch<ThemeController>();
                      final wallpaperController =
                          ChatWallpaperController.shared;
                      final selectedWallpaper = selectGlobalChatWallpaper(
                        defaultWallpaper: wallpaperController.defaultWallpaper(
                          dark: dark,
                        ),
                        cloudThemeWallpaper: bubbles
                            .cloudThemeFor(
                              dark ? Brightness.dark : Brightness.light,
                            )
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
                const SizedBox(height: AppSpacing.xl),
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
          ),
        ],
      ),
    );
  }
}

class _TextSizeSettingsView extends StatelessWidget {
  const _TextSizeSettingsView();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.appearanceFontSize,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                const AppearanceView()._fontSizeCard(context, theme),
                const SizedBox(height: AppSpacing.xl),
                const AppearanceView()._fontSizePreview(context, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppIconSettingsView extends StatelessWidget {
  const AppIconSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.watch<AppIconController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appIconTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Column(
              children: [
                if (!controller.supported)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      0,
                    ),
                    child: Text(
                      AppStrings.t(AppStringKeys.appIconUnsupported),
                      style: TextStyle(
                        fontSize: AppTextSize.footnote,
                        color: c.textTertiary,
                      ),
                    ),
                  ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.xl,
                      AppSpacing.section,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 132,
                          mainAxisExtent: 116,
                          mainAxisSpacing: AppSpacing.xl,
                          crossAxisSpacing: AppSpacing.xl,
                        ),
                    itemCount: AppIconVariant.values.length,
                    itemBuilder: (context, index) {
                      final variant = AppIconVariant.values[index];
                      return _AppIconVariantTile(
                        variant: variant,
                        selected: controller.variant == variant,
                        loading: controller.loading,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppIconVariantTile extends StatelessWidget {
  const _AppIconVariantTile({
    required this.variant,
    required this.selected,
    required this.loading,
  });

  final AppIconVariant variant;
  final bool selected;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final controller = context.read<AppIconController>();
    // The icon assets are 1024x1024: decoding all eight at full size holds
    // 32 MiB of image cache for tiles that are drawn at 96 px.
    final tilePx = (96 * MediaQuery.devicePixelRatioOf(context)).ceil();
    return Semantics(
      button: true,
      selected: selected,
      label: AppStrings.t(variant.labelKey),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: loading
            ? null
            : () async {
                final ok = await controller.setVariant(variant);
                if (!ok && context.mounted) {
                  showToast(context, AppStringKeys.appIconChangeFailed);
                }
              },
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: selected ? AppTheme.brand : c.divider,
                    width: selected ? 3 : 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Image.asset(
                    variant.asset,
                    fit: BoxFit.cover,
                    cacheWidth: tilePx,
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppTheme.brand,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.groupedBackground, width: 3),
                    ),
                    alignment: Alignment.center,
                    child: const AppIcon(
                      HeroAppIcons.check,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class InterfaceSizeSettingsView extends StatelessWidget {
  const InterfaceSizeSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceInterfaceSize),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                const AppearanceView()._interfaceSizeCard(context, theme),
                const SizedBox(height: AppSpacing.xl),
                const AppearanceView()._interfaceSizePreview(context, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SenderNameReadabilitySettingsView extends StatelessWidget {
  const SenderNameReadabilitySettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceSenderNameReadability),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
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
                        SenderNameReadabilityMode.blend =>
                          HeroAppIcons.droplet.data,
                        SenderNameReadabilityMode.none =>
                          HeroAppIcons.eyeSlash.data,
                      },
                      switch (mode) {
                        SenderNameReadabilityMode.background =>
                          AppStringKeys
                              .appearanceSenderNameReadabilityBackground,
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
          ),
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
        return ClipRRect(
          key: const ValueKey('senderNameReadabilityPreview'),
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: ChatWallpaperBackground(
            wallpaper: selected == null
                ? null
                : wallpaperController.resolvedWallpaper(selected),
            fallbackColor: c.chatBackground,
            brightness: Theme.of(context).brightness,
            child: Padding(
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
    final c = context.colors;
    const appearance = AppearanceView();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceSize),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                appearance._card(context, [
                  appearance._chatViewNavigationRow(context),
                ]),
                const SizedBox(height: AppSpacing.xl),
                appearance._label(
                  context,
                  AppStrings.t(AppStringKeys.appearanceSectionChatList),
                ),
                appearance._card(
                  context,
                  appearance._chatListNavigationRows(context),
                ),
                const SizedBox(height: AppSpacing.xl),
                appearance._label(
                  context,
                  AppStrings.t(AppStringKeys.appearanceAvatarsAndSidebar),
                ),
                appearance._avatarsAndSidebarControls(context),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatViewAppearanceSettingsView extends StatelessWidget {
  const ChatViewAppearanceSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    const appearance = AppearanceView();
    return _DisplaySectionPage(
      title: AppStrings.t(AppStringKeys.appearanceChatView),
      preview: const _ChatViewSettingsPreview(),
      controls: appearance._card(context, [
        appearance._toggleRow(
          context,
          HeroAppIcons.images.data,
          AppStrings.t(AppStringKeys.appearanceMergeConsecutiveImages),
          theme.groupImageMessages,
          (value) => theme.groupImageMessages = value,
        ),
        appearance._toggleRow(
          context,
          HeroAppIcons.listCheck.data,
          AppStrings.t(AppStringKeys.appearanceShowGroupMemberTitles),
          theme.showMemberTags,
          (value) => theme.showMemberTags = value,
        ),
        appearance._toggleRow(
          context,
          HeroAppIcons.idBadge.data,
          AppStrings.t(AppStringKeys.appearanceShowPlainMemberRoleTags),
          theme.showPlainMemberRoleTags,
          (value) => theme.showPlainMemberRoleTags = value,
        ),
        appearance._navigationRow(
          context,
          AppStrings.t(AppStringKeys.appearanceSenderNameReadability),
          AppStrings.t(switch (theme.senderNameReadabilityMode) {
            SenderNameReadabilityMode.background =>
              AppStringKeys.appearanceSenderNameReadabilityBackground,
            SenderNameReadabilityMode.blend =>
              AppStringKeys.appearanceSenderNameReadabilityBlend,
            SenderNameReadabilityMode.none =>
              AppStringKeys.appearanceSenderNameReadabilityNone,
          }),
          () => Navigator.of(context).push(
            AppPageRoute<void>(
              pageBuilder: (_, _, _) =>
                  const SenderNameReadabilitySettingsView(),
            ),
          ),
          icon: HeroAppIcons.eye.data,
        ),
        appearance._navigationRow(
          context,
          AppStrings.t(AppStringKeys.appearanceShowNameColors),
          _nameColorSummary(
            theme.chatNameColorAudience,
            theme.chatStatusEmojiMode,
          ),
          () => Navigator.of(context).push(
            AppPageRoute<void>(
              pageBuilder: (_, _, _) => const NameColorSettingsView(
                surface: NameColorSettingsSurface.chat,
              ),
            ),
          ),
          icon: HeroAppIcons.solidFaceSmile.data,
        ),
        appearance._toggleRow(
          context,
          HeroAppIcons.clock.data,
          AppStrings.t(AppStringKeys.appearanceAlwaysShowMessageTime),
          theme.alwaysShowMessageTime,
          (value) => theme.alwaysShowMessageTime = value,
        ),
        appearance._navigationRow(
          context,
          AppStrings.t(AppStringKeys.quickReactionsTitle),
          AppStrings.t(AppStringKeys.quickReactionsCount, {
            'value1': theme.quickReactions.length,
          }),
          () => Navigator.of(context).push(
            AppPageRoute<void>(
              pageBuilder: (_, _, _) => const QuickReactionSettingsView(),
            ),
          ),
          icon: HeroAppIcons.thumbsUp.data,
        ),
      ]),
    );
  }
}

class ChatListAppearanceSettingsView extends StatelessWidget {
  const ChatListAppearanceSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    const appearance = AppearanceView();
    return _DisplaySectionPage(
      title: AppStrings.t(AppStringKeys.appearanceChatList),
      controls: Column(
        key: const ValueKey('chat-list-merged-controls'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          appearance._card(context, [
            appearance._navigationRow(
              context,
              AppStrings.t(AppStringKeys.appearanceChatFolders),
              AppStrings.t(theme.chatFolderDisplayMode.label),
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ChatFolderSettingsView(),
                ),
              ),
              icon: HeroAppIcons.folder.data,
            ),
            KeyedSubtree(
              key: const ValueKey('chat-list-swipe-settings-row'),
              child: appearance._navigationRow(
                context,
                AppStrings.t(AppStringKeys.gesturesChatListSwipe),
                AppStrings.t(theme.chatListSwipeMode.label),
                () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) =>
                        const ChatListGestureSettingsView(),
                  ),
                ),
                icon: HeroAppIcons.arrowsRightLeft.data,
              ),
            ),
            appearance._navigationRow(
              context,
              AppStrings.t(AppStringKeys.appearanceArchivedChats),
              AppStrings.t(theme.archivedChatsDisplayMode.label),
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ArchivedChatsSettingsView(),
                ),
              ),
              icon: HeroAppIcons.inbox.data,
            ),
            appearance._toggleRow(
              context,
              HeroAppIcons.magnifyingGlass.data,
              AppStrings.t(AppStringKeys.appearanceShowChatListSearch),
              theme.showChatListSearch,
              (value) => theme.showChatListSearch = value,
            ),
            appearance._navigationRow(
              context,
              AppStrings.t(AppStringKeys.appearanceShowNameColors),
              _nameColorSummary(
                theme.chatListNameColorAudience,
                theme.chatListStatusEmojiMode,
              ),
              () => Navigator.of(context).push(
                AppPageRoute<void>(
                  pageBuilder: (_, _, _) => const NameColorSettingsView(
                    surface: NameColorSettingsSurface.chatList,
                  ),
                ),
              ),
              icon: HeroAppIcons.wandMagicSparkles.data,
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),
          appearance._label(
            context,
            AppStrings.t(AppStringKeys.appearanceUnreadBadge),
          ),
          KeyedSubtree(
            key: const ValueKey('unread-badge-controls'),
            child: appearance._card(context, [
              appearance._toggleRow(
                context,
                HeroAppIcons.message.data,
                AppStrings.t(AppStringKeys.appearanceShowUnreadChatCount),
                theme.unreadBadgeShowsChatCount,
                (value) => theme.unreadBadgeShowsChatCount = value,
              ),
              appearance._toggleRow(
                context,
                HeroAppIcons.solidBell.data,
                AppStrings.t(AppStringKeys.appearanceCapUnreadCountAt99),
                theme.capUnreadBadgeAt99,
                (value) => theme.capUnreadBadgeAt99 = value,
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _DisplaySectionPage extends StatelessWidget {
  const _DisplaySectionPage({
    required this.title,
    required this.controls,
    this.preview,
  });

  final String title;
  final Widget? preview;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: title, onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                if (preview != null) ...[
                  preview!,
                  const SizedBox(height: AppSpacing.xl),
                ],
                controls,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _nameColorSummary(
  NameColorAudience audience,
  StatusEmojiDisplayMode status,
) => '${AppStrings.t(audience.label)} · ${AppStrings.t(status.label)}';

String _messageBubbleBackgroundLabel(ThemeController theme) {
  if (!theme.messageBubblesEnabled) {
    return AppStrings.t(AppStringKeys.privacyDisabled);
  }
  return AppStrings.t(switch (theme.messageBubbleBackground) {
    MessageBubbleBackground.standard => AppStringKeys.messageBubbleDefault,
    MessageBubbleBackground.midnightAurora =>
      AppStringKeys.messageBubbleMidnightAurora,
    MessageBubbleBackground.solarPorcelain =>
      AppStringKeys.messageBubbleSolarPorcelain,
    MessageBubbleBackground.berryOrbit => AppStringKeys.messageBubbleBerryOrbit,
    MessageBubbleBackground.arcticBlueprint =>
      AppStringKeys.messageBubbleArcticBlueprint,
    MessageBubbleBackground.emberArcade =>
      AppStringKeys.messageBubbleEmberArcade,
    MessageBubbleBackground.lilacConstellation =>
      AppStringKeys.messageBubbleLilacConstellation,
    MessageBubbleBackground.forestFamiliar =>
      AppStringKeys.messageBubbleForestFamiliar,
    MessageBubbleBackground.inkWanderer =>
      AppStringKeys.messageBubbleInkWanderer,
    MessageBubbleBackground.pixelCadet => AppStringKeys.messageBubblePixelCadet,
    MessageBubbleBackground.cosmicMechanic =>
      AppStringKeys.messageBubbleCosmicMechanic,
    MessageBubbleBackground.pastryPal => AppStringKeys.messageBubblePastryPal,
    MessageBubbleBackground.noirDetective =>
      AppStringKeys.messageBubbleNoirDetective,
    MessageBubbleBackground.custom => AppStringKeys.messageBubbleCustom,
  });
}

class _ChatViewSettingsPreview extends StatefulWidget {
  const _ChatViewSettingsPreview();

  @override
  State<_ChatViewSettingsPreview> createState() =>
      _ChatViewSettingsPreviewState();
}

class _ChatViewSettingsPreviewState extends State<_ChatViewSettingsPreview> {
  static final List<ChatMessage> _albumMessages = [
    ChatMessage(
      id: -9101,
      isOutgoing: false,
      text: '',
      date: 1785862260,
      senderId: 42,
      senderName: AppStrings.t(AppStringKeys.appearancePreviewAlbumSenderName),
      senderRole: MemberRole.member,
      senderTitle: AppStrings.t(
        AppStringKeys.appearancePreviewAlbumSenderTitle,
      ),
      senderAccentColorId: 3,
      contentType: 'messagePhoto',
      mediaAlbumId: 91,
      imageWidth: 1600,
      imageHeight: 1200,
      image: TdFileRef(
        id: -9101,
        miniThumb: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAADAAAAAkCAYAAADPRbkKAAABoElEQVR42tXPDWsMABzH8f/LQ0Ye8pCHPOQhjzNmbYZ7vt3D7mH3uNt2u+127nbNJIkkkkjakkQSSSStSSKJ9PV/G7938PkYiwH+XQ3ydyHIn26I3/MhfnXC/GyH+dGK8H0uwrdmlK+zUVYbMVamY3ypx/k8FefTxAgfayN8GE/wvprgXTnJ21KSN8UUrwspXuXTvMyleZEd5XlmlGfpDMupDEvJLE8TWZ7EczyO5XgUzfMwkudBaIz7wTHuBQrcvVzgzsUit4eL3LpQ4uZQmRuDZa4PVLh2vsJif5WFc1VMGd/tG8eU8Z0zHlDGt3trmDK+ddoDyvjmyQlMGT9zwgPK+MbxSUwZXz/mAWX85NEpTBlfO+IBZXz1cB1TxlcOeUAZXzo4jSnjCwc8oIzP729gyvjcPg8o4zN7ZzBlfHqPB5Txyd2zmDI+scsDyvj4ziamjI/u8IAyPrx9DlPGB7d5QBkf2NrClPGXtnhAGT+8+QqmjB/a5AFl/ODGNqaMH9jgAWV8f08HU8afXe8BZXzfunlMGd+71gPK+FNruvwHhyS2QTVTO4sAAAAASUVORK5CYII=',
        ),
      ),
    ),
    ChatMessage(
      id: -9102,
      isOutgoing: false,
      text: AppStrings.t(AppStringKeys.appearancePreviewAlbumCaption),
      date: 1785862260,
      senderId: 42,
      senderName: AppStrings.t(AppStringKeys.appearancePreviewAlbumSenderName),
      senderRole: MemberRole.member,
      senderTitle: AppStrings.t(
        AppStringKeys.appearancePreviewAlbumSenderTitle,
      ),
      senderAccentColorId: 3,
      contentType: 'messagePhoto',
      mediaAlbumId: 91,
      imageWidth: 1200,
      imageHeight: 1600,
      image: TdFileRef(
        id: -9102,
        miniThumb: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAADAAAAAkCAYAAADPRbkKAAABh0lEQVR42tXP5y7DYQCF8f/V0Gq1WrP26l0QI0aMIEaMIEaMGEGMUKu0qCpapaUown0d572M8+H5/nss/18W/t8sGn8+0fj9iYavDzRk2cc76t9ZJoP6twzq0iz1htoX9vyK2qdX1CTSqImzhzSq71OojqVQdfeCqlsWeUblDbtOojKcREWIXT6hPMjOEyg/S8B3GofvmAXiKDt6RNnhI0oPHlC6z/buUbLLdmIo2Y6heItt3qFog61HUbQWReHqLSxlfOEKB5Tx3uUIB4Tx3iUOKOO9i2ZAGO9ZuOGAMN4zzwFlvGfumgPC+IJZMyCML5i5gqWMd0+bAWG8e4oDynj3ZJgDwnjXhBkQxrvGQ7CU8a4xMyCMzx+95IAwPn+EA8p45/AFB4TxziEOKOOdg2ZAGO8YCHJAGO/o54Ay3tF3zgFhfF6vGRDG5/WcwVLG27vNgDDe3sUBZby985QDwnhbhxkQxtvaT2Ap421tZkAYn9t6zAFhfG4LB5TxOc0BDgjjc5oC+Acf2nhjj5N6ogAAAABJRU5ErkJggg==',
        ),
      ),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Container(
      key: const ValueKey('chat-view-preview'),
      decoration: BoxDecoration(
        color: c.chatBackground,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: RepaintBoundary(
        child: ExcludeSemantics(
          child: TickerMode(
            enabled: false,
            child: SizedBox(
              height: 280,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: theme.groupImageMessages
                    ? ImageMediaAlbumBubble(
                        key: const ValueKey('chat-view-preview-album'),
                        messages: _albumMessages,
                        peerTitle: AppStrings.t(
                          AppStringKeys.appearancePreviewGroupTitle,
                        ),
                        isGroup: true,
                        meName: 'You',
                        imageBuilder: _previewAlbumImage,
                        onLongPress: _showQuickReactions,
                      )
                    : Column(
                        children: [
                          for (final message in _albumMessages)
                            MessageBubble(
                              key: ValueKey(
                                'chat-view-preview-message-${message.id}',
                              ),
                              message: message,
                              peerTitle: AppStrings.t(
                                AppStringKeys.appearancePreviewGroupTitle,
                              ),
                              isGroup: true,
                              meName: 'You',
                              onLongPress: _showQuickReactions,
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  OverlayEntry? _quickReactionOverlay;

  void _showQuickReactions(
    ChatMessage message,
    Rect? globalBounds,
    MessageActionSource _,
  ) {
    _dismissQuickReactions();
    EmojiStore.shared.loadIfNeeded();

    final overlay = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final anchorRect = globalBounds != null && overlayBox?.hasSize == true
        ? MessageActionMenu.rectInOverlay(
            globalBounds,
            globalToLocal: overlayBox!.globalToLocal,
          )
        : null;
    late final OverlayEntry entry;
    void dismiss() {
      if (_quickReactionOverlay != entry) return;
      entry.remove();
      _quickReactionOverlay = null;
    }

    entry = OverlayEntry(
      builder: (context) => _ChatViewQuickReactionOverlay(
        anchorRect: anchorRect,
        outgoing: message.isOutgoing,
        onDismiss: dismiss,
        onReaction: (_) => dismiss(),
        onExpand: dismiss,
      ),
    );
    _quickReactionOverlay = entry;
    overlay.insert(entry);
  }

  void _dismissQuickReactions() {
    _quickReactionOverlay?.remove();
    _quickReactionOverlay = null;
  }

  @override
  void dispose() {
    _dismissQuickReactions();
    super.dispose();
  }

  static Widget _previewAlbumImage(
    BuildContext context,
    ChatMessage message,
    double width,
    double height,
  ) => Image.memory(
    message.image!.miniThumb!,
    fit: BoxFit.cover,
    gaplessPlayback: true,
  );
}

class _ChatViewQuickReactionOverlay extends StatelessWidget {
  const _ChatViewQuickReactionOverlay({
    required this.anchorRect,
    required this.outgoing,
    required this.onDismiss,
    required this.onReaction,
    required this.onExpand,
  });

  final Rect? anchorRect;
  final bool outgoing;
  final VoidCallback onDismiss;
  final ValueChanged<QuickReactionChoice> onReaction;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topSafe = media.padding.top + AppSpacing.sm;
    final bottomSafe = media.size.height - media.padding.bottom - AppSpacing.sm;
    const barHeight = 46.0;
    final top = anchorRect == null
        ? (media.size.height - barHeight) / 2
        : (anchorRect!.top - barHeight - AppSpacing.sm).clamp(
            topSafe,
            bottomSafe - barHeight,
          );
    final alignment = outgoing ? Alignment.centerRight : Alignment.centerLeft;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('chat-view-preview-reaction-dismiss'),
              behavior: HitTestBehavior.opaque,
              onTap: onDismiss,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: top,
            left: 10,
            right: 10,
            child: AnimatedBuilder(
              animation: EmojiStore.shared,
              builder: (context, _) => Align(
                alignment: alignment,
                child: QuickReactionBar(
                  reactions: effectiveQuickReactions(
                    context.watch<ThemeController>().quickReactions,
                    allowCustomEmoji: EmojiStore.shared.isPremium,
                  ),
                  onReaction: onReaction,
                  onExpand: onExpand,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RepresentativeChatListRow extends StatelessWidget {
  const _RepresentativeChatListRow({required this.theme});

  final ThemeController theme;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            width: theme.avatarSize,
            height: theme.avatarSize,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: AppIcon(
              HeroAppIcons.solidMessage,
              size: AppIconSize.xl,
              color: AppTheme.brand,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.t(AppStringKeys.appearancePreviewUsersSample),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  AppStrings.t(AppStringKeys.appearancePreviewMessageSample),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTextSize.footnote,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '10:42',
                style: TextStyle(
                  fontSize: AppTextSize.caption,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text(
                  '2',
                  style: TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: AppTextSize.caption,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RepresentativeMessageBubble extends StatelessWidget {
  const _RepresentativeMessageBubble();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Align(
      key: const ValueKey('font-size-chat-preview'),
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: c.bubbleIncoming,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.t(AppStringKeys.appearancePreviewChatTextSample),
              style: TextStyle(
                fontSize: AppTextSize.bodyLarge,
                color: c.bubbleIncomingText,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '10:42',
                style: TextStyle(
                  fontSize: AppTextSize.caption,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum NameColorSettingsSurface { chat, chatList }

class NameColorSettingsView extends StatelessWidget {
  const NameColorSettingsView({required this.surface, super.key});

  final NameColorSettingsSurface surface;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = context.watch<ThemeController>();
    final isChatList = surface == NameColorSettingsSurface.chatList;
    final audience = isChatList
        ? theme.chatListNameColorAudience
        : theme.chatNameColorAudience;
    final status = isChatList
        ? theme.chatListStatusEmojiMode
        : theme.chatStatusEmojiMode;

    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(
              isChatList
                  ? AppStringKeys.appearanceChatListNameColorsTitle
                  : AppStringKeys.appearanceChatNameColorsTitle,
            ),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                const AppearanceView()._label(
                  context,
                  AppStrings.t(AppStringKeys.appearanceNameColorAudience),
                ),
                const AppearanceView()._card(context, [
                  for (final option in NameColorAudience.values)
                    const AppearanceView()._choiceRow(
                      context,
                      option.icon,
                      option.label,
                      audience == option,
                      () {
                        if (isChatList) {
                          theme.chatListNameColorAudience = option;
                        } else {
                          theme.chatNameColorAudience = option;
                        }
                      },
                    ),
                ]),
                const SizedBox(height: AppSpacing.xl),
                const AppearanceView()._label(
                  context,
                  AppStrings.t(AppStringKeys.appearanceStatusDisplay),
                ),
                const AppearanceView()._card(context, [
                  for (final option in StatusEmojiDisplayMode.values)
                    const AppearanceView()._choiceRow(
                      context,
                      option.icon,
                      option.label,
                      status == option,
                      () {
                        if (isChatList) {
                          theme.chatListStatusEmojiMode = option;
                        } else {
                          theme.chatStatusEmojiMode = option;
                        }
                      },
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatFolderSettingsView extends StatelessWidget {
  const ChatFolderSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceChatFolders),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                const AppearanceView()._card(context, [
                  for (final mode in ChatFolderDisplayMode.values)
                    const AppearanceView()._choiceRow(
                      context,
                      mode.icon,
                      mode.label,
                      theme.chatFolderDisplayMode == mode,
                      () => theme.chatFolderDisplayMode = mode,
                    ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatListGestureSettingsView extends StatelessWidget {
  const ChatListGestureSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    const appearance = AppearanceView();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.gesturesChatListSwipe),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                appearance._card(context, [
                  for (final mode in ChatListSwipeMode.values)
                    _modeRow(context, theme, mode),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeRow(
    BuildContext context,
    ThemeController theme,
    ChatListSwipeMode mode,
  ) {
    final c = context.colors;
    final selected = theme.chatListSwipeMode == mode;
    final label = AppStrings.t(mode.label);
    final description = AppStrings.t(mode.description);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label. $description',
      child: GestureDetector(
        key: ValueKey('chat-list-swipe-mode-${mode.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => theme.chatListSwipeMode = mode,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 80),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                AppIcon(mode.icon, size: AppIconSize.xl, color: AppTheme.brand),
                const SizedBox(width: AppSpacing.xl),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: AppTextSize.bodyLarge,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: AppTextSize.footnote,
                          height: 1.25,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (selected)
                  AppIcon(
                    HeroAppIcons.check,
                    size: AppIconSize.lg,
                    color: AppTheme.brand,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ArchivedChatsSettingsView extends StatelessWidget {
  const ArchivedChatsSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceArchivedChats),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: DesktopContentConstraint(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.section,
                ),
                children: [
                  const AppearanceView()._card(context, [
                    for (final mode in ArchivedChatsDisplayMode.values)
                      const AppearanceView()._choiceRow(
                        context,
                        mode.icon,
                        mode.label,
                        theme.archivedChatsDisplayMode == mode,
                        () => theme.archivedChatsDisplayMode = mode,
                      ),
                  ]),
                  if (!kIsWeb && isDesktopTargetPlatform()) ...[
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: Text(
                        AppStringKeys.appearanceArchivedChatsDesktopHint.l10n(
                          context,
                        ),
                        style: AppTextStyle.footnote(c.textSecondary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension _DisplayAppearanceHelpers on AppearanceView {
  /// What a single conversation looks like.
  Widget _chatViewNavigationRow(BuildContext context) => KeyedSubtree(
    key: const ValueKey('chat-view-settings-row'),
    child: _navigationRow(
      context,
      AppStrings.t(AppStringKeys.appearanceChatView),
      null,
      () => Navigator.of(context).push(
        AppPageRoute<void>(
          pageBuilder: (_, _, _) => const ChatViewAppearanceSettingsView(),
        ),
      ),
      icon: HeroAppIcons.message.data,
    ),
  );

  List<Widget> _chatListNavigationRows(BuildContext context) => [
    KeyedSubtree(
      key: const ValueKey('chat-list-settings-row'),
      child: _navigationRow(
        context,
        AppStrings.t(AppStringKeys.appearanceChatList),
        null,
        () => Navigator.of(context).push(
          AppPageRoute<void>(
            pageBuilder: (_, _, _) => const ChatListAppearanceSettingsView(),
          ),
        ),
        icon: HeroAppIcons.listCheck.data,
      ),
    ),
  ];

  Widget _avatarsAndSidebarControls(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return KeyedSubtree(
      key: const ValueKey('avatars-sidebar-controls'),
      child: _card(context, [
        _toggleRow(
          context,
          HeroAppIcons.users.data,
          AppStrings.t(AppStringKeys.appearanceRoundGroupAvatars),
          theme.circularGroupAvatars,
          (value) => theme.circularGroupAvatars = value,
        ),
        _toggleRow(
          context,
          HeroAppIcons.play.data,
          AppStrings.t(AppStringKeys.appearanceAnimateAvatars),
          theme.animateAvatars,
          (value) => theme.animateAvatars = value,
        ),
      ]),
    );
  }

  Widget _fontSizeCard(BuildContext context, ThemeController theme) {
    final c = context.colors;
    return SettingsPanel(
      clipBehavior: Clip.antiAlias,
      child: _scaleSlider(
        context,
        icon: HeroAppIcons.font.data,
        title: AppStrings.t(AppStringKeys.appearanceFontSize),
        value: theme.fontScale,
        min: ThemeController.minFontScale,
        max: ThemeController.maxFontScale,
        divisions: 24,
        leading: Text(
          'A',
          style: TextStyle(
            fontSize: AppTextSize.footnote,
            color: c.textSecondary,
          ),
        ),
        trailing: Text(
          'A',
          style: TextStyle(
            fontSize: AppTextSize.largeDisplay,
            color: c.textPrimary,
          ),
        ),
        onChanged: (value) => theme.fontScale = value,
      ),
    );
  }

  Widget _interfaceSizeCard(BuildContext context, ThemeController theme) {
    final c = context.colors;
    return SettingsPanel(
      clipBehavior: Clip.antiAlias,
      child: _scaleSlider(
        context,
        icon: HeroAppIcons.tableCells.data,
        title: AppStrings.t(AppStringKeys.appearanceInterfaceSize),
        value: theme.interfaceScale,
        min: ThemeController.minInterfaceScale,
        max: ThemeController.maxInterfaceScale,
        divisions: 84,
        leading: AppIcon(
          HeroAppIcons.square,
          size: AppTextSize.body,
          color: c.textSecondary,
        ),
        trailing: AppIcon(
          HeroAppIcons.square,
          size: AppIconSize.add,
          color: c.textPrimary,
        ),
        onChanged: (value) => theme.interfaceScale = value,
      ),
    );
  }

  Widget _fontSizePreview(BuildContext context, ThemeController theme) {
    return _previewCard(
      context,
      title: AppStrings.t(AppStringKeys.appearanceFontSize),
      value: theme.fontScale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.t(AppStringKeys.appearanceChatView),
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: context.colors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const _RepresentativeMessageBubble(),
          const SizedBox(height: AppSpacing.xl),
          Text(
            AppStrings.t(AppStringKeys.appearanceChatList),
            style: TextStyle(
              fontSize: AppTextSize.caption,
              color: context.colors.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            key: const ValueKey('font-size-chat-list-preview'),
            decoration: BoxDecoration(
              color: context.colors.background,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: context.colors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: _RepresentativeChatListRow(theme: theme),
          ),
        ],
      ),
    );
  }

  Widget _interfaceSizePreview(BuildContext context, ThemeController theme) {
    final c = context.colors;
    return _previewCard(
      context,
      title: AppStrings.t(AppStringKeys.appearanceInterfaceSize),
      value: theme.interfaceScale,
      child: Container(
        decoration: BoxDecoration(
          color: c.groupedBackground,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.divider),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: Row(
                  children: [
                    AppIcon(
                      HeroAppIcons.chevronLeft,
                      size: AppIconSize.lg,
                      color: c.textPrimary,
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Text(
                      AppStrings.t(AppStringKeys.appearanceTitle),
                      style: TextStyle(
                        fontSize: AppTextSize.bodyLarge,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const InsetDivider(leadingInset: 0),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: AppIcon(
                      HeroAppIcons.solidMessage,
                      size: AppIconSize.xl,
                      color: AppTheme.brand,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStrings.t(AppStringKeys.savedMessages),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTextSize.bodyLarge,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          AppStrings.t(AppStringKeys.appearanceChatView),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTextSize.footnote,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Text(
                    '10:42',
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewCard(
    BuildContext context, {
    required String title,
    required double value,
    required Widget child,
  }) {
    final c = context.colors;
    return SettingsPanel(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextSize.footnote,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),
              ),
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  fontSize: AppTextSize.footnote,
                  color: AppTheme.brand,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          child,
        ],
      ),
    );
  }

  Widget _scaleSlider(
    BuildContext context, {
    required IconData icon,
    required String title,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Widget leading,
    required Widget trailing,
    required ValueChanged<double> onChanged,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.lg,
        AppSpacing.xxl,
        AppSpacing.md,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.brand),
              const SizedBox(width: AppSpacing.xl),
              Text(
                title,
                style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                '${(value * 100).round()}%',
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              SizedBox(
                width: AppIconSize.nav,
                child: Center(child: leading),
              ),
              Expanded(
                child: _nativeSlider(
                  context,
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
              SizedBox(
                width: AppIconSize.toolbar + AppSpacing.xs,
                child: Center(child: trailing),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _nativeSlider(
    BuildContext context, {
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final c = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        void update(Offset position) {
          final fraction = (position.dx / constraints.maxWidth).clamp(0.0, 1.0);
          final step = (fraction * divisions).round() / divisions;
          onChanged(min + (max - min) * step);
        }

        final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => update(details.localPosition),
          onHorizontalDragUpdate: (details) => update(details.localPosition),
          child: SizedBox(
            height: AppMetric.hitTarget,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.linkBlue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  left: fraction * (constraints.maxWidth - 22),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: c.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.linkBlue, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Color(0x26000000), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _label(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.only(left: AppSpacing.xxl, bottom: AppSpacing.sm),
    child: Text(
      t,
      style: TextStyle(
        fontSize: AppTextSize.footnote,
        color: context.colors.textTertiary,
      ),
    ),
  );

  Widget _card(BuildContext context, List<Widget> rows) {
    return SettingsCard(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1) const InsetDivider(leadingInset: 52),
        ],
      ],
    );
  }

  Widget _choiceRow(
    BuildContext context,
    IconData icon,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Icon(icon, size: AppIconSize.xl, color: AppTheme.brand),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Text(
                  label.l10n(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    color: c.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (selected)
                AppIcon(
                  HeroAppIcons.check,
                  size: AppIconSize.lg,
                  color: AppTheme.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleRow(
    BuildContext context,
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool>? onChanged,
  ) {
    final c = context.colors;
    final enabled = onChanged != null;
    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.xxs,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            Icon(
              icon,
              size: AppIconSize.xl,
              color: enabled ? AppTheme.brand : c.textTertiary,
            ),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  color: enabled ? c.textPrimary : c.textTertiary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            AppSwitch(
              value: value,
              enabled: enabled,
              onChanged: onChanged ?? (_) {},
            ),
          ],
        ),
      ),
    );
  }

  Widget _navigationRow(
    BuildContext context,
    String label,
    String? value,
    VoidCallback onTap, {
    IconData? icon,
    Widget? preview,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppIconSize.xl, color: AppTheme.brand),
                const SizedBox(width: AppSpacing.xl),
              ] else if (preview != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: preview,
                ),
                const SizedBox(width: AppSpacing.xl),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: value == null ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    color: c.textPrimary,
                  ),
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: AppSpacing.lg),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(
                      MediaQuery.sizeOf(context).width * 0.42,
                      190,
                    ),
                  ),
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: AppTextSize.body,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.sm),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: AppIconSize.lg,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FontSettingsView extends StatelessWidget {
  const FontSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceFont),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.appearanceFontSize),
                      value: '${(theme.fontScale * 100).round()}%',
                      height: AppMetric.compactSettingsRowHeight,
                      onTap: () => Navigator.of(context).push(
                        AppPageRoute<void>(
                          pageBuilder: (_, _, _) =>
                              const _TextSizeSettingsView(),
                        ),
                      ),
                    ),
                    const InsetDivider(leadingInset: AppSpacing.xxl),
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.appearanceTextFont),
                      value: theme.effectiveFontChainLabel,
                      height: AppMetric.compactSettingsRowHeight,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TextFontView()),
                      ),
                    ),
                    const InsetDivider(leadingInset: AppSpacing.xxl),
                    SettingsRow(
                      title: AppStrings.t(
                        AppStringKeys.appearanceMonospaceFont,
                      ),
                      value: theme.effectiveMonospaceFontLabel,
                      height: AppMetric.compactSettingsRowHeight,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MonospaceFontPickerView(),
                        ),
                      ),
                    ),
                    const InsetDivider(leadingInset: AppSpacing.xxl),
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.appearanceEmojiFont),
                      value: theme.emojiFontChoice.label,
                      height: AppMetric.compactSettingsRowHeight,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EmojiFontPickerView(),
                        ),
                      ),
                    ),
                    const InsetDivider(leadingInset: AppSpacing.xxl),
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.appearanceFontCache),
                      value: AppStrings.t(AppStringKeys.appearanceManage),
                      height: AppMetric.compactSettingsRowHeight,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FontCacheManagementView(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                  child: Text(
                    AppStrings.t(AppStringKeys.appearanceFontChainDescription),
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FontCacheManagementView extends StatefulWidget {
  const FontCacheManagementView({super.key});

  @override
  State<FontCacheManagementView> createState() =>
      _FontCacheManagementViewState();
}

class _FontCacheManagementViewState extends State<FontCacheManagementView> {
  late Future<_FontCacheSnapshot> _snapshot = _loadSnapshot();
  _FontCacheOperation? _operation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceFontCache),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: FutureBuilder<_FontCacheSnapshot>(
              future: _snapshot,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.section,
                  ),
                  children: [
                    _summaryCard(context, data),
                    const SizedBox(height: AppSpacing.xl),
                    _actionCard(context, data),
                    const SizedBox(height: AppSpacing.xl),
                    _fontFilesCard(context, data),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxl,
                      ),
                      child: Text(
                        AppStrings.t(
                          AppStringKeys.appearanceFontCacheDescription,
                        ),
                        style: TextStyle(
                          fontSize: AppTextSize.footnote,
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<_FontCacheSnapshot> _loadSnapshot() async {
    final theme = context.read<ThemeController>();
    final supportDir = await getApplicationSupportDirectory();
    final activeFamilies = _activeGoogleFamilies(theme);
    final byFamily = <String, _FontCacheEntry>{};
    if (await supportDir.exists()) {
      await for (final entity in supportDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final entry = await _FontCacheEntry.tryFromFile(entity, activeFamilies);
        if (entry == null) continue;
        final key = entry.normalizedDisplayName;
        final current = byFamily[key];
        byFamily[key] = current == null ? entry : current.merged(entry);
      }
    }
    final entries = byFamily.values.toList();
    entries.sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return _FontCacheSnapshot(entries);
  }

  Set<String> _activeGoogleFamilies(ThemeController theme) {
    final googleFamilies = GoogleFonts.asMap().keys.toSet();
    final active = <String>{};
    void addIfGoogle(String? family) {
      final value = family?.trim();
      if (value == null || value.isEmpty) return;
      final decoded = decodeGoogleFontFamily(value) ?? value;
      if (googleFamilies.contains(decoded)) active.add(decoded);
    }

    for (final family in theme.fontFallbackChain) {
      addIfGoogle(family);
    }
    addIfGoogle(theme.monospaceFontChoice.googleFamily);
    if (theme.monospaceFontChoice.isCustom) {
      addIfGoogle(theme.customMonospaceFontFamily);
    }
    return active;
  }

  Widget _summaryCard(BuildContext context, _FontCacheSnapshot data) {
    return _cacheCard(context, [
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceCacheFiles),
        AppStrings.t(AppStringKeys.appearanceFileCount, {
          'value1': data.entries.length,
        }),
      ),
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceTotalSize),
        _formatBytes(data.totalBytes),
      ),
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceInUseSize),
        AppStrings.t(AppStringKeys.appearanceFileCount, {
          'value1': data.activeCount,
        }),
      ),
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceCleanableSize),
        AppStrings.t(AppStringKeys.appearanceFileCount, {
          'value1': data.unusedCount,
        }),
      ),
    ]);
  }

  Widget _actionCard(BuildContext context, _FontCacheSnapshot data) {
    final busy = _operation != null;
    return _cacheCard(context, [
      _actionRow(
        context,
        AppStrings.t(AppStringKeys.appearanceRefreshCacheList),
        HeroAppIcons.arrowsRotate.data,
        busy ? null : _refreshSnapshot,
        busy: _operation == _FontCacheOperation.refreshing,
        status: _operation == _FontCacheOperation.refreshed
            ? AppStrings.t(AppStringKeys.appearanceCacheRefreshed)
            : null,
      ),
      _actionRow(
        context,
        AppStrings.t(AppStringKeys.appearanceCleanUnusedFonts),
        HeroAppIcons.trash.data,
        busy || data.unusedCount == 0 ? null : () => _deleteUnused(data),
        destructive: true,
        busy: _operation == _FontCacheOperation.deletingUnused,
        status: _operation == _FontCacheOperation.deletedUnused
            ? AppStrings.t(AppStringKeys.appearanceCacheCleaned)
            : data.unusedCount == 0
            ? AppStrings.t(AppStringKeys.appearanceNoCleanableFonts)
            : null,
      ),
    ]);
  }

  Widget _fontFilesCard(BuildContext context, _FontCacheSnapshot data) {
    final c = context.colors;
    if (data.entries.isEmpty) {
      return SettingsPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xxl,
        ),
        child: Text(
          AppStrings.t(AppStringKeys.appearanceNoDownloadedFontCache),
          style: TextStyle(fontSize: AppTextSize.body, color: c.textSecondary),
        ),
      );
    }
    return _cacheCard(context, [
      for (final entry in data.entries) _fileRow(context, entry),
    ]);
  }

  Widget _cacheCard(BuildContext context, List<Widget> rows) {
    return SettingsCard(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1)
            const InsetDivider(leadingInset: AppSpacing.xxl),
        ],
      ],
    );
  }

  Widget _plainRow(BuildContext context, String label, String value) {
    final c = context.colors;
    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.xxs,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.bodyLarge,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback? onTap, {
    bool destructive = false,
    bool busy = false,
    String? status,
  }) {
    final c = context.colors;
    final enabled = onTap != null && !busy;
    final color = destructive ? AppTheme.unreadBadge : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Opacity(
          opacity: enabled || busy || status != null ? 1 : 0.35,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Row(
              children: [
                Icon(icon, size: AppIconSize.xl, color: color),
                const SizedBox(width: AppSpacing.lg),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    color: color,
                  ),
                ),
                const Spacer(),
                if (busy)
                  SizedBox(
                    width: AppIconSize.lg,
                    height: AppIconSize.lg,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: destructive
                          ? AppTheme.unreadBadge
                          : AppTheme.brand,
                    ),
                  )
                else if (status != null)
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      color: c.textTertiary,
                    ),
                  )
                else
                  AppIcon(
                    HeroAppIcons.chevronRight,
                    size: AppIconSize.lg,
                    color: enabled && !destructive
                        ? c.textTertiary
                        : Colors.transparent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileRow(BuildContext context, _FontCacheEntry entry) {
    final c = context.colors;
    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.bodyLarge,
                      color: c.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatBytes(entry.bytes)} · ${entry.modifiedLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              entry.active
                  ? AppStrings.t(AppStringKeys.appearanceFontInUse)
                  : AppStrings.t(AppStringKeys.appearanceFontUnused),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: AppTextSize.footnote,
                color: entry.active ? AppTheme.brand : c.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: entry.active ? null : () => _deleteEntry(entry),
              child: SizedBox(
                width: AppMetric.hitTarget,
                height: AppMetric.hitTarget,
                child: Opacity(
                  opacity: entry.active ? 0.2 : 1,
                  child: Center(
                    child: AppIcon(
                      HeroAppIcons.trash,
                      size: AppIconSize.xl,
                      color: entry.active
                          ? c.textTertiary
                          : AppTheme.unreadBadge,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshSnapshot() async {
    if (_operation != null) return;
    setState(() {
      _operation = _FontCacheOperation.refreshing;
    });
    final snapshot = await _loadSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = Future.value(snapshot);
      _operation = _FontCacheOperation.refreshed;
    });
    _clearOperationSoon(_FontCacheOperation.refreshed);
  }

  Future<void> _deleteUnused(_FontCacheSnapshot data) async {
    if (_operation != null) return;
    setState(() {
      _operation = _FontCacheOperation.deletingUnused;
    });
    for (final entry in data.entries.where((entry) => !entry.active)) {
      try {
        await entry.deleteFiles();
      } catch (_) {
        // The cache may have been removed by the font loader or the OS.
      }
    }
    if (!mounted) return;
    final snapshot = await _loadSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = Future.value(snapshot);
      _operation = _FontCacheOperation.deletedUnused;
    });
    _clearOperationSoon(_FontCacheOperation.deletedUnused);
  }

  Future<void> _deleteEntry(_FontCacheEntry entry) async {
    try {
      await entry.deleteFiles();
    } catch (_) {
      // The cache may have been removed by the font loader or the OS.
    }
    if (!mounted) return;
    final snapshot = await _loadSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = Future.value(snapshot);
    });
  }

  void _clearOperationSoon(_FontCacheOperation operation) {
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _operation != operation) return;
      setState(() {
        _operation = null;
      });
    });
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    if (unit == 0) return '$bytes ${units[unit]}';
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
  }
}

class _FontCacheSnapshot {
  const _FontCacheSnapshot(this.entries);

  final List<_FontCacheEntry> entries;

  int get totalBytes =>
      entries.fold<int>(0, (total, entry) => total + entry.bytes);
  int get activeCount => entries.where((entry) => entry.active).length;
  int get unusedCount => entries.length - activeCount;
}

enum _FontCacheOperation {
  refreshing,
  refreshed,
  deletingUnused,
  deletedUnused,
}

class _FontCacheEntry {
  const _FontCacheEntry({
    required this.files,
    required this.displayName,
    required this.bytes,
    required this.modified,
    required this.active,
  });

  static final _cacheFilePattern = RegExp(r'^(.+)_([a-fA-F0-9]{16,128})\.ttf$');

  final List<File> files;
  final String displayName;
  final int bytes;
  final DateTime modified;
  final bool active;

  String get normalizedDisplayName => _normalize(displayName);

  String get modifiedLabel {
    final local = modified.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  static Future<_FontCacheEntry?> tryFromFile(
    File file,
    Set<String> activeGoogleFamilies,
  ) async {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    final match = _cacheFilePattern.firstMatch(name);
    if (match == null) return null;
    final rawFamily = match.group(1)!;
    final displayName = _displayName(rawFamily);
    final stat = await file.stat();
    final normalizedFile = _normalize(rawFamily);
    final active = activeGoogleFamilies.any((family) {
      final normalizedFamily = _normalize(family);
      return normalizedFile.contains(normalizedFamily) ||
          normalizedFamily.contains(normalizedFile);
    });
    return _FontCacheEntry(
      files: [file],
      displayName: displayName,
      bytes: stat.size,
      modified: stat.modified,
      active: active,
    );
  }

  _FontCacheEntry merged(_FontCacheEntry other) {
    return _FontCacheEntry(
      files: [...files, ...other.files],
      displayName: displayName,
      bytes: bytes + other.bytes,
      modified: modified.isAfter(other.modified) ? modified : other.modified,
      active: active || other.active,
    );
  }

  Future<void> deleteFiles() async {
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Individual cache files can disappear while the list is open.
      }
    }
  }

  static String _displayName(String rawFamily) {
    final value = rawFamily
        .replaceAll(RegExp(r'_(regular|italic)$', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'_(100|200|300|400|500|600|700|800|900)(italic)?$'),
          '',
        )
        .replaceAll('_', ' ');
    return value.trim().isEmpty ? rawFamily : value.trim();
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

Future<Set<String>> _cachedGoogleFontFamilies() async {
  final googleFamilies = GoogleFonts.asMap().keys.toList();
  final byNormalized = {
    for (final family in googleFamilies)
      _FontCacheEntry._normalize(family): family,
  };
  final supportDir = await getApplicationSupportDirectory();
  final cached = <String>{};
  if (!await supportDir.exists()) return cached;
  await for (final entity in supportDir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.isEmpty
        ? entity.path
        : entity.uri.pathSegments.last;
    final match = _FontCacheEntry._cacheFilePattern.firstMatch(name);
    if (match == null) continue;
    final rawFamily = match.group(1)!;
    final normalizedFile = _FontCacheEntry._normalize(rawFamily);
    final exact = byNormalized[normalizedFile];
    if (exact != null) {
      cached.add(exact);
      continue;
    }
    for (final entry in byNormalized.entries) {
      if (normalizedFile.contains(entry.key) ||
          entry.key.contains(normalizedFile)) {
        cached.add(entry.value);
        break;
      }
    }
  }
  return cached;
}

List<String> _fontTitleFallback() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => const [
      '.AppleSystemUIFont',
      'SF Pro',
      'Helvetica Neue',
      'Arial',
    ],
    TargetPlatform.android => const ['sans-serif', 'Roboto', 'Noto Sans'],
    _ => const ['sans-serif', 'Arial'],
  };
}

TextStyle _fontTitleStyle(
  String family,
  TextStyle base, {
  String? googleFamily,
  bool googleLoaded = false,
}) {
  final fallback = _fontTitleFallback();
  if (googleFamily != null && googleLoaded) {
    return GoogleFonts.getFont(
      googleFamily,
      textStyle: base,
    ).copyWith(fontFamilyFallback: fallback);
  }
  if (googleFamily != null) return base.copyWith(fontFamilyFallback: fallback);
  return base.copyWith(fontFamily: family, fontFamilyFallback: fallback);
}

String _fontPreviewSample() => appFontPreviewText;

int _popularSystemFontPriority(String family) {
  final popular = switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => const [
      '.AppleSystemUIFont',
      'SF Pro',
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
      'PingFang SC',
      'PingFang TC',
      'PingFang HK',
      'Hiragino Sans',
    ],
    TargetPlatform.android => const [
      'sans',
      'sans-serif',
      'Roboto',
      'Noto Sans',
      'Noto Serif',
      'Droid Sans',
      'monospace',
      'serif',
    ],
    _ => const [
      'Arial',
      'Helvetica',
      'Verdana',
      'Tahoma',
      'Georgia',
      'Times New Roman',
      'Courier New',
      'monospace',
      'sans-serif',
      'serif',
    ],
  };
  final exact = popular.indexWhere(
    (font) => font.toLowerCase() == family.toLowerCase(),
  );
  if (exact >= 0) return exact;
  final prefix = popular.indexWhere(
    (font) => family.toLowerCase().startsWith(font.toLowerCase()),
  );
  return prefix >= 0 ? prefix : popular.length + 1;
}

const _googleMonospaceFamilies = {
  'Anonymous Pro',
  'Azeret Mono',
  'B612 Mono',
  'Chivo Mono',
  'Courier Prime',
  'Cousine',
  'Cutive Mono',
  'DM Mono',
  'Datatype',
  'Fira Code',
  'Fira Mono',
  'Fragment Mono',
  'Geist Mono',
  'Google Sans Code',
  'IBM Plex Mono',
  'Inconsolata',
  'Intel One Mono',
  'Iosevka Charon',
  'Iosevka Charon Mono',
  'JetBrains Mono',
  'Kode Mono',
  'LXGW WenKai Mono TC',
  'Lekton',
  'Libertinus Mono',
  'Lilex',
  'M PLUS 1 Code',
  'M PLUS Code Latin',
  'Major Mono Display',
  'Martian Mono',
  'Monofett',
  'Nanum Gothic Coding',
  'Noto Sans Mono',
  'Nova Mono',
  'Overpass Mono',
  'Oxygen Mono',
  'PT Mono',
  'Red Hat Mono',
  'Reddit Mono',
  'Roboto Mono',
  'Rubik Mono One',
  'Share Tech Mono',
  'Sixtyfour',
  'Sixtyfour Convergence',
  'Sometype Mono',
  'Sono',
  'Source Code Pro',
  'Space Mono',
  'Spline Sans Mono',
  'Syne Mono',
  'Ubuntu Mono',
  'Ubuntu Sans Mono',
  'VT323',
  'Victor Mono',
  'Workbench',
  'Xanh Mono',
};

bool _isSystemMonospaceFontFamily(String family) {
  final normalized = family.toLowerCase();
  return normalized.contains('mono') ||
      normalized.contains('menlo') ||
      normalized.contains('courier');
}

class TextFontView extends StatelessWidget {
  const TextFontView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final fonts = theme.fontFallbackChain;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceTextFont),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                _chainCard(context, fonts),
                const SizedBox(height: AppSpacing.xl),
                _actionCard(context, theme),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxl,
                  ),
                  child: Text(
                    AppStrings.t(AppStringKeys.appearanceTextFontOrderHint),
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chainCard(BuildContext context, List<String> fonts) {
    final c = context.colors;
    if (fonts.isEmpty) {
      return SettingsPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xxl,
        ),
        child: Text(
          AppStrings.t(AppStringKeys.appearanceTextFontUnsetHint),
          style: TextStyle(fontSize: AppTextSize.body, color: c.textSecondary),
        ),
      );
    }
    return SettingsPanel(
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: fonts.length,
        onReorderItem: context.read<ThemeController>().moveFontInFallbackChain,
        itemBuilder: (context, index) {
          final family = fonts[index];
          return Column(
            key: ValueKey('font-chain-$family-$index'),
            children: [
              _chainRow(context, family, index),
              if (index < fonts.length - 1)
                const InsetDivider(leadingInset: AppSpacing.xxl),
            ],
          );
        },
      ),
    );
  }

  Widget _chainRow(BuildContext context, String family, int index) {
    final c = context.colors;
    final googleFamily = decodeGoogleFontFamily(family);
    final displayFamily = displayStoredFontFamily(family);
    TextStyle previewStyle(TextStyle base) {
      if (googleFamily != null) {
        return GoogleFonts.getFont(googleFamily, textStyle: base);
      }
      return base.copyWith(fontFamily: family);
    }

    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: AppIcon(
                HeroAppIcons.bars,
                size: AppIconSize.xl,
                color: c.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayFamily,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _fontTitleStyle(
                      family,
                      TextStyle(
                        fontSize: AppTextSize.bodyLarge,
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      googleFamily: googleFamily,
                      googleLoaded: googleFamily != null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fontPreviewSample(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: previewStyle(
                      TextStyle(
                        fontSize: AppTextSize.footnote,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context
                  .read<ThemeController>()
                  .removeFontFromFallbackChainAt(index),
              child: SizedBox(
                width: AppMetric.hitTarget,
                height: AppMetric.hitTarget,
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.trash,
                    size: AppIconSize.xl,
                    color: c.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(BuildContext context, ThemeController theme) {
    return SettingsCard(
      children: [
        _actionRow(
          context,
          AppStrings.t(AppStringKeys.appearanceAddTextFont),
          HeroAppIcons.plus.data,
          () async {
            final family = await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => const FontAddView()),
            );
            if (family == null || !context.mounted) return;
            context.read<ThemeController>().addFontToFallbackChain(family);
          },
        ),
        if (theme.fontFallbackChain.isNotEmpty) ...[
          const InsetDivider(leadingInset: AppSpacing.xxl),
          _actionRow(
            context,
            AppStrings.t(AppStringKeys.appearanceClearTextFonts),
            HeroAppIcons.xmark.data,
            () => context.read<ThemeController>().setFontFallbackChain(
              const <String>[],
            ),
            destructive: true,
          ),
        ],
      ],
    );
  }

  Widget _actionRow(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    final c = context.colors;
    final color = destructive ? AppTheme.unreadBadge : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Icon(icon, size: AppIconSize.xl, color: color),
              const SizedBox(width: AppSpacing.lg),
              Text(
                title,
                style: TextStyle(fontSize: AppTextSize.bodyLarge, color: color),
              ),
              const Spacer(),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: AppIconSize.lg,
                color: destructive ? Colors.transparent : c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmojiFontPickerView extends StatefulWidget {
  const EmojiFontPickerView({super.key});

  @override
  State<EmojiFontPickerView> createState() => _EmojiFontPickerViewState();
}

class _EmojiFontPickerViewState extends State<EmojiFontPickerView> {
  static const _fallbackPreviewAsset = 'assets/emoji_preview/noto.svg';
  static const _previewAssets = {
    'noto': 'assets/emoji_preview/noto.svg',
    'noto-mono': 'assets/emoji_preview/noto-mono.svg',
    'blobmoji': 'assets/emoji_preview/blobmoji.svg',
    'fluent': 'assets/emoji_preview/fluent.png',
    'fluent-flat': 'assets/emoji_preview/fluent-flat.svg',
    'fluent-mono': 'assets/emoji_preview/fluent-mono.svg',
    'twemoji': 'assets/emoji_preview/twemoji.svg',
    'openmoji': 'assets/emoji_preview/openmoji.svg',
    'emojitwo': 'assets/emoji_preview/emojitwo.svg',
    'tossface': 'assets/emoji_preview/tossface.svg',
  };

  late final Future<List<EmojiFontManifestEntry>> _fonts = EmojiFontCatalog
      .shared
      .loadManifest(forceRefresh: true);
  String? _loadingKey;
  String? _failedKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceEmojiFont),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: FutureBuilder<List<EmojiFontManifestEntry>>(
              future: _fonts,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError && !snapshot.hasData) {
                  return Center(
                    child: Text(
                      AppStrings.t(AppStringKeys.appearanceFontLoadFailed),
                      style: TextStyle(
                        fontSize: AppTextSize.bodyLarge,
                        color: c.textSecondary,
                      ),
                    ),
                  );
                }
                final entries =
                    snapshot.data ?? const <EmojiFontManifestEntry>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.section,
                  ),
                  children: [
                    SettingsCard(
                      children: [
                        _systemRow(context, theme),
                        if (entries.isNotEmpty)
                          const InsetDivider(leadingInset: AppSpacing.xxl),
                        for (var i = 0; i < entries.length; i++) ...[
                          _entryRow(context, entries[i], theme),
                          if (i < entries.length - 1)
                            const InsetDivider(leadingInset: AppSpacing.xxl),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxl,
                      ),
                      child: Text(
                        AppStrings.t(
                          AppStringKeys.appearanceEmojiFontCatalogDescription,
                        ),
                        style: TextStyle(
                          fontSize: AppTextSize.footnote,
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _systemRow(BuildContext context, ThemeController theme) {
    return _row(
      context,
      title: EmojiFontChoice.system.label,
      subtitle: AppStrings.t(AppStringKeys.appearanceSystemEmojiFont),
      preview: const _SystemEmojiPreview(),
      selected: theme.emojiFontChoice.isSystem,
      loading: false,
      failed: false,
      onTap: () {
        context.read<ThemeController>().useSystemEmojiFont();
        setState(() {
          _loadingKey = null;
          _failedKey = null;
        });
      },
    );
  }

  Widget _entryRow(
    BuildContext context,
    EmojiFontManifestEntry entry,
    ThemeController theme,
  ) {
    return _row(
      context,
      title: entry.label,
      subtitle: [
        entry.license,
        if (entry.emojiVersion.isNotEmpty) 'Emoji ${entry.emojiVersion}',
      ].where((part) => part.isNotEmpty).join(' · '),
      preview: _EmojiPreviewImage(asset: _previewAssetForKey(entry.key)),
      selected: theme.emojiFontChoice.key == entry.key,
      loading: _loadingKey == entry.key,
      failed: _failedKey == entry.key,
      onTap: () async {
        if (_loadingKey != null) return;
        setState(() {
          _loadingKey = entry.key;
          _failedKey = null;
        });
        try {
          await context.read<ThemeController>().setEmojiFont(entry);
        } catch (_) {
          if (mounted) setState(() => _failedKey = entry.key);
        } finally {
          if (mounted) setState(() => _loadingKey = null);
        }
      },
    );
  }

  Widget _row(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget preview,
    required bool selected,
    required bool loading,
    required bool failed,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Semantics(
                  label: AppStringKeys.emojiPreviewFaceWithTearsOfJoy.l10n(
                    context,
                  ),
                  image: true,
                  child: ExcludeSemantics(child: preview),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTextSize.bodyLarge,
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      failed
                          ? AppStrings.t(
                              AppStringKeys.appearanceFontDownloadFailedName,
                              {'value1': subtitle},
                            )
                          : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTextSize.footnote,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: AppIconSize.lg,
                  height: AppIconSize.lg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (selected)
                AppIcon(
                  HeroAppIcons.check,
                  size: AppIconSize.lg,
                  color: AppTheme.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewAssetForKey(String key) =>
      _previewAssets[key] ?? _fallbackPreviewAsset;
}

/// Draws the preview glyph with the platform emoji font itself, so the row
/// shows what the system default actually looks like instead of a bundled
/// picture of somebody else's emoji set.
class _SystemEmojiPreview extends StatelessWidget {
  const _SystemEmojiPreview();

  static const _faceWithTearsOfJoy = '\u{1F602}';

  @override
  Widget build(BuildContext context) {
    final families = EmojiFontChoice.platformEmojiFontFallback();
    return SizedBox(
      width: 26,
      height: 26,
      child: Center(
        child: Text(
          _faceWithTearsOfJoy,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            height: 1,
            fontFamily: families.firstOrNull,
            fontFamilyFallback: families.skip(1).toList(),
          ),
        ),
      ),
    );
  }
}

class _EmojiPreviewImage extends StatelessWidget {
  const _EmojiPreviewImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    if (asset.endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        width: 26,
        height: 26,
        placeholderBuilder: (_) => const _TearJoyFallbackIcon(),
        errorBuilder: (_, _, _) => const _TearJoyFallbackIcon(),
      );
    }
    return Image.asset(
      asset,
      width: 26,
      height: 26,
      errorBuilder: (_, _, _) => const _TearJoyFallbackIcon(),
    );
  }
}

class _TearJoyFallbackIcon extends StatelessWidget {
  const _TearJoyFallbackIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(painter: _TearJoyFallbackPainter()),
    );
  }
}

class _TearJoyFallbackPainter extends CustomPainter {
  const _TearJoyFallbackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final face = Paint()..color = const Color(0xFFFFD447);
    final stroke = Paint()
      ..color = const Color(0xFF5A3210)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.08;
    final tear = Paint()..color = const Color(0xFF37A8FF);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.43;
    canvas.drawCircle(center, radius, face);

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.34, size.height * 0.39),
        width: size.width * 0.28,
        height: size.height * 0.18,
      ),
      0.15,
      2.6,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.66, size.height * 0.39),
        width: size.width * 0.28,
        height: size.height * 0.18,
      ),
      0.4,
      2.6,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.55),
        width: size.width * 0.48,
        height: size.height * 0.34,
      ),
      0.1,
      2.95,
      false,
      stroke,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.18, size.height * 0.58),
        width: size.width * 0.18,
        height: size.height * 0.28,
      ),
      tear,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.82, size.height * 0.58),
        width: size.width * 0.18,
        height: size.height * 0.28,
      ),
      tear,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FontAddView extends StatefulWidget {
  const FontAddView({super.key});

  @override
  State<FontAddView> createState() => _FontAddViewState();
}

class _FontAddViewState extends State<FontAddView> {
  late final Future<List<_FontCandidate>> _fonts = _loadFonts();
  String _query = '';
  String? _loadingGoogleFamily;
  String? _failedGoogleFamily;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<List<_FontCandidate>> _loadFonts() async {
    final systemFonts = await SystemFontCatalog.loadFonts();
    final cachedGoogleFamilies = await _cachedGoogleFontFamilies();
    final candidates = <_FontCandidate>[
      for (final font in systemFonts)
        _FontCandidate(
          label: font,
          family: font,
          preview: _fontPreviewSample(),
          source: AppStringKeys.appearanceSystem,
          priority: _popularSystemFontPriority(font),
        ),
      for (final family in GoogleFonts.asMap().keys)
        _FontCandidate(
          label: family,
          family: family,
          preview: _fontPreviewSample(),
          source: 'Google',
          google: true,
          downloaded: cachedGoogleFamilies.contains(family),
        ),
    ];
    return candidates..sort((a, b) {
      final sourceCompare = a.sourceOrder.compareTo(b.sourceOrder);
      if (sourceCompare != 0) return sourceCompare;
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.lowerLabel.compareTo(b.lowerLabel);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceAddFont),
            onBack: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: CupertinoSearchTextField(
              placeholder: AppStrings.t(AppStringKeys.appearanceSearchFont),
              itemColor: c.textTertiary,
              prefixIcon: AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: AppIconSize.lg,
                color: c.textTertiary,
              ),
              suffixIcon: Icon(
                HeroAppIcons.circleXmark.data,
                size: AppIconSize.lg,
                color: c.textTertiary,
              ),
              // Each filter pass scans the ~1900 Google families; a keystroke
              // burst should only pay for the query the user settles on.
              onChanged: (value) {
                final next = value.trim();
                _searchDebounce?.cancel();
                if (next == _query) return;
                _searchDebounce = Timer(
                  const Duration(milliseconds: 150),
                  () => setState(() => _query = next),
                );
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_FontCandidate>>(
              future: _fonts,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final query = _query.toLowerCase();
                final fonts = snapshot.data!
                    .where(
                      (font) =>
                          query.isEmpty ||
                          font.lowerLabel.contains(query) ||
                          font.lowerFamily.contains(query),
                    )
                    .toList();
                return _fontList(context, fonts);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _fontList(BuildContext context, List<_FontCandidate> fonts) {
    final c = context.colors;
    if (fonts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.section,
        ),
        children: [
          SettingsPanel(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              AppStrings.t(AppStringKeys.appearanceNoMatchingFonts),
              style: TextStyle(
                fontSize: AppTextSize.body,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.section,
      ),
      itemCount: fonts.length,
      itemBuilder: (context, index) => _virtualRow(
        context,
        first: index == 0,
        last: index == fonts.length - 1,
        child: _fontRow(context, fonts[index]),
      ),
      separatorBuilder: (context, index) => ColoredBox(
        color: c.card,
        child: const InsetDivider(leadingInset: AppSpacing.xxl),
      ),
    );
  }

  Widget _virtualRow(
    BuildContext context, {
    required bool first,
    required bool last,
    required Widget child,
  }) {
    const radius = Radius.circular(AppRadius.card);
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: first ? radius : Radius.zero,
        bottom: last ? radius : Radius.zero,
      ),
      child: ColoredBox(color: context.colors.card, child: child),
    );
  }

  Widget _fontRow(BuildContext context, _FontCandidate font) {
    final c = context.colors;
    final loading = font.google && _loadingGoogleFamily == font.family;
    final failed = font.google && _failedGoogleFamily == font.family;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectFont(context, font),
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      font.label.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.titleStyle(
                        TextStyle(
                          fontSize: AppTextSize.bodyLarge,
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      font.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.previewStyle(
                        TextStyle(
                          fontSize: AppTextSize.footnote,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                failed
                    ? AppStrings.t(AppStringKeys.appearanceDownloadFailed)
                    : font.google && font.downloaded
                    ? AppStrings.t(AppStringKeys.appearanceGoogleDownloaded)
                    : font.source.l10n(context),
                style: TextStyle(
                  fontSize: AppTextSize.footnote,
                  color: c.textTertiary,
                ),
              ),
              if (loading) ...[
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 48,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppTheme.brand,
                    backgroundColor: c.divider,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectFont(BuildContext context, _FontCandidate font) async {
    if (!font.google) {
      Navigator.of(context).pop(font.selectionFamily);
      return;
    }
    if (_loadingGoogleFamily != null) return;
    setState(() {
      _loadingGoogleFamily = font.family;
      _failedGoogleFamily = null;
    });
    try {
      GoogleFonts.getFont(font.family, textStyle: const TextStyle());
      await GoogleFonts.pendingFonts();
      if (!context.mounted) return;
      Navigator.of(context).pop(font.selectionFamily);
    } catch (_) {
      if (!mounted || _loadingGoogleFamily != font.family) return;
      setState(() => _failedGoogleFamily = font.family);
    } finally {
      if (mounted && _loadingGoogleFamily == font.family) {
        setState(() => _loadingGoogleFamily = null);
      }
    }
  }
}

class _FontCandidate {
  _FontCandidate({
    required this.label,
    required this.family,
    required this.preview,
    required this.source,
    this.google = false,
    this.downloaded = false,
    this.priority = 0,
  }) : lowerLabel = label.toLowerCase(),
       lowerFamily = family.toLowerCase();

  final String label;
  final String family;
  // Search keys for the ~1900 candidates, folded once at construction instead
  // of twice per candidate per keystroke.
  final String lowerLabel;
  final String lowerFamily;
  final String preview;
  final String source;
  final bool google;
  final bool downloaded;
  final int priority;

  String get selectionFamily =>
      google ? encodeGoogleFontFamily(family) : family;

  TextStyle titleStyle(TextStyle base) {
    return _fontTitleStyle(
      family,
      base,
      googleFamily: google ? family : null,
      googleLoaded: downloaded,
    );
  }

  TextStyle previewStyle(TextStyle base) {
    if (google) {
      return downloaded ? GoogleFonts.getFont(family, textStyle: base) : base;
    }
    return base.copyWith(fontFamily: family);
  }

  int get sourceOrder => switch (source) {
    AppStringKeys.appearanceSystem => 0,
    'Google' => 1,
    _ => 4,
  };
}

class _MonoFontCandidate {
  const _MonoFontCandidate({
    required this.label,
    required this.family,
    required this.preview,
    required this.source,
    this.choice,
    this.google = false,
    this.downloaded = false,
    required this.priority,
  });

  final String label;
  final String family;
  final String preview;
  final String source;
  final AppMonospaceFontChoice? choice;
  final bool google;
  final bool downloaded;
  final int priority;

  String get selectionKey {
    final selectedChoice = choice;
    if (selectedChoice != null && !google) {
      return 'choice:${selectedChoice.name}';
    }
    if (google) return 'google:$family';
    return 'system:$family';
  }

  TextStyle previewStyle(TextStyle base, {required bool selected}) {
    if (google && (selected || downloaded)) {
      return GoogleFonts.getFont(family, textStyle: base);
    }
    if (google) return base;
    return base.copyWith(fontFamily: family);
  }

  TextStyle titleStyle(TextStyle base, {required bool selected}) {
    return _fontTitleStyle(
      family,
      base,
      googleFamily: google ? family : null,
      googleLoaded: selected || downloaded,
    );
  }
}

class MonospaceFontPickerView extends StatefulWidget {
  const MonospaceFontPickerView({super.key});

  @override
  State<MonospaceFontPickerView> createState() =>
      _MonospaceFontPickerViewState();
}

class _MonospaceFontPickerViewState extends State<MonospaceFontPickerView> {
  late final Future<List<_MonoFontCandidate>> _fonts = _loadFonts();
  String? _loadingGoogleFamily;
  String? _failedGoogleFamily;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final selectedKey = _selectedKey(theme);
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceMonospaceFont),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: FutureBuilder<List<_MonoFontCandidate>>(
              future: _fonts,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _fontList(context, snapshot.data!, selectedKey);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<_MonoFontCandidate>> _loadFonts() async {
    final systemFonts = await SystemFontCatalog.loadFonts();
    final cachedGoogleFamilies = await _cachedGoogleFontFamilies();
    final candidates = <_MonoFontCandidate>[
      ..._preferredPlatformMonospaceFonts(),
      ..._googleMonospaceFonts(cachedGoogleFamilies),
      for (final family in systemFonts.where(_isSystemMonospaceFontFamily))
        _MonoFontCandidate(
          label: family,
          family: family,
          preview: appMonospaceFontPreviewText,
          source: AppStringKeys.appearanceSystem,
          priority: _systemMonospacePriority(family),
        ),
    ];
    final byKey = <String, _MonoFontCandidate>{};
    for (final candidate in candidates) {
      byKey.putIfAbsent(candidate.selectionKey, () => candidate);
    }
    return byKey.values.toList()..sort((a, b) {
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      final sourceCompare = a.source.compareTo(b.source);
      if (sourceCompare != 0) return sourceCompare;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  }

  List<_MonoFontCandidate> _preferredPlatformMonospaceFonts() {
    final choices = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        AppMonospaceFontChoice.sfMono,
        AppMonospaceFontChoice.menlo,
        AppMonospaceFontChoice.courierNew,
      ],
      TargetPlatform.android => const [
        AppMonospaceFontChoice.system,
        AppMonospaceFontChoice.courierNew,
      ],
      _ => const [
        AppMonospaceFontChoice.system,
        AppMonospaceFontChoice.courierNew,
      ],
    };
    return [
      for (var i = 0; i < choices.length; i++)
        _MonoFontCandidate(
          label: choices[i].label,
          family: choices[i].fontFamily,
          preview: choices[i].previewText,
          source: AppStringKeys.appearanceSystem,
          choice: choices[i],
          priority: i,
        ),
    ];
  }

  List<_MonoFontCandidate> _googleMonospaceFonts(
    Set<String> cachedGoogleFamilies,
  ) {
    final families =
        GoogleFonts.asMap().keys
            .where(_googleMonospaceFamilies.contains)
            .toList()
          ..sort((a, b) {
            final priorityCompare = _googleMonospacePriority(
              a,
            ).compareTo(_googleMonospacePriority(b));
            if (priorityCompare != 0) return priorityCompare;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
    return [
      for (final family in families)
        _MonoFontCandidate(
          label: family,
          family: family,
          preview: appMonospaceFontPreviewText,
          source: 'Google',
          google: true,
          downloaded: cachedGoogleFamilies.contains(family),
          priority: 100 + _googleMonospacePriority(family),
        ),
    ];
  }

  int _systemMonospacePriority(String family) {
    final priorities = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        'SF Mono',
        'Menlo',
        'Courier',
        'Courier New',
      ],
      TargetPlatform.android => const [
        'monospace',
        'Roboto Mono',
        'Noto Sans Mono',
      ],
      _ => const ['monospace', 'Courier New'],
    };
    final exact = priorities.indexWhere((value) => value == family);
    if (exact >= 0) return 10 + exact;
    final prefix = priorities.indexWhere((value) => family.startsWith(value));
    if (prefix >= 0) return 10 + prefix;
    return 50;
  }

  int _googleMonospacePriority(String family) {
    const priorities = [
      'Roboto Mono',
      'Source Code Pro',
      'JetBrains Mono',
      'Fira Code',
      'IBM Plex Mono',
      'Noto Sans Mono',
      'Space Mono',
      'Inconsolata',
      'Ubuntu Mono',
      'Anonymous Pro',
      'DM Mono',
      'Red Hat Mono',
      'Geist Mono',
      'Courier Prime',
    ];
    final index = priorities.indexOf(family);
    return index >= 0 ? index : 60;
  }

  String _selectedKey(ThemeController theme) {
    final selected = theme.monospaceFontChoice;
    if (selected.isCustom) {
      final customFamily = theme.customMonospaceFontFamily.trim();
      final googleFamily = decodeGoogleFontFamily(customFamily);
      if (googleFamily != null) return 'google:$googleFamily';
      if (customFamily.isNotEmpty) return 'system:$customFamily';
      return 'choice:${AppMonospaceFontChoice.system.name}';
    }
    if (selected.googleFamily != null) return 'google:${selected.googleFamily}';
    return 'choice:${selected.name}';
  }

  Widget _fontList(
    BuildContext context,
    List<_MonoFontCandidate> fonts,
    String selectedKey,
  ) {
    final c = context.colors;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.section,
      ),
      itemCount: fonts.length,
      itemBuilder: (context, index) {
        final font = fonts[index];
        return _virtualRow(
          context,
          first: index == 0,
          last: index == fonts.length - 1,
          child: _fontRow(
            context,
            font,
            selected: selectedKey == font.selectionKey,
            loading: font.google && _loadingGoogleFamily == font.family,
            failed: font.google && _failedGoogleFamily == font.family,
            onTap: () {
              final theme = context.read<ThemeController>();
              final choice = font.choice;
              if (choice != null && !font.google) {
                theme.monospaceFontChoice = choice;
                _trackGoogleFontLoad(null);
                return;
              }
              theme.customMonospaceFontFamily = font.google
                  ? encodeGoogleFontFamily(font.family)
                  : font.family;
              theme.monospaceFontChoice = AppMonospaceFontChoice.custom;
              _trackGoogleFontLoad(font.google ? font.family : null);
            },
          ),
        );
      },
      separatorBuilder: (context, index) => ColoredBox(
        color: c.card,
        child: const InsetDivider(leadingInset: AppSpacing.xxl),
      ),
    );
  }

  Widget _virtualRow(
    BuildContext context, {
    required bool first,
    required bool last,
    required Widget child,
  }) {
    const radius = Radius.circular(AppRadius.card);
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: first ? radius : Radius.zero,
        bottom: last ? radius : Radius.zero,
      ),
      child: ColoredBox(color: context.colors.card, child: child),
    );
  }

  Widget _fontRow(
    BuildContext context,
    _MonoFontCandidate font, {
    required bool selected,
    required bool loading,
    required bool failed,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      font.label.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.titleStyle(
                        TextStyle(
                          fontSize: AppTextSize.bodyLarge,
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        selected: selected,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      font.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.previewStyle(
                        TextStyle(
                          fontSize: AppTextSize.footnote,
                          color: c.textSecondary,
                        ),
                        selected: selected,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                failed
                    ? AppStrings.t(AppStringKeys.appearanceDownloadFailed)
                    : font.google && font.downloaded
                    ? AppStrings.t(AppStringKeys.appearanceGoogleDownloaded)
                    : font.source.l10n(context),
                style: TextStyle(
                  fontSize: AppTextSize.footnote,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (loading) ...[
                SizedBox(
                  width: 48,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppTheme.brand,
                    backgroundColor: c.divider,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (!loading && failed) ...[
                Text(
                  AppStrings.t(AppStringKeys.appearanceDownloadFailed),
                  style: TextStyle(
                    fontSize: AppTextSize.footnote,
                    color: c.textTertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (selected)
                AppIcon(
                  HeroAppIcons.check,
                  size: AppIconSize.lg,
                  color: AppTheme.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _trackGoogleFontLoad(String? googleFamily) {
    if (googleFamily == null) {
      if (_loadingGoogleFamily != null || _failedGoogleFamily != null) {
        setState(() {
          _loadingGoogleFamily = null;
          _failedGoogleFamily = null;
        });
      }
      return;
    }
    setState(() {
      _loadingGoogleFamily = googleFamily;
      _failedGoogleFamily = null;
    });
    try {
      GoogleFonts.getFont(googleFamily, textStyle: const TextStyle());
    } catch (_) {
      if (!mounted || _loadingGoogleFamily != googleFamily) return;
      setState(() {
        _loadingGoogleFamily = null;
        _failedGoogleFamily = googleFamily;
      });
      return;
    }
    GoogleFonts.pendingFonts().then(
      (_) {
        if (!mounted || _loadingGoogleFamily != googleFamily) return;
        setState(() => _loadingGoogleFamily = null);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || _loadingGoogleFamily != googleFamily) return;
        setState(() {
          _loadingGoogleFamily = null;
          _failedGoogleFamily = googleFamily;
        });
      },
    );
  }
}
