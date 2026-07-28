import '../tdlib/td_client.dart';

enum ChatSendFailureKind {
  paidMessageRequired,
  insufficientStars,
  premiumRequired,
  mutualContactRequired,
  privacyRestricted,
  blocked,
  chatPermissionDenied,
  recipientUnavailable,
  rateLimited,
  generic,
}

class ChatSendFailure {
  const ChatSendFailure({
    required this.kind,
    required this.code,
    required this.technicalMessage,
    this.paidMessageStarCount = 0,
  });

  factory ChatSendFailure.fromError(
    Object error, {
    int paidMessageStarCount = 0,
  }) {
    final code = error is TdError ? error.code : 0;
    final message = error is TdError ? error.message : error.toString();
    return ChatSendFailure(
      kind: classifyChatSendFailure(message, code: code),
      code: code,
      technicalMessage: message.trim().isEmpty
          ? 'Message send failed'
          : message.trim(),
      paidMessageStarCount: paidMessageStarCount,
    );
  }

  factory ChatSendFailure.premiumOrContactRequired() => const ChatSendFailure(
    kind: ChatSendFailureKind.premiumRequired,
    code: 403,
    technicalMessage: 'PRIVACY_PREMIUM_REQUIRED',
  );

  factory ChatSendFailure.recipientUnavailable() => const ChatSendFailure(
    kind: ChatSendFailureKind.recipientUnavailable,
    code: 400,
    technicalMessage: 'USER_DEACTIVATED',
  );

  final ChatSendFailureKind kind;
  final int code;
  final String technicalMessage;
  final int paidMessageStarCount;

  String get deduplicationKey => '$code:${kind.name}:$technicalMessage';
}

ChatSendFailureKind classifyChatSendFailure(String message, {int code = 0}) {
  final normalized = message.trim().toUpperCase();

  bool containsAny(Iterable<String> values) => values.any(normalized.contains);

  if (containsAny(const [
    'STARS_TOO_FEW',
    'NOT_ENOUGH_STARS',
    'BALANCE_TOO_LOW',
    'PAYMENT_NOT_ENOUGH',
    'INSUFFICIENT_STARS',
  ])) {
    return ChatSendFailureKind.insufficientStars;
  }
  if (containsAny(const [
    'PRIVACY_PREMIUM_REQUIRED',
    'PREMIUM_ACCOUNT_REQUIRED',
    'PREMIUM_SUBSCRIPTION_REQUIRED',
    'PREMIUM_REQUIRED',
  ])) {
    return ChatSendFailureKind.premiumRequired;
  }
  if (containsAny(const [
    'ALLOW_PAYMENT_REQUIRED',
    'PAID_MESSAGE_REQUIRED',
    'PAYMENT_REQUIRED',
    'PAID MESSAGES',
  ])) {
    return ChatSendFailureKind.paidMessageRequired;
  }
  if (containsAny(const [
    'USER_NOT_MUTUAL_CONTACT',
    'MUTUAL_CONTACT_REQUIRED',
    'MUTUAL CONTACT',
  ])) {
    return ChatSendFailureKind.mutualContactRequired;
  }
  if (containsAny(const [
    'USER_IS_BLOCKED',
    'YOU_BLOCKED_USER',
    'USER_BLOCKED',
    'PEER_IS_BLOCKED',
    'BLACKLIST',
  ])) {
    return ChatSendFailureKind.blocked;
  }
  if (containsAny(const [
    'USER_PRIVACY_RESTRICTED',
    'PRIVACY_RESTRICTED',
    'PRIVACY VIOLATION',
  ])) {
    return ChatSendFailureKind.privacyRestricted;
  }
  if (containsAny(const [
    'USER_DEACTIVATED',
    'INPUT_USER_DEACTIVATED',
    'USER_IS_DELETED',
    'PEER_ID_INVALID',
    'CHAT_NOT_FOUND',
  ])) {
    return ChatSendFailureKind.recipientUnavailable;
  }
  if (containsAny(const [
    'CHAT_WRITE_FORBIDDEN',
    'CHAT_SEND_',
    'USER_BANNED_IN_CHANNEL',
    'CHANNEL_PRIVATE',
    'CHAT_ADMIN_REQUIRED',
    'RIGHT_FORBIDDEN',
    'TOPIC_CLOSED',
    'MESSAGE_THREAD_NOT_FOUND',
    'NOT ENOUGH RIGHTS',
  ])) {
    return ChatSendFailureKind.chatPermissionDenied;
  }
  if (containsAny(const [
    'FLOOD_WAIT',
    'FLOOD_PREMIUM_WAIT',
    'SLOWMODE_WAIT',
    'TOO MANY REQUESTS',
  ])) {
    return ChatSendFailureKind.rateLimited;
  }
  if (code == 403) return ChatSendFailureKind.chatPermissionDenied;
  return ChatSendFailureKind.generic;
}
