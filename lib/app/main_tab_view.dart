//
//  main_tab_view.dart
//
//  Three-tab shell: 消息 / 联系人 / 动态, plus the left-sliding "我" profile drawer
//  overlaid above the tab bar. The bottom tab bar is either a custom flat bar
//  ("classic", default) or the system tab bar — chosen in 通用 settings. Port of
//  the Swift `MainTabView`.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../call/call_manager.dart';
import '../call/call_screen.dart';
import '../chats/chat_list_view.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/sf_symbols.dart';
import '../contacts/contacts_view.dart';
import '../moments/moments_view.dart';
import '../profile/profile_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../update/update_checker.dart';

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
      }
    });
  }
}

class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  int _selection = 0;
  late final dc.TabBarVisibility _tabBar = dc.TabBarVisibility();
  late final UnreadBadgeModel _unread = UnreadBadgeModel()..start();
  late final CallManager _calls = CallManager()..start();
  late final ChatListController _chatListController = ChatListController();

  @override
  void initState() {
    super.initState();
    // Android-only: check GitHub Releases for a newer same-ABI build (once).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateChecker.maybePrompt(context);
    });
  }

  @override
  void dispose() {
    _calls.dispose();
    _chatListController.dispose();
    super.dispose();
  }

  late final List<GlobalKey<NavigatorState>> _navKeys = List.generate(
    3,
    (_) => GlobalKey<NavigatorState>(),
  );

  static const _tabs = [
    ('消息', 'message.fill'),
    ('联系人', 'person.2.fill'),
    ('动态', 'circle.dashed'),
  ];

  Widget _root(int i) => switch (i) {
    0 => ChatListView(controller: _chatListController),
    1 => const ContactsView(),
    _ => const MomentsView(),
  };

  Future<bool> _onWillPop() async {
    final nav = _navKeys[_selection].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return false;
    }
    return true;
  }

  void _select(int i) {
    final theme = context.read<ThemeController>();
    final shouldJumpUnread =
        i == 0 && _unread.countFor(theme.unreadBadgeMode) > 0;
    if (i == _selection) {
      // Tapping the active tab pops to its root.
      _navKeys[i].currentState?.popUntil((r) => r.isFirst);
      if (shouldJumpUnread) _scrollMessagesToFirstUnread();
      return;
    }
    setState(() => _selection = i);
    if (shouldJumpUnread) _scrollMessagesToFirstUnread();
  }

  void _scrollMessagesToFirstUnread() {
    _chatListController.scrollToFirstUnread();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _tabBar),
        ChangeNotifierProvider.value(value: _unread),
        ChangeNotifierProvider.value(value: _calls),
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
          child: Stack(
            children: [
              theme.tabBarStyle == TabBarStyle.system
                  ? _systemTabs()
                  : _classicTabs(),
              _drawerOverlay(),
              // Full-screen call HUD over everything when a call is active.
              Consumer<CallManager>(
                builder: (context, calls, _) => calls.call == null
                    ? const SizedBox.shrink()
                    : Positioned.fill(child: CallScreen(manager: calls)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Per-tab navigators

  Widget _tabNavigator(int i) {
    return _TabNavigator(
      navigatorKey: _navKeys[i],
      observer: dc.TabDepthObserver(i, _tabBar),
      root: _root(i),
    );
  }

  Widget _stack() => IndexedStack(
    index: _selection,
    children: [for (var i = 0; i < 3; i++) _tabNavigator(i)],
  );

  // MARK: - Classic (flat) tab bar

  Widget _classicTabs() {
    final theme = context.watch<ThemeController>();
    return Column(
      children: [
        Expanded(child: _stack()),
        Consumer<dc.TabBarVisibility>(
          builder: (context, vis, _) {
            final hidden = vis.depth(_selection) > 0;
            return AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: hidden
                  ? const SizedBox(width: double.infinity)
                  : _ClassicTabBar(
                      selection: _selection,
                      onSelect: _select,
                      items: _tabs,
                      unread: context.watch<UnreadBadgeModel>().countFor(
                        theme.unreadBadgeMode,
                      ),
                    ),
            );
          },
        ),
      ],
    );
  }

  // MARK: - System tab bar

  Widget _systemTabs() {
    final c = context.colors;
    return Scaffold(
      body: _stack(),
      bottomNavigationBar: Consumer<dc.TabBarVisibility>(
        builder: (context, vis, _) {
          if (vis.depth(_selection) > 0) return const SizedBox.shrink();
          return BottomNavigationBar(
            currentIndex: _selection,
            onTap: _select,
            type: BottomNavigationBarType.fixed,
            backgroundColor: c.navBar,
            selectedItemColor: AppTheme.brand,
            unselectedItemColor: c.textTertiary,
            items: [
              for (final t in _tabs)
                BottomNavigationBarItem(icon: Icon(sfIcon(t.$2)), label: t.$1),
            ],
          );
        },
      ),
    );
  }

  // MARK: - Drawer overlay (the "我" profile drawer)

  Widget _drawerOverlay() {
    return Consumer<dc.DrawerController>(
      builder: (context, drawer, _) {
        final width = MediaQuery.of(context).size.width * 0.88;
        return IgnorePointer(
          ignoring: !drawer.isOpen,
          child: Stack(
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                opacity: drawer.isOpen ? 1 : 0,
                child: GestureDetector(
                  onTap: drawer.close,
                  child: Container(color: Colors.black.withValues(alpha: 0.35)),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
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
    required this.items,
    required this.unread,
  });
  final int selection;
  final ValueChanged<int> onSelect;
  final List<(String, String)> items;
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
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 28,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                sfIcon(items[i].$2),
                                size: 26,
                                color: selection == i
                                    ? AppTheme.brand
                                    : c.textTertiary,
                              ),
                              if (i == 0 && unread > 0)
                                Positioned(
                                  right: -10,
                                  top: -5,
                                  child: _miniBadge(unread),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].$1,
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniBadge(int count) => Container(
    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
    padding: EdgeInsets.symmetric(horizontal: count > 9 ? 5 : 0),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppTheme.unreadBadge,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      count > 99 ? '99+' : '$count',
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
  );
}
