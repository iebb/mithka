import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/chat_deep_link_controller.dart';
import 'package:mithka/chat/internal_chat_link_router.dart';

void main() {
  testWidgets('scope resolves the transcript that owns the tapped link', (
    tester,
  ) async {
    late BuildContext linkContext;
    final target = InternalChatLinkTarget(
      chatId: 42,
      openMessage: (_) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InternalChatLinkScope(
          target: target,
          child: Builder(
            builder: (context) {
              linkContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(InternalChatLinkScope.targetOf(linkContext), same(target));
  });

  test(
    'same-chat message links scroll without requesting another chat',
    () async {
      final controller = ChatDeepLinkController.shared;
      controller.consumePending();
      addTearDown(controller.consumePending);
      int? openedMessageId;

      final disposition = await routeResolvedInternalChatLink(
        chatId: 42,
        title: 'Current chat',
        messageId: 9001,
        source: InternalChatLinkTarget(
          chatId: 42,
          openMessage: (messageId) async => openedMessageId = messageId,
        ),
        controller: controller,
      );

      expect(
        disposition,
        InternalChatLinkDisposition.scrolledWithinCurrentChat,
      );
      expect(openedMessageId, 9001);
      expect(controller.consumePending(), isNull);
    },
  );

  test(
    'different-chat links request adaptive replacement, not a route push',
    () async {
      final controller = ChatDeepLinkController.shared;
      controller.consumePending();
      addTearDown(controller.consumePending);

      final disposition = await routeResolvedInternalChatLink(
        chatId: 84,
        title: 'Replacement chat',
        messageId: 700,
        source: InternalChatLinkTarget(
          chatId: 42,
          openMessage: (_) async => fail('must not scroll the old transcript'),
        ),
        controller: controller,
      );

      expect(
        disposition,
        InternalChatLinkDisposition.requestedAdaptiveReplacement,
      );
      final request = controller.consumePending();
      expect(request?.chatId, 84);
      expect(request?.title, 'Replacement chat');
      expect(request?.messageId, 700);
      expect(controller.consumePending(), isNull);
    },
  );
}
