//
//  ghost_mode_settings_view.dart
//
//  Ghost mode settings. Only reachable when the binary was built with
//  `I_DONT_FUCKING_CARE_ABOUT_TOS` — the entry point in the privacy screen is
//  gated by the same compile-time constant, so without the define this view
//  never mounts. Global switch + four interception dimensions + per-chat
//  three-state exceptions (follow global / always hide / never hide).
//

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../chat/chat_picker_view.dart';
import '../components/app_icons.dart';
import '../components/settings_selection_row.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import 'ghost_mode_controller.dart';

class GhostModeSettingsView extends StatelessWidget {
  const GhostModeSettingsView({super.key});

  Future<void> _addChatException(BuildContext context) async {
    final controller = GhostModeController.shared;
    final chat = await Navigator.of(context).push<ChatSummary>(
      AppPageRoute(
        pageBuilder: (_, _, _) => ChatPickerView(
          title: AppStrings.t(AppStringKeys.ghostModeAddChatException),
        ),
      ),
    );
    if (chat == null || !context.mounted) return;
    // Make the new exception mean something immediately: with ghost mode on
    // the chat is exempted from interception, with it off the chat is hidden
    // on its own. The picker row can switch it to any of the three states.
    final state = controller.globalEnabled
        ? GhostChatException.forceAllow
        : GhostChatException.forceBlock;
    await controller.setChatException(chat.id, state);
  }

  @override
  Widget build(BuildContext context) {
    if (!GhostModeController.isAvailable) return const SizedBox.shrink();
    final controller = GhostModeController.shared;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final exceptions = controller.chatExceptions.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        // While ghost mode is off the dimensions are inert — interception is
        // resolved against the global switch — and the exceptions cannot
        // bite either. The rows dim and stop answering; re-enabling the
        // master lights them right up with their stored values.
        final active = controller.globalEnabled;
        return SettingsPageScaffold(
          title: AppStrings.t(AppStringKeys.ghostModeTitle),
          onBack: () => Navigator.of(context).pop(),
          child: SettingsListView(
            children: [
              SettingsSwitchRow(
                key: const ValueKey('ghost-mode-master'),
                title: AppStringKeys.ghostModeEnable.l10n(context),
                value: controller.globalEnabled,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.eyeSlash),
                onChanged: (value) =>
                    unawaited(controller.setGlobalEnabled(value)),
              ),
              const SettingsNote(text: AppStringKeys.ghostModeDescription),
              SettingsSwitchRow(
                key: const ValueKey('ghost-mode-sidebar-entry'),
                title: AppStringKeys.ghostModeShowSidebarEntry.l10n(context),
                subtitle: AppStringKeys.ghostModeShowSidebarEntryDescription
                    .l10n(context),
                value: controller.showSidebarEntry,
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.eyeSlash),
                onChanged: (value) =>
                    unawaited(controller.setShowSidebarEntry(value)),
              ),
              const SettingsNote(
                text: AppStringKeys.ghostModeShowSidebarEntryDescription,
              ),
              SettingsSection(
                titleKey: AppStringKeys.ghostModeTitle,
                rows: [
                  SettingsSwitchRow(
                    title: AppStringKeys.ghostModeReadReceipts.l10n(context),
                    subtitle: AppStringKeys.ghostModeReadReceiptsDescription
                        .l10n(context),
                    value: controller.blockReadReceipts,
                    enabled: active,
                    onChanged: (value) =>
                        unawaited(controller.setBlockReadReceipts(value)),
                  ),
                  SettingsSwitchRow(
                    title: AppStringKeys.ghostModeStoryReads.l10n(context),
                    subtitle: AppStringKeys.ghostModeStoryReadsDescription.l10n(
                      context,
                    ),
                    value: controller.blockStoryReads,
                    enabled: active,
                    onChanged: (value) =>
                        unawaited(controller.setBlockStoryReads(value)),
                  ),
                  SettingsSwitchRow(
                    title: AppStringKeys.ghostModeTyping.l10n(context),
                    subtitle: AppStringKeys.ghostModeTypingDescription.l10n(
                      context,
                    ),
                    value: controller.blockTyping,
                    enabled: active,
                    onChanged: (value) =>
                        unawaited(controller.setBlockTyping(value)),
                  ),
                  SettingsSwitchRow(
                    title: AppStringKeys.ghostModeOnline.l10n(context),
                    subtitle: AppStringKeys.ghostModeOnlineDescription.l10n(
                      context,
                    ),
                    value: controller.hideOnline,
                    enabled: active,
                    onChanged: (value) =>
                        unawaited(controller.setHideOnline(value)),
                  ),
                ],
              ),
              SettingsSection(
                titleKey: AppStringKeys.ghostModeChatExceptions,
                rows: [
                  for (final entry in exceptions)
                    _GhostExceptionRow(
                      key: ValueKey('ghost-exception-${entry.key}'),
                      chatId: entry.key,
                      state: entry.value,
                      enabled: active,
                      onSelected: active
                          ? (value) => unawaited(
                              controller.setChatException(entry.key, value),
                            )
                          : null,
                    ),
                  SettingsRow(
                    key: const ValueKey('ghost-mode-add-exception'),
                    title: AppStringKeys.ghostModeAddChatException.l10n(
                      context,
                    ),
                    leading: const SettingsLeadingIcon(icon: HeroAppIcons.plus),
                    enabled: active,
                    onTap: active
                        ? () => unawaited(_addChatException(context))
                        : null,
                  ),
                  if (exceptions.isEmpty)
                    SettingsRow(
                      title: AppStringKeys.ghostModeNoChatExceptions.l10n(
                        context,
                      ),
                      showChevron: false,
                      enabled: false,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  static String _exceptionLabel(
    BuildContext context,
    GhostChatException state,
  ) => switch (state) {
    GhostChatException.defaultState =>
      AppStringKeys.ghostModeExceptionDefault.l10n(context),
    GhostChatException.forceBlock =>
      AppStringKeys.ghostModeExceptionForceBlock.l10n(context),
    GhostChatException.forceAllow =>
      AppStringKeys.ghostModeExceptionForceAllow.l10n(context),
  };
}

/// One per-chat exception row. The chat title resolves from TDLib once per
/// chat and is cached for the row's lifetime; the selection menu offers the
/// three states plus removal.
class _GhostExceptionRow extends StatefulWidget {
  const _GhostExceptionRow({
    super.key,
    required this.chatId,
    required this.state,
    required this.onSelected,
    this.enabled = true,
  });

  final int chatId;
  final GhostChatException state;
  final FutureOr<void> Function(GhostChatException value)? onSelected;
  final bool enabled;

  @override
  State<_GhostExceptionRow> createState() => _GhostExceptionRowState();
}

class _GhostExceptionRowState extends State<_GhostExceptionRow> {
  Future<String>? _title;

  @override
  void didUpdateWidget(_GhostExceptionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) _title = null;
  }

  Future<String> _resolveTitle() async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': widget.chatId,
      });
      return chat.str('title') ?? '${widget.chatId}';
    } catch (_) {
      return '${widget.chatId}';
    }
  }

  @override
  Widget build(BuildContext context) {
    _title ??= _resolveTitle();
    return FutureBuilder<String>(
      future: _title,
      builder: (context, snapshot) {
        final title = snapshot.data;
        return SettingsSelectionRow<GhostChatException>(
          title: title == null || title.isEmpty ? '${widget.chatId}' : title,
          value: GhostModeSettingsView._exceptionLabel(context, widget.state),
          enabled: widget.onSelected != null,
          options: [
            for (final state in GhostChatException.values)
              SettingsSelectionOption(
                id: 'ghost-exception-${widget.chatId}-${state.name}',
                value: state,
                label: GhostModeSettingsView._exceptionLabel(context, state),
              ),
          ],
          isSelected: (value) => value == widget.state,
          onSelected: widget.onSelected ?? (_) {},
        );
      },
    );
  }
}
