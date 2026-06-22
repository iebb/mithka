//
//  location_picker_view.dart
//
//  QQ/WeChat-style location picker with a fixed centre pin — pan the map to aim
//  the pin; the centre coordinate is what gets sent. Uses the native Apple Maps
//  (MapKit) on iOS and flutter_map + OpenStreetMap tiles elsewhere. A 我的位置
//  button recentres on the GPS fix and the current centre's address is
//  reverse-geocoded (best-effort) into a bottom card. 发送 returns the chosen LatLng.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amap;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

class LocationPickerView extends StatefulWidget {
  const LocationPickerView({super.key, required this.initial});
  final LatLng initial;

  @override
  State<LocationPickerView> createState() => _LocationPickerViewState();
}

class _LocationPickerViewState extends State<LocationPickerView> {
  final MapController _map = MapController(); // flutter_map (Android / OSM)
  amap.AppleMapController? _appleCtrl; // Apple MapKit (iOS)
  late LatLng _center = widget.initial;
  String _address = '';
  bool _geocoding = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _reverseGeocode(_center);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _map.dispose();
    super.dispose();
  }

  void _onMove(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 650),
      () => _reverseGeocode(_center),
    );
  }

  /// Best-effort OSM Nominatim reverse geocode → a human address line.
  Future<void> _reverseGeocode(LatLng p) async {
    setState(() => _geocoding = true);
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': p.latitude.toStringAsFixed(6),
        'lon': p.longitude.toStringAsFixed(6),
        'accept-language': 'zh',
        'zoom': '18',
      });
      final client = HttpClient();
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'Mithkal/1.0');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body);
      final name = (json is Map ? json['display_name'] : null) as String?;
      if (mounted) {
        setState(() {
          _address = name ?? '';
          _geocoding = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _myLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final p = LatLng(pos.latitude, pos.longitude);
      if (Platform.isIOS) {
        _appleCtrl?.animateCamera(
          amap.CameraUpdate.newLatLngZoom(
            amap.LatLng(p.latitude, p.longitude),
            16,
          ),
        );
      } else {
        _map.move(p, 16);
      }
      _center = p;
      _reverseGeocode(p);
    } catch (_) {}
  }

  void _send() => Navigator.of(context).pop(_center);

  /// Native Apple Maps (MapKit) on iOS; flutter_map + OSM tiles elsewhere.
  Widget _mapWidget() {
    if (Platform.isIOS) {
      return amap.AppleMap(
        initialCameraPosition: amap.CameraPosition(
          target: amap.LatLng(
            widget.initial.latitude,
            widget.initial.longitude,
          ),
          zoom: 15,
        ),
        myLocationEnabled: true,
        myLocationButtonEnabled: false,
        onMapCreated: (c) => _appleCtrl = c,
        onCameraMove: (pos) =>
            _center = LatLng(pos.target.latitude, pos.target.longitude),
        onCameraIdle: () {
          _debounce?.cancel();
          _debounce = Timer(
            const Duration(milliseconds: 350),
            () => _reverseGeocode(_center),
          );
        },
      );
    }
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: widget.initial,
        initialZoom: 16,
        onPositionChanged: _onMove,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'ad.neko.mithkal',
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
          NavHeader(
            title: '位置',
            onBack: () => Navigator.of(context).pop(),
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _send,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '发送',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                _mapWidget(),
                // Fixed centre pin (its tip marks the chosen point).
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -18),
                      child: Icon(
                        sfIcon('location.fill'),
                        size: 38,
                        color: AppTheme.brand,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _myLocation,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c.card,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        sfIcon('location.fill'),
                        size: 20,
                        color: AppTheme.brand,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _addressBar(),
        ],
      ),
    );
  }

  Widget _addressBar() {
    final c = context.colors;
    return Container(
      width: double.infinity,
      color: c.card,
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Icon(sfIcon('mappin.and.ellipse'), size: 18, color: AppTheme.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _geocoding && _address.isEmpty
                  ? '正在获取位置…'
                  : (_address.isEmpty ? '拖动地图选择位置' : _address),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
