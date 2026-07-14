import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

class ChatStickerSetPickerView extends StatefulWidget {
  const ChatStickerSetPickerView({
    super.key,
    required this.title,
    required this.customEmoji,
    required this.selectedId,
  });

  final String title;
  final bool customEmoji;
  final int selectedId;

  @override
  State<ChatStickerSetPickerView> createState() =>
      _ChatStickerSetPickerViewState();
}

class _ChatStickerSetPickerViewState extends State<ChatStickerSetPickerView> {
  List<_StickerSetChoice> _sets = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await TdClient.shared.query({
        '@type': 'getInstalledStickerSets',
        'sticker_type': {
          '@type': widget.customEmoji
              ? 'stickerTypeCustomEmoji'
              : 'stickerTypeRegular',
        },
      });
      final sets = <_StickerSetChoice>[];
      for (final value
          in response.objects('sets') ?? const <Map<String, dynamic>>[]) {
        final id = value.int64('id');
        final title = value.str('title');
        if (id == null || title == null) continue;
        sets.add(
          _StickerSetChoice(
            id: id,
            title: title,
            thumbnail: TDParse.fileRef(value.obj('thumbnail')?.obj('file')),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _sets = sets;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: widget.title,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: _StickerSetSpinner())
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                    itemCount: _sets.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(height: 1),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _row(
                          id: 0,
                          title: AppStringKeys.groupAppearanceNone.l10n(
                            context,
                          ),
                        );
                      }
                      final set = _sets[index - 1];
                      return _row(
                        id: set.id,
                        title: set.title,
                        thumbnail: set.thumbnail,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _row({required int id, required String title, TdFileRef? thumbnail}) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(id),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: thumbnail == null
                  ? AppIcon(
                      id == 0
                          ? HeroAppIcons.circleXmark
                          : HeroAppIcons.solidFaceSmile,
                      size: 24,
                      color: c.textTertiary,
                    )
                  : TDImage(photo: thumbnail),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: c.textPrimary),
              ),
            ),
            if (widget.selectedId == id)
              AppIcon(HeroAppIcons.check, size: 20, color: c.linkBlue),
          ],
        ),
      ),
    );
  }
}

class _StickerSetChoice {
  const _StickerSetChoice({
    required this.id,
    required this.title,
    this.thumbnail,
  });

  final int id;
  final String title;
  final TdFileRef? thumbnail;
}

class _StickerSetSpinner extends StatefulWidget {
  const _StickerSetSpinner();

  @override
  State<_StickerSetSpinner> createState() => _StickerSetSpinnerState();
}

class _StickerSetSpinnerState extends State<_StickerSetSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: AppIcon(
      HeroAppIcons.rotate,
      size: 24,
      color: context.colors.textTertiary,
    ),
  );
}
