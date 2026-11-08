import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/notification_exceptions_sheet.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _privateScope = 'notificationSettingsScopePrivateChats';

/// Two real accounts: slot 1 / client 100 and slot 2 / client 101, with the
/// first one foreground. Both own a chat 42 with a different title and
/// different notification settings, so a request that follows the foreground
/// instead of the pinned owner is observable in the rendered rows and in the
/// exact (clientId, @type, chat_id) tuples.
const _alphaClientId = 100;
const _betaClientId = 101;
const _chatId = 42;

typedef _Respond =
    FutureOr<Map<String, dynamic>> Function(
      Map<String, dynamic> request,
      int clientId,
    );

/// Stands in for tdjson: allocates client ids and answers the close handshake
/// so slot removal completes without the real 15-second timeout.
class _FakeBindings implements TdBindings {
  _FakeBindings(this._client);

  final TdClient _client;
  int _nextClientId = _alphaClientId;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    final decoded = jsonDecode(request) as Map<String, dynamic>;
    if (decoded['@type'] == 'close') {
      _client.debugCompleteClientClosed(clientId);
    }
  }

  @override
  void importSessionString(String sessionString, String destinationPath) {
    File(destinationPath).writeAsBytesSync(Uint8List.fromList(const [1]));
  }

  @override
  bool get supportsSessionStringBackup => true;

  @override
  bool get supportsTransferBoost => false;

  @override
  String? receive(double timeout) => throw UnimplementedError();

  @override
  Object? receiveJson(double timeout) => throw UnimplementedError();

  @override
  String? execute(String request) => throw UnimplementedError();

  @override
  String exportSessionString(
    String sourcePath, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) => throw UnimplementedError();

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}

/// One private real [TdClient] registry per test.
final class _Registry {
  _Registry(this.client, this.bindings, this.supportDir);

  final TdClient client;
  final _FakeBindings bindings;
  final Directory supportDir;
  late final int alphaSlot;
  late final int betaSlot;

  /// Every request as (client that served it, request body), in order.
  final List<(int, Map<String, dynamic>)> requests = [];

  NotificationExceptionAccounts get accounts =>
      TdNotificationExceptionAccounts(client: client);

  List<(int, String, int?)> tuples(Iterable<String> types) => [
    for (final (clientId, request) in requests)
      if (types.contains(request['@type']))
        (clientId, request['@type'] as String, request['chat_id'] as int?),
  ];

  void switchToBeta() => client.setActive(betaSlot);

  void removeAlpha() {
    // `removeSlot` refuses the active slot, so a switch must come first.
    client.removeSlot(alphaSlot);
  }
}

Future<_Registry> _startRegistry(_Respond respond) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  final supportDir = Directory.systemTemp.createTempSync('mithka_notif_owner');
  addTearDown(() {
    if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
  });

  final client = TdClient.forTesting();
  final bindings = _FakeBindings(client);
  final registry = _Registry(client, bindings, supportDir);
  client.prepareForTesting(
    prefs: prefs,
    supportDir: supportDir.path,
    bindings: bindings,
    queryOverride: (request, clientId) async {
      registry.requests.add((clientId, Map<String, dynamic>.from(request)));
      return respond(request, clientId);
    },
  );
  // `addSlot` uses the fake allocator: 100 for the first account, 101 for the
  // second. Both stay registered; only the foreground moves.
  registry.alphaSlot = client.addSlot();
  registry.betaSlot = client.addSlot();
  client.setActive(registry.alphaSlot);
  return registry;
}

/// Per-account answers for the exception list and its detail rows.
_Respond _exceptionResponder({Completer<void>? holdList}) {
  return (request, clientId) async {
    switch (request['@type']) {
      case 'getChatNotificationSettingsExceptions':
        if (holdList != null && clientId == _alphaClientId) {
          await holdList.future;
        }
        return _chats(const [_chatId]);
      case 'getChat':
        return clientId == _alphaClientId ? _alphaChat() : _betaChat();
      case 'setChatNotificationSettings':
        return const {'@type': 'ok'};
    }
    return const {'@type': 'ok'};
  };
}

Future<void> _pumpSheet(
  WidgetTester tester, {
  required NotificationExceptionAccounts accounts,
  Future<void> Function(int chatId, String title)? onOpenChat,
  Future<void> Function()? onExceptionsChanged,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.light,
        extensions: [AppColors.light],
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const ValueKey('open-notification-exceptions'),
              onPressed: () => showNotificationExceptionsSheet(
                context: context,
                scope: _privateScope,
                title: 'Private chats',
                scopeSettings: _scopeSettings(),
                accounts: accounts,
                onOpenChat: onOpenChat,
                onExceptionsChanged: onExceptionsChanged,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-notification-exceptions')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await _settle(tester);
}

/// Pumps the reverse animation after a stale owner closed the sheet.
Future<void> _pumpClosed(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await _settle(tester);
}

void main() {
  testWidgets('stale completion never pops a different route above the sheet', (
    tester,
  ) async {
    final holdList = Completer<void>();
    final registry = await _startRegistry(
      _exceptionResponder(holdList: holdList),
    );
    await _pumpSheet(tester, accounts: registry.accounts);
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('New account settings')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    registry.switchToBeta();
    holdList.complete();
    await _pumpClosed(tester);
    expect(find.text('New account settings'), findsOneWidget);
    expect(
      find.byType(NotificationExceptionsSheet, skipOffstage: false),
      findsNothing,
    );
  });
  testWidgets(
    'a pending list result from the old owner never reaches the new foreground',
    (tester) async {
      final holdList = Completer<void>();
      final registry = await _startRegistry(
        _exceptionResponder(holdList: holdList),
      );
      var refreshes = 0;

      await _pumpSheet(
        tester,
        accounts: registry.accounts,
        onExceptionsChanged: () async => refreshes++,
      );

      expect(registry.tuples(const ['getChatNotificationSettingsExceptions']), [
        (_alphaClientId, 'getChatNotificationSettingsExceptions', null),
      ]);
      expect(
        find.byKey(const ValueKey('notification-exceptions-loading')),
        findsOneWidget,
      );

      registry.switchToBeta();
      holdList.complete();
      await _pumpClosed(tester);

      expect(
        find.byKey(const ValueKey('notification-exceptions-sheet')),
        findsNothing,
      );
      expect(find.text('Alpha'), findsNothing);
      expect(find.text('Beta'), findsNothing);
      // The new foreground never served a request and the stale list never
      // reached the parent's count refresh.
      expect(
        registry.requests.where((entry) => entry.$1 == _betaClientId),
        isEmpty,
      );
      expect(refreshes, 0);
    },
  );

  testWidgets(
    'resetting an already-loaded row after a switch sends nothing to either account',
    (tester) async {
      final registry = await _startRegistry(_exceptionResponder());
      var refreshes = 0;

      await _pumpSheet(
        tester,
        accounts: registry.accounts,
        onExceptionsChanged: () async => refreshes++,
      );
      expect(find.text('Alpha'), findsOneWidget);

      registry.switchToBeta();
      await tester.tap(
        find.byKey(const ValueKey('notification-exception-reset-$_chatId')),
      );
      await _pumpClosed(tester);

      expect(registry.tuples(const ['setChatNotificationSettings']), isEmpty);
      expect(
        find.byKey(const ValueKey('notification-exceptions-sheet')),
        findsNothing,
      );
      expect(refreshes, 0);
    },
  );

  testWidgets(
    'removing the owning account mid-flight closes the sheet without a crash',
    (tester) async {
      final holdList = Completer<void>();
      final registry = await _startRegistry(
        _exceptionResponder(holdList: holdList),
      );
      var refreshes = 0;

      await _pumpSheet(
        tester,
        accounts: registry.accounts,
        onExceptionsChanged: () async => refreshes++,
      );
      expect(registry.tuples(const ['getChatNotificationSettingsExceptions']), [
        (_alphaClientId, 'getChatNotificationSettingsExceptions', null),
      ]);

      registry.switchToBeta();
      registry.removeAlpha();
      holdList.complete();
      await _pumpClosed(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('notification-exceptions-sheet')),
        findsNothing,
      );
      expect(
        registry.requests.where((entry) => entry.$1 == _betaClientId),
        isEmpty,
      );
      expect(refreshes, 0);
    },
  );

  testWidgets('disposing the sheet mid-flight drops the late result safely', (
    tester,
  ) async {
    final holdList = Completer<void>();
    final registry = await _startRegistry(
      _exceptionResponder(holdList: holdList),
    );

    await _pumpSheet(tester, accounts: registry.accounts);

    // Tear the whole tree down while the list response is still held.
    await tester.pumpWidget(const SizedBox.shrink());
    holdList.complete();
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(
      registry.tuples(const ['getChat']),
      isEmpty,
      reason: 'a disposed sheet must not resolve rows',
    );
  });
}

Map<String, dynamic> _scopeSettings() => {
  '@type': 'scopeNotificationSettings',
  'mute_for': 0,
  'sound_id': 0,
  'show_preview': true,
  'use_default_mute_stories': true,
  'mute_stories': false,
  'story_sound_id': 0,
  'show_story_poster': true,
  'disable_pinned_message_notifications': false,
  'disable_mention_notifications': false,
};

Map<String, dynamic> _chats(List<int> chatIds) => {
  '@type': 'chats',
  'total_count': chatIds.length,
  'chat_ids': chatIds,
};

/// Account 100's chat 42: muted, titled Alpha.
Map<String, dynamic> _alphaChat() =>
    _chat('Alpha', {'use_default_mute_for': false, 'mute_for': 2147483647});

/// Account 101's chat 42: sound off, titled Beta.
Map<String, dynamic> _betaChat() => _chat('Beta', {
  'use_default_sound': false,
  'sound_id': 0,
  'use_default_show_preview': false,
  'show_preview': false,
});

Map<String, dynamic> _chat(
  String title,
  Map<String, dynamic> notificationSettings,
) => {
  '@type': 'chat',
  'id': _chatId,
  'title': title,
  'photo': null,
  'notification_settings': {
    '@type': 'chatNotificationSettings',
    'use_default_mute_for': true,
    'mute_for': 0,
    'use_default_sound': true,
    'sound_id': 0,
    'use_default_show_preview': true,
    'show_preview': true,
    'use_default_mute_stories': true,
    'mute_stories': false,
    'use_default_story_sound': true,
    'story_sound_id': 0,
    'use_default_show_story_poster': true,
    'show_story_poster': true,
    'use_default_disable_pinned_message_notifications': true,
    'disable_pinned_message_notifications': false,
    'use_default_disable_mention_notifications': true,
    'disable_mention_notifications': false,
    ...notificationSettings,
  },
};

/// Pumps a few frames so sequential scope reads finish without waiting on the
/// loading indicator's endless animation.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
