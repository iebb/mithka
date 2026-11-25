//
//  forward_handoff.dart
//
//  Carries a forward from the chat the user picked it in (source) to the
//  chat it must land in (target), mirroring the reference client's forward flow: the
//  picker only chooses the recipient, and the target chat's composer holds
//  the pending forward as a reply-style preview panel until the user sends.
//

import '../tdlib/td_models.dart';
import 'messages/forward_markdown.dart';
import 'messages/forward_options.dart';

/// A forward carried from the picking chat into the newly opened transcript.
///
/// The target composer holds this until send; the actual `forwardMessages`
/// request is issued from the target chat with the source account pinned
/// ([accountSlot]/[clientId]), so a concurrent account switch can never
/// re-author the source ids under a different account.
class ForwardMessagesHandoff {
  const ForwardMessagesHandoff({
    required this.fromChatId,
    required this.messages,
    required this.accountSlot,
    required this.clientId,
    required this.hasCaption,
    required this.markdownOffer,
    this.protectedCopy = false,
  });

  final int fromChatId;

  /// Source messages in forward order. [ChatMessage] is plain data; holding
  /// the references is safe after the source view model is disposed.
  final List<ChatMessage> messages;

  /// The account that owns [fromChatId] and [messages].
  final int accountSlot;
  final int clientId;

  /// Whether any source message is captioned media — the only selection
  /// shape the 移除说明 option applies to (the reference client `hasCaption`).
  final bool hasCaption;

  /// Markdown detected in the forwarded text, for the render-markdown chip.
  final ForwardMarkdownOffer markdownOffer;

  /// The source chat has protected content and the kept-messages toggle
  /// routes the forward through the copy path instead.
  final bool protectedCopy;
}

/// The composer's pending forward: a handoff plus the user's live choices.
class PendingForward {
  PendingForward({
    required this.fromChatId,
    required this.messages,
    required this.accountSlot,
    required this.clientId,
    required this.hasCaption,
    required this.markdownOffer,
    required this.protectedCopy,
  }) : // A caption can only be dropped from a copy (drop_media_captions
       // requires drop_author), so a protected-copy forward starts with the
       // sender hidden and the restore memory armed.
       _removeSender = protectedCopy,
       _removeCaption = false,
       _returnSendersNames = protectedCopy;

  final int fromChatId;
  final List<ChatMessage> messages;
  final int accountSlot;
  final int clientId;
  final bool hasCaption;
  final ForwardMarkdownOffer markdownOffer;
  final bool protectedCopy;

  bool _removeSender;
  bool _removeCaption;

  /// the reference client `returnSendersNames`: remembers that hiding the sender was
  /// forced by hiding the caption, so restoring the caption restores the
  /// sender too. Any manual sender toggle clears the memory.
  bool _returnSendersNames = false;

  bool get removeSender => _removeSender;
  bool get removeCaption => _removeCaption;

  /// A protected-copy forward re-sends as freshly authored messages: there
  /// is no forward header to hide a sender from and no media caption option
  /// travels with the copy, so neither toggle applies (the send path
  /// ignores them). The options sheet hides both rows.
  bool get canToggleSender => !protectedCopy;
  bool get canToggleCaption => !protectedCopy;

  bool get renderMarkdown => _renderMarkdown && markdownOffer.available;
  bool _renderMarkdown = false;

  ForwardOptions get options => ForwardOptions(
    removeSender: _removeSender,
    removeCaption: _removeCaption,
    richText: renderMarkdown,
  );

  /// the reference client sendersNameButton semantics: showing the sender again also
  /// brings captions back (a caption cannot be dropped from a forwarded
  /// original).
  void toggleSender() {
    _removeSender = !_removeSender;
    _returnSendersNames = false;
    if (!_removeSender) _removeCaption = false;
  }

  /// the reference client captionButton semantics: hiding the caption forces the copy
  /// path (sender hidden), remembering to restore the sender when the
  /// caption returns.
  void toggleCaption() {
    _removeCaption = !_removeCaption;
    if (_removeCaption) {
      if (!_removeSender) {
        _removeSender = true;
        _returnSendersNames = true;
      }
    } else {
      if (_returnSendersNames) _removeSender = false;
      _returnSendersNames = false;
    }
  }

  void toggleRenderMarkdown() => _renderMarkdown = !_renderMarkdown;
}

PendingForward pendingForwardFromHandoff(ForwardMessagesHandoff handoff) =>
    PendingForward(
      fromChatId: handoff.fromChatId,
      messages: handoff.messages,
      accountSlot: handoff.accountSlot,
      clientId: handoff.clientId,
      hasCaption: handoff.hasCaption,
      markdownOffer: handoff.markdownOffer,
      protectedCopy: handoff.protectedCopy,
    ).._renderMarkdown = handoff.markdownOffer.suggested;

/// Whether any message in the selection is captioned media — the only shape
/// the 移除说明 option applies to. Mirrors the reference client `hasCaption`
/// (`!TextUtils.isEmpty(messageObject.caption)`): plain text messages carry
/// no caption, and media without text carries nothing to remove.
bool forwardSelectionHasCaption(List<ChatMessage> messages) {
  for (final message in messages) {
    if (message.text.trim().isEmpty) continue;
    if (_carriesCaption(message)) return true;
  }
  return false;
}

bool _carriesCaption(ChatMessage message) =>
    message.image != null ||
    message.video != null ||
    message.document != null ||
    message.music != null ||
    message.voice != null;
