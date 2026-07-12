import 'package:flutter/material.dart';

import '../chat/rich_message_bot_relay.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'rich_message_relay_config.dart';

class RichMessageRelayView extends StatefulWidget {
  const RichMessageRelayView({super.key});

  @override
  State<RichMessageRelayView> createState() => _RichMessageRelayViewState();
}

class _RichMessageRelayViewState extends State<RichMessageRelayView> {
  final _token = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;
  String _botLabel = '';

  @override
  void initState() {
    super.initState();
    _token.addListener(_tokenChanged);
    _load();
  }

  void _tokenChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _token.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = await RichMessageRelayConfig.readToken();
    if (!mounted) return;
    _token.text = token ?? '';
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final token = _token.text.trim();
    if (_saving || token.isEmpty) return;
    setState(() => _saving = true);
    final relay = RichMessageBotRelay();
    try {
      final bot = await relay.validateToken(token);
      await RichMessageRelayConfig.saveToken(token);
      if (!mounted) return;
      setState(() {
        _botLabel = bot.username.isEmpty ? bot.displayName : '@${bot.username}';
      });
      showToast(
        context,
        AppStrings.t(AppStringKeys.richTextRelayBotSaved, {
          'value1': _botLabel,
        }),
      );
    } on RichMessageRelayException catch (error) {
      if (mounted) showToast(context, error.message);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      relay.close();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    await RichMessageRelayConfig.clear();
    if (!mounted) return;
    _token.clear();
    setState(() => _botLabel = '');
    showToast(context, AppStringKeys.richTextRelayBotRemoved.l10n(context));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: SafeArea(
        child: Column(
          children: [
            NavHeader(
              title: AppStringKeys.richTextRelayBotTitle,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: _loading
                  ? Center(
                      child: Text(
                        AppStringKeys.contactsLoading.l10n(context),
                        style: AppTextStyle.body(c.textSecondary),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xl,
                        AppSpacing.lg,
                        AppSpacing.section,
                      ),
                      children: [
                        Text(
                          AppStringKeys.richTextRelayBotDescription.l10n(
                            context,
                          ),
                          style: AppTextStyle.footnote(c.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          height: 54,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: c.card,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border.all(color: c.divider),
                          ),
                          child: Row(
                            children: [
                              AppIcon(
                                HeroAppIcons.key,
                                size: 20,
                                color: c.textSecondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: EditableText(
                                  controller: _token,
                                  focusNode: _focusNode,
                                  style: AppTextStyle.body(c.textPrimary),
                                  cursorColor: AppTheme.brand,
                                  backgroundCursorColor: c.textTertiary,
                                  obscureText: _obscure,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  keyboardType: TextInputType.visiblePassword,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _save(),
                                ),
                              ),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () =>
                                    setState(() => _obscure = !_obscure),
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: AppIcon(
                                    _obscure
                                        ? HeroAppIcons.eye
                                        : HeroAppIcons.eyeSlash,
                                    size: 20,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_botLabel.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            AppStrings.t(
                              AppStringKeys.richTextRelayBotConnected,
                              {'value1': _botLabel},
                            ),
                            style: AppTextStyle.footnote(
                              const Color(0xFF34C759),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        _actionButton(
                          AppStringKeys.richTextRelayBotSave.l10n(context),
                          enabled: !_saving && _token.text.trim().isNotEmpty,
                          onTap: _save,
                        ),
                        if (_token.text.trim().isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _actionButton(
                            AppStringKeys.richTextRelayBotRemove.l10n(context),
                            destructive: true,
                            onTap: _remove,
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    String label, {
    required VoidCallback onTap,
    bool enabled = true,
    bool destructive = false,
  }) {
    final color = destructive ? AppTheme.tagRed : AppTheme.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: enabled ? 0.12 : 0.05),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Text(
          label,
          style: AppTextStyle.body(
            color.withValues(alpha: enabled ? 1 : 0.4),
            weight: AppTextWeight.semibold,
          ),
        ),
      ),
    );
  }
}
