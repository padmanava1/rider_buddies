import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:math';

class OlaMapsService {
  // Ola Maps API Configuration
  static const String _baseUrl = 'https://api.olamaps.io';
  static const String _apiKey =
      '64eM9Zrb7p3kgvZqUwJbx1bJfNawEBccRTEpwPYj'; // Your API key

  // API Headers
  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent': 'RideBuddies/1.0',
  };

  // Search for places using Ola Maps Places API
  static Future<List<Map<String, dynamic>>> searchPlaces(String query) async {
    try {
      if (_apiKey == 'YOUR_OLA_MAPS_API_KEY') {
        debugPrint('Ola Maps API key not configured, using fallback');
        return _getFallbackSearchResults(query);
      }

      debugPrint('Searching for: $query');

      // Use the correct Places Autocomplete API endpoint
      final response = await http.get(
        Uri.parse(
          '$_baseUrl/places/v1/autocomplete?input=${Uri.encodeComponent(query)}&api_key=$_apiKey',
        ),
        headers: _headers,
      );

      debugPrint(
        'Ola Maps API Response Status:  [32m${response.statusCode} [0m',
      );
      debugPrint(
        'Ola Maps API Response Body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseAutocompleteResults(data);
      } else {
        debugPrint(
          'Ola Maps API error: ${response.statusCode} - ${response.body}',
        );
        return _getFallbackSearchResults(query);
      }
    } catch (e) {
      debugPrint('Ola Maps API error: $e');
      return _getFallbackSearchResults(query);
    }
  }

  // Get detailed information about a place using place_id
  static Future<Map<String, dynamic>?> getPlaceDetailsById(
    String placeId,
  ) async {
    try {
      if (_apiKey == 'YOUR_OLA_MAPS_API_KEY') {
        debugPrint('Ola Maps API key not configured, using fallback');
        return null;
      }

      debugPrint('Getting place details for: $placeId');

      final response = await http.get(
        Uri.parse(
          '$_baseUrl/places/v1/details?place_id=${Uri.encodeComponent(placeId)}&api_key=$_apiKey',
        ),
        headers: _headers,
      );

      debugPrint('Place Details API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parsePlaceDetailsResponse(data);
      } else {
        debugPrint(
          'Place Details API error: ${response.statusCode} - ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('Place Details API error: $e');
      return null;
    }
  }

  // Parse place details response
  static Map<String, dynamic>? _parsePlaceDetailsResponse(
    Map<String, dynamic> data,
  ) {
    try {
      final result = data['result'];
      if (result == null) return null;

      final geometry = result['geometry'];
      final location = geometry?['location'];

      return {
        'place_id': result['place_id'] ?? '',
        'name': result['name'] ?? 'Unknown Location',
        'formatted_address': result['formatted_address'] ?? '',
        'formatted_phone_number': result['formatted_phone_number'] ?? '',
        'international_phone_number':
            result['international_phone_number'] ?? '',
        'website': result['website'] ?? '',
        'url': result['url'] ?? '',
        'rating': result['rating']?.toDouble() ?? 0.0,
        'user_ratings_total': result['user_ratings_total'] ?? 0,
        'price_level': result['price_level'] ?? 0,
        'opening_hours': result['opening_hours'] ?? {},
        'photos': result['photos'] ?? [],
        'types': result['types'] ?? [],
        'coordinates': location != null
            ? LatLng(location['lat'].toDouble(), location['lng'].toDouble())
            : null,
        'source': 'Ola Maps',
      };
    } catch (e) {
      debugPrint('Error parsing place details: $e');
      return null;
    }
  }

  // Search for places near a specific location
  static Future<List<Map<String, dynamic>>> searchNearbyPlaces(
    LatLng location, {
    String? type,
    int radius = 5000,
    String? keyword,
  }) async {
    try {
      if (_apiKey == 'YOUR_OLA_MAPS_API_KEY') {
        debugPrint('Ola Maps API key not configured, using fallback');
        return [];
      }

      debugPrint(
        'Searching nearby places at: ${location.latitude}, ${location.longitude}',
      );

      final queryParams = {
        'location': '${location.latitude},${location.longitude}',
        'radius': radius.toString(),
        'api_key': _apiKey,
      };

      if (type != null) queryParams['type'] = type;
      if (keyword != null) queryParams['keyword'] = keyword;

      final uri = Uri.parse(
        '$_baseUrl/places/v1/nearbysearch',
      ).replace(queryParameters: queryParams);

      final response = await http.get(uri, headers: _headers);

      debugPrint('Nearby Search API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseNearbySearchResults(data);
      } else {
        debugPrint(
          'Nearby Search API error: ${response.statusCode} - ${response.body}',
        );
        return [];
      }
    } catch (e) {
      debugPrint('Nearby Search API error: $e');
      return [];
    }
  }

  // Parse nearby search results
  static List<Map<String, dynamic>> _parseNearbySearchResults(
    Map<String, dynamic> data,
  ) {
    try {
      final results = data['results'] as List?;
      if (results == null) return [];

      return results.map((result) {
        final geometry = result['geometry'];
        final location = geometry?['location'];

        return {
          'place_id': result['place_id'] ?? '',
          'name': result['name'] ?? 'Unknown Location',
          'formatted_address': result['vicinity'] ?? '',
          'rating': result['rating']?.toDouble() ?? 0.0,
          'user_ratings_total': result['user_ratings_total'] ?? 0,
          'price_level': result['price_level'] ?? 0,
          'types': result['types'] ?? [],
          'coordinates': location != null
              ? LatLng(location['lat'].toDouble(), location['lng'].toDouble())
              : null,
          'source': 'Ola Maps Nearby',
        };
      }).toList();
    } catch (e) {
      debugPrint('Error parsing nearby search results: $e');
      return [];
    }
  }

  // Try autocomplete search as fallback
  static Future<List<Map<String, dynamic>>> _tryAutocompleteSearch(
    String query,
  ) async {
    try {
      debugPrint('Trying autocomplete search...');

      final response = await http.get(
        Uri.parse(
          '$_baseUrl/places/v1/autocomplete?input=${Uri.encodeComponent(query)}&api_key=$_apiKey',
        ),
        headers: _headers,
      );

      debugPrint('Autocomplete API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseAutocompleteResults(data);
      } else {
        debugPrint('Autocomplete API also failed: ${response.statusCode}');
        return _getFallbackSearchResults(query);
      }
    } catch (e) {
      debugPrint('Autocomplete search error: $e');
      return _getFallbackSearchResults(query);
    }
  }

  // Parse places search results from Ola Maps API
  static List<Map<String, dynamic>> _parsePlacesSearchResults(
    Map<String, dynamic> data,
  ) {
    try {
      final predictions = data['predictions'] as List?;
      if (predictions == null) return [];

      return predictions.map((prediction) {
        final geometry = prediction['geometry'];
        final location = geometry?['location'];

        return {
          'name': prediction['name'] ?? 'Unknown Location',
          'address': prediction['formatted_address'] ?? '',
          'coordinates': location != null
              ? LatLng(location['lat'].toDouble(), location['lng'].toDouble())
              : LatLng(0, 0),
          'place_id': prediction['place_id'] ?? '',
          'types': prediction['types'] ?? [],
          'source': 'Ola Maps',
        };
      }).toList();
    } catch (e) {
      debugPrint('Error parsing places search results: $e');
      return [];
    }
  }

  // Parse autocomplete results from Ola Maps API
  static List<Map<String, dynamic>> _parseAutocompleteResults(
    Map<String, dynamic> data,
  ) {
    try {
      final predictions = data['predictions'] as List?;
      if (predictions == null) return [];

      return predictions.map((prediction) {
        final geometry = prediction['geometry'];
        final location = geometry?['location'];

        return {
          'name':
              prediction['structured_formatting']?['main_text'] ??
              prediction['description'] ??
              'Unknown Location',
          'address': prediction['description'] ?? '',
          'coordinates': location != null
              ? LatLng(location['lat'].toDouble(), location['lng'].toDouble())
              : LatLng(0, 0),
          'place_id': prediction['place_id'] ?? '',
          'types': prediction['types'] ?? [],
          'source': 'Ola Maps Autocomplete',
        };
      }).toList();
    } catch (e) {
      debugPrint('Error parsing autocomplete results: $e');
      return [];
    }
  }

  // Fallback search using geocoding package
  static Future<List<Map<String, dynamic>>> _getFallbackSearchResults(
    String query,
  ) async {
    try {
      debugPrint('Using fallback geocoding for: $query');
      List<Location> locations = await locationFromAddress(query);

      List<Map<String, dynamic>> results = [];
      for (Location location in locations.take(5)) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );

          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            String address = [
              place.street,
              place.locality,
              place.administrativeArea,
            ].where((part) => part != null && part.isNotEmpty).join(', ');

            results.add({
              'name': place.name ?? place.locality ?? 'Unknown Location',
              'address': address,
              'coordinates': LatLng(location.latitude, location.longitude),
              'place_id': '',
              'types': [],
              'source': 'Geocoding Fallback',
            });
          }
        } catch (e) {
          debugPrint('Error getting placemark: $e');
        }
      }

      debugPrint('Fallback results: ${results.length}');
      return results;
    } catch (e) {
      debugPrint('Fallback search error: $e');
      return [];
    }
  }

  // Get place details by coordinates (Reverse Geocoding)
  static Future<Map<String, dynamic>?> getPlaceDetails(
    LatLng coordinates,
  ) async {
    try {
      if (_apiKey == 'YOUR_OLA_MAPS_API_KEY') {
        debugPrint('Ola Maps API key not configured, using fallback');
        return _getFallbackPlaceDetails(coordinates);
      }

      final response = await http.get(
        Uri.parse(
          '$_baseUrl/places/v1/reverse-geocode?latlng=${coordinates.latitude},${coordinates.longitude}&api_key=$_apiKey',
        ),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseReverseGeocodeResults(data, coordinates);
      } else {
        debugPrint(
          'Ola Maps reverse geocoding error: ${response.statusCode} - ${response.body}',
        );
        return _getFallbackPlaceDetails(coordinates);
      }
    } catch (e) {
      debugPrint('Ola Maps reverse geocoding error: $e');
      return _getFallbackPlaceDetails(coordinates);
    }
  }

  // Parse reverse geocode results from Ola Maps API
  static Map<String, dynamic>? _parseReverseGeocodeResults(
    Map<String, dynamic> data,
    LatLng coordinates,
  ) {
    try {
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final result = results[0];
      final geometry = result['geometry'];
      final location = geometry?['location'];

      return {
        'name': result['name'] ?? 'Unknown Location',
        'address': result['formatted_address'] ?? '',
        'coordinates': coordinates,
        'place_id': result['place_id'] ?? '',
        'types': result['types'] ?? [],
        'source': 'Ola Maps',
      };
    } catch (e) {
      debugPrint('Error parsing reverse geocode results: $e');
      return null;
    }
  }

  // Fallback place details
  static Future<Map<String, dynamic>?> _getFallbackPlaceDetails(
    LatLng coordinates,
  ) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        coordinates.latitude,
        coordinates.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = [
          place.street,
          place.locality,
          place.administrativeArea,
        ].where((part) => part != null && part.isNotEmpty).join(', ');

        return {
          'name': place.name ?? place.locality ?? 'Unknown Location',
          'address': address,
          'coordinates': coordinates,
          'place_id': '',
          'types': [],
          'source': 'Geocoding Fallback',
        };
      }
    } catch (e) {
      debugPrint('Fallback place details error: $e');
    }
    return null;
  }

  // Get route between two points using Ola Maps Directions API
  static Future<Map<String, dynamic>?> getRoute(
    LatLng start,
    LatLng end, {
    String profile = 'driving',
  }) async {
    try {
      if (_apiKey == 'YOUR_OLA_MAPS_API_KEY') {
        debugPrint('Ola Maps API key not configured, using fallback');
        return _getFallbackRoute(start, end, profile);
      }

      final response = await http.post(
        Uri.parse(
          '$_baseUrl/routing/v1/directions?origin=${start.latitude},${start.longitude}&destination=${end.latitude},${end.longitude}&api_key=$_apiKey',
        ),
        headers: _headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseDirectionsResponse(data);
      } else {
        debugPrint(
          'Ola Maps routing error: ${response.statusCode} - ${response.body}',
        );
        return _getFallbackRoute(start, end, profile);
      }
    } catch (e) {
      debugPrint('Ola Maps routing error: $e');
      return _getFallbackRoute(start, end, profile);
    }
  }

  // Parse directions response from Ola Maps API
  static Map<String, dynamic>? _parseDirectionsResponse(
    Map<String, dynamic> data,
  ) {
    try {
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes[0];
      final legs = route['legs'] as List?;
      if (legs == null || legs.isEmpty) return null;

      final leg = legs[0];
      final steps = leg['steps'] as List? ?? [];

      // Extract polyline coordinates from steps
      List<LatLng> coordinates = [];
      for (var step in steps) {
        final startLocation = step['start_location'];
        final endLocation = step['end_location'];

        if (startLocation != null) {
          coordinates.add(
            LatLng(
              startLocation['lat'].toDouble(),
              startLocation['lng'].toDouble(),
            ),
          );
        }

        if (endLocation != null) {
          coordinates.add(
            LatLng(
              endLocation['lat'].toDouble(),
              endLocation['lng'].toDouble(),
            ),
          );
        }
      }

      return {
        'distance': leg['distance'] ?? 0.0,
        'duration': leg['duration'] ?? 0.0,
        'coordinates': coordinates,
        'summary': route['summary'] ?? '',
        'source': 'Ola Maps',
      };
    } catch (e) {
      debugPrint('Error parsing directions response: $e');
      return null;
    }
  }

  // Fallback route calculation
  static Future<Map<String, dynamic>?> _getFallbackRoute(
    LatLng start,
    LatLng end,
    String profile,
  ) async {
    try {
      // Simple distance calculation as fallback
      final distance = _calculateDistance(start, end);
      final duration = (distance / 1000) * 60; // Rough estimate: 1km = 1 minute

      return {
        'distance': distance,
        'duration': duration.toInt(),
        'coordinates': [start, end],
        'summary': 'Direct route',
        'source': 'Fallback Calculation',
      };
    } catch (e) {
      debugPrint('Fallback route error: $e');
      return null;
    }
  }

  // Calculate distance between two points (Haversine formula)
  static double _calculateDistance(LatLng start, LatLng end) {
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

  // Snap GPS coordinates to the nearest road
  static Future<List<LatLng>> snapToRoad(List<LatLng> coordinates) async {
    try {
      if (_apiKey == 'YOUR_OLA_MAPS_API_KEY') {
        debugPrint('Ola Maps API key not configured, using fallback');
        return coordinates; // Return original coordinates as fallback
      }

      if (coordinates.isEmpty) return [];

      debugPrint('Snapping ${coordinates.length} coordinates to road');

      // Convert coordinates to the format expected by the API
      final path = coordinates
          .map((coord) => '${coord.latitude},${coord.longitude}')
          .join('|');

      final response = await http.get(
        Uri.parse(
          '$_baseUrl/routing/v1/snap-to-road?path=${Uri.encodeComponent(path)}&api_key=$_apiKey',
        ),
        headers: _headers,
      );

      debugPrint('SnapToRoad API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseSnapToRoadResponse(data);
      } else {
        debugPrint(
          'SnapToRoad API error: ${response.statusCode} - ${response.body}',
        );
        return coordinates; // Return original coordinates as fallback
      }
    } catch (e) {
      debugPrint('SnapToRoad API error: $e');
      return coordinates; // Return original coordinates as fallback
    }
  }

  // Parse SnapToRoad response
  static List<LatLng> _parseSnapToRoadResponse(Map<String, dynamic> data) {
    try {
      final snappedPoints = data['snappedPoints'] as List?;
      if (snappedPoints == null) return [];

      return snappedPoints.map((point) {
        final location = point['location'];
        return LatLng(
          location['latitude'].toDouble(),
          location['longitude'].toDouble(),
        );
      }).toList();
    } catch (e) {
      debugPrint('Error parsing SnapToRoad response: $e');
      return [];
    }
  }

  // Optimize route with multiple waypoints
  static Future<Map<String, dynamic>?> optimizeRoute(
    LatLng start,
    LatLng end,
    List<LatLng> waypoints,
  ) async {
    try {
      if (_apiKey == 'YOUR_OLA_MAPS_API_KEY') {
        debugPrint('Ola Maps API key not configured, using fallback');
        return _getFallbackOptimizedRoute(start, end, waypoints);
      }

      debugPrint('Optimizing route with ${waypoints.length} waypoints');

      final waypointsStr = waypoints
          .map((wp) => '${wp.latitude},${wp.longitude}')
          .join('|');

      final response = await http.post(
        Uri.parse(
          '$_baseUrl/routing/v1/optimize?origin=${start.latitude},${start.longitude}&destination=${end.latitude},${end.longitude}&waypoints=${Uri.encodeComponent(waypointsStr)}&api_key=$_apiKey',
        ),
        headers: _headers,
      );

      debugPrint('Route Optimizer API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseOptimizedRouteResponse(data);
      } else {
        debugPrint(
          'Route Optimizer API error: ${response.statusCode} - ${response.body}',
        );
        return _getFallbackOptimizedRoute(start, end, waypoints);
      }
    } catch (e) {
      debugPrint('Route Optimizer API error: $e');
      return _getFallbackOptimizedRoute(start, end, waypoints);
    }
  }

  // Parse optimized route response
  static Map<String, dynamic>? _parseOptimizedRouteResponse(
    Map<String, dynamic> data,
  ) {
    try {
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes[0];
      final legs = route['legs'] as List?;
      if (legs == null || legs.isEmpty) return null;

      List<LatLng> coordinates = [];
      double totalDistance = 0.0;
      int totalDuration = 0;

      for (var leg in legs) {
        final steps = leg['steps'] as List? ?? [];

        for (var step in steps) {
          final startLocation = step['start_location'];
          final endLocation = step['end_location'];

          if (startLocation != null) {
            coordinates.add(
              LatLng(
                startLocation['lat'].toDouble(),
                startLocation['lng'].toDouble(),
              ),
            );
          }

          if (endLocation != null) {
            coordinates.add(
              LatLng(
                endLocation['lat'].toDouble(),
                endLocation['lng'].toDouble(),
              ),
            );
          }
        }

        totalDistance += (leg['distance']?['value'] ?? 0).toDouble();
        totalDuration += ((leg['duration']?['value'] ?? 0) as num).toInt();
      }

      return {
        'distance': totalDistance,
        'duration': totalDuration,
        'coordinates': coordinates,
        'waypoint_order': route['waypoint_order'] ?? [],
        'summary': route['summary'] ?? '',
        'source': 'Ola Maps Optimized',
      };
    } catch (e) {
      debugPrint('Error parsing optimized route response: $e');
      return null;
    }
  }

  // Fallback optimized route
  static Future<Map<String, dynamic>?> _getFallbackOptimizedRoute(
    LatLng start,
    LatLng end,
    List<LatLng> waypoints,
  ) async {
    try {
      // Simple fallback: connect all points in order
      List<LatLng> allPoints = [start, ...waypoints, end];
      double totalDistance = 0.0;
      int totalDuration = 0;

      for (int i = 0; i < allPoints.length - 1; i++) {
        final distance = _calculateDistance(allPoints[i], allPoints[i + 1]);
        totalDistance += distance;
        totalDuration += (distance / 1000 * 60).toInt(); // Rough estimate
      }

      return {
        'distance': totalDistance,
        'duration': totalDuration,
        'coordinates': allPoints,
        'waypoint_order': List.generate(waypoints.length, (i) => i),
        'summary': 'Fallback optimized route',
        'source': 'Fallback Calculation',
      };
    } catch (e) {
      debugPrint('Fallback optimized route error: $e');
      return null;
    }
  }

  // Get elevation data for locations
  static Future<List<double>> getElevation(List<LatLng> locations) async {
    try {
      if (_apiKey == 'YOUR_OLA_MAPS_API_KEY') {
        debugPrint('Ola Maps API key not configured, using fallback');
        return List.filled(
          locations.length,
          0.0,
        ); // Return zero elevation as fallback
      }

      debugPrint('Getting elevation for ${locations.length} locations');

      final locationsStr = locations
          .map((loc) => '${loc.latitude},${loc.longitude}')
          .join('|');

      final response = await http.get(
        Uri.parse(
          '$_baseUrl/elevation/v1/locations?locations=${Uri.encodeComponent(locationsStr)}&api_key=$_apiKey',
        ),
        headers: _headers,
      );

      debugPrint('Elevation API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseElevationResponse(data);
      } else {
        debugPrint(
          'Elevation API error: ${response.statusCode} - ${response.body}',
        );
        return List.filled(
          locations.length,
          0.0,
        ); // Return zero elevation as fallback
      }
    } catch (e) {
      debugPrint('Elevation API error: $e');
      return List.filled(
        locations.length,
        0.0,
      ); // Return zero elevation as fallback
    }
  }

  // Get elevation along a path
  static Future<List<double>> getElevationAlongPath(
    List<LatLng> path,
    int samples,
  ) async {
    try {
      if (_apiKey == 'YOUR_OLA_MAPS_API_KEY') {
        debugPrint('Ola Maps API key not configured, using fallback');
        return List.filled(samples, 0.0); // Return zero elevation as fallback
      }

      debugPrint('Getting elevation along path with $samples samples');

      final pathStr = path
          .map((loc) => '${loc.latitude},${loc.longitude}')
          .join('|');

      final response = await http.get(
        Uri.parse(
          '$_baseUrl/elevation/v1/path?path=${Uri.encodeComponent(pathStr)}&samples=$samples&api_key=$_apiKey',
        ),
        headers: _headers,
      );

      debugPrint('Elevation Path API Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseElevationResponse(data);
      } else {
        debugPrint(
          'Elevation Path API error: ${response.statusCode} - ${response.body}',
        );
        return List.filled(samples, 0.0); // Return zero elevation as fallback
      }
    } catch (e) {
      debugPrint('Elevation Path API error: $e');
      return List.filled(samples, 0.0); // Return zero elevation as fallback
    }
  }

  // Parse elevation response
  static List<double> _parseElevationResponse(Map<String, dynamic> data) {
    try {
      final results = data['results'] as List?;
      if (results == null) return [];

      return results
          .map((result) {
            return (result['elevation'] ?? 0.0).toDouble();
          })
          .toList()
          .cast<double>();
    } catch (e) {
      debugPrint('Error parsing elevation response: $e');
      return [];
    }
  }

  // Check if API key is configured
  static bool get isConfigured => _apiKey != 'YOUR_OLA_MAPS_API_KEY';

  // Get API configuration status
  static String get configurationStatus {
    if (isConfigured) {
      return 'Ola Maps API is configured and ready to use';
    } else {
      return 'Ola Maps API key not configured. Please add your API key to use advanced features.';
    }
  }

  // Test API connectivity
  static Future<bool> testApiConnection() async {
    try {
      if (!isConfigured) return false;

      debugPrint('Testing Ola Maps API connection...');

      // Test with a simple search
      final results = await searchPlaces('Mumbai');
      final isWorking = results.isNotEmpty;

      debugPrint('API Test Result: ${isWorking ? 'SUCCESS' : 'FAILED'}');
      debugPrint('Found ${results.length} results for "Mumbai"');

      return isWorking;
    } catch (e) {
      debugPrint('API connection test failed: $e');
      return false;
    }
  }

  // Test search functionality
  static Future<void> testSearchFunctionality() async {
    debugPrint('=== Testing Ola Maps Search Functionality ===');

    // Test 1: Basic search
    debugPrint('Test 1: Searching for "Mumbai"');
    final results1 = await searchPlaces('Mumbai');
    debugPrint('Results: ${results1.length}');
    for (var result in results1.take(3)) {
      debugPrint('- ${result['name']} (${result['source']})');
    }

    // Test 2: Specific location
    debugPrint('\nTest 2: Searching for "Mumbai Airport"');
    final results2 = await searchPlaces('Mumbai Airport');
    debugPrint('Results: ${results2.length}');
    for (var result in results2.take(3)) {
      debugPrint('- ${result['name']} (${result['source']})');
    }

    // Test 3: Fallback test
    debugPrint('\nTest 3: Testing fallback with invalid query');
    final results3 = await searchPlaces('xyz123invalid');
    debugPrint('Fallback Results: ${results3.length}');

    debugPrint('=== Search Test Complete ===');
  }

  // Test all API functionality
  static Future<void> testAllApis() async {
    debugPrint('=== Testing All Ola Maps APIs ===');

    // Test 1: Place Search
    debugPrint('\n1. Testing Place Search...');
    final searchResults = await searchPlaces('Mumbai');
    debugPrint('Search Results: ${searchResults.length}');

    // Test 2: Place Details (if we have a place_id)
    if (searchResults.isNotEmpty) {
      debugPrint('\n2. Testing Place Details...');
      final placeId = searchResults.first['place_id'];
      if (placeId.isNotEmpty) {
        final placeDetails = await getPlaceDetailsById(placeId);
        debugPrint(
          'Place Details: ${placeDetails != null ? 'SUCCESS' : 'FAILED'}',
        );
      }
    }

    // Test 3: Nearby Search
    debugPrint('\n3. Testing Nearby Search...');
    final nearbyResults = await searchNearbyPlaces(
      LatLng(19.0760, 72.8777), // Mumbai coordinates
      type: 'restaurant',
      radius: 5000,
    );
    debugPrint('Nearby Results: ${nearbyResults.length}');

    // Test 4: Reverse Geocoding
    debugPrint('\n4. Testing Reverse Geocoding...');
    final reverseGeocode = await getPlaceDetails(LatLng(19.0760, 72.8777));
    debugPrint(
      'Reverse Geocode: ${reverseGeocode != null ? 'SUCCESS' : 'FAILED'}',
    );

    // Test 5: Routing
    debugPrint('\n5. Testing Routing...');
    final route = await getRoute(
      LatLng(19.0760, 72.8777), // Mumbai
      LatLng(19.0896, 72.8656), // Mumbai Airport
    );
    debugPrint('Route: ${route != null ? 'SUCCESS' : 'FAILED'}');

    // Test 6: SnapToRoad
    debugPrint('\n6. Testing SnapToRoad...');
    final coordinates = [LatLng(19.0760, 72.8777), LatLng(19.0896, 72.8656)];
    final snappedCoordinates = await snapToRoad(coordinates);
    debugPrint('SnapToRoad: ${snappedCoordinates.length} coordinates');

    // Test 7: Route Optimization
    debugPrint('\n7. Testing Route Optimization...');
    final waypoints = [
      LatLng(19.0896, 72.8656), // Mumbai Airport
      LatLng(19.0760, 72.8777), // Mumbai
    ];
    final optimizedRoute = await optimizeRoute(
      LatLng(19.0760, 72.8777), // Start
      LatLng(19.0896, 72.8656), // End
      waypoints,
    );
    debugPrint(
      'Route Optimization: ${optimizedRoute != null ? 'SUCCESS' : 'FAILED'}',
    );

    // Test 8: Elevation
    debugPrint('\n8. Testing Elevation...');
    final elevation = await getElevation([
      LatLng(19.0760, 72.8777),
      LatLng(19.0896, 72.8656),
    ]);
    debugPrint('Elevation: ${elevation.length} values');

    debugPrint('\n=== All API Tests Complete ===');
  }
}
