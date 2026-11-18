# Design Notes

- All reusable font sizes, text weights, spacing, insets, radii, icon sizes, row heights, and control dimensions live in `lib/theme/app_theme.dart`.
- New UI should use `AppTextSize`, `AppTextWeight`, `AppTextStyle`, `AppSpacing`, `AppInsets`, `AppRadius`, `AppIconSize`, and `AppMetric` instead of hard-coded design numbers. Add a named token first when a new reusable size is needed.
- Use `AppIcon` and `HeroAppIcons` (`lib/components/app_icons.dart`) or owned image assets. Never use built-in Material (`Icons.*`) or Cupertino (`CupertinoIcons.*`) icon sets.
- Use `SettingsCard`, `SettingsRow`, and `SettingsSwitchRow` from `lib/components/ui_components.dart` for grouped settings UI. Do not create per-screen `_settingsCard` / left-label-right-value row variants.
- Left-label/right-value rows must right-align the value text and keep the chevron at the far right.
- Use `showAppConfirmDialog`, `AppDialogSurface`, and `showAppTextEntryDialog` (`lib/components/app_confirm_dialog.dart`, `lib/components/app_dialog.dart`) for modal prompts rather than Material `AlertDialog` or `CupertinoAlertDialog`.
- Do not use Material `Switch` in app UI. Use `SettingsSwitchRow` or `CupertinoSwitch`.
