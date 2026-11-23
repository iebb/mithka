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
const _closedDuo = TopOcclusionData(
  safeTop: 82,
  statusBarBottom: 2,
  windowWidth: 466,
  regions: [Rect.fromLTWH(266, 0, 200, 82)],
);

final _add = find.byKey(const ValueKey('chat-list-header-add-hit'));
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

  testWidgets(
    'with folders the + sits at the end of the tab row',
    (tester) async {
      await _pumpChatList(tester, updates, folders: true);
      final add = tester.getRect(_add);
      final width = tester.view.physicalSize.width;
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
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

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
    variant: TargetPlatformVariant.only(TargetPlatform.android),
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
        // Window points: the avatar is centred on the cluster and the
        // truncated name ends 8pt before it.
        expect(tester.getCenter(_avatar).dy, moreOrLessEquals(41, epsilon: 1));
        final name = tester.getRect(find.text(_longName));
        expect(name.right, lessThanOrEqualTo(258 + 0.5));
        // Tabs start below the cluster, keeping the + clear of it.
        expect(tester.getRect(_add).top, greaterThanOrEqualTo(82));
        expect(
          tester.getTopLeft(find.byType(ShaderMask)).dy,
          greaterThanOrEqualTo(82 - 0.5),
        );
        await _dispose(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
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
    variant: TargetPlatformVariant.only(TargetPlatform.android),
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
        home: const Scaffold(body: ChatListView()),
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
