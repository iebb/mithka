import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/message_action_menu.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/hidden_sender_store.dart';
import 'package:mithka/settings/hidden_senders_view.dart';
import 'package:mithka/settings/keyword_blocker.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

const _group = -1001;
const _otherGroup = -1002;

HiddenSender _entry(int sender, {int? chatId, String name = 'Mallory'}) =>
    HiddenSender(
      senderId: sender,
      name: name,
      chatId: chatId,
      chatTitle: chatId == null ? null : 'Group $chatId',
      hiddenAt: 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixtures = L10nFixtures.load();

  setUp(() async {
    fixtures.install();
    AppStrings.setLocale(const Locale('en'));
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    KeywordBlocker.shared.initialize(prefs);
    HiddenSenderStore.shared.initialize(prefs);
  });

  group('store', () {
    test('a group entry hides only in that group', () {
      final store = HiddenSenderStore.shared..hide(_entry(7, chatId: _group));
      expect(store.hides(7, _group), isTrue);
      expect(store.hides(7, _otherGroup), isFalse);
      expect(store.hides(8, _group), isFalse);
      expect(store.hides(null, _group), isFalse);
    });

    test('an everywhere entry hides in every chat and absorbs group ones', () {
      final store = HiddenSenderStore.shared
        ..hide(_entry(7, chatId: _group))
        ..hide(_entry(7, chatId: _otherGroup))
        ..hide(_entry(9, chatId: _group))
        ..hide(_entry(7));
      expect(store.hides(7, 12345), isTrue);
      expect(store.entries.map((e) => (e.senderId, e.chatId)), [
        (7, null),
        (9, _group),
      ]);
      expect(store.entriesFor(_otherGroup).map((e) => e.senderId), [7]);
    });

    test('hiding the same scope twice keeps one entry, newest first', () {
      final store = HiddenSenderStore.shared
        ..hide(_entry(7, chatId: _group, name: 'Old'))
        ..hide(_entry(8, chatId: _group))
        ..hide(_entry(7, chatId: _group, name: 'New'));
      expect(store.entries.map((e) => e.name), ['New', 'Mallory']);
    });

    test('entries persist across a reload and unhide removes them', () async {
      HiddenSenderStore.shared
        ..hide(_entry(7, chatId: _group))
        ..hide(_entry(-555));
      final reloaded = HiddenSenderStore.forTesting()
        ..initialize(await SharedPreferences.getInstance());
      expect(reloaded.hides(7, _group), isTrue);
      expect(reloaded.hides(-555, _otherGroup), isTrue, reason: 'chat sender');
      expect(reloaded.entries.first.chatTitle, isNull);

      reloaded.unhide(reloaded.entries.first);
      expect(reloaded.hides(-555, _otherGroup), isFalse);
      expect(reloaded.hides(7, _group), isTrue);
    });
  });

  test('hidden members leave the transcript and come back when shown', () {
    ChatMessage message(int id, int sender) => ChatMessage(
      id: id,
      chatId: _group,
      isOutgoing: false,
      text: 'message $id',
      date: id,
      senderId: sender,
    );
    final vm = ChatViewModel(
      chatId: _group,
      title: 'Group',
      markReadOnOpen: false,
      sessionMessages: [message(1, 7), message(2, 8), message(3, 7)],
    );
    addTearDown(vm.dispose);
    vm.onAppear();
    expect(vm.messages.map((m) => m.id), [1, 2, 3]);

    final entry = _entry(7, chatId: _group);
    HiddenSenderStore.shared.hide(entry);
    expect(vm.messages.map((m) => m.id), [2]);

    HiddenSenderStore.shared.hide(_entry(8, chatId: _otherGroup));
    expect(vm.messages.map((m) => m.id), [2], reason: 'other group only');

    HiddenSenderStore.shared.unhide(entry);
    expect(vm.messages.map((m) => m.id), [1, 2, 3]);
  });

  testWidgets('the menu offers Hide sender only when allowed', (tester) async {
    final translation = TranslationController(
      await SharedPreferences.getInstance(),
    );
    addTearDown(translation.dispose);
    MessageAction? selected;
    Future<void> pump({required bool allow}) => tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          home: Scaffold(
            body: MessageActionMenu(
              message: ChatMessage(
                id: 1,
                isOutgoing: false,
                text: 'hi',
                date: 1,
                senderId: 7,
                contentType: 'messageText',
              ),
              isPinned: false,
              allowHideSender: allow,
              onSelect: (action) => selected = action,
            ),
          ),
        ),
      ),
    );
    final hide = find.byKey(const ValueKey('message-action-hideSender'));
    await pump(allow: false);
    expect(hide, findsNothing);
    await pump(allow: true);
    expect(hide, findsOneWidget);
    await tester.tap(hide);
    expect(selected, MessageAction.hideSender);
  });

  testWidgets('the Hidden Members page lists scopes and shows again', (
    tester,
  ) async {
    HiddenSenderStore.shared
      ..hide(_entry(7, chatId: _group))
      ..hide(_entry(9, name: 'Eve'))
      ..hide(_entry(8, chatId: _otherGroup, name: 'Trent'));
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    Future<void> pump({int? chatId}) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: HiddenSendersView(chatId: chatId),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump();
    expect(find.text('Mallory'), findsOneWidget);
    expect(find.text('Group $_group'), findsOneWidget);
    expect(find.text('All chats'), findsOneWidget);
    expect(find.text('Trent'), findsOneWidget);

    // From a group's info: its own entries plus the every-chat ones.
    await pump(chatId: _group);
    expect(find.text('Mallory'), findsOneWidget);
    expect(find.text('Eve'), findsOneWidget);
    expect(find.text('Trent'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('hidden-sender-show-7-$_group')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mallory'), findsNothing);
    expect(HiddenSenderStore.shared.hides(7, _group), isFalse);
    await tester.pump(const Duration(seconds: 2));
  });
}
