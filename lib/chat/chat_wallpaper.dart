import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_graphics/vector_graphics_compat.dart'
    show RenderingStrategy;

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

enum ChatWallpaperKind { preset, image, telegram, theme }

enum ChatThemeKind { emoji, gift }

@immutable
class ChatWallpaper {
  const ChatWallpaper._({
    required this.kind,
    this.presetId,
    this.imagePath,
    this.themeName,
    this.themeKind = ChatThemeKind.emoji,
    this.backgroundId = 0,
    this.fileId = 0,
    this.remoteType,
    this.mimeType,
    this.colors = const [],
    this.rotationAngle = 0,
    this.intensity = 0,
    this.isInverted = false,
    this.isBlurred = false,
    this.isMoving = false,
    this.isTiled = false,
    this.darkThemeDimming = 0,
  });

  const ChatWallpaper.preset(String presetId)
    : this._(kind: ChatWallpaperKind.preset, presetId: presetId);

  const ChatWallpaper.image(
    String imagePath, {
    bool isBlurred = false,
    bool isMoving = false,
  }) : this._(
         kind: ChatWallpaperKind.image,
         imagePath: imagePath,
         isBlurred: isBlurred,
         isMoving: isMoving,
       );

  const ChatWallpaper.theme(
    String themeName, {
    ChatThemeKind themeKind = ChatThemeKind.emoji,
  }) : this._(
         kind: ChatWallpaperKind.theme,
         themeName: themeName,
         themeKind: themeKind,
       );

  const ChatWallpaper.telegram({
    required int backgroundId,
    required String remoteType,
    int fileId = 0,
    String? imagePath,
    String? mimeType,
    String? themeName,
    List<int> colors = const [],
    int rotationAngle = 0,
    int intensity = 0,
    bool isInverted = false,
    bool isBlurred = false,
    bool isMoving = false,
    bool isTiled = false,
    int darkThemeDimming = 0,
  }) : this._(
         kind: ChatWallpaperKind.telegram,
         backgroundId: backgroundId,
         remoteType: remoteType,
         fileId: fileId,
         imagePath: imagePath,
         mimeType: mimeType,
         themeName: themeName,
         colors: colors,
         rotationAngle: rotationAngle,
         intensity: intensity,
         isInverted: isInverted,
         isBlurred: isBlurred,
         isMoving: isMoving,
         isTiled: isTiled,
         darkThemeDimming: darkThemeDimming,
       );

  final ChatWallpaperKind kind;
  final String? presetId;
  final String? imagePath;
  final String? themeName;
  final ChatThemeKind themeKind;
  final int backgroundId;
  final int fileId;
  final String? remoteType;
  final String? mimeType;
  final List<int> colors;
  final int rotationAngle;
  final int intensity;
  final bool isInverted;
  final bool isBlurred;
  final bool isMoving;
  final bool isTiled;
  final int darkThemeDimming;

  bool get isRemoteFile =>
      kind == ChatWallpaperKind.telegram &&
      (remoteType == 'wallpaper' || remoteType == 'pattern');

  bool get supportsBlur =>
      kind == ChatWallpaperKind.image ||
      (kind == ChatWallpaperKind.telegram && remoteType == 'wallpaper');

  bool get supportsMotion =>
      kind == ChatWallpaperKind.image ||
      (kind == ChatWallpaperKind.telegram &&
          (remoteType == 'wallpaper' || remoteType == 'pattern'));

  bool get supportsIntensity =>
      kind == ChatWallpaperKind.telegram && remoteType == 'pattern';

  ChatWallpaper withImagePath(String path) => ChatWallpaper.telegram(
    backgroundId: backgroundId,
    remoteType: remoteType ?? 'wallpaper',
    fileId: fileId,
    imagePath: path,
    mimeType: mimeType,
    themeName: themeName,
    colors: colors,
    rotationAngle: rotationAngle,
    intensity: intensity,
    isInverted: isInverted,
    isBlurred: isBlurred,
    isMoving: isMoving,
    isTiled: isTiled,
    darkThemeDimming: darkThemeDimming,
  );

  /// A fill-only representation for compact theme cards. Pattern documents
  /// are intentionally omitted so simply opening the picker doesn't download,
  /// decompress, or rasterize every Telegram pattern.
  ChatWallpaper withoutPatternDocument() => ChatWallpaper.telegram(
    backgroundId: backgroundId,
    remoteType: remoteType ?? 'pattern',
    themeName: themeName,
    colors: colors,
    rotationAngle: rotationAngle,
    intensity: intensity,
    isInverted: isInverted,
    isBlurred: isBlurred,
    isMoving: isMoving,
    isTiled: isTiled,
    darkThemeDimming: darkThemeDimming,
  );

  ChatWallpaper withBlurred(bool value) {
    if (kind == ChatWallpaperKind.image) {
      return ChatWallpaper.image(
        imagePath ?? '',
        isBlurred: value,
        isMoving: isMoving,
      );
    }
    return _copyTelegram(isBlurred: value);
  }

  ChatWallpaper withMoving(bool value) {
    if (kind == ChatWallpaperKind.image) {
      return ChatWallpaper.image(
        imagePath ?? '',
        isBlurred: isBlurred,
        isMoving: value,
      );
    }
    return _copyTelegram(isMoving: value);
  }

  ChatWallpaper withIntensity(int value) =>
      _copyTelegram(intensity: value.clamp(0, 100));

  ChatWallpaper withColors(List<int> value) =>
      _copyTelegram(colors: List<int>.unmodifiable(value));

  ChatWallpaper _copyTelegram({
    bool? isBlurred,
    bool? isMoving,
    int? intensity,
    List<int>? colors,
  }) => ChatWallpaper.telegram(
    backgroundId: backgroundId,
    remoteType: remoteType ?? 'wallpaper',
    fileId: fileId,
    imagePath: imagePath,
    mimeType: mimeType,
    themeName: themeName,
    colors: colors ?? this.colors,
    rotationAngle: rotationAngle,
    intensity: intensity ?? this.intensity,
    isInverted: isInverted,
    isBlurred: isBlurred ?? this.isBlurred,
    isMoving: isMoving ?? this.isMoving,
    isTiled: isTiled,
    darkThemeDimming: darkThemeDimming,
  );

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (presetId != null) 'preset_id': presetId,
    if (imagePath != null) 'image_path': imagePath,
    if (kind == ChatWallpaperKind.image) ...{
      'is_blurred': isBlurred,
      'is_moving': isMoving,
    },
    if (themeName != null) 'theme_name': themeName,
    if (themeKind != ChatThemeKind.emoji) 'theme_kind': themeKind.name,
    if (kind == ChatWallpaperKind.telegram) ...{
      'background_id': backgroundId,
      'file_id': fileId,
      if (remoteType != null) 'remote_type': remoteType,
      if (mimeType != null) 'mime_type': mimeType,
      'colors': colors,
      'rotation_angle': rotationAngle,
      'intensity': intensity,
      'is_inverted': isInverted,
      'is_blurred': isBlurred,
      'is_moving': isMoving,
      'is_tiled': isTiled,
      'dark_theme_dimming': darkThemeDimming,
    },
  };

  static ChatWallpaper? fromJson(Object? value) {
    if (value is! Map) return null;
    final kind = value['kind'];
    if (kind == ChatWallpaperKind.preset.name) {
      final id = value['preset_id'];
      return id is String && chatWallpaperPreset(id) != null
          ? ChatWallpaper.preset(id)
          : null;
    }
    if (kind == ChatWallpaperKind.image.name) {
      final path = value['image_path'];
      return path is String && path.isNotEmpty
          ? ChatWallpaper.image(
              path,
              isBlurred: value['is_blurred'] == true,
              isMoving: value['is_moving'] == true,
            )
          : null;
    }
    if (kind == ChatWallpaperKind.theme.name) {
      final name = value['theme_name'];
      final themeKind = ChatThemeKind.values.firstWhere(
        (item) => item.name == value['theme_kind'],
        orElse: () => ChatThemeKind.emoji,
      );
      return name is String && name.isNotEmpty
          ? ChatWallpaper.theme(name, themeKind: themeKind)
          : null;
    }
    if (kind == ChatWallpaperKind.telegram.name) {
      final remoteType = value['remote_type'];
      if (remoteType is! String || remoteType.isEmpty) return null;
      final colors = value['colors'];
      return ChatWallpaper.telegram(
        backgroundId: _jsonInt(value['background_id']),
        remoteType: remoteType,
        fileId: _jsonInt(value['file_id']),
        imagePath: value['image_path'] as String?,
        mimeType: value['mime_type'] as String?,
        themeName: value['theme_name'] as String?,
        colors: colors is List
            ? colors.map(_jsonInt).toList(growable: false)
            : const [],
        rotationAngle: _jsonInt(value['rotation_angle']),
        intensity: _jsonInt(value['intensity']),
        isInverted: value['is_inverted'] == true,
        isBlurred: value['is_blurred'] == true,
        isMoving: value['is_moving'] == true,
        isTiled: value['is_tiled'] == true,
        darkThemeDimming: _jsonInt(value['dark_theme_dimming']),
      );
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ChatWallpaper &&
      other.kind == kind &&
      other.presetId == presetId &&
      other.imagePath == imagePath &&
      other.themeName == themeName &&
      other.themeKind == themeKind &&
      other.backgroundId == backgroundId &&
      other.fileId == fileId &&
      other.remoteType == remoteType &&
      other.mimeType == mimeType &&
      listEquals(other.colors, colors) &&
      other.rotationAngle == rotationAngle &&
      other.intensity == intensity &&
      other.isInverted == isInverted &&
      other.isBlurred == isBlurred &&
      other.isMoving == isMoving &&
      other.isTiled == isTiled &&
      other.darkThemeDimming == darkThemeDimming;

  @override
  int get hashCode => Object.hash(
    kind,
    presetId,
    imagePath,
    themeName,
    themeKind,
    backgroundId,
    fileId,
    remoteType,
    mimeType,
    Object.hashAll(colors),
    rotationAngle,
    intensity,
    isInverted,
    isBlurred,
    isMoving,
    isTiled,
    darkThemeDimming,
  );
}

int _jsonInt(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text) ?? 0,
  _ => 0,
};

@immutable
class ChatWallpaperPreset {
  const ChatWallpaperPreset({required this.id, required this.colors});

  final String id;
  final List<Color> colors;
}

const chatWallpaperPresets = <ChatWallpaperPreset>[
  ChatWallpaperPreset(
    id: 'sky',
    colors: [Color(0xFF91C8EA), Color(0xFFB8E0D2), Color(0xFFF2D6A2)],
  ),
  ChatWallpaperPreset(
    id: 'aurora',
    colors: [Color(0xFF354A78), Color(0xFF786FA6), Color(0xFFE0A2B4)],
  ),
  ChatWallpaperPreset(
    id: 'mint',
    colors: [Color(0xFF80C9B8), Color(0xFFC7DFB7), Color(0xFFF5E8B7)],
  ),
  ChatWallpaperPreset(
    id: 'sunset',
    colors: [Color(0xFFF4A58A), Color(0xFFE98DA6), Color(0xFF9A7FC2)],
  ),
  ChatWallpaperPreset(
    id: 'ocean',
    colors: [Color(0xFF176B87), Color(0xFF64CCC5), Color(0xFFDAFFFB)],
  ),
  ChatWallpaperPreset(
    id: 'night',
    colors: [Color(0xFF111827), Color(0xFF27365C), Color(0xFF634B7A)],
  ),
];

ChatWallpaperPreset? chatWallpaperPreset(String id) {
  for (final preset in chatWallpaperPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}

@immutable
class ChatThemeStyle {
  const ChatThemeStyle({
    required this.outgoingColors,
    required this.accentColor,
    required this.isDark,
  });

  final List<int> outgoingColors;
  final int accentColor;
  final bool isDark;

  Color? get outgoingColor {
    if (outgoingColors.isEmpty) return null;
    if (outgoingColors.length == 1) return _rgbColor(outgoingColors.first);
    final first = _rgbColor(outgoingColors.first);
    final last = _rgbColor(outgoingColors.last);
    return Color.lerp(first, last, 0.5);
  }

  Color get incomingColor {
    final base = isDark ? const Color(0xFF202427) : const Color(0xFFFFFFFF);
    if (accentColor == 0) return base;
    return Color.alphaBlend(
      _rgbColor(accentColor).withValues(alpha: isDark ? 0.20 : 0.10),
      base,
    );
  }

  Color get incomingTextColor => incomingColor.computeLuminance() > 0.58
      ? const Color(0xFF171717)
      : const Color(0xFFF4F4F4);

  Color get outgoingTextColor {
    final color = outgoingColor;
    return color != null && color.computeLuminance() > 0.58
        ? const Color(0xFF171717)
        : const Color(0xFFFFFFFF);
  }
}

@immutable
class ChatThemeOption {
  const ChatThemeOption({
    required this.name,
    required this.kind,
    required this.label,
    required this.wallpaper,
    required this.style,
  });

  final String name;
  final ChatThemeKind kind;
  final String label;
  final ChatWallpaper? wallpaper;
  final ChatThemeStyle style;
}

@immutable
class ChatWallpaperSearchResult {
  const ChatWallpaperSearchResult({
    required this.id,
    required this.preview,
    required this.fileId,
    required this.width,
    required this.height,
    this.title = '',
    this.description = '',
  });

  final String id;
  final TdFileRef preview;
  final int fileId;
  final int width;
  final int height;
  final String title;
  final String description;
}

@immutable
class ChatWallpaperSearchPage {
  const ChatWallpaperSearchPage({
    required this.results,
    required this.nextOffset,
    required this.providerUsername,
  });

  final List<ChatWallpaperSearchResult> results;
  final String nextOffset;
  final String providerUsername;
}

@immutable
class ChatWallpaperBoostAccess {
  const ChatWallpaperBoostAccess({
    required this.isBoostedChat,
    required this.currentLevel,
    required this.requiredLevel,
    required this.allowed,
  });

  const ChatWallpaperBoostAccess.unrestricted()
    : isBoostedChat = false,
      currentLevel = 0,
      requiredLevel = 0,
      allowed = true;

  final bool isBoostedChat;
  final int currentLevel;
  final int requiredLevel;
  final bool allowed;
}

typedef TdWallpaperQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

class ChatWallpaperController extends ChangeNotifier {
  ChatWallpaperController({
    Future<SharedPreferences> Function()? preferences,
    Future<Directory> Function()? supportDirectory,
    int Function()? activeSlot,
    bool Function()? hasActiveClient,
    TdWallpaperQuery? query,
    Stream<Map<String, dynamic>> Function()? subscribe,
    Map<String, dynamic>? Function()? latestEmojiChatThemes,
    bool listenForUpdates = true,
  }) : _preferences = preferences ?? SharedPreferences.getInstance,
       _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _activeSlot = activeSlot ?? (() => TdClient.shared.activeSlot),
       _hasActiveClient =
           hasActiveClient ?? (() => TdClient.shared.hasActiveClient),
       _query = query ?? TdClient.shared.query,
       _latestEmojiChatThemes =
           latestEmojiChatThemes ??
           (() => TdClient.shared.latestEmojiChatThemesUpdate) {
    if (listenForUpdates) {
      _updateSubscription = (subscribe ?? TdClient.shared.subscribe)().listen(
        _handleTdUpdate,
      );
    }
  }

  static final shared = ChatWallpaperController();

  final Future<SharedPreferences> Function() _preferences;
  final Future<Directory> Function() _supportDirectory;
  final int Function() _activeSlot;
  final bool Function() _hasActiveClient;
  final TdWallpaperQuery _query;
  final Map<String, dynamic>? Function() _latestEmojiChatThemes;
  StreamSubscription<Map<String, dynamic>>? _updateSubscription;

  final Map<String, ChatWallpaper?> _localValues = {};
  final Map<String, ChatWallpaper?> _serverBackgrounds = {};
  final Map<String, String?> _themeNames = {};
  final Map<String, ChatThemeKind> _themeKinds = {};
  final Map<String, String?> _chatTypes = {};
  final Map<String, int> _chatSupergroupIds = {};
  final Map<String, bool> _chatIsChannel = {};
  final Map<String, int> _chatBoostLevels = {};
  final Map<String, Map<String, dynamic>> _chatBoostFeatures = {};
  final Map<int, List<Map<String, dynamic>>> _emojiThemes = {};
  final Map<int, List<Map<String, dynamic>>> _giftThemes = {};
  final Set<int> _loadingGiftThemes = {};
  final Set<int> _loadedGiftThemes = {};
  final Map<String, String> _resolvedFilePaths = {};
  final Set<String> _wallpaperFileKeys = {};
  final Set<String> _loadedLocal = {};
  final Set<String> _loading = {};
  final Set<String> _resolvingFiles = {};
  final Map<String, List<ChatWallpaper>> _installedBackgrounds = {};
  final Map<String, ChatWallpaper?> _defaultBackgrounds = {};
  final Map<int, String> _photoSearchBotUsernames = {};
  final Map<int, int> _photoSearchBotUserIds = {};
  final Map<int, int> _photoSearchBotChatIds = {};

  String _id(int chatId) => '${_activeSlot()}:$chatId';
  String _fileKey(int fileId) => '${_activeSlot()}:$fileId';
  String _preferenceKey(int chatId) => 'mithka.chatWallpaper.v1.${_id(chatId)}';
  String _globalId(bool dark) => '${_activeSlot()}:${dark ? 'dark' : 'light'}';

  ChatWallpaper? wallpaperFor(int chatId, {bool dark = false}) {
    final id = _id(chatId);
    final explicit = _serverBackgrounds[id];
    if (explicit != null && explicit.remoteType == 'chatTheme') {
      return themeWallpaper(explicit.themeName ?? '', dark: dark) ?? explicit;
    }
    if (explicit != null) return _withResolvedFile(explicit);
    final themeName = _themeNames[id];
    if (themeName != null && themeName.isNotEmpty) {
      return themeWallpaper(
        themeName,
        kind: _themeKinds[id] ?? ChatThemeKind.emoji,
        dark: dark,
      );
    }
    return _localValues[id];
  }

  ChatWallpaper? selectionFor(int chatId) {
    final id = _id(chatId);
    final explicit = _serverBackgrounds[id];
    if (explicit != null) return _withResolvedFile(explicit);
    final themeName = _themeNames[id];
    if (themeName != null && themeName.isNotEmpty) {
      return ChatWallpaper.theme(
        themeName,
        themeKind: _themeKinds[id] ?? ChatThemeKind.emoji,
      );
    }
    return _localValues[id];
  }

  ChatWallpaper? wallpaperSelectionFor(int chatId) {
    final id = _id(chatId);
    final explicit = _serverBackgrounds[id];
    if (explicit != null && explicit.remoteType != 'chatTheme') {
      return _withResolvedFile(explicit);
    }
    return _localValues[id];
  }

  ChatWallpaper? themeSelectionFor(int chatId) {
    final id = _id(chatId);
    final explicit = _serverBackgrounds[id];
    if (explicit?.remoteType == 'chatTheme') {
      final name = explicit?.themeName;
      return name == null || name.isEmpty ? null : ChatWallpaper.theme(name);
    }
    final name = _themeNames[id];
    return name == null || name.isEmpty
        ? null
        : ChatWallpaper.theme(
            name,
            themeKind: _themeKinds[id] ?? ChatThemeKind.emoji,
          );
  }

  ChatWallpaper resolvedWallpaper(ChatWallpaper wallpaper) =>
      _withResolvedFile(wallpaper);

  bool canApplyOnlyForSelf(int chatId) {
    final type = _chatTypes[_id(chatId)];
    return type == 'chatTypePrivate' || type == 'chatTypeSecret';
  }

  bool canApplyTheme(int chatId) => switch (_chatTypes[_id(chatId)]) {
    'chatTypePrivate' || 'chatTypeSecret' || 'chatTypeSupergroup' => true,
    _ => false,
  };

  bool isBoostedChat(int chatId) =>
      _chatTypes[_id(chatId)] == 'chatTypeSupergroup';

  int boostLevelFor(int chatId) => _chatBoostLevels[_id(chatId)] ?? 0;

  ChatWallpaperBoostAccess accessFor(int chatId, ChatWallpaper? wallpaper) {
    final id = _id(chatId);
    if (_chatTypes[id] != 'chatTypeSupergroup' || wallpaper == null) {
      return const ChatWallpaperBoostAccess.unrestricted();
    }
    final level = _chatBoostLevels[id] ?? 0;
    final featureSet = _chatBoostFeatures[id];
    if (featureSet == null) {
      return ChatWallpaperBoostAccess(
        isBoostedChat: true,
        currentLevel: level,
        requiredLevel: 0,
        allowed: true,
      );
    }
    final levels = featureSet.objects('features') ?? const [];
    final current = _featureForLevel(levels, level);
    if (wallpaper.kind == ChatWallpaperKind.theme ||
        wallpaper.remoteType == 'chatTheme') {
      final themes = availableThemes(dark: false, chatId: chatId);
      final index = themes.indexWhere(
        (item) =>
            item.name == wallpaper.themeName &&
            item.kind == wallpaper.themeKind,
      );
      final target = index < 0 ? 0 : index;
      final allowedCount = current?.integer('chat_theme_background_count') ?? 0;
      final required = _firstFeatureLevel(
        levels,
        (item) => (item.integer('chat_theme_background_count') ?? 0) > target,
        fallback:
            featureSet.integer('min_chat_theme_background_boost_level') ?? 1,
      );
      return ChatWallpaperBoostAccess(
        isBoostedChat: true,
        currentLevel: level,
        requiredLevel: required,
        allowed: allowedCount > target,
      );
    }
    final allowed = current?.boolean('can_set_custom_background') ?? false;
    return ChatWallpaperBoostAccess(
      isBoostedChat: true,
      currentLevel: level,
      requiredLevel:
          featureSet.integer('min_custom_background_boost_level') ?? 1,
      allowed: allowed,
    );
  }

  Map<String, dynamic>? _featureForLevel(
    List<Map<String, dynamic>> levels,
    int level,
  ) {
    Map<String, dynamic>? result;
    for (final item in levels) {
      final itemLevel = item.integer('level') ?? 0;
      if (itemLevel <= level &&
          (result == null || itemLevel > (result.integer('level') ?? 0))) {
        result = item;
      }
    }
    return result;
  }

  int _firstFeatureLevel(
    List<Map<String, dynamic>> levels,
    bool Function(Map<String, dynamic>) test, {
    required int fallback,
  }) {
    var result = 1 << 30;
    for (final item in levels) {
      final level = item.integer('level') ?? 0;
      if (test(item) && level < result) result = level;
    }
    return result == 1 << 30 ? fallback : result;
  }

  bool canApplyGiftTheme(int chatId) =>
      _chatTypes[_id(chatId)] == 'chatTypePrivate';

  List<ChatThemeOption> availableThemes({
    required bool dark,
    int? chatId,
    bool resolvePatterns = true,
  }) {
    final includeGifts = chatId == null || canApplyGiftTheme(chatId);
    return [
      for (final theme in _emojiThemes[_activeSlot()] ?? const [])
        ?_themeOption(
          theme,
          kind: ChatThemeKind.emoji,
          dark: dark,
          resolvePattern: resolvePatterns,
        ),
      if (includeGifts)
        for (final theme in _giftThemes[_activeSlot()] ?? const [])
          ?_themeOption(
            theme,
            kind: ChatThemeKind.gift,
            dark: dark,
            resolvePattern: resolvePatterns,
          ),
    ];
  }

  ChatWallpaper? themeWallpaper(
    String name, {
    ChatThemeKind kind = ChatThemeKind.emoji,
    required bool dark,
  }) {
    final raw = _themeSource(
      kind,
    ).where((theme) => _themeName(theme, kind) == name);
    if (raw.isEmpty) return null;
    return _themeOption(raw.first, kind: kind, dark: dark)?.wallpaper;
  }

  ChatThemeStyle? themeStyleFor(int chatId, {required bool dark}) {
    final name = _themeNames[_id(chatId)];
    if (name == null || name.isEmpty) return null;
    final kind = _themeKinds[_id(chatId)] ?? ChatThemeKind.emoji;
    return styleForTheme(name, kind: kind, dark: dark);
  }

  ChatThemeStyle? styleForTheme(
    String name, {
    ChatThemeKind kind = ChatThemeKind.emoji,
    required bool dark,
  }) {
    final raw = _themeSource(
      kind,
    ).where((theme) => _themeName(theme, kind) == name);
    if (raw.isEmpty) return null;
    return _themeOption(raw.first, kind: kind, dark: dark)?.style;
  }

  Future<void> loadGiftThemes() async {
    final slot = _activeSlot();
    if (!_hasActiveClient() ||
        _loadedGiftThemes.contains(slot) ||
        !_loadingGiftThemes.add(slot)) {
      return;
    }
    try {
      var offset = '';
      final themes = <Map<String, dynamic>>[];
      do {
        final response = await _query({
          '@type': 'getGiftChatThemes',
          'offset': offset,
          'limit': 100,
        });
        themes.addAll(response.objects('themes') ?? const []);
        offset = response.str('next_offset') ?? '';
      } while (offset.isNotEmpty);
      _giftThemes[slot] = themes;
      _loadedGiftThemes.add(slot);
      notifyListeners();
    } catch (_) {
      // Gift themes are optional; emoji themes must remain usable when this
      // account has no eligible collectible themes or is temporarily offline.
      _giftThemes.putIfAbsent(slot, () => const []);
      _loadedGiftThemes.add(slot);
    } finally {
      _loadingGiftThemes.remove(slot);
    }
  }

  Future<void> load(int chatId) async {
    final id = _id(chatId);
    _ingestEmojiThemes(_latestEmojiChatThemes());
    if (!_loadedLocal.contains(id)) {
      _loadedLocal.add(id);
      await _loadLocal(chatId);
    }
    if (!_hasActiveClient() || !_loading.add(id)) return;
    try {
      final chat = await _query({'@type': 'getChat', 'chat_id': chatId});
      _ingestChat(chat);
      await _loadBoostAccess(chatId, chat);
    } catch (_) {
      // The legacy local value remains usable while TDLib reconnects.
    } finally {
      _loading.remove(id);
    }
  }

  Future<void> _loadBoostAccess(int chatId, Map<String, dynamic> chat) async {
    final type = chat.obj('type');
    if (type?.type != 'chatTypeSupergroup') return;
    final supergroupId = type?.int64('supergroup_id');
    if (supergroupId == null) return;
    final id = _id(chatId);
    _chatSupergroupIds[id] = supergroupId;
    try {
      final supergroup = await _query({
        '@type': 'getSupergroup',
        'supergroup_id': supergroupId,
      });
      final isChannel = supergroup.boolean('is_channel') ?? false;
      _chatIsChannel[id] = isChannel;
      _chatBoostLevels[id] = supergroup.integer('boost_level') ?? 0;
      final features = await _query({
        '@type': 'getChatBoostFeatures',
        'is_channel': isChannel,
      });
      if (features.type == 'chatBoostFeatures') {
        _chatBoostFeatures[id] = features;
      } else {
        _chatBoostFeatures.remove(id);
      }
      try {
        final status = await _query({
          '@type': 'getChatBoostStatus',
          'chat_id': chatId,
        });
        _chatBoostLevels[id] = status.integer('level') ?? _chatBoostLevels[id]!;
      } catch (_) {
        // Non-admins can still use the boost level included in supergroup.
      }
      notifyListeners();
    } catch (_) {
      // Appearance remains visible, but gated, until TDLib can resolve levels.
    }
  }

  Future<List<ChatWallpaper>> installedBackgrounds({required bool dark}) async {
    final key = _globalId(dark);
    final cached = _installedBackgrounds[key];
    if (cached != null) return cached;
    if (!_hasActiveClient()) return const [];
    final response = await _query({
      '@type': 'getInstalledBackgrounds',
      'for_dark_theme': dark,
    });
    final result = <ChatWallpaper>[];
    for (final raw in response.objects('backgrounds') ?? const []) {
      final parsed = _parseBackground(raw, dimming: 0, resolvePattern: false);
      if (parsed != null) result.add(parsed);
    }
    _installedBackgrounds[key] = List.unmodifiable(result);
    return _installedBackgrounds[key]!;
  }

  ChatWallpaper? defaultWallpaper({required bool dark}) =>
      _defaultBackgrounds[_globalId(dark)];

  Future<void> loadDefaultWallpaper({required bool dark}) async {
    if (!_hasActiveClient()) return;
    await installedBackgrounds(dark: dark);
    try {
      final state = await _query({'@type': 'getCurrentState'});
      for (final update in state.objects('updates') ?? const []) {
        if (update.type == 'updateDefaultBackground' &&
            (update.boolean('for_dark_theme') ?? false) == dark) {
          _ingestDefaultBackground(update);
        }
      }
    } catch (_) {}
  }

  Future<void> applyDefaultWallpaper(
    ChatWallpaper? wallpaper, {
    required bool dark,
  }) async {
    if (!_hasActiveClient()) {
      throw UnsupportedError('Telegram is not connected');
    }
    if (wallpaper == null) {
      await _query({
        '@type': 'deleteDefaultBackground',
        'for_dark_theme': dark,
      });
      _defaultBackgrounds[_globalId(dark)] = null;
    } else {
      if (wallpaper.kind == ChatWallpaperKind.theme) {
        throw UnsupportedError('Chat themes cannot be global wallpapers');
      }
      final payload = await _wallpaperRequestPayload(wallpaper);
      final response = await _query({
        '@type': 'setDefaultBackground',
        'background': payload.background,
        'type': payload.type,
        'for_dark_theme': dark,
      });
      _defaultBackgrounds[_globalId(dark)] =
          _parseBackground(response, dimming: payload.darkThemeDimming) ??
          wallpaper;
    }
    _installedBackgrounds.remove(_globalId(dark));
    notifyListeners();
  }

  Future<ChatWallpaperSearchPage> searchBackgroundImages(
    String query, {
    String offset = '',
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const ChatWallpaperSearchPage(
        results: [],
        nextOffset: '',
        providerUsername: 'pic',
      );
    }
    final bot = await _photoSearchBot();
    final response = await _query({
      '@type': 'getInlineQueryResults',
      'bot_user_id': bot.$2,
      'chat_id': bot.$3,
      'user_location': null,
      'query': trimmed,
      'offset': offset,
    });
    final results = <ChatWallpaperSearchResult>[];
    for (final raw
        in response.objects('results') ?? const <Map<String, dynamic>>[]) {
      if (raw['@type'] != 'inlineQueryResultPhoto') continue;
      final photo = raw.obj('photo');
      final sizes = photo?.objects('sizes') ?? const [];
      if (sizes.isEmpty) continue;
      final best = TDParse.bestPhotoSize(sizes);
      final previewSize = TDParse.photoThumbnailSize(sizes, best) ?? best;
      final mini = TDParse.decodeMiniThumb(photo?.obj('minithumbnail'));
      final preview = TDParse.fileRef(
        previewSize.obj('photo'),
        miniThumb: mini,
      );
      final fullId = best.obj('photo')?.integer('id') ?? 0;
      if (preview == null || fullId == 0) continue;
      results.add(
        ChatWallpaperSearchResult(
          id: raw.str('id') ?? '$fullId',
          title: raw.str('title') ?? '',
          description: raw.str('description') ?? '',
          preview: preview,
          fileId: fullId,
          width: best.integer('width') ?? 0,
          height: best.integer('height') ?? 0,
        ),
      );
    }
    return ChatWallpaperSearchPage(
      results: results,
      nextOffset: response.str('next_offset') ?? '',
      providerUsername: bot.$1,
    );
  }

  Future<(String, int, int)> _photoSearchBot() async {
    final slot = _activeSlot();
    final cachedName = _photoSearchBotUsernames[slot];
    final cachedUser = _photoSearchBotUserIds[slot];
    final cachedChat = _photoSearchBotChatIds[slot];
    if (cachedName != null && cachedUser != null && cachedChat != null) {
      return (cachedName, cachedUser, cachedChat);
    }
    var username = 'pic';
    try {
      final option = await _query({
        '@type': 'getOption',
        'name': 'photo_search_bot_username',
      });
      final configured = option.str('value')?.replaceFirst('@', '').trim();
      if (configured != null && configured.isNotEmpty) username = configured;
    } catch (_) {}
    final chat = await _query({
      '@type': 'searchPublicChat',
      'username': username,
    });
    final userId = chat.obj('type')?.int64('user_id');
    final chatId = chat.int64('id');
    if (userId == null || chatId == null) {
      throw StateError('Wallpaper search bot is unavailable');
    }
    _photoSearchBotUsernames[slot] = username;
    _photoSearchBotUserIds[slot] = userId;
    _photoSearchBotChatIds[slot] = chatId;
    return (username, userId, chatId);
  }

  Future<String?> downloadSearchResult(ChatWallpaperSearchResult result) =>
      TdFileCenter.shared.path(result.fileId);

  Future<void> refresh(int chatId) async {
    if (!_hasActiveClient()) return;
    final chat = await _query({'@type': 'getChat', 'chat_id': chatId});
    _ingestChat(chat);
  }

  Future<void> applyWallpaper(
    int chatId,
    ChatWallpaper? wallpaper, {
    required bool onlyForSelf,
  }) async {
    if (wallpaper?.kind == ChatWallpaperKind.theme) {
      if (onlyForSelf) {
        throw UnsupportedError('Telegram chat themes are shared by both users');
      }
      await applyTheme(
        chatId,
        wallpaper?.themeName,
        kind: wallpaper?.themeKind ?? ChatThemeKind.emoji,
      );
      return;
    }
    if (!_hasActiveClient()) {
      await _applyLocally(chatId, wallpaper);
      return;
    }
    if (onlyForSelf && !canApplyOnlyForSelf(chatId)) {
      throw UnsupportedError('This chat cannot use a personal wallpaper');
    }
    final access = accessFor(chatId, wallpaper);
    if (!access.allowed) {
      throw StateError('Chat boost level ${access.requiredLevel} is required');
    }
    if (wallpaper == null) {
      await _query({
        '@type': 'deleteChatBackground',
        'chat_id': chatId,
        'restore_previous': false,
      });
    } else {
      final payload = await _wallpaperRequestPayload(wallpaper);
      await _query({
        '@type': 'setChatBackground',
        'chat_id': chatId,
        'background': payload.background,
        'type': payload.type,
        'dark_theme_dimming': payload.darkThemeDimming,
        'only_for_self': onlyForSelf,
      });
    }
    await _discardLocal(chatId);
    await refresh(chatId);
  }

  Future<void> applyTheme(
    int chatId,
    String? themeName, {
    ChatThemeKind kind = ChatThemeKind.emoji,
  }) async {
    if (!_hasActiveClient()) {
      throw UnsupportedError('Telegram is not connected');
    }
    if (!canApplyTheme(chatId)) {
      throw UnsupportedError('Telegram themes are unavailable in this chat');
    }
    final id = _id(chatId);
    final isGroup = _chatTypes[id] == 'chatTypeSupergroup';
    if (isGroup) {
      final selection = themeName == null || themeName.isEmpty
          ? null
          : ChatWallpaper.theme(themeName, themeKind: kind);
      final access = accessFor(chatId, selection);
      if (!access.allowed) {
        throw StateError(
          'Chat boost level ${access.requiredLevel} is required',
        );
      }
      if (selection == null) {
        await _query({
          '@type': 'deleteChatBackground',
          'chat_id': chatId,
          'restore_previous': false,
        });
        _serverBackgrounds[id] = null;
      } else {
        await _query({
          '@type': 'setChatBackground',
          'chat_id': chatId,
          'background': null,
          'type': {'@type': 'backgroundTypeChatTheme', 'theme_name': themeName},
          'dark_theme_dimming': 0,
          'only_for_self': false,
        });
        _serverBackgrounds[id] = ChatWallpaper.telegram(
          backgroundId: 0,
          remoteType: 'chatTheme',
          themeName: themeName,
        );
      }
      _themeNames[id] = null;
      _themeKinds.remove(id);
      unawaited(_discardLocalSilently(chatId, notify: false));
      notifyListeners();
      return;
    }
    await _query({
      '@type': 'setChatTheme',
      'chat_id': chatId,
      'theme': themeName == null || themeName.isEmpty
          ? null
          : {
              '@type': kind == ChatThemeKind.gift
                  ? 'inputChatThemeGift'
                  : 'inputChatThemeEmoji',
              'name': themeName,
            },
    });
    // setChatTheme returning successfully is the authoritative save result.
    // Do not turn a successful save into an error because getChat is briefly
    // stale/unavailable or local preference cleanup fails afterwards.
    _themeNames[id] = themeName == null || themeName.isEmpty ? null : themeName;
    if (themeName == null || themeName.isEmpty) {
      _themeKinds.remove(id);
    } else {
      _themeKinds[id] = kind;
    }
    unawaited(_discardLocalSilently(chatId, notify: false));
    notifyListeners();
  }

  Future<void> clearAppearance(int chatId) async {
    if (!_hasActiveClient()) {
      await clear(chatId);
      return;
    }
    final id = _id(chatId);
    if (_serverBackgrounds[id] != null) {
      await _query({
        '@type': 'deleteChatBackground',
        'chat_id': chatId,
        'restore_previous': false,
      });
    }
    if (_chatTypes[id] != 'chatTypeSupergroup' &&
        (_themeNames[id] ?? '').isNotEmpty &&
        canApplyTheme(chatId)) {
      await _query({'@type': 'setChatTheme', 'chat_id': chatId, 'theme': null});
    }
    await _discardLocal(chatId);
    await refresh(chatId);
  }

  // Legacy local APIs stay available for offline/debug builds and migration.
  Future<void> setPreset(int chatId, String presetId) async {
    if (chatWallpaperPreset(presetId) == null) return;
    await _replaceLocal(chatId, ChatWallpaper.preset(presetId));
  }

  Future<void> setImage(int chatId, String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return;
    final current = _localValues[_id(chatId)];
    if (current?.kind == ChatWallpaperKind.image &&
        current?.imagePath == sourcePath) {
      return;
    }
    final support = await _supportDirectory();
    final folder = Directory(
      '${support.path}/chat_wallpapers/${_activeSlot()}',
    );
    await folder.create(recursive: true);
    final dot = sourcePath.lastIndexOf('.');
    final rawExtension = dot >= 0
        ? sourcePath.substring(dot).toLowerCase()
        : '';
    final extension = RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(rawExtension)
        ? rawExtension
        : '.jpg';
    final destination = File('${folder.path}/$chatId$extension');
    if (await destination.exists()) await destination.delete();
    await source.copy(destination.path);
    if (current?.kind == ChatWallpaperKind.image &&
        current?.imagePath != destination.path) {
      await _deleteImage(current?.imagePath);
    }
    await _storeLocal(chatId, ChatWallpaper.image(destination.path));
  }

  Future<void> clear(int chatId) async => _discardLocal(chatId);

  Future<void> _loadLocal(int chatId) async {
    final id = _id(chatId);
    try {
      final encoded = (await _preferences()).getString(_preferenceKey(chatId));
      final value = encoded == null
          ? null
          : ChatWallpaper.fromJson(jsonDecode(encoded));
      if (value?.kind == ChatWallpaperKind.image &&
          !File(value!.imagePath!).existsSync()) {
        _localValues[id] = null;
      } else {
        _localValues[id] = value;
      }
    } catch (_) {
      _localValues[id] = null;
    }
    notifyListeners();
  }

  void _handleTdUpdate(Map<String, dynamic> update) {
    switch (update.type) {
      case 'updateEmojiChatThemes':
        _ingestEmojiThemes(update);
        notifyListeners();
      case 'updateChatBackground':
        final chatId = update.int64('chat_id');
        if (chatId == null) return;
        _serverBackgrounds[_id(chatId)] = _parseChatBackground(
          update.obj('background'),
        );
        if (update.obj('background') == null) unawaited(_discardLocal(chatId));
        notifyListeners();
      case 'updateChatTheme':
        final chatId = update.int64('chat_id');
        if (chatId == null) return;
        final theme = update.obj('theme');
        _ingestCurrentGiftTheme(theme);
        _themeNames[_id(chatId)] = _chatThemeName(theme);
        _themeKinds[_id(chatId)] = _chatThemeKind(theme);
        notifyListeners();
      case 'updateDefaultBackground':
        _ingestDefaultBackground(update);
        notifyListeners();
      case 'updateFile':
        final file = update.obj('file');
        final fileId = file?.integer('id');
        final path = file?.obj('local')?.str('path');
        if (fileId == null || path == null || path.isEmpty) return;
        final key = _fileKey(fileId);
        if (!_wallpaperFileKeys.contains(key)) return;
        final previous = _resolvedFilePaths[key];
        if (previous == path ||
            previous?.toLowerCase().endsWith('.svg') == true) {
          return;
        }
        _resolvedFilePaths[key] = path;
        notifyListeners();
    }
  }

  void _ingestChat(Map<String, dynamic> chat) {
    final chatId = chat.int64('id');
    if (chatId == null) return;
    final id = _id(chatId);
    _chatTypes[id] = chat.obj('type')?.type;
    _serverBackgrounds[id] = _parseChatBackground(chat.obj('background'));
    final theme = chat.obj('theme');
    _ingestCurrentGiftTheme(theme);
    _themeNames[id] = _chatThemeName(theme);
    _themeKinds[id] = _chatThemeKind(theme);
    // Once TDLib has returned the chat, its server-backed appearance is the
    // source of truth. Keeping the old preference would resurrect a stale
    // local wallpaper after it was reset from another Telegram client.
    if (_localValues[id] != null) unawaited(_discardLocal(chatId));
    notifyListeners();
  }

  void _ingestDefaultBackground(Map<String, dynamic> update) {
    final dark = update.boolean('for_dark_theme') ?? false;
    _defaultBackgrounds[_globalId(dark)] = _parseBackground(
      update.obj('background'),
      dimming: 0,
    );
  }

  void _ingestEmojiThemes(Map<String, dynamic>? update) {
    if (update?.type != 'updateEmojiChatThemes') return;
    _emojiThemes[_activeSlot()] = update?.objects('chat_themes') ?? const [];
  }

  void _ingestCurrentGiftTheme(Map<String, dynamic>? theme) {
    if (theme?.type != 'chatThemeGift') return;
    final giftTheme = theme?.obj('gift_theme');
    final name = giftTheme?.obj('gift')?.str('name');
    if (giftTheme == null || name == null || name.isEmpty) return;
    final themes = _giftThemes.putIfAbsent(_activeSlot(), () => []);
    themes.removeWhere((item) => item.obj('gift')?.str('name') == name);
    themes.add(giftTheme);
  }

  String? _chatThemeName(Map<String, dynamic>? theme) {
    return switch (theme?.type) {
      'chatThemeEmoji' => theme?.str('name'),
      'chatThemeGift' => theme?.obj('gift_theme')?.obj('gift')?.str('name'),
      _ => null,
    };
  }

  ChatThemeKind _chatThemeKind(Map<String, dynamic>? theme) =>
      theme?.type == 'chatThemeGift' ? ChatThemeKind.gift : ChatThemeKind.emoji;

  List<Map<String, dynamic>> _themeSource(ChatThemeKind kind) =>
      kind == ChatThemeKind.gift
      ? _giftThemes[_activeSlot()] ?? const []
      : _emojiThemes[_activeSlot()] ?? const [];

  String? _themeName(Map<String, dynamic> theme, ChatThemeKind kind) =>
      kind == ChatThemeKind.gift
      ? theme.obj('gift')?.str('name')
      : theme.str('name');

  ChatThemeOption? _themeOption(
    Map<String, dynamic> theme, {
    required ChatThemeKind kind,
    required bool dark,
    bool resolvePattern = true,
  }) {
    final gift = kind == ChatThemeKind.gift ? theme.obj('gift') : null;
    final name = _themeName(theme, kind);
    if (name == null || name.isEmpty) return null;
    final settings = theme.obj(dark ? 'dark_settings' : 'light_settings');
    if (settings == null) return null;
    final wallpaper = _parseBackground(
      settings.obj('background'),
      dimming: 0,
      resolvePattern: resolvePattern,
    );
    final outgoing = _fillColors(settings.obj('outgoing_message_fill'));
    final displayWallpaper = wallpaper == null
        ? null
        : wallpaper.remoteType == 'pattern' && !resolvePattern
        ? wallpaper.withoutPatternDocument()
        : _withResolvedFile(wallpaper);
    return ChatThemeOption(
      name: name,
      kind: kind,
      label: kind == ChatThemeKind.gift
          ? gift?.str('title') ?? gift?.str('name') ?? name
          : name,
      wallpaper: displayWallpaper,
      style: ChatThemeStyle(
        outgoingColors: outgoing,
        accentColor:
            settings.integer('accent_color') ??
            settings.integer('outgoing_message_accent_color') ??
            0,
        isDark:
            settings.obj('base_theme')?.type == 'builtInThemeNight' ||
            settings.obj('base_theme')?.type == 'builtInThemeTinted' ||
            dark,
      ),
    );
  }

  ChatWallpaper? _parseChatBackground(Map<String, dynamic>? chatBackground) {
    if (chatBackground == null) return null;
    return _parseBackground(
      chatBackground.obj('background'),
      dimming: chatBackground.integer('dark_theme_dimming') ?? 0,
    );
  }

  ChatWallpaper? _parseBackground(
    Map<String, dynamic>? background, {
    required int dimming,
    bool resolvePattern = true,
  }) {
    if (background == null) return null;
    final type = background.obj('type');
    final remoteType = switch (type?.type) {
      'backgroundTypeWallpaper' => 'wallpaper',
      'backgroundTypePattern' => 'pattern',
      'backgroundTypeFill' => 'fill',
      'backgroundTypeChatTheme' => 'chatTheme',
      _ => null,
    };
    if (remoteType == null) return null;
    final document = background.obj('document');
    final file = document?.obj('document');
    final fileId = file?.integer('id') ?? 0;
    final shouldResolveFile =
        fileId != 0 && (remoteType != 'pattern' || resolvePattern);
    if (shouldResolveFile) _wallpaperFileKeys.add(_fileKey(fileId));
    final embeddedPath = file?.obj('local')?.str('path');
    final resolvedPath = fileId == 0
        ? embeddedPath
        : _resolvedFilePaths[_fileKey(fileId)] ?? embeddedPath;
    final fill = type?.obj('fill');
    final wallpaper = ChatWallpaper.telegram(
      backgroundId: background.int64('id') ?? 0,
      remoteType: remoteType,
      fileId: fileId,
      imagePath: resolvedPath,
      mimeType: document?.str('mime_type'),
      themeName: type?.str('theme_name'),
      colors: _fillColors(fill),
      rotationAngle: fill?.integer('rotation_angle') ?? 0,
      intensity: type?.integer('intensity') ?? 0,
      isInverted: type?.boolean('is_inverted') ?? false,
      isBlurred: type?.boolean('is_blurred') ?? false,
      isMoving: type?.boolean('is_moving') ?? false,
      darkThemeDimming: dimming,
    );
    if (shouldResolveFile && (resolvedPath == null || resolvedPath.isEmpty)) {
      _scheduleFileResolution(wallpaper);
    } else if (resolvePattern &&
        wallpaper.remoteType == 'pattern' &&
        resolvedPath != null) {
      _scheduleFileResolution(wallpaper);
    }
    return wallpaper;
  }

  List<int> _fillColors(Map<String, dynamic>? fill) {
    return switch (fill?.type) {
      'backgroundFillSolid' => [fill?.integer('color') ?? 0],
      'backgroundFillGradient' => [
        fill?.integer('top_color') ?? 0,
        fill?.integer('bottom_color') ?? 0,
      ],
      'backgroundFillFreeformGradient' =>
        fill?.int64Array('colors') ?? const <int>[],
      _ => const <int>[],
    };
  }

  ChatWallpaper _withResolvedFile(ChatWallpaper wallpaper) {
    if (!wallpaper.isRemoteFile || wallpaper.fileId == 0) return wallpaper;
    final key = _fileKey(wallpaper.fileId);
    _wallpaperFileKeys.add(key);
    final path = _resolvedFilePaths[key];
    if (path != null && path.isNotEmpty) {
      final resolved = path == wallpaper.imagePath
          ? wallpaper
          : wallpaper.withImagePath(path);
      if (wallpaper.remoteType != 'pattern' ||
          path.toLowerCase().endsWith('.svg')) {
        return resolved;
      }
      _scheduleFileResolution(resolved);
      return resolved;
    }
    _scheduleFileResolution(wallpaper);
    return wallpaper;
  }

  void _scheduleFileResolution(ChatWallpaper wallpaper) {
    if (wallpaper.fileId == 0) return;
    final key = _fileKey(wallpaper.fileId);
    _wallpaperFileKeys.add(key);
    final current = _resolvedFilePaths[key];
    if (wallpaper.remoteType == 'pattern') {
      if (current?.toLowerCase().endsWith('.svg') == true) return;
      final embedded = wallpaper.imagePath;
      if (embedded?.toLowerCase().endsWith('.svg') == true) {
        _resolvedFilePaths.putIfAbsent(key, () => embedded!);
        return;
      }
    } else if (current != null && current.isNotEmpty) {
      return;
    }
    if (!_resolvingFiles.add(key)) return;
    unawaited(() async {
      try {
        var path = wallpaper.imagePath;
        if (path == null || path.isEmpty || !await File(path).exists()) {
          path = await TdFileCenter.shared.path(wallpaper.fileId);
        }
        if (path == null || path.isEmpty) return;
        if (wallpaper.remoteType == 'pattern') {
          path = await _preparePatternSvg(wallpaper.fileId, path);
        }
        if (_resolvedFilePaths[key] != path) {
          _resolvedFilePaths[key] = path;
          notifyListeners();
        }
      } finally {
        _resolvingFiles.remove(key);
      }
    }());
  }

  Future<String> _preparePatternSvg(int fileId, String sourcePath) async {
    if (sourcePath.toLowerCase().endsWith('.svg')) return sourcePath;
    final source = File(sourcePath);
    final bytes = await source.readAsBytes();
    final decoded = bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b
        ? GZipDecoder().decodeBytes(bytes)
        : bytes;
    final support = await _supportDirectory();
    final folder = Directory(
      '${support.path}/chat_wallpapers/${_activeSlot()}/telegram',
    );
    await folder.create(recursive: true);
    final destination = File('${folder.path}/pattern_$fileId.svg');
    await destination.writeAsBytes(decoded, flush: true);
    return destination.path;
  }

  Future<_WallpaperRequestPayload> _wallpaperRequestPayload(
    ChatWallpaper wallpaper,
  ) async {
    switch (wallpaper.kind) {
      case ChatWallpaperKind.preset:
        final preset = chatWallpaperPreset(wallpaper.presetId ?? '');
        if (preset == null) throw ArgumentError('Unknown wallpaper preset');
        return _WallpaperRequestPayload(
          background: null,
          type: {
            '@type': 'backgroundTypeFill',
            'fill': {
              '@type': 'backgroundFillFreeformGradient',
              'colors': preset.colors
                  .map((color) => color.toARGB32() & 0x00FFFFFF)
                  .toList(growable: false),
            },
          },
          darkThemeDimming: 25,
        );
      case ChatWallpaperKind.image:
        final path = await _prepareWallpaperJpeg(wallpaper.imagePath ?? '');
        return _WallpaperRequestPayload(
          background: {
            '@type': 'inputBackgroundLocal',
            'background': {'@type': 'inputFileLocal', 'path': path},
          },
          type: {
            '@type': 'backgroundTypeWallpaper',
            'is_blurred': wallpaper.isBlurred,
            'is_moving': wallpaper.isMoving,
          },
          darkThemeDimming: 30,
        );
      case ChatWallpaperKind.telegram:
        return _WallpaperRequestPayload(
          background:
              wallpaper.backgroundId == 0 || wallpaper.remoteType == 'chatTheme'
              ? null
              : {
                  '@type': 'inputBackgroundRemote',
                  'background_id': wallpaper.backgroundId,
                },
          type: _backgroundTypePayload(wallpaper),
          darkThemeDimming: wallpaper.darkThemeDimming,
        );
      case ChatWallpaperKind.theme:
        throw UnsupportedError('A theme must be applied with setChatTheme');
    }
  }

  Map<String, dynamic> _backgroundTypePayload(ChatWallpaper wallpaper) {
    final fill = _fillPayload(wallpaper.colors, wallpaper.rotationAngle);
    return switch (wallpaper.remoteType) {
      'pattern' => {
        '@type': 'backgroundTypePattern',
        'fill': fill,
        'intensity': wallpaper.intensity,
        'is_inverted': wallpaper.isInverted,
        'is_moving': wallpaper.isMoving,
      },
      'fill' => {'@type': 'backgroundTypeFill', 'fill': fill},
      'chatTheme' => {
        '@type': 'backgroundTypeChatTheme',
        'theme_name': wallpaper.themeName ?? '',
      },
      _ => {
        '@type': 'backgroundTypeWallpaper',
        'is_blurred': wallpaper.isBlurred,
        'is_moving': wallpaper.isMoving,
      },
    };
  }

  Map<String, dynamic> _fillPayload(List<int> colors, int rotationAngle) {
    if (colors.length >= 3) {
      return {'@type': 'backgroundFillFreeformGradient', 'colors': colors};
    }
    if (colors.length == 2) {
      return {
        '@type': 'backgroundFillGradient',
        'top_color': colors.first,
        'bottom_color': colors.last,
        'rotation_angle': rotationAngle,
      };
    }
    return {
      '@type': 'backgroundFillSolid',
      'color': colors.isEmpty ? 0 : colors.first,
    };
  }

  Future<String> _prepareWallpaperJpeg(String sourcePath) async {
    final source = File(sourcePath);
    if (sourcePath.isEmpty || !await source.exists()) {
      throw ArgumentError('Wallpaper image is missing');
    }
    final lower = sourcePath.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return sourcePath;
    final decoded = image_lib.decodeImage(await source.readAsBytes());
    if (decoded == null) throw const FormatException('Unsupported image');
    final support = await _supportDirectory();
    final folder = Directory(
      '${support.path}/chat_wallpapers/${_activeSlot()}',
    );
    await folder.create(recursive: true);
    final output = File(
      '${folder.path}/upload_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await output.writeAsBytes(
      image_lib.encodeJpg(
        decoded,
        quality: 90,
        chroma: image_lib.JpegChroma.yuv420,
      ),
      flush: true,
    );
    return output.path;
  }

  Future<void> _applyLocally(int chatId, ChatWallpaper? wallpaper) async {
    if (wallpaper == null) return clear(chatId);
    if (wallpaper.kind == ChatWallpaperKind.preset) {
      return setPreset(chatId, wallpaper.presetId ?? '');
    }
    if (wallpaper.kind == ChatWallpaperKind.image) {
      return setImage(chatId, wallpaper.imagePath ?? '');
    }
    await _replaceLocal(chatId, wallpaper);
  }

  Future<void> _replaceLocal(int chatId, ChatWallpaper wallpaper) async {
    final old = _localValues[_id(chatId)];
    if (old?.kind == ChatWallpaperKind.image) {
      await _deleteImage(old?.imagePath);
    }
    await _storeLocal(chatId, wallpaper);
  }

  Future<void> _storeLocal(int chatId, ChatWallpaper wallpaper) async {
    final id = _id(chatId);
    _loadedLocal.add(id);
    _localValues[id] = wallpaper;
    await (await _preferences()).setString(
      _preferenceKey(chatId),
      jsonEncode(wallpaper.toJson()),
    );
    notifyListeners();
  }

  Future<void> _discardLocal(int chatId, {bool notify = true}) async {
    final id = _id(chatId);
    final old = _localValues[id];
    if (old?.kind == ChatWallpaperKind.image) {
      await _deleteImage(old?.imagePath);
    }
    _loadedLocal.add(id);
    _localValues[id] = null;
    await (await _preferences()).remove(_preferenceKey(chatId));
    if (notify) notifyListeners();
  }

  Future<void> _discardLocalSilently(int chatId, {bool notify = true}) async {
    try {
      await _discardLocal(chatId, notify: notify);
    } catch (_) {
      // The remote appearance is already saved. A stale local preference can
      // be cleaned up on a later load and must not report that save as failed.
    }
  }

  Future<void> _deleteImage(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(_updateSubscription?.cancel());
    super.dispose();
  }
}

class _WallpaperRequestPayload {
  const _WallpaperRequestPayload({
    required this.background,
    required this.type,
    required this.darkThemeDimming,
  });

  final Map<String, dynamic>? background;
  final Map<String, dynamic> type;
  final int darkThemeDimming;
}

class ChatWallpaperBackground extends StatelessWidget {
  const ChatWallpaperBackground({
    super.key,
    required this.wallpaper,
    required this.fallbackColor,
    this.brightness,
    this.child,
    this.imageScrim = const Color(0x12000000),
  });

  final ChatWallpaper? wallpaper;
  final Color fallbackColor;
  final Brightness? brightness;
  final Widget? child;
  final Color imageScrim;

  @override
  Widget build(BuildContext context) {
    final value = wallpaper;
    if (value == null || value.kind == ChatWallpaperKind.theme) {
      return ColoredBox(color: fallbackColor, child: child);
    }
    if (value.kind == ChatWallpaperKind.image) {
      return _localImage(value);
    }
    if (value.kind == ChatWallpaperKind.telegram) {
      return _telegramBackground(context, value);
    }
    final preset = chatWallpaperPreset(value.presetId ?? '');
    if (preset == null) return ColoredBox(color: fallbackColor, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: preset.colors,
        ),
      ),
      child: child,
    );
  }

  Widget _localImage(ChatWallpaper value) {
    final path = value.imagePath;
    if (path == null || path.isEmpty) {
      return ColoredBox(color: fallbackColor, child: child);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: fallbackColor),
        _wallpaperEffects(
          value,
          RepaintBoundary(
            child: Image.file(
              File(path),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        ColoredBox(color: imageScrim),
        ?child,
      ],
    );
  }

  Widget _telegramBackground(BuildContext context, ChatWallpaper value) {
    final fill = _fillDecoration(value.colors, value.rotationAngle);
    final path = value.imagePath;
    final hasFile = path != null && path.isNotEmpty;
    final invertedPattern =
        hasFile && value.remoteType == 'pattern' && value.isInverted;
    final dark =
        (brightness ?? MediaQuery.platformBrightnessOf(context)) ==
        Brightness.dark;
    final dimming = dark
        ? (value.darkThemeDimming.clamp(0, 100) / 100).toDouble()
        : 0.0;
    return DecoratedBox(
      decoration: invertedPattern
          ? const BoxDecoration(color: Color(0xFF000000))
          : fill ?? BoxDecoration(color: fallbackColor),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (value.remoteType == 'wallpaper' && hasFile)
            _wallpaperEffects(
              value,
              RepaintBoundary(
                child: Image.file(
                  File(path),
                  fit: value.isTiled ? BoxFit.none : BoxFit.cover,
                  repeat: value.isTiled
                      ? ImageRepeat.repeat
                      : ImageRepeat.noRepeat,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (value.remoteType == 'pattern' && hasFile)
            _wallpaperEffects(
              value,
              RepaintBoundary(
                child: Opacity(
                  opacity: (value.intensity.abs().clamp(0, 100) / 100)
                      .toDouble(),
                  child: SvgPicture.file(
                    File(path),
                    fit: BoxFit.cover,
                    renderingStrategy: RenderingStrategy.raster,
                    colorFilter: ColorFilter.mode(
                      invertedPattern
                          ? _representativeFillColor(value.colors)
                          : const Color(0xFF000000),
                      BlendMode.srcIn,
                    ),
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          if (dimming > 0) ColoredBox(color: Color.fromRGBO(0, 0, 0, dimming)),
          if (value.remoteType == 'wallpaper') ColoredBox(color: imageScrim),
          ?child,
        ],
      ),
    );
  }

  Widget _wallpaperEffects(ChatWallpaper value, Widget image) {
    Widget result = image;
    if (value.isBlurred) {
      result = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: result,
      );
    }
    if (value.isBlurred || value.isMoving) {
      result = Transform.scale(scale: 1.08, child: result);
    }
    if (value.isMoving) result = _WallpaperMotion(child: result);
    return ClipRect(child: result);
  }
}

class _WallpaperMotion extends StatefulWidget {
  const _WallpaperMotion({required this.child});

  final Widget child;

  @override
  State<_WallpaperMotion> createState() => _WallpaperMotionState();
}

class _WallpaperMotionState extends State<_WallpaperMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final phase = _controller.value * 2 - 1;
        return Transform.translate(
          offset: Offset(phase * 5, phase * -3),
          child: child,
        );
      },
    );
  }
}

BoxDecoration? _fillDecoration(List<int> colors, int rotationAngle) {
  if (colors.isEmpty) return null;
  final resolved = colors.map(_rgbColor).toList(growable: false);
  if (resolved.length == 1) return BoxDecoration(color: resolved.first);
  final radians = rotationAngle * math.pi / 180;
  final direction = Alignment(math.sin(radians), -math.cos(radians));
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment(-direction.x, -direction.y),
      end: direction,
      colors: resolved,
    ),
  );
}

Color _rgbColor(int value) => Color(0xFF000000 | (value & 0x00FFFFFF));

Color _representativeFillColor(List<int> colors) {
  if (colors.isEmpty) return const Color(0xFFFFFFFF);
  var color = _rgbColor(colors.first);
  for (var index = 1; index < colors.length; index++) {
    color = Color.lerp(color, _rgbColor(colors[index]), 1 / (index + 1))!;
  }
  return color;
}
