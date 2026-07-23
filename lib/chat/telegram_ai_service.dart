import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

typedef TelegramAiQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

@immutable
class TelegramAiFormattedText {
  const TelegramAiFormattedText({required this.text, this.entities = const []});

  final String text;
  final List<Map<String, dynamic>> entities;

  Map<String, dynamic> toTdJson() => {
    '@type': 'formattedText',
    'text': text,
    'entities': entities,
  };

  static TelegramAiFormattedText fromTdJson(Map<String, dynamic> value) =>
      TelegramAiFormattedText(
        text: value.str('text') ?? '',
        entities: value.objects('entities') ?? const [],
      );
}

@immutable
class TelegramAiStyle {
  const TelegramAiStyle({
    required this.name,
    required this.title,
    required this.customEmojiId,
    required this.isCustom,
    required this.isCreator,
    required this.installCount,
    required this.prompt,
    required this.creatorUserId,
  });

  final String name;
  final String title;
  final int customEmojiId;
  final bool isCustom;
  final bool isCreator;
  final int installCount;
  final String prompt;
  final int creatorUserId;

  static TelegramAiStyle fromTdJson(Map<String, dynamic> value) =>
      TelegramAiStyle(
        name: value.str('name') ?? '',
        title: value.str('title') ?? value.str('name') ?? '',
        customEmojiId: value.int64('custom_emoji_id') ?? 0,
        isCustom: value.boolean('is_custom') ?? false,
        isCreator: value.boolean('is_creator') ?? false,
        installCount: value.integer('install_count') ?? 0,
        prompt: value.str('prompt') ?? '',
        creatorUserId: value.int64('creator_user_id') ?? 0,
      );
}

@immutable
class TelegramAiCapabilities {
  const TelegramAiCapabilities({
    required this.tdlibVersion,
    required this.compositionSupported,
    required this.customStylesSupported,
    required this.summarySupported,
    required this.transcriptionSupported,
    required this.styleTitleMax,
    required this.stylePromptMax,
    required this.addedStyleCountMax,
  });

  final String tdlibVersion;
  final bool compositionSupported;
  final bool customStylesSupported;
  final bool summarySupported;
  final bool transcriptionSupported;
  final int styleTitleMax;
  final int stylePromptMax;
  final int addedStyleCountMax;
}

class TelegramAiPremiumRequired implements Exception {
  const TelegramAiPremiumRequired();

  @override
  String toString() => 'Telegram Premium is required for more AI requests.';
}

Map<String, dynamic> buildComposeTextWithAiRequest({
  required TelegramAiFormattedText text,
  String translateToLanguageCode = '',
  String styleName = '',
  bool addEmojis = false,
}) => {
  '@type': 'composeTextWithAi',
  'text': text.toTdJson(),
  'translate_to_language_code': translateToLanguageCode,
  'style_name': styleName,
  'add_emojis': addEmojis,
};

Map<String, dynamic> buildSummarizeMessageRequest({
  required int chatId,
  required int messageId,
  String translateToLanguageCode = '',
  String tone = 'neutral',
}) => {
  '@type': 'summarizeMessage',
  'chat_id': chatId,
  'message_id': messageId,
  'translate_to_language_code': translateToLanguageCode,
  'tone': tone,
};

class TelegramAiService extends ChangeNotifier {
  TelegramAiService({TdClient? client, this.queryOverride})
    : _client = client ?? TdClient.shared {
    _applyStylesUpdate(_client.latestTextCompositionStylesUpdate);
    _subscription = _client.subscribe().listen((update) {
      if (update.type == 'updateTextCompositionStyles') {
        _applyStylesUpdate(update);
      }
    });
  }

  final TdClient _client;
  @visibleForTesting
  final TelegramAiQuery? queryOverride;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  List<TelegramAiStyle> _styles = const [];
  TelegramAiCapabilities? _capabilities;
  Future<TelegramAiCapabilities>? _capabilitiesRequest;

  List<TelegramAiStyle> get styles => _styles;
  TelegramAiCapabilities? get capabilitiesSnapshot => _capabilities;

  void _applyStylesUpdate(Map<String, dynamic>? update) {
    if (update == null) return;
    _styles = (update.objects('styles') ?? const [])
        .map(TelegramAiStyle.fromTdJson)
        .where((style) => style.name.isNotEmpty)
        .toList(growable: false);
    notifyListeners();
  }

  void _upsertStyle(TelegramAiStyle style) {
    final index = _styles.indexWhere((item) => item.name == style.name);
    if (index < 0) {
      _styles = [style, ..._styles];
    } else {
      final updated = List<TelegramAiStyle>.of(_styles);
      updated[index] = style;
      _styles = updated;
    }
    notifyListeners();
  }

  void _removeLocalStyle(String name) {
    final updated = _styles.where((item) => item.name != name).toList();
    if (updated.length == _styles.length) return;
    _styles = updated;
    notifyListeners();
  }

  Future<TelegramAiCapabilities> capabilities() async {
    final cached = _capabilities;
    if (cached != null) return cached;
    final pending = _capabilitiesRequest;
    if (pending != null) return pending;
    final request = _loadCapabilities();
    _capabilitiesRequest = request;
    try {
      final loaded = await request;
      _capabilities = loaded;
      notifyListeners();
      return loaded;
    } finally {
      _capabilitiesRequest = null;
    }
  }

  Future<TelegramAiCapabilities> _loadCapabilities() async {
    final values = await Future.wait([
      _option('version'),
      _option('text_composition_style_title_length_max'),
      _option('text_composition_style_prompt_length_max'),
      _option('added_text_composition_style_count_max'),
      _option('speech_recognition_trial_weekly_count'),
    ]);
    final version = _optionString(values[0]);
    final titleMax = _optionInt(values[1]);
    final promptMax = _optionInt(values[2]);
    final styleCountMax = _optionInt(values[3]);
    final transcriptionTrial = _optionInt(values[4]);
    final composition = promptMax > 0 || _styles.isNotEmpty;
    return TelegramAiCapabilities(
      tdlibVersion: version,
      compositionSupported: composition,
      customStylesSupported: titleMax > 0 && promptMax > 0,
      summarySupported: composition,
      transcriptionSupported: transcriptionTrial >= 0,
      styleTitleMax: titleMax > 0 ? titleMax : 64,
      stylePromptMax: promptMax > 0 ? promptMax : 1024,
      addedStyleCountMax: styleCountMax,
    );
  }

  Future<Map<String, dynamic>> _option(String name) async {
    try {
      return await _queryTd({'@type': 'getOption', 'name': name});
    } catch (_) {
      return const {'@type': 'optionValueEmpty'};
    }
  }

  String _optionString(Map<String, dynamic> value) => value.str('value') ?? '';

  int _optionInt(Map<String, dynamic> value) =>
      value.integer('value') ?? value.int64('value') ?? -1;

  Future<TelegramAiFormattedText> compose({
    required TelegramAiFormattedText text,
    bool proofread = false,
    String translateToLanguageCode = '',
    String styleName = '',
    bool addEmojis = false,
  }) async {
    var current = text;
    if (proofread) current = await fix(current);
    if (translateToLanguageCode.isEmpty && styleName.isEmpty && !addEmojis) {
      return current;
    }
    return _formatted(
      buildComposeTextWithAiRequest(
        text: current,
        translateToLanguageCode: translateToLanguageCode,
        styleName: styleName,
        addEmojis: addEmojis,
      ),
    );
  }

  Future<TelegramAiFormattedText> fix(TelegramAiFormattedText text) async {
    final response = await _queryAi({
      '@type': 'fixTextWithAi',
      'text': text.toTdJson(),
    });
    final result = response.obj('text') ?? response;
    return TelegramAiFormattedText.fromTdJson(result);
  }

  Future<TelegramAiFormattedText> summarize({
    required int chatId,
    required int messageId,
    String translateToLanguageCode = '',
    String tone = 'neutral',
  }) => _formatted(
    buildSummarizeMessageRequest(
      chatId: chatId,
      messageId: messageId,
      translateToLanguageCode: translateToLanguageCode,
      tone: tone,
    ),
  );

  Future<TelegramAiStyle> createStyle({
    required String title,
    required String prompt,
    int customEmojiId = 0,
    bool showCreator = false,
  }) async {
    final style = TelegramAiStyle.fromTdJson(
      await _queryAi({
        '@type': 'createTextCompositionStyle',
        'title': title,
        'custom_emoji_id': customEmojiId,
        'prompt': prompt,
        'show_creator': showCreator,
      }),
    );
    _upsertStyle(style);
    return style;
  }

  Future<TelegramAiStyle> editStyle({
    required String name,
    required String title,
    required String prompt,
    int customEmojiId = 0,
    bool showCreator = false,
  }) async {
    final style = TelegramAiStyle.fromTdJson(
      await _queryAi({
        '@type': 'editTextCompositionStyle',
        'name': name,
        'title': title,
        'custom_emoji_id': customEmojiId,
        'prompt': prompt,
        'show_creator': showCreator,
      }),
    );
    _upsertStyle(style);
    return style;
  }

  Future<void> deleteStyle(String name) async {
    await _ok({'@type': 'deleteTextCompositionStyle', 'name': name});
    _removeLocalStyle(name);
  }

  Future<TelegramAiStyle> searchStyle(String name) async =>
      TelegramAiStyle.fromTdJson(
        await _queryAi({'@type': 'searchTextCompositionStyle', 'name': name}),
      );

  Future<void> addStyle(String name, {TelegramAiStyle? style}) async {
    await _ok({'@type': 'addTextCompositionStyle', 'name': name});
    if (style != null) _upsertStyle(style);
  }

  Future<void> removeStyle(String name) async {
    await _ok({'@type': 'removeTextCompositionStyle', 'name': name});
    _removeLocalStyle(name);
  }

  Future<TelegramAiFormattedText> _formatted(
    Map<String, dynamic> request,
  ) async => TelegramAiFormattedText.fromTdJson(await _queryAi(request));

  Future<void> _ok(Map<String, dynamic> request) async {
    await _queryAi(request);
  }

  Future<Map<String, dynamic>> _queryAi(Map<String, dynamic> request) async {
    try {
      return await _queryTd(request);
    } on TdError catch (error) {
      if (error.message.contains('AICOMPOSE_FLOOD_PREMIUM') ||
          error.message.contains('TONES_SAVED_TOO_MANY')) {
        throw const TelegramAiPremiumRequired();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _queryTd(Map<String, dynamic> request) =>
      queryOverride?.call(request) ?? _client.query(request);

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
