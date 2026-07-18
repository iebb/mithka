import 'dart:async';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';

class MessageInfoView extends StatefulWidget {
  const MessageInfoView({
    super.key,
    required this.chatId,
    required this.message,
  });

  final int chatId;
  final ChatMessage message;

  @override
  State<MessageInfoView> createState() => _MessageInfoViewState();
}

class _MessageInfoViewState extends State<MessageInfoView> {
  bool _loading = true;
  String? _error;
  String? _senderName;
  TdFileRef? _senderPhoto;
  Map<String, dynamic>? _readDate;
  List<_MessageViewer> _viewers = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final properties = await TdClient.shared.query({
        '@type': 'getMessageProperties',
        'chat_id': widget.chatId,
        'message_id': widget.message.id,
      });
      final futures = <Future<void>>[_loadSender()];
      if (properties.boolean('can_get_read_date') ?? false) {
        futures.add(_loadReadDate());
      }
      if (properties.boolean('can_get_viewers') ?? false) {
        futures.add(_loadViewers());
      }
      await Future.wait(futures);
    } catch (error) {
      _error = error.toString();
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadSender() async {
    final senderId = widget.message.senderId;
    if (senderId == null || senderId == 0) return;
    try {
      if (widget.message.senderIsChat) {
        final chat = await TdClient.shared.query({
          '@type': 'getChat',
          'chat_id': senderId,
        });
        _senderName = chat.str('title');
        _senderPhoto = TDParse.smallPhoto(chat.obj('photo'));
      } else {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        _senderName = TDParse.userName(user);
        _senderPhoto = TDParse.smallPhoto(user.obj('profile_photo'));
      }
    } catch (_) {}
  }

  Future<void> _loadReadDate() async {
    try {
      _readDate = await TdClient.shared.query({
        '@type': 'getMessageReadDate',
        'chat_id': widget.chatId,
        'message_id': widget.message.id,
      });
    } catch (_) {}
  }

  Future<void> _loadViewers() async {
    try {
      final response = await TdClient.shared.query({
        '@type': 'getMessageViewers',
        'chat_id': widget.chatId,
        'message_id': widget.message.id,
      });
      final rawViewers = response.objects('viewers') ?? const [];
      final viewers = await Future.wait(
        rawViewers.map((viewer) async {
          final userId = viewer.int64('user_id') ?? 0;
          String name = AppStrings.t(AppStringKeys.messageInfoUnknownViewer);
          TdFileRef? photo;
          if (userId != 0) {
            try {
              final user = await TdClient.shared.query({
                '@type': 'getUser',
                'user_id': userId,
              });
              name = TDParse.userName(user);
              photo = TDParse.smallPhoto(user.obj('profile_photo'));
            } catch (_) {}
          }
          return _MessageViewer(
            userId: userId,
            name: name,
            photo: photo,
            viewDate: viewer.integer('view_date') ?? 0,
          );
        }),
      );
      viewers.sort((a, b) => b.viewDate.compareTo(a.viewDate));
      _viewers = viewers;
    } catch (_) {}
  }

  String _readStatus() {
    final readDate = _readDate;
    return switch (readDate?.type) {
      'messageReadDateRead' => DateText.messageDetailLabel(
        readDate?.integer('read_date') ?? 0,
      ),
      'messageReadDateUnread' => AppStrings.t(AppStringKeys.messageInfoUnread),
      'messageReadDateTooOld' => AppStrings.t(
        AppStringKeys.messageInfoReadDateTooOld,
      ),
      'messageReadDateUserPrivacyRestricted' => AppStrings.t(
        AppStringKeys.messageInfoReadDatePrivate,
      ),
      'messageReadDateMyPrivacyRestricted' => AppStrings.t(
        AppStringKeys.messageInfoReadDateHidden,
      ),
      _ => AppStrings.t(AppStringKeys.messageInfoReadDateUnavailable),
    };
  }

  String _messageType() {
    final type = widget.message.contentType ?? 'messageText';
    final withoutPrefix = type.startsWith('message')
        ? type.substring('message'.length)
        : type;
    final words = withoutPrefix.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) => '${match.group(1)} ${match.group(2)}',
    );
    if (words.isEmpty) return AppStrings.t(AppStringKeys.messageInfoText);
    return '${words[0].toUpperCase()}${words.substring(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.messageInformationTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator(size: 24))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
                    children: [
                      if (_error != null) _errorCard(),
                      _summaryCard(),
                      const SizedBox(height: 14),
                      _deliveryCard(),
                      if (_viewers.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _viewersCard(),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        AppStringKeys.messageInfoLoadFailed.l10n(context),
        style: TextStyle(fontSize: 14, color: c.textSecondary),
      ),
    );
  }

  Widget _summaryCard() {
    return _InfoCard(
      children: [
        if ((_senderName ?? widget.message.senderName)?.isNotEmpty ?? false)
          _senderRow(),
        _InfoRow(
          icon: HeroAppIcons.clock,
          label: AppStringKeys.messageInfoSent,
          value: DateText.messageDetailLabel(widget.message.date),
        ),
        _InfoRow(
          icon: HeroAppIcons.file,
          label: AppStringKeys.messageInfoType,
          value: _messageType(),
        ),
      ],
    );
  }

  Widget _senderRow() {
    final c = context.colors;
    final name = _senderName ?? widget.message.senderName ?? '—';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          PhotoAvatar(title: name, photo: _senderPhoto, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStringKeys.messageInfoSender.l10n(context),
                  style: TextStyle(fontSize: 12, color: c.textTertiary),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: c.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _deliveryCard() {
    return _InfoCard(
      children: [
        _InfoRow(
          icon: HeroAppIcons.checkDouble,
          label: AppStringKeys.messageInfoRead,
          value: _readStatus(),
        ),
        _InfoRow(
          icon: HeroAppIcons.eye,
          label: AppStringKeys.messageInfoViews,
          value: widget.message.viewCount.toString(),
        ),
        _InfoRow(
          icon: HeroAppIcons.share,
          label: AppStringKeys.messageInfoForwards,
          value: widget.message.forwardCount.toString(),
        ),
      ],
    );
  }

  Widget _viewersCard() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 7),
            child: Text(
              AppStringKeys.messageInfoViewers.l10n(context),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
          for (var index = 0; index < _viewers.length; index++) ...[
            if (index > 0) Divider(height: 1, indent: 64, color: c.divider),
            _viewerRow(_viewers[index]),
          ],
        ],
      ),
    );
  }

  Widget _viewerRow(_MessageViewer viewer) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: [
          PhotoAvatar(title: viewer.name, photo: viewer.photo, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              viewer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            DateText.messageDetailLabel(viewer.viewDate),
            style: TextStyle(fontSize: 12, color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0)
              Divider(height: 1, indent: 48, color: context.colors.divider),
            children[index],
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final AppIconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          AppIcon(icon, size: 20, color: AppTheme.brand),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label.l10n(context),
              style: TextStyle(fontSize: 15, color: c.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageViewer {
  const _MessageViewer({
    required this.userId,
    required this.name,
    required this.photo,
    required this.viewDate,
  });

  final int userId;
  final String name;
  final TdFileRef? photo;
  final int viewDate;
}
