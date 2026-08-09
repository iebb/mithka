import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

class BotApiFileRecord {
  const BotApiFileRecord({
    required this.id,
    required this.botFileId,
    required this.uniqueId,
    required this.size,
    required this.localPath,
    required this.remotePath,
  });

  final int id;
  final String botFileId;
  final String uniqueId;
  final int size;
  final String localPath;
  final String remotePath;
}

/// Per-account on-device history used by the TD-compatible Bot API backend.
///
/// Telegram bots cannot fetch historical messages. Every received update is
/// therefore committed here before its getUpdates offset is advanced.
class BotApiStore {
  BotApiStore(this.path);

  final String path;
  Database? _database;

  Database get _db {
    final database = _database;
    if (database == null) throw StateError('Bot API history is not open.');
    return database;
  }

  Future<void> open() async {
    if (_database != null) return;
    await File(path).parent.create(recursive: true);
    final database = sqlite3.open(path);
    database.execute('PRAGMA journal_mode = WAL');
    database.execute('PRAGMA synchronous = FULL');
    database.execute('PRAGMA foreign_keys = ON');
    database.execute('''
      CREATE TABLE IF NOT EXISTS metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS raw_updates (
        update_id INTEGER PRIMARY KEY,
        received_at INTEGER NOT NULL,
        payload_json TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS users (
        user_id INTEGER PRIMARY KEY,
        updated_at INTEGER NOT NULL,
        td_json TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS chats (
        chat_id INTEGER PRIMARY KEY,
        last_message_date INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        td_json TEXT NOT NULL
      )
    ''');
    database.execute('''
      CREATE INDEX IF NOT EXISTS chats_last_message_date
      ON chats(last_message_date DESC, chat_id DESC)
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        chat_id INTEGER NOT NULL,
        message_id INTEGER NOT NULL,
        message_date INTEGER NOT NULL,
        sender_id INTEGER NOT NULL DEFAULT 0,
        content_type TEXT NOT NULL,
        search_text TEXT NOT NULL,
        td_json TEXT NOT NULL,
        PRIMARY KEY (chat_id, message_id)
      )
    ''');
    database.execute('''
      CREATE INDEX IF NOT EXISTS messages_history
      ON messages(chat_id, message_date DESC, message_id DESC)
    ''');
    database.execute('''
      CREATE INDEX IF NOT EXISTS messages_sender
      ON messages(chat_id, sender_id, message_date DESC, message_id DESC)
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS files (
        file_id INTEGER PRIMARY KEY AUTOINCREMENT,
        bot_file_id TEXT NOT NULL UNIQUE,
        unique_id TEXT NOT NULL DEFAULT '',
        size INTEGER NOT NULL DEFAULT 0,
        local_path TEXT NOT NULL DEFAULT '',
        remote_path TEXT NOT NULL DEFAULT ''
      )
    ''');
    database.execute('''
      CREATE TABLE IF NOT EXISTS polls (
        poll_id TEXT NOT NULL,
        chat_id INTEGER NOT NULL,
        message_id INTEGER NOT NULL,
        PRIMARY KEY (poll_id, chat_id, message_id)
      )
    ''');
    _database = database;
  }

  void close() {
    _database?.close();
    _database = null;
  }

  T transaction<T>(T Function() action) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  int get nextUpdateOffset =>
      int.tryParse(metadata('next_update_offset') ?? '') ?? 0;

  String? metadata(String key) {
    final rows = _db.select(
      'SELECT value FROM metadata WHERE key = ? LIMIT 1',
      [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  void setMetadata(String key, String value) {
    _db.execute(
      '''
      INSERT INTO metadata(key, value) VALUES(?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value
      ''',
      [key, value],
    );
  }

  void saveRawUpdate(int updateId, Map<String, dynamic> update) {
    _db.execute(
      '''
      INSERT OR IGNORE INTO raw_updates(update_id, received_at, payload_json)
      VALUES(?, ?, ?)
      ''',
      [updateId, DateTime.now().millisecondsSinceEpoch, jsonEncode(update)],
    );
  }

  bool hasRawUpdate(int updateId) {
    final rows = _db.select(
      'SELECT 1 FROM raw_updates WHERE update_id = ? LIMIT 1',
      [updateId],
    );
    return rows.isNotEmpty;
  }

  /// Returns the original Bot API payloads for one-time compatibility
  /// migrations. Normal history reads continue to use the converted tables.
  List<Map<String, dynamic>> rawUpdates() => [
    for (final row in _db.select(
      'SELECT payload_json FROM raw_updates ORDER BY update_id',
    ))
      ?_decodeJson(row['payload_json']),
  ];

  void upsertUser(Map<String, dynamic> user) {
    final id = _int(user['id']);
    if (id == null) return;
    _db.execute(
      '''
      INSERT INTO users(user_id, updated_at, td_json) VALUES(?, ?, ?)
      ON CONFLICT(user_id) DO UPDATE SET
        updated_at = excluded.updated_at,
        td_json = excluded.td_json
      ''',
      [id, DateTime.now().millisecondsSinceEpoch, jsonEncode(user)],
    );
  }

  void upsertChat(Map<String, dynamic> chat) {
    final id = _int(chat['id']);
    if (id == null) return;
    final lastDate = _int((chat['last_message'] as Map?)?['date']) ?? 0;
    _db.execute(
      '''
      INSERT INTO chats(chat_id, last_message_date, updated_at, td_json)
      VALUES(?, ?, ?, ?)
      ON CONFLICT(chat_id) DO UPDATE SET
        last_message_date = excluded.last_message_date,
        updated_at = excluded.updated_at,
        td_json = excluded.td_json
      ''',
      [id, lastDate, DateTime.now().millisecondsSinceEpoch, jsonEncode(chat)],
    );
  }

  void upsertMessage(Map<String, dynamic> message) {
    final chatId = _int(message['chat_id']);
    final messageId = _int(message['id']);
    if (chatId == null || messageId == null) return;
    final content = message['content'];
    final contentMap = content is Map
        ? Map<String, dynamic>.from(content)
        : null;
    _db.execute(
      '''
      INSERT INTO messages(
        chat_id, message_id, message_date, sender_id, content_type,
        search_text, td_json
      ) VALUES(?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(chat_id, message_id) DO UPDATE SET
        message_date = excluded.message_date,
        sender_id = excluded.sender_id,
        content_type = excluded.content_type,
        search_text = excluded.search_text,
        td_json = excluded.td_json
      ''',
      [
        chatId,
        messageId,
        _int(message['date']) ?? 0,
        _senderId(message['sender_id']),
        contentMap?['@type'] as String? ?? '',
        _searchText(contentMap),
        jsonEncode(message),
      ],
    );
    final pollId = _pollId(contentMap);
    if (pollId != null) {
      _db.execute(
        'INSERT OR IGNORE INTO polls(poll_id, chat_id, message_id) VALUES(?, ?, ?)',
        [pollId, chatId, messageId],
      );
    }
  }

  Map<String, dynamic>? user(int userId) =>
      _oneJson('SELECT td_json FROM users WHERE user_id = ? LIMIT 1', [userId]);

  List<Map<String, dynamic>> users({int limit = 1000}) => _jsonRows(
    'SELECT td_json FROM users ORDER BY updated_at DESC LIMIT ?',
    [limit.clamp(1, 5000)],
  );

  Map<String, dynamic>? chat(int chatId) =>
      _oneJson('SELECT td_json FROM chats WHERE chat_id = ? LIMIT 1', [chatId]);

  Map<String, dynamic>? message(int chatId, int messageId) => _oneJson(
    '''
    SELECT td_json FROM messages
    WHERE chat_id = ? AND message_id = ? LIMIT 1
    ''',
    [chatId, messageId],
  );

  Map<String, dynamic>? latestMessage(int chatId) => _oneJson(
    '''
    SELECT td_json FROM messages WHERE chat_id = ?
    ORDER BY message_date DESC, message_id DESC LIMIT 1
    ''',
    [chatId],
  );

  List<Map<String, dynamic>> chats({int limit = 100}) => _jsonRows(
    '''
    SELECT td_json FROM chats
    ORDER BY last_message_date DESC, chat_id DESC LIMIT ?
    ''',
    [limit.clamp(1, 1000)],
  );

  List<Map<String, dynamic>> history({
    required int chatId,
    required int fromMessageId,
    required int offset,
    required int limit,
  }) {
    var start = offset;
    if (fromMessageId != 0) {
      final rank = _db.select(
        '''
        WITH ordered AS (
          SELECT message_id,
                 ROW_NUMBER() OVER (
                   ORDER BY message_date DESC, message_id DESC
                 ) - 1 AS row_index
          FROM messages WHERE chat_id = ?
        )
        SELECT row_index FROM ordered WHERE message_id = ? LIMIT 1
        ''',
        [chatId, fromMessageId],
      );
      if (rank.isEmpty) return const [];
      start += _int(rank.first['row_index']) ?? 0;
    }
    start = start.clamp(0, 1 << 31);
    return _jsonRows(
      '''
      SELECT td_json FROM messages WHERE chat_id = ?
      ORDER BY message_date DESC, message_id DESC LIMIT ? OFFSET ?
      ''',
      [chatId, limit.clamp(1, 100), start],
    );
  }

  int messageCount(int chatId) {
    final result = _db.select(
      'SELECT COUNT(*) AS count FROM messages WHERE chat_id = ?',
      [chatId],
    );
    return result.isEmpty ? 0 : _int(result.first['count']) ?? 0;
  }

  List<Map<String, dynamic>> searchMessages({
    int? chatId,
    required String query,
    int? senderId,
    int fromMessageId = 0,
    int limit = 50,
    Set<String>? contentTypes,
  }) {
    final where = <String>[];
    final parameters = <Object?>[];
    if (chatId != null) {
      where.add('chat_id = ?');
      parameters.add(chatId);
    }
    final normalized = query.trim().toLowerCase();
    if (normalized.isNotEmpty) {
      where.add("LOWER(search_text) LIKE ? ESCAPE '\\'");
      parameters.add('%${_escapeLike(normalized)}%');
    }
    if (senderId != null) {
      where.add('sender_id = ?');
      parameters.add(senderId);
    }
    if (fromMessageId > 0) {
      where.add('message_id < ?');
      parameters.add(fromMessageId);
    }
    if (contentTypes != null && contentTypes.isNotEmpty) {
      where.add(
        'content_type IN (${List.filled(contentTypes.length, '?').join(', ')})',
      );
      parameters.addAll(contentTypes);
    }
    parameters.add(limit.clamp(1, 100));
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return _jsonRows('''
      SELECT td_json FROM messages $clause
      ORDER BY message_date DESC, message_id DESC LIMIT ?
      ''', parameters);
  }

  void deleteMessages(int chatId, Iterable<int> messageIds) {
    final ids = messageIds.toSet().toList();
    if (ids.isEmpty) return;
    _db.execute(
      '''
      DELETE FROM messages WHERE chat_id = ?
      AND message_id IN (${List.filled(ids.length, '?').join(', ')})
      ''',
      [chatId, ...ids],
    );
    _db.execute(
      '''
      DELETE FROM polls WHERE chat_id = ?
      AND message_id IN (${List.filled(ids.length, '?').join(', ')})
      ''',
      [chatId, ...ids],
    );
  }

  List<Map<String, dynamic>> messagesForPoll(String pollId) {
    final rows = _db.select(
      '''
      SELECT messages.td_json FROM polls
      JOIN messages USING(chat_id, message_id)
      WHERE polls.poll_id = ?
      ''',
      [pollId],
    );
    return _decodeRows(rows);
  }

  BotApiFileRecord registerFile({
    required String botFileId,
    String uniqueId = '',
    int size = 0,
  }) {
    final existing = fileByBotId(botFileId);
    if (existing != null) {
      if (uniqueId.isNotEmpty || size > existing.size) {
        _db.execute(
          '''
          UPDATE files SET
            unique_id = CASE WHEN ? = '' THEN unique_id ELSE ? END,
            size = MAX(size, ?)
          WHERE file_id = ?
          ''',
          [uniqueId, uniqueId, size, existing.id],
        );
      }
      return file(existing.id)!;
    }
    _db.execute(
      'INSERT INTO files(bot_file_id, unique_id, size) VALUES(?, ?, ?)',
      [botFileId, uniqueId, size],
    );
    return file(_db.lastInsertRowId)!;
  }

  BotApiFileRecord? file(int id) {
    final rows = _db.select('SELECT * FROM files WHERE file_id = ? LIMIT 1', [
      id,
    ]);
    return rows.isEmpty ? null : _fileFromRow(rows.first);
  }

  BotApiFileRecord? fileByBotId(String botFileId) {
    final rows = _db.select(
      'SELECT * FROM files WHERE bot_file_id = ? LIMIT 1',
      [botFileId],
    );
    return rows.isEmpty ? null : _fileFromRow(rows.first);
  }

  void updateFile({
    required int id,
    String? remotePath,
    String? localPath,
    int? size,
  }) {
    final current = file(id);
    if (current == null) return;
    _db.execute(
      '''
      UPDATE files SET remote_path = ?, local_path = ?, size = ?
      WHERE file_id = ?
      ''',
      [
        remotePath ?? current.remotePath,
        localPath ?? current.localPath,
        size ?? current.size,
        id,
      ],
    );
  }

  Map<String, dynamic>? _oneJson(String sql, List<Object?> parameters) {
    final rows = _db.select(sql, parameters);
    if (rows.isEmpty) return null;
    return _decodeJson(rows.first['td_json']);
  }

  List<Map<String, dynamic>> _jsonRows(String sql, List<Object?> parameters) =>
      _decodeRows(_db.select(sql, parameters));

  List<Map<String, dynamic>> _decodeRows(ResultSet rows) => [
    for (final row in rows) ?_decodeJson(row['td_json']),
  ];

  Map<String, dynamic>? _decodeJson(Object? value) {
    if (value is! String) return null;
    final decoded = jsonDecode(value);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  BotApiFileRecord _fileFromRow(Row row) => BotApiFileRecord(
    id: _int(row['file_id']) ?? 0,
    botFileId: row['bot_file_id'] as String? ?? '',
    uniqueId: row['unique_id'] as String? ?? '',
    size: _int(row['size']) ?? 0,
    localPath: row['local_path'] as String? ?? '',
    remotePath: row['remote_path'] as String? ?? '',
  );
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

int _senderId(Object? value) {
  if (value is! Map) return 0;
  return _int(value['user_id']) ?? _int(value['chat_id']) ?? 0;
}

String _searchText(Map<String, dynamic>? content) {
  if (content == null) return '';
  final text = content['text'];
  if (text is Map && text['text'] is String) return text['text'] as String;
  final caption = content['caption'];
  if (caption is Map && caption['text'] is String) {
    return caption['text'] as String;
  }
  final poll = content['poll'];
  if (poll is Map) {
    final question = poll['question'];
    if (question is Map && question['text'] is String) {
      return question['text'] as String;
    }
  }
  final contact = content['contact'];
  if (contact is Map) {
    return [
      contact['first_name'],
      contact['last_name'],
      contact['phone_number'],
    ].whereType<String>().join(' ');
  }
  return '';
}

String? _pollId(Map<String, dynamic>? content) {
  final poll = content?['poll'];
  if (poll is! Map) return null;
  final botApiId = poll['bot_api_id'];
  if (botApiId is String && botApiId.isNotEmpty) return botApiId;
  final id = poll['id'];
  return id == null ? null : '$id';
}

String _escapeLike(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('%', '\\%')
    .replaceAll('_', '\\_');
