import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';

/// A chat id is only meaningful inside the account that produced it, so these
/// cover the one thing that must never happen: a notification for one account
/// opening its chat id against a different one, which lands on an unrelated
/// conversation rather than failing visibly.
void main() {
  const accounts = <({int slot, int? userId})>[
    (slot: 0, userId: 111),
    (slot: 1, userId: 222),
  ];

  int? resolve({
    int? slot,
    int? userId,
    int active = 0,
    List<({int slot, int? userId})> signedIn = accounts,
  }) => resolveDeepLinkAccountSlot(
    requestedSlot: slot,
    requestedUserId: userId,
    activeSlot: active,
    accounts: signedIn,
  );

  test('an explicit slot is taken as given', () {
    expect(resolve(slot: 1), 1);
  });

  test('a user id resolves to the account signed in with it', () {
    expect(resolve(userId: 222), 1);
    expect(resolve(userId: 111), 0);
  });

  test('an account that is not signed in resolves to nothing', () {
    // Falling back to the active account would open account 333's chat id
    // inside account 111 — a different conversation with the same number.
    expect(resolve(userId: 333), isNull);
  });

  test('naming no account is ambiguous once there are several', () {
    expect(resolve(), isNull);
  });

  test('naming no account is unambiguous with a single one', () {
    expect(
      resolve(signedIn: const [(slot: 0, userId: 111)]),
      0,
      reason: 'the case that predates notifications carrying an identity',
    );
    expect(resolve(signedIn: const []), 0);
  });

  test('an explicit slot wins over a user id', () {
    expect(resolve(slot: 1, userId: 111), 1);
  });
}
