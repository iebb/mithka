import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chat/custom_emoji.dart';
import '../chat/emoji_store.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

Future<void> showEmojiStatusPicker(
  BuildContext context, {
  required int currentStatusId,
}) async {
  EmojiStore.shared.loadIfNeeded();
  final optionsFuture = _statusOptions();
  await showCupertinoModalPopup<void>(
    context: context,
    builder: (sheetContext) {
      final c = sheetContext.colors;
      final maxHeight = MediaQuery.of(sheetContext).size.height * 0.6;

      Future<void> pick(int id) async {
        final ok = await _setEmojiStatus(id);
        if (!sheetContext.mounted) return;
        Navigator.of(sheetContext).pop();
        if (!ok && context.mounted) {
          showToast(
            context,
            AppStrings.t(AppStringKeys.emojiStatusSetRequiresPremiumFailed),
          );
        }
      }

      Widget grid(List<int> ids) {
        if (ids.isEmpty) {
          return Center(
            child: Text(
              AppStrings.t(AppStringKeys.emojiStatusNoAvailableStatuses),
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 6,
          ),
          itemCount: ids.length,
          itemBuilder: (context, index) {
            final id = ids[index];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => pick(id),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: CustomEmojiView(id: id, size: 34, color: c.textPrimary),
              ),
            );
          },
        );
      }

      var statusTab = 0;
      return DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: maxHeight,
                child: ListenableBuilder(
                  listenable: EmojiStore.shared,
                  builder: (ctx, _) {
                    final packs = EmojiStore.shared.isPremium
                        ? EmojiStore.shared.customPacks
                        : const <CustomEmojiPack>[];
                    return StatefulBuilder(
                      builder: (ctx2, setSheet) {
                        if (statusTab > packs.length) statusTab = 0;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                              child: Row(
                                children: [
                                  Text(
                                    AppStrings.t(
                                      AppStringKeys.emojiStatusSetTitle,
                                    ),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: c.textPrimary,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (currentStatusId != 0)
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => pick(0),
                                      child: Text(
                                        AppStrings.t(
                                          AppStringKeys.emojiStatusClear,
                                        ),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: AppTheme.tagRed,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: statusTab == 0
                                    ? FutureBuilder<List<int>>(
                                        future: optionsFuture,
                                        builder: (context, snap) {
                                          if (snap.connectionState !=
                                              ConnectionState.done) {
                                            return const Center(
                                              child: SizedBox(
                                                width: 24,
                                                height: 24,
                                                child:
                                                    CircularProgressIndicator.adaptive(
                                                      strokeWidth: 2,
                                                    ),
                                              ),
                                            );
                                          }
                                          final ids =
                                              snap.data ?? const <int>[];
                                          if (ids.isEmpty && packs.isEmpty) {
                                            return Center(
                                              child: Text(
                                                AppStrings.t(
                                                  AppStringKeys
                                                      .emojiStatusNoAvailableStatusesPremiumRequired,
                                                ),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: c.textSecondary,
                                                ),
                                              ),
                                            );
                                          }
                                          return grid(ids);
                                        },
                                      )
                                    : grid([
                                        for (final e
                                            in packs[statusTab - 1].emoji)
                                          if (e.customEmojiId != 0)
                                            e.customEmojiId,
                                      ]),
                              ),
                            ),
                            if (packs.isNotEmpty)
                              _statusTabStrip(
                                c,
                                packs,
                                statusTab,
                                (i) => setSheet(() => statusTab = i),
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

Future<List<int>> _statusOptions() async {
  final ids = <int>[];
  for (final type in const [
    'getThemedEmojiStatuses',
    'getDefaultEmojiStatuses',
  ]) {
    try {
      final res = await TdClient.shared.query({'@type': type});
      for (final s
          in res.objects('emoji_statuses') ?? const <Map<String, dynamic>>[]) {
        final id =
            s.int64('custom_emoji_id') ??
            s.obj('type')?.int64('custom_emoji_id');
        if (id != null && id != 0) ids.add(id);
      }
      for (final id in res.int64Array('custom_emoji_ids') ?? const <int>[]) {
        if (id != 0) ids.add(id);
      }
    } catch (_) {}
    if (ids.isNotEmpty) break;
  }
  return ids.toSet().toList();
}

Future<bool> _setEmojiStatus(int id) async {
  try {
    await TdClient.shared.query({
      '@type': 'setEmojiStatus',
      'emoji_status': id == 0
          ? null
          : {
              '@type': 'emojiStatus',
              'type': {
                '@type': 'emojiStatusTypeCustomEmoji',
                'custom_emoji_id': id,
              },
              'expiration_date': 0,
            },
    });
    return true;
  } catch (_) {
    return false;
  }
}

Widget _statusTabStrip(
  dynamic c,
  List<CustomEmojiPack> packs,
  int selected,
  ValueChanged<int> onTap,
) {
  Widget tab(int i, Widget child) {
    final active = i == selected;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(i),
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: active ? c.searchFill : null,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  return Container(
    height: 54,
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: c.divider, width: 0.5)),
    ),
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      children: [
        tab(
          0,
          AppIcon(
            HeroAppIcons.solidStar,
            size: 22,
            color: selected == 0 ? AppTheme.brand : c.textSecondary,
          ),
        ),
        for (var i = 0; i < packs.length; i++)
          tab(i + 1, _packTabIcon(packs[i], c)),
      ],
    ),
  );
}

Widget _packTabIcon(CustomEmojiPack pack, dynamic c) {
  final withId = pack.emoji.where((e) => e.customEmojiId != 0).toList();
  if (withId.isNotEmpty) {
    return CustomEmojiView(
      id: withId.first.customEmojiId,
      size: 26,
      color: c.textPrimary,
    );
  }
  if (pack.cover != null) {
    return SizedBox(
      width: 26,
      height: 26,
      child: TDImage(photo: pack.cover, cornerRadius: 4),
    );
  }
  return AppIcon(HeroAppIcons.tableCells, size: 22, color: c.textSecondary);
}
