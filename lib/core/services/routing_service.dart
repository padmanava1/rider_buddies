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
    int alternatives = 3,
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
