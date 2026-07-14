//
//  main_tab_view.dart
//
//  Tab shell: 消息 / 联系人 / optional 动态, plus the left-sliding "我" profile drawer
//  overlaid above the tab bar. The bottom tab bar is either a custom flat bar
//  ("classic", default) or the system tab bar — chosen in 外观 settings. Port of
//  the Swift `MainTabView`.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../call/call_manager.dart';
import '../call/call_screen.dart';
import '../call/group_call_screen.dart';
import '../channels/topic_channels_view.dart';
import '../channels/topic_chat_view.dart';
import '../chat/chat_view.dart';
import '../chat/music_player_controller.dart';
import '../chat/video_player_view.dart';
import '../chats/chat_list_view.dart';
import '../components/app_icons.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/ui_components.dart';
import '../contacts/contacts_view.dart';
import '../l10n/app_localizations.dart';
import '../moments/moments_view.dart';
import '../profile/profile_view.dart';
import '../settings/developer_mode_controller.dart';
import '../settings/topic_group_display_mode.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../update/update_checker.dart';
import 'chat_deep_link_controller.dart';
import 'pip_bounds_debug_overlay.dart';
import 'video_split_controller.dart';

/// Global unread badge source.
class UnreadBadgeModel extends ChangeNotifier {
  int _chatCount = 0;
  int _messageCount = 0;
  bool _started = false;

  int countFor(UnreadBadgeMode mode) => switch (mode) {
    UnreadBadgeMode.messages => _messageCount,
    UnreadBadgeMode.chats => _chatCount,
  };

  void start() {
    if (_started) return;
    _started = true;
    TdClient.shared.subscribe().listen((update) {
      switch (update.type) {
        case 'updateUnreadChatCount':
          if (update.obj('chat_list')?.type != 'chatListMain') return;
          _chatCount = update.integer('unread_unmuted_count') ?? 0;
          notifyListeners();
        case 'updateUnreadMessageCount':
          if (update.obj('chat_list')?.type != 'chatListMain') return;
          _messageCount = update.integer('unread_unmuted_count') ?? 0;
          notifyListeners();
        case 'mithkaUnreadDelta':
          if (update.obj('chat_list')?.type != 'chatListMain') return;
          final chatDelta = update.integer('chat_delta') ?? 0;
          final messageDelta = update.integer('message_delta') ?? 0;
          if (chatDelta == 0 && messageDelta == 0) return;
          _chatCount = math.max(0, _chatCount + chatDelta);
          _messageCount = math.max(0, _messageCount + messageDelta);
          notifyListeners();
      }
    });
  }
}

class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class MainSplitRootView extends StatefulWidget {
  const MainSplitRootView({super.key});

  @override
  State<MainSplitRootView> createState() => _MainSplitRootViewState();
}

class _MainTabViewState extends _MainRootViewState<MainTabView> {
  @override
  bool get checkForUpdates => true;

  @override
  bool get showCallOverlay => true;
}

class _MainSplitRootViewState extends _MainRootViewState<MainSplitRootView> {}

abstract class _MainRootViewState<T extends StatefulWidget> extends State<T> {
  bool get checkForUpdates => false;
  bool get showCallOverlay => false;

  int _selection = 0;
  late final dc.TabBarVisibility _tabBar = dc.TabBarVisibility();
  late final UnreadBadgeModel _unread = UnreadBadgeModel()..start();
  late final CallManager _calls = CallManager()..start();
  late final ChatListController _chatListController = ChatListController();
  final VideoSplitController _videoSplit = VideoSplitController.instance;
  ChatListSelection? _selectedMessageChat;
  Widget? _selectedChannelDetail;
  Widget? _selectedContactDetail;
  Widget? _selectedMomentDetail;
  double _videoSplitFraction = 0.42;
  OverlayEntry? _pictureInPictureVideo;
  ChatDeepLinkController? _chatDeepLinks;

  @override
  void initState() {
    super.initState();
    // Android-only: check GitHub Releases for a newer same-ABI build (once).
    if (checkForUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) UpdateChecker.maybePrompt(context);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<ChatDeepLinkController>();
    if (identical(_chatDeepLinks, controller)) return;
    _chatDeepLinks?.removeListener(_handlePendingChatDeepLink);
    _chatDeepLinks = controller..addListener(_handlePendingChatDeepLink);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _handlePendingChatDeepLink();
    });
  }

  @override
  void dispose() {
    _chatDeepLinks?.removeListener(_handlePendingChatDeepLink);
    _pictureInPictureVideo?.remove();
    if (_pictureInPictureVideo != null) {
      VideoPiPController.instance.close();
    }
    _calls.dispose();
    _chatListController.dispose();
    super.dispose();
  }

  late final List<GlobalKey<NavigatorState>> _navKeys = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  static const _allTabs = [
    _MainTabItem(0, AppStringKeys.tabMessages, HeroAppIcons.solidMessage),
    _MainTabItem(1, AppStringKeys.tabChannels, HeroAppIcons.hashtag),
    _MainTabItem(2, AppStringKeys.tabContacts, HeroAppIcons.users),
    _MainTabItem(3, AppStringKeys.tabMoments, HeroAppIcons.circleNotch),
  ];

  List<_MainTabItem> _visibleTabs(ThemeController theme) => [
    _allTabs[0],
    if (theme.showChannelsTab) _allTabs[1],
    _allTabs[2],
    if (theme.showMomentsTab) _allTabs[3],
  ];

  Widget _root(int i) => switch (i) {
    0 => ChatListView(controller: _chatListController),
    1 => const TopicChannelsView(),
    2 => const ContactsView(),
    _ => const MomentsView(),
  };

  Future<bool> _onWillPop() async {
    if (_usesTabletSplit(context)) {
      switch (_selection) {
        case 0:
          if (_selectedMessageChat != null) {
            setState(() => _selectedMessageChat = null);
            return false;
          }
        case 1:
          if (_selectedChannelDetail != null) {
            setState(() => _selectedChannelDetail = null);
            return false;
          }
        case 2:
          if (_selectedContactDetail != null) {
            setState(() => _selectedContactDetail = null);
            return false;
          }
        case 3:
          if (_selectedMomentDetail != null) {
            setState(() => _selectedMomentDetail = null);
            return false;
          }
      }
    }
    final nav = _navKeys[_selection].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return false;
    }
    return true;
  }

  void _select(int i) {
    final theme = context.read<ThemeController>();
    final tabs = _visibleTabs(theme);
    if (i < 0 || i >= tabs.length) return;
    final tabIndex = tabs[i].index;
    final shouldToggleMessages = tabIndex == 0;
    if (tabIndex == _selection) {
      // Tapping the active tab pops to its root.
      _navKeys[tabIndex].currentState?.popUntil((r) => r.isFirst);
      if (_usesTabletSplit(context)) _clearTabletDetail(tabIndex);
      if (shouldToggleMessages) _toggleMessagesListTarget(theme);
      return;
    }
    setState(() => _selection = tabIndex);
    if (shouldToggleMessages) _toggleMessagesListTarget(theme);
  }

  void _toggleMessagesListTarget(ThemeController theme) {
    _chatListController.toggleFirstUnreadOrTop(
      mayHaveUnread: _unread.countFor(theme.unreadBadgeMode) > 0,
    );
  }

  void _handlePendingChatDeepLink() {
    if (!mounted) return;
    final request = _chatDeepLinks?.consumePending();
    if (request == null) return;
    _openMessageDeepLink(request);
  }

  void _openMessageDeepLink(ChatDeepLinkRequest request) {
    if (_usesTabletSplit(context)) {
      setState(() {
        _selection = 0;
        _selectedMessageChat = ChatListSelection(
          chatId: request.chatId,
          title: request.title,
          initialMessageId: request.messageId,
        );
      });
      return;
    }

    setState(() => _selection = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = _navKeys[0].currentState;
      if (navigator == null) {
        _chatDeepLinks?.openChat(
          chatId: request.chatId,
          title: request.title,
          messageId: request.messageId,
        );
        return;
      }
      navigator.popUntil((route) => route.isFirst);
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatView(
            chatId: request.chatId,
            title: request.title,
            initialMessageId: request.messageId,
          ),
        ),
      );
    });
  }

  void _clearTabletDetail(int tabIndex) {
    switch (tabIndex) {
      case 0:
        if (_selectedMessageChat != null) {
          setState(() => _selectedMessageChat = null);
        }
      case 1:
        if (_selectedChannelDetail != null) {
          setState(() => _selectedChannelDetail = null);
        }
      case 2:
        if (_selectedContactDetail != null) {
          setState(() => _selectedContactDetail = null);
        }
      case 3:
        if (_selectedMomentDetail != null) {
          setState(() => _selectedMomentDetail = null);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _tabBar),
        ChangeNotifierProvider.value(value: _unread),
        ChangeNotifierProvider.value(value: _calls),
        ChangeNotifierProvider.value(value: _videoSplit),
      ],
      // Material ancestor so the tab content (bare Containers) gets a proper
      // DefaultTextStyle instead of the debug red/yellow-underline fallback.
      child: Material(
        type: MaterialType.transparency,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) await _onWillPop();
          },
          child: _videoSplitHost(_rootStack()),
        ),
      ),
    );
  }

  Widget _rootStack() {
    return Stack(
      children: [
        _classicTabs(),
        _drawerOverlay(),
        // Full-screen call HUD over everything when a call is active.
        if (showCallOverlay)
          Consumer<CallManager>(
            builder: (context, calls, _) {
              if (calls.groups.session != null) {
                if (calls.groups.isMinimized) {
                  return Positioned(
                    top: MediaQuery.paddingOf(context).top + 12,
                    right: 16,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: calls.groups.restore,
                      child: Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFF253442),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x55000000),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const AppIcon(
                          HeroAppIcons.users,
                          size: 26,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  );
                }
                return Positioned.fill(
                  child: GroupCallScreen(controller: calls.groups),
                );
              }
              if (calls.call != null) {
                return Positioned.fill(child: CallScreen(manager: calls));
              }
              return const SizedBox.shrink();
            },
          ),
      ],
    );
  }

  Widget _videoSplitHost(Widget root) {
    return AnimatedBuilder(
      animation: _videoSplit,
      builder: (context, _) {
        final session = _videoSplit.session;
        if (session == null) return root;
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= 760 &&
                constraints.maxWidth > constraints.maxHeight;
            if (wide) {
              final videoWidth = _clampSplitExtent(
                totalExtent: constraints.maxWidth,
                fraction: _videoSplitFraction,
                preferredMin: 280,
                reservedExtent: 320,
                fallbackMin: 180,
              );
              return Row(
                children: [
                  Expanded(child: root),
                  _videoSplitDivider(
                    vertical: true,
                    onDrag: (delta) => setState(() {
                      _videoSplitFraction =
                          (_videoSplitFraction - delta / constraints.maxWidth)
                              .clamp(0.25, 0.72);
                    }),
                  ),
                  SizedBox(width: videoWidth, child: _videoSibling(session)),
                ],
              );
            }

            final videoHeight = _clampSplitExtent(
              totalExtent: constraints.maxHeight,
              fraction: _videoSplitFraction,
              preferredMin: 220,
              reservedExtent: 260,
              fallbackMin: 96,
            );
            final topInset = MediaQuery.paddingOf(context).top;
            return Column(
              children: [
                SizedBox(
                  height: videoHeight + topInset,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Column(
                      children: [
                        SizedBox(height: topInset),
                        Expanded(child: _videoSibling(session)),
                      ],
                    ),
                  ),
                ),
                _videoSplitDivider(
                  vertical: false,
                  onDrag: (delta) => setState(() {
                    _videoSplitFraction =
                        (_videoSplitFraction + delta / constraints.maxHeight)
                            .clamp(0.25, 0.72);
                  }),
                ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: root,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  double _clampSplitExtent({
    required double totalExtent,
    required double fraction,
    required double preferredMin,
    required double reservedExtent,
    required double fallbackMin,
  }) {
    if (!totalExtent.isFinite || totalExtent <= 0) return fallbackMin;
    final upper = math.max(fallbackMin, totalExtent - reservedExtent);
    final lower = math.min(preferredMin, upper);
    return (totalExtent * fraction).clamp(lower, upper).toDouble();
  }

  Widget _videoSibling(VideoSplitSession session) {
    return ColoredBox(
      color: Colors.black,
      child: VideoPlayerView(
        key: ValueKey(session.video.id),
        video: session.video,
        thumb: session.thumb,
        width: session.width,
        height: session.height,
        presentation: VideoPlayerPresentation.embedded,
        onClose: _videoSplit.close,
        sourceChatId: session.chatId,
        messageId: session.messageId,
        currentMode: VideoDisplayMode.split,
        onSwitchMode: (mode) => _switchSiblingVideoMode(session, mode),
      ),
    );
  }

  Widget _videoSplitDivider({
    required bool vertical,
    required ValueChanged<double> onDrag,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) =>
          onDrag(vertical ? details.delta.dx : details.delta.dy),
      child: Container(
        width: vertical ? 14 : double.infinity,
        height: vertical ? double.infinity : 14,
        color: const Color(0xFF111113),
        alignment: Alignment.center,
        child: Container(
          width: vertical ? 3 : 52,
          height: vertical ? 52 : 3,
          decoration: BoxDecoration(
            color: const Color(0xFF3A3A3C),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  void _switchSiblingVideoMode(
    VideoSplitSession session,
    VideoDisplayMode mode,
  ) {
    switch (mode) {
      case VideoDisplayMode.split:
        break;
      case VideoDisplayMode.pictureInPicture:
        _videoSplit.close();
        _showSplitVideoPictureInPicture(session);
      case VideoDisplayMode.fullscreen:
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => VideoPlayerView(
              video: session.video,
              thumb: session.thumb,
              width: session.width,
              height: session.height,
              sourceChatId: session.chatId,
              messageId: session.messageId,
            ),
          ),
        );
    }
  }

  void _showSplitVideoPictureInPicture(VideoSplitSession session) {
    final pip = VideoPiPController.instance;
    if (_pictureInPictureVideo != null) {
      pip.play(session);
      return;
    }
    if (pip.isOpen) {
      pip.play(session);
      return;
    }
    pip.play(session);
    final overlay = Overlay.of(context, rootOverlay: true);
    final screen = MediaQuery.sizeOf(context);
    const margin = 16.0;
    var aspect = _videoSessionAspect(session);
    var boxWidth = (screen.width * 0.46).clamp(220.0, 360.0);
    var boxHeight = (boxWidth / aspect).clamp(130.0, 260.0);
    boxWidth = boxHeight * aspect;
    var displayedVideoId = session.video.id;
    var offset = Offset(
      screen.width - boxWidth - margin,
      screen.height - boxHeight - MediaQuery.paddingOf(context).bottom - 110,
    );

    late final OverlayEntry entry;
    void close() {
      entry.remove();
      if (_pictureInPictureVideo == entry) {
        _pictureInPictureVideo = null;
      }
      if (pip.session?.video.id == displayedVideoId) {
        pip.close();
      }
    }

    void switchMode(VideoDisplayMode mode, VideoSplitSession modeSession) {
      if (mode == VideoDisplayMode.pictureInPicture) return;
      close();
      switch (mode) {
        case VideoDisplayMode.pictureInPicture:
          break;
        case VideoDisplayMode.split:
          _videoSplit.play(modeSession);
        case VideoDisplayMode.fullscreen:
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (routeContext) => VideoPlayerView(
                video: modeSession.video,
                thumb: modeSession.thumb,
                width: modeSession.width,
                height: modeSession.height,
                sourceChatId: modeSession.chatId,
                messageId: modeSession.messageId,
                onSwitchMode: (nextMode) {
                  switch (nextMode) {
                    case VideoDisplayMode.fullscreen:
                      break;
                    case VideoDisplayMode.pictureInPicture:
                      Navigator.of(routeContext).maybePop();
                      _showSplitVideoPictureInPicture(modeSession);
                    case VideoDisplayMode.split:
                      Navigator.of(routeContext).maybePop();
                      _videoSplit.play(modeSession);
                  }
                },
              ),
            ),
          );
      }
    }

    entry = OverlayEntry(
      builder: (overlayContext) => StatefulBuilder(
        builder: (context, setOverlayState) {
          final media = MediaQuery.sizeOf(context);
          final padding = MediaQuery.paddingOf(context);
          void clampFrame() {
            final maxWidth = math.max(80.0, media.width - margin * 2);
            final maxHeight = math.max(
              80.0,
              media.height - padding.top - padding.bottom - margin * 2,
            );
            if (boxWidth > maxWidth) {
              boxWidth = maxWidth;
              boxHeight = boxWidth / aspect;
            }
            if (boxHeight > maxHeight) {
              boxHeight = maxHeight;
              boxWidth = boxHeight * aspect;
            }
            final minX = math.min(margin, media.width - boxWidth);
            final maxX = math.max(minX, media.width - boxWidth - margin);
            final minY = math.min(
              padding.top + margin,
              media.height - boxHeight,
            );
            final maxY = math.max(
              minY,
              media.height - boxHeight - padding.bottom - margin,
            );
            offset = Offset(
              offset.dx.clamp(minX, maxX),
              offset.dy.clamp(minY, maxY),
            );
          }

          void syncSession(VideoSplitSession nextSession) {
            if (nextSession.video.id == displayedVideoId) return;
            displayedVideoId = nextSession.video.id;
            aspect = _videoSessionAspect(nextSession);
            boxHeight = (boxWidth / aspect).clamp(110.0, media.height * 0.72);
            boxWidth = boxHeight * aspect;
            clampFrame();
          }

          void move(DragUpdateDetails details) {
            setOverlayState(() {
              offset += details.delta;
              clampFrame();
            });
          }

          void resizeFromCorner(
            DragUpdateDetails details, {
            required int horizontalSign,
            required int verticalSign,
          }) {
            setOverlayState(() {
              final oldWidth = boxWidth;
              final oldHeight = boxHeight;
              final minW = math.min(180.0, media.width - margin * 2);
              final maxW = math.max(minW, media.width - margin * 2);
              final widthFromX = boxWidth + details.delta.dx * horizontalSign;
              final widthFromY =
                  boxWidth + details.delta.dy * verticalSign * aspect;
              final nextWidth =
                  (widthFromX - boxWidth).abs() > (widthFromY - boxWidth).abs()
                  ? widthFromX
                  : widthFromY;
              boxWidth = nextWidth.clamp(minW, maxW);
              boxHeight = boxWidth / aspect;
              if (boxHeight > media.height * 0.72) {
                boxHeight = media.height * 0.72;
                boxWidth = boxHeight * aspect;
              }
              if (boxHeight < 110) {
                boxHeight = 110;
                boxWidth = boxHeight * aspect;
              }
              if (horizontalSign < 0) {
                offset = offset.translate(oldWidth - boxWidth, 0);
              }
              if (verticalSign < 0) {
                offset = offset.translate(0, oldHeight - boxHeight);
              }
              clampFrame();
            });
          }

          return AnimatedBuilder(
            animation: pip,
            builder: (context, _) {
              final currentSession = pip.session;
              if (currentSession == null) return const SizedBox.shrink();
              syncSession(currentSession);
              clampFrame();
              final showDebugBounds = context
                  .watch<DeveloperModeController>()
                  .showPiPBounds;
              return Positioned(
                left: offset.dx,
                top: offset.dy,
                width: boxWidth,
                height: boxHeight,
                child: Material(
                  type: MaterialType.transparency,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: GestureDetector(
                          onPanUpdate: move,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: VideoPlayerView(
                              key: ValueKey(currentSession.video.id),
                              video: currentSession.video,
                              thumb: currentSession.thumb,
                              width: currentSession.width,
                              height: currentSession.height,
                              presentation:
                                  VideoPlayerPresentation.pictureInPicture,
                              compactControls: true,
                              onClose: close,
                              sourceChatId: currentSession.chatId,
                              messageId: currentSession.messageId,
                              currentMode: VideoDisplayMode.pictureInPicture,
                              onSwitchMode: (mode) =>
                                  switchMode(mode, currentSession),
                            ),
                          ),
                        ),
                      ),
                      _SplitPiPCornerHandle(
                        alignment: Alignment.topLeft,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: -1,
                          verticalSign: -1,
                        ),
                      ),
                      _SplitPiPCornerHandle(
                        alignment: Alignment.topRight,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: 1,
                          verticalSign: -1,
                        ),
                      ),
                      _SplitPiPCornerHandle(
                        alignment: Alignment.bottomLeft,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: -1,
                          verticalSign: 1,
                        ),
                      ),
                      _SplitPiPCornerHandle(
                        alignment: Alignment.bottomRight,
                        onDrag: (details) => resizeFromCorner(
                          details,
                          horizontalSign: 1,
                          verticalSign: 1,
                        ),
                      ),
                      if (showDebugBounds)
                        PiPBoundsDebugOverlay(
                          offset: offset,
                          size: Size(boxWidth, boxHeight),
                          viewport: media,
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
    _pictureInPictureVideo = entry;
    overlay.insert(entry);
  }

  // MARK: - Per-tab navigators

  Widget _tabNavigator(int i) {
    return _TabNavigator(
      navigatorKey: _navKeys[i],
      observer: dc.TabDepthObserver(i, _tabBar),
      root: _root(i),
    );
  }

  int _visibleSelection(List<_MainTabItem> tabs) {
    final index = tabs.indexWhere((tab) => tab.index == _selection);
    return index < 0 ? tabs.length - 1 : index;
  }

  Widget _stack(List<_MainTabItem> tabs) => _LazyTabStack(
    selection: _visibleSelection(tabs),
    items: tabs,
    builder: (tab) => _tabNavigator(tab.index),
  );

  // MARK: - Classic (flat) tab bar

  Widget _classicTabs() {
    final theme = context.watch<ThemeController>();
    final tabs = _visibleTabs(theme);
    if (!tabs.any((tab) => tab.index == _selection)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selection = tabs.last.index);
      });
    }
    final selection = _visibleSelection(tabs);
    final activeTabIndex = tabs[selection].index;
    if (_usesTabletSplit(context)) {
      return _tabletSplitTabs(tabs, selection, activeTabIndex);
    }
    return AnimatedBuilder(
      animation: _tabBar,
      builder: (context, _) {
        final showTabBar =
            _tabBar.depth(activeTabIndex) == 0 && !_tabBar.isChatSuppressed;
        return Column(
          children: [
            Expanded(
              child: _musicAwareContent(
                _stack(tabs),
                reserveForShellPlayer: !_tabBar.isChatSuppressed,
              ),
            ),
            if (!_tabBar.isChatSuppressed)
              _fixedMusicPlayer(safeBottom: !showTabBar),
            if (showTabBar)
              AnimatedBuilder(
                animation: _unread,
                builder: (context, _) => _ClassicTabBar(
                  selection: selection,
                  onSelect: _select,
                  items: tabs,
                  onClearUnread: _chatListController.markAllRead,
                  unread: _unread.countFor(theme.unreadBadgeMode),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _fixedMusicPlayer({required bool safeBottom}) {
    return AnimatedBuilder(
      animation: MusicPlayerController.shared,
      builder: (context, _) {
        final player = MusicPlayerController.shared;
        return AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: player.isVisible && !player.collapsed
              ? GlobalMusicPlayerBar(
                  bottomPadding: safeBottom
                      ? MediaQuery.paddingOf(context).bottom.clamp(0, 12)
                      : 0,
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _musicAwareContent(Widget child, {bool reserveForShellPlayer = true}) {
    return AnimatedBuilder(
      animation: MusicPlayerController.shared,
      child: child,
      builder: (context, child) {
        final player = MusicPlayerController.shared;
        if (!reserveForShellPlayer || !player.isVisible || player.collapsed) {
          return child!;
        }
        return MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: child!,
        );
      },
    );
  }

  Widget _tabletSplitTabs(
    List<_MainTabItem> tabs,
    int selection,
    int activeTabIndex,
  ) {
    final theme = context.watch<ThemeController>();
    final size = MediaQuery.of(context).size;
    final sidebarWidth = (size.width * 0.32).clamp(320.0, 420.0).toDouble();
    return AnimatedBuilder(
      animation: _tabBar,
      builder: (context, _) => Column(
        children: [
          Expanded(
            child: Row(
              children: [
                SizedBox(
                  width: sidebarWidth,
                  child: Column(
                    children: [
                      Expanded(
                        child: _LazyTabStack(
                          selection: selection,
                          items: tabs,
                          builder: (tab) => _tabletSidebarRoot(tab.index),
                        ),
                      ),
                      AnimatedBuilder(
                        animation: _unread,
                        builder: (context, _) => _ClassicTabBar(
                          selection: selection,
                          onSelect: _select,
                          items: tabs,
                          onClearUnread: _chatListController.markAllRead,
                          unread: _unread.countFor(theme.unreadBadgeMode),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _musicAwareContent(
                    _tabletDetailPane(activeTabIndex),
                    reserveForShellPlayer: !_tabBar.isChatSuppressed,
                  ),
                ),
              ],
            ),
          ),
          if (!_tabBar.isChatSuppressed) _fixedMusicPlayer(safeBottom: true),
        ],
      ),
    );
  }

  Widget _tabletSidebarRoot(int tabIndex) => switch (tabIndex) {
    0 => ChatListView(
      controller: _chatListController,
      selectedChatId: _selectedMessageChat?.chatId,
      onChatSelected: (chat) {
        setState(() => _selectedMessageChat = chat);
      },
    ),
    1 => TopicChannelsView(
      onOpenDetail: (detail) {
        setState(() => _selectedChannelDetail = detail);
      },
    ),
    2 => ContactsView(
      onOpenDetail: (detail) {
        setState(() => _selectedContactDetail = detail);
      },
    ),
    _ => MomentsView(
      onOpenDetail: (detail) {
        setState(() => _selectedMomentDetail = detail);
      },
    ),
  };

  Widget _tabletDetailPane(int activeTabIndex) => switch (activeTabIndex) {
    0 => _messageDetailPane(),
    1 =>
      _selectedChannelDetail ??
          const _SplitEmptyPane(
            icon: HeroAppIcons.hashtag,
            title: AppStringKeys.tabSelectChannelContent,
          ),
    2 =>
      _selectedContactDetail ??
          const _SplitEmptyPane(
            icon: HeroAppIcons.users,
            title: AppStringKeys.tabSelectContact,
          ),
    _ =>
      _selectedMomentDetail ??
          ChannelMomentsView(
            isRootTab: true,
            title: AppStringKeys.tabFriendMoments,
            onOpenDetail: (detail) {
              setState(() => _selectedMomentDetail = detail);
            },
          ),
  };

  Widget _messageDetailPane() {
    final selected = _selectedMessageChat;
    if (selected == null) return const _MessageEmptyPane();
    final chat = selected.chat;
    const headerHeight =
        AppMetric.headerAvatarSize + (AppSpacing.md + AppSpacing.xxs) * 2;
    final headerColor = context.colors.chatBackground;
    return KeyedSubtree(
      key: ValueKey(
        'message-detail-${selected.chatId}-${selected.isForum}-${selected.initialMessageId ?? 0}',
      ),
      child:
          selected.isForum && chat != null && selected.initialMessageId == null
          ? _ForumSplitDetailPane(
              chat: chat,
              headerHeight: headerHeight,
              headerColor: headerColor,
            )
          : ChatView(
              chatId: selected.chatId,
              title: selected.title,
              seedMessage: chat?.lastChatMessage,
              initialMessageId: selected.initialMessageId,
              showBackButton: false,
              headerHeight: headerHeight,
              headerColor: headerColor,
              showHeaderDivider: false,
              onBack: () => setState(() => _selectedMessageChat = null),
            ),
    );
  }

  bool _usesTabletSplit(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > size.height && math.min(size.width, size.height) >= 600;
  }

  // MARK: - Drawer overlay (the "我" profile drawer)

  Widget _drawerOverlay() {
    return Consumer<dc.DrawerController>(
      builder: (context, drawer, _) {
        final width = math.min(MediaQuery.of(context).size.width * 0.88, 420.0);
        return IgnorePointer(
          ignoring: !drawer.isOpen,
          child: Stack(
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                opacity: drawer.isOpen ? 1 : 0,
                child: GestureDetector(
                  onTap: drawer.close,
                  child: Container(color: Colors.black.withValues(alpha: 0.35)),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: drawer.isOpen ? 0 : -width,
                top: 0,
                bottom: 0,
                width: width,
                child: Material(
                  color: context.colors.groupedBackground,
                  child: const ProfileView(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ForumSplitDetailPane extends StatefulWidget {
  const _ForumSplitDetailPane({
    required this.chat,
    required this.headerHeight,
    required this.headerColor,
  });

  final ChatSummary chat;
  final double headerHeight;
  final Color headerColor;

  @override
  State<_ForumSplitDetailPane> createState() => _ForumSplitDetailPaneState();
}

class _ForumSplitDetailPaneState extends State<_ForumSplitDetailPane> {
  var _index = 0;
  int? _topicThreadId;

  Future<void> _showChatMode() async {
    await TopicGroupDisplayPreference.set(TopicGroupDisplayMode.chat);
    if (!mounted) return;
    setState(() => _index = 0);
  }

  Future<void> _showChannelMode([int? threadId]) async {
    await TopicGroupDisplayPreference.set(TopicGroupDisplayMode.channel);
    if (!mounted) return;
    setState(() {
      _index = 1;
      _topicThreadId = threadId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _index == 0
        ? ChatView(
            chatId: widget.chat.id,
            title: widget.chat.title,
            seedMessage: widget.chat.lastChatMessage,
            showBackButton: false,
            headerHeight: widget.headerHeight,
            headerColor: widget.headerColor,
            headerBottom: _tabSwitcher(c),
            onOpenTopicMode: (threadId) =>
                unawaited(_showChannelMode(threadId)),
          )
        : TopicChatView(
            key: ValueKey('${widget.chat.id}:${_topicThreadId ?? 0}'),
            chat: widget.chat,
            initialThreadId: _topicThreadId,
            showBackButton: false,
            headerHeight: widget.headerHeight,
            headerColor: widget.headerColor,
            onOpenChatView: () => unawaited(_showChatMode()),
          );
  }

  Widget _tabSwitcher(AppColors c) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          height: 32,
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ForumDetailTabButton(
                selected: _index == 0,
                icon: HeroAppIcons.solidMessage,
                label: AppStringKeys.tabMessages,
                onTap: () => unawaited(_showChatMode()),
              ),
              _ForumDetailTabButton(
                selected: _index == 1,
                icon: HeroAppIcons.hashtag,
                label: AppStringKeys.topicChatAllTopics,
                onTap: () => unawaited(_showChannelMode()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForumDetailTabButton extends StatelessWidget {
  const _ForumDetailTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.brand : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 17,
              color: selected ? Colors.white : c.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label.l10n(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageEmptyPane extends StatelessWidget {
  const _MessageEmptyPane();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Center(
        child: Opacity(
          opacity: 0.08,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/penguin.png', width: 92, height: 92),
              const SizedBox(width: 18),
              Text(
                'Mithka',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitEmptyPane extends StatelessWidget {
  const _SplitEmptyPane({required this.icon, required this.title});

  final AppIconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Center(
        child: Opacity(
          opacity: 0.18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 56, color: c.textTertiary),
              const SizedBox(height: 14),
              Text(
                title.l10n(context),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainTabItem {
  const _MainTabItem(this.index, this.label, this.icon);

  final int index;
  final String label;
  final AppIconData icon;
}

class _LazyTabStack extends StatefulWidget {
  const _LazyTabStack({
    required this.selection,
    required this.items,
    required this.builder,
  });

  final int selection;
  final List<_MainTabItem> items;
  final Widget Function(_MainTabItem tab) builder;

  @override
  State<_LazyTabStack> createState() => _LazyTabStackState();
}

class _LazyTabStackState extends State<_LazyTabStack> {
  final Set<int> _builtTabIndexes = {};

  @override
  void initState() {
    super.initState();
    _rememberSelection();
  }

  @override
  void didUpdateWidget(covariant _LazyTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _builtTabIndexes.removeWhere(
      (index) => !widget.items.any((tab) => tab.index == index),
    );
    _rememberSelection();
  }

  void _rememberSelection() {
    if (widget.items.isEmpty) return;
    final selectedIndex = widget.selection
        .clamp(0, widget.items.length - 1)
        .toInt();
    final selected = widget.items[selectedIndex];
    _builtTabIndexes.add(selected.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.selection,
      children: [
        for (final tab in widget.items)
          _builtTabIndexes.contains(tab.index)
              ? widget.builder(tab)
              : const SizedBox.expand(),
      ],
    );
  }
}

/// Hosts one tab's navigation stack so pushes stay within the tab.
class _TabNavigator extends StatelessWidget {
  const _TabNavigator({
    required this.navigatorKey,
    required this.observer,
    required this.root,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final NavigatorObserver observer;
  final Widget root;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      observers: [observer],
      onGenerateRoute: (settings) =>
          MaterialPageRoute(builder: (_) => root, settings: settings),
    );
  }
}

/// Flat bottom tab bar.
class _ClassicTabBar extends StatelessWidget {
  const _ClassicTabBar({
    required this.selection,
    required this.onSelect,
    required this.onClearUnread,
    required this.items,
    required this.unread,
  });
  final int selection;
  final ValueChanged<int> onSelect;
  final VoidCallback onClearUnread;
  final List<_MainTabItem> items;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(i),
                    child: Center(
                      child: SizedBox(
                        width: 64,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 36,
                              height: 28,
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  AppIcon(
                                    items[i].icon,
                                    size: 24,
                                    color: selection == i
                                        ? AppTheme.brand
                                        : c.textTertiary,
                                  ),
                                  if (i == 0 && unread > 0)
                                    Positioned(
                                      right: -14,
                                      top: -2,
                                      child: UnreadBadge(
                                        count: unread,
                                        onClear: onClearUnread,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              items[i].label.l10n(context),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: selection == i
                                    ? AppTheme.brand
                                    : c.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
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

double _videoSessionAspect(VideoSplitSession session) {
  return (session.width != null &&
          session.height != null &&
          session.width! > 0 &&
          session.height! > 0)
      ? session.width! / session.height!
      : 16 / 9;
}

class _SplitPiPCornerHandle extends StatelessWidget {
  const _SplitPiPCornerHandle({required this.alignment, required this.onDrag});

  final Alignment alignment;
  final GestureDragUpdateCallback onDrag;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: alignment.x < 0 ? -8 : null,
      right: alignment.x > 0 ? -8 : null,
      top: alignment.y < 0 ? -8 : null,
      bottom: alignment.y > 0 ? -8 : null,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanUpdate: onDrag,
        child: const SizedBox(width: 44, height: 44),
      ),
    );
  }
}
