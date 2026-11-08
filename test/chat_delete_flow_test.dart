import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_delete_dialog.dart';
import 'package:mithka/chats/chat_delete_policy.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';

import 'support/l10n_fixtures.dart';

final fixtures = L10nFixtures.load();

void main() {
  test('builds the correct revoke request and leave policy', () {
    final selfRequest = deleteChatHistoryRequest(
      chatId: 7,
      scope: ChatDeleteScope.self,
    );
    expect(selfRequest, containsPair('revoke', false));
    expect(selfRequest, containsPair('remove_from_chat_list', true));
    expect(
      deleteChatHistoryRequest(
        chatId: 7,
        scope: ChatDeleteScope.self,
        removeFromChatList: false,
      ),
      containsPair('remove_from_chat_list', false),
    );
    expect(
      deleteChatHistoryRequest(chatId: 7, scope: ChatDeleteScope.allUsers),
      containsPair('revoke', true),
    );
    expect(
      shouldLeaveBeforeDeletingChat(ChatKind.group, ChatDeleteScope.self),
      isTrue,
    );
    expect(
      shouldLeaveBeforeDeletingChat(ChatKind.group, ChatDeleteScope.allUsers),
      isFalse,
    );
    expect(
      chatLeftLocalUpdate(7),
      equals({'@type': 'mithkaChatLeft', 'chat_id': 7}),
    );
  });

  testWidgets('chat deletion requires scope and final confirmation', (
    tester,
  ) async {
    ChatDeleteScope? selected;
    await tester.pumpWidget(
      _dialogApp(
        onPressed: () async {
          selected = await showTwoStepChatDeleteDialog(
            tester.element(find.byType(FilledButton)),
            capabilities: const ChatDeleteCapabilities(
              canDeleteForSelf: true,
              canDeleteForAllUsers: true,
            ),
            isGroupOrChannel: false,
            isSavedMessages: false,
            chatTitle: 'Taylor',
            title: AppStringKeys.chatListDeleteChatQuestion,
            selfOnlyDescription: AppStringKeys.chatInfoClearHistoryDescription,
          );
        },
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-delete-scope-all')));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(
      find.text(
        AppStrings.tForLocale('en', AppStringKeys.chatDeleteFinalQuestion, {
          'value1': 'Taylor',
        }),
      ),
      findsOneWidget,
    );
    expect(find.text('Delete for both sides'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(selected, isNull, reason: 'canceling step two must block deletion');

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-delete-scope-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-confirm-accept')));
    await tester.pumpAndSettle();
    expect(selected, ChatDeleteScope.allUsers);
  });

  testWidgets('clear history returns true only after both confirmations', (
    tester,
  ) async {
    bool? confirmed;
    await tester.pumpWidget(
      _dialogApp(
        onPressed: () async {
          confirmed = await showTwoStepClearHistoryDialog(
            tester.element(find.byType(FilledButton)),
            chatTitle: 'Morgan',
          );
        },
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    confirmed = null;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-confirm-accept')));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
    await tester.tap(find.byKey(const ValueKey('app-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    confirmed = null;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-confirm-accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-confirm-accept')));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}

Widget _dialogApp({
  required VoidCallback onPressed,
  TextScaler? textScaler,
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: onPressed,
              child: const Text('Delete chat'),
            ),
          ),
        ),
      ),
    ),
  );
}
