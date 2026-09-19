import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/audio_search_view.dart';
import 'package:mithka/tdlib/td_client.dart';

Map<String, dynamic> _audioMessage({
  required int chatId,
  required int messageId,
  String title = 'Track',
}) => {
  '@type': 'message',
  'id': messageId,
  'chat_id': chatId,
  'date': 1,
  'is_outgoing': true,
  'content': {
    '@type': 'messageAudio',
    'audio': {
      '@type': 'audio',
      'duration': 120,
      'title': title,
      'performer': 'Artist',
      'file_name': '$title.mp3',
      'audio': {'@type': 'file', 'id': messageId},
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pending = <String, Completer<Map<String, dynamic>>>{};
  late StreamController<Map<String, dynamic>> updates;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) {
          if (request['@type'] == 'searchMessages') {
            final query = request['query'] as String;
            return (pending[query] = Completer<Map<String, dynamic>>()).future;
          }
          return Future<Map<String, dynamic>>.value({
            '@type': 'chat',
            'id': 0,
            'title': 'Chat',
          });
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

  setUp(pending.clear);

  Future<void> pumpView(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AudioSearchView(selectOnly: true)),
    );
    await tester.pump();
  }

  Future<void> typeQuery(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField), query);
    // Let the debounce timer fire.
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('an older search cannot clear the spinner of a newer one', (
    tester,
  ) async {
    await pumpView(tester);

    await typeQuery(tester, 'alpha');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await typeQuery(tester, 'beta');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // The superseded search completes while the newer one is still pending:
    // the spinner must stay and no stale results may appear.
    pending['alpha']!.complete({
      '@type': 'foundMessages',
      'messages': [_audioMessage(chatId: 1, messageId: 11, title: 'Alpha')],
    });
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);

    pending['beta']!.complete({
      '@type': 'foundMessages',
      'messages': [_audioMessage(chatId: 2, messageId: 22, title: 'Beta')],
    });
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('clearing the query drops in-flight results', (tester) async {
    await pumpView(tester);

    await typeQuery(tester, 'alpha');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await typeQuery(tester, '');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    pending['alpha']!.complete({
      '@type': 'foundMessages',
      'messages': [_audioMessage(chatId: 1, messageId: 11, title: 'Alpha')],
    });
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('disposing the view mid-search never touches state', (
    tester,
  ) async {
    await pumpView(tester);

    await typeQuery(tester, 'alpha');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    pending['alpha']!.complete({
      '@type': 'foundMessages',
      'messages': [_audioMessage(chatId: 1, messageId: 11, title: 'Alpha')],
    });
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
