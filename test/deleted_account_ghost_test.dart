import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_message_merge.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_detail_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

/// The account TDLib reports as `userTypeDeleted`: it keeps its id — history
/// still points at it — but has no name, photo or reachable inbox.
Map<String, dynamic> deletedUser(int id) => {
  '@type': 'user',
  'id': id,
  'first_name': '',
  'last_name': '',
  'type': {'@type': 'userTypeDeleted'},
  'status': {'@type': 'userStatusEmpty'},
};

Map<String, dynamic> regularUser(int id, {String first = 'Ada'}) => {
  '@type': 'user',
  'id': id,
  'first_name': first,
  'last_name': 'Lovelace',
  'type': {'@type': 'userTypeRegular'},
  'status': {'@type': 'userStatusOffline', 'was_online': 1},
};

/// Requests are answered by whichever fixture the running test installs; the
/// transport itself is configured once so no test closes a live update stream.
late Future<Map<String, dynamic>> Function(Map<String, dynamic>) serve;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures = L10nFixtures.load();

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) => serve(request),
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });

  tearDownAll(TdClient.shared.closeProxy);

  setUp(() {
    fixtures.install();
    AppStrings.setLocale(const Locale('en'));
    serve = (request) async => {'@type': 'ok'};
  });

  test('a refreshed message keeps the ghost while its sender is unchanged', () {
    ChatMessage cached() => ChatMessage(
      id: 61,
      isOutgoing: false,
      text: 'Hello',
      date: 1,
      chatId: -10061,
      senderId: 910021,
      senderName: 'Deleted Account',
      senderIsDeleted: true,
    );
    ChatMessage refresh({int senderId = 910021}) => ChatMessage(
      id: 61,
      isOutgoing: false,
      text: 'Hello, edited',
      date: 1,
      chatId: -10061,
      senderId: senderId,
    );

    final sameSender = mergeChatMessages([cached()], [refresh()]).single;
    expect(sameSender.senderIsDeleted, isTrue);
    expect(sameSender.senderName, 'Deleted Account');

    // An edit cannot hand the message to another account; if it does, the old
    // sender's ghost must not follow it.
    final retargeted = mergeChatMessages(
      [cached()],
      [refresh(senderId: 910022)],
    ).single;
    expect(retargeted.senderIsDeleted, isFalse);
  });

  testWidgets('the profile shows a ghost and no unusable actions', (
    tester,
  ) async {
    const userId = 910031;
    final queried = <String>[];
    serve = (request) async {
      queried.add('${request['@type']}');
      return switch (request['@type']) {
        'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Me'},
        'getUser' => deletedUser(userId),
        'getUserProfilePhotos' => {
          '@type': 'photos',
          'total_count': 0,
          'photos': <dynamic>[],
        },
        'createPrivateChat' => {'@type': 'chat', 'id': 42},
        _ => {'@type': 'ok'},
      };
    };

    final theme = await _theme(tester);
    tester.view.physicalSize = const Size(560, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
          home: const ProfileDetailView(userId: userId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(queried, contains('getUser'));
    expect(find.text('Deleted Account'), findsWidgets);
    expect(_ghosts(), findsWidgets);
    // Nothing here can reach the account: no composer, no call, no contact
    // management, and no history search that would open the dead chat.
    expect(find.text('Send message'), findsNothing);
    expect(find.text('Audio/video call'), findsNothing);
    expect(find.text('Add friend'), findsNothing);
    expect(find.text('Search chat history'), findsNothing);
  });
}

/// The ghost surface under any avatar: the silhouette, not just a monogram.
Finder _ghosts() => find.byKey(ghostAvatarKey);

Future<ThemeController> _theme(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  addTearDown(theme.dispose);
  return theme;
}
