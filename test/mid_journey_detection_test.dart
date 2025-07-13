import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rider_buddies/core/services/mid_journey_detection_service.dart';

void main() {
  group('MidJourneyDetectionService Tests', () {
    test('should detect mid-journey when far from start', () async {
      // Test coordinates (far from start)
      final currentLocation = LatLng(40.7128, -74.0060); // New York
      final startLocation = LatLng(34.0522, -118.2437); // Los Angeles

      final status = await MidJourneyDetectionService.detectMidJourneyStatus(
        currentLocation: currentLocation,
        tripStartLocation: startLocation,
        tripRoutePoints: null,
      );

      expect(status.isMidJourney, true);
      expect(status.distanceToStart, greaterThan(2000.0));
      expect(status.confidence, greaterThan(0.8));
    });

    test('should not detect mid-journey when close to start', () async {
      // Test coordinates (close to start)
      final currentLocation = LatLng(40.7128, -74.0060); // New York
      final startLocation = LatLng(40.7129, -74.0061); // Very close to current

      final status = await MidJourneyDetectionService.detectMidJourneyStatus(
        currentLocation: currentLocation,
        tripStartLocation: startLocation,
        tripRoutePoints: null,
      );

      expect(status.isMidJourney, false);
      expect(status.distanceToStart, lessThan(2000.0));
      expect(status.confidence, 1.0);
    });

    test('should calculate route to start point', () async {
      final currentLocation = LatLng(40.7128, -74.0060);
      final startLocation = LatLng(34.0522, -118.2437);

      final route = await MidJourneyDetectionService.calculateRouteToStart(
        currentLocation: currentLocation,
        tripStartLocation: startLocation,
      );

      expect(route, isNotNull);
      expect(route!.points, isNotEmpty);
      expect(route.distance, greaterThan(0.0));
      expect(route.duration, greaterThan(0));
    });

    test('should find best meeting point', () async {
      final currentLocation = LatLng(40.7128, -74.0060);
      final tripRoutePoints = [
        LatLng(34.0522, -118.2437), // Start
        LatLng(36.7783, -119.4179), // Middle
        LatLng(37.7749, -122.4194), // End
      ];
      final memberLocations = [
        LatLng(36.7783, -119.4179), // Member at middle
      ];

      final meetingPoint =
          await MidJourneyDetectionService.findBestMeetingPoint(
            currentLocation: currentLocation,
            tripRoutePoints: tripRoutePoints,
            memberLocations: memberLocations,
          );

      expect(meetingPoint, isNotNull);
      expect(meetingPoint!.distanceFromCurrent, greaterThanOrEqualTo(0.0));
      expect(meetingPoint.averageMemberDistance, greaterThanOrEqualTo(0.0));
    });
  });
}
