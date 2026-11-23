//
//  Mithka channel bottom panel: the three-way choice (stock mute bar,
//  discussion / direct-message actions, hidden) and its per-channel fallback
//  when neither a discussion group nor a direct-messages group exists.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/channel_bottom_panel.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ThemeController> _theme() async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  addTearDown(theme.dispose);
  return theme;
}

Widget _app(ThemeController theme, Widget home) =>
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

Widget _panel({
  required ChannelBottomBarMode mode,
  bool hasDiscussion = false,
  bool hasDirectMessages = false,
  bool muted = false,
  VoidCallback? onToggleMute,
  VoidCallback? onOpenDiscussion,
  VoidCallback? onOpenDirectMessages,
}) => ChannelBottomPanel(
  mode: mode,
  muted: muted,
  hasDiscussion: hasDiscussion,
  hasDirectMessages: hasDirectMessages,
  onToggleMute: onToggleMute ?? () {},
  onOpenDiscussion: onOpenDiscussion ?? () {},
  onOpenDirectMessages: onOpenDirectMessages ?? () {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('action list', () {
    test('a channel without linked chats offers no action', () {
      expect(
        channelBottomPanelActions(
          hasDiscussion: false,
          hasDirectMessages: false,
        ),
        isEmpty,
      );
    });

    test('the discussion group leads, then direct messages', () {
      expect(
        channelBottomPanelActions(hasDiscussion: true, hasDirectMessages: true),
        [
          ChannelBottomPanelAction.discussion,
          ChannelBottomPanelAction.directMessages,
        ],
      );
      expect(
        channelBottomPanelActions(
          hasDiscussion: false,
          hasDirectMessages: true,
        ),
        [ChannelBottomPanelAction.directMessages],
      );
    });
  });

  testWidgets('default mode keeps the stock mute / unmute bar', (tester) async {
    final theme = await _theme();
    var toggles = 0;
    await tester.pumpWidget(
      _app(
        theme,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: _panel(
              mode: ChannelBottomBarMode.mute,
              hasDiscussion: true,
              hasDirectMessages: true,
              onToggleMute: () => toggles++,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(ChannelBottomPanel.muteKey), findsOneWidget);
    expect(find.text(AppStrings.t(AppStringKeys.callMute)), findsOneWidget);
    // The action buttons never appear in the stock mode.
    expect(find.byKey(ChannelBottomPanel.discussionKey), findsNothing);
    expect(find.byKey(ChannelBottomPanel.directMessagesKey), findsNothing);

    await tester.tap(find.byKey(ChannelBottomPanel.muteKey));
    expect(toggles, 1);
  });

  testWidgets('actions mode opens discussion and direct messages', (
    tester,
  ) async {
    final theme = await _theme();
    var discussion = 0;
    var direct = 0;
    await tester.pumpWidget(
      _app(
        theme,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: _panel(
              mode: ChannelBottomBarMode.actions,
              hasDiscussion: true,
              hasDirectMessages: true,
              onOpenDiscussion: () => discussion++,
              onOpenDirectMessages: () => direct++,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(ChannelBottomPanel.discussionKey), findsOneWidget);
    expect(find.byKey(ChannelBottomPanel.directMessagesKey), findsOneWidget);
    expect(find.byKey(ChannelBottomPanel.muteKey), findsNothing);

    await tester.tap(find.byKey(ChannelBottomPanel.discussionKey));
    await tester.tap(find.byKey(ChannelBottomPanel.directMessagesKey));
    expect(discussion, 1);
    expect(direct, 1);
  });

  testWidgets('actions mode shows nothing when the channel has neither', (
    tester,
  ) async {
    final theme = await _theme();
    await tester.pumpWidget(
      _app(
        theme,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: _panel(mode: ChannelBottomBarMode.actions),
          ),
        ),
      ),
    );

    expect(find.byKey(ChannelBottomPanel.emptyKey), findsOneWidget);
    expect(find.byKey(ChannelBottomPanel.muteKey), findsNothing);
    expect(find.byKey(ChannelBottomPanel.discussionKey), findsNothing);
    expect(find.byKey(ChannelBottomPanel.directMessagesKey), findsNothing);
  });

  testWidgets('hidden mode reserves no panel at all', (tester) async {
    final theme = await _theme();
    await tester.pumpWidget(
      _app(
        theme,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: _panel(
              mode: ChannelBottomBarMode.hidden,
              hasDiscussion: true,
              hasDirectMessages: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(ChannelBottomPanel.muteKey), findsNothing);
    expect(find.byKey(ChannelBottomPanel.discussionKey), findsNothing);
    expect(find.byKey(ChannelBottomPanel.emptyKey), findsNothing);
  });

  testWidgets('the settings page persists the chosen mode', (tester) async {
    final theme = await _theme();
    await tester.pumpWidget(_app(theme, const ChannelBottomBarSettingsView()));
    await tester.pumpAndSettle();

    expect(theme.channelBottomBarMode, ChannelBottomBarMode.mute);
    await tester.tap(find.byKey(const ValueKey('channel-bottom-bar-hidden')));
    await tester.pumpAndSettle();
    expect(theme.channelBottomBarMode, ChannelBottomBarMode.hidden);

    await tester.tap(find.byKey(const ValueKey('channel-bottom-bar-actions')));
    await tester.pumpAndSettle();
    expect(theme.channelBottomBarMode, ChannelBottomBarMode.actions);
    expect(theme.showChannelPostStats, isTrue);
  });
}
