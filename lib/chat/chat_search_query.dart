//
//  chat_search_query.dart
//
//  Token syntax for in-chat search: `from:` narrows to one sender, `has:`
//  narrows to one kind of message. Both map onto parameters TDLib's
//  searchChatMessages already takes — `sender_id` and `filter` — so a token is
//  a shorthand for a filter the search can genuinely apply, never a client-side
//  pass over results.
//
//  Deliberately absent: `mentions:<user>` and date ranges. TDLib can filter
//  mentions of the current user only, and searchChatMessages takes no date
//  bounds, so neither could be honoured.
//

import 'chat_message_search_controller.dart';

/// What a raw search field resolves to.
class ChatSearchTokens {
  const ChatSearchTokens({
    required this.text,
    this.fromQuery,
    this.inQuery,
    this.filter,
  });

  /// The query with every recognised token removed — what TDLib searches for.
  final String text;

  /// The text after `from:`, still to be resolved to a sender.
  final String? fromQuery;

  /// The text after `in:`, still to be resolved to a chat.
  final String? inQuery;

  /// The kind named by `has:`, when it named a supported one.
  final ChatSearchFilter? filter;

  bool get isEmpty =>
      text.trim().isEmpty && fromQuery == null && inQuery == null;
}

/// The kinds of token that offer suggestions while being typed.
enum ChatSearchTokenKind { from, chat }

/// The token the caret is sitting in, which is the one to suggest for.
class ChatSearchActiveToken {
  const ChatSearchActiveToken({
    required this.kind,
    required this.value,
    required this.start,
    required this.end,
  });

  final ChatSearchTokenKind kind;

  /// What has been typed after the colon, unquoted.
  final String value;

  /// Range of the whole token in the raw text, so a picked suggestion can
  /// replace exactly what was typed and nothing around it.
  final int start;
  final int end;
}

const _filterAliases = <String, ChatSearchFilter>{
  'link': ChatSearchFilter.links,
  'links': ChatSearchFilter.links,
  'url': ChatSearchFilter.links,
  'embed': ChatSearchFilter.links,
  'file': ChatSearchFilter.files,
  'files': ChatSearchFilter.files,
  'doc': ChatSearchFilter.files,
  'document': ChatSearchFilter.files,
  'photo': ChatSearchFilter.media,
  'image': ChatSearchFilter.media,
  'video': ChatSearchFilter.media,
  'media': ChatSearchFilter.media,
  'voice': ChatSearchFilter.voice,
  'music': ChatSearchFilter.music,
  'audio': ChatSearchFilter.music,
  'sound': ChatSearchFilter.music,
};

/// Kinds `has:` accepts, for anything that wants to describe the syntax.
Iterable<String> get chatSearchHasAliases => _filterAliases.keys;

final _tokenPattern = RegExp(
  // A token is `key:value`, where the value may be quoted to hold spaces.
  r'\b(from|in|has):("([^"]*)"|\S*)',
  caseSensitive: false,
);

/// Which token, if any, the caret at [caretOffset] is editing.
///
/// Suggestions follow the caret rather than the last token in the string, so
/// going back to fix an earlier `in:` offers chats again instead of whatever
/// was typed last.
ChatSearchActiveToken? activeChatSearchToken(String raw, int caretOffset) {
  final caret = caretOffset.clamp(0, raw.length);
  for (final match in _tokenPattern.allMatches(raw)) {
    if (caret < match.start || caret > match.end) continue;
    final key = match.group(1)!.toLowerCase();
    final kind = switch (key) {
      'from' => ChatSearchTokenKind.from,
      'in' => ChatSearchTokenKind.chat,
      _ => null,
    };
    if (kind == null) return null;
    return ChatSearchActiveToken(
      kind: kind,
      value: (match.group(3) ?? match.group(2) ?? '').trim(),
      start: match.start,
      end: match.end,
    );
  }
  return null;
}

/// Rewrites the token at [token] to [value], quoting it when it holds spaces.
///
/// Returns the new text and where the caret should land — just past the token,
/// with a trailing space, so typing can continue without repositioning.
({String text, int caret}) applyChatSearchToken(
  String raw,
  ChatSearchActiveToken token,
  String value,
) {
  final key = switch (token.kind) {
    ChatSearchTokenKind.from => 'from',
    ChatSearchTokenKind.chat => 'in',
  };
  final quoted = value.contains(' ') ? '"$value"' : value;
  // Leave the caret past a single separating space. Adding one unconditionally
  // would double the space when the token already had words after it.
  final followedBySpace =
      token.end < raw.length && raw[token.end].trim().isEmpty;
  final replacement = followedBySpace ? '$key:$quoted' : '$key:$quoted ';
  final text = raw.replaceRange(token.start, token.end, replacement);
  // Either the separator is already in the text just past the replacement, or
  // the replacement supplied it; the caret goes after it in both cases.
  final caret = token.start + replacement.length + (followedBySpace ? 1 : 0);
  return (text: text, caret: caret);
}

/// Takes the token at [token] out of the text entirely.
///
/// A token that has been resolved to a chat or a person is shown as a badge
/// beside the field, so leaving its text behind would state the same filter
/// twice and invite the two to disagree.
({String text, int caret}) removeChatSearchToken(
  String raw,
  ChatSearchActiveToken token,
) {
  var end = token.end;
  // Take the separator with it, so removing a token from the middle does not
  // leave a double space behind.
  if (end < raw.length && raw[end].trim().isEmpty) end += 1;
  return (text: raw.replaceRange(token.start, end, ''), caret: token.start);
}

/// Splits a raw field value into its search text and its tokens.
///
/// An unfinished token (`from:` with nothing after it) is dropped from the
/// search text but resolves to nothing, so results do not thrash while the
/// name is still being typed.
ChatSearchTokens parseChatSearchQuery(String raw) {
  String? fromQuery;
  String? inQuery;
  ChatSearchFilter? filter;
  final text = raw
      .replaceAllMapped(_tokenPattern, (match) {
        final key = match.group(1)!.toLowerCase();
        final value = (match.group(3) ?? match.group(2) ?? '').trim();
        if (key == 'from') {
          if (value.isNotEmpty) fromQuery = value;
          return '';
        }
        if (key == 'in') {
          if (value.isNotEmpty) inQuery = value;
          return '';
        }
        final resolved = _filterAliases[value.toLowerCase()];
        // An unknown kind is not a filter; leave it in the text so the search
        // still looks for what was typed instead of silently ignoring it.
        if (resolved == null) return match.group(0)!;
        filter = resolved;
        return '';
      })
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return ChatSearchTokens(
    text: text,
    fromQuery: fromQuery,
    inQuery: inQuery,
    filter: filter,
  );
}
