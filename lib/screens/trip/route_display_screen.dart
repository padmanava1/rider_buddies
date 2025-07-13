import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/trip_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/ola_maps_service.dart';
import '../../core/services/routing_service.dart';

class RouteDisplayScreen extends StatefulWidget {
  final TripRoute route;
  final List<TripPoint> tripPoints;

  const RouteDisplayScreen({required this.route, required this.tripPoints});

  @override
  State<RouteDisplayScreen> createState() => _RouteDisplayScreenState();
}

class _RouteDisplayScreenState extends State<RouteDisplayScreen> {
  final MapController _mapController = MapController();
  List<List<LatLng>> _suggestedRoutes = [];
  int _selectedRouteIndex = 0;
  List<Map<String, dynamic>> _routeDetails = [];
  bool _isLoadingRoutes = true;
  String? _routeError;
  List<Marker> _markers = [];
  List<Polyline> _polylines = [];
  bool _isLoading = true;
  String? _error;
  LatLng? _pendingBreakPoint;
  LatLng? _currentMapCenter;
  double _currentMapZoom = 12;
  int? _selectedBreakMarkerIndex;

  @override
  void initState() {
    super.initState();
    _currentMapCenter = _getMapCenter();
    _currentMapZoom = 12;
    _setupMap();
    _fetchSuggestedRoutes();
  }

  Future<void> _setupMap() async {
    _addMarkers();
    await _fetchAndAddRoutePolyline();
    setState(() {
      _isLoading = false;
    });
  }

  void _addMarkers() {
    _markers.clear();

    // Add start point marker
    if (widget.tripPoints.isNotEmpty) {
      final startPoint = widget.tripPoints.firstWhere(
        (p) => p.type == 'start',
        orElse: () => widget.tripPoints.first,
      );

      _markers.add(
        Marker(
          point: startPoint.coordinates,
          width: 40,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(Icons.trip_origin, color: Colors.white, size: 20),
          ),
        ),
      );
    }

    // Add end point marker
    final endPoint = widget.tripPoints.firstWhere(
      (p) => p.type == 'end',
      orElse: () => widget.tripPoints.last,
    );

    _markers.add(
      Marker(
        point: endPoint.coordinates,
        width: 40,
        height: 40,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(Icons.flag, color: Colors.white, size: 20),
        ),
      ),
    );

    // Add break point markers
    final breakPoints = widget.tripPoints.where((p) => p.type == 'break');
    for (final breakPoint in breakPoints) {
      _markers.add(
        Marker(
          point: breakPoint.coordinates,
          width: 30,
          height: 30,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.orange,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(Icons.coffee, color: Colors.white, size: 16),
          ),
        ),
      );
    }
  }

  Future<void> _fetchAndAddRoutePolyline() async {
    _polylines.clear();
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // Collect waypoints: start, breaks, end
      final waypoints = <LatLng>[];
      final start = widget.tripPoints
          .firstWhere(
            (p) => p.type == 'start',
            orElse: () => widget.tripPoints.first,
          )
          .coordinates;
      final end = widget.tripPoints
          .firstWhere(
            (p) => p.type == 'end',
            orElse: () => widget.tripPoints.last,
          )
          .coordinates;
      waypoints.add(start);
      waypoints.addAll(
        widget.tripPoints
            .where((p) => p.type == 'break')
            .map((p) => p.coordinates),
      );
      waypoints.add(end);

      // Call RoutingService Directions API (OSRM)
      final routeResult = await RoutingService.getRouteWithWaypoints(waypoints);
      if (routeResult != null && routeResult.fullPolyline.isNotEmpty) {
        _polylines.add(
          Polyline(
            points: routeResult.fullPolyline,
            color: AppColors.primary,
            strokeWidth: 4,
          ),
        );
      } else {
        // fallback: draw straight lines between waypoints
        _polylines.add(
          Polyline(points: waypoints, color: AppColors.primary, strokeWidth: 4),
        );
      }
    } catch (e) {
      _error = 'Failed to fetch route: $e';
      // fallback: draw straight lines between waypoints
      final waypoints = <LatLng>[];
      final start = widget.tripPoints
          .firstWhere(
            (p) => p.type == 'start',
            orElse: () => widget.tripPoints.first,
          )
          .coordinates;
      final end = widget.tripPoints
          .firstWhere(
            (p) => p.type == 'end',
            orElse: () => widget.tripPoints.last,
          )
          .coordinates;
      waypoints.add(start);
      waypoints.addAll(
        widget.tripPoints
            .where((p) => p.type == 'break')
            .map((p) => p.coordinates),
      );
      waypoints.add(end);
      _polylines.add(
        Polyline(points: waypoints, color: AppColors.primary, strokeWidth: 4),
      );
    }
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchSuggestedRoutes() async {
    setState(() {
      _isLoadingRoutes = true;
      _routeError = null;
    });
    try {
      // Prepare waypoints from tripPoints
      final waypoints = widget.tripPoints.map((p) => p.coordinates).toList();
      // For alternatives, only start and end are supported by OSRM
      if (waypoints.length < 2) {
        setState(() {
          _routeError = 'At least start and end points are required.';
          _isLoadingRoutes = false;
        });
        return;
      }
      final start = waypoints.first;
      final end = waypoints.last;
      // Fetch alternatives from RoutingService (OSRM)
      final routes = await RoutingService.getAlternativeRoutes(
        start,
        end,
        alternatives: 3,
      );
      if (routes.isNotEmpty) {
        setState(() {
          _suggestedRoutes = routes.map((r) => r.fullPolyline).toList();
          _routeDetails = routes
              .map(
                (r) => {
                  'distance': r.totalDistance,
                  'duration': r.totalDuration,
                },
              )
              .toList();
          _selectedRouteIndex = 0;
          _isLoadingRoutes = false;
        });
      } else {
        setState(() {
          _routeError = 'No routes found.';
          _isLoadingRoutes = false;
        });
      }
    } catch (e) {
      setState(() {
        _routeError = 'Failed to fetch routes: $e';
        _isLoadingRoutes = false;
      });
    }
  }

  void _onRouteTap(int index) {
    setState(() {
      _selectedRouteIndex = index;
    });
  }

  LatLng _getMapCenter() {
    if (widget.route.waypoints.isNotEmpty) {
      final points = widget.route.waypoints;
      final lat =
          points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
      final lng =
          points.map((p) => p.longitude).reduce((a, b) => a + b) /
          points.length;
      return LatLng(lat, lng);
    }
    return LatLng(20.5937, 78.9629); // Default to India center
  }

  void _zoomIn() {
    if (_currentMapCenter != null) {
      _mapController.move(_currentMapCenter!, _currentMapZoom + 1);
    }
  }

  void _zoomOut() {
    if (_currentMapCenter != null) {
      _mapController.move(_currentMapCenter!, _currentMapZoom - 1);
    }
  }

  void _onMapEvent(MapEvent event) {
    setState(() {
      _currentMapCenter = event.camera.center;
      _currentMapZoom = event.camera.zoom;
    });
  }

  void _onMapTap(TapPosition tapPosition, LatLng latlng) async {
    // Check if tap is close to a break marker
    final breakMarkerIndex = _markers.indexWhere((marker) {
      final isBreak = marker.width == 30 && marker.height == 30;
      if (!isBreak) return false;
      final dist = Distance().as(LengthUnit.Meter, marker.point, latlng);
      return dist < 30; // 30 meters threshold
    });
    if (breakMarkerIndex != -1) {
      // Prompt for removal
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove Break Point?'),
          content: Text('Do you want to remove this break point?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Remove'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        setState(() {
          _markers.removeAt(breakMarkerIndex);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Break point removed (not persisted in this demo)'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }
    // Otherwise, treat as add break point
    setState(() {
      _pendingBreakPoint = latlng;
    });
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Break Point?'),
        content: Text('Do you want to add a break point here?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Add'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // In a real app, you would update the trip points in the provider or parent
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Break point added (not persisted in this demo)'),
          backgroundColor: AppColors.warning,
        ),
      );
      setState(() {
        _markers.add(
          Marker(
            point: latlng,
            width: 30,
            height: 30,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(Icons.coffee, color: Colors.white, size: 16),
            ),
          ),
        );
        _pendingBreakPoint = null;
      });
    } else {
      setState(() {
        _pendingBreakPoint = null;
      });
    }
  }

  void _onMarkerTap(int index) async {
    // Only allow removal for break point markers
    final marker = _markers[index];
    final isBreakMarker = marker.width == 30 && marker.height == 30;
    if (!isBreakMarker) return;
    setState(() {
      _selectedBreakMarkerIndex = index;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Break Point?'),
        content: Text('Do you want to remove this break point?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        _markers.removeAt(index);
        _selectedBreakMarkerIndex = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Break point removed (not persisted in this demo)'),
          backgroundColor: AppColors.error,
        ),
      );
    } else {
      setState(() {
        _selectedBreakMarkerIndex = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Select Route', style: theme.textTheme.titleLarge),
        centerTitle: true,
      ),
      body: _isLoadingRoutes
          ? Center(child: CircularProgressIndicator())
          : _routeError != null
          ? Center(child: Text(_routeError!))
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter:
                        _suggestedRoutes.isNotEmpty &&
                            _suggestedRoutes[0].isNotEmpty
                        ? _suggestedRoutes[0][0]
                        : LatLng(20.5937, 78.9629),
                    initialZoom: 12,
                    // Remove empty callbacks that might interfere with zoom
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.example.rider_buddies', // Rider Buddies app
                    ),
                    _buildPolylines(),
                    MarkerLayer(
                      markers: [
                        ..._markers,
                        if (_pendingBreakPoint != null)
                          Marker(
                            point: _pendingBreakPoint!,
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.7),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                Icons.coffee,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                    PolylineLayer(polylines: _polylines),
                  ],
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (int i = 0; i < _routeDetails.length; i++)
                            GestureDetector(
                              onTap: () => _onRouteTap(i),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: i == _selectedRouteIndex
                                      ? AppColors.primary.withOpacity(0.15)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      'Route ${i + 1}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${(_routeDetails[i]['distance'] / 1000).toStringAsFixed(1)} km',
                                    ),
                                    Text(
                                      '${(_routeDetails[i]['duration'] / 60).toStringAsFixed(0)} min',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPolylines() {
    // Since PolylineLayer does not support onTap, we can overlay GestureDetector or use a plugin for advanced interaction.
    // For now, highlight selected route and allow selection via the bottom card.
    return PolylineLayer(
      polylines: [
        for (int i = 0; i < _suggestedRoutes.length; i++)
          Polyline(
            points: _suggestedRoutes[i],
            color: i == _selectedRouteIndex
                ? AppColors.primary
                : AppColors.secondary.withOpacity(0.5),
            strokeWidth: i == _selectedRouteIndex ? 6 : 4,
          ),
      ],
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
