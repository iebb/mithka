final RegExp _usernameLink = RegExp(
  r'(?:https?://)?(?:t\.me|telegram\.me)/(@?[A-Za-z0-9_]+)',
  caseSensitive: false,
);
final RegExp _publicUsername = RegExp(r'^[A-Za-z0-9_]{3,32}$');

/// Whether [value] has the shape of a public Telegram username (no `@`).
bool isPublicTelegramUsername(String value) => _publicUsername.hasMatch(value);

/// The username a search query names — `@name`, `name`, or a `t.me/name`
/// link — or null when it does not name one.
String? telegramUsernameFromQuery(String query) {
  var value = query.trim();
  final link = _usernameLink.firstMatch(value);
  if (link != null) value = link.group(1)!;
  if (value.startsWith('@')) value = value.substring(1);
  return isPublicTelegramUsername(value) ? value : null;
}

final RegExp _userIdPrefix = RegExp(
  r'^(?:user(?:_?id)?|uid|id)\s*[:=#]?\s*(\d+)$',
  caseSensitive: false,
);
final RegExp _digitsOnly = RegExp(r'^\d+$');

/// Extracts a positive Telegram user ID from a numeric query, an `id:`/`uid:`
/// prefix, or a `tg://user?id=...` / `tg://openmessage?user_id=...` link.
///
/// Queries beginning with `+` (such as E.164 phone numbers) or evaluating to
/// non-positive integers return null.
int? telegramUserIdFromQuery(String query) {
  final value = query.trim();
  if (value.isEmpty || value.startsWith('+')) return null;

  int? validUserId(String? raw) {
    if (raw == null || !_digitsOnly.hasMatch(raw)) return null;
    final parsed = int.tryParse(raw);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  final direct = validUserId(value);
  if (direct != null) return direct;

  final prefixed = _userIdPrefix.firstMatch(value);
  if (prefixed != null) return validUserId(prefixed.group(1));

  final link = normalizeTelegramLink(value);
  if (link == null) return null;
  final uri = Uri.tryParse(link);
  if (uri == null || uri.scheme.toLowerCase() != 'tg') return null;
  final host = uri.host.toLowerCase();
  try {
    if (host == 'user') {
      return validUserId(uri.queryParameters['id']);
    }
    if (host == 'openmessage') {
      return validUserId(
        uri.queryParameters['user_id'] ?? uri.queryParameters['id'],
      );
    }
  } on FormatException {
    // Uri.tryParse accepts escaped bytes whose UTF-8 decoding can still fail
    // when queryParameters is read. Search input must never throw on them.
    return null;
  }
  return null;
}

/// Returns the canonical web form understood by Mithka's Telegram link
/// handler, or null when [raw] is not a Telegram deep link.
String? normalizeTelegramLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('tg:')) return trimmed;
  // The app's own schemes carry tg:// grammar too. Keep the normalization in
  // one place so search candidates and tapped message links agree on what is
  // an in-app Telegram destination.
  if (lower.startsWith('mk:') || lower.startsWith('mithka:')) {
    final wrapped = Uri.tryParse(trimmed);
    if (wrapped != null && wrapped.host.toLowerCase() == mithkaOpenLinkHost) {
      final inner = unwrapMithkaOpenLink(wrapped);
      if (inner != null) return inner;
    }
  }
  if (lower.startsWith('mk:')) return 'tg:${trimmed.substring(3)}';
  if (lower.startsWith('mithka:')) return 'tg:${trimmed.substring(7)}';

  var candidate = trimmed;
  if (!candidate.contains('://')) candidate = 'https://$candidate';
  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host == 't.me' ||
      host == 'telegram.me' ||
      host == 'telegram.dog' ||
      host == 'www.t.me' ||
      host == 'www.telegram.me' ||
      host == 'www.telegram.dog') {
    return uri.replace(scheme: 'https').toString();
  }
  return null;
}

/// The http(s) hosts Mithka registers with the OS (the Android VIEW filter).
const externalTelegramWebHosts = {
  't.me',
  'www.t.me',
  'telegram.me',
  'www.telegram.me',
  'telegram.dog',
  'www.telegram.dog',
};

/// Whether [uri] is an http(s) link on a host in [externalTelegramWebHosts].
bool isExternalTelegramWebLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  return (scheme == 'https' || scheme == 'http') &&
      externalTelegramWebHosts.contains(uri.host.toLowerCase());
}

/// A Telegram web link that names no chat, post or invite (the bare t.me
/// home page). It goes straight to the browser: there is nothing to open
/// in-app and nothing to log in for.
bool isTelegramWebHomePage(Uri uri) =>
    isExternalTelegramWebLink(uri) &&
    uri.pathSegments.every((segment) => segment.isEmpty) &&
    uri.query.isEmpty;

/// Host of Mithka's wrapper link, `mk://open?url=<percent-encoded link>`.
///
/// It hands an arbitrary Telegram link (tg://, t.me, telegram.me) to Mithka
/// through a scheme only Mithka registers, so a share extension or another
/// app can target Mithka even when an official Telegram client also claims
/// tg:// and t.me. `mithka://open?url=` is accepted too.
const mithkaOpenLinkHost = 'open';

/// Builds the wrapper link for [telegramLink]; see [mithkaOpenLinkHost].
String mithkaOpenLinkFor(String telegramLink) => Uri(
  scheme: 'mk',
  host: mithkaOpenLinkHost,
  queryParameters: {'url': telegramLink.trim()},
).toString();

/// The Telegram link carried by a `mk://open?url=` wrapper, normalized, or
/// null when [uri] is not a wrapper or carries anything else. Wrappers never
/// nest.
String? unwrapMithkaOpenLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if ((scheme != 'mk' && scheme != 'mithka') ||
      uri.host.toLowerCase() != mithkaOpenLinkHost) {
    return null;
  }
  String? inner;
  try {
    inner = uri.queryParameters['url']?.trim();
  } on FormatException {
    return null;
  }
  if (inner == null || inner.isEmpty) return null;
  final lower = inner.toLowerCase();
  if (lower.startsWith('mk:') || lower.startsWith('mithka:')) return null;
  return normalizeTelegramLink(inner);
}

enum ExternalLinkKind {
  /// Open in-app with the Telegram link handler.
  telegram,

  /// A `mk://open?url=` wrapper whose payload is not a Telegram link.
  notTelegram,

  /// Not a link Mithka accepts from outside; drop it silently.
  ignored,
}

/// How Mithka treats a URL the OS delivered (Android VIEW intent, iOS/macOS
/// open-URL, a share extension's wrapper link).
class ExternalLink {
  const ExternalLink._(this.kind, [this.link]);

  const ExternalLink.telegram(String link)
    : this._(ExternalLinkKind.telegram, link);
  static const notTelegram = ExternalLink._(ExternalLinkKind.notTelegram);
  static const ignored = ExternalLink._(ExternalLinkKind.ignored);

  final ExternalLinkKind kind;

  /// The link to hand to `openLink`; set only for [ExternalLinkKind.telegram].
  final String? link;

  @override
  bool operator ==(Object other) =>
      other is ExternalLink && other.kind == kind && other.link == link;

  @override
  int get hashCode => Object.hash(kind, link);

  @override
  String toString() => 'ExternalLink($kind, $link)';
}

/// Classifies a URL delivered from outside the app.
///
/// mk:// and mithka:// keep their tg:// grammar unchanged; the `open` host
/// unwraps a Telegram link. tg:// and http(s) links on
/// [externalTelegramWebHosts] are Telegram links. Everything else is ignored.
ExternalLink classifyExternalLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'mk' || scheme == 'mithka') {
    if (uri.host.toLowerCase() == mithkaOpenLinkHost) {
      final inner = unwrapMithkaOpenLink(uri);
      return inner == null
          ? ExternalLink.notTelegram
          : ExternalLink.telegram(inner);
    }
    return ExternalLink.telegram(uri.toString());
  }
  if (scheme == 'tg') return ExternalLink.telegram(uri.toString());
  if (isExternalTelegramWebLink(uri)) {
    return ExternalLink.telegram(uri.toString());
  }
  return ExternalLink.ignored;
}
