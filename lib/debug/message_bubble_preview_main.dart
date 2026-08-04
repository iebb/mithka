import 'package:flutter/widgets.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chat/stretchable_message_bubble_background.dart';
import '../theme/message_bubble_background.dart';

const _canvasColor = Color(0xFF17181C);

void main() {
  runApp(const MessageBubblePreviewApp());
}

/// Deterministic grid for visually checking every generated center-slice
/// preset at a compact picker width.
class MessageBubblePreviewApp extends StatelessWidget {
  const MessageBubblePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: _canvasColor,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.noScaling, boldText: false),
        child: const ColoredBox(
          color: _canvasColor,
          child: SafeArea(child: _PreviewGallery()),
        ),
      ),
    );
  }
}

class _PreviewGallery extends StatelessWidget {
  const _PreviewGallery();

  static const _items =
      <({String name, MessageBubbleBackgroundSpec background})>[
        (
          name: 'Midnight Aurora',
          background: MessageBubbleBackgroundSpec.midnightAurora,
        ),
        (
          name: 'Solar Porcelain',
          background: MessageBubbleBackgroundSpec.solarPorcelain,
        ),
        (
          name: 'Berry Orbit',
          background: MessageBubbleBackgroundSpec.berryOrbit,
        ),
        (
          name: 'Arctic Blueprint',
          background: MessageBubbleBackgroundSpec.arcticBlueprint,
        ),
        (
          name: 'Ember Arcade',
          background: MessageBubbleBackgroundSpec.emberArcade,
        ),
        (
          name: 'Lilac Constellation',
          background: MessageBubbleBackgroundSpec.lilacConstellation,
        ),
        (
          name: 'Forest Familiar · Storybook',
          background: MessageBubbleBackgroundSpec.forestFamiliar,
        ),
        (
          name: 'Ink Wanderer · Ink wash',
          background: MessageBubbleBackgroundSpec.inkWanderer,
        ),
        (
          name: 'Pixel Cadet · Pixel art',
          background: MessageBubbleBackgroundSpec.pixelCadet,
        ),
        (
          name: 'Cosmic Mechanic · Sci-fi',
          background: MessageBubbleBackgroundSpec.cosmicMechanic,
        ),
        (
          name: 'Pastry Pal · Food art',
          background: MessageBubbleBackgroundSpec.pastryPal,
        ),
        (
          name: 'Noir Detective · Comic',
          background: MessageBubbleBackgroundSpec.noirDetective,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final items = [..._items.skip(6), ..._items.take(6)];
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
          sliver: SliverToBoxAdapter(
            child: Text(
              AppStrings.t(AppStringKeys.debugBubblePreviewGenres),
              style: const TextStyle(
                color: Color(0xFFF4F4F7),
                fontSize: 19,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          sliver: SliverToBoxAdapter(
            child: Text(
              AppStrings.t(AppStringKeys.debugBubblePreviewExperimental),
              style: const TextStyle(
                color: Color(0xFFA9ABB6),
                fontSize: 11,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.18,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF24252B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF363840)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SizedBox.expand(
                          child: StretchableMessageBubbleBackground(
                            background: item.background,
                            constraints: const BoxConstraints.expand(),
                            fallbackColor: const Color(0xFF33343A),
                            fallbackBorderRadius: BorderRadius.circular(10),
                            fallbackPadding: EdgeInsets.zero,
                            child: const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        item.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD7D8DE),
                          fontSize: 11,
                          height: 1.15,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
