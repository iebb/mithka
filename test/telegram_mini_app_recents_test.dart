import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_mini_app_recents.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uses bot identity while preserving the recent launch title', () {
    const recent = TelegramMiniAppRecent(
      title: '小程序购买',
      url: 'menu://https://example.com/app',
      botUserId: 10,
      chatId: 20,
      updatedAt: 30,
    );
    final discovered = TelegramMiniAppRecent(
      title: 'Open',
      botTitle: 'USDT eSIM',
      url: 'menu://https://example.com/app',
      botUserId: 10,
      chatId: 20,
      updatedAt: 0,
      photo: TdFileRef(id: 42),
    );

    final merged = mergeTelegramMiniAppRecents([recent], [discovered]);

    expect(merged, hasLength(1));
    expect(merged.single.title, '小程序购买');
    expect(merged.single.displayTitle, 'USDT eSIM');
    expect(merged.single.photo?.id, 42);
  });

  test('keeps only the most recently stored app for each bot', () {
    TelegramMiniAppRecent recent(String title, String url) =>
        TelegramMiniAppRecent(
          title: title,
          url: url,
          botUserId: 10,
          chatId: 20,
          updatedAt: 30,
        );

    final merged = mergeTelegramMiniAppRecents([
      recent('Open', 'menu://https://example.com/new'),
      recent('小程序购买', 'https://example.com/old'),
    ], const []);

    expect(merged, hasLength(1));
    expect(merged.single.title, 'Open');
  });

  test(
    'stored recents stay isolated between Telegram user identities',
    () async {
      final accountAKey = TelegramMiniAppRecents.storageKeyForTesting(
        slot: 0,
        clientId: 11,
        userId: 101,
      );
      final accountBKey = TelegramMiniAppRecents.storageKeyForTesting(
        slot: 0,
        clientId: 22,
        userId: 202,
      );
      SharedPreferences.setMockInitialValues({
        accountAKey: jsonEncode([_storedApp('Account A app', 1010)]),
        accountBKey: jsonEncode([_storedApp('Account B app', 2020)]),
      });

      final accountA = await TelegramMiniAppRecents.loadStoredForTesting(
        slot: 0,
        clientId: 11,
        userId: 101,
      );
      final accountB = await TelegramMiniAppRecents.loadStoredForTesting(
        slot: 0,
        clientId: 22,
        userId: 202,
      );

      expect(accountA.map((app) => app.title), ['Account A app']);
      expect(accountB.map((app) => app.title), ['Account B app']);
    },
  );

  test('ownerless legacy recents are discarded instead of claimed', () async {
    final firstAccountKey = TelegramMiniAppRecents.storageKeyForTesting(
      slot: 0,
      clientId: 33,
      userId: 303,
    );
    SharedPreferences.setMockInitialValues({
      firstAccountKey: jsonEncode([_storedApp('Owned account app', 3031)]),
      'telegramMiniAppRecents.v1': jsonEncode([
        _storedApp('Unknown legacy owner', 3030),
      ]),
    });

    final firstAccount = await TelegramMiniAppRecents.loadStoredForTesting(
      slot: 0,
      clientId: 33,
      userId: 303,
    );
    final secondAccount = await TelegramMiniAppRecents.loadStoredForTesting(
      slot: 0,
      clientId: 44,
      userId: 404,
    );
    final prefs = await SharedPreferences.getInstance();

    expect(firstAccount.map((app) => app.title), ['Owned account app']);
    expect(secondAccount, isEmpty);
    expect(prefs.containsKey('telegramMiniAppRecents.v1'), isFalse);
  });

  test('temporary slot fallback is isolated by TD client lifetime', () async {
    final firstSessionKey = TelegramMiniAppRecents.storageKeyForTesting(
      slot: 0,
      clientId: 51,
    );
    final replacementSessionKey = TelegramMiniAppRecents.storageKeyForTesting(
      slot: 0,
      clientId: 52,
    );
    SharedPreferences.setMockInitialValues({
      firstSessionKey: jsonEncode([_storedApp('First session', 5050)]),
    });

    final firstSession = await TelegramMiniAppRecents.loadStoredForTesting(
      slot: 0,
      clientId: 51,
    );
    final replacementSession =
        await TelegramMiniAppRecents.loadStoredForTesting(
          slot: 0,
          clientId: 52,
        );

    expect(firstSession.map((app) => app.title), ['First session']);
    expect(replacementSession, isEmpty);
    expect(firstSessionKey, isNot(replacementSessionKey));
  });

  test('known user cache merges newer temporary slot recents', () async {
    final userKey = TelegramMiniAppRecents.storageKeyForTesting(
      slot: 0,
      clientId: 61,
      userId: 606,
    );
    final slotKey = TelegramMiniAppRecents.storageKeyForTesting(
      slot: 0,
      clientId: 61,
    );
    SharedPreferences.setMockInitialValues({
      userKey: jsonEncode([
        _storedApp('Existing user app', 6060, updatedAt: 20),
        _storedApp('Older copy', 7070, updatedAt: 10),
      ]),
      slotKey: jsonEncode([
        _storedApp('Temporary launch', 8080, updatedAt: 30),
        _storedApp('Newer copy', 7070, updatedAt: 40),
      ]),
    });

    final merged = await TelegramMiniAppRecents.loadStoredForTesting(
      slot: 0,
      clientId: 61,
      userId: 606,
    );
    final prefs = await SharedPreferences.getInstance();

    expect(merged.map((app) => app.title), [
      'Newer copy',
      'Temporary launch',
      'Existing user app',
    ]);
    expect(prefs.containsKey(slotKey), isFalse);
    expect(jsonDecode(prefs.getString(userKey)!) as List, hasLength(3));
  });

  test('concurrent records serialize without dropping either app', () async {
    SharedPreferences.setMockInitialValues({});
    final firstEntered = Completer<void>();
    final releaseFirst = Completer<void>();
    var secondEntered = false;

    final first = TelegramMiniAppRecents.recordStoredForTesting(
      slot: 0,
      clientId: 71,
      userId: 707,
      recent: _recent('First app', 7100, updatedAt: 10),
      onLockAcquired: () async {
        firstEntered.complete();
        await releaseFirst.future;
      },
    );
    await firstEntered.future;
    final second = TelegramMiniAppRecents.recordStoredForTesting(
      slot: 0,
      clientId: 71,
      userId: 707,
      recent: _recent('Second app', 7200, updatedAt: 20),
      onLockAcquired: () async {
        secondEntered = true;
      },
    );

    await Future<void>.delayed(Duration.zero);
    expect(secondEntered, isFalse);
    releaseFirst.complete();
    await Future.wait([first, second]);

    final stored = await TelegramMiniAppRecents.loadStoredForTesting(
      slot: 0,
      clientId: 71,
      userId: 707,
    );
    expect(stored.map((app) => app.title), ['Second app', 'First app']);
  });
}

TelegramMiniAppRecent _recent(
  String title,
  int botUserId, {
  required int updatedAt,
}) => TelegramMiniAppRecent(
  title: title,
  url: 'https://example.com/$botUserId',
  botUserId: botUserId,
  chatId: botUserId + 1,
  updatedAt: updatedAt,
);

Map<String, Object?> _storedApp(
  String title,
  int botUserId, {
  int? updatedAt,
}) => {
  'title': title,
  'url': 'https://example.com/$botUserId',
  'botUserId': botUserId,
  'chatId': botUserId + 1,
  'updatedAt': updatedAt ?? botUserId + 2,
};
