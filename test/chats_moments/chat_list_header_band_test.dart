import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/scaled_app_view.dart';
import 'package:mithka/app/top_corner_cluster.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _longName =
    'Wilhelmina Featherstonehaugh-Cholmondeley of the Northern Reaches';

/// A closed iPhone Duo as the platform reports it, in window points.
/// The closed screen reports the camera as its own region inside the status
/// cluster.
const _closedDuo = TopOcclusionData(
  safeTop: 82,
  statusBarBottom: 2,
  windowWidth: 466,
  regions: [Rect.fromLTWH(266, 0, 200, 82), Rect.fromLTWH(399.7, 29.3, 37, 37)],
);

/// An opened iPhone Duo: the status items sit in the top-right corner.
const _openedDuo = TopOcclusionData(
  safeTop: 82,
  statusBarBottom: 2,
  windowWidth: 951,
  regions: [Rect.fromLTWH(807, 0, 144, 82)],
);

/// A regular iPhone: a centred Dynamic Island under a full-width status bar.
const _islandPhone = TopOcclusionData(
  safeTop: 62,
  statusBarBottom: 54,
  windowWidth: 440,
  regions: [Rect.fromLTWH(157, 11, 126, 37)],
);

/// The same island reported while the status bar is not: the geometry alone
/// would free the top edge, but the island touches no side edge.
const _islandNoStatusBar = TopOcclusionData(
  safeTop: 62,
  statusBarBottom: 0,
  windowWidth: 440,
  regions: [Rect.fromLTWH(157, 0, 126, 62)],
);

final _add = find.byKey(const ValueKey('chat-list-header-add-hit'));
final _tabs = find.byWidgetPredicate(
  (widget) => widget is ListView && widget.scrollDirection == Axis.horizontal,
);
final _search = find.byKey(const ValueKey('chat-list-inline-search'));
final _avatar = find.byKey(const ValueKey('chat-list-header-avatar-hit'));

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': _longName},
          'getConnectionState' => {'@type': 'connectionStateReady'},
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  // Regular iPhones, iPads, Android and the rest keep the header exactly as
  // it was before the Duo work: the + on the profile row, a full-width tab
  // strip with no fade, and the menu at its old anchor.
  for (final (name, occlusion) in const [
    ('no cluster', null),
    ('a Dynamic Island under a status bar', _islandPhone),
    ('a Dynamic Island without a status bar', _islandNoStatusBar),
  ]) {
    testWidgets(
      'off a Duo with $name the + stays on the profile row',
      (tester) async {
        final top = occlusion?.safeTop ?? 47.0;
        await _pumpChatList(
          tester,
          updates,
          folders: true,
          size: const Size(440, 956),
          topInset: top,
          occlusion: occlusion,
        );
        final add = tester.getRect(_add);
        final avatar = tester.getRect(_avatar);
        expect(add.size, const Size(44, 44));
        expect(add.right, moreOrLessEquals(440 - 16));
        expect(add.center.dy, moreOrLessEquals(avatar.center.dy));
        expect(avatar.top, greaterThanOrEqualTo(top));
        // Full-width tabs right under the row, with no fade and no slot.
        expect(find.byType(ShaderMask), findsNothing);
        final tabs = tester.getRect(_tabs);
        expect(tabs.left, 0);
        expect(tabs.width, 440);
        expect(tabs.top, moreOrLessEquals(avatar.bottom + 10));
        expect(
          tester.widget<ListView>(_tabs).padding,
          const EdgeInsetsDirectional.only(start: 12, end: 12),
        );
        expect(
          tester.getTopLeft(_search).dy,
          greaterThanOrEqualTo(tabs.bottom),
        );

        await tester.tap(_add);
        await tester.pumpAndSettle();
        expect(find.text('Create group'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byType(PlusMenu)).dy,
          moreOrLessEquals(top + 48),
        );
        await _dispose(tester);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  testWidgets(
    'Duo geometry off iOS keeps the original header',
    (tester) async {
      await _pumpChatList(
        tester,
        updates,
        folders: true,
        size: const Size(466, 1000),
        topInset: 82,
        occlusion: _closedDuo,
      );
      expect(find.byType(ShaderMask), findsNothing);
      expect(
        tester.getCenter(_add).dy,
        moreOrLessEquals(tester.getCenter(_avatar).dy, epsilon: 0.5),
      );
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final (name, occlusion) in const [
    ('closed', _closedDuo),
    ('opened', _openedDuo),
  ]) {
    testWidgets(
      '$name Duo: the + sits at the end of the tab row',
      (tester) async {
        final width = occlusion.windowWidth;
        await _pumpChatList(
          tester,
          updates,
          folders: true,
          size: Size(width, occlusion == _closedDuo ? 1000 : 669),
          topInset: 82,
          occlusion: occlusion,
        );
        final add = tester.getRect(_add);
        expect(add.size, const Size(44, 44));
        expect(add.right, moreOrLessEquals(width - 16));
        expect(
          add.center.dy,
          moreOrLessEquals(tester.getCenter(find.text('Work')).dy, epsilon: 1),
        );
        expect(add.top, greaterThan(tester.getRect(_avatar).bottom));
        // The tabs fade out before they reach the +.
        expect(find.byType(ShaderMask), findsOneWidget);

        await tester.tap(_add);
        await tester.pumpAndSettle();
        expect(find.text('Create group'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Create group')).dy,
          greaterThan(add.center.dy),
        );
        await _dispose(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'without folders the + stays on the profile row',
    (tester) async {
      await _pumpChatList(tester, updates, folders: false);
      expect(find.byType(ShaderMask), findsNothing);
      expect(
        tester.getCenter(_add).dy,
        moreOrLessEquals(tester.getCenter(_avatar).dy, epsilon: 0.5),
      );
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  for (final s in const [1.0, 0.9487, 1.483]) {
    testWidgets(
      'closed Duo: the profile row moves up beside the cluster at s=$s',
      (tester) async {
        await _pumpChatList(
          tester,
          updates,
          folders: true,
          size: const Size(466, 1000),
          topInset: 82,
          scale: s,
          occlusion: _closedDuo,
        );
        // Window points: the avatar sits on the clock and camera line and
        // the truncated name ends 8pt before the cluster.
        final avatar = tester.getRect(_avatar);
        expect(avatar.center.dy, moreOrLessEquals(47.8, epsilon: 1));
        final name = tester.getRect(find.text(_longName));
        expect(name.right, lessThanOrEqualTo(258 + 0.5));
        // The tabs follow the row with its usual 10pt gap, clear of the
        // camera.
        final tabsTop = tester.getTopLeft(find.byType(ShaderMask)).dy;
        expect(tabsTop, moreOrLessEquals(avatar.bottom + 10 * s, epsilon: 1));
        expect(tabsTop, greaterThanOrEqualTo(66.3));
        expect(tester.getRect(_add).top, greaterThan(66.3));
        await _dispose(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  for (final s in const [1.0, 0.9487, 1.483]) {
    testWidgets(
      'opened Duo, one column: the profile row sits on the clock line at s=$s',
      (tester) async {
        await _pumpChatList(
          tester,
          updates,
          folders: true,
          size: const Size(951, 669),
          topInset: 82,
          scale: s,
          occlusion: _openedDuo,
        );
        final avatar = tester.getRect(_avatar);
        expect(avatar.center.dy, moreOrLessEquals(41, epsilon: 1));
        expect(
          tester.getRect(find.text(_longName)).right,
          lessThanOrEqualTo(799 + 0.5),
        );
        // Everything below starts clear of the cluster.
        final tabsTop = tester.getTopLeft(find.byType(ShaderMask)).dy;
        expect(tabsTop, greaterThanOrEqualTo(82 - 0.5));
        await _dispose(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'opened Duo, two columns: the list column moves up level with the '
      'clock at s=$s',
      (tester) async {
        await _pumpChatList(
          tester,
          updates,
          folders: true,
          size: const Size(951, 669),
          topInset: 82,
          scale: s,
          occlusion: _openedDuo,
          layout: (list) => Row(
            children: [
              SizedBox(
                width: 400 / s,
                child: TopClusterPane(child: list),
              ),
              const Expanded(child: TopClusterPane(child: SizedBox.expand())),
            ],
          ),
        );
        final avatar = tester.getRect(_avatar);
        expect(avatar.center.dy, moreOrLessEquals(41, epsilon: 1));
        // Away from the cluster the tabs keep their usual 10pt gap below the
        // row instead of waiting for the cluster's bottom.
        final tabsTop = tester.getTopLeft(find.byType(ShaderMask)).dy;
        expect(tabsTop, moreOrLessEquals(avatar.bottom + 10 * s, epsilon: 1));
        // At 220% the row alone already reaches past the cluster's bottom.
        if (s < 1.2) expect(tabsTop, lessThan(82));
        await _dispose(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'opened Duo, list column under the cluster: on the line, 8pt clear at '
      's=$s',
      (tester) async {
        await _pumpChatList(
          tester,
          updates,
          folders: true,
          size: const Size(951, 669),
          topInset: 82,
          scale: s,
          occlusion: _openedDuo,
          layout: (list) => Row(
            children: [
              const Expanded(child: TopClusterPane(child: SizedBox.expand())),
              SizedBox(
                width: 551 / s,
                child: TopClusterPane(child: list),
              ),
            ],
          ),
        );
        final avatar = tester.getRect(_avatar);
        expect(avatar.center.dy, moreOrLessEquals(41, epsilon: 1));
        expect(
          tester.getRect(find.text(_longName)).right,
          lessThanOrEqualTo(799 + 0.5),
        );
        expect(
          tester.getTopLeft(find.byType(ShaderMask)).dy,
          greaterThanOrEqualTo(82 - 0.5),
        );
        await _dispose(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'without a cluster the header keeps the safe-area top',
    (tester) async {
      await _pumpChatList(
        tester,
        updates,
        folders: true,
        size: const Size(466, 1000),
        topInset: 82,
      );
      expect(tester.getRect(_avatar).top, greaterThanOrEqualTo(82));
      await _dispose(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

Future<void> _pumpChatList(
  WidgetTester tester,
  StreamController<Map<String, dynamic>> updates, {
  required bool folders,
  Size size = const Size(390, 844),
  double topInset = 0,
  double scale = 1,
  TopOcclusionData? occlusion,
  Widget Function(Widget list)? layout,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: topInset);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    'communitiesEnabled': false,
    'showChatListSearch': true,
  });
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        builder: (context, child) => ScaledAppView(
          textScale: 1,
          interfaceScale: scale,
          child: Builder(
            builder: (context) => TopOcclusionGeometry(
              data: occlusion?.inViewScale(ScaledAppView.scaleOf(context)),
              child: child!,
            ),
          ),
        ),
        home: Scaffold(
          body: layout?.call(const ChatListView()) ?? const ChatListView(),
        ),
      ),
    ),
  );

  updates.add({
    '@type': 'updateConnectionState',
    'state': {'@type': 'connectionStateReady'},
  });
  updates.add({
    '@type': 'updateChatFolders',
    'chat_folders': [
      if (folders) {'id': 1, 'title': 'Work'},
    ],
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}
