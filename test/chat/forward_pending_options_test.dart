import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/forward_handoff.dart';
import 'package:mithka/chat/messages/forward_markdown.dart';
import 'package:mithka/tdlib/td_models.dart';

ChatMessage _msg({int id = 1, String text = '', TdFileRef? image}) =>
    ChatMessage(id: id, isOutgoing: false, text: text, date: 1, image: image);

PendingForward _forward({bool hasCaption = false}) => PendingForward(
  fromChatId: 10,
  messages: [_msg(text: 'hello')],
  accountSlot: 0,
  clientId: 9,
  hasCaption: hasCaption,
  markdownOffer: const ForwardMarkdownOffer.none(),
  protectedCopy: false,
);

void main() {
  group('sender and caption toggles are independent', () {
    test('hiding the sender alone never touches the caption', () {
      final forward = _forward(hasCaption: true);
      forward.toggleSender();
      expect(forward.removeSender, isTrue);
      expect(forward.removeCaption, isFalse);
      // Toggling back restores both to default.
      forward.toggleSender();
      expect(forward.removeSender, isFalse);
      expect(forward.removeCaption, isFalse);
    });

    test(
      'removing the caption forces the sender hidden (copy requirement)',
      () {
        final forward = _forward(hasCaption: true);
        forward.toggleCaption();
        expect(forward.removeCaption, isTrue);
        expect(
          forward.removeSender,
          isTrue,
          reason: 'drop_media_captions requires drop_author',
        );
      },
    );

    test('restoring the caption restores a sender it forced off', () {
      final forward = _forward(hasCaption: true);
      forward.toggleCaption(); // sender forced off, memory armed
      forward.toggleCaption(); // caption back
      expect(forward.removeCaption, isFalse);
      expect(
        forward.removeSender,
        isFalse,
        reason: 'returnSendersNames must restore the forced-off sender',
      );
    });

    test('a manually hidden sender stays hidden when the caption returns', () {
      final forward = _forward(hasCaption: true);
      forward.toggleSender(); // manual, memory cleared
      forward.toggleCaption(); // sender already hidden: no memory armed
      expect(forward.removeSender, isTrue);
      forward.toggleCaption(); // caption back
      expect(
        forward.removeSender,
        isTrue,
        reason: 'the user hid the sender explicitly; it must stay hidden',
      );
      expect(forward.removeCaption, isFalse);
    });

    test('showing the sender after a forced copy drops the caption', () {
      final forward = _forward(hasCaption: true);
      forward.toggleCaption(); // copy armed
      forward.toggleSender(); // sender back
      expect(forward.removeSender, isFalse);
      expect(
        forward.removeCaption,
        isFalse,
        reason: 'a caption cannot be dropped from a forwarded original',
      );
    });
  });

  group('forwardSelectionHasCaption', () {
    test('media with text counts as captioned', () {
      expect(
        forwardSelectionHasCaption([
          _msg(text: 'cap', image: TdFileRef(id: 1)),
        ]),
        isTrue,
      );
    });

    test('media without text carries nothing to remove', () {
      expect(
        forwardSelectionHasCaption([_msg(image: TdFileRef(id: 1))]),
        isFalse,
      );
    });

    test('plain text messages are not captioned media', () {
      expect(forwardSelectionHasCaption([_msg(text: 'just text')]), isFalse);
    });

    test('one captioned media in a mixed selection is enough', () {
      expect(
        forwardSelectionHasCaption([
          _msg(text: 'plain'),
          _msg(id: 2, text: 'cap', image: TdFileRef(id: 1)),
        ]),
        isTrue,
      );
    });
  });

  group('options', () {
    test('defaults are a plain attributed forward', () {
      final forward = _forward();
      expect(forward.options.removeSender, isFalse);
      expect(forward.options.removeCaption, isFalse);
      expect(forward.options.richText, isFalse);
    });

    test('a protected copy starts with the sender hidden and memory armed', () {
      final forward = PendingForward(
        fromChatId: 10,
        messages: [_msg()],
        accountSlot: 0,
        clientId: 9,
        hasCaption: false,
        markdownOffer: const ForwardMarkdownOffer.none(),
        protectedCopy: true,
      );
      expect(forward.removeSender, isTrue);
      // Restoring the caption memory never existed here; toggling the sender
      // back is a plain manual toggle.
      forward.toggleSender();
      expect(forward.removeSender, isFalse);
    });
  });
}
