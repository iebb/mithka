import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_delete_dialog.dart';
import 'package:mithka/chats/chat_delete_policy.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/messages/de.dart';
import 'package:mithka/l10n/messages/en.dart';
import 'package:mithka/l10n/messages/es.dart';
import 'package:mithka/l10n/messages/fr.dart';
import 'package:mithka/l10n/messages/ja.dart';
import 'package:mithka/l10n/messages/ko.dart';
import 'package:mithka/l10n/messages/zh_hans.dart';
import 'package:mithka/l10n/messages/zh_hant.dart';
import 'package:mithka/tdlib/td_models.dart';

void main() {
  test('reads Telegram chat deletion capabilities', () {
    expect(
      chatDeleteCapabilities({
        'can_be_deleted_only_for_self': true,
        'can_be_deleted_for_all_users': true,
      }).canDeleteForAllUsers,
      isTrue,
    );
    expect(
      chatDeleteCapabilities(const {}).canDeleteForSelf,
      isTrue,
      reason: 'older TDLib responses retain the safe local-only action',
    );
  });

  test('builds the correct revoke request and leave policy', () {
    expect(
      deleteChatHistoryRequest(chatId: 7, scope: ChatDeleteScope.self),
      containsPair('revoke', false),
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
  });

  test('delete scope copy exists in every supported locale', () {
    const tables = [
      enMessages,
      deMessages,
      esMessages,
      frMessages,
      jaMessages,
      koMessages,
      zhHansMessages,
      zhHantMessages,
    ];
    const keys = [
      'chatDeleteAllMembersDescription',
      'chatDeleteBothSidesDescription',
      'chatDeleteForAllMembers',
      'chatDeleteForBothSides',
      'chatDeleteForMe',
      'chatDeleteScopeGroupDescription',
      'chatDeleteScopePrivateDescription',
      'chatDeleteUnavailable',
    ];
    for (final table in tables) {
      for (final key in keys) {
        expect(table[key]?.trim(), isNotEmpty, reason: 'missing $key');
      }
    }
  });

  testWidgets('private chat asks between me and both sides', (tester) async {
    ChatDeleteScope? selected;
    await tester.pumpWidget(
      _dialogApp(
        onPressed: () async {
          selected = await showChatDeleteScopeDialog(
            tester.element(find.byType(FilledButton)),
            capabilities: const ChatDeleteCapabilities(
              canDeleteForSelf: true,
              canDeleteForAllUsers: true,
            ),
            isGroupOrChannel: false,
            title: AppStringKeys.chatListDeleteChatQuestion,
            selfOnlyDescription: AppStringKeys.chatInfoClearHistoryDescription,
          );
        },
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Delete for both sides'), findsOneWidget);

    await tester.tap(find.text('Delete for both sides'));
    await tester.pumpAndSettle();
    expect(selected, ChatDeleteScope.allUsers);
  });

  testWidgets('group chat labels revoke as delete for all members', (
    tester,
  ) async {
    await tester.pumpWidget(
      _dialogApp(
        onPressed: () => showChatDeleteScopeDialog(
          tester.element(find.byType(FilledButton)),
          capabilities: const ChatDeleteCapabilities(
            canDeleteForSelf: true,
            canDeleteForAllUsers: true,
          ),
          isGroupOrChannel: true,
          title: AppStringKeys.chatListDeleteChatQuestion,
          selfOnlyDescription: AppStringKeys.chatInfoClearHistoryDescription,
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Delete for all members'), findsOneWidget);
    expect(
      find.text(
        'Choose whether to delete this chat only for you or for all members.',
      ),
      findsOneWidget,
    );
  });
}

Widget _dialogApp({required VoidCallback onPressed}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [AppLocalizations.delegate],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: onPressed,
          child: const Text('Delete chat'),
        ),
      ),
    ),
  );
}
