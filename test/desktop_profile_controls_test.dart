import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/app_navigator.dart';
import 'package:mithka/app/content_view.dart';
import 'package:mithka/app/desktop_utility_window.dart';
import 'package:mithka/app/desktop_window_controls.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:mithka/chat/custom_emoji.dart';
import 'package:mithka/chat/emoji_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _accountSlot = 2;
const _userId = 88;
const _statusKey = ValueKey('desktop-title-bar-status');
const _accountKey = ValueKey('macos-title-bar-account');
const _popupKey = ValueKey('desktop-title-bar-profile-popup');
const _editKey = ValueKey('desktop-title-bar-profile-edit');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StreamController<Map<String, dynamic>> updates;
  late AccountStore accounts;
  late ThemeController theme;
  var statusId = 0;
  final statusRequests = <Map<String, dynamic>>[];

  Map<String, dynamic> user() => {
    '@type': 'user',
    'id': _userId,
    'first_name': 'Alpha',
    'phone_number': '15550100',
    'emoji_status': statusId == 0
        ? null
        : {
            '@type': 'emojiStatus',
            'type': {
              '@type': 'emojiStatusTypeCustomEmoji',
              'custom_emoji_id': statusId,
            },
            'expiration_date': 0,
          },
  };

  setUpAll(() async {
    updates = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: _accountSlot,
        accountUserId: _userId,
        query: (request) async {
          switch (request['@type']) {
            case 'getMe':
              return user();
            case 'getOption':
              return {'@type': 'optionValueBoolean', 'value': false};
            case 'getThemedEmojiStatuses':
              return {
                '@type': 'emojiStatuses',
                'custom_emoji_ids': [42, 43],
              };
            case 'getCustomEmojiStickers':
              return {'@type': 'stickers', 'stickers': <dynamic>[]};
            case 'setEmojiStatus':
              statusRequests.add(request);
              final status = request['emoji_status'] as Map<String, dynamic>?;
              statusId = status?['type']['custom_emoji_id'] as int? ?? 0;
              updates.add({'@type': 'updateUser', 'user': user()});
              return {'@type': 'ok'};
          }
          return {'@type': 'ok'};
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    accounts = AccountStore(prefs);
    theme = ThemeController(prefs);
    await accounts.refresh();
  });

  setUp(() async {
    statusId = 0;
    statusRequests.clear();
    CustomEmojiCenter.shared.reset();
    EmojiStore.shared.reset();
    await accounts.refresh();
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
    accounts.dispose();
    theme.dispose();
  });

  Future<void> pumpFrame(
    WidgetTester tester, {
    bool accountReady = true,
    String? accountName,
    Future<bool> Function(DesktopUtilityWindowArguments)? opener,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountStore>.value(value: accounts),
          ChangeNotifierProvider<ThemeController>.value(value: theme),
        ],
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          theme: ThemeData(extensions: [AppColors.light]),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => DesktopPrimaryWindowFrame(
            accountReady: accountReady,
            accountName: accountName,
            showAccountPhone: true,
            profileWindowOpener: opener,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const ColoredBox(
            key: ValueKey('workspace'),
            color: Colors.white,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'status next to account opens picker, updates, and clears',
    (tester) async {
      await pumpFrame(tester);
      final status = find.byKey(_statusKey);
      expect(tester.getSize(status), const Size.square(28));
      expect(
        tester.getTopLeft(status).dx,
        tester.getTopRight(find.byKey(_accountKey)).dx + 2,
      );
      expect(find.byType(StatusEmojiView), findsNothing);

      // The frame is above the Navigator, so the button must resolve a context
      // inside its overlay to present the real picker.
      await tester.tap(find.byKey(_accountKey));
      await tester.pump();
      expect(find.byKey(_popupKey), findsOneWidget);
      await tester.tap(status);
      await tester.pumpAndSettle();
      expect(find.byKey(_popupKey), findsNothing);
      expect(find.text('Set status'), findsOneWidget);

      await tester.tap(
        find
            .ancestor(
              of: find.byWidgetPredicate(
                (widget) => widget is StatusEmojiView && widget.id == 42,
              ),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(statusRequests.single['emoji_status'], {
        '@type': 'emojiStatus',
        'type': {'@type': 'emojiStatusTypeCustomEmoji', 'custom_emoji_id': 42},
        'expiration_date': 0,
      });
      expect(accounts.summaries.single.emojiStatusId, 42);
      expect(
        tester.widget<StatusEmojiView>(find.byType(StatusEmojiView)).id,
        42,
      );
      expect(find.text('Set status'), findsNothing);

      await tester.tap(status);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(statusRequests.last['emoji_status'], isNull);
      expect(find.byType(StatusEmojiView), findsNothing);
      expect(find.byKey(_statusKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'remote self status changes refresh the title bar',
    (tester) async {
      await pumpFrame(tester);
      statusId = 43;
      updates.add({'@type': 'updateUser', 'user': user()});
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.widget<StatusEmojiView>(find.byType(StatusEmojiView)).id,
        43,
      );
      expect(statusRequests, isEmpty);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      'profile Edit opens current account editor on ${platform.name}',
      (tester) async {
        DesktopUtilityWindowArguments? request;
        await pumpFrame(
          tester,
          opener: (arguments) async {
            request = arguments;
            return true;
          },
        );
        await tester.tap(find.byKey(_accountKey));
        await tester.pump();
        expect(find.text('Edit profile'), findsOneWidget);
        await tester.tap(find.byKey(_editKey));
        await tester.pumpAndSettle();
        expect(request?.kind, DesktopUtilityWindowKind.editProfile);
        expect(request?.accountSlot, _accountSlot);
        expect(request?.accountUserId, _userId);
        expect(request?.title, 'Edit profile');
        expect(request?.localeTag, 'en');
        expect(request?.dark, false);
        expect(find.byKey(_popupKey), findsNothing);
        expect(find.byKey(const ValueKey('workspace')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets(
    'long names and narrow desktop windows do not overflow',
    (tester) async {
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());
      tester.view.devicePixelRatio = 1;
      for (final width in [800.0, 520.0, 440.0, 430.0, 420.0, 400.0]) {
        tester.view.physicalSize = Size(width, 600);
        await pumpFrame(
          tester,
          accountName: 'An exceptionally long account name',
        );
        expect(
          tester.takeException(),
          isNull,
          reason: '$defaultTargetPlatform at $width',
        );
        if (usesFlutterDesktopWindowControls) {
          expect(
            tester
                .getTopRight(
                  find.byKey(
                    const ValueKey('desktop-title-bar-window-controls'),
                  ),
                )
                .dx,
            width,
          );
        }
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }),
  );

  testWidgets(
    'signed out title bar has no profile editing controls',
    (tester) async {
      await pumpFrame(tester, accountReady: false);
      expect(find.byKey(_statusKey), findsNothing);
      await tester.tap(find.byKey(_accountKey));
      await tester.pump();
      expect(find.byKey(_popupKey), findsNothing);
      expect(find.byKey(_editKey), findsNothing);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
