import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_dialog.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'message_send_options.dart';

class ScheduledMessagesView extends StatefulWidget {
  const ScheduledMessagesView({
    super.key,
    required this.chatId,
    this.chatTitle = '',
  });

  final int chatId;
  final String chatTitle;

  @override
  State<ScheduledMessagesView> createState() => _ScheduledMessagesViewState();
}

class _ScheduledMessage {
  const _ScheduledMessage({
    required this.raw,
    required this.message,
    required this.sendDate,
    required this.repeatPeriod,
    required this.whenOnline,
  });

  final Map<String, dynamic> raw;
  final ChatMessage message;
  final int sendDate;
  final int repeatPeriod;
  final bool whenOnline;
}

class _ScheduledMessagesViewState extends State<ScheduledMessagesView> {
  final _client = TdClient.shared;
  List<_ScheduledMessage> _messages = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final response = await _client.query({
        '@type': 'getChatScheduledMessages',
        'chat_id': widget.chatId,
      });
      final parsed = <_ScheduledMessage>[];
      for (final raw
          in response.objects('messages') ?? const <Map<String, dynamic>>[]) {
        final message = TDParse.message(raw);
        if (message == null) continue;
        final scheduling = raw.obj('scheduling_state');
        parsed.add(
          _ScheduledMessage(
            raw: raw,
            message: message,
            sendDate: scheduling?.integer('send_date') ?? 0,
            repeatPeriod: scheduling?.integer('repeat_period') ?? 0,
            whenOnline:
                scheduling?.type == 'messageSchedulingStateSendWhenOnline',
          ),
        );
      }
      parsed.sort((a, b) {
        if (a.whenOnline != b.whenOnline) return a.whenOnline ? -1 : 1;
        return a.sendDate.compareTo(b.sendDate);
      });
      if (!mounted) return;
      setState(() {
        _messages = parsed;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _edit(_ScheduledMessage entry) async {
    final text = await showAppTextEntryDialog(
      context,
      title: AppStrings.t(AppStringKeys.scheduledMessagesEditScheduledMessage),
      hint: 'Message',
      initial: entry.message.text,
      minLines: 2,
      maxLines: 8,
      actionLabel: 'Save',
    );
    if (!mounted || text == null || text.isEmpty) return;
    try {
      if (entry.raw.obj('content')?.type == 'messageText') {
        await _client.query({
          '@type': 'editMessageText',
          'chat_id': widget.chatId,
          'message_id': entry.message.id,
          'input_message_content': {
            '@type': 'inputMessageText',
            'text': {'@type': 'formattedText', 'text': text},
          },
        });
      } else {
        await _client.query({
          '@type': 'editMessageCaption',
          'chat_id': widget.chatId,
          'message_id': entry.message.id,
          'caption': {'@type': 'formattedText', 'text': text},
          'show_caption_above_media':
              entry.raw.obj('content')?.boolean('show_caption_above_media') ??
              false,
        });
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _reschedule(_ScheduledMessage entry) async {
    final initialDate = entry.sendDate > 0
        ? DateTime.fromMillisecondsSinceEpoch(entry.sendDate * 1000)
        : DateTime.now().add(const Duration(hours: 1));
    final config = await showMessageSendOptionsSheet(
      context,
      initial: MessageSendConfiguration(
        scheduleAt: initialDate,
        sendWhenOnline: entry.whenOnline,
        repeatPeriod: entry.repeatPeriod,
      ),
      allowWhenOnline: true,
    );
    if (!mounted || config == null || config.schedulingState == null) return;
    try {
      await _client.query({
        '@type': 'editMessageSchedulingState',
        'chat_id': widget.chatId,
        'message_id': entry.message.id,
        'scheduling_state': config.schedulingState,
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _sendNow(_ScheduledMessage entry) async {
    try {
      await _client.query({
        '@type': 'editMessageSchedulingState',
        'chat_id': widget.chatId,
        'message_id': entry.message.id,
        'scheduling_state': null,
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _delete(_ScheduledMessage entry) async {
    final confirmed = await confirmDialog(
      context,
      title: AppStrings.t(
        AppStringKeys.scheduledMessagesDeleteScheduledMessage,
      ),
      message: 'This scheduled message will not be sent.',
      confirmText: AppStrings.t(AppStringKeys.chatDelete),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _client.query({
        '@type': 'deleteMessages',
        'chat_id': widget.chatId,
        'message_ids': [entry.message.id],
        'revoke': true,
      });
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: widget.chatTitle.isEmpty
                ? 'Scheduled messages'
                : 'Scheduled · ${widget.chatTitle}',
            onBack: () => Navigator.of(context).pop(),
            trailing: _refreshAction(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator(size: 24))
                : _messages.isEmpty
                ? _empty()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    itemCount: _messages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _messageCard(_messages[index]),
                  ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: AppTheme.tagRed.withValues(alpha: 0.12),
              child: Text(
                _error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _refreshAction() => Semantics(
    button: true,
    label: AppStrings.t(
      AppStringKeys.scheduledMessagesRefreshScheduledMessages,
    ),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _loading ? null : () => unawaited(_load()),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AppIcon(
          HeroAppIcons.arrowsRotate,
          size: 19,
          color: _loading
              ? context.colors.textTertiary
              : context.colors.textPrimary,
        ),
      ),
    ),
  );

  Widget _messageCard(_ScheduledMessage entry) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        color: colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppIcon(HeroAppIcons.clock, size: 17, color: AppTheme.brand),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _scheduleLabel(entry),
                  style: TextStyle(
                    color: AppTheme.brand,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.message.text.trim().isEmpty
                ? _contentLabel(entry.message.contentType ?? '')
                : entry.message.text,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _action('Edit', HeroAppIcons.pen, () => _edit(entry)),
              _action(
                'Reschedule',
                HeroAppIcons.clock,
                () => _reschedule(entry),
              ),
              _action(
                'Send now',
                HeroAppIcons.paperPlane,
                () => _sendNow(entry),
              ),
              _action(
                'Delete',
                HeroAppIcons.trash,
                () => _delete(entry),
                destructive: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(
    String label,
    AppIconData icon,
    VoidCallback onTap, {
    bool destructive = false,
  }) => Expanded(
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              icon,
              size: 17,
              color: destructive ? AppTheme.tagRed : AppTheme.brand,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: destructive
                    ? AppTheme.tagRed
                    : context.colors.textSecondary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(
            HeroAppIcons.clock,
            size: 42,
            color: context.colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.t(AppStringKeys.scheduledMessagesNoScheduledMessages),
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            AppStrings.t(
              AppStringKeys.scheduledMessagesLongPressTheSendButtonToScheduleA,
            ),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    ),
  );

  String _scheduleLabel(_ScheduledMessage entry) {
    if (entry.whenOnline) return 'Send when online';
    if (entry.sendDate <= 0) return 'Scheduled';
    final repeat = switch (entry.repeatPeriod) {
      86400 => ' · repeats daily',
      604800 => ' · repeats weekly',
      2592000 => ' · repeats monthly',
      _ => '',
    };
    return '${DateText.messageDetailLabel(entry.sendDate)}$repeat';
  }

  String _contentLabel(String type) => switch (type) {
    'messagePhoto' => 'Photo',
    'messageVideo' => 'Video',
    'messageAnimation' => 'GIF',
    'messageVoiceNote' => 'Voice message',
    'messageVideoNote' => 'Video message',
    'messageDocument' => 'File',
    _ => 'Scheduled message',
  };
}
