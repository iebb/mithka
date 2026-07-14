import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'chat_wallpaper.dart';

class ChatWallpaperColorView extends StatefulWidget {
  const ChatWallpaperColorView({
    super.key,
    required this.controller,
    required this.dark,
    this.initial,
  });

  final ChatWallpaperController controller;
  final bool dark;
  final ChatWallpaper? initial;

  @override
  State<ChatWallpaperColorView> createState() => _ChatWallpaperColorViewState();
}

class _ChatWallpaperColorViewState extends State<ChatWallpaperColorView> {
  late HSVColor _color;
  ChatWallpaper? _pattern;
  List<ChatWallpaper> _patterns = const [];
  int _intensity = 35;
  bool _moving = false;
  bool _loadingPatterns = true;

  @override
  void initState() {
    super.initState();
    final initialColors = widget.initial?.colors ?? const <int>[];
    final initialColor = initialColors.isNotEmpty
        ? initialColors.first
        : 0x4B8DEE;
    _color = HSVColor.fromColor(
      Color(0xFF000000 | (initialColor & 0x00FFFFFF)),
    );
    if (widget.initial?.remoteType == 'pattern') {
      _pattern = widget.initial;
      _intensity = widget.initial!.intensity.clamp(0, 100);
      _moving = widget.initial!.isMoving;
    }
    _loadPatterns();
  }

  Future<void> _loadPatterns() async {
    try {
      final values = await widget.controller.installedBackgrounds(
        dark: widget.dark,
      );
      if (!mounted) return;
      setState(() {
        _patterns = values
            .where((item) => item.remoteType == 'pattern')
            .toList(growable: false);
        _loadingPatterns = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPatterns = false);
    }
  }

  int get _rgb => _color.toColor().toARGB32() & 0x00FFFFFF;

  ChatWallpaper get _result {
    final pattern = _pattern;
    if (pattern == null) {
      return ChatWallpaper.telegram(
        backgroundId: 0,
        remoteType: 'fill',
        colors: [_rgb],
      );
    }
    return pattern
        .withColors([_rgb])
        .withIntensity(_intensity)
        .withMoving(_moving);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.chatWallpaperColorTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 230,
                    child: ChatWallpaperBackground(
                      wallpaper: widget.controller.resolvedWallpaper(_result),
                      fallbackColor: c.chatBackground,
                      brightness: widget.dark
                          ? Brightness.dark
                          : Brightness.light,
                      child: const Center(
                        child: AppIcon(
                          HeroAppIcons.palette,
                          size: 44,
                          color: Color(0xCCFFFFFF),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _label(AppStringKeys.chatWallpaperColor),
                const SizedBox(height: 10),
                _slider(
                  value: _color.hue / 360,
                  painter: const _HueTrackPainter(),
                  onChanged: (value) =>
                      setState(() => _color = _color.withHue(value * 360)),
                ),
                const SizedBox(height: 12),
                _slider(
                  value: _color.saturation,
                  painter: _SaturationTrackPainter(_color.withSaturation(1)),
                  onChanged: (value) =>
                      setState(() => _color = _color.withSaturation(value)),
                ),
                const SizedBox(height: 12),
                _slider(
                  value: _color.value,
                  painter: _ValueTrackPainter(_color.withValue(1)),
                  onChanged: (value) =>
                      setState(() => _color = _color.withValue(value)),
                ),
                const SizedBox(height: 22),
                _label(AppStringKeys.chatWallpaperPattern),
                const SizedBox(height: 10),
                SizedBox(
                  height: 92,
                  child: _loadingPatterns
                      ? const Center(child: _ColorSpinner())
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _patterns.length + 1,
                          separatorBuilder: (_, _) => const SizedBox(width: 9),
                          itemBuilder: (context, index) {
                            if (index == 0) return _noPatternChoice();
                            return _patternChoice(_patterns[index - 1]);
                          },
                        ),
                ),
                if (_pattern != null) ...[
                  const SizedBox(height: 20),
                  _label(AppStringKeys.chatWallpaperIntensity),
                  const SizedBox(height: 9),
                  _slider(
                    value: _intensity / 100,
                    painter: _PlainTrackPainter(c.linkBlue),
                    onChanged: (value) =>
                        setState(() => _intensity = (value * 100).round()),
                  ),
                  const SizedBox(height: 16),
                  _effectToggle(
                    AppStringKeys.chatWallpaperMotion,
                    HeroAppIcons.rotate,
                    _moving,
                    () => setState(() => _moving = !_moving),
                  ),
                ],
              ],
            ),
          ),
          ColoredBox(
            color: c.card,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(_result),
                child: Container(
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.linkBlue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    AppStringKeys.accentColorPickerSave.l10n(context),
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String key) => Text(
    key.l10n(context),
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: context.colors.textSecondary,
    ),
  );

  Widget _slider({
    required double value,
    required CustomPainter painter,
    required ValueChanged<double> onChanged,
  }) {
    return _WallpaperValueSlider(
      value: value,
      painter: painter,
      onChanged: onChanged,
    );
  }

  Widget _noPatternChoice() {
    return _patternFrame(
      selected: _pattern == null,
      onTap: () => setState(() => _pattern = null),
      child: ColoredBox(
        color: _color.toColor(),
        child: Center(
          child: AppIcon(
            HeroAppIcons.circleXmark,
            size: 25,
            color: _color.value > 0.6
                ? const Color(0xAA000000)
                : const Color(0xCCFFFFFF),
          ),
        ),
      ),
    );
  }

  Widget _patternChoice(ChatWallpaper wallpaper) {
    final selected = _pattern?.backgroundId == wallpaper.backgroundId;
    final preview = wallpaper.withColors([_rgb]).withIntensity(_intensity);
    return _patternFrame(
      selected: selected,
      onTap: () => setState(() => _pattern = wallpaper),
      child: ChatWallpaperBackground(
        wallpaper: preview.withoutPatternDocument(),
        fallbackColor: _color.toColor(),
        brightness: widget.dark ? Brightness.dark : Brightness.light,
        child: Center(
          child: AppIcon(
            HeroAppIcons.wandMagicSparkles,
            size: 23,
            color: _color.value > 0.6
                ? const Color(0xAA000000)
                : const Color(0xCCFFFFFF),
          ),
        ),
      ),
    );
  }

  Widget _patternFrame({
    required bool selected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 78,
        padding: EdgeInsets.all(selected ? 3 : 1),
        decoration: BoxDecoration(
          color: selected ? c.linkBlue : c.divider,
          borderRadius: BorderRadius.circular(13),
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
      ),
    );
  }

  Widget _effectToggle(
    String key,
    AppIconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? c.linkBlue.withValues(alpha: 0.13) : c.card,
          border: Border.all(color: selected ? c.linkBlue : c.divider),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            AppIcon(
              icon,
              size: 20,
              color: selected ? c.linkBlue : c.textSecondary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                key.l10n(context),
                style: TextStyle(fontSize: 15, color: c.textPrimary),
              ),
            ),
            AppIcon(
              selected ? HeroAppIcons.circleCheck : HeroAppIcons.circle,
              size: 20,
              color: selected ? c.linkBlue : c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _WallpaperValueSlider extends StatelessWidget {
  const _WallpaperValueSlider({
    required this.value,
    required this.painter,
    required this.onChanged,
  });

  final double value;
  final CustomPainter painter;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    void update(Offset local, double width) =>
        onChanged((local.dx / width).clamp(0.0, 1.0));
    return LayoutBuilder(
      builder: (context, constraints) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            update(details.localPosition, constraints.maxWidth),
        onHorizontalDragUpdate: (details) =>
            update(details.localPosition, constraints.maxWidth),
        child: SizedBox(
          height: 30,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                top: 9,
                bottom: 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CustomPaint(painter: painter),
                ),
              ),
              Positioned(
                left: value.clamp(0.0, 1.0) * (constraints.maxWidth - 24),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFFFF),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x33000000)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x30000000), blurRadius: 4),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HueTrackPainter extends CustomPainter {
  const _HueTrackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SaturationTrackPainter extends CustomPainter {
  const _SaturationTrackPainter(this.color);
  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: [const Color(0xFFFFFFFF), color.toColor()],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_SaturationTrackPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ValueTrackPainter extends CustomPainter {
  const _ValueTrackPainter(this.color);
  final HSVColor color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: [const Color(0xFF000000), color.toColor()],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_ValueTrackPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _PlainTrackPainter extends CustomPainter {
  const _PlainTrackPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0.15), color],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_PlainTrackPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ColorSpinner extends StatefulWidget {
  const _ColorSpinner();

  @override
  State<_ColorSpinner> createState() => _ColorSpinnerState();
}

class _ColorSpinnerState extends State<_ColorSpinner>
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
      HeroAppIcons.circleNotch,
      size: 22,
      color: context.colors.linkBlue,
    ),
  );
}
