part of 'appearance_view.dart';

class ChatViewAppearanceSettingsView extends StatelessWidget {
  const ChatViewAppearanceSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final desktop = isDesktopTargetPlatform(Theme.of(context).platform);
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
          AppStrings.t(AppStringKeys.channelBottomBar),
          AppStrings.t(theme.channelBottomBarMode.label),
          () => Navigator.of(context).push(
            AppPageRoute<void>(
              pageBuilder: (_, _, _) => const ChannelBottomBarSettingsView(),
            ),
          ),
          icon: HeroAppIcons.bell.data,
        ),
        appearance._toggleRow(
          context,
          HeroAppIcons.eye.data,
          AppStrings.t(AppStringKeys.channelPostStats),
          theme.showChannelPostStats,
          (value) => theme.showChannelPostStats = value,
        ),
        if (!desktop)
          KeyedSubtree(
            key: const ValueKey('mobile-message-action-menu-style-row'),
            child: appearance._navigationRow(
              context,
              AppStrings.t(AppStringKeys.appearanceMessageActionMenu),
              AppStrings.t(theme.mobileMessageActionMenuStyle.label),
              () => Navigator.of(context).push(
                AppPageRoute<void>(
                  pageBuilder: (_, _, _) =>
                      const MobileMessageActionMenuSettingsView(),
                ),
              ),
              icon: HeroAppIcons.listCheck.data,
            ),
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
    final platform = Theme.of(context).platform;
    final desktop = isDesktopTargetPlatform(platform);
    final archiveMode = theme.archivedChatsDisplayMode.effectiveForPlatform(
      platform: platform,
    );
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
            if (!desktop)
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
              AppStrings.t(archiveMode.label),
              () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ArchivedChatsSettingsView(),
                ),
              ),
              icon: HeroAppIcons.inbox.data,
            ),
            if (!desktop)
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
    return SettingsPageScaffold(
      title: title,
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          if (preview != null) ...[
            preview!,
            const SizedBox(height: AppSpacing.xl),
          ],
          controls,
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

enum NameColorSettingsSurface { chat, chatList }

class NameColorSettingsView extends StatelessWidget {
  const NameColorSettingsView({required this.surface, super.key});

  final NameColorSettingsSurface surface;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final isChatList = surface == NameColorSettingsSurface.chatList;
    final audience = isChatList
        ? theme.chatListNameColorAudience
        : theme.chatNameColorAudience;
    final status = isChatList
        ? theme.chatListStatusEmojiMode
        : theme.chatStatusEmojiMode;

    return SettingsPageScaffold(
      title: AppStrings.t(
        isChatList
            ? AppStringKeys.appearanceChatListNameColorsTitle
            : AppStringKeys.appearanceChatNameColorsTitle,
      ),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
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
    );
  }
}

class ChatFolderSettingsView extends StatelessWidget {
  const ChatFolderSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceChatFolders),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
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
          if (theme.chatFolderDisplayMode != ChatFolderDisplayMode.hidden)
            const AppearanceView()._card(context, [
              const AppearanceView()._toggleRow(
                context,
                HeroAppIcons.eyeSlash.data,
                AppStrings.t(AppStringKeys.appearanceHideAllChatsFolder),
                theme.hideAllChatsFolder,
                (value) => theme.hideAllChatsFolder = value,
              ),
            ]),
          const AppearanceView()._label(
            context,
            AppStrings.t(AppStringKeys.appearanceUnreadBadge),
          ),
          const AppearanceView()._card(context, [
            const AppearanceView()._toggleRow(
              context,
              HeroAppIcons.solidBell.data,
              AppStrings.t(AppStringKeys.appearanceShowFolderBadges),
              theme.showFolderUnreadBadges,
              (value) => theme.showFolderUnreadBadges = value,
            ),
            const AppearanceView()._toggleRow(
              context,
              HeroAppIcons.solidBell.data,
              AppStrings.t(AppStringKeys.appearanceCapUnreadCountAt99),
              theme.capUnreadBadgeAt99,
              (value) => theme.capUnreadBadgeAt99 = value,
            ),
          ]),
        ],
      ),
    );
  }
}

class ChatListGestureSettingsView extends StatelessWidget {
  const ChatListGestureSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    const appearance = AppearanceView();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.gesturesChatListSwipe),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          appearance._card(context, [
            for (final mode in ChatListSwipeMode.values)
              _modeRow(context, theme, mode),
          ]),
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
    final theme = context.watch<ThemeController>();
    final platform = Theme.of(context).platform;
    final desktop = isDesktopTargetPlatform(platform);
    final selectedMode = theme.archivedChatsDisplayMode.effectiveForPlatform(
      platform: platform,
    );
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceArchivedChats),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          const AppearanceView()._card(context, [
            for (final mode in ArchivedChatsDisplayMode.values)
              if (!desktop || mode != ArchivedChatsDisplayMode.pullDown)
                const AppearanceView()._choiceRow(
                  context,
                  mode.icon,
                  mode.label,
                  selectedMode == mode,
                  () => theme.archivedChatsDisplayMode = mode,
                ),
          ]),
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

  Widget _interfaceSizeCard(BuildContext context, ThemeController theme) {
    return SettingsPanel(
      clipBehavior: Clip.antiAlias,
      child: InterfaceScaleControl(
        value: theme.interfaceScale,
        renderedScale: theme.renderedInterfaceScale,
        onChanged: (value) => theme.interfaceScale = value,
      ),
    );
  }

  Widget _interfaceSizePreview(BuildContext context, ThemeController theme) {
    final c = context.colors;
    return _previewCard(
      context,
      title: AppStrings.t(AppStringKeys.appearanceInterfaceSize),
      value: theme.interfaceScale,
      valueLabel: InterfaceScaleSteps.percent(theme.interfaceScale),
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
                    Expanded(
                      child: Text(
                        AppStrings.t(AppStringKeys.appearanceTitle),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTextSize.bodyLarge,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
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
    String? valueLabel,
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
                valueLabel ?? '${(value * 100).round()}%',
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

  Widget _label(BuildContext _, String t) => SettingsSectionHeader.text(t);

  Widget _card(BuildContext _, List<Widget> rows) {
    return SettingsCard.rows(rows: rows);
  }

  Widget _choiceRow(
    BuildContext _,
    IconData icon,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return SettingsRow(
      title: label,
      leading: SettingsLeadingIcon(icon: AppIconData(icon)),
      onTap: onTap,
      showChevron: false,
      trailing: selected
          ? AppIcon(
              HeroAppIcons.check,
              size: AppIconSize.lg,
              color: AppTheme.brand,
            )
          : null,
    );
  }

  Widget _toggleRow(
    BuildContext context,
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool>? onChanged,
  ) {
    final enabled = onChanged != null;
    return SettingsSwitchRow(
      title: label,
      value: value,
      leading: SettingsLeadingIcon(
        icon: AppIconData(icon),
        color: enabled ? AppTheme.brand : context.colors.textTertiary,
      ),
      enabled: enabled,
      onChanged: onChanged ?? (_) {},
    );
  }

  Widget _navigationRow(
    BuildContext _,
    String label,
    String? value,
    VoidCallback onTap, {
    IconData? icon,
    Widget? preview,
    double? minimumTapExtent,
  }) {
    Widget? leading;
    if (icon != null) {
      leading = SettingsLeadingIcon(icon: AppIconData(icon));
    } else if (preview != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: preview,
      );
    }
    final row = SettingsRow(
      title: label,
      value: value ?? '',
      leading: leading,
      onTap: minimumTapExtent == null ? onTap : null,
    );
    if (minimumTapExtent == null) return row;
    return AppInteractiveSurface(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minimumTapExtent),
        child: IgnorePointer(child: row),
      ),
    );
  }
}
