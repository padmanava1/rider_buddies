import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../providers/trip_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/services/intelligent_meeting_service.dart';
import '../../core/services/haptic_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/live_group_tracking.dart';
import '../../widgets/map_markers.dart';
import 'dart:convert'; // Added for json.decode
import 'package:http/http.dart' as http; // Added for http.get

class MeetingPointSuggestionsScreen extends StatefulWidget {
  final String groupCode;
  const MeetingPointSuggestionsScreen({required this.groupCode});

  @override
  State<MeetingPointSuggestionsScreen> createState() =>
      _MeetingPointSuggestionsScreenState();
}

class _MeetingPointSuggestionsScreenState
    extends State<MeetingPointSuggestionsScreen> {
  final MapController _mapController = MapController();
  List<MeetingPointSuggestion> _suggestions = [];
  bool _isLoading = true;
  String? _error;
  LatLng? _currentLocation;
  MeetingPointSuggestion? _selectedSuggestion;
  List<LatLng>? _routeToSuggestion; // Added for route to suggestion

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    // Load suggestions immediately without waiting for location
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMeetingPointSuggestions();
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      // Reload suggestions with current location
      _loadMeetingPointSuggestions();
    } catch (e) {
      setState(() {
        _error = 'Failed to get current location';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMeetingPointSuggestions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final trackingService = Provider.of<LiveGroupTracking>(
        context,
        listen: false,
      );

      if (!tripProvider.hasActiveTrip || tripProvider.startPoint == null) {
        setState(() {
          _error = 'No active trip or start point found';
          _isLoading = false;
        });
        return;
      }

      // Get actual member locations from tracking service
      List<LatLng> memberLocations = [];

      // Add current user location
      if (_currentLocation != null) {
        memberLocations.add(_currentLocation!);
      }

      // Add other group members' locations
      for (final member in trackingService.memberLocations) {
        // Don't add current user twice
        if (member.userId != authProvider.user?.uid) {
          memberLocations.add(member.coordinates);
        }
      }

      // If no other members are online, use some sample locations for testing
      if (memberLocations.length < 2) {
        debugPrint(
          'Only ${memberLocations.length} member(s) found, adding sample locations for testing',
        );
        // Add some sample locations around the start point for testing
        final startPoint = tripProvider.startPoint!.coordinates;
        memberLocations.addAll([
          LatLng(
            startPoint.latitude + 0.01,
            startPoint.longitude + 0.01,
          ), // ~1km away
          LatLng(
            startPoint.latitude - 0.005,
            startPoint.longitude + 0.005,
          ), // ~500m away
          LatLng(
            startPoint.latitude + 0.02,
            startPoint.longitude - 0.01,
          ), // ~2km away
        ]);
      }

      debugPrint(
        'Using ${memberLocations.length} member locations for meeting point suggestions',
      );

      final suggestions = await IntelligentMeetingService.findMeetingPoints(
        startPoint: tripProvider.startPoint!.coordinates,
        memberLocations: memberLocations,
        maxSuggestions: 5,
        routePoints: _getRoutePoints(tripProvider), // Add route points
      );

      setState(() {
        _suggestions = suggestions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load meeting point suggestions: $e';
        _isLoading = false;
      });
    }
  }

  void _selectSuggestion(MeetingPointSuggestion suggestion) {
    setState(() {
      _selectedSuggestion = suggestion;
    });

    // Center map on selected suggestion
    _mapController.move(suggestion.location, 15);

    // Show route to the selected meeting point
    _showRouteToSuggestion(suggestion);
  }

  Future<void> _showRouteToSuggestion(MeetingPointSuggestion suggestion) async {
    if (_currentLocation == null) return;

    try {
      // Show loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Calculating route to ${suggestion.name}...'),
          backgroundColor: AppColors.primary,
        ),
      );

      // Calculate route from current location to meeting point
      final route = await _calculateRouteToMeetingPoint(suggestion.location);

      if (route != null) {
        // Show route on map
        setState(() {
          _routeToSuggestion = route;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Route to ${suggestion.name} displayed on map'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not calculate route to ${suggestion.name}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error calculating route: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<List<LatLng>?> _calculateRouteToMeetingPoint(
    LatLng destination,
  ) async {
    if (_currentLocation == null) return null;

    try {
      // Use OSRM API to get route from current location to meeting point
      final response = await http.get(
        Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${_currentLocation!.longitude},${_currentLocation!.latitude};'
          '${destination.longitude},${destination.latitude}'
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

          return points;
        }
      }
    } catch (e) {
      debugPrint('Error calculating route to meeting point: $e');
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Meeting Point Suggestions',
          style: theme.textTheme.titleLarge,
        ),
        centerTitle: true,
        actions: [
          // Debug button to show member locations
          IconButton(
            icon: Icon(Icons.bug_report),
            onPressed: () {
              final trackingService = Provider.of<LiveGroupTracking>(
                context,
                listen: false,
              );
              final authProvider = Provider.of<AuthProvider>(
                context,
                listen: false,
              );

              debugPrint('=== Meeting Point Debug ===');
              debugPrint('Current Location: $_currentLocation');
              debugPrint(
                'Member Locations: ${trackingService.memberLocations.length}',
              );
              for (final member in trackingService.memberLocations) {
                debugPrint('- ${member.userId}: ${member.coordinates}');
              }
              debugPrint('Suggestions: ${_suggestions.length}');

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Members: ${trackingService.memberLocations.length}, Suggestions: ${_suggestions.length}',
                  ),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
            tooltip: 'Debug Info',
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadMeetingPointSuggestions,
            tooltip: 'Refresh Suggestions',
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
                  Text(_error!, style: theme.textTheme.bodyLarge),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadMeetingPointSuggestions,
                    child: Text('Retry'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Map
                Expanded(
                  flex: 2,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          _currentLocation ?? LatLng(20.5937, 78.9629),
                      initialZoom: 12,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.example.rider_buddies', // Rider Buddies app
                      ),
                      // Current location marker
                      if (_currentLocation != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _currentLocation!,
                              width: 40,
                              height: 40,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.my_location,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                      // Member location markers
                      MarkerLayer(markers: _buildMemberMarkers()),
                      // Meeting point markers
                      MarkerLayer(
                        markers: _suggestions.map((suggestion) {
                          final isSelected =
                              _selectedSuggestion?.location ==
                              suggestion.location;
                          return Marker(
                            point: suggestion.location,
                            width: isSelected ? 50 : 40,
                            height: isSelected ? 50 : 40,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.secondary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: isSelected ? 3 : 2,
                                ),
                              ),
                              child: Icon(
                                _getIconForType(suggestion.type),
                                color: Colors.white,
                                size: isSelected ? 24 : 20,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      // Route polyline
                      if (_routeToSuggestion != null &&
                          _routeToSuggestion!.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routeToSuggestion!,
                              strokeWidth: 4,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                // Suggestions list
                Expanded(
                  flex: 1,
                  child: Container(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Suggested Meeting Points',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _suggestions.length,
                            itemBuilder: (context, index) {
                              final suggestion = _suggestions[index];
                              final isSelected =
                                  _selectedSuggestion?.location ==
                                  suggestion.location;

                              return Card(
                                margin: EdgeInsets.only(bottom: 8),
                                elevation: isSelected ? 4 : 2,
                                color: isSelected
                                    ? AppColors.primary.withOpacity(0.1)
                                    : null,
                                child: ListTile(
                                  leading: Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      _getIconForType(suggestion.type),
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                  ),
                                  title: Text(
                                    suggestion.name,
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(suggestion.address),
                                      SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.star,
                                            size: 16,
                                            color: Colors.amber,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            '${suggestion.rating.toStringAsFixed(1)}',
                                          ),
                                          SizedBox(width: 16),
                                          Icon(
                                            Icons.directions_walk,
                                            size: 16,
                                            color: Colors.grey,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            '${(suggestion.averageDistanceFromMembers / 1000).toStringAsFixed(1)} km',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(Icons.directions),
                                    onPressed: () =>
                                        _showRouteToSuggestion(suggestion),
                                    tooltip: 'Get Directions',
                                  ),
                                  onTap: () => _selectSuggestion(suggestion),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'cafe':
        return Icons.coffee;
      case 'park':
        return Icons.park;
      case 'landmark':
        return Icons.place;
      default:
        return Icons.location_on;
    }
  }

  List<LatLng> _getRoutePoints(TripProvider tripProvider) {
    final List<LatLng> routePoints = [];

    // Add start point
    if (tripProvider.startPoint != null) {
      routePoints.add(tripProvider.startPoint!.coordinates);
    }

    // Add route polyline points if available
    if (tripProvider.selectedRoute != null &&
        tripProvider.selectedRoute!.polyline.isNotEmpty) {
      final polylineString = tripProvider.selectedRoute!.polyline;
      final points = polylineString.split('|').map((point) {
        final coords = point.split(',');
        return LatLng(double.parse(coords[0]), double.parse(coords[1]));
      }).toList();
      routePoints.addAll(points);
    }

    // Add end point
    if (tripProvider.endPoint != null) {
      routePoints.add(tripProvider.endPoint!.coordinates);
    }

    debugPrint('Extracted ${routePoints.length} route points');
    return routePoints;
  }

  List<Marker> _buildMemberMarkers() {
    final trackingService = Provider.of<LiveGroupTracking>(
      context,
      listen: false,
    );
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return trackingService.memberLocations.map((member) {
      final isCurrentUser = member.userId == authProvider.user?.uid;
      return MapMarkers.buildMemberMarker(member, isCurrentUser: isCurrentUser);
    }).toList();
  }
}
