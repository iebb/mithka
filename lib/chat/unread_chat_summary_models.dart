import 'package:flutter/foundation.dart';

@immutable
class UnreadChatRangeSnapshot {
  const UnreadChatRangeSnapshot({
    required this.chatId,
    required this.accountSlot,
    required this.lastReadInboxId,
    required this.unreadCount,
    required this.upperMessageId,
    required this.capturedAt,
  }) : assert(chatId != 0),
       assert(accountSlot >= 0),
       assert(lastReadInboxId >= 0),
       assert(unreadCount >= 0),
       assert(upperMessageId >= 0);

  final int chatId;
  final int accountSlot;
  final int lastReadInboxId;
  final int unreadCount;
  final int upperMessageId;
  final DateTime capturedAt;

  bool get hasUnreadRange =>
      unreadCount > 0 && upperMessageId > lastReadInboxId;

  Map<String, Object?> toJson() => {
    'chat_id': chatId,
    'account_slot': accountSlot,
    'last_read_inbox_id': lastReadInboxId,
    'unread_count': unreadCount,
    'upper_message_id': upperMessageId,
    'captured_at': capturedAt.toUtc().toIso8601String(),
  };
}

@immutable
class UnreadChatMessage {
  const UnreadChatMessage({
    required this.id,
    required this.date,
    required this.senderKey,
    required this.isOutgoing,
    required this.isService,
    required this.contentType,
    required this.text,
    this.replyToMessageId,
  }) : assert(id > 0);

  final int id;
  final int date;
  final String senderKey;
  final bool isOutgoing;
  final bool isService;
  final String contentType;
  final String text;
  final int? replyToMessageId;

  String get evidenceId => 'm$id';

  Map<String, Object?> toPromptJson() => {
    'evidence_id': evidenceId,
    'message_id': id,
    'date_unix': date,
    'sender_key': senderKey,
    'is_outgoing': isOutgoing,
    'is_service': isService,
    'content_type': contentType,
    if (replyToMessageId case final replyId?)
      'reply_to_evidence_id': 'm$replyId',
    'text': text,
  };
}

@immutable
class UnreadChatTranscript {
  UnreadChatTranscript({
    required this.snapshot,
    required Iterable<UnreadChatMessage> messages,
    required this.historyRequestCount,
    required this.reachedReadBoundary,
    required this.historyCapped,
    required this.historyStalled,
  }) : messages = List.unmodifiable(messages);

  final UnreadChatRangeSnapshot snapshot;
  final List<UnreadChatMessage> messages;
  final int historyRequestCount;
  final bool reachedReadBoundary;
  final bool historyCapped;
  final bool historyStalled;

  int get fetchedUnreadMessageCount => messages
      .where((message) => !message.isOutgoing && !message.isService)
      .length;

  Set<String> get evidenceIds => {
    for (final message in messages) message.evidenceId,
  };
}

class UnreadChatSummaryFormatException implements Exception {
  const UnreadChatSummaryFormatException(this.message);

  final String message;

  @override
  String toString() => 'UnreadChatSummaryFormatException: $message';
}

@immutable
class UnreadChatSummaryItem {
  UnreadChatSummaryItem({
    required this.text,
    required Iterable<String> evidenceIds,
  }) : evidenceIds = List.unmodifiable(evidenceIds);

  final String text;
  final List<String> evidenceIds;

  Map<String, Object?> toJson() => {'text': text, 'evidence_ids': evidenceIds};
}

@immutable
class UnreadChatSummaryTopic {
  UnreadChatSummaryTopic({
    required this.title,
    required this.summary,
    required Iterable<String> evidenceIds,
    this.firstDate,
    this.lastDate,
  }) : evidenceIds = List.unmodifiable(evidenceIds);

  final String title;
  final String summary;
  final List<String> evidenceIds;
  final int? firstDate;
  final int? lastDate;

  UnreadChatSummaryTopic copyWith({int? firstDate, int? lastDate}) =>
      UnreadChatSummaryTopic(
        title: title,
        summary: summary,
        evidenceIds: evidenceIds,
        firstDate: firstDate ?? this.firstDate,
        lastDate: lastDate ?? this.lastDate,
      );

  Map<String, Object?> toJson() => {
    'title': title,
    'summary': summary,
    'evidence_ids': evidenceIds,
    'start_date_unix': ?firstDate,
    'end_date_unix': ?lastDate,
  };
}

@immutable
class UnreadChatSummaryContent {
  UnreadChatSummaryContent({
    this.title = '',
    required this.overview,
    required Iterable<String> overviewEvidenceIds,
    Iterable<UnreadChatSummaryTopic> topics = const [],
    this.rant,
    required Iterable<UnreadChatSummaryItem> highlights,
    required Iterable<UnreadChatSummaryItem> needsReply,
    required Iterable<UnreadChatSummaryItem> decisions,
    required Iterable<UnreadChatSummaryItem> actions,
    required Iterable<UnreadChatSummaryItem> questions,
    required Iterable<UnreadChatSummaryItem> uncertainties,
  }) : overviewEvidenceIds = List.unmodifiable(overviewEvidenceIds),
       topics = List.unmodifiable(topics),
       highlights = List.unmodifiable(highlights),
       needsReply = List.unmodifiable(needsReply),
       decisions = List.unmodifiable(decisions),
       actions = List.unmodifiable(actions),
       questions = List.unmodifiable(questions),
       uncertainties = List.unmodifiable(uncertainties);

  factory UnreadChatSummaryContent.empty() => UnreadChatSummaryContent(
    overview: '',
    overviewEvidenceIds: const [],
    highlights: const [],
    needsReply: const [],
    decisions: const [],
    actions: const [],
    questions: const [],
    uncertainties: const [],
  );

  factory UnreadChatSummaryContent.fromJson(
    Map<String, dynamic> value, {
    required Set<String> allowedEvidenceIds,
  }) {
    final overviewValue = value['overview'];
    late final String overview;
    late final List<String> overviewEvidenceIds;
    if (overviewValue is String) {
      overview = overviewValue.trim();
      overviewEvidenceIds = _parseEvidenceIds(
        value['overview_evidence_ids'] ?? value['overviewEvidenceIds'],
        field: 'overview_evidence_ids',
        allowedEvidenceIds: allowedEvidenceIds,
      );
    } else if (overviewValue is Map) {
      final overviewMap = Map<String, dynamic>.from(overviewValue);
      overview = _requiredText(overviewMap, 'overview');
      overviewEvidenceIds = _parseEvidenceIds(
        overviewMap['evidence_ids'] ?? overviewMap['evidenceIds'],
        field: 'overview.evidence_ids',
        allowedEvidenceIds: allowedEvidenceIds,
      );
    } else {
      throw const UnreadChatSummaryFormatException(
        'overview must be a string or object',
      );
    }
    _requireGrounding(
      text: overview,
      evidenceIds: overviewEvidenceIds,
      field: 'overview',
    );

    final title = value['title'] is String
        ? (value['title'] as String).trim()
        : '';
    _requireGrounding(
      text: title,
      evidenceIds: overviewEvidenceIds,
      field: 'title',
    );

    return UnreadChatSummaryContent(
      title: title,
      overview: overview,
      overviewEvidenceIds: overviewEvidenceIds,
      topics: _parseTopics(
        value['topics'],
        allowedEvidenceIds: allowedEvidenceIds,
      ),
      rant: _parseOptionalItem(
        value['rant'],
        field: 'rant',
        allowedEvidenceIds: allowedEvidenceIds,
      ),
      highlights: _parseItems(
        value['highlights'],
        field: 'highlights',
        allowedEvidenceIds: allowedEvidenceIds,
      ),
      needsReply: _parseItems(
        value['needs_reply'] ?? value['needsReply'],
        field: 'needs_reply',
        allowedEvidenceIds: allowedEvidenceIds,
      ),
      decisions: _parseItems(
        value['decisions'],
        field: 'decisions',
        allowedEvidenceIds: allowedEvidenceIds,
      ),
      actions: _parseItems(
        value['actions'],
        field: 'actions',
        allowedEvidenceIds: allowedEvidenceIds,
      ),
      questions: _parseItems(
        value['questions'],
        field: 'questions',
        allowedEvidenceIds: allowedEvidenceIds,
      ),
      uncertainties: _parseItems(
        value['uncertainties'],
        field: 'uncertainties',
        allowedEvidenceIds: allowedEvidenceIds,
      ),
    );
  }

  final String title;
  final String overview;
  final List<String> overviewEvidenceIds;
  final List<UnreadChatSummaryTopic> topics;
  final UnreadChatSummaryItem? rant;
  final List<UnreadChatSummaryItem> highlights;
  final List<UnreadChatSummaryItem> needsReply;
  final List<UnreadChatSummaryItem> decisions;
  final List<UnreadChatSummaryItem> actions;
  final List<UnreadChatSummaryItem> questions;
  final List<UnreadChatSummaryItem> uncertainties;

  Map<String, Object?> toJson() => {
    'title': title,
    'overview': overview,
    'overview_evidence_ids': overviewEvidenceIds,
    'topics': topics.map((topic) => topic.toJson()).toList(),
    'rant': rant?.toJson(),
    'highlights': highlights.map((item) => item.toJson()).toList(),
    'needs_reply': needsReply.map((item) => item.toJson()).toList(),
    'decisions': decisions.map((item) => item.toJson()).toList(),
    'actions': actions.map((item) => item.toJson()).toList(),
    'questions': questions.map((item) => item.toJson()).toList(),
    'uncertainties': uncertainties.map((item) => item.toJson()).toList(),
  };

  UnreadChatSummaryContent copyWith({
    String? title,
    String? overview,
    Iterable<String>? overviewEvidenceIds,
    Iterable<UnreadChatSummaryTopic>? topics,
    UnreadChatSummaryItem? rant,
    bool clearRant = false,
    Iterable<UnreadChatSummaryItem>? highlights,
    Iterable<UnreadChatSummaryItem>? needsReply,
    Iterable<UnreadChatSummaryItem>? decisions,
    Iterable<UnreadChatSummaryItem>? actions,
    Iterable<UnreadChatSummaryItem>? questions,
    Iterable<UnreadChatSummaryItem>? uncertainties,
  }) => UnreadChatSummaryContent(
    title: title ?? this.title,
    overview: overview ?? this.overview,
    overviewEvidenceIds: overviewEvidenceIds ?? this.overviewEvidenceIds,
    topics: topics ?? this.topics,
    rant: clearRant ? null : rant ?? this.rant,
    highlights: highlights ?? this.highlights,
    needsReply: needsReply ?? this.needsReply,
    decisions: decisions ?? this.decisions,
    actions: actions ?? this.actions,
    questions: questions ?? this.questions,
    uncertainties: uncertainties ?? this.uncertainties,
  );
}

@immutable
class UnreadChatSummaryCoverage {
  const UnreadChatSummaryCoverage({
    required this.expectedUnreadCount,
    required this.fetchedMessageCount,
    required this.fetchedUnreadMessageCount,
    required this.summarizedMessageCount,
    required this.summarizedUnreadMessageCount,
    required this.reachedReadBoundary,
    required this.historyCapped,
    required this.processingCapped,
    required this.historyStalled,
    this.failedRequestCount = 0,
  });

  final int expectedUnreadCount;
  final int fetchedMessageCount;
  final int fetchedUnreadMessageCount;
  final int summarizedMessageCount;
  final int summarizedUnreadMessageCount;
  final bool reachedReadBoundary;
  final bool historyCapped;
  final bool processingCapped;
  final bool historyStalled;
  final int failedRequestCount;

  bool get countMismatch => fetchedUnreadMessageCount < expectedUnreadCount;

  bool get complete =>
      reachedReadBoundary &&
      !historyCapped &&
      !processingCapped &&
      !historyStalled &&
      failedRequestCount == 0 &&
      !countMismatch;

  List<String> get limitations => [
    if (!reachedReadBoundary) 'read_boundary_not_reached',
    if (historyCapped) 'history_message_cap_reached',
    if (processingCapped) 'summary_chunk_cap_reached',
    if (historyStalled) 'history_pagination_stalled',
    if (failedRequestCount > 0) 'summary_partial_failure',
    if (countMismatch) 'unread_count_mismatch',
  ];

  Map<String, Object?> toJson() => {
    'expected_unread_count': expectedUnreadCount,
    'fetched_message_count': fetchedMessageCount,
    'fetched_unread_message_count': fetchedUnreadMessageCount,
    'summarized_message_count': summarizedMessageCount,
    'summarized_unread_message_count': summarizedUnreadMessageCount,
    'reached_read_boundary': reachedReadBoundary,
    'history_capped': historyCapped,
    'processing_capped': processingCapped,
    'history_stalled': historyStalled,
    'failed_request_count': failedRequestCount,
    'complete': complete,
    'limitations': limitations,
  };
}

@immutable
class UnreadChatSummary {
  const UnreadChatSummary({required this.content, required this.coverage});

  final UnreadChatSummaryContent content;
  final UnreadChatSummaryCoverage coverage;

  String get title => content.title;
  String get overview => content.overview;
  List<String> get overviewEvidenceIds => content.overviewEvidenceIds;
  List<UnreadChatSummaryTopic> get topics => content.topics;
  UnreadChatSummaryItem? get rant => content.rant;
  List<UnreadChatSummaryItem> get highlights => content.highlights;
  List<UnreadChatSummaryItem> get needsReply => content.needsReply;
  List<UnreadChatSummaryItem> get decisions => content.decisions;
  List<UnreadChatSummaryItem> get actions => content.actions;
  List<UnreadChatSummaryItem> get questions => content.questions;
  List<UnreadChatSummaryItem> get uncertainties => content.uncertainties;

  Map<String, Object?> toJson() => {
    ...content.toJson(),
    'coverage': coverage.toJson(),
  };
}

List<UnreadChatSummaryTopic> _parseTopics(
  Object? raw, {
  required Set<String> allowedEvidenceIds,
}) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const UnreadChatSummaryFormatException('topics must be an array');
  }
  return [
    for (var index = 0; index < raw.length; index++)
      _parseTopic(
        raw[index],
        field: 'topics[$index]',
        allowedEvidenceIds: allowedEvidenceIds,
      ),
  ];
}

UnreadChatSummaryTopic _parseTopic(
  Object? raw, {
  required String field,
  required Set<String> allowedEvidenceIds,
}) {
  if (raw is! Map) {
    throw UnreadChatSummaryFormatException('$field must be an object');
  }
  final value = Map<String, dynamic>.from(raw);
  final title = value['title'];
  if (title is! String || title.trim().isEmpty) {
    throw UnreadChatSummaryFormatException('$field has no title');
  }
  final summary = _requiredText(value, field);
  final evidenceIds = _parseEvidenceIds(
    value['evidence_ids'] ?? value['evidenceIds'],
    field: '$field.evidence_ids',
    allowedEvidenceIds: allowedEvidenceIds,
  );
  _requireGrounding(
    text: '${title.trim()} $summary',
    evidenceIds: evidenceIds,
    field: field,
  );
  return UnreadChatSummaryTopic(
    title: title.trim(),
    summary: summary,
    evidenceIds: evidenceIds,
    firstDate: _optionalUnixDate(value['start_date_unix']),
    lastDate: _optionalUnixDate(value['end_date_unix']),
  );
}

UnreadChatSummaryItem? _parseOptionalItem(
  Object? raw, {
  required String field,
  required Set<String> allowedEvidenceIds,
}) {
  if (raw == null) return null;
  return _parseItem(raw, field: field, allowedEvidenceIds: allowedEvidenceIds);
}

int? _optionalUnixDate(Object? raw) {
  if (raw is int && raw >= 0) return raw;
  if (raw is num && raw >= 0) return raw.toInt();
  return null;
}

String _requiredText(Map<String, dynamic> value, String field) {
  for (final key in const [
    'text',
    'summary',
    'request',
    'decision',
    'action',
    'question',
    'uncertainty',
  ]) {
    final candidate = value[key];
    if (candidate is String && candidate.trim().isNotEmpty) {
      return candidate.trim();
    }
  }
  throw UnreadChatSummaryFormatException('$field item has no text');
}

List<UnreadChatSummaryItem> _parseItems(
  Object? raw, {
  required String field,
  required Set<String> allowedEvidenceIds,
}) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw UnreadChatSummaryFormatException('$field must be an array');
  }
  return [
    for (var index = 0; index < raw.length; index++)
      _parseItem(
        raw[index],
        field: '$field[$index]',
        allowedEvidenceIds: allowedEvidenceIds,
      ),
  ];
}

UnreadChatSummaryItem _parseItem(
  Object? raw, {
  required String field,
  required Set<String> allowedEvidenceIds,
}) {
  if (raw is! Map) {
    throw UnreadChatSummaryFormatException('$field must be an object');
  }
  final value = Map<String, dynamic>.from(raw);
  final text = _requiredText(value, field);
  final evidenceIds = _parseEvidenceIds(
    value['evidence_ids'] ?? value['evidenceIds'],
    field: '$field.evidence_ids',
    allowedEvidenceIds: allowedEvidenceIds,
  );
  _requireGrounding(text: text, evidenceIds: evidenceIds, field: field);
  return UnreadChatSummaryItem(text: text, evidenceIds: evidenceIds);
}

List<String> _parseEvidenceIds(
  Object? raw, {
  required String field,
  required Set<String> allowedEvidenceIds,
}) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw UnreadChatSummaryFormatException('$field must be an array');
  }
  final result = <String>[];
  final seen = <String>{};
  for (final value in raw) {
    final id = switch (value) {
      final String stringValue => stringValue.trim(),
      final int intValue => 'm$intValue',
      _ => throw UnreadChatSummaryFormatException(
        '$field contains a non-string evidence ID',
      ),
    };
    if (!allowedEvidenceIds.contains(id)) {
      throw UnreadChatSummaryFormatException(
        '$field contains unknown evidence ID $id',
      );
    }
    if (seen.add(id)) result.add(id);
  }
  return result;
}

void _requireGrounding({
  required String text,
  required List<String> evidenceIds,
  required String field,
}) {
  if (text.isNotEmpty && evidenceIds.isEmpty) {
    throw UnreadChatSummaryFormatException('$field has no evidence IDs');
  }
}
