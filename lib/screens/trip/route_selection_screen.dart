import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import '../../providers/trip_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/routing_service.dart';
import '../../core/theme/app_colors.dart';

class RouteSelectionScreen extends StatefulWidget {
  final TripPoint startPoint;
  final TripPoint endPoint;
  final List<TripPoint> breakPoints;

  const RouteSelectionScreen({
    required this.startPoint,
    required this.endPoint,
    required this.breakPoints,
  });

  @override
  State<RouteSelectionScreen> createState() => _RouteSelectionScreenState();
}

class _RouteSelectionScreenState extends State<RouteSelectionScreen> {
  final MapController _mapController = MapController();
  List<RouteWithMetadata> _routes = [];
  int _selectedRouteIndex = 0;
  bool _isLoading = true;
  bool _isMapReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateRoutes();
  }

  Future<void> _generateRoutes() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      debugPrint(
        'Generating comprehensive routes from ${widget.startPoint.coordinates} to ${widget.endPoint.coordinates}',
      );

      // Use the new comprehensive routing
      final routes = await RoutingService.getComprehensiveRoutes(
        widget.startPoint.coordinates,
        widget.endPoint.coordinates,
        breakPoints: widget.breakPoints.map((bp) => bp.coordinates).toList(),
      );

      debugPrint('Total routes found: ${routes.length}');

      if (routes.isEmpty) {
        // Fallback to basic routing if comprehensive fails
        debugPrint('Comprehensive routing returned no routes, trying basic...');
        final basicRoute = await RoutingService.getRoute(
          widget.startPoint.coordinates,
          widget.endPoint.coordinates,
        );

        if (basicRoute != null) {
          setState(() {
            _routes = [
              RouteWithMetadata(
                route: basicRoute,
                name: 'Direct Route',
                description: 'Basic route to destination',
                routeType: 'fastest',
                source: 'OSRM',
              )
            ];
            _selectedRouteIndex = 0;
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = 'No routes found. Please check your start and end points.';
            _isLoading = false;
          });
        }
        return;
      }

      setState(() {
        _routes = routes;
        _selectedRouteIndex = 0;
        _isLoading = false;
      });

      // Wait for map to be ready before centering
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _centerMapOnRoute();
        }
      });
    } catch (e) {
      debugPrint('Error generating routes: $e');
      setState(() {
        _error = 'Failed to generate routes: $e';
        _isLoading = false;
      });
    }
  }

  void _centerMapOnRoute() {
    if (_routes.isNotEmpty &&
        _routes[0].route.fullPolyline.isNotEmpty &&
        _isMapReady) {
      try {
        final polyline = _routes[0].route.fullPolyline;
        final bounds = _calculateBounds(polyline);
        final center = LatLng(
          (bounds.southWest.latitude + bounds.northEast.latitude) / 2,
          (bounds.southWest.longitude + bounds.northEast.longitude) / 2,
        );
        _mapController.move(center, 12);
      } catch (e) {
        debugPrint('Error centering map: $e');
      }
    }
  }

  void _onMapReady() {
    setState(() {
      _isMapReady = true;
    });
    // Center map after it's ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _centerMapOnRoute();
      }
    });
  }

  LatLngBounds _calculateBounds(List<LatLng> points) {
    if (points.isEmpty) {
      return LatLngBounds(
        const LatLng(20.5937, 78.9629),
        const LatLng(20.5937, 78.9629),
      );
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    return LatLngBounds(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  void _selectRoute(int index) {
    HapticService.selection();
    setState(() {
      _selectedRouteIndex = index;
    });
  }

  void _confirmRoute() {
    if (_routes.isNotEmpty) {
      final selectedRouteData = _routes[_selectedRouteIndex];

      // Create TripRoute from RouteWithMetadata
      final tripRoute = TripRoute(
        id: 'route_${_selectedRouteIndex}',
        name: selectedRouteData.name,
        waypoints: [widget.startPoint.coordinates, widget.endPoint.coordinates],
        distance: selectedRouteData.route.totalDistance,
        duration: selectedRouteData.route.totalDuration,
        polyline: _encodePolyline(selectedRouteData.route.fullPolyline),
      );

      Navigator.pop(context, tripRoute);
    }
  }

  IconData _getRouteIcon(String routeType) {
    switch (routeType) {
      case 'fastest':
        return Icons.speed;
      case 'shortest':
        return Icons.straighten;
      case 'scenic':
        return Icons.landscape;
      case 'with_stops':
        return Icons.local_cafe;
      default:
        return Icons.alt_route;
    }
  }

  Color _getRouteColor(String routeType) {
    switch (routeType) {
      case 'fastest':
        return AppColors.primary;
      case 'shortest':
        return Colors.green;
      case 'scenic':
        return Colors.purple;
      case 'with_stops':
        return Colors.orange;
      default:
        return AppColors.secondary;
    }
  }

  String _encodePolyline(List<LatLng> points) {
    return points.map((p) => '${p.latitude},${p.longitude}').join('|');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Select Route', style: theme.textTheme.titleLarge),
        centerTitle: true,
        actions: [
          if (_routes.isNotEmpty)
            TextButton(
              onPressed: _confirmRoute,
              child: Text(
                'Confirm',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.startPoint.coordinates,
                    initialZoom: 12,
                    onMapEvent: (event) {
                      // Mark map as ready on first event
                      if (!_isMapReady) {
                        _onMapReady();
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.example.rider_buddies', // Rider Buddies app
                    ),
                    // Draw all routes
                    if (_routes.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          for (int i = 0; i < _routes.length; i++)
                            Polyline(
                              points: _routes[i].route.fullPolyline,
                              color: i == _selectedRouteIndex
                                  ? _getRouteColor(_routes[i].routeType)
                                  : _getRouteColor(_routes[i].routeType).withValues(alpha: 0.4),
                              strokeWidth: i == _selectedRouteIndex ? 6 : 3,
                            ),
                        ],
                      ),
                    // Markers for start, end, and break points
                    MarkerLayer(
                      markers: [
                        // Start point
                        Marker(
                          point: widget.startPoint.coordinates,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Icon(
                              Icons.trip_origin,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        // End point
                        Marker(
                          point: widget.endPoint.coordinates,
                          width: 40,
                          height: 40,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Icon(
                              Icons.flag,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        // Break points
                        ...widget.breakPoints.map(
                          (bp) => Marker(
                            point: bp.coordinates,
                            width: 30,
                            height: 30,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.orange,
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
                        ),
                      ],
                    ),
                  ],
                ),
                // Error overlay (only if critical error)
                if (_error != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Icon(Icons.error, color: Colors.red),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(color: Colors.red.shade800),
                              ),
                            ),
                            TextButton(
                              onPressed: _generateRoutes,
                              child: Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Route selection cards at bottom (only if routes exist)
                if (_routes.isNotEmpty)
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Available Routes',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${_routes.length} options',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: 200),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _routes.length,
                                itemBuilder: (context, index) {
                                  final routeData = _routes[index];
                                  final isSelected = index == _selectedRouteIndex;
                                  final routeColor = _getRouteColor(routeData.routeType);

                                  return GestureDetector(
                                    onTap: () => _selectRoute(index),
                                    child: Container(
                                      margin: EdgeInsets.only(bottom: 8),
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? routeColor.withValues(alpha: 0.1)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: isSelected
                                              ? routeColor
                                              : Colors.grey.withValues(alpha: 0.3),
                                          width: isSelected ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          // Route type icon
                                          Container(
                                            padding: EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: routeColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              _getRouteIcon(routeData.routeType),
                                              color: routeColor,
                                              size: 20,
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  routeData.name,
                                                  style: theme.textTheme.bodyLarge?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  routeData.description,
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Icon(Icons.route, size: 14, color: Colors.grey),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      '${(routeData.route.totalDistance / 1000).toStringAsFixed(1)} km',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                    SizedBox(width: 12),
                                                    Icon(Icons.access_time, size: 14, color: Colors.grey),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      '${(routeData.route.totalDuration / 60).round()} min',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isSelected)
                                            Icon(
                                              Icons.check_circle,
                                              color: routeColor,
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _confirmRoute,
                                icon: Icon(Icons.check),
                                label: Text('Select This Route'),
                                style: ElevatedButton.styleFrom(
                                  padding: EdgeInsets.symmetric(vertical: 14),
                                  backgroundColor: _getRouteColor(_routes[_selectedRouteIndex].routeType),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
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
}
