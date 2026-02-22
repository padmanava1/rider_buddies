import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'dart:math';

class RoutePoint {
  final LatLng coordinates;
  final String? name;
  final String? address;

  RoutePoint({required this.coordinates, this.name, this.address});
}

class RouteSegment {
  final LatLng start;
  final LatLng end;
  final double distance; // meters
  final int duration; // seconds
  final List<LatLng> polyline;

  RouteSegment({
    required this.start,
    required this.end,
    required this.distance,
    required this.duration,
    required this.polyline,
  });
}

class RouteResult {
  final List<RouteSegment> segments;
  final double totalDistance; // meters
  final int totalDuration; // seconds
  final List<LatLng> fullPolyline;

  RouteResult({
    required this.segments,
    required this.totalDistance,
    required this.totalDuration,
    required this.fullPolyline,
  });
}

class RouteWithMetadata {
  final RouteResult route;
  final String name;
  final String description;
  final String routeType; // 'fastest', 'shortest', 'scenic', 'alternative', 'with_stops'
  final String source; // 'OSRM', 'Ola Maps', etc.

  RouteWithMetadata({
    required this.route,
    required this.name,
    required this.description,
    required this.routeType,
    required this.source,
  });
}

class RoutingService {
  static const String _baseUrl = 'https://router.project-osrm.org/route/v1';

  // Get route between two points
  static Future<RouteResult?> getRoute(
    LatLng start,
    LatLng end, {
    String profile = 'driving', // driving, walking, cycling
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/$profile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseRouteResponse(data);
      } else {
        print('Routing API error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error getting route: $e');
      return null;
    }
  }

  // Get route with multiple waypoints
  static Future<RouteResult?> getRouteWithWaypoints(
    List<LatLng> waypoints, {
    String profile = 'driving',
  }) async {
    if (waypoints.length < 2) return null;

    try {
      final coordinates = waypoints
          .map((wp) => '${wp.longitude},${wp.latitude}')
          .join(';');

      final url = Uri.parse(
        '$_baseUrl/$profile/$coordinates'
        '?overview=full&geometries=geojson&steps=true',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseRouteResponse(data);
      } else {
        print('Routing API error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error getting route with waypoints: $e');
      return null;
    }
  }

  // Parse OSRM response
  static RouteResult? _parseRouteResponse(Map<String, dynamic> data) {
    try {
      final routes = data['routes'] as List;
      if (routes.isEmpty) return null;

      final route = routes[0];
      final geometry = route['geometry'];
      final legs = route['legs'] as List;

      // Parse polyline
      List<LatLng> fullPolyline = [];
      if (geometry['type'] == 'LineString') {
        final coordinates = geometry['coordinates'] as List;
        fullPolyline = coordinates.map((coord) {
          return LatLng(coord[1].toDouble(), coord[0].toDouble());
        }).toList();
      }

      // Parse segments
      List<RouteSegment> segments = [];
      double totalDistance = 0;
      int totalDuration = 0;

      for (int i = 0; i < legs.length; i++) {
        final leg = legs[i];
        final steps = leg['steps'] as List;

        for (int j = 0; j < steps.length; j++) {
          final step = steps[j];
          final geometry = step['geometry'];

          List<LatLng> polyline = [];
          if (geometry['type'] == 'LineString') {
            final coordinates = geometry['coordinates'] as List;
            polyline = coordinates.map((coord) {
              return LatLng(coord[1].toDouble(), coord[0].toDouble());
            }).toList();
          }

          if (polyline.isNotEmpty) {
            // Handle both int and double values for distance and duration
            final distance = (step['distance'] as num).toDouble();
            final duration = (step['duration'] as num).toInt();

            segments.add(
              RouteSegment(
                start: polyline.first,
                end: polyline.last,
                distance: distance,
                duration: duration,
                polyline: polyline,
              ),
            );

            totalDistance += distance;
            totalDuration += duration;
          }
        }
      }

      return RouteResult(
        segments: segments,
        totalDistance: totalDistance,
        totalDuration: totalDuration,
        fullPolyline: fullPolyline,
      );
    } catch (e) {
      print('Error parsing route response: $e');
      return null;
    }
  }

  // Get alternative routes
  static Future<List<RouteResult>> getAlternativeRoutes(
    LatLng start,
    LatLng end, {
    String profile = 'driving',
    int alternatives = 5,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/$profile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&steps=true&alternatives=$alternatives',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List;

        return routes
            .map(
              (route) => _parseRouteResponse({
                'routes': [route],
              }),
            )
            .where((route) => route != null)
            .cast<RouteResult>()
            .toList();
      } else {
        print('Routing API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error getting alternative routes: $e');
      return [];
    }
  }

  // Get comprehensive routes with multiple strategies
  // IMPORTANT: When breakPoints are provided, ALL routes pass through them
  static Future<List<RouteWithMetadata>> getComprehensiveRoutes(
    LatLng start,
    LatLng end, {
    List<LatLng>? breakPoints,
  }) async {
    List<RouteWithMetadata> allRoutes = [];
    final hasBreakPoints = breakPoints != null && breakPoints.isNotEmpty;

    if (hasBreakPoints) {
      // ===== BREAKPOINTS MODE =====
      // ALL routes must pass through the breakpoints
      print('Generating routes through ${breakPoints.length} break point(s)...');

      // Primary waypoints: start -> breakpoints -> end
      List<LatLng> waypoints = [start, ...breakPoints, end];

      // Route 1: Direct route through all breakpoints (fastest)
      final primaryRoute = await getRouteWithWaypoints(waypoints);
      if (primaryRoute != null) {
        allRoutes.add(RouteWithMetadata(
          route: primaryRoute,
          name: 'Fastest via Stops',
          description: 'Quickest route through ${breakPoints.length} stop(s)',
          routeType: 'with_stops',
          source: 'OSRM',
        ));
      }

      // Route 2-3: Try alternative approaches to first/last breakpoint
      await _addBreakpointAlternatives(allRoutes, start, end, breakPoints);

    } else {
      // ===== NO BREAKPOINTS MODE =====
      // Standard routing with alternatives
      print('Fetching OSRM routes with alternatives...');
      final osrmRoutes = await getAlternativeRoutes(start, end, alternatives: 5);

      for (int i = 0; i < osrmRoutes.length; i++) {
        final route = osrmRoutes[i];
        String routeType;
        String description;

        if (i == 0) {
          routeType = 'fastest';
          description = 'Fastest route based on current conditions';
        } else {
          final isShorter = route.totalDistance < osrmRoutes[0].totalDistance;
          final isLonger = route.totalDistance > osrmRoutes[0].totalDistance * 1.1;

          if (isShorter) {
            routeType = 'shortest';
            description = 'Shorter distance, may take longer';
          } else if (isLonger) {
            routeType = 'scenic';
            description = 'Longer route, possibly more scenic';
          } else {
            routeType = 'alternative';
            description = 'Alternative route option';
          }
        }

        allRoutes.add(RouteWithMetadata(
          route: route,
          name: _generateRouteName(i, routeType),
          description: description,
          routeType: routeType,
          source: 'OSRM',
        ));
      }

      // Generate more alternatives if needed
      if (allRoutes.length < 3) {
        print('Generating waypoint-based alternatives...');
        final waypointRoutes = await _generateWaypointAlternatives(start, end);
        for (var route in waypointRoutes) {
          if (_isRouteSufficientlyDifferent(route.route, allRoutes.map((r) => r.route).toList())) {
            allRoutes.add(route);
          }
        }
      }
    }

    // Sort routes appropriately
    allRoutes.sort((a, b) {
      // Routes with stops come first when breakpoints exist
      if (hasBreakPoints) {
        // Sort by duration for routes with stops
        return a.route.totalDuration.compareTo(b.route.totalDuration);
      }
      // Standard sorting for non-breakpoint routes
      if (a.routeType == 'fastest') return -1;
      if (b.routeType == 'fastest') return 1;
      if (a.routeType == 'shortest') return -1;
      if (b.routeType == 'shortest') return 1;
      return a.route.totalDuration.compareTo(b.route.totalDuration);
    });

    // Limit to top 5 most relevant routes
    return allRoutes.take(5).toList();
  }

  // Generate alternative routes that still pass through all breakpoints
  static Future<void> _addBreakpointAlternatives(
    List<RouteWithMetadata> allRoutes,
    LatLng start,
    LatLng end,
    List<LatLng> breakPoints,
  ) async {
    // Try to get alternatives by varying the approach to the first breakpoint
    try {
      // Get alternative routes to first breakpoint
      final toFirstBreak = await getAlternativeRoutes(start, breakPoints.first, alternatives: 2);

      if (toFirstBreak.length > 1) {
        // Build route using alternative path to first breakpoint, then continue normally
        List<LatLng> remainingWaypoints = [...breakPoints, end];
        final remainingRoute = await getRouteWithWaypoints(remainingWaypoints);

        if (remainingRoute != null) {
          final altRoute = toFirstBreak[1]; // Use the second alternative

          // Combine the routes
          final combinedPolyline = [...altRoute.fullPolyline, ...remainingRoute.fullPolyline];
          final combinedDistance = altRoute.totalDistance + remainingRoute.totalDistance;
          final combinedDuration = altRoute.totalDuration + remainingRoute.totalDuration;

          allRoutes.add(RouteWithMetadata(
            route: RouteResult(
              segments: [...altRoute.segments, ...remainingRoute.segments],
              totalDistance: combinedDistance,
              totalDuration: combinedDuration,
              fullPolyline: combinedPolyline,
            ),
            name: 'Alternative via Stops',
            description: 'Different approach, same ${breakPoints.length} stop(s)',
            routeType: 'with_stops',
            source: 'OSRM',
          ));
        }
      }

      // Try alternative from last breakpoint to end
      final fromLastBreak = await getAlternativeRoutes(breakPoints.last, end, alternatives: 2);

      if (fromLastBreak.length > 1) {
        List<LatLng> initialWaypoints = [start, ...breakPoints];
        final initialRoute = await getRouteWithWaypoints(initialWaypoints);

        if (initialRoute != null) {
          final altRoute = fromLastBreak[1];

          final combinedPolyline = [...initialRoute.fullPolyline, ...altRoute.fullPolyline];
          final combinedDistance = initialRoute.totalDistance + altRoute.totalDistance;
          final combinedDuration = initialRoute.totalDuration + altRoute.totalDuration;

          // Only add if sufficiently different
          if (_isRouteSufficientlyDifferent(
            RouteResult(
              segments: [],
              totalDistance: combinedDistance,
              totalDuration: combinedDuration,
              fullPolyline: combinedPolyline,
            ),
            allRoutes.map((r) => r.route).toList(),
          )) {
            allRoutes.add(RouteWithMetadata(
              route: RouteResult(
                segments: [...initialRoute.segments, ...altRoute.segments],
                totalDistance: combinedDistance,
                totalDuration: combinedDuration,
                fullPolyline: combinedPolyline,
              ),
              name: 'Scenic via Stops',
              description: 'Different ending, same ${breakPoints.length} stop(s)',
              routeType: 'with_stops',
              source: 'OSRM',
            ));
          }
        }
      }
    } catch (e) {
      print('Error generating breakpoint alternatives: $e');
    }
  }

  // Generate alternative routes using intermediate waypoints
  static Future<List<RouteWithMetadata>> _generateWaypointAlternatives(
    LatLng start,
    LatLng end,
  ) async {
    List<RouteWithMetadata> routes = [];

    // Calculate midpoint and offset points for alternatives
    final midLat = (start.latitude + end.latitude) / 2;
    final midLng = (start.longitude + end.longitude) / 2;

    // Calculate perpendicular offset (about 10% of the distance)
    final dx = end.longitude - start.longitude;
    final dy = end.latitude - start.latitude;
    final dist = sqrt(dx * dx + dy * dy);
    final offsetFactor = dist * 0.1;

    // Try routes via offset midpoints
    final offsets = [
      LatLng(midLat + offsetFactor, midLng - offsetFactor), // North-West
      LatLng(midLat - offsetFactor, midLng + offsetFactor), // South-East
    ];

    for (int i = 0; i < offsets.length; i++) {
      try {
        final route = await getRouteWithWaypoints([start, offsets[i], end]);
        if (route != null) {
          routes.add(RouteWithMetadata(
            route: route,
            name: i == 0 ? 'Northern Route' : 'Southern Route',
            description: 'Alternative path via ${i == 0 ? 'northern' : 'southern'} areas',
            routeType: 'alternative',
            source: 'OSRM (via waypoint)',
          ));
        }
      } catch (e) {
        print('Error generating waypoint alternative: $e');
      }
    }

    return routes;
  }

  // Check if a route is sufficiently different from existing routes
  static bool _isRouteSufficientlyDifferent(RouteResult newRoute, List<RouteResult> existingRoutes) {
    for (var existing in existingRoutes) {
      // Routes are considered similar if distance differs by less than 5%
      final distanceDiff = (newRoute.totalDistance - existing.totalDistance).abs();
      final maxDistance = max(newRoute.totalDistance, existing.totalDistance);
      if (distanceDiff / maxDistance < 0.05) {
        return false;
      }
    }
    return true;
  }

  // Generate descriptive route name
  static String _generateRouteName(int index, String routeType) {
    switch (routeType) {
      case 'fastest':
        return 'Fastest Route';
      case 'shortest':
        return 'Shortest Distance';
      case 'scenic':
        return 'Scenic Route';
      case 'highway':
        return 'Highway Route';
      case 'local':
        return 'Local Roads';
      default:
        return 'Alternative ${index > 0 ? index : ''}';
    }
  }

  // Calculate distance between two points (Haversine formula)
  static double calculateDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371000; // meters
    final double lat1 = start.latitude * (pi / 180);
    final double lat2 = end.latitude * (pi / 180);
    final double deltaLat = (end.latitude - start.latitude) * (pi / 180);
    final double deltaLon = (end.longitude - start.longitude) * (pi / 180);

    final double a =
        sin(deltaLat / 2) * sin(deltaLat / 2) +
        cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  // Estimate duration based on distance and profile
  static int estimateDuration(double distance, String profile) {
    double speed; // meters per second

    switch (profile) {
      case 'driving':
        speed = 13.89; // ~50 km/h average
        break;
      case 'cycling':
        speed = 5.56; // ~20 km/h average
        break;
      case 'walking':
        speed = 1.39; // ~5 km/h average
        break;
      default:
        speed = 13.89;
    }

    return (distance / speed).round();
  }
}
