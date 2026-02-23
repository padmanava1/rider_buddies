import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/trip_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/location_permission_manager.dart';
import '../../core/services/mid_journey_detection_service.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/mid_journey_join_dialog.dart';
import 'route_display_screen.dart';
import 'meeting_point_suggestions_screen.dart';
import 'dart:convert'; // Added for JSON decoding
import 'package:http/http.dart' as http; // Added for HTTP requests

class TripStatusScreen extends StatefulWidget {
  final String groupCode;
  const TripStatusScreen({required this.groupCode});

  @override
  State<TripStatusScreen> createState() => _TripStatusScreenState();
}

class _TripStatusScreenState extends State<TripStatusScreen> {
  LatLng? _currentLocation;
  double? _distanceToStart;
  String? _etaToStart;
  bool _isLoadingLocation = false;

  // Mid-journey detection variables
  MidJourneyStatus? _midJourneyStatus;
  MidJourneyRoute? _routeToStart;
  MeetingPoint? _meetingPoint;
  MidJourneyRoute? _routeToMeetingPoint;
  bool _isCheckingMidJourney = false;
  bool _hasShownMidJourneyDialog = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      tripProvider.loadTripData(widget.groupCode);
      _getCurrentLocation();
    });
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoadingLocation = true);

    try {
      final hasPermission = await LocationPermissionManager.ensurePermission(
        context,
        title: 'Location Access Required',
        message:
            'We need your location to show your distance to the start point.',
      );

      if (hasPermission) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        );

        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _isLoadingLocation = false;
        });

        _calculateDistanceToStart();
      } else {
        setState(() => _isLoadingLocation = false);
      }
    } catch (e) {
      setState(() => _isLoadingLocation = false);
      debugPrint('Error getting location: $e');
    }
  }

  void _calculateDistanceToStart() {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    if (_currentLocation != null && tripProvider.startPoint != null) {
      final distance = Geolocator.distanceBetween(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
        tripProvider.startPoint!.coordinates.latitude,
        tripProvider.startPoint!.coordinates.longitude,
      );

      setState(() {
        _distanceToStart = distance;
        // Rough ETA calculation (assuming 20 km/h average speed)
        final etaMinutes = (distance / 1000) * 3; // 3 minutes per km
        _etaToStart = etaMinutes < 1
            ? 'Less than 1 minute'
            : '${etaMinutes.round()} minutes';
      });

      // Check for mid-journey joining
      _checkMidJourneyStatus();
    }
  }

  Future<void> _checkMidJourneyStatus() async {
    if (_isCheckingMidJourney || _hasShownMidJourneyDialog) return;

    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    if (_currentLocation == null ||
        !tripProvider.hasActiveTrip ||
        tripProvider.startPoint == null) {
      return;
    }

    setState(() {
      _isCheckingMidJourney = true;
    });

    try {
      // Get trip route points
      List<LatLng>? tripRoutePoints;
      if (tripProvider.selectedRoute != null &&
          tripProvider.selectedRoute!.polyline.isNotEmpty) {
        tripRoutePoints = tripProvider.selectedRoute!.polyline.split('|').map((
          point,
        ) {
          final coords = point.split(',');
          return LatLng(double.parse(coords[0]), double.parse(coords[1]));
        }).toList();
      }

      // Detect mid-journey status
      final status = await MidJourneyDetectionService.detectMidJourneyStatus(
        currentLocation: _currentLocation!,
        tripStartLocation: tripProvider.startPoint!.coordinates,
        tripRoutePoints: tripRoutePoints,
      );

      setState(() {
        _midJourneyStatus = status;
      });

      // If mid-journey, calculate routes and show dialog
      if (status.isMidJourney && !_hasShownMidJourneyDialog) {
        await _calculateMidJourneyRoutes();
        _showMidJourneyDialog();
      }
    } catch (e) {
      debugPrint('Error checking mid-journey status: $e');
    } finally {
      setState(() {
        _isCheckingMidJourney = false;
      });
    }
  }

  Future<void> _calculateMidJourneyRoutes() async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    if (_currentLocation == null || tripProvider.startPoint == null) return;

    try {
      // Calculate route to start point
      final routeToStart =
          await MidJourneyDetectionService.calculateRouteToStart(
            currentLocation: _currentLocation!,
            tripStartLocation: tripProvider.startPoint!.coordinates,
          );

      setState(() {
        _routeToStart = routeToStart;
      });

      // If we have trip route points, find best meeting point
      if (tripProvider.selectedRoute != null &&
          tripProvider.selectedRoute!.polyline.isNotEmpty) {
        final tripRoutePoints = tripProvider.selectedRoute!.polyline
            .split('|')
            .map((point) {
              final coords = point.split(',');
              return LatLng(double.parse(coords[0]), double.parse(coords[1]));
            })
            .toList();

        // For trip status screen, we don't have member locations, so use empty list
        final memberLocations = <LatLng>[];

        final meetingPoint =
            await MidJourneyDetectionService.findBestMeetingPoint(
              currentLocation: _currentLocation!,
              tripRoutePoints: tripRoutePoints,
              memberLocations: memberLocations,
            );

        if (meetingPoint != null) {
          setState(() {
            _meetingPoint = meetingPoint;
          });

          // Calculate route to meeting point
          final routeToMeetingPoint =
              await MidJourneyDetectionService.calculateRouteToMeetingPoint(
                currentLocation: _currentLocation!,
                meetingPoint: meetingPoint.location,
              );

          setState(() {
            _routeToMeetingPoint = routeToMeetingPoint;
          });
        }
      }
    } catch (e) {
      debugPrint('Error calculating mid-journey routes: $e');
    }
  }

  void _showMidJourneyDialog() {
    if (_midJourneyStatus == null) return;

    setState(() {
      _hasShownMidJourneyDialog = true;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => MidJourneyJoinDialog(
        status: _midJourneyStatus!,
        routeToStart: _routeToStart,
        meetingPoint: _meetingPoint,
        routeToMeetingPoint: _routeToMeetingPoint,
        onJoinAtStart: () {
          HapticService.success();
          _handleJoinAtStart();
        },
        onJoinMidJourney: () {
          HapticService.success();
          _handleJoinMidJourney();
        },
        onCancel: () {
          HapticService.lightImpact();
          _handleCancelMidJourney();
        },
      ),
    );
  }

  void _handleJoinAtStart() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Joining at start point'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    // Additional logic for joining at start can be added here
  }

  void _handleJoinMidJourney() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Joining at meeting point'),
        backgroundColor: Colors.purple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    // Additional logic for joining mid-journey can be added here
  }

  void _handleCancelMidJourney() {
    setState(() {
      _hasShownMidJourneyDialog = false;
    });
    // Reset the flag to allow showing dialog again if needed
  }

  Future<void> _viewRouteOnMap() async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    if (tripProvider.selectedRoute != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RouteDisplayScreen(
            route: tripProvider.selectedRoute!,
            tripPoints: tripProvider.tripPoints,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No route selected yet'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _getDirectionsToStart() async {
    if (_currentLocation != null &&
        _distanceToStart != null &&
        _distanceToStart! > 1000) {
      // Show dialog with options for members far from start
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'You\'re ${(_distanceToStart! / 1000).toStringAsFixed(1)} km from start',
          ),
          content: Text('Would you like to get directions to the start point?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'directions'),
              child: Text('Get Directions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );

      if (result == 'directions') {
        // Implement directions to start point
        final tripProvider = Provider.of<TripProvider>(context, listen: false);
        if (tripProvider.startPoint != null) {
          try {
            // Show loading
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Calculating route to start point...'),
                backgroundColor: AppColors.primary,
              ),
            );

            // Get route from current location to start point
            final route = await _calculateRouteToStart();

            if (route != null) {
              // Navigate to route display screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RouteDisplayScreen(
                    route: route,
                    tripPoints: [tripProvider.startPoint!],
                  ),
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Could not calculate route to start point'),
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
      }
    }
  }

  Future<TripRoute?> _calculateRouteToStart() async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    if (_currentLocation == null || tripProvider.startPoint == null) {
      return null;
    }

    try {
      // Use OSRM API to get route from current location to start point
      final response = await http.get(
        Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${_currentLocation!.longitude},${_currentLocation!.latitude};'
          '${tripProvider.startPoint!.coordinates.longitude},${tripProvider.startPoint!.coordinates.latitude}'
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

          // Create TripRoute object
          return TripRoute(
            id: 'directions_to_start',
            name: 'Route to Start Point',
            waypoints: [
              _currentLocation!,
              tripProvider.startPoint!.coordinates,
            ],
            distance: (route['distance'] as num).toDouble(),
            duration: (route['duration'] as num).toInt(),
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

  Future<void> _showMeetingPointSuggestions() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MeetingPointSuggestionsScreen(groupCode: widget.groupCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Trip Status', style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          // Debug button for testing distance features
          IconButton(
            icon: Icon(Icons.bug_report),
            onPressed: () {
              debugPrint('=== Distance Debug Info ===');
              debugPrint('Current Location: $_currentLocation');
              debugPrint('Distance to Start: $_distanceToStart');
              debugPrint('ETA to Start: $_etaToStart');

              final tripProvider = Provider.of<TripProvider>(
                context,
                listen: false,
              );
              debugPrint('Has Active Trip: ${tripProvider.hasActiveTrip}');
              debugPrint(
                'Start Point: ${tripProvider.startPoint?.coordinates}',
              );

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Distance: ${_distanceToStart?.toStringAsFixed(1)}m, ETA: $_etaToStart',
                  ),
                  backgroundColor: AppColors.primary,
                ),
              );
            },
            tooltip: 'Debug Distance Info',
          ),
        ],
      ),
      body: Consumer<TripProvider>(
        builder: (context, tripProvider, child) {
          if (tripProvider.isLoading) {
            return Center(child: CircularProgressIndicator());
          }

          if (tripProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(
                    tripProvider.error!,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      tripProvider.clearError();
                      tripProvider.loadTripData(widget.groupCode);
                    },
                    child: Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (!tripProvider.hasActiveTrip) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No active trip', style: theme.textTheme.titleLarge),
                  SizedBox(height: 8),
                  Text(
                    'The group leader will start trip planning soon',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Trip Status Card
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Trip Status',
                            style: theme.textTheme.titleLarge,
                          ),
                          SizedBox(height: 8),
                          Text(
                            _getStatusText(
                              tripProvider.tripData?['status'] ?? 'planning',
                            ),
                            style: theme.textTheme.bodyLarge,
                          ),
                          if (tripProvider.selectedRoute != null) ...[
                            SizedBox(height: 8),
                            Text(
                              'Route: ${tripProvider.selectedRoute!.name}',
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              'Distance: ${(tripProvider.selectedRoute!.distance / 1000).toStringAsFixed(1)} km',
                              style: theme.textTheme.bodyMedium,
                            ),
                            Text(
                              'Duration: ${(tripProvider.selectedRoute!.duration / 60).round()} min',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // Current Location Card (for members)
                  if (_currentLocation != null || _isLoadingLocation)
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.my_location,
                                  color: AppColors.primary,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Your Location',
                                  style: theme.textTheme.titleMedium,
                                ),
                                Spacer(),
                                if (_isLoadingLocation)
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppColors.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            SizedBox(height: 8),
                            if (_currentLocation != null) ...[
                              Text(
                                'Lat: ${_currentLocation!.latitude.toStringAsFixed(4)}',
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(
                                'Lng: ${_currentLocation!.longitude.toStringAsFixed(4)}',
                                style: theme.textTheme.bodyMedium,
                              ),
                              if (_distanceToStart != null) ...[
                                SizedBox(height: 8),
                                Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _distanceToStart! > 5000
                                        ? Colors.red.withValues(alpha: 0.1)
                                        : _distanceToStart! > 1000
                                        ? Colors.orange.withValues(alpha: 0.1)
                                        : Colors.green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _distanceToStart! > 5000
                                          ? Colors.red.withValues(alpha: 0.3)
                                          : _distanceToStart! > 1000
                                          ? Colors.orange.withValues(alpha: 0.3)
                                          : Colors.green.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        _distanceToStart! > 5000
                                            ? Icons.warning
                                            : _distanceToStart! > 1000
                                            ? Icons.info
                                            : Icons.check_circle,
                                        color: _distanceToStart! > 5000
                                            ? Colors.red
                                            : _distanceToStart! > 1000
                                            ? Colors.orange
                                            : Colors.green,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Distance to Start: ${(_distanceToStart! / 1000).toStringAsFixed(1)} km',
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                            ),
                                            if (_etaToStart != null)
                                              Text(
                                                'ETA: $_etaToStart',
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                      color: AppColors.warning,
                                                    ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (_distanceToStart! > 1000)
                                        IconButton(
                                          onPressed: _getDirectionsToStart,
                                          icon: Icon(Icons.directions),
                                          tooltip: 'Get Directions',
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ] else if (_isLoadingLocation) ...[
                              Text(
                                'Getting your location...',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (_currentLocation != null || _isLoadingLocation)
                    SizedBox(height: 16),

                  // Distance Warning Card (always show if distance > 500m)
                  if (_distanceToStart != null && _distanceToStart! > 500)
                    Card(
                      color: _distanceToStart! > 2000
                          ? Colors.orange.shade50
                          : Colors.blue.shade50,
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _distanceToStart! > 2000
                                      ? Icons.warning
                                      : Icons.info,
                                  color: _distanceToStart! > 2000
                                      ? Colors.orange
                                      : Colors.blue,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  _distanceToStart! > 2000
                                      ? 'You\'re far from the start point'
                                      : 'Distance to Start Point',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              'You are ${(_distanceToStart! / 1000).toStringAsFixed(1)} km from the trip start point.',
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (_etaToStart != null) ...[
                              SizedBox(height: 4),
                              Text(
                                'Estimated arrival time: $_etaToStart',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                            if (_distanceToStart! > 1000) ...[
                              SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _showMeetingPointSuggestions,
                                      icon: Icon(Icons.search),
                                      label: Text('Find Meeting Points'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.warning,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _getDirectionsToStart,
                                      icon: Icon(Icons.directions),
                                      label: Text('Get Directions'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (_distanceToStart != null && _distanceToStart! > 500)
                    SizedBox(height: 16),

                  // Meeting Point Suggestions (if far from start)
                  if (_distanceToStart != null &&
                      _distanceToStart! > 1000) // Lowered from 2000m to 1000m
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.group, color: AppColors.warning),
                                SizedBox(width: 8),
                                Text(
                                  'Meeting Point Suggestions',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              'You\'re ${(_distanceToStart! / 1000).toStringAsFixed(1)} km from the start point.',
                              style: theme.textTheme.bodyMedium,
                            ),
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.warning.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: AppColors.warning,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Meeting point suggestions will be available when other members join the trip on the way.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: Colors.orange[700]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_distanceToStart != null &&
                      _distanceToStart! > 1000) // Lowered from 2000m to 1000m
                    SizedBox(height: 16),

                  // Start Point
                  if (tripProvider.startPoint != null)
                    _buildPointCard(
                      context,
                      'Start Point',
                      tripProvider.startPoint!,
                      Icons.trip_origin,
                      AppColors.primary,
                    ),
                  if (tripProvider.startPoint != null) SizedBox(height: 16),

                  // End Point
                  if (tripProvider.endPoint != null)
                    _buildPointCard(
                      context,
                      'End Point',
                      tripProvider.endPoint!,
                      Icons.flag,
                      Colors.red,
                    ),
                  if (tripProvider.endPoint != null) SizedBox(height: 16),

                  // Break Points
                  if (tripProvider.breakPoints.isNotEmpty) ...[
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Break Points',
                              style: theme.textTheme.titleMedium,
                            ),
                            SizedBox(height: 8),
                            ...tripProvider.breakPoints.map(
                              (point) => _buildBreakPointTile(context, point),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 16),
                  ],

                  // Trip Actions (if active)
                  if (tripProvider.tripData?['status'] == 'active')
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Trip Actions',
                              style: theme.textTheme.titleMedium,
                            ),
                            SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                HapticService.mediumImpact();
                                _viewRouteOnMap();
                              },
                              icon: Icon(Icons.map),
                              label: Text('View Route on Map'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                HapticService.mediumImpact();
                                setState(() {
                                  _hasShownMidJourneyDialog = false;
                                });
                                _checkMidJourneyStatus();
                              },
                              icon: Icon(Icons.join_full),
                              label: Text('Check Mid-Journey Status'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            SizedBox(height: 8),
                            if (_currentLocation != null &&
                                _distanceToStart != null)
                              ListTile(
                                leading: Icon(
                                  Icons.directions_walk,
                                  color: AppColors.primary,
                                ),
                                title: Text(
                                  'Distance to Start: ${(_distanceToStart! / 1000).toStringAsFixed(1)} km',
                                ),
                                subtitle: Text('ETA: $_etaToStart'),
                                onTap: () => _getDirectionsToStart(),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPointCard(
    BuildContext context,
    String title,
    TripPoint point,
    IconData icon,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  SizedBox(height: 4),
                  Text(point.name, style: theme.textTheme.bodyLarge),
                  Text(
                    point.address,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakPointTile(BuildContext context, TripPoint point) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.coffee, color: Colors.orange, size: 20),
      ),
      title: Text(point.name),
      subtitle: Text(point.address),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'planning':
        return 'Trip planning in progress';
      case 'active':
        return 'Trip is active';
      case 'completed':
        return 'Trip completed';
      case 'cancelled':
        return 'Trip cancelled';
      default:
        return 'Unknown status';
    }
  }
}
