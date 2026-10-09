//
//  link_preview_fixer.dart
//
//  Telegram builds a link preview by fetching the linked page itself, and a
//  handful of large sites serve its crawler no usable Open Graph metadata, so
//  an x.com or Instagram link lands in the chat as bare text. Community mirrors
//  publish the same pages with metadata; when the user opts in, the mirror is
//  handed to TDLib through `linkPreviewOptions.url` while the outgoing message
//  text keeps the original link.
//

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_models.dart';

/// Opt-in preview mirrors plus the URL scanning needed to pick one.
class LinkPreviewFixer extends ChangeNotifier {
  LinkPreviewFixer._();

  static final LinkPreviewFixer shared = LinkPreviewFixer._();

  /// Local preference: nothing is stored on the account, and a message's text is
  /// never rewritten — only the URL the preview is fetched from.
  static const preferenceKey = 'fixLinkPreviews';

  /// Hosts Telegram cannot preview, mapped to the mirror serving the same page
  /// with metadata. Every subdomain is listed explicitly because a mirror only
  /// answers on the hosts it publishes; a rewritten `mobile.` prefix would not
  /// resolve.
  static const Map<String, String> previewHosts = {
    'x.com': 'fixupx.com',
    'www.x.com': 'fixupx.com',
    'mobile.x.com': 'fixupx.com',
    'twitter.com': 'fxtwitter.com',
    'www.twitter.com': 'fxtwitter.com',
    'mobile.twitter.com': 'fxtwitter.com',
    'tiktok.com': 'vxtiktok.com',
    'www.tiktok.com': 'vxtiktok.com',
    // A short link keeps its own prefix: the mirror follows the redirect.
    'vm.tiktok.com': 'vm.vxtiktok.com',
    'instagram.com': 'ddinstagram.com',
    'www.instagram.com': 'ddinstagram.com',
    'reddit.com': 'www.vxreddit.com',
    'www.reddit.com': 'www.vxreddit.com',
    'bsky.app': 'fxbsky.app',
    'www.bsky.app': 'fxbsky.app',
    'pixiv.net': 'www.phixiv.net',
    'www.pixiv.net': 'www.phixiv.net',
    'miyoushe.com': 'www.miyoushe.pp.ua',
    'www.miyoushe.com': 'www.miyoushe.pp.ua',
    'm.miyoushe.com': 'www.miyoushe.pp.ua',
    'hoyolab.com': 'www.hoyolab.pp.ua',
    'www.hoyolab.com': 'www.hoyolab.pp.ua',
    'm.hoyolab.com': 'www.hoyolab.pp.ua',
    'coolapk.com': 'coolapk1s.com',
    'www.coolapk.com': 'coolapk1s.com',
  };

  SharedPreferences? _preferences;
  bool _enabled = false;

  bool get enabled => _enabled;

  void initialize(SharedPreferences preferences) {
    _preferences = preferences;
    final value = preferences.getBool(preferenceKey) ?? false;
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    await preferences.setBool(preferenceKey, value);
  }

  /// `link_preview_options` for an outgoing text message, or null when the
  /// message needs no override.
  Map<String, dynamic>? optionsFor(
    String text, {
    List<MessageTextEntity> entities = const [],
  }) {
    final url = previewUrl(text, entities: entities);
    if (url == null) return null;
    return {'@type': 'linkPreviewOptions', 'is_disabled': false, 'url': url};
  }

  /// Same as [optionsFor] for a TDLib `formattedText` payload.
  Map<String, dynamic>? optionsForFormattedText(Map<String, dynamic>? text) =>
      optionsFor(text?.str('text') ?? '', entities: TDParse.textEntities(text));

  /// [request] with its preview pointed at a mirror, for the send paths that
  /// build an `inputMessageText` themselves.
  ///
  /// A request that already carries `link_preview_options` keeps them: an
  /// explicit choice by the caller beats a local preference. Anything that is
  /// not a plain text send — a caption, a media, a sticker — is returned as it
  /// came in, because TDLib only builds a preview card for text. Every composer
  /// funnel calls this, so a surface that builds its own request gets the same
  /// treatment as the main one.
  Map<String, dynamic> applyTo(Map<String, dynamic> request) {
    final content = request['input_message_content'];
    if (content is! Map<String, dynamic> ||
        content['@type'] != 'inputMessageText' ||
        content.containsKey('link_preview_options')) {
      return request;
    }
    final text = content['text'];
    if (text is! Map<String, dynamic>) return request;
    final options = optionsForFormattedText(text);
    if (options == null) return request;
    return {
      ...request,
      'input_message_content': {...content, 'link_preview_options': options},
    };
  }

  /// The mirror to fetch [text]'s preview from, or null when the preference is
  /// off, the text has no link, or its first link has no rule.
  String? previewUrl(
    String text, {
    List<MessageTextEntity> entities = const [],
  }) {
    if (!_enabled) return null;
    final first = firstPreviewableUrl(text, entities: entities);
    if (first == null) return null;
    return fixedUrl(first);
  }

  /// The link TDLib would preview in [text] — its first URL — or null when there
  /// is none.
  ///
  /// TDLib fills `linkPreviewOptions.url` for exactly one page, and without it
  /// previews the first URL in the text. Returning only that first URL keeps the
  /// override from swapping which link the card shows: a rule matching a later
  /// link is deliberately ignored.
  ///
  /// Selection follows TDLib's own `get_first_url`
  /// (td/telegram/MessageEntity.cpp), which walks the message's entities in
  /// order and takes the first `Url` or `TextUrl` one. A `TextUrl` contributes
  /// the target hidden behind its label, not the label — so a message whose
  /// first link is disguised still keeps its preview, and a later link that does
  /// have a rule cannot steal the slot. mithka only sends the entities its
  /// composer made, so whatever no entity covers is scanned the way TDLib's
  /// detector would have; see [_withoutEntitySpans] for which spans that leaves
  /// out.
  @visibleForTesting
  static String? firstPreviewableUrl(
    String text, {
    List<MessageTextEntity> entities = const [],
  }) {
    if (text.isEmpty) return null;
    final ordered = _orderedEntities(entities, text.length);
    for (final entity in ordered) {
      final url = _entityUrl(entity, text);
      if (url != null) return url;
    }
    final searchable = _withoutEntitySpans(text, ordered);
    final schemed = _schemeUrl.firstMatch(searchable);
    final bare = _bareHost.firstMatch(searchable);
    if (schemed == null && bare == null) return null;
    final start =
        bare != null && (schemed == null || bare.start < schemed.start)
        ? bare.start
        : schemed!.start;
    final url = trimmedUrl(searchable.substring(start));
    return url.isEmpty ? null : url;
  }

  /// [entities] in the order TDLib walks them: by offset, with anything that
  /// cannot point into [text] dropped.
  static List<MessageTextEntity> _orderedEntities(
    List<MessageTextEntity> entities,
    int textLength,
  ) {
    if (entities.isEmpty) return const [];
    final ordered = [...entities]..sort((a, b) => a.offset.compareTo(b.offset));
    return [
      for (final entity in ordered)
        if (entity.length > 0 &&
            entity.offset >= 0 &&
            entity.offset < textLength)
          entity,
    ];
  }

  /// The URL one entity contributes to the preview, or null when TDLib would
  /// look past it and keep walking.
  static String? _entityUrl(MessageTextEntity entity, String text) {
    final String candidate;
    switch (entity.type) {
      case 'textEntityTypeTextUrl':
        // The label is decoration; the hidden target is what gets fetched.
        candidate = entity.url ?? '';
      case 'textEntityTypeUrl':
        // TDLib skips a `Url` entity too short to hold a link.
        if (entity.length <= 4) return null;
        final start = entity.offset.clamp(0, text.length);
        candidate = text.substring(start, entity.end.clamp(start, text.length));
      default:
        return null;
    }
    final url = trimmedUrl(candidate.trim());
    return url.isEmpty || !_isWebLink(url) ? null : url;
  }

  /// True when [url] is something a preview mirror could serve: no scheme at
  /// all, or an http(s) one. TDLib walks past `ton:`, `tg:`, `ftp:` and
  /// `tonsite:` entities instead of giving up, so a foreign scheme has to skip
  /// the entity rather than fail the whole lookup.
  static bool _isWebLink(String url) {
    final separator = url.indexOf('://');
    if (separator < 0) return !_hasForeignScheme(url);
    final scheme = url.substring(0, separator).toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  /// The mirror for a single [url], or null when no rule matches or rewriting
  /// would not be safe.
  @visibleForTesting
  static String? fixedUrl(String url) {
    final trimmed = trimmedUrl(url);
    if (trimmed.isEmpty) return null;
    final hasSeparator = trimmed.contains('://');
    // `mailto:`, `tel:`, `data:` — a scheme without an authority is never the
    // web link a preview mirror can serve.
    if (!hasSeparator && _hasForeignScheme(trimmed)) return null;
    final absolute = hasSeparator ? trimmed : 'https://$trimmed';
    final parsed = Uri.tryParse(absolute);
    if (parsed == null) return null;
    final scheme = parsed.scheme.toLowerCase();
    // Mirrors are HTTPS only, and a port other than the scheme default means
    // this is not the public site the rule was written for.
    if ((scheme != 'https' && scheme != 'http') || parsed.hasPort) return null;
    final host = parsed.host.toLowerCase();
    final mirror = previewHosts[host];
    if (mirror == null) return null;

    final authorityStart = scheme.length + 3;
    // Query and fragment go: mirrors key off the canonical path, and tracking
    // parameters would only follow the reader to a third party.
    var sanitized = absolute;
    final queryStart = _firstOf(absolute, authorityStart, 0x3f, 0x23); // ? #
    if (queryStart >= 0) sanitized = absolute.substring(0, queryStart);
    final pathStart = _firstOf(sanitized, authorityStart, 0x2f); // /
    final authorityEnd = pathStart < 0 ? sanitized.length : pathStart;
    final authority = sanitized.substring(authorityStart, authorityEnd);
    // Credentials in a shared link never travel to a mirror.
    final credentials = authority.lastIndexOf('@');
    var hostPart = credentials < 0
        ? authority
        : authority.substring(credentials + 1);
    // A written-out default port (`:443` on https) is normalized away by the
    // parse above, so what is left of the authority is the port to drop.
    final portSeparator = hostPart.indexOf(':');
    if (portSeparator >= 0) hostPart = hostPart.substring(0, portSeparator);
    if (hostPart.toLowerCase() != host) return null;
    final path = pathStart < 0 ? '' : sanitized.substring(pathStart);

    final result = 'https://$mirror$path';
    final check = Uri.tryParse(result);
    if (check == null ||
        check.scheme != 'https' ||
        check.host.toLowerCase() != mirror.toLowerCase() ||
        check.userInfo.isNotEmpty ||
        check.hasPort) {
      return null;
    }
    return result;
  }

  /// Cuts [raw] down to its link: a URL body is printable ASCII without quotes
  /// or angle brackets, and trailing sentence punctuation belongs to the text
  /// around it.
  @visibleForTesting
  static String trimmedUrl(String raw) {
    var end = raw.length;
    for (var index = 0; index < raw.length; index++) {
      final code = raw.codeUnitAt(index);
      if (code < 0x21 || code > 0x7e || _quoteOrBracket(code)) {
        end = index;
        break;
      }
    }
    var url = raw.substring(0, end);
    while (url.isNotEmpty) {
      final last = url.codeUnitAt(url.length - 1);
      final shorter = url.substring(0, url.length - 1);
      if (_trailingPunctuation.contains(last)) {
        url = shorter;
        continue;
      }
      // A closing bracket is part of the link only if the link opened it.
      final opener = _openingBracketFor(last);
      if (opener != null && _countOf(url, last) > _countOf(url, opener)) {
        url = shorter;
        continue;
      }
      break;
    }
    return url;
  }

  static final RegExp _schemeUrl = RegExp(
    r'https?://\S+',
    caseSensitive: false,
  );

  /// A bare host. It only decides which link comes first, so a false positive
  /// (`file.txt`, `v1.2.3`) costs a skipped fix, never a wrong preview.
  static final RegExp _bareHost = RegExp(
    r'(?<![A-Za-z0-9._~%+@-])'
    r'(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}'
    r'(?![A-Za-z0-9-])',
  );

  /// A scheme-like prefix without an authority: the colon arrives before any
  /// path separator, as in `mailto:` or `tel:`.
  static bool _hasForeignScheme(String value) {
    for (var index = 0; index < value.length; index++) {
      final code = value.codeUnitAt(index);
      if (code == 0x3a) return index > 0; // :
      if (code == 0x2f || code == 0x3f || code == 0x23) return false; // / ? #
    }
    return false;
  }

  /// . , ; : ! ?
  static const List<int> _trailingPunctuation = [
    0x2e,
    0x2c,
    0x3b,
    0x3a,
    0x21,
    0x3f,
  ];

  static bool _quoteOrBracket(int code) =>
      code == 0x22 || // "
      code == 0x27 || // '
      code == 0x3c || // <
      code == 0x3e || // >
      code == 0x60; // `

  static int? _openingBracketFor(int code) => switch (code) {
    0x29 => 0x28, // ) (
    0x5d => 0x5b, // ] [
    0x7d => 0x7b, // } {
    _ => null,
  };

  static int _countOf(String value, int code) {
    var count = 0;
    for (var index = 0; index < value.length; index++) {
      if (value.codeUnitAt(index) == code) count++;
    }
    return count;
  }

  static int _firstOf(String value, int from, int first, [int? second]) {
    for (var index = from; index < value.length; index++) {
      final code = value.codeUnitAt(index);
      if (code == first || code == second) return index;
    }
    return -1;
  }

  /// The entity types TDLib treats as splittable: a link it detects inside one
  /// of these survives the merge, so their spans stay searchable
  /// (`is_splittable_entity` in td/telegram/MessageEntity.cpp).
  static const Set<String> _splittableEntities = {
    'textEntityTypeBold',
    'textEntityTypeItalic',
    'textEntityTypeUnderline',
    'textEntityTypeStrikethrough',
    'textEntityTypeSpoiler',
  };

  /// Blanks every span TDLib would not linkify, without moving any offset.
  ///
  /// TDLib merges its detector's findings with the entities a client sent and
  /// drops any detected link overlapping a non-splittable one
  /// (`merge_new_entities`), so code and quotes, mentions and addresses, and a
  /// `TextUrl`'s label all hide whatever link-shaped text they cover. Scanning
  /// them anyway would let a label stand in for the target behind it.
  static String _withoutEntitySpans(
    String text,
    List<MessageTextEntity> entities,
  ) {
    if (entities.isEmpty) return text;
    final codes = text.codeUnits.toList();
    var masked = false;
    for (final entity in entities) {
      if (_splittableEntities.contains(entity.type)) continue;
      final start = entity.offset.clamp(0, codes.length);
      final end = entity.end.clamp(start, codes.length);
      for (var index = start; index < end; index++) {
        // Line breaks stay: they already separate tokens.
        if (codes[index] == 0x0a || codes[index] == 0x0d) continue;
        codes[index] = 0x20;
        masked = true;
      }
    }
    return masked ? String.fromCharCodes(codes) : text;
  }
}
