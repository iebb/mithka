part of 'appearance_view.dart';

class FontSettingsView extends StatelessWidget {
  const FontSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceFont),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsCard.rows(
            dividerInset: AppMetric.settingsTextDividerInset,
            rows: [
              SettingsRow(
                title: AppStrings.t(AppStringKeys.contentSizeTitle),
                value: contentSizeValue(theme.fontScale),
                onTap: () => Navigator.of(context).push(
                  AppPageRoute<void>(
                    pageBuilder: (_, _, _) => const ContentSizeSettingsView(),
                  ),
                ),
              ),
              SettingsRow(
                title: AppStrings.t(AppStringKeys.appearanceTextFont),
                value: theme.effectiveFontChainLabel,
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const TextFontView())),
              ),
              SettingsRow(
                title: AppStrings.t(AppStringKeys.appearanceMonospaceFont),
                value: theme.effectiveMonospaceFontLabel,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MonospaceFontPickerView(),
                  ),
                ),
              ),
              SettingsRow(
                title: AppStrings.t(AppStringKeys.appearanceEmojiFont),
                value: theme.emojiFontChoice.label,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const EmojiFontPickerView(),
                  ),
                ),
              ),
              SettingsRow(
                title: AppStrings.t(AppStringKeys.appearanceFontCache),
                value: AppStrings.t(AppStringKeys.appearanceManage),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FontCacheManagementView(),
                  ),
                ),
              ),
            ],
          ),
          SettingsNote(
            text: AppStrings.t(AppStringKeys.appearanceFontChainDescription),
          ),
        ],
      ),
    );
  }
}

class FontCacheManagementView extends StatefulWidget {
  const FontCacheManagementView({super.key});

  @override
  State<FontCacheManagementView> createState() =>
      _FontCacheManagementViewState();
}

class _FontCacheManagementViewState extends State<FontCacheManagementView> {
  late Future<_FontCacheSnapshot> _snapshot = _loadSnapshot();
  _FontCacheOperation? _operation;

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceFontCache),
      onBack: () => Navigator.of(context).pop(),
      child: FutureBuilder<_FontCacheSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: AppActivityIndicator(size: 24));
          }
          final data = snapshot.data!;
          return SettingsListView(
            children: [
              _summaryCard(context, data),
              const SizedBox(height: AppSpacing.xl),
              _actionCard(context, data),
              const SizedBox(height: AppSpacing.xl),
              _fontFilesCard(context, data),
              SettingsNote(
                text: AppStrings.t(
                  AppStringKeys.appearanceFontCacheDescription,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<_FontCacheSnapshot> _loadSnapshot() async {
    final theme = context.read<ThemeController>();
    final supportDir = await getApplicationSupportDirectory();
    final activeFamilies = _activeGoogleFamilies(theme);
    final byFamily = <String, _FontCacheEntry>{};
    if (await supportDir.exists()) {
      await for (final entity in supportDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final entry = await _FontCacheEntry.tryFromFile(entity, activeFamilies);
        if (entry == null) continue;
        final key = entry.normalizedDisplayName;
        final current = byFamily[key];
        byFamily[key] = current == null ? entry : current.merged(entry);
      }
    }
    final entries = byFamily.values.toList();
    entries.sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return _FontCacheSnapshot(entries);
  }

  Set<String> _activeGoogleFamilies(ThemeController theme) {
    final googleFamilies = GoogleFonts.asMap().keys.toSet();
    final active = <String>{};
    void addIfGoogle(String? family) {
      final value = family?.trim();
      if (value == null || value.isEmpty) return;
      final decoded = decodeGoogleFontFamily(value) ?? value;
      if (googleFamilies.contains(decoded)) active.add(decoded);
    }

    for (final family in theme.fontFallbackChain) {
      addIfGoogle(family);
    }
    addIfGoogle(theme.monospaceFontChoice.googleFamily);
    if (theme.monospaceFontChoice.isCustom) {
      addIfGoogle(theme.customMonospaceFontFamily);
    }
    return active;
  }

  Widget _summaryCard(BuildContext context, _FontCacheSnapshot data) {
    return _cacheCard(context, [
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceCacheFiles),
        AppStrings.t(AppStringKeys.appearanceFileCount, {
          'value1': data.entries.length,
        }),
      ),
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceTotalSize),
        _formatBytes(data.totalBytes),
      ),
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceInUseSize),
        AppStrings.t(AppStringKeys.appearanceFileCount, {
          'value1': data.activeCount,
        }),
      ),
      _plainRow(
        context,
        AppStrings.t(AppStringKeys.appearanceCleanableSize),
        AppStrings.t(AppStringKeys.appearanceFileCount, {
          'value1': data.unusedCount,
        }),
      ),
    ]);
  }

  Widget _actionCard(BuildContext context, _FontCacheSnapshot data) {
    final busy = _operation != null;
    return _cacheCard(context, [
      _actionRow(
        context,
        AppStrings.t(AppStringKeys.appearanceRefreshCacheList),
        HeroAppIcons.arrowsRotate.data,
        busy ? null : _refreshSnapshot,
        busy: _operation == _FontCacheOperation.refreshing,
        status: _operation == _FontCacheOperation.refreshed
            ? AppStrings.t(AppStringKeys.appearanceCacheRefreshed)
            : null,
      ),
      _actionRow(
        context,
        AppStrings.t(AppStringKeys.appearanceCleanUnusedFonts),
        HeroAppIcons.trash.data,
        busy || data.unusedCount == 0 ? null : () => _deleteUnused(data),
        destructive: true,
        busy: _operation == _FontCacheOperation.deletingUnused,
        status: _operation == _FontCacheOperation.deletedUnused
            ? AppStrings.t(AppStringKeys.appearanceCacheCleaned)
            : data.unusedCount == 0
            ? AppStrings.t(AppStringKeys.appearanceNoCleanableFonts)
            : null,
      ),
    ]);
  }

  Widget _fontFilesCard(BuildContext context, _FontCacheSnapshot data) {
    final c = context.colors;
    if (data.entries.isEmpty) {
      return SettingsPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xxl,
        ),
        child: Text(
          AppStrings.t(AppStringKeys.appearanceNoDownloadedFontCache),
          style: TextStyle(fontSize: AppTextSize.body, color: c.textSecondary),
        ),
      );
    }
    return _cacheCard(context, [
      for (final entry in data.entries) _fileRow(context, entry),
    ]);
  }

  Widget _cacheCard(BuildContext context, List<Widget> rows) {
    return SettingsCard(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1)
            const InsetDivider(leadingInset: AppSpacing.xxl),
        ],
      ],
    );
  }

  Widget _plainRow(BuildContext context, String label, String value) {
    final c = context.colors;
    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.xxs,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.bodyLarge,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTextSize.body,
                  color: c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback? onTap, {
    bool destructive = false,
    bool busy = false,
    String? status,
  }) {
    final c = context.colors;
    final enabled = onTap != null && !busy;
    final color = destructive ? AppTheme.unreadBadge : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Opacity(
          opacity: enabled || busy || status != null ? 1 : 0.35,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: Row(
              children: [
                Icon(icon, size: AppIconSize.xl, color: color),
                const SizedBox(width: AppSpacing.lg),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextSize.bodyLarge,
                    color: color,
                  ),
                ),
                const Spacer(),
                if (busy)
                  SizedBox(
                    width: AppIconSize.lg,
                    height: AppIconSize.lg,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: destructive
                          ? AppTheme.unreadBadge
                          : AppTheme.brand,
                    ),
                  )
                else if (status != null)
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      color: c.textTertiary,
                    ),
                  )
                else
                  AppIcon(
                    HeroAppIcons.chevronRight,
                    size: AppIconSize.lg,
                    color: enabled && !destructive
                        ? c.textTertiary
                        : Colors.transparent,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileRow(BuildContext context, _FontCacheEntry entry) {
    final c = context.colors;
    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.bodyLarge,
                      color: c.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatBytes(entry.bytes)} · ${entry.modifiedLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.footnote,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              entry.active
                  ? AppStrings.t(AppStringKeys.appearanceFontInUse)
                  : AppStrings.t(AppStringKeys.appearanceFontUnused),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: AppTextSize.footnote,
                color: entry.active ? AppTheme.brand : c.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: entry.active ? null : () => _deleteEntry(entry),
              child: SizedBox(
                width: AppMetric.hitTarget,
                height: AppMetric.hitTarget,
                child: Opacity(
                  opacity: entry.active ? 0.2 : 1,
                  child: Center(
                    child: AppIcon(
                      HeroAppIcons.trash,
                      size: AppIconSize.xl,
                      color: entry.active
                          ? c.textTertiary
                          : AppTheme.unreadBadge,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshSnapshot() async {
    if (_operation != null) return;
    setState(() {
      _operation = _FontCacheOperation.refreshing;
    });
    final snapshot = await _loadSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = Future.value(snapshot);
      _operation = _FontCacheOperation.refreshed;
    });
    _clearOperationSoon(_FontCacheOperation.refreshed);
  }

  Future<void> _deleteUnused(_FontCacheSnapshot data) async {
    if (_operation != null) return;
    setState(() {
      _operation = _FontCacheOperation.deletingUnused;
    });
    for (final entry in data.entries.where((entry) => !entry.active)) {
      try {
        await entry.deleteFiles();
      } catch (_) {
        // The cache may have been removed by the font loader or the OS.
      }
    }
    if (!mounted) return;
    final snapshot = await _loadSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = Future.value(snapshot);
      _operation = _FontCacheOperation.deletedUnused;
    });
    _clearOperationSoon(_FontCacheOperation.deletedUnused);
  }

  Future<void> _deleteEntry(_FontCacheEntry entry) async {
    try {
      await entry.deleteFiles();
    } catch (_) {
      // The cache may have been removed by the font loader or the OS.
    }
    if (!mounted) return;
    final snapshot = await _loadSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = Future.value(snapshot);
    });
  }

  void _clearOperationSoon(_FontCacheOperation operation) {
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (!mounted || _operation != operation) return;
      setState(() {
        _operation = null;
      });
    });
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    if (unit == 0) return '$bytes ${units[unit]}';
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
  }
}

class _FontCacheSnapshot {
  const _FontCacheSnapshot(this.entries);

  final List<_FontCacheEntry> entries;

  int get totalBytes =>
      entries.fold<int>(0, (total, entry) => total + entry.bytes);
  int get activeCount => entries.where((entry) => entry.active).length;
  int get unusedCount => entries.length - activeCount;
}

enum _FontCacheOperation {
  refreshing,
  refreshed,
  deletingUnused,
  deletedUnused,
}

class _FontCacheEntry {
  const _FontCacheEntry({
    required this.files,
    required this.displayName,
    required this.bytes,
    required this.modified,
    required this.active,
  });

  static final _cacheFilePattern = RegExp(r'^(.+)_([a-fA-F0-9]{16,128})\.ttf$');

  final List<File> files;
  final String displayName;
  final int bytes;
  final DateTime modified;
  final bool active;

  String get normalizedDisplayName => _normalize(displayName);

  String get modifiedLabel {
    final local = modified.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  static Future<_FontCacheEntry?> tryFromFile(
    File file,
    Set<String> activeGoogleFamilies,
  ) async {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
    final match = _cacheFilePattern.firstMatch(name);
    if (match == null) return null;
    final rawFamily = match.group(1)!;
    final displayName = _displayName(rawFamily);
    final stat = await file.stat();
    final normalizedFile = _normalize(rawFamily);
    final active = activeGoogleFamilies.any((family) {
      final normalizedFamily = _normalize(family);
      return normalizedFile.contains(normalizedFamily) ||
          normalizedFamily.contains(normalizedFile);
    });
    return _FontCacheEntry(
      files: [file],
      displayName: displayName,
      bytes: stat.size,
      modified: stat.modified,
      active: active,
    );
  }

  _FontCacheEntry merged(_FontCacheEntry other) {
    return _FontCacheEntry(
      files: [...files, ...other.files],
      displayName: displayName,
      bytes: bytes + other.bytes,
      modified: modified.isAfter(other.modified) ? modified : other.modified,
      active: active || other.active,
    );
  }

  Future<void> deleteFiles() async {
    for (final file in files) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Individual cache files can disappear while the list is open.
      }
    }
  }

  static String _displayName(String rawFamily) {
    final value = rawFamily
        .replaceAll(RegExp(r'_(regular|italic)$', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'_(100|200|300|400|500|600|700|800|900)(italic)?$'),
          '',
        )
        .replaceAll('_', ' ');
    return value.trim().isEmpty ? rawFamily : value.trim();
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

Future<Set<String>> _cachedGoogleFontFamilies() async {
  final googleFamilies = GoogleFonts.asMap().keys.toList();
  final byNormalized = {
    for (final family in googleFamilies)
      _FontCacheEntry._normalize(family): family,
  };
  final supportDir = await getApplicationSupportDirectory();
  final cached = <String>{};
  if (!await supportDir.exists()) return cached;
  await for (final entity in supportDir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.isEmpty
        ? entity.path
        : entity.uri.pathSegments.last;
    final match = _FontCacheEntry._cacheFilePattern.firstMatch(name);
    if (match == null) continue;
    final rawFamily = match.group(1)!;
    final normalizedFile = _FontCacheEntry._normalize(rawFamily);
    final exact = byNormalized[normalizedFile];
    if (exact != null) {
      cached.add(exact);
      continue;
    }
    for (final entry in byNormalized.entries) {
      if (normalizedFile.contains(entry.key) ||
          entry.key.contains(normalizedFile)) {
        cached.add(entry.value);
        break;
      }
    }
  }
  return cached;
}

List<String> _fontTitleFallback() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => [
      AppFontChoice.apple.fontFamily,
      'SF Pro',
      'Helvetica Neue',
      'Arial',
    ],
    TargetPlatform.android => const ['sans-serif', 'Roboto', 'Noto Sans'],
    _ => const ['sans-serif', 'Arial'],
  };
}

TextStyle _fontTitleStyle(
  String family,
  TextStyle base, {
  String? googleFamily,
  bool googleLoaded = false,
}) {
  final fallback = _fontTitleFallback();
  if (googleFamily != null && googleLoaded) {
    return GoogleFonts.getFont(
      googleFamily,
      textStyle: base,
    ).copyWith(fontFamilyFallback: fallback);
  }
  if (googleFamily != null) return base.copyWith(fontFamilyFallback: fallback);
  return base.copyWith(
    fontFamily: AppFontChoice.resolvePlatformFontFamily(family),
    fontFamilyFallback: fallback,
  );
}

String _fontPreviewSample() => appFontPreviewText;

int _popularSystemFontPriority(String family) {
  final popular = switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => [
      AppFontChoice.apple.fontFamily,
      'SF Pro',
      'Helvetica Neue',
      'Helvetica',
      'Avenir Next',
      'Avenir',
      'Futura',
      'Gill Sans',
      'Optima',
      'Palatino',
      'Georgia',
      'Times New Roman',
      'Didot',
      'American Typewriter',
      'Courier New',
      'Menlo',
      'PingFang SC',
      'PingFang TC',
      'PingFang HK',
      'Hiragino Sans',
    ],
    TargetPlatform.android => const [
      'sans',
      'sans-serif',
      'Roboto',
      'Noto Sans',
      'Noto Serif',
      'Droid Sans',
      'monospace',
      'serif',
    ],
    TargetPlatform.windows => const [
      'Segoe UI',
      'Segoe UI Variable',
      'Yu Gothic UI',
      'Microsoft YaHei UI',
      'Malgun Gothic',
      'Calibri',
      'Arial',
      'Cambria',
      'Georgia',
      'Times New Roman',
      'Consolas',
      'Cascadia Mono',
      'Courier New',
    ],
    TargetPlatform.linux => const [
      'Ubuntu',
      'Cantarell',
      'Noto Sans',
      'DejaVu Sans',
      'Liberation Sans',
      'Noto Serif',
      'DejaVu Serif',
      'DejaVu Sans Mono',
      'Liberation Mono',
      'Ubuntu Mono',
      'monospace',
      'sans-serif',
      'serif',
    ],
    _ => const [
      'Arial',
      'Helvetica',
      'Verdana',
      'Tahoma',
      'Georgia',
      'Times New Roman',
      'Courier New',
      'monospace',
      'sans-serif',
      'serif',
    ],
  };
  final exact = popular.indexWhere(
    (font) => font.toLowerCase() == family.toLowerCase(),
  );
  if (exact >= 0) return exact;
  final prefix = popular.indexWhere(
    (font) => family.toLowerCase().startsWith(font.toLowerCase()),
  );
  return prefix >= 0 ? prefix : popular.length + 1;
}

const _googleMonospaceFamilies = {
  'Anonymous Pro',
  'Azeret Mono',
  'B612 Mono',
  'Chivo Mono',
  'Courier Prime',
  'Cousine',
  'Cutive Mono',
  'DM Mono',
  'Datatype',
  'Fira Code',
  'Fira Mono',
  'Fragment Mono',
  'Geist Mono',
  'Google Sans Code',
  'IBM Plex Mono',
  'Inconsolata',
  'Intel One Mono',
  'Iosevka Charon',
  'Iosevka Charon Mono',
  'JetBrains Mono',
  'Kode Mono',
  'LXGW WenKai Mono TC',
  'Lekton',
  'Libertinus Mono',
  'Lilex',
  'M PLUS 1 Code',
  'M PLUS Code Latin',
  'Major Mono Display',
  'Martian Mono',
  'Monofett',
  'Nanum Gothic Coding',
  'Noto Sans Mono',
  'Nova Mono',
  'Overpass Mono',
  'Oxygen Mono',
  'PT Mono',
  'Red Hat Mono',
  'Reddit Mono',
  'Roboto Mono',
  'Rubik Mono One',
  'Share Tech Mono',
  'Sixtyfour',
  'Sixtyfour Convergence',
  'Sometype Mono',
  'Sono',
  'Source Code Pro',
  'Space Mono',
  'Spline Sans Mono',
  'Syne Mono',
  'Ubuntu Mono',
  'Ubuntu Sans Mono',
  'VT323',
  'Victor Mono',
  'Workbench',
  'Xanh Mono',
};

bool _isSystemMonospaceFontFamily(String family) {
  final normalized = family.toLowerCase();
  return normalized.contains('mono') ||
      normalized.contains('menlo') ||
      normalized.contains('monaco') ||
      normalized.contains('courier') ||
      normalized.contains('consolas') ||
      normalized.contains('cascadia') ||
      normalized.contains('lucida console') ||
      normalized.contains('fira code') ||
      normalized.contains('source code') ||
      normalized.contains('inconsolata');
}

class TextFontView extends StatelessWidget {
  const TextFontView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final fonts = theme.fontFallbackChain;
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceTextFont),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          _chainCard(context, fonts),
          const SizedBox(height: AppSpacing.xl),
          _actionCard(context, theme),
          SettingsNote(
            text: AppStrings.t(AppStringKeys.appearanceTextFontOrderHint),
          ),
        ],
      ),
    );
  }

  Widget _chainCard(BuildContext context, List<String> fonts) {
    final c = context.colors;
    if (fonts.isEmpty) {
      return SettingsPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xxl,
        ),
        child: Text(
          AppStrings.t(AppStringKeys.appearanceTextFontUnsetHint),
          style: TextStyle(fontSize: AppTextSize.body, color: c.textSecondary),
        ),
      );
    }
    return SettingsPanel(
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: fonts.length,
        onReorderItem: context.read<ThemeController>().moveFontInFallbackChain,
        itemBuilder: (context, index) {
          final family = fonts[index];
          return Column(
            key: ValueKey('font-chain-$family-$index'),
            children: [
              _chainRow(context, family, index),
              if (index < fonts.length - 1)
                const InsetDivider(leadingInset: AppSpacing.xxl),
            ],
          );
        },
      ),
    );
  }

  Widget _chainRow(BuildContext context, String family, int index) {
    final c = context.colors;
    final googleFamily = decodeGoogleFontFamily(family);
    final displayFamily = displayStoredFontFamily(family);
    TextStyle previewStyle(TextStyle base) {
      if (googleFamily != null) {
        return GoogleFonts.getFont(googleFamily, textStyle: base);
      }
      return base.copyWith(fontFamily: family);
    }

    return SizedBox(
      height: AppMetric.menuRowHeight + AppSpacing.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: AppIcon(
                HeroAppIcons.bars,
                size: AppIconSize.xl,
                color: c.textTertiary,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayFamily,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _fontTitleStyle(
                      family,
                      TextStyle(
                        fontSize: AppTextSize.bodyLarge,
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      googleFamily: googleFamily,
                      googleLoaded: googleFamily != null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _fontPreviewSample(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: previewStyle(
                      TextStyle(
                        fontSize: AppTextSize.footnote,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context
                  .read<ThemeController>()
                  .removeFontFromFallbackChainAt(index),
              child: SizedBox(
                width: AppMetric.hitTarget,
                height: AppMetric.hitTarget,
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.trash,
                    size: AppIconSize.xl,
                    color: c.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(BuildContext context, ThemeController theme) {
    return SettingsCard(
      children: [
        _actionRow(
          context,
          AppStrings.t(AppStringKeys.appearanceAddTextFont),
          HeroAppIcons.plus.data,
          () async {
            final family = await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => const FontAddView()),
            );
            if (family == null || !context.mounted) return;
            context.read<ThemeController>().addFontToFallbackChain(family);
          },
        ),
        if (theme.fontFallbackChain.isNotEmpty) ...[
          const InsetDivider(leadingInset: AppSpacing.xxl),
          _actionRow(
            context,
            AppStrings.t(AppStringKeys.appearanceClearTextFonts),
            HeroAppIcons.xmark.data,
            () => context.read<ThemeController>().setFontFallbackChain(
              const <String>[],
            ),
            destructive: true,
          ),
        ],
      ],
    );
  }

  Widget _actionRow(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap, {
    bool destructive = false,
  }) {
    final c = context.colors;
    final color = destructive ? AppTheme.unreadBadge : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.xxs,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Icon(icon, size: AppIconSize.xl, color: color),
              const SizedBox(width: AppSpacing.lg),
              Text(
                title,
                style: TextStyle(fontSize: AppTextSize.bodyLarge, color: color),
              ),
              const Spacer(),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: AppIconSize.lg,
                color: destructive ? Colors.transparent : c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmojiFontPickerView extends StatefulWidget {
  const EmojiFontPickerView({super.key});

  @override
  State<EmojiFontPickerView> createState() => _EmojiFontPickerViewState();
}

class _EmojiFontPickerViewState extends State<EmojiFontPickerView> {
  static const _fallbackPreviewAsset = 'assets/emoji_preview/noto.svg';
  static const _previewAssets = {
    'noto': 'assets/emoji_preview/noto.svg',
    'noto-mono': 'assets/emoji_preview/noto-mono.svg',
    'blobmoji': 'assets/emoji_preview/blobmoji.svg',
    'fluent': 'assets/emoji_preview/fluent.png',
    'fluent-flat': 'assets/emoji_preview/fluent-flat.svg',
    'fluent-mono': 'assets/emoji_preview/fluent-mono.svg',
    'twemoji': 'assets/emoji_preview/twemoji.svg',
    'openmoji': 'assets/emoji_preview/openmoji.svg',
    'emojitwo': 'assets/emoji_preview/emojitwo.svg',
    'tossface': 'assets/emoji_preview/tossface.svg',
  };

  late final Future<List<EmojiFontManifestEntry>> _fonts = EmojiFontCatalog
      .shared
      .loadManifest(forceRefresh: true);
  String? _loadingKey;
  String? _failedKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceEmojiFont),
      onBack: () => Navigator.of(context).pop(),
      child: FutureBuilder<List<EmojiFontManifestEntry>>(
        future: _fonts,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: AppActivityIndicator(size: 24));
          }
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Text(
                AppStrings.t(AppStringKeys.appearanceFontLoadFailed),
                style: TextStyle(
                  fontSize: AppTextSize.bodyLarge,
                  color: c.textSecondary,
                ),
              ),
            );
          }
          final entries = snapshot.data ?? const <EmojiFontManifestEntry>[];
          return SettingsListView(
            children: [
              SettingsCard.rows(
                dividerInset: AppMetric.settingsTextDividerInset,
                rows: [
                  _systemRow(context, theme),
                  for (final entry in entries) _entryRow(context, entry, theme),
                ],
              ),
              SettingsNote(
                text: AppStrings.t(
                  AppStringKeys.appearanceEmojiFontCatalogDescription,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _systemRow(BuildContext context, ThemeController theme) {
    return _row(
      context,
      title: EmojiFontChoice.system.label,
      subtitle: AppStrings.t(AppStringKeys.appearanceSystemEmojiFont),
      preview: const _SystemEmojiPreview(),
      selected: theme.emojiFontChoice.isSystem,
      loading: false,
      failed: false,
      onTap: () {
        context.read<ThemeController>().useSystemEmojiFont();
        setState(() {
          _loadingKey = null;
          _failedKey = null;
        });
      },
    );
  }

  Widget _entryRow(
    BuildContext context,
    EmojiFontManifestEntry entry,
    ThemeController theme,
  ) {
    return _row(
      context,
      title: entry.label,
      subtitle: [
        entry.license,
        if (entry.emojiVersion.isNotEmpty) 'Emoji ${entry.emojiVersion}',
      ].where((part) => part.isNotEmpty).join(' · '),
      preview: _EmojiPreviewImage(asset: _previewAssetForKey(entry.key)),
      selected: theme.emojiFontChoice.key == entry.key,
      loading: _loadingKey == entry.key,
      failed: _failedKey == entry.key,
      onTap: () async {
        if (_loadingKey != null) return;
        setState(() {
          _loadingKey = entry.key;
          _failedKey = null;
        });
        try {
          await context.read<ThemeController>().setEmojiFont(entry);
        } catch (_) {
          if (mounted) setState(() => _failedKey = entry.key);
        } finally {
          if (mounted) setState(() => _loadingKey = null);
        }
      },
    );
  }

  Widget _row(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget preview,
    required bool selected,
    required bool loading,
    required bool failed,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Semantics(
                  label: AppStringKeys.emojiPreviewFaceWithTearsOfJoy.l10n(
                    context,
                  ),
                  image: true,
                  child: ExcludeSemantics(child: preview),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTextSize.bodyLarge,
                        color: c.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      failed
                          ? AppStrings.t(
                              AppStringKeys.appearanceFontDownloadFailedName,
                              {'value1': subtitle},
                            )
                          : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: AppTextSize.footnote,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: AppIconSize.lg,
                  height: AppIconSize.lg,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (selected)
                AppIcon(
                  HeroAppIcons.check,
                  size: AppIconSize.lg,
                  color: AppTheme.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _previewAssetForKey(String key) =>
      _previewAssets[key] ?? _fallbackPreviewAsset;
}

/// Draws the preview glyph with the platform emoji font itself, so the row
/// shows what the system default actually looks like instead of a bundled
/// picture of somebody else's emoji set.
class _SystemEmojiPreview extends StatelessWidget {
  const _SystemEmojiPreview();

  static const _faceWithTearsOfJoy = '\u{1F602}';

  @override
  Widget build(BuildContext context) {
    final families = EmojiFontChoice.platformEmojiFontFallback();
    return SizedBox(
      width: 26,
      height: 26,
      child: Center(
        child: Text(
          _faceWithTearsOfJoy,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            height: 1,
            fontFamily: families.firstOrNull,
            fontFamilyFallback: families.skip(1).toList(),
          ),
        ),
      ),
    );
  }
}

class _EmojiPreviewImage extends StatelessWidget {
  const _EmojiPreviewImage({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    if (asset.endsWith('.svg')) {
      return SvgPicture.asset(
        asset,
        width: 26,
        height: 26,
        placeholderBuilder: (_) => const _TearJoyFallbackIcon(),
        errorBuilder: (_, _, _) => const _TearJoyFallbackIcon(),
      );
    }
    return Image.asset(
      asset,
      width: 26,
      height: 26,
      errorBuilder: (_, _, _) => const _TearJoyFallbackIcon(),
    );
  }
}

class _TearJoyFallbackIcon extends StatelessWidget {
  const _TearJoyFallbackIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(painter: _TearJoyFallbackPainter()),
    );
  }
}

class _TearJoyFallbackPainter extends CustomPainter {
  const _TearJoyFallbackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final face = Paint()..color = const Color(0xFFFFD447);
    final stroke = Paint()
      ..color = const Color(0xFF5A3210)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.width * 0.08;
    final tear = Paint()..color = const Color(0xFF37A8FF);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.43;
    canvas.drawCircle(center, radius, face);

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.34, size.height * 0.39),
        width: size.width * 0.28,
        height: size.height * 0.18,
      ),
      0.15,
      2.6,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.66, size.height * 0.39),
        width: size.width * 0.28,
        height: size.height * 0.18,
      ),
      0.4,
      2.6,
      false,
      stroke,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.55),
        width: size.width * 0.48,
        height: size.height * 0.34,
      ),
      0.1,
      2.95,
      false,
      stroke,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.18, size.height * 0.58),
        width: size.width * 0.18,
        height: size.height * 0.28,
      ),
      tear,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.82, size.height * 0.58),
        width: size.width * 0.18,
        height: size.height * 0.28,
      ),
      tear,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FontAddView extends StatefulWidget {
  const FontAddView({super.key});

  @override
  State<FontAddView> createState() => _FontAddViewState();
}

class _FontAddViewState extends State<FontAddView> {
  late final Future<List<_FontCandidate>> _fonts = _loadFonts();
  String _query = '';
  String? _loadingGoogleFamily;
  String? _failedGoogleFamily;
  Timer? _searchDebounce;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<_FontCandidate>> _loadFonts() async {
    final systemFonts = await SystemFontCatalog.loadFonts();
    final cachedGoogleFamilies = await _cachedGoogleFontFamilies();
    final candidates = <_FontCandidate>[
      for (final font in systemFonts)
        _FontCandidate(
          label: font,
          family: font,
          preview: _fontPreviewSample(),
          source: AppStringKeys.appearanceSystem,
          priority: _popularSystemFontPriority(font),
        ),
      for (final family in GoogleFonts.asMap().keys)
        _FontCandidate(
          label: family,
          family: family,
          preview: _fontPreviewSample(),
          source: 'Google',
          google: true,
          downloaded: cachedGoogleFamilies.contains(family),
        ),
    ];
    return candidates..sort((a, b) {
      final sourceCompare = a.sourceOrder.compareTo(b.sourceOrder);
      if (sourceCompare != 0) return sourceCompare;
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.lowerLabel.compareTo(b.lowerLabel);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceAddFont),
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        children: [
          Padding(
            padding: AppInsets.screen.copyWith(bottom: AppSpacing.sm),
            child: SettingsSearchField(
              controller: _searchController,
              hintText: AppStringKeys.appearanceSearchFont,
              // Each filter pass scans the ~1900 Google families; a keystroke
              // burst should only pay for the query the user settles on.
              onChanged: (value) {
                final next = value.trim();
                _searchDebounce?.cancel();
                if (next == _query) return;
                _searchDebounce = Timer(
                  const Duration(milliseconds: 150),
                  () => setState(() => _query = next),
                );
              },
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_FontCandidate>>(
              future: _fonts,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: AppActivityIndicator(size: 24));
                }
                final query = _query.toLowerCase();
                final fonts = snapshot.data!
                    .where(
                      (font) =>
                          query.isEmpty ||
                          font.lowerLabel.contains(query) ||
                          font.lowerFamily.contains(query),
                    )
                    .toList();
                return _fontList(context, fonts);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _fontList(BuildContext context, List<_FontCandidate> fonts) {
    final c = context.colors;
    if (fonts.isEmpty) {
      return ListView(
        padding: AppInsets.screen.copyWith(top: AppSpacing.sm),
        children: [
          SettingsPanel(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              AppStrings.t(AppStringKeys.appearanceNoMatchingFonts),
              style: TextStyle(
                fontSize: AppTextSize.body,
                color: c.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: AppInsets.screen.copyWith(top: AppSpacing.sm),
      itemCount: fonts.length,
      itemBuilder: (context, index) => _virtualRow(
        context,
        first: index == 0,
        last: index == fonts.length - 1,
        child: _fontRow(context, fonts[index]),
      ),
      separatorBuilder: (context, index) => ColoredBox(
        color: c.card,
        child: const InsetDivider(leadingInset: AppSpacing.xxl),
      ),
    );
  }

  Widget _virtualRow(
    BuildContext context, {
    required bool first,
    required bool last,
    required Widget child,
  }) {
    const radius = Radius.circular(AppRadius.card);
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: first ? radius : Radius.zero,
        bottom: last ? radius : Radius.zero,
      ),
      child: ColoredBox(color: context.colors.card, child: child),
    );
  }

  Widget _fontRow(BuildContext context, _FontCandidate font) {
    final c = context.colors;
    final loading = font.google && _loadingGoogleFamily == font.family;
    final failed = font.google && _failedGoogleFamily == font.family;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectFont(context, font),
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      font.label.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.titleStyle(
                        TextStyle(
                          fontSize: AppTextSize.bodyLarge,
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      font.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.previewStyle(
                        TextStyle(
                          fontSize: AppTextSize.footnote,
                          color: c.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                failed
                    ? AppStrings.t(AppStringKeys.appearanceDownloadFailed)
                    : font.google && font.downloaded
                    ? AppStrings.t(AppStringKeys.appearanceGoogleDownloaded)
                    : font.source.l10n(context),
                style: TextStyle(
                  fontSize: AppTextSize.footnote,
                  color: c.textTertiary,
                ),
              ),
              if (loading) ...[
                const SizedBox(width: AppSpacing.md),
                SizedBox(
                  width: 48,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppTheme.brand,
                    backgroundColor: c.divider,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectFont(BuildContext context, _FontCandidate font) async {
    if (!font.google) {
      Navigator.of(context).pop(font.selectionFamily);
      return;
    }
    if (_loadingGoogleFamily != null) return;
    setState(() {
      _loadingGoogleFamily = font.family;
      _failedGoogleFamily = null;
    });
    try {
      GoogleFonts.getFont(font.family, textStyle: const TextStyle());
      await GoogleFonts.pendingFonts();
      if (!context.mounted) return;
      Navigator.of(context).pop(font.selectionFamily);
    } catch (_) {
      if (!mounted || _loadingGoogleFamily != font.family) return;
      setState(() => _failedGoogleFamily = font.family);
    } finally {
      if (mounted && _loadingGoogleFamily == font.family) {
        setState(() => _loadingGoogleFamily = null);
      }
    }
  }
}

class _FontCandidate {
  _FontCandidate({
    required this.label,
    required this.family,
    required this.preview,
    required this.source,
    this.google = false,
    this.downloaded = false,
    this.priority = 0,
  }) : lowerLabel = label.toLowerCase(),
       lowerFamily = family.toLowerCase();

  final String label;
  final String family;
  // Search keys for the ~1900 candidates, folded once at construction instead
  // of twice per candidate per keystroke.
  final String lowerLabel;
  final String lowerFamily;
  final String preview;
  final String source;
  final bool google;
  final bool downloaded;
  final int priority;

  String get selectionFamily =>
      google ? encodeGoogleFontFamily(family) : family;

  TextStyle titleStyle(TextStyle base) {
    return _fontTitleStyle(
      family,
      base,
      googleFamily: google ? family : null,
      googleLoaded: downloaded,
    );
  }

  TextStyle previewStyle(TextStyle base) {
    if (google) {
      return downloaded ? GoogleFonts.getFont(family, textStyle: base) : base;
    }
    return base.copyWith(fontFamily: family);
  }

  int get sourceOrder => switch (source) {
    AppStringKeys.appearanceSystem => 0,
    'Google' => 1,
    _ => 4,
  };
}

class _MonoFontCandidate {
  const _MonoFontCandidate({
    required this.label,
    required this.family,
    required this.preview,
    required this.source,
    this.choice,
    this.google = false,
    this.downloaded = false,
    required this.priority,
  });

  final String label;
  final String family;
  final String preview;
  final String source;
  final AppMonospaceFontChoice? choice;
  final bool google;
  final bool downloaded;
  final int priority;

  String get selectionKey {
    final selectedChoice = choice;
    if (selectedChoice != null && !google) {
      return 'choice:${selectedChoice.name}';
    }
    if (google) return 'google:$family';
    return 'system:$family';
  }

  TextStyle previewStyle(TextStyle base, {required bool selected}) {
    if (google && (selected || downloaded)) {
      return GoogleFonts.getFont(family, textStyle: base);
    }
    if (google) return base;
    return base.copyWith(fontFamily: family);
  }

  TextStyle titleStyle(TextStyle base, {required bool selected}) {
    return _fontTitleStyle(
      family,
      base,
      googleFamily: google ? family : null,
      googleLoaded: selected || downloaded,
    );
  }
}

class MonospaceFontPickerView extends StatefulWidget {
  const MonospaceFontPickerView({super.key});

  @override
  State<MonospaceFontPickerView> createState() =>
      _MonospaceFontPickerViewState();
}

class _MonospaceFontPickerViewState extends State<MonospaceFontPickerView> {
  late final Future<List<_MonoFontCandidate>> _fonts = _loadFonts();
  String? _loadingGoogleFamily;
  String? _failedGoogleFamily;

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    final selectedKey = _selectedKey(theme);
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.appearanceMonospaceFont),
      onBack: () => Navigator.of(context).pop(),
      child: FutureBuilder<List<_MonoFontCandidate>>(
        future: _fonts,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: AppActivityIndicator(size: 24));
          }
          return _fontList(context, snapshot.data!, selectedKey);
        },
      ),
    );
  }

  Future<List<_MonoFontCandidate>> _loadFonts() async {
    final systemFonts = await SystemFontCatalog.loadFonts();
    final cachedGoogleFamilies = await _cachedGoogleFontFamilies();
    final candidates = <_MonoFontCandidate>[
      ..._preferredPlatformMonospaceFonts(),
      ..._googleMonospaceFonts(cachedGoogleFamilies),
      for (final family in systemFonts.where(_isSystemMonospaceFontFamily))
        _MonoFontCandidate(
          label: family,
          family: family,
          preview: appMonospaceFontPreviewText,
          source: AppStringKeys.appearanceSystem,
          priority: _systemMonospacePriority(family),
        ),
    ];
    final byKey = <String, _MonoFontCandidate>{};
    for (final candidate in candidates) {
      byKey.putIfAbsent(candidate.selectionKey, () => candidate);
    }
    return byKey.values.toList()..sort((a, b) {
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      final sourceCompare = a.source.compareTo(b.source);
      if (sourceCompare != 0) return sourceCompare;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
  }

  List<_MonoFontCandidate> _preferredPlatformMonospaceFonts() {
    final choices = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        AppMonospaceFontChoice.sfMono,
        AppMonospaceFontChoice.menlo,
        AppMonospaceFontChoice.courierNew,
      ],
      TargetPlatform.android => const [
        AppMonospaceFontChoice.system,
        AppMonospaceFontChoice.courierNew,
      ],
      _ => const [
        AppMonospaceFontChoice.system,
        AppMonospaceFontChoice.courierNew,
      ],
    };
    return [
      for (var i = 0; i < choices.length; i++)
        _MonoFontCandidate(
          label: choices[i].label,
          family: choices[i].fontFamily,
          preview: choices[i].previewText,
          source: AppStringKeys.appearanceSystem,
          choice: choices[i],
          priority: i,
        ),
    ];
  }

  List<_MonoFontCandidate> _googleMonospaceFonts(
    Set<String> cachedGoogleFamilies,
  ) {
    final families =
        GoogleFonts.asMap().keys
            .where(_googleMonospaceFamilies.contains)
            .toList()
          ..sort((a, b) {
            final priorityCompare = _googleMonospacePriority(
              a,
            ).compareTo(_googleMonospacePriority(b));
            if (priorityCompare != 0) return priorityCompare;
            return a.toLowerCase().compareTo(b.toLowerCase());
          });
    return [
      for (final family in families)
        _MonoFontCandidate(
          label: family,
          family: family,
          preview: appMonospaceFontPreviewText,
          source: 'Google',
          google: true,
          downloaded: cachedGoogleFamilies.contains(family),
          priority: 100 + _googleMonospacePriority(family),
        ),
    ];
  }

  int _systemMonospacePriority(String family) {
    final priorities = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const [
        'SF Mono',
        'Menlo',
        'Courier',
        'Courier New',
      ],
      TargetPlatform.android => const [
        'monospace',
        'Roboto Mono',
        'Noto Sans Mono',
      ],
      TargetPlatform.windows => const [
        'Consolas',
        'Cascadia Mono',
        'Cascadia Code',
        'Courier New',
        'Lucida Console',
      ],
      TargetPlatform.linux => const [
        'monospace',
        'DejaVu Sans Mono',
        'Liberation Mono',
        'Ubuntu Mono',
        'Noto Sans Mono',
      ],
      _ => const ['monospace', 'Courier New'],
    };
    final exact = priorities.indexWhere((value) => value == family);
    if (exact >= 0) return 10 + exact;
    final prefix = priorities.indexWhere((value) => family.startsWith(value));
    if (prefix >= 0) return 10 + prefix;
    return 50;
  }

  int _googleMonospacePriority(String family) {
    const priorities = [
      'Roboto Mono',
      'Source Code Pro',
      'JetBrains Mono',
      'Fira Code',
      'IBM Plex Mono',
      'Noto Sans Mono',
      'Space Mono',
      'Inconsolata',
      'Ubuntu Mono',
      'Anonymous Pro',
      'DM Mono',
      'Red Hat Mono',
      'Geist Mono',
      'Courier Prime',
    ];
    final index = priorities.indexOf(family);
    return index >= 0 ? index : 60;
  }

  String _selectedKey(ThemeController theme) {
    final selected = theme.monospaceFontChoice;
    if (selected.isCustom) {
      final customFamily = theme.customMonospaceFontFamily.trim();
      final googleFamily = decodeGoogleFontFamily(customFamily);
      if (googleFamily != null) return 'google:$googleFamily';
      if (customFamily.isNotEmpty) return 'system:$customFamily';
      return 'choice:${AppMonospaceFontChoice.system.name}';
    }
    if (selected.googleFamily != null) return 'google:${selected.googleFamily}';
    return 'choice:${selected.name}';
  }

  Widget _fontList(
    BuildContext context,
    List<_MonoFontCandidate> fonts,
    String selectedKey,
  ) {
    final c = context.colors;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.section,
      ),
      itemCount: fonts.length,
      itemBuilder: (context, index) {
        final font = fonts[index];
        return _virtualRow(
          context,
          first: index == 0,
          last: index == fonts.length - 1,
          child: _fontRow(
            context,
            font,
            selected: selectedKey == font.selectionKey,
            loading: font.google && _loadingGoogleFamily == font.family,
            failed: font.google && _failedGoogleFamily == font.family,
            onTap: () {
              final theme = context.read<ThemeController>();
              final choice = font.choice;
              if (choice != null && !font.google) {
                theme.monospaceFontChoice = choice;
                _trackGoogleFontLoad(null);
                return;
              }
              theme.customMonospaceFontFamily = font.google
                  ? encodeGoogleFontFamily(font.family)
                  : font.family;
              theme.monospaceFontChoice = AppMonospaceFontChoice.custom;
              _trackGoogleFontLoad(font.google ? font.family : null);
            },
          ),
        );
      },
      separatorBuilder: (context, index) => ColoredBox(
        color: c.card,
        child: const InsetDivider(leadingInset: AppSpacing.xxl),
      ),
    );
  }

  Widget _virtualRow(
    BuildContext context, {
    required bool first,
    required bool last,
    required Widget child,
  }) {
    const radius = Radius.circular(AppRadius.card);
    return ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: first ? radius : Radius.zero,
        bottom: last ? radius : Radius.zero,
      ),
      child: ColoredBox(color: context.colors.card, child: child),
    );
  }

  Widget _fontRow(
    BuildContext context,
    _MonoFontCandidate font, {
    required bool selected,
    required bool loading,
    required bool failed,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: AppMetric.menuRowHeight + AppSpacing.md,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      font.label.l10n(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.titleStyle(
                        TextStyle(
                          fontSize: AppTextSize.bodyLarge,
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                        selected: selected,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      font.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: font.previewStyle(
                        TextStyle(
                          fontSize: AppTextSize.footnote,
                          color: c.textSecondary,
                        ),
                        selected: selected,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                failed
                    ? AppStrings.t(AppStringKeys.appearanceDownloadFailed)
                    : font.google && font.downloaded
                    ? AppStrings.t(AppStringKeys.appearanceGoogleDownloaded)
                    : font.source.l10n(context),
                style: TextStyle(
                  fontSize: AppTextSize.footnote,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (loading) ...[
                SizedBox(
                  width: 48,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AppTheme.brand,
                    backgroundColor: c.divider,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (!loading && failed) ...[
                Text(
                  AppStrings.t(AppStringKeys.appearanceDownloadFailed),
                  style: TextStyle(
                    fontSize: AppTextSize.footnote,
                    color: c.textTertiary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (selected)
                AppIcon(
                  HeroAppIcons.check,
                  size: AppIconSize.lg,
                  color: AppTheme.brand,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _trackGoogleFontLoad(String? googleFamily) {
    if (googleFamily == null) {
      if (_loadingGoogleFamily != null || _failedGoogleFamily != null) {
        setState(() {
          _loadingGoogleFamily = null;
          _failedGoogleFamily = null;
        });
      }
      return;
    }
    setState(() {
      _loadingGoogleFamily = googleFamily;
      _failedGoogleFamily = null;
    });
    try {
      GoogleFonts.getFont(googleFamily, textStyle: const TextStyle());
    } catch (_) {
      if (!mounted || _loadingGoogleFamily != googleFamily) return;
      setState(() {
        _loadingGoogleFamily = null;
        _failedGoogleFamily = googleFamily;
      });
      return;
    }
    GoogleFonts.pendingFonts().then(
      (_) {
        if (!mounted || _loadingGoogleFamily != googleFamily) return;
        setState(() => _loadingGoogleFamily = null);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || _loadingGoogleFamily != googleFamily) return;
        setState(() {
          _loadingGoogleFamily = null;
          _failedGoogleFamily = googleFamily;
        });
      },
    );
  }
}

class ChannelBottomBarSettingsView extends StatelessWidget {
  const ChannelBottomBarSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeController>();
    const appearance = AppearanceView();
    return SettingsPageScaffold(
      key: const ValueKey('channel-bottom-bar-settings-page'),
      title: AppStrings.t(AppStringKeys.channelBottomBar),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          appearance._card(context, [
            for (final mode in ChannelBottomBarMode.values)
              KeyedSubtree(
                key: ValueKey('channel-bottom-bar-${mode.name}'),
                child: appearance._choiceRow(
                  context,
                  mode.icon.data,
                  AppStrings.t(mode.label),
                  theme.channelBottomBarMode == mode,
                  () => theme.channelBottomBarMode = mode,
                ),
              ),
          ]),
          SettingsNote(text: AppStrings.t(AppStringKeys.channelBottomBarNote)),
        ],
      ),
    );
  }
}
