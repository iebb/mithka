import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

class VenueComposerResult {
  const VenueComposerResult({required this.title, required this.address});

  final String title;
  final String address;
}

class VenueComposerView extends StatefulWidget {
  const VenueComposerView({
    super.key,
    required this.location,
    required this.suggestedAddress,
  });

  final LatLng location;
  final String suggestedAddress;

  @override
  State<VenueComposerView> createState() => _VenueComposerViewState();
}

class _VenueComposerViewState extends State<VenueComposerView> {
  late final TextEditingController _title;
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    final parts = widget.suggestedAddress
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    _title = TextEditingController(text: parts.isEmpty ? '' : parts.first);
    _address = TextEditingController(text: widget.suggestedAddress.trim());
    _title.addListener(_rebuild);
  }

  @override
  void dispose() {
    _title
      ..removeListener(_rebuild)
      ..dispose();
    _address.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _send() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    Navigator.of(
      context,
    ).pop(VenueComposerResult(title: title, address: _address.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = _title.text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.composerVenue,
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? _send : null,
              child: Container(
                height: 34,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: enabled ? AppTheme.brand : c.divider,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Text(
                  AppStringKeys.composerSend.l10n(context),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: enabled ? c.onAccent : c.textTertiary,
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: c.card,
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.brand.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: AppIcon(
                    HeroAppIcons.venue,
                    size: 24,
                    color: AppTheme.brand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${widget.location.latitude.toStringAsFixed(6)}, '
                    '${widget.location.longitude.toStringAsFixed(6)}',
                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            color: c.card,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStringKeys.composerVenueName.l10n(context),
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                TextField(
                  controller: _title,
                  maxLength: 128,
                  decoration: const InputDecoration(counterText: ''),
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
                const SizedBox(height: 14),
                Text(
                  AppStringKeys.composerVenueAddress.l10n(context),
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
                TextField(
                  controller: _address,
                  maxLength: 256,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(counterText: ''),
                  style: TextStyle(fontSize: 16, color: c.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
