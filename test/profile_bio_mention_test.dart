import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_detail_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A typed `@username` in a profile bio carries no user id, so a tap has to
/// resolve the username and open that person instead of falling through to the
/// public chat-link route.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const viewerId = 777;
  const otherId = 888;
  const mentionedId = 999;
  const mentionedUsername = 'duck_user';
  const mentionedChatId = 555;
  const bio = '@duck_user keeps the tea tins on the top shelf.';

  late Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler;
  late List<Map<String, dynamic>> requests;
  late bool usernameLookupFails;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) => handler(request),
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });

  tearDownAll(TdClient.shared.closeProxy);

  setUp(() {
    requests = [];
    usernameLookupFails = false;
    handler = (request) async {
      requests.add(request);
      switch (request['@type']) {
        case 'getMe':
          return {'@type': 'user', 'id': viewerId, 'first_name': 'Me'};
        case 'getUser':
          final userId = request['user_id'];
          return {
            '@type': 'user',
            'id': userId,
            'first_name': userId == mentionedId ? 'Duck' : 'ieb',
            'type': {'@type': 'userTypeRegular'},
            'status': {'@type': 'userStatusOffline', 'was_online': 0},
          };
        case 'getUserFullInfo':
          return {
            '@type': 'userFullInfo',
            'bio': {
              '@type': 'formattedText',
              'text': bio,
              'entities': [
                {
                  'offset': 0,
                  'length': mentionedUsername.length + 1,
                  'type': {'@type': 'textEntityTypeMention'},
                },
              ],
            },
          };
        case 'getUserProfilePhotos':
          return {'@type': 'photos', 'total_count': 0, 'photos': <dynamic>[]};
        case 'createPrivateChat':
          return {
            '@type': 'chat',
            'id': 42,
            'action_bar': {'@type': 'chatActionBarNone'},
          };
        case 'searchPublicChat':
          if (usernameLookupFails) {
            throw StateError('username lookup unavailable');
          }
          return {
            '@type': 'chat',
            'id': mentionedChatId,
            'title': mentionedUsername,
            'type': {'@type': 'chatTypePrivate', 'user_id': mentionedId},
            'action_bar': {'@type': 'chatActionBarNone'},
          };
        default:
          return {'@type': 'ok'};
      }
    };
  });

  Future<void> pumpProfile(WidgetTester tester, {required int id}) async {
    tester.view.physicalSize = const Size(560, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);

    await tester.pumpWidget(
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
          home: ProfileDetailView(userId: id, name: 'ieb'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapMention(WidgetTester tester) async {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byKey(const ValueKey('profileBio')),
        matching: find.byType(RichText),
      ),
    );
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(
        baseOffset: 0,
        extentOffset: mentionedUsername.length + 1,
      ),
    );
    expect(boxes, isNotEmpty);
    await tester.tapAt(paragraph.localToGlobal(boxes.first.toRect().center));
  }

  List<Object?> requestedTypes() =>
      requests.map((request) => request['@type']).toList(growable: false);

  Iterable<Map<String, dynamic>> requestsOf(String type) =>
      requests.where((request) => request['@type'] == type);

  List<int> pushedProfileIds(WidgetTester tester) => tester
      .widgetList<ProfileDetailView>(find.byType(ProfileDetailView))
      .map((view) => view.userId)
      .toList(growable: false);

  testWidgets('a typed username mention on another profile opens that person', (
    tester,
  ) async {
    await pumpProfile(tester, id: otherId);
    await tapMention(tester);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(pushedProfileIds(tester), contains(mentionedId));
    final lookups = requestsOf('searchPublicChat').toList(growable: false);
    expect(lookups, hasLength(1));
    expect(lookups.single['username'], mentionedUsername);
    // The chat deep-link route would classify the t.me link and then open the
    // public chat; neither step belongs in a profile mention tap.
    expect(requestedTypes(), isNot(contains('getInternalLinkType')));
    expect(
      requests.where(
        (request) =>
            request['@type'] == 'getChat' &&
            request['chat_id'] == mentionedChatId,
      ),
      isEmpty,
    );
  });

  testWidgets(
    'the signed-in profile resolves a username mention the same way',
    (tester) async {
      await pumpProfile(tester, id: viewerId);
      expect(find.byKey(const ValueKey('profileBioEditIcon')), findsOneWidget);

      await tapMention(tester);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(pushedProfileIds(tester), contains(mentionedId));
      expect(requestsOf('searchPublicChat'), hasLength(1));
      expect(requestedTypes(), isNot(contains('getInternalLinkType')));
    },
  );

  testWidgets('a failed username lookup reports it and pushes no profile', (
    tester,
  ) async {
    usernameLookupFails = true;
    await pumpProfile(tester, id: otherId);
    await tapMention(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Unable to open Telegram link'), findsOneWidget);
    expect(pushedProfileIds(tester), [otherId]);
    expect(requestedTypes(), contains('searchPublicChat'));
    expect(requestedTypes(), isNot(contains('getInternalLinkType')));

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('a closed profile drops a late username lookup', (tester) async {
    final release = Completer<void>();
    final arrived = Completer<void>();
    final previous = handler;
    handler = (request) async {
      final response = await previous(request);
      if (request['@type'] == 'searchPublicChat') {
        arrived.complete();
        await release.future;
      }
      return response;
    };
    await pumpProfile(tester, id: otherId);
    await tapMention(tester);
    await tester.pump();
    expect(arrived.isCompleted, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    release.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      requests.where(
        (r) => r['@type'] == 'getUser' && r['user_id'] == mentionedId,
      ),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
}
