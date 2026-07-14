import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

typedef MusicPlaylistQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);
typedef MusicPlaylistFolderUpdate = Map<String, dynamic>? Function();

class MusicPlaylist {
  const MusicPlaylist({
    required this.chatId,
    required this.title,
    this.tracks = const [],
  });

  final int chatId;
  final String title;
  final List<ChatMessage> tracks;

  MusicPlaylist copyWith({List<ChatMessage>? tracks}) => MusicPlaylist(
    chatId: chatId,
    title: title,
    tracks: tracks ?? this.tracks,
  );
}

/// Stores playlists as Telegram chats inside a dedicated `_Playlist` folder.
/// Tracks are ordinary audio messages, so the library follows the account and
/// can be inspected or recovered without Mithka-specific local state.
class MusicPlaylistService {
  MusicPlaylistService({
    MusicPlaylistQuery? query,
    MusicPlaylistFolderUpdate? folderUpdate,
  }) : _query = query ?? TdClient.shared.query,
       _folderUpdate =
           folderUpdate ?? (() => TdClient.shared.latestChatFoldersUpdate);

  static const folderTitle = '_Playlist';

  final MusicPlaylistQuery _query;
  final MusicPlaylistFolderUpdate _folderUpdate;

  Future<List<MusicPlaylist>> loadPlaylists() async {
    final folder = await _findFolder();
    if (folder == null) return const [];
    final chatIds = folder.int64Array('included_chat_ids') ?? const <int>[];
    final playlists = await Future.wait(
      chatIds.map((chatId) async {
        try {
          final chat = await _query({'@type': 'getChat', 'chat_id': chatId});
          return MusicPlaylist(
            chatId: chatId,
            title: chat.str('title')?.trim().isNotEmpty == true
                ? chat.str('title')!.trim()
                : 'Playlist',
            tracks: await loadTracks(chatId),
          );
        } catch (_) {
          return null;
        }
      }),
    );
    return playlists.whereType<MusicPlaylist>().toList(growable: false);
  }

  Future<MusicPlaylist> createPlaylist(String title) async {
    final normalized = title.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
    final chat = await _query({
      '@type': 'createNewSupergroupChat',
      'title': normalized,
      'is_forum': false,
      'is_channel': false,
      'description': '',
      'location': null,
      'message_auto_delete_time': 0,
      'for_import': false,
    });
    final chatId = chat.int64('id') ?? chat.int64('chat_id');
    if (chatId == null) {
      throw const FormatException('TDLib did not return a playlist chat');
    }
    await _includeChatInFolder(chatId);
    return MusicPlaylist(chatId: chatId, title: normalized);
  }

  Future<ChatMessage> addTrack(
    MusicPlaylist playlist,
    ChatMessage source,
  ) async {
    final music = source.music;
    final sourceChatId = source.chatId;
    if (music?.file == null) {
      throw const FormatException('Message has no playable audio');
    }
    if (sourceChatId == null || sourceChatId == 0 || source.id == 0) {
      throw const FormatException('Message has no Telegram source');
    }
    final sent = await _query({
      '@type': 'forwardMessages',
      'chat_id': playlist.chatId,
      'from_chat_id': sourceChatId,
      'message_ids': [source.id],
      'options': {'@type': 'messageSendOptions'},
      'send_copy': true,
      'remove_caption': false,
    });
    final parsed = (sent.objects('messages') ?? const [])
        .map(TDParse.message)
        .whereType<ChatMessage>()
        .firstOrNull;
    if (parsed?.music?.file == null) {
      throw const FormatException('TDLib did not return the playlist track');
    }
    return parsed!;
  }

  Future<void> removeTrack(MusicPlaylist playlist, ChatMessage track) async {
    if (track.id == 0) return;
    await _query({
      '@type': 'deleteMessages',
      'chat_id': playlist.chatId,
      'message_ids': [track.id],
      'revoke': true,
    });
  }

  Future<List<ChatMessage>> loadTracks(int chatId) async {
    final result = <ChatMessage>[];
    var fromMessageId = 0;
    for (var page = 0; page < 10; page++) {
      final response = await _query({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': '',
        'sender_id': null,
        'from_message_id': fromMessageId,
        'offset': 0,
        'limit': 100,
        'filter': {'@type': 'searchMessagesFilterAudio'},
      });
      final messages = (response.objects('messages') ?? const [])
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .toList();
      if (messages.isEmpty) break;
      result.addAll(messages);
      final oldestId = messages
          .map((message) => message.id)
          .reduce((a, b) => a < b ? a : b);
      if (messages.length < 100 || oldestId == fromMessageId) break;
      fromMessageId = oldestId;
    }
    final seen = <int>{};
    final unique = result.where((message) => seen.add(message.id)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return unique;
  }

  Future<Map<String, dynamic>?> _findFolder() async {
    final response = _folderUpdate();
    if (response == null) return null;
    final infos =
        response.objects('chat_folders') ??
        response.objects('chat_folder_infos') ??
        const <Map<String, dynamic>>[];
    for (final info in infos) {
      if (_title(info) != folderTitle) continue;
      final id = info.integer('id') ?? info.integer('chat_folder_id');
      if (id == null) continue;
      final folder = await _query({
        '@type': 'getChatFolder',
        'chat_folder_id': id,
      });
      return {...folder, '_folder_id': id};
    }
    return null;
  }

  Future<void> _includeChatInFolder(int chatId) async {
    var folder = await _findFolder();
    if (folder == null) {
      await _query({
        '@type': 'createChatFolder',
        'folder': _folderPayload(const {}, includedChatIds: {chatId}),
      });
      return;
    }
    final folderId =
        folder.integer('_folder_id') ??
        folder.integer('id') ??
        folder.integer('chat_folder_id');
    if (folderId == null) {
      final folders = _folderUpdate();
      if (folders == null) {
        throw const FormatException('Playlist folder list is unavailable');
      }
      Map<String, dynamic>? info;
      for (final item in folders.objects('chat_folders') ?? const []) {
        if (_title(item) == folderTitle) {
          info = item;
          break;
        }
      }
      final resolvedId = info?.integer('id') ?? info?.integer('chat_folder_id');
      if (resolvedId == null) {
        throw const FormatException('Playlist folder has no identifier');
      }
      folder = await _query({
        '@type': 'getChatFolder',
        'chat_folder_id': resolvedId,
      });
      await _editFolder(resolvedId, folder, chatId);
      return;
    }
    await _editFolder(folderId, folder, chatId);
  }

  Future<void> _editFolder(
    int folderId,
    Map<String, dynamic> folder,
    int chatId,
  ) async {
    final included =
        (folder.int64Array('included_chat_ids') ?? const <int>[]).toSet()
          ..add(chatId);
    await _query({
      '@type': 'editChatFolder',
      'chat_folder_id': folderId,
      'folder': _folderPayload(folder, includedChatIds: included),
    });
  }

  static Map<String, dynamic> _folderPayload(
    Map<String, dynamic> folder, {
    required Set<int> includedChatIds,
  }) {
    final title = _title(folder).isEmpty ? folderTitle : _title(folder);
    final existingName = folder.obj('name');
    return {
      '@type': 'chatFolder',
      'name': {
        '@type': 'chatFolderName',
        'text': {
          '@type': 'formattedText',
          'text': title,
          'entities':
              existingName?.obj('text')?.objects('entities') ?? const [],
        },
        'animate_custom_emoji':
            existingName?.boolean('animate_custom_emoji') ?? false,
      },
      if (folder.obj('icon') != null) 'icon': folder.obj('icon'),
      'color_id': folder.integer('color_id') ?? -1,
      'is_shareable': false,
      'pinned_chat_ids': folder.int64Array('pinned_chat_ids') ?? const <int>[],
      'included_chat_ids': includedChatIds.toList()..sort(),
      'excluded_chat_ids':
          folder.int64Array('excluded_chat_ids') ?? const <int>[],
      'exclude_muted': folder.boolean('exclude_muted') ?? false,
      'exclude_read': folder.boolean('exclude_read') ?? false,
      'exclude_archived': folder.boolean('exclude_archived') ?? false,
      'include_contacts': false,
      'include_non_contacts': false,
      'include_bots': false,
      'include_groups': false,
      'include_channels': false,
    };
  }

  static String _title(Map<String, dynamic> object) =>
      object.str('title') ??
      object.obj('title')?.str('text') ??
      object.obj('name')?.obj('text')?.str('text') ??
      object.str('name') ??
      '';
}
