//
//  accent_color_picker_view.dart
//
//  A full-page custom swatch picker for a Telegram accent color (the name
//  color via setAccentColor, or the profile color via setProfileAccentColor).
//  Returns the chosen id via Navigator.pop (or -1 for “none” when allowed).
//  No Material dialog — flat NavHeader + 保存.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

/// The 7 built-in Telegram peer/name accent colors (ids 0–6, light theme).
/// These ids are universal across clients; higher ids are premium palettes
/// delivered via updateAccentColors and are out of scope here.
const List<Color> kAccentColors = [
  Color(0xFFCC5049), // 0 red
  Color(0xFFD67722), // 1 orange
  Color(0xFF955CDB), // 2 purple
  Color(0xFF40A920), // 3 green
  Color(0xFF309EBA), // 4 cyan
  Color(0xFF368AD1), // 5 blue
  Color(0xFFC7508B), // 6 pink
];

class AccentColorPickerView extends StatefulWidget {
  const AccentColorPickerView({
    super.key,
    required this.title,
    required this.selectedId,
    this.allowNone = false,
    this.footnote,
  });

  final String title;
  final int selectedId;
  final bool allowNone; // profile color may be cleared (id -1)
  final String? footnote;

  @override
  State<AccentColorPickerView> createState() => _AccentColorPickerViewState();
}

class _AccentColorPickerViewState extends State<AccentColorPickerView> {
  late int _sel = widget.selectedId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: widget.title,
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(_sel),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  AppStrings.t(AppStringKeys.accentColorPickerSave),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.brand,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Wrap(
                    spacing: 18,
                    runSpacing: 18,
                    children: [
                      if (widget.allowNone) _swatch(-1, null),
                      for (var i = 0; i < kAccentColors.length; i++)
                        _swatch(i, kAccentColors[i]),
                    ],
                  ),
                ),
                if (widget.footnote != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Text(
                      widget.footnote!,
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _swatch(int id, Color? color) {
    final c = context.colors;
    final selected = _sel == id;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _sel = id),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? (color ?? c.textSecondary) : Colors.transparent,
            width: 2,
          ),
        ),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color ?? c.groupedBackground,
            shape: BoxShape.circle,
            border: color == null
                ? Border.all(color: c.textTertiary, width: 1.5)
                : null,
          ),
          child: selected
              ? AppIcon(
                  HeroAppIcons.check,
                  size: 20,
                  color: color == null ? c.textSecondary : Colors.white,
                )
              : (color == null
                    ? AppIcon(HeroAppIcons.ban, size: 18, color: c.textTertiary)
                    : null),
        ),
      ),
    );
  }
}
