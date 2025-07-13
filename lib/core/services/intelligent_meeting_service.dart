import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'ola_maps_service.dart';
import 'routing_service.dart';

class MeetingPointSuggestion {
  final LatLng location;
  final String name;
  final String address;
  final double distanceFromStart; // in meters
  final double averageDistanceFromMembers; // in meters
  final String type; // 'cafe', 'park', 'landmark', 'intersection'
  final double rating;

  MeetingPointSuggestion({
    required this.location,
    required this.name,
    required this.address,
    required this.distanceFromStart,
    required this.averageDistanceFromMembers,
    required this.type,
    required this.rating,
  });
}

class IntelligentMeetingService {
  static const double _maxDistanceFromStart = 5000; // 5km max from start
  static const double _maxDistanceFromMembers = 3000; // 3km max from members

  /// Find intelligent meeting points based on member locations and start point
  static Future<List<MeetingPointSuggestion>> findMeetingPoints({
    required LatLng startPoint,
    required List<LatLng> memberLocations,
    int maxSuggestions = 5,
    List<LatLng>? routePoints, // Add route points parameter
  }) async {
    try {
      debugPrint(
        'Finding meeting points for ${memberLocations.length} members',
      );

      // Calculate center point of all members
      final centerLat =
          memberLocations.map((p) => p.latitude).reduce((a, b) => a + b) /
          memberLocations.length;
      final centerLng =
          memberLocations.map((p) => p.longitude).reduce((a, b) => a + b) /
          memberLocations.length;
      final centerPoint = LatLng(centerLat, centerLng);

      debugPrint('Center point: $centerPoint');

      // If we have route points, use route-based suggestions
      if (routePoints != null && routePoints.isNotEmpty) {
        debugPrint('Using route-based meeting point suggestions');
        return _findRouteBasedMeetingPoints(
          startPoint: startPoint,
          memberLocations: memberLocations,
          routePoints: routePoints,
          maxSuggestions: maxSuggestions,
        );
      }

      // Search for nearby places around the center point
      final nearbyPlaces = await OlaMapsService.searchNearbyPlaces(
        centerPoint,
        type: 'establishment',
        radius: 5000, // 5km radius
      );

      debugPrint('Found ${nearbyPlaces.length} nearby places');

      List<MeetingPointSuggestion> suggestions = [];

      for (final place in nearbyPlaces.take(10)) {
        final placeLocation = LatLng(
          place['geometry']['location']['lat'],
          place['geometry']['location']['lng'],
        );

        // Calculate distances
        final distanceFromStart = Geolocator.distanceBetween(
          startPoint.latitude,
          startPoint.longitude,
          placeLocation.latitude,
          placeLocation.longitude,
        );

        // Calculate average distance from all members
        double totalMemberDistance = 0;
        for (final memberLocation in memberLocations) {
          totalMemberDistance += Geolocator.distanceBetween(
            memberLocation.latitude,
            memberLocation.longitude,
            placeLocation.latitude,
            placeLocation.longitude,
          );
        }
        final averageDistanceFromMembers =
            totalMemberDistance / memberLocations.length;

        // Filter based on criteria
        if (distanceFromStart <= _maxDistanceFromStart &&
            averageDistanceFromMembers <= _maxDistanceFromMembers) {
          suggestions.add(
            MeetingPointSuggestion(
              location: placeLocation,
              name: place['name'] ?? 'Unknown',
              address: place['vicinity'] ?? 'Unknown address',
              distanceFromStart: distanceFromStart,
              averageDistanceFromMembers: averageDistanceFromMembers,
              type: _determinePlaceType(place),
              rating: (place['rating'] as num?)?.toDouble() ?? 0.0,
            ),
          );
        }
      }

      // If no suggestions found from API, create fallback suggestions
      if (suggestions.isEmpty) {
        debugPrint('No suggestions from API, creating fallback suggestions');
        suggestions = _createFallbackSuggestions(
          startPoint,
          memberLocations,
          centerPoint,
        );
      }

      // Sort by score (lower is better)
      suggestions.sort((a, b) {
        final scoreA = _calculateScore(a);
        final scoreB = _calculateScore(b);
        return scoreA.compareTo(scoreB);
      });

      debugPrint('Returning ${suggestions.length} suggestions');
      return suggestions.take(maxSuggestions).toList();
    } catch (e) {
      debugPrint('Error finding meeting points: $e');
      // Return fallback suggestions on error
      return _createFallbackSuggestions(
        startPoint,
        memberLocations,
        startPoint,
      );
    }
  }

  /// Find meeting points along the actual route path
  static List<MeetingPointSuggestion> _findRouteBasedMeetingPoints({
    required LatLng startPoint,
    required List<LatLng> memberLocations,
    required List<LatLng> routePoints,
    int maxSuggestions = 5,
  }) {
    List<MeetingPointSuggestion> suggestions = [];

    // Create meeting points at different positions along the route
    final routePositions = [
      {
        'name': 'Route Start',
        'position': 0.0,
        'description': 'Trip starting point',
      },
      {
        'name': 'Route Quarter',
        'position': 0.25,
        'description': 'Quarter way through route',
      },
      {
        'name': 'Route Mid Point',
        'position': 0.5,
        'description': 'Mid-point of the route',
      },
      {
        'name': 'Route Three Quarter',
        'position': 0.75,
        'description': 'Three-quarter way through',
      },
      {
        'name': 'Route End',
        'position': 1.0,
        'description': 'Near route destination',
      },
    ];

    for (final position in routePositions) {
      final routeIndex = (routePoints.length * (position['position'] as double))
          .round();
      final clampedIndex = routeIndex.clamp(0, routePoints.length - 1);
      final routeLocation = routePoints[clampedIndex];

      final distanceFromStart = Geolocator.distanceBetween(
        startPoint.latitude,
        startPoint.longitude,
        routeLocation.latitude,
        routeLocation.longitude,
      );

      double totalMemberDistance = 0;
      for (final memberLocation in memberLocations) {
        totalMemberDistance += Geolocator.distanceBetween(
          memberLocation.latitude,
          memberLocation.longitude,
          routeLocation.latitude,
          routeLocation.longitude,
        );
      }
      final averageDistanceFromMembers =
          totalMemberDistance / memberLocations.length;

      suggestions.add(
        MeetingPointSuggestion(
          location: routeLocation,
          name: position['name'] as String,
          address: position['description'] as String,
          distanceFromStart: distanceFromStart,
          averageDistanceFromMembers: averageDistanceFromMembers,
          type: 'landmark',
          rating: 4.8, // High rating for route-based points
        ),
      );
    }

    return suggestions;
  }

  /// Create fallback meeting point suggestions when API fails
  static List<MeetingPointSuggestion> _createFallbackSuggestions(
    LatLng startPoint,
    List<LatLng> memberLocations,
    LatLng centerPoint,
  ) {
    List<MeetingPointSuggestion> suggestions = [];

    // Create route-based meeting points instead of generic locations
    final routeBasedPoints = [
      {
        'name': 'Route Start Point',
        'type': 'landmark',
        'offset': [0.0, 0.0],
        'description': 'Trip starting location',
      },
      {
        'name': 'Route Mid Point',
        'type': 'landmark',
        'offset': [0.005, 0.005],
        'description': 'Mid-point on route',
      },
      {
        'name': 'Route Checkpoint',
        'type': 'landmark',
        'offset': [0.01, 0.0],
        'description': 'Route checkpoint',
      },
      {
        'name': 'Route Junction',
        'type': 'landmark',
        'offset': [0.0, 0.01],
        'description': 'Route intersection',
      },
      {
        'name': 'Route End Point',
        'type': 'landmark',
        'offset': [0.015, 0.015],
        'description': 'Near trip destination',
      },
    ];

    for (final point in routeBasedPoints) {
      final location = LatLng(
        centerPoint.latitude + (point['offset'] as List<num>)[0],
        centerPoint.longitude + (point['offset'] as List<num>)[1],
      );

      final distanceFromStart = Geolocator.distanceBetween(
        startPoint.latitude,
        startPoint.longitude,
        location.latitude,
        location.longitude,
      );

      double totalMemberDistance = 0;
      for (final memberLocation in memberLocations) {
        totalMemberDistance += Geolocator.distanceBetween(
          memberLocation.latitude,
          memberLocation.longitude,
          location.latitude,
          location.longitude,
        );
      }
      final averageDistanceFromMembers =
          totalMemberDistance / memberLocations.length;

      suggestions.add(
        MeetingPointSuggestion(
          location: location,
          name: point['name'] as String,
          address: point['description'] as String,
          distanceFromStart: distanceFromStart,
          averageDistanceFromMembers: averageDistanceFromMembers,
          type: point['type'] as String,
          rating: 4.5, // Higher rating for route-based points
        ),
      );
    }

    return suggestions;
  }

  /// Calculate a score for ranking meeting points (lower is better)
  static double _calculateScore(MeetingPointSuggestion suggestion) {
    // Factors: distance from start (40%), distance from members (40%), rating (20%)
    final startScore = suggestion.distanceFromStart / _maxDistanceFromStart;
    final memberScore =
        suggestion.averageDistanceFromMembers / _maxDistanceFromMembers;
    final ratingScore =
        (5.0 - suggestion.rating) / 5.0; // Invert rating so lower is better

    return (startScore * 0.4) + (memberScore * 0.4) + (ratingScore * 0.2);
  }

  /// Determine the type of place
  static String _determinePlaceType(Map<String, dynamic> place) {
    final types = place['types'] as List<dynamic>? ?? [];

    if (types.contains('cafe') || types.contains('restaurant')) return 'cafe';
    if (types.contains('park') || types.contains('natural_feature'))
      return 'park';
    if (types.contains('point_of_interest') || types.contains('establishment'))
      return 'landmark';
    return 'intersection';
  }

  /// Get directions to a meeting point
  static Future<Map<String, dynamic>?> getDirectionsToMeetingPoint({
    required LatLng fromLocation,
    required LatLng toLocation,
  }) async {
    try {
      final route = await RoutingService.getRoute(fromLocation, toLocation);
      if (route != null) {
        return {
          'distance': route.totalDistance,
          'duration': route.totalDuration,
          'coordinates': route.fullPolyline,
        };
      }
      return null;
    } catch (e) {
      debugPrint('Error getting directions: $e');
      return null;
    }
  }

  /// Check if a member is too far from the start point
  static bool isMemberTooFar(LatLng memberLocation, LatLng startPoint) {
    final distance = Geolocator.distanceBetween(
      memberLocation.latitude,
      memberLocation.longitude,
      startPoint.latitude,
      startPoint.longitude,
    );
    return distance > _maxDistanceFromStart;
  }

  /// Get ETA to start point
  static String getETAToStart(double distanceInMeters) {
    // Assume average speed of 20 km/h for cycling
    final distanceInKm = distanceInMeters / 1000;
    final etaMinutes = distanceInKm * 3; // 3 minutes per km

    if (etaMinutes < 1) return 'Less than 1 minute';
    if (etaMinutes < 60) return '${etaMinutes.round()} minutes';

    final hours = (etaMinutes / 60).floor();
    final minutes = (etaMinutes % 60).round();

    if (minutes == 0) return '$hours hour${hours > 1 ? 's' : ''}';
    return '$hours hour${hours > 1 ? 's' : ''} $minutes minutes';
  }
}
