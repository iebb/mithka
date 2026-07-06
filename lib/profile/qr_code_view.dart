//
//  qr_code_view.dart
//
//  我的二维码 — a personal QR card: a brand-gradient identity header, a
//  brand-tinted QR (high error correction) with the user's avatar inset in the
//  centre, on a shadowed card over a soft gradient. Encodes the user's t.me
//  profile link. Port of the Swift `QRCodeView`.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class QRCodeView extends StatefulWidget {
  const QRCodeView({
    super.key,
    this.name = AppStringKeys.chatMeLabel,
    this.chatId,
    this.isGroup = false,
  });
  final String name;
  final int? chatId; // non-null → render a group/chat QR instead of 我的二维码
  final bool isGroup;

  @override
  State<QRCodeView> createState() => _QRCodeViewState();
}

class _QRCodeViewState extends State<QRCodeView> {
  late String _name = widget.name;
  String? _username;
  TdFileRef? _photo;
  String? _link;
  bool _loadDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.chatId != null) {
      await _loadGroup();
      return;
    }
    try {
      final me = await TdClient.shared.query({'@type': 'getMe'});
      final id = me.int64('id');
      final parsed = TDParse.userName(me);
      final username = me.obj('usernames')?.str('editable_username');
      String? link;
      if (username != null && username.isNotEmpty) {
        link = 'https://t.me/$username';
      } else {
        try {
          final res = await TdClient.shared.query({'@type': 'getUserLink'});
          link = res.str('url');
        } catch (_) {}
        link ??= id != null ? 'tg://user?id=$id' : null;
      }
      if (!mounted) return;
      setState(() {
        if (parsed.isNotEmpty) _name = parsed;
        _username = username;
        _photo = TDParse.smallPhoto(me.obj('profile_photo'));
        _link = link;
        _loadDone = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loadDone = true);
    }
  }

  /// Group QR: a public chat → its t.me/username link; a private group → its
  /// primary invite link (from full info). Falls back to a "no link" message.
  Future<void> _loadGroup() async {
    Map<String, dynamic>? chat;
    try {
      chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': widget.chatId,
      });
    } catch (_) {}
    String? link;
    final type = chat?.obj('type');
    try {
      if (type?.type == 'chatTypeSupergroup') {
        final sgid = type?.int64('supergroup_id');
        final sg = await TdClient.shared.query({
          '@type': 'getSupergroup',
          'supergroup_id': sgid,
        });
        final uname = sg.obj('usernames')?.str('editable_username') ?? '';
        if (uname.isNotEmpty) {
          link = 'https://t.me/$uname';
        } else {
          final full = await TdClient.shared.query({
            '@type': 'getSupergroupFullInfo',
            'supergroup_id': sgid,
          });
          link = full.obj('invite_link')?.str('invite_link');
        }
      } else if (type?.type == 'chatTypeBasicGroup') {
        final gid = type?.int64('basic_group_id');
        final full = await TdClient.shared.query({
          '@type': 'getBasicGroupFullInfo',
          'basic_group_id': gid,
        });
        link = full.obj('invite_link')?.str('invite_link');
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      final t = chat?.str('title');
      if (t != null && t.isNotEmpty) _name = t;
      _photo = TDParse.smallPhoto(chat?.obj('photo'));
      _link = link;
      _loadDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xFFE6F2FF), c.groupedBackground],
          ),
        ),
        child: Column(
          children: [
            NavHeader(
              title: widget.isGroup
                  ? AppStringKeys.qrCodeGroupTitle
                  : AppStringKeys.qrCodeMineTitle,
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 36, 26, 36),
                child: _card(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _identityHeader(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: _qr(),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 26, left: 16, right: 16),
            child: Text(
              (widget.isGroup
                      ? AppStringKeys.qrCodeScanToJoinGroup
                      : AppStringKeys.qrCodeScanToAddFriend)
                  .l10n(context),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityHeader() {
    final circleGroups = context.watch<ThemeController>().circularGroupAvatars;
    final squareGroupAvatar = widget.isGroup && !circleGroups;
    return Container(
      height: 92,
      decoration: BoxDecoration(gradient: AppTheme.brandGradient),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: squareGroupAvatar ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: squareGroupAvatar
                  ? BorderRadius.circular(12)
                  : null,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.9),
                width: 2,
              ),
            ),
            child: PhotoAvatar(
              title: _name.l10n(context),
              photo: _photo,
              square: squareGroupAvatar,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name.l10n(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if ((_username ?? '').isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '@$_username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _qr() {
    final c = context.colors;
    final circleGroups = context.watch<ThemeController>().circularGroupAvatars;
    final squareGroupAvatar = widget.isGroup && !circleGroups;
    if (_link == null) {
      return SizedBox(
        width: 224,
        height: 224,
        child: Center(
          child: _loadDone
              ? Text(
                  AppStringKeys.qrCodeNoGroupQrCode.l10n(context),
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                )
              : const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
        ),
      );
    }
    return SizedBox(
      width: 224,
      height: 224,
      child: Stack(
        alignment: Alignment.center,
        children: [
          QrImageView(
            data: _link!,
            size: 224,
            errorCorrectionLevel: QrErrorCorrectLevel.H,
            // Fancy custom QR: rounded position eyes + circular data dots.
            eyeStyle: QrEyeStyle(
              eyeShape: QrEyeShape.circle,
              color: AppTheme.brand,
            ),
            dataModuleStyle: QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.circle,
              color: AppTheme.brand,
            ),
          ),
          // Avatar inset (H correction keeps it scannable).
          Container(
            decoration: BoxDecoration(
              shape: squareGroupAvatar ? BoxShape.rectangle : BoxShape.circle,
              borderRadius: squareGroupAvatar
                  ? BorderRadius.circular(10)
                  : null,
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: PhotoAvatar(
              title: _name.l10n(context),
              photo: _photo,
              size: 46,
              square: squareGroupAvatar,
            ),
          ),
        ],
      ),
    );
  }
}
