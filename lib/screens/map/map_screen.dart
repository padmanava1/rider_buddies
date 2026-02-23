import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../providers/group_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/live_group_tracking.dart';
import '../../core/services/location_permission_manager.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/map_markers.dart';
import '../../providers/trip_provider.dart';

class MapScreen extends StatefulWidget {
  final String groupCode;
  const MapScreen({required this.groupCode});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  bool _isLoading = true;
  String? _error;
  bool _hasLocationPermission = false;
  List<Marker> _markers = [];

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    try {
      // Use the new permission manager
      final hasPermission = await LocationPermissionManager.ensurePermission(
        context,
        title: 'Location Access Required',
        message:
            'We need your location to show your position on the map and help with group coordination.',
      );

      setState(() {
        _hasLocationPermission = hasPermission;
        _isLoading = false;
      });

      if (hasPermission) {
        _getCurrentLocation();
      } else {
        setState(() {
          _error =
              'Location permission is required to show your position on the map';
          _isLoading = false;
        });
      }
    } on PlatformException catch (e) {
      debugPrint('Platform exception in map screen: $e');
      setState(() {
        _error = 'Location service is unavailable. Please restart the app.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to check location permission';
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() => _isLoading = true);

      debugPrint('Getting current location in map screen...');

      // Test location access first
      final canAccessLocation =
          await LocationPermissionManager.testLocationAccess();
      if (!canAccessLocation) {
        setState(() {
          _error =
              'Location access failed. Please check your location settings.';
          _isLoading = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      debugPrint(
        'Location obtained in map screen: ${position.latitude}, ${position.longitude}',
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });

      _addCurrentLocationMarker();
      _centerMapOnLocation();
    } on PlatformException catch (e) {
      debugPrint(
        'Platform exception getting current location in map screen: $e',
      );
      setState(() {
        _error = 'Location service is unavailable. Please restart the app.';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error getting current location in map screen: $e');
      setState(() {
        _error = 'Failed to get current location: $e';
        _isLoading = false;
      });
    }
  }

  void _addCurrentLocationMarker() {
    if (_currentLocation != null) {
      _markers.add(
        Marker(
          point: _currentLocation!,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(Icons.my_location, color: Colors.white, size: 20),
          ),
        ),
      );
    }
  }

  void _centerMapOnLocation() {
    if (_currentLocation != null) {
      // Defer the map operation to ensure FlutterMap is rendered
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(_currentLocation!, 15);
        } catch (e) {
          debugPrint('Map not ready yet, will retry: $e');
          // Retry after a short delay
          Future.delayed(Duration(milliseconds: 500), () {
            try {
              _mapController.move(_currentLocation!, 15);
            } catch (e) {
              debugPrint('Map still not ready: $e');
            }
          });
        }
      });
    }
  }

  void _requestLocationPermission() async {
    final granted = await LocationPermissionManager.ensurePermission(
      context,
      title: 'Location Access Required',
      message:
          'We need your location to show your position on the map and help with group coordination.',
    );

    if (granted) {
      setState(() {
        _hasLocationPermission = true;
        _error = null;
      });
      _getCurrentLocation();
    }
  }

  void _buildMarkers() {
    _markers.clear();
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    final isLeader = tripProvider.isLeader;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = authProvider.userId;
    final trackingService = Provider.of<LiveGroupTracking>(
      context,
      listen: false,
    );

    // Add member markers
    for (final member in trackingService.memberLocations) {
      final isCurrentUser = member.userId == currentUserId;
      if (isLeader) {
        // Show status-aware marker for leaders
        _markers.add(
          MapMarkers.buildMemberMarker(member, isCurrentUser: isCurrentUser),
        );
      } else {
        // Show basic marker for non-leaders
        _markers.add(
          Marker(
            point: member.coordinates,
            width: 45,
            height: 45,
            child: Container(
              decoration: BoxDecoration(
                color: isCurrentUser ? AppColors.primary : AppColors.secondary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.person, color: Colors.white, size: 22),
            ),
          ),
        );
      }
    }
    // Add current user marker if not already present
    if (_currentLocation != null &&
        !trackingService.memberLocations.any(
          (m) => m.userId == currentUserId,
        )) {
      _markers.add(MapMarkers.buildCurrentUserMarker(_currentLocation!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Group Map', style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          if (_currentLocation != null)
            IconButton(
              icon: Icon(Icons.my_location),
              onPressed: () {
                HapticService.selection();
                _centerMapOnLocation();
              },
              tooltip: 'Center on My Location',
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  if (!_hasLocationPermission)
                    ElevatedButton.icon(
                      onPressed: _requestLocationPermission,
                      icon: Icon(Icons.location_on),
                      label: Text('Enable Location'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                    )
                  else
                    ElevatedButton(
                      onPressed: _getCurrentLocation,
                      child: Text('Retry'),
                    ),
                ],
              ),
            )
          : Column(
              children: [
                // Group Info Card
                Consumer<GroupProvider>(
                  builder: (context, groupProvider, child) {
                    final group = groupProvider.activeGroupData;
                    if (group == null) return SizedBox.shrink();

                    return Card(
                      margin: EdgeInsets.all(16),
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Group: ${group['code']}',
                              style: theme.textTheme.titleMedium,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Code: ${group['code']}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey,
                              ),
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.people,
                                  color: AppColors.primary,
                                  size: 16,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '${(group['members'] as List?)?.length ?? 0} members',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Map
                Expanded(
                  child: Consumer<LiveGroupTracking>(
                    builder: (context, tracking, child) {
                      _buildMarkers();
                      return FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter:
                              _currentLocation ?? LatLng(20.5937, 78.9629),
                          initialZoom: _currentLocation != null ? 15 : 5,
                          onMapEvent: (MapEvent event) {
                            // Handle map events
                          },
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName:
                                'com.example.rider_buddies', // Rider Buddies app
                          ),
                          MarkerLayer(markers: _markers),
                        ],
                      );
                    },
                  ),
                ),

                // Legend
                Container(
                  padding: EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLegendItem(
                        Icons.my_location,
                        AppColors.primary,
                        'Your Location',
                      ),
                      _buildLegendItem(
                        Icons.people,
                        AppColors.primary,
                        'Group Members',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String label) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12)),
      ],
    );
  }
}
