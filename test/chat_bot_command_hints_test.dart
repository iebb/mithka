import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/l10n/app_localizations.dart';

class _BotCommandTestViewModel extends ChatViewModel {
  _BotCommandTestViewModel()
    : super(chatId: 1, title: 'Group', markReadOnOpen: false);

  String? sentCommand;

  @override
  void sendTyping() {}

  @override
  void setDraft(
    String value, {
    String? formattedText,
    List<Map<String, dynamic>> entities = const [],
  }) {
    draft = value;
  }

  @override
  bool sendCommand(String command) {
    sentCommand = command;
    return true;
  }
}

void main() {
  group('group bot command data', () {
    test('parses a leading slash query and filters by prefix', () {
      expect(
        activeBotCommandQuery(
          '/He',
          const TextSelection.collapsed(offset: 3),
        )?.query,
        'He',
      );
      expect(
        activeBotCommandQuery(
          '/',
          const TextSelection.collapsed(offset: 1),
        )?.query,
        '',
      );
      expect(
        activeBotCommandQuery(
          ' /help',
          const TextSelection.collapsed(offset: 6),
        ),
        isNull,
      );
      expect(
        activeBotCommandQuery(
          '/help now',
          const TextSelection.collapsed(offset: 9),
        ),
        isNull,
      );
      expect(
        activeBotCommandQuery(
          '/help',
          const TextSelection.collapsed(offset: 3),
        ),
        isNull,
      );

      const commands = [
        BotCommandOption(command: 'help', description: 'Help'),
        BotCommandOption(command: 'start', description: 'Start'),
        BotCommandOption(command: 'hello_world', description: 'Hello'),
      ];
      expect(
        matchingBotCommands(
          commands,
          'HE',
        ).map((command) => command.normalizedCommand),
        ['help', 'hello_world'],
      );
    });

    test(
      'resolves group metadata without losing bot or command order',
      () async {
        final commands = await resolveGroupBotCommandOptions(
          {
            'bot_commands': [
              {
                'bot_user_id': 7,
                'commands': [
                  {'command': 'help', 'description': 'Help'},
                  {'command': 'start', 'description': 'Start'},
                ],
              },
              {
                'bot_user_id': 9,
                'commands': [
                  {'command': 'id', 'description': 'Account details'},
                ],
              },
            ],
          },
          (userId) async {
            return switch (userId) {
              7 => {
                'id': 7,
                'first_name': 'Helper',
                'last_name': 'Bot',
                'usernames': {
                  'active_usernames': ['helper_bot'],
                },
              },
              9 => {
                'id': 9,
                'first_name': 'Info Bot',
                'usernames': {'editable_username': '@info_bot'},
              },
              _ => null,
            };
          },
        );

        expect(commands.map((command) => command.displayCommand), [
          '/help',
          '/start',
          '/id',
        ]);
        expect(commands.map((command) => command.botUserId), [7, 7, 9]);
        expect(commands.first.botName, 'Helper Bot');
        expect(commands.first.targetedCommand, '/help@helper_bot');
        expect(commands.last.targetedCommand, '/id@info_bot');
      },
    );
  });

  testWidgets('group command rows send immediately while arrows insert', (
    tester,
  ) async {
    final vm = _BotCommandTestViewModel()
      ..isGroup = true
      ..botCommands = const [
        BotCommandOption(
          command: 'help',
          description: 'Help',
          botUserId: 7,
          botName: 'Helper Bot',
          botUsername: 'helper_bot',
        ),
        BotCommandOption(
          command: 'start',
          description: 'Start',
          botUserId: 7,
          botName: 'Helper Bot',
          botUsername: 'helper_bot',
        ),
      ];
    addTearDown(vm.dispose);
    var sentCount = 0;

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
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              vm: vm,
              onStartCall: (_) {},
              onMessageSent: () => sentCount++,
            ),
          ),
        ),
      ),
    );

    final field = find.byType(TextField).first;
    await tester.enterText(field, '/he');
    await tester.pump();

    expect(find.byKey(const ValueKey('groupBotCommandHints')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('groupBotCommand-7-help')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('groupBotCommand-7-start')), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('insertGroupBotCommand-7-help')),
    );
    await tester.pump();
    expect(tester.widget<TextField>(field).controller?.text, '/help ');
    expect(vm.sentCommand, isNull);
    expect(find.byKey(const ValueKey('groupBotCommandHints')), findsNothing);

    await tester.enterText(field, '/');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('groupBotCommand-7-start')));
    await tester.pump();

    expect(vm.sentCommand, '/start@helper_bot');
    expect(tester.widget<TextField>(field).controller?.text, '');
    expect(sentCount, 1);
  });
}
