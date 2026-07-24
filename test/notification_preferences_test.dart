import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/notifications/notification_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'notification preferences use the requested defaults and persist',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = NotificationPreferences.shared;
      settings.initialize(preferences);

      expect(settings.allAccounts, isTrue);
      expect(settings.accountMode, NotificationAccountMode.all);
      expect(settings.selectedAccountIds, isEmpty);
      expect(settings.inAppSounds, isTrue);
      expect(settings.inAppVibrate, isFalse);
      expect(settings.inAppPreview, isTrue);
      expect(settings.namesOnLockScreen, isTrue);

      await settings.setAccountMode(
        NotificationAccountMode.selected,
        defaultSelectedAccountIds: const [101],
      );
      await settings.setSelectedAccountIds(const [101, 303]);
      await settings.setInAppSounds(false);
      await settings.setInAppVibrate(true);
      await settings.setInAppPreview(false);
      await settings.setNamesOnLockScreen(false);

      settings.initialize(preferences);
      expect(settings.allAccounts, isFalse);
      expect(settings.accountMode, NotificationAccountMode.selected);
      expect(settings.selectedAccountIds, {101, 303});
      expect(
        settings.receivesNotificationsFrom(userId: 101, isActiveAccount: false),
        isTrue,
      );
      expect(
        settings.receivesNotificationsFrom(userId: 202, isActiveAccount: true),
        isFalse,
      );
      expect(settings.inAppSounds, isFalse);
      expect(settings.inAppVibrate, isTrue);
      expect(settings.inAppPreview, isFalse);
      expect(settings.namesOnLockScreen, isFalse);
    },
  );

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

  test(
    'empty selected-account state falls back to current on launch',
    () async {
      SharedPreferences.setMockInitialValues({
        'mithka.notifications.accountMode.v2': 'selected',
        'mithka.notifications.selectedAccountIds.v2': <String>[],
      });
      final preferences = await SharedPreferences.getInstance();
      final settings = NotificationPreferences.shared;

      settings.initialize(preferences);

      expect(settings.accountMode, NotificationAccountMode.current);
    },
  );
}
