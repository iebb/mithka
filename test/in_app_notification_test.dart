import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/notifications/in_app_notification_banner.dart';
import 'package:mithka/notifications/notification_controller.dart';
import 'package:mithka/notifications/notification_target.dart';
import 'package:mithka/notifications/scope_notification_settings.dart';
import 'package:mithka/tdlib/chat_membership.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  test('foreground messages use only the in-app surface', () {
    expect(
      notificationSurfaceFor(
        lifecycleState: AppLifecycleState.resumed,
        inAppBannersEnabled: true,
        systemNotificationsAvailable: true,
      ),
      NotificationSurface.inApp,
    );
    expect(
      notificationSurfaceFor(
        lifecycleState: AppLifecycleState.resumed,
        inAppBannersEnabled: false,
        systemNotificationsAvailable: true,
      ),
      NotificationSurface.none,
    );
  });

  test('background messages keep using the system notification surface', () {
    expect(
      notificationSurfaceFor(
        lifecycleState: AppLifecycleState.paused,
        inAppBannersEnabled: true,
        systemNotificationsAvailable: true,
      ),
      NotificationSurface.system,
    );
    expect(
      notificationSurfaceFor(
        lifecycleState: AppLifecycleState.hidden,
        inAppBannersEnabled: true,
        systemNotificationsAvailable: false,
      ),
      NotificationSurface.none,
    );
  });

  test('banner identity keeps the exact chat and message target', () {
    const target = NotificationTarget(chatId: 42, messageId: 9001);
    const banner = InAppNotificationBannerData(
      target: target,
      title: 'Chat',
      body: 'Message',
      photo: null,
      squarePhoto: false,
    );

    expect(banner.key, '42:9001');
    expect(banner.target.chatId, 42);
    expect(banner.target.messageId, 9001);
  });

  test('scope preview setting hides text unless a chat overrides it', () {
    final settings = ScopeNotificationSettings.shared;
    const privateScope = 'notificationSettingsScopePrivateChats';
    settings.updateShowPreview(privateScope, false);
    addTearDown(() => settings.updateShowPreview(privateScope, true));

    final inherited = <String, dynamic>{
      '@type': 'chat',
      'type': {'@type': 'chatTypePrivate', 'user_id': 7},
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'use_default_show_preview': true,
      },
    };
    final overridden = <String, dynamic>{
      ...inherited,
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'use_default_show_preview': false,
        'show_preview': true,
      },
    };

    expect(settings.showPreview(inherited), isFalse);
    expect(settings.showPreview(overridden), isTrue);
  });

  test('chat and inherited scope mute settings suppress notifications', () {
    final settings = ScopeNotificationSettings.shared;
    const groupScope = 'notificationSettingsScopeGroupChats';
    settings.update(groupScope, 2147483647);
    addTearDown(() => settings.update(groupScope, 0));

    final inherited = <String, dynamic>{
      '@type': 'chat',
      'type': {'@type': 'chatTypeBasicGroup', 'basic_group_id': 7},
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'use_default_mute_for': true,
      },
    };
    final chatMuted = <String, dynamic>{
      ...inherited,
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'use_default_mute_for': false,
        'mute_for': 2147483647,
      },
    };

    expect(settings.isMuted(inherited), isTrue);
    expect(settings.isMuted(chatMuted), isTrue);
  });

  test('left, banned, and non-member restricted chats are not joined', () {
    expect(isJoinedMemberStatus({'@type': 'chatMemberStatusLeft'}), isFalse);
    expect(isJoinedMemberStatus({'@type': 'chatMemberStatusBanned'}), isFalse);
    expect(
      isJoinedMemberStatus({
        '@type': 'chatMemberStatusRestricted',
        'is_member': false,
      }),
      isFalse,
    );
  });

  test('fresh mute updates override a stale chat snapshot', () {
    final controller = NotificationController.shared;
    final staleChat = <String, dynamic>{
      '@type': 'chat',
      'id': 73,
      'type': {
        '@type': 'chatTypeSupergroup',
        'supergroup_id': 730,
        'is_channel': true,
      },
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'use_default_mute_for': false,
        'mute_for': 0,
      },
    };

    controller.applyChatNotificationSettingsUpdateForTesting({
      '@type': 'updateChatNotificationSettings',
      'chat_id': 73,
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'use_default_mute_for': false,
        'mute_for': 2147483647,
      },
    });
    expect(controller.isChatMutedForTesting(staleChat), isTrue);

    controller.applyChatNotificationSettingsUpdateForTesting({
      '@type': 'updateChatNotificationSettings',
      'chat_id': 73,
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'use_default_mute_for': false,
        'mute_for': 0,
      },
    });
    expect(controller.isChatMutedForTesting(staleChat), isFalse);
  });

  test('muting a chat dismisses its visible in-app banner', () {
    final controller = NotificationController.shared;
    addTearDown(controller.dismissInAppBanner);
    controller.presentInAppBannerForTesting(
      const InAppNotificationBannerData(
        target: NotificationTarget(chatId: 42, messageId: 9001),
        title: 'Muted chat',
        body: 'Message',
        photo: null,
        squarePhoto: true,
      ),
    );

    controller.applyChatNotificationSettingsUpdateForTesting({
      '@type': 'updateChatNotificationSettings',
      'chat_id': 42,
      'notification_settings': {
        '@type': 'chatNotificationSettings',
        'use_default_mute_for': false,
        'mute_for': 2147483647,
      },
    });

    expect(controller.inAppBanner, isNull);
  });

  testWidgets('banner opens the exact message and supports swipe dismissal', (
    tester,
  ) async {
    final controller = NotificationController.shared;
    addTearDown(controller.dismissInAppBanner);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          padding: EdgeInsets.only(top: 47),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: ThemeData(extensions: [AppColors.light]),
            child: SizedBox.expand(
              child: InAppNotificationBannerHost(controller: controller),
            ),
          ),
        ),
      ),
    );

    const first = InAppNotificationBannerData(
      target: NotificationTarget(chatId: 88, messageId: 1234, title: 'Alice'),
      title: 'Alice',
      body: 'Hello from the banner',
      photo: null,
      squarePhoto: false,
    );
    controller.presentInAppBannerForTesting(first);
    await tester.pumpAndSettle();
    expect(find.text('Hello from the banner'), findsOneWidget);

    await tester.tap(find.text('Hello from the banner'));
    await tester.pumpAndSettle();
    final request = ChatDeepLinkController.shared.consumePending();
    expect(request?.chatId, 88);
    expect(request?.messageId, 1234);

    controller.presentInAppBannerForTesting(first);
    await tester.pumpAndSettle();
    await tester.drag(find.text('Hello from the banner'), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(controller.inAppBanner, isNull);
  });
}
