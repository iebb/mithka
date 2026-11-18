//
//  emoji_channel_source.dart
//
//  Emoji font catalog served from the @mithka_metadata Telegram channel —
//  the exteraless-style remote source. A #emojiv2 catalog message holds a
//  JSON body naming each pack's preview and font message ids; fonts are
//  channel documents fetched through the active TDLib account, so no
//  external HTTP host is involved once the client is signed in.
//

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'emoji_font_catalog.dart';

/// The channel that serves the fork's emoji packs.
class EmojiChannelSource {
  EmojiChannelSource({TdClient? client}) : _client = client ?? TdClient.shared;

  static const channelUsername = 'mithka_metadata';
  static const catalogTag = '#emojiv2';

  final TdClient _client;

  /// Cache of chat_id → chat so repeated lookups don't re-resolve the peer.
  int? _cachedChatId;

  /// Resolves the metadata channel to its chat id via searchPublicChat.
  Future<int?> _chatId() async {
    final cached = _cachedChatId;
    if (cached != null) return cached;
    if (!_client.hasActiveClient) return null;
    try {
      final chat = await _client.query(
        {'@type': 'searchPublicChat', 'username': channelUsername},
        timeout: const Duration(seconds: 10),
      );
      final id = chat.int64('id');
      if (id == null || id == 0) return null;
      _cachedChatId = id;
      return id;
    } catch (error) {
      debugPrint(
        '[emoji_channel_source] metadata channel lookup failed '
        'type=${error.runtimeType}',
      );
      return null;
    }
  }

  /// Fetches and parses the #emojiv2 catalog into manifest entries. Returns
  /// null when the channel is unreachable (no account / network) so the
  /// caller can fall back to the HTTP manifest.
  Future<List<EmojiFontManifestEntry>?> fetchCatalog() async {
    final chatId = await _chatId();
    if (chatId == null) return null;
    try {
      final response = await _client.query(
        {
          '@type': 'searchChatMessages',
          'chat_id': chatId,
          'query': catalogTag,
          'from_message_id': 0,
          'offset': 0,
          'limit': 4,
          'filter': {'@type': 'searchMessagesFilterEmpty'},
        },
        timeout: const Duration(seconds: 15),
      );
      final messages = response.objects('messages') ?? const [];
      for (final message in messages) {
        final text = message.obj('content')?.obj('text')?.str('text');
        if (text == null || !text.startsWith(catalogTag)) continue;
        final entries = parseCatalog(text);
        if (entries == null) continue;
        return [
          for (final entry in entries)
            EmojiFontManifestEntry.channel(
              key: entry.key,
              label: entry.label,
              license: entry.license,
              chatId: chatId,
              messageId: entry.channelMessageId!,
              sizeBytes: entry.sizeBytes,
            ),
        ];
      }
      return null;
    } catch (error) {
      debugPrint(
        '[emoji_channel_source] catalog search failed '
        'type=${error.runtimeType}',
      );
      return null;
    }
  }

  /// Catalog text is `<tag>\n{json}` — the same body the exteraless helper
  /// parses. Mapped onto [EmojiFontManifestEntry]s with the channel message
  /// id kept as the download address; chatId is left 0 for the caller to
  /// stamp once the channel is known.
  @visibleForTesting
  static List<EmojiFontManifestEntry>? parseCatalog(String body) {
    final jsonStart = body.indexOf('{');
    if (jsonStart < 0) return null;
    final decoded = jsonDecode(body.substring(jsonStart));
    if (decoded is! Map) return null;
    final emojis = decoded['emojis'];
    if (emojis is! List) return null;
    final entries = <EmojiFontManifestEntry>[];
    for (final item in emojis) {
      if (item is! Map) continue;
      final key = (item['id'] as String?)?.trim() ?? '';
      final label = (item['name'] as String?)?.trim() ?? '';
      final file = (item['file'] as num?)?.toInt();
      final size = (item['size'] as num?)?.toInt();
      if (key.isEmpty || label.isEmpty || file == null || file <= 0) continue;
      entries.add(
        EmojiFontManifestEntry.channel(
          key: key,
          label: label,
          license: (item['license'] as String?)?.trim() ?? '',
          chatId: 0,
          messageId: file,
          sizeBytes: size,
        ),
      );
    }
    return entries.isEmpty ? null : entries;
  }

  /// Downloads a channel document to [destPath]. Returns the byte length, or
  /// null when the message/file can't be fetched through TDLib.
  Future<int?> downloadFont({
    required int chatId,
    required int messageId,
    required String destPath,
  }) async {
    try {
      final messages = await _client.query(
        {
          '@type': 'getChatMessages',
          'chat_id': chatId,
          'message_ids': [messageId],
        },
        timeout: const Duration(seconds: 15),
      );
      final list = messages.objects('messages') ?? const [];
      Map<String, dynamic>? message;
      for (final candidate in list) {
        if (candidate.int64('id') == messageId) message = candidate;
      }
      if (message == null) return null;
      final doc = message.obj('content')?.obj('document')?.obj('document');
      final fileId = doc?.int64('id');
      if (fileId == null || fileId == 0) return null;
      final file = await _client.query(
        {
          '@type': 'downloadFile',
          'file_id': fileId,
          'priority': 32,
          'offset': 0,
          'limit': 0,
          'synchronous': true,
        },
        timeout: const Duration(minutes: 10),
      );
      final local = file.obj('local');
      final path = local?.str('path');
      final done = local?.boolean('is_downloading_completed') == true;
      if (!done || path == null || path.isEmpty) return null;
      final src = File(path);
      if (!await src.exists()) return null;
      final dst = File(destPath);
      await dst.parent.create(recursive: true);
      await src.copy(destPath);
      return await dst.length();
    } catch (error) {
      debugPrint(
        '[emoji_channel_source] font download failed '
        'type=${error.runtimeType}',
      );
      return null;
    }
  }
}
