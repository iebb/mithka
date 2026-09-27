import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/content_view.dart';
import 'package:mithka/auth/account_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final cached = AccountSummary(
    slot: 2,
    userId: 4242,
    name: 'Natu',
    phone: '+372 5555 5555',
    avatarPath: '/tmp/avatar.jpg',
    emojiStatusId: 77,
    isPremium: true,
    isBotApi: true,
    botApiEndpoint: Uri.parse('https://api.example.test'),
  );

  test('summaries round-trip through JSON', () {
    final restored = AccountSummary.fromJson(
      jsonDecode(jsonEncode(cached.toJson())),
    )!;
    expect(restored.slot, 2);
    expect(restored.userId, 4242);
    expect(restored.name, 'Natu');
    expect(restored.phone, '+372 5555 5555');
    expect(restored.avatarPath, '/tmp/avatar.jpg');
    expect(restored.emojiStatusId, 77);
    expect(restored.isPremium, isTrue);
    expect(restored.isBotApi, isTrue);
    expect(restored.botApiEndpoint, Uri.parse('https://api.example.test'));
  });

  test('the cached identity is known before any getMe', () async {
    SharedPreferences.setMockInitialValues({
      'drachma.activeSlot': 2,
      'drachma.accountSummaries': jsonEncode([cached.toJson()]),
    });
    final store = AccountStore(await SharedPreferences.getInstance());

    expect(store.summaries.single.name, 'Natu');
    expect(store.activeUserId, 4242);
    // Premium-only menu entries are decided from this before getMe answers.
    expect(store.activeIsPremium, isTrue);
    // The primary window is keyed on this identity; knowing it up front is
    // what keeps the window from remounting when getMe lands.
    expect(
      desktopPrimaryWindowIdentityKey(store.activeSlot, store.activeUserId),
      desktopPrimaryWindowIdentityKey(2, 4242),
    );
  });

  test('a missing or corrupt cache starts empty', () async {
    SharedPreferences.setMockInitialValues({
      'drachma.accountSummaries': '{not json',
    });
    expect(AccountStore(await SharedPreferences.getInstance()).summaries, []);

    SharedPreferences.setMockInitialValues({
      'drachma.accountSummaries': jsonEncode([
        {'slot': 'x'},
        {'slot': 1, 'userId': 5, 'name': ''},
      ]),
    });
    expect(AccountStore(await SharedPreferences.getInstance()).summaries, []);
  });
}
