//
//  location_picker_view.dart
//
//  messenger-style location picker with a fixed centre pin — pan the map to aim
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
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

const defaultLocationPickerCenter = LatLng(35.681236, 139.767125);

Future<LatLng> resolveLocationPickerStart() async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return defaultLocationPickerCenter;
    }
    final position = await Geolocator.getCurrentPosition();
    return LatLng(position.latitude, position.longitude);
  } catch (_) {
    return defaultLocationPickerCenter;
  }
}

class LocationPickerResult {
  const LocationPickerResult({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;
}

class LocationPickerView extends StatefulWidget {
  const LocationPickerView({
    super.key,
    required this.initial,
    this.initialZoom = 16,
    this.returnCamera = false,
  });

  final LatLng initial;
  final double initialZoom;
  final bool returnCamera;

  @override
  State<LocationPickerView> createState() => _LocationPickerViewState();
}

class _LocationPickerViewState extends State<LocationPickerView> {
  static const _minimumZoom = 3.0;
  static const _maximumZoom = 20.0;

  final MapController _map = MapController(); // flutter_map (Android / OSM)
  amap.AppleMapController? _appleCtrl; // Apple MapKit (iOS)
  late LatLng _center = widget.initial;
  late double _zoom = widget.initialZoom;
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
    _zoom = camera.zoom;
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
      req.headers.set(HttpHeaders.userAgentHeader, 'Mithka/1.0');
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
      final p = await resolveLocationPickerStart();
      if (Platform.isIOS) {
        unawaited(
          _appleCtrl?.animateCamera(
            amap.CameraUpdate.newLatLngZoom(
              amap.LatLng(p.latitude, p.longitude),
              16,
            ),
          ),
        );
      } else {
        _map.move(p, 16);
      }
      _center = p;
      _zoom = 16;
      unawaited(_reverseGeocode(p));
    } catch (_) {}
  }

  void _changeZoom(double delta) {
    final next = (_zoom + delta).clamp(_minimumZoom, _maximumZoom);
    if ((next - _zoom).abs() < 0.01) return;
    setState(() => _zoom = next);
    if (Platform.isIOS) {
      unawaited(
        _appleCtrl?.animateCamera(
          amap.CameraUpdate.newLatLngZoom(
            amap.LatLng(_center.latitude, _center.longitude),
            next,
          ),
        ),
      );
    } else {
      _map.move(_center, next);
    }
  }

  void _send() => Navigator.of(context).pop(
    widget.returnCamera
        ? LocationPickerResult(center: _center, zoom: _zoom)
        : _center,
  );

  /// Native Apple Maps (MapKit) on iOS; flutter_map + OSM tiles elsewhere.
  Widget _mapWidget() {
    if (Platform.isIOS) {
      return amap.AppleMap(
        initialCameraPosition: amap.CameraPosition(
          target: amap.LatLng(
            widget.initial.latitude,
            widget.initial.longitude,
          ),
          zoom: widget.initialZoom,
        ),
        myLocationEnabled: true,
        onMapCreated: (c) => _appleCtrl = c,
        onCameraMove: (pos) {
          _center = LatLng(pos.target.latitude, pos.target.longitude);
          _zoom = pos.zoom;
        },
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
        initialZoom: widget.initialZoom,
        onPositionChanged: _onMove,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'ad.neko.mithka',
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
            title: AppStrings.t(AppStringKeys.composerLocation),
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
                  child: Text(
                    AppStrings.t(AppStringKeys.composerSend),
                    style: const TextStyle(
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
                      child: AppIcon(
                        HeroAppIcons.locationDot,
                        size: 38,
                        color: AppTheme.brand,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _mapControlButton(
                              c,
                              HeroAppIcons.plus,
                              () => _changeZoom(1),
                            ),
                            Divider(height: 1, color: c.divider),
                            _mapControlButton(
                              c,
                              HeroAppIcons.minus,
                              () => _changeZoom(-1),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _myLocation,
                        child: Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
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
                          child: AppIcon(
                            HeroAppIcons.locationDot,
                            size: 20,
                            color: AppTheme.brand,
                          ),
                        ),
                      ),
                    ],
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

  Widget _mapControlButton(AppColors c, AppIconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 40,
        child: Center(child: AppIcon(icon, size: 19, color: c.textPrimary)),
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
          AppIcon(HeroAppIcons.locationPin, size: 18, color: AppTheme.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _geocoding && _address.isEmpty
                  ? AppStrings.t(AppStringKeys.locationDetailFetchingLocation)
                  : (_address.isEmpty
                        ? AppStrings.t(
                            AppStringKeys.locationPickerDragMapToChoose,
                          )
                        : _address),
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
