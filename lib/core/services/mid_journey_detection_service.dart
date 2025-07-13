import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

class MidJourneyDetectionService {
  static const double _midJourneyThreshold = 2000.0; // 2km threshold
  static const double _farFromStartThreshold = 5000.0; // 5km threshold

  /// Detects if user is joining mid-journey based on their distance from trip start
  static Future<MidJourneyStatus> detectMidJourneyStatus({
    required LatLng currentLocation,
    required LatLng tripStartLocation,
    required List<LatLng>? tripRoutePoints,
  }) async {
    try {
      final distanceToStart = Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        tripStartLocation.latitude,
        tripStartLocation.longitude,
      );

      debugPrint('Distance to start: ${distanceToStart}m');

      if (distanceToStart <= _midJourneyThreshold) {
        return MidJourneyStatus(
          isMidJourney: false,
          distanceToStart: distanceToStart,
          recommendedAction: 'Join at start point',
          confidence: 1.0,
        );
      } else if (distanceToStart <= _farFromStartThreshold) {
        return MidJourneyStatus(
          isMidJourney: true,
          distanceToStart: distanceToStart,
          recommendedAction: 'Join mid-journey',
          confidence: 0.8,
        );
      } else {
        return MidJourneyStatus(
          isMidJourney: true,
          distanceToStart: distanceToStart,
          recommendedAction: 'Join mid-journey (far from start)',
          confidence: 0.9,
        );
      }
    } catch (e) {
      debugPrint('Error detecting mid-journey status: $e');
      return MidJourneyStatus(
        isMidJourney: false,
        distanceToStart: 0.0,
        recommendedAction: 'Unable to determine',
        confidence: 0.0,
      );
    }
  }

  /// Calculates route from current location to trip start point
  static Future<MidJourneyRoute?> calculateRouteToStart({
    required LatLng currentLocation,
    required LatLng tripStartLocation,
  }) async {
    try {
      debugPrint('Calculating route from current location to start point');

      final response = await http.get(
        Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${currentLocation.longitude},${currentLocation.latitude};'
          '${tripStartLocation.longitude},${tripStartLocation.latitude}'
          '?overview=full&geometries=geojson',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List;

          // Convert coordinates to LatLng points
          final points = coordinates.map((coord) {
            return LatLng(coord[1].toDouble(), coord[0].toDouble());
          }).toList();

          final distance = (route['distance'] as num).toDouble();
          final duration = (route['duration'] as num).toInt();

          return MidJourneyRoute(
            points: points,
            distance: distance,
            duration: duration,
            polyline: points
                .map((point) => '${point.latitude},${point.longitude}')
                .join('|'),
          );
        }
      }
    } catch (e) {
      debugPrint('Error calculating route to start: $e');
    }

    return null;
  }

  /// Finds the best meeting point along the trip route for mid-journey joining
  static Future<MeetingPoint?> findBestMeetingPoint({
    required LatLng currentLocation,
    required List<LatLng> tripRoutePoints,
    required List<LatLng> memberLocations,
  }) async {
    try {
      if (tripRoutePoints.isEmpty) return null;

      // Calculate distances to each route point
      List<Map<String, dynamic>> routePointDistances = [];

      for (int i = 0; i < tripRoutePoints.length; i++) {
        final routePoint = tripRoutePoints[i];
        final distanceFromCurrent = Geolocator.distanceBetween(
          currentLocation.latitude,
          currentLocation.longitude,
          routePoint.latitude,
          routePoint.longitude,
        );

        // Calculate average distance from all members
        double totalMemberDistance = 0;
        for (final memberLocation in memberLocations) {
          totalMemberDistance += Geolocator.distanceBetween(
            memberLocation.latitude,
            memberLocation.longitude,
            routePoint.latitude,
            routePoint.longitude,
          );
        }
        final averageMemberDistance =
            totalMemberDistance / memberLocations.length;

        routePointDistances.add({
          'index': i,
          'point': routePoint,
          'distanceFromCurrent': distanceFromCurrent,
          'averageMemberDistance': averageMemberDistance,
          'totalScore': distanceFromCurrent + (averageMemberDistance * 0.5),
        });
      }

      // Sort by total score (lower is better)
      routePointDistances.sort(
        (a, b) => a['totalScore'].compareTo(b['totalScore']),
      );

      if (routePointDistances.isNotEmpty) {
        final bestPoint = routePointDistances.first;
        return MeetingPoint(
          location: bestPoint['point'],
          distanceFromCurrent: bestPoint['distanceFromCurrent'],
          averageMemberDistance: bestPoint['averageMemberDistance'],
          routeIndex: bestPoint['index'],
        );
      }
    } catch (e) {
      debugPrint('Error finding best meeting point: $e');
    }

    return null;
  }

  /// Calculates route to the best meeting point
  static Future<MidJourneyRoute?> calculateRouteToMeetingPoint({
    required LatLng currentLocation,
    required LatLng meetingPoint,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${currentLocation.longitude},${currentLocation.latitude};'
          '${meetingPoint.longitude},${meetingPoint.latitude}'
          '?overview=full&geometries=geojson',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          final coordinates = geometry['coordinates'] as List;

          final points = coordinates.map((coord) {
            return LatLng(coord[1].toDouble(), coord[0].toDouble());
          }).toList();

          final distance = (route['distance'] as num).toDouble();
          final duration = (route['duration'] as num).toInt();

          return MidJourneyRoute(
            points: points,
            distance: distance,
            duration: duration,
            polyline: points
                .map((point) => '${point.latitude},${point.longitude}')
                .join('|'),
          );
        }
      }
    } catch (e) {
      debugPrint('Error calculating route to meeting point: $e');
    }

    return null;
  }
}

class MidJourneyStatus {
  final bool isMidJourney;
  final double distanceToStart;
  final String recommendedAction;
  final double confidence;

  MidJourneyStatus({
    required this.isMidJourney,
    required this.distanceToStart,
    required this.recommendedAction,
    required this.confidence,
  });
}

class MidJourneyRoute {
  final List<LatLng> points;
  final double distance;
  final int duration;
  final String polyline;

  MidJourneyRoute({
    required this.points,
    required this.distance,
    required this.duration,
    required this.polyline,
  });
}

class MeetingPoint {
  final LatLng location;
  final double distanceFromCurrent;
  final double averageMemberDistance;
  final int routeIndex;

  MeetingPoint({
    required this.location,
    required this.distanceFromCurrent,
    required this.averageMemberDistance,
    required this.routeIndex,
  });
}
