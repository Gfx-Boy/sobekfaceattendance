import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';

class LocationPickerResult {
  final double latitude;
  final double longitude;
  final double radius;

  LocationPickerResult({
    required this.latitude,
    required this.longitude,
    required this.radius,
  });
}

class LocationPickerScreen extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final double initialRadius;

  const LocationPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialRadius = 200,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late MapController _mapController;
  LatLng? _pickedLocation;
  double _radius = 200;
  bool _locating = false;

  static const _radiusOptions = [50.0, 100.0, 200.0, 300.0, 500.0, 1000.0];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _radius = widget.initialRadius;
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _pickedLocation = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
  }

  Future<void> _goToCurrentLocation() async {
    setState(() => _locating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied. Enable it in settings.')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() => _pickedLocation = ll);
      _mapController.move(ll, 16);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    if (_pickedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please tap the map or use current location to set a point')),
      );
      return;
    }
    Navigator.pop(
      context,
      LocationPickerResult(
        latitude: _pickedLocation!.latitude,
        longitude: _pickedLocation!.longitude,
        radius: _radius,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = _pickedLocation ?? const LatLng(24.7136, 46.6753); // Default: Riyadh

    return Scaffold(
      appBar: AppBar(
        title: Text(S.pickLocation),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: const Text('Confirm', style: TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: _pickedLocation != null ? 16 : 5,
              onTap: (tapPos, point) {
                setState(() => _pickedLocation = point);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.face_attendance',
              ),
              if (_pickedLocation != null) ...[
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _pickedLocation!,
                      radius: _radius,
                      useRadiusInMeter: true,
                      color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                      borderColor: AppTheme.primaryBlue,
                      borderStrokeWidth: 2,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _pickedLocation!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_pin, color: AppTheme.checkOutRed, size: 40),
                    ),
                  ],
                ),
              ],
            ],
          ),

          // Instruction banner
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.touch_app, color: Colors.white, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pickedLocation == null
                          ? 'Tap the map to set the work location'
                          : 'Lat: ${_pickedLocation!.latitude.toStringAsFixed(5)}, Lng: ${_pickedLocation!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Radius selector
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              decoration: BoxDecoration(
                color: context.colors.scaffoldBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Allowed Radius', style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                  SizedBox(height: 4),
                  Text(
                    'Employee must be within ${_radius.toInt()} meters to mark attendance',
                    style: TextStyle(color: context.colors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _radiusOptions.map((r) {
                        final selected = _radius == r;
                        return GestureDetector(
                          onTap: () => setState(() => _radius = r),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected ? AppTheme.primaryBlue : context.colors.cardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected ? AppTheme.primaryBlue : context.colors.surfaceBorder,
                              ),
                            ),
                            child: Text(
                              r >= 1000 ? '${(r / 1000).toStringAsFixed(1)}km' : '${r.toInt()}m',
                              style: TextStyle(
                                color: selected ? Colors.white : context.colors.textSecondary,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Current location FAB
          Positioned(
            right: 16,
            bottom: 160,
            child: FloatingActionButton.small(
              onPressed: _locating ? null : _goToCurrentLocation,
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primaryBlue,
              child: _locating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}
