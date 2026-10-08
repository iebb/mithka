import '../tdlib/json_helpers.dart';
import '../tdlib/td_models.dart';
import 'rich_text_format.dart';

/// Whether a plain text message carries literal Markdown markers that can be
/// re-rendered as Telegram formatting when the message is forwarded.
///
/// AI-generated replies often arrive with raw `**bold**`/`` `code` `` markers
/// and no entities, so they display as plain text. Forwarding such a message
/// with [richText] parses the markers through TDLib's `parseMarkdown` and
/// sends the result as a newly authored message.
class ForwardMarkdownOffer {
  const ForwardMarkdownOffer({
    required this.available,
    required this.suggested,
  });

  const ForwardMarkdownOffer.none() : available = false, suggested = false;

  /// At least one convertible marker pair was found; the rich-text option is
  /// worth showing. Weak enough to be offered unchecked: a lone pair can also
  /// appear in pasted code such as `int **argv, **env;`.
  final bool available;

  /// Multiple markers or a strong one (fenced code, link) were found; the
  /// message almost certainly is authored Markdown, so the option defaults on.
  final bool suggested;
}

/// Telegram caps text messages at 4096 UTF-16 code units; longer messages
/// cannot be re-sent as rich text and fall back to a regular forward.
const int markdownForwardTextLimit = 4096;

/// Counts the Markdown markers TDLib's `parseMarkdown` converts to entities.
/// Lone pairs score 1; fenced code blocks and links score higher because they
/// never appear in human prose by accident.
int markdownMarkerScore(String text) {
  var score = 0;
  final fenceLines = RegExp(
    r'^[ \t]{0,3}`{3,}',
    multiLine: true,
  ).allMatches(text).length;
  score += 3 * (fenceLines ~/ 2);
  score +=
      2 *
      RegExp(
        r'\[[^\[\]]*\]\((?:https?://|tg://)[^\s)]*\)',
      ).allMatches(text).length;
  score += _pairCount(text, '**');
  score += _pairCount(text, '__');
  score += _pairCount(text, '~~');
  score += _pairCount(text, '||');
  score += _pairCount(text, '`');
  return score;
}

int _pairCount(String text, String marker) {
  var count = 0;
  var cursor = 0;
  while (true) {
    final open = text.indexOf(marker, cursor);
    if (open < 0) return count;
    final close = text.indexOf(marker, open + marker.length);
    if (close < 0) return count;
    final inner = text.substring(open + marker.length, close);
    if (inner.trim().isNotEmpty) {
      count++;
      cursor = close + marker.length;
    } else {
      cursor = open + marker.length;
    }
  }
}

ForwardMarkdownOffer forwardMarkdownOffer(String text) {
  if (text.trim().isEmpty) return const ForwardMarkdownOffer.none();
  if (text.length > markdownForwardTextLimit) {
    return const ForwardMarkdownOffer.none();
  }
  final score = markdownMarkerScore(text);
  return ForwardMarkdownOffer(available: score >= 1, suggested: score >= 2);
}

/// Message-level gate: only plain text messages qualify. Media captions would
/// lose their attachment, and table blocks are extracted out of [ChatMessage]
/// text, so forwarding `.text` would silently drop them.
ForwardMarkdownOffer forwardMarkdownOfferForMessage(ChatMessage message) {
  // Detection is heuristic and must never break forwarding: an unexpected
  // message shape degrades to "no offer" instead of throwing.
  try {
    if (message.isService || !message.isPlainText) {
      return const ForwardMarkdownOffer.none();
    }
    // Only genuinely unformatted text qualifies. isPlainText describes the
    // content type, not the entity list: a message can already carry hidden
    // links, custom emoji, mentions or spoilers while still showing literal
    // markers. Re-authoring such text would parse only the markers and drop
    // the existing entities, so those messages keep the regular forward.
    if (message.textEntities.isNotEmpty || message.customEmoji.isNotEmpty) {
      return const ForwardMarkdownOffer.none();
    }
    if (message.richBlocks.any((block) => block.isTable)) {
      return const ForwardMarkdownOffer.none();
    }
    return forwardMarkdownOffer(message.text);
  } catch (_) {
    return const ForwardMarkdownOffer.none();
  }
}

/// Re-sends one text message as freshly authored rich text.
///
/// The literal markers are parsed through TDLib's `parseMarkdown` (the same
/// authority the composer uses) and the result is delivered with `sendMessage`,
/// which is why the forwarded copy has no "forwarded from" header. Returns
/// false when nothing converts — markers absent, all pairs empty, or the parsed
/// text exceeds Telegram's text limit — so the caller falls back to a regular
/// forward instead of sending an unchanged duplicate.
Future<bool> sendMarkdownRichTextForward({
  required Future<Map<String, dynamic>> Function(Map<String, dynamic>) query,
  required int fromChatId,
  required int messageId,
  required int targetChatId,
  required String text,
  Map<String, dynamic>? topicId,
}) async {
  late final Map<String, dynamic> sendRequest;
  try {
    if (text.trim().isEmpty) return false;
    // A re-sent message is a copy of protected content. Unlike the server-
    // enforced forward path, sendMessage no longer identifies the protected
    // source, so permission must be verified up front and fail closed: only
    // an explicit can_be_copied == true authorizes the re-send. A probe that
    // errors or times out falls back to the regular forward instead.
    final properties = await query({
      '@type': 'getMessageProperties',
      'chat_id': fromChatId,
      'message_id': messageId,
    });
    if (properties.type == 'error' ||
        properties.boolean('can_be_copied') != true) {
      return false;
    }
    final chat = await query({'@type': 'getChat', 'chat_id': fromChatId});
    if (chat.type == 'error' || chat.boolean('has_protected_content') == true) {
      return false;
    }
    final payload = await parseTelegramMarkdownWithTdLib(text, query: query);
    if (payload.entities.isEmpty) return false;
    final parsedText = payload.text;
    if (parsedText.trim().isEmpty || parsedText.length > 4096) return false;
    sendRequest = {
      '@type': 'sendMessage',
      'chat_id': targetChatId,
      'topic_id': ?topicId,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': payload.toTdJson(),
        'clear_draft': false,
      },
    };
  } catch (_) {
    // Before dispatch, a failed probe or conversion can safely fall back.
    return false;
  }
  // A lost acknowledgement does not mean the server rejected the message.
  // Propagate dispatch failures instead of forwarding a possible duplicate.
  await query(sendRequest);
  return true;
}
