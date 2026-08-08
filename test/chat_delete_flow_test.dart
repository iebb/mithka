import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_delete_dialog.dart';
import 'package:mithka/chats/chat_delete_policy.dart';
import 'package:mithka/components/app_confirm_dialog.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';

import 'support/l10n_fixtures.dart';

final fixtures = L10nFixtures.load();

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

  test('delete scope copy exists in every supported locale', () {
    final tables = [
      fixtures.messages('en'),
      fixtures.messages('de'),
      fixtures.messages('es'),
      fixtures.messages('fr'),
      fixtures.messages('ja'),
      fixtures.messages('ko'),
      fixtures.messages('zhHans'),
      fixtures.messages('zhHant'),
    ];
    const keys = [
      'chatDeleteAllMembersDescription',
      'chatDeleteBothSidesDescription',
      'chatDeleteFinalQuestion',
      'chatDeleteFinalWarning',
      'chatDeleteForAllMembers',
      'chatDeleteForBothSides',
      'chatDeleteForMe',
      'chatDeleteForMeDescription',
      'chatDeleteScopeGroupDescription',
      'chatDeleteScopePrivateDescription',
      'chatDeleteUnavailable',
      'chatInfoClearHistoryFinalQuestion',
      'chatLeaveAndDeleteDescription',
      'savedMessagesClear',
      'savedMessagesClearDescription',
      'savedMessagesClearFinalQuestion',
      'savedMessagesClearQuestion',
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

  testWidgets('Saved Messages uses two dedicated clear confirmations', (
    tester,
  ) async {
    ChatDeleteScope? selected;
    await tester.pumpWidget(
      _dialogApp(
        onPressed: () async {
          selected = await showTwoStepChatDeleteDialog(
            tester.element(find.byType(FilledButton)),
            capabilities: const ChatDeleteCapabilities.selfOnly(),
            isGroupOrChannel: false,
            isSavedMessages: true,
            chatTitle: 'Saved Messages',
            title: AppStringKeys.chatListDeleteChatQuestion,
            selfOnlyDescription: AppStringKeys.chatInfoClearHistoryDescription,
          );
        },
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(
      find.text(
        AppStrings.tForLocale('en', AppStringKeys.savedMessagesClearQuestion),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-delete-scope-self')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('app-confirm-accept')));
    await tester.pumpAndSettle();

    expect(selected, isNull);
    expect(
      find.text(
        AppStrings.tForLocale(
          'en',
          AppStringKeys.savedMessagesClearFinalQuestion,
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('app-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(selected, isNull);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-confirm-accept')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-confirm-accept')));
    await tester.pumpAndSettle();
    expect(selected, ChatDeleteScope.self);
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

  testWidgets('owned scope dialog supports narrow large text', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _dialogApp(
        textScaler: const TextScaler.linear(2),
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
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('chat-delete-scope-all')), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('chat-delete-scope-all')))
          .height,
      greaterThanOrEqualTo(52),
    );
  });

  testWidgets('owned confirmation stacks full labels on narrow large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _dialogApp(
        textScaler: const TextScaler.linear(2),
        onPressed: () => showAppConfirmDialog(
          tester.element(find.byType(FilledButton)),
          title: AppStringKeys.savedMessagesClearFinalQuestion,
          message: AppStringKeys.chatDeleteFinalWarning,
          confirmText: fixtures.messages(
            'de',
          )[AppStringKeys.savedMessagesClear]!,
          destructive: true,
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final label = fixtures.messages('de')[AppStringKeys.savedMessagesClear]!;
    final labelFinder = find.text(label);
    final acceptFinder = find.byKey(const ValueKey('app-confirm-accept'));
    final cancelFinder = find.byKey(const ValueKey('app-confirm-cancel'));
    expect(tester.takeException(), isNull);
    expect(labelFinder, findsOneWidget);
    expect(tester.widget<Text>(labelFinder).maxLines, isNull);
    expect(
      tester.getSize(acceptFinder).width,
      tester.getSize(cancelFinder).width,
    );
    expect(
      tester.getTopLeft(acceptFinder).dy,
      lessThan(tester.getTopLeft(cancelFinder).dy),
    );
  });

  testWidgets('owned confirmation defaults focus to cancel and supports keys', (
    tester,
  ) async {
    bool? confirmed;
    await tester.pumpWidget(
      _dialogApp(
        onPressed: () async {
          confirmed = await showAppConfirmDialog(
            tester.element(find.byType(FilledButton)),
            title: 'Delete chat?',
            message: 'This action cannot be undone.',
            confirmText: 'Delete',
            destructive: true,
          );
        },
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    confirmed = null;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);

    confirmed = null;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
  });

  testWidgets('owned confirmation can host a visual preview', (tester) async {
    await tester.pumpWidget(
      _dialogApp(
        onPressed: () => showAppConfirmDialog(
          tester.element(find.byType(FilledButton)),
          title: 'Appearance',
          message: 'Background name',
          content: const SizedBox(
            key: ValueKey('confirmation-visual-preview'),
            width: 240,
            height: 120,
          ),
          confirmText: 'Apply',
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('confirmation-visual-preview')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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
