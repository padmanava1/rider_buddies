import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
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
  List<RouteResult> _routes = [];
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
        'Generating routes from ${widget.startPoint.coordinates} to ${widget.endPoint.coordinates}',
      );
      List<RouteResult> routes = [];

      // Route 1: Direct route
      debugPrint('Fetching direct route...');
      final directRoute = await RoutingService.getRoute(
        widget.startPoint.coordinates,
        widget.endPoint.coordinates,
        profile: 'driving',
      );

      if (directRoute != null) {
        debugPrint(
          'Direct route found: ${directRoute.totalDistance}m, ${directRoute.totalDuration}s',
        );
        routes.add(directRoute);
      } else {
        debugPrint('Direct route not found');
      }

      // Route 2: Alternative routes
      debugPrint('Fetching alternative routes...');
      final alternativeRoutes = await RoutingService.getAlternativeRoutes(
        widget.startPoint.coordinates,
        widget.endPoint.coordinates,
        profile: 'driving',
        alternatives: 2,
      );

      debugPrint('Found ${alternativeRoutes.length} alternative routes');
      routes.addAll(alternativeRoutes);

      // Route 3: Route with break points (if any)
      if (widget.breakPoints.isNotEmpty) {
        debugPrint('Fetching route with break points...');
        List<LatLng> waypoints = [widget.startPoint.coordinates];
        waypoints.addAll(widget.breakPoints.map((bp) => bp.coordinates));
        waypoints.add(widget.endPoint.coordinates);

        final scenicRoute = await RoutingService.getRouteWithWaypoints(
          waypoints,
          profile: 'driving',
        );

        if (scenicRoute != null) {
          debugPrint(
            'Scenic route found: ${scenicRoute.totalDistance}m, ${scenicRoute.totalDuration}s',
          );
          routes.add(scenicRoute);
        } else {
          debugPrint('Scenic route not found');
        }
      }

      debugPrint('Total routes found: ${routes.length}');
      if (routes.isEmpty) {
        setState(() {
          _error = 'No routes found. Please check your start and end points.';
          _isLoading = false;
        });
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
        _routes[0].fullPolyline.isNotEmpty &&
        _isMapReady) {
      try {
        final polyline = _routes[0].fullPolyline;
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
      final selectedRoute = _routes[_selectedRouteIndex];

      // Create TripRoute from RouteResult
      final tripRoute = TripRoute(
        id: 'route_${_selectedRouteIndex}',
        name: _getRouteName(_selectedRouteIndex),
        waypoints: [widget.startPoint.coordinates, widget.endPoint.coordinates],
        distance: selectedRoute.totalDistance,
        duration: selectedRoute.totalDuration,
        polyline: _encodePolyline(selectedRoute.fullPolyline),
      );

      Navigator.pop(context, tripRoute);
    }
  }

  String _getRouteName(int index) {
    if (index == 0) return 'Fastest Route';
    if (index == 1) return 'Alternative Route 1';
    if (index == 2) return 'Alternative Route 2';
    if (widget.breakPoints.isNotEmpty && index == _routes.length - 1) {
      return 'Route with Break Points';
    }
    return 'Route ${index + 1}';
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
                              points: _routes[i].fullPolyline,
                              color: i == _selectedRouteIndex
                                  ? AppColors.primary
                                  : AppColors.secondary.withOpacity(0.6),
                              strokeWidth: i == _selectedRouteIndex ? 6 : 4,
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
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Available Routes',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 12),
                            ...List.generate(_routes.length, (index) {
                              final route = _routes[index];
                              final isSelected = index == _selectedRouteIndex;

                              return GestureDetector(
                                onTap: () => _selectRoute(index),
                                child: Container(
                                  margin: EdgeInsets.only(bottom: 8),
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary.withOpacity(0.1)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary
                                          : Colors.grey.withOpacity(0.3),
                                      width: isSelected ? 2 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 4,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.secondary,
                                          borderRadius: BorderRadius.circular(
                                            2,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _getRouteName(index),
                                              style: theme.textTheme.bodyLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.route,
                                                  size: 16,
                                                  color: Colors.grey,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  '${(route.totalDistance / 1000).toStringAsFixed(1)} km',
                                                  style:
                                                      theme.textTheme.bodySmall,
                                                ),
                                                SizedBox(width: 16),
                                                Icon(
                                                  Icons.access_time,
                                                  size: 16,
                                                  color: Colors.grey,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  '${(route.totalDuration / 60).toStringAsFixed(0)} min',
                                                  style:
                                                      theme.textTheme.bodySmall,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(
                                          Icons.check_circle,
                                          color: AppColors.primary,
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            }),
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
