import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/notifications/notification_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'legacy all-account toggle migrates to the current-account mode',
    () async {
      SharedPreferences.setMockInitialValues({
        'mithka.notifications.allAccounts.v1': false,
      });
      final preferences = await SharedPreferences.getInstance();
      final settings = NotificationPreferences.shared;
      settings.initialize(preferences);

      expect(settings.accountMode, NotificationAccountMode.current);
      expect(
        settings.receivesNotificationsFrom(userId: 1, isActiveAccount: true),
        isTrue,
      );
      expect(
        settings.receivesNotificationsFrom(userId: 2, isActiveAccount: false),
        isFalse,
      );
    },
  );

  test('removing the last selected account falls back to current', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = NotificationPreferences.shared;
    settings.initialize(preferences);
    await settings.setAccountMode(
      NotificationAccountMode.selected,
      defaultSelectedAccountIds: const [55],
    );

    await settings.removeAccount(55);

    expect(settings.accountMode, NotificationAccountMode.current);
    expect(settings.selectedAccountIds, isEmpty);
  });
}
