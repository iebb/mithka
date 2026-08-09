import 'package:flutter/material.dart';

import '../bot_api/bot_api_client.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';

class BotApiEndpointView extends StatefulWidget {
  const BotApiEndpointView({super.key});

  @override
  State<BotApiEndpointView> createState() => _BotApiEndpointViewState();
}

class _BotApiEndpointViewState extends State<BotApiEndpointView> {
  final _endpoint = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _endpoint.addListener(_endpointChanged);
    _load();
  }

  void _endpointChanged() {
    if (mounted) setState(() => _error = null);
  }

  @override
  void dispose() {
    _endpoint
      ..removeListener(_endpointChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final endpoint = await TdClient.shared.configuredBotApiEndpoint();
      if (!mounted) return;
      _endpoint.text = endpoint.toString();
    } on Object {
      if (!mounted) return;
      _error = AppStringKeys.editProfileSaveFailed.l10n(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _endpoint.text.trim().isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final endpoint = await TdClient.shared.setBotApiEndpoint(_endpoint.text);
      if (!mounted) return;
      _endpoint.text = endpoint.toString();
      showToast(context, AppStringKeys.aiSaved);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on BotApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on TdError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = AppStringKeys.editProfileSaveFailed.l10n(context),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = !_saving && _endpoint.text.trim().isNotEmpty;
    return SettingsPageScaffold(
      title: AppStringKeys.loginBotApiEndpoint,
      onBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Center(child: AppActivityIndicator(size: 24))
          : SettingsListView(
              children: [
                const SettingsNote(text: AppStringKeys.loginBotApiEndpointHint),
                const SizedBox(height: AppSpacing.md),
                SettingsPanel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      AppIcon(
                        HeroAppIcons.server,
                        size: 20,
                        color: c.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _endpoint,
                          focusNode: _focusNode,
                          style: AppTextStyle.body(c.textPrimary),
                          cursorColor: AppTheme.brand,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isCollapsed: true,
                          ),
                          contextMenuBuilder: (context, editableTextState) =>
                              AdaptiveTextSelectionToolbar.editableText(
                                editableTextState: editableTextState,
                              ),
                          onSubmitted: (_) => _save(),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(error, style: AppTextStyle.footnote(AppTheme.tagRed)),
                ],
                const SizedBox(height: AppSpacing.lg),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: enabled ? _save : null,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.brand.withValues(
                        alpha: enabled ? 0.12 : 0.05,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: _saving
                        ? const AppActivityIndicator(size: 20)
                        : Text(
                            AppStringKeys.aiSave.l10n(context),
                            style: AppTextStyle.body(
                              AppTheme.brand.withValues(
                                alpha: enabled ? 1 : 0.4,
                              ),
                              weight: AppTextWeight.semibold,
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
