class FormattedTextPayload {
  const FormattedTextPayload(this.text, this.entities);

  final String text;
  final List<Map<String, dynamic>> entities;

  Map<String, dynamic> toTdJson() => {
    '@type': 'formattedText',
    'text': text,
    if (entities.isNotEmpty) 'entities': entities,
  };
}

class _Marker {
  const _Marker(this.marker, this.type);

  final String marker;
  final String type;
}

typedef TelegramMarkdownQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

/// Parses explicitly authored Markdown through TDLib, the protocol authority.
/// The local parser is retained only as a compatibility fallback for older or
/// temporarily unavailable TDLib builds.
Future<FormattedTextPayload> parseTelegramMarkdownWithTdLib(
  String text, {
  required TelegramMarkdownQuery query,
}) async {
  try {
    final response = await query({
      '@type': 'parseMarkdown',
      'text': {
        '@type': 'formattedText',
        'text': text,
        'entities': const <Object>[],
      },
    });
    final parsedText = response['text'];
    final rawEntities = response['entities'];
    if (parsedText is String && rawEntities is List) {
      return FormattedTextPayload(
        parsedText,
        rawEntities
            .whereType<Map<String, dynamic>>()
            .map(Map<String, dynamic>.of)
            .toList(growable: false),
      );
    }
  } catch (_) {
    // Fall back below so a temporary TDLib error does not block the post.
  }
  return parseTelegramMarkdown(text);
}

FormattedTextPayload parseTelegramMarkdown(String text) {
  const markers = [
    _Marker('```', 'textEntityTypePre'),
    _Marker('~~', 'textEntityTypeStrikethrough'),
    _Marker('||', 'textEntityTypeSpoiler'),
    _Marker('**', 'textEntityTypeBold'),
    _Marker('__', 'textEntityTypeItalic'),
    _Marker('`', 'textEntityTypeCode'),
    _Marker('*', 'textEntityTypeItalic'),
    _Marker('_', 'textEntityTypeItalic'),
  ];
  final buffer = StringBuffer();
  final entities = <Map<String, dynamic>>[];
  var i = 0;
  while (i < text.length) {
    _Marker? matched;
    for (final marker in markers) {
      if (text.startsWith(marker.marker, i)) {
        matched = marker;
        break;
      }
    }
    if (matched == null) {
      buffer.write(text[i]);
      i += 1;
      continue;
    }
    final contentStart = i + matched.marker.length;
    final contentEnd = text.indexOf(matched.marker, contentStart);
    if (contentEnd <= contentStart) {
      buffer.write(text[i]);
      i += 1;
      continue;
    }
    final inner = text.substring(contentStart, contentEnd);
    if (inner.trim().isEmpty) {
      buffer.write(text[i]);
      i += 1;
      continue;
    }
    final offset = buffer.length;
    buffer.write(inner);
    entities.add({
      '@type': 'textEntity',
      'offset': offset,
      'length': inner.length,
      'type': {'@type': matched.type},
    });
    i = contentEnd + matched.marker.length;
  }
  return FormattedTextPayload(buffer.toString(), entities);
}
