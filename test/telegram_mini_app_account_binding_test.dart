import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_mini_app_recents.dart';
import 'package:mithka/chat/telegram_mini_app_view.dart';

void main() {
  test(
    'deferred A launch is rejected after the active account becomes B',
    () async {
      const accountA = TelegramMiniAppAccountScope(
        slot: 0,
        clientId: 11,
        userId: 101,
      );
      var active = accountA;
      final resolution = Completer<String?>();
      int? routedClientId;
      var rejected = 0;

      final pending = resolveTelegramMiniAppForPinnedAccount<String>(
        account: accountA,
        resolve: (clientId) {
          routedClientId = clientId;
          return resolution.future;
        },
        isCurrent: (captured) async => captured.matches(
          currentSlot: active.slot,
          currentClientId: active.clientId,
          currentUserId: active.userId,
        ),
        onRejected: (_) => rejected += 1,
      );

      active = const TelegramMiniAppAccountScope(
        slot: 0,
        clientId: 12,
        userId: 202,
      );
      resolution.complete('account-A-signed-url');

      expect(await pending, isNull);
      expect(routedClientId, accountA.clientId);
      expect(rejected, 1);
    },
  );

  test(
    'resolved launch is cleaned up when presentation is unavailable',
    () async {
      var presented = 0;
      var cleaned = 0;

      final unmounted = await presentResolvedTelegramMiniAppLaunch(
        isContextMounted: () => false,
        present: () async => presented += 1,
        cleanup: () async => cleaned += 1,
      );
      final failed = await presentResolvedTelegramMiniAppLaunch(
        isContextMounted: () => true,
        present: () async => throw StateError('No Navigator'),
        cleanup: () async => cleaned += 1,
      );

      expect(unmounted, isFalse);
      expect(failed, isFalse);
      expect(presented, 0);
      expect(cleaned, 2);
    },
  );
}
