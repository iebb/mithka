//
//  location_detail_view.dart
//
//  Read-only map screen for a received location / venue message. Uses native
//  Apple Maps on iOS and flutter_map + OpenStreetMap elsewhere, matching the
//  sender-side location picker stack.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amap;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/ui_components.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

class LocationDetailView extends StatefulWidget {
  const LocationDetailView({super.key, required this.location});

  final MessageLocation location;

  @override
  State<LocationDetailView> createState() => _LocationDetailViewState();
}

class _LocationDetailViewState extends State<LocationDetailView> {
  final MapController _map = MapController();
  String _resolvedAddress = '';
  bool _geocoding = false;

  LatLng get _point =>
      LatLng(widget.location.latitude, widget.location.longitude);

  String get _title {
    final t = widget.location.title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final resolved = _resolvedAddress.trim();
    if (resolved.isNotEmpty) return resolved.split('，').first;
    return '位置';
  }

  String get _subtitle {
    final address = widget.location.address?.trim();
    if (address != null && address.isNotEmpty) return address;
    return _resolvedAddress.trim();
  }

  @override
  void initState() {
    super.initState();
    if ((widget.location.title?.trim().isEmpty ?? true) ||
        (widget.location.address?.trim().isEmpty ?? true)) {
      unawaited(_reverseGeocode());
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocode() async {
    setState(() => _geocoding = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': widget.location.latitude.toStringAsFixed(6),
        'lon': widget.location.longitude.toStringAsFixed(6),
        'accept-language': 'zh',
        'zoom': '18',
      });
      final client = HttpClient();
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'Mithka/1.0');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body);
      final name = (json is Map ? json['display_name'] : null) as String?;
      if (!mounted) return;
      setState(() {
        _resolvedAddress = name ?? '';
        _geocoding = false;
      });
    } catch (_) {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Widget _mapWidget() {
    if (Platform.isIOS) {
      return amap.AppleMap(
        initialCameraPosition: amap.CameraPosition(
          target: amap.LatLng(_point.latitude, _point.longitude),
          zoom: 16,
        ),
        scrollGesturesEnabled: true,
        zoomGesturesEnabled: true,
        rotateGesturesEnabled: false,
        pitchGesturesEnabled: false,
        annotations: {
          amap.Annotation(
            annotationId: amap.AnnotationId('location'),
            position: amap.LatLng(_point.latitude, _point.longitude),
            infoWindow: amap.InfoWindow(
              title: _title,
              snippet: _subtitle.isEmpty ? null : _subtitle,
            ),
          ),
        },
      );
    }
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _point,
        initialZoom: 16,
        interactionOptions: const InteractionOptions(
          flags:
              InteractiveFlag.drag |
              InteractiveFlag.flingAnimation |
              InteractiveFlag.pinchMove |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom |
              InteractiveFlag.doubleTapDragZoom,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'ad.neko.mithka',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: _point,
              width: 42,
              height: 42,
              alignment: Alignment.topCenter,
              child: FaIcon(
                FontAwesomeIcons.locationPin,
                size: 38,
                color: AppTheme.brand,
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          NavHeader(title: '位置', onBack: () => Navigator.of(context).pop()),
          Expanded(child: _mapWidget()),
          Container(
            width: double.infinity,
            color: c.card,
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              14 + MediaQuery.of(context).padding.bottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FaIcon(
                  FontAwesomeIcons.locationPin,
                  size: 20,
                  color: AppTheme.brand,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _geocoding && _subtitle.isEmpty
                            ? '正在获取位置…'
                            : (_subtitle.isEmpty
                                  ? '${widget.location.latitude.toStringAsFixed(6)}, ${widget.location.longitude.toStringAsFixed(6)}'
                                  : _subtitle),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
