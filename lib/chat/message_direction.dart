import '../tdlib/td_models.dart';

/// Use the actual sender for transcript placement when the account is known.
/// TDLib can mark a post sent as a channel as outgoing even though its sender
/// is the channel, and all of that channel's posts belong on the same side.
bool isOutgoingTranscriptMessage(ChatMessage message, int? meId) =>
    meId != null ? message.senderId == meId : message.isOutgoing;
