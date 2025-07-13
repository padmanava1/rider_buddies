import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart'; // Add compass support
import '../../providers/group_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/live_group_tracking.dart';
import '../../core/services/location_permission_manager.dart';
import '../../core/services/mid_journey_detection_service.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/location_permission_dialog.dart';
import '../../widgets/map_markers.dart';
import '../../widgets/mid_journey_join_dialog.dart';
import '../../providers/trip_provider.dart';
import '../trip/meeting_point_suggestions_screen.dart';
import 'dart:convert'; // Added for json
import 'package:http/http.dart' as http; // Added for http
import 'dart:async'; // Added for StreamSubscription
import 'package:flutter_compass/flutter_compass.dart'; // Added for CompassEvent

class LiveGroupMapScreen extends StatefulWidget {
  final String groupCode;
  const LiveGroupMapScreen({super.key, required this.groupCode});

  @override
  State<LiveGroupMapScreen> createState() => _LiveGroupMapScreenState();
}

class _LiveGroupMapScreenState extends State<LiveGroupMapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  bool _isLoading = true;
  String? _error;
  bool _hasLocationPermission = false;
  bool _isSharingLocation = false;
  List<Marker> _markers = [];
  LiveGroupTracking? _trackingService;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  List<Polyline> _routePolylines = []; // Add route polylines
  double? _distanceToStart;
  String? _etaToStart;
  List<Polyline> _directionsToStartPolylines =
      []; // Add directions to start polylines

  // Mid-journey detection variables
  MidJourneyStatus? _midJourneyStatus;
  MidJourneyRoute? _routeToStart;
  MeetingPoint? _meetingPoint;
  MidJourneyRoute? _routeToMeetingPoint;
  bool _isCheckingMidJourney = false;
  bool _hasShownMidJourneyDialog = false;

  // Direction tracking
  double? _currentHeading;
  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<CompassEvent>?
  _compassSubscription; // Add compass subscription
  String? _currentDirection; // Add cardinal direction tracking
  bool _compassNeedsCalibration = false; // Add calibration status

  /// Convert heading degrees to cardinal direction
  String _getCardinalDirection(double heading) {
    // Normalize heading to 0-360 degrees
    double normalizedHeading = heading % 360;
    if (normalizedHeading < 0) normalizedHeading += 360;

    // Define cardinal directions with their degree ranges
    if (normalizedHeading >= 337.5 || normalizedHeading < 22.5) {
      return 'North';
    } else if (normalizedHeading >= 22.5 && normalizedHeading < 67.5) {
      return 'Northeast';
    } else if (normalizedHeading >= 67.5 && normalizedHeading < 112.5) {
      return 'East';
    } else if (normalizedHeading >= 112.5 && normalizedHeading < 157.5) {
      return 'Southeast';
    } else if (normalizedHeading >= 157.5 && normalizedHeading < 202.5) {
      return 'South';
    } else if (normalizedHeading >= 202.5 && normalizedHeading < 247.5) {
      return 'Southwest';
    } else if (normalizedHeading >= 247.5 && normalizedHeading < 292.5) {
      return 'West';
    } else if (normalizedHeading >= 292.5 && normalizedHeading < 337.5) {
      return 'Northwest';
    } else {
      return 'North';
    }
  }

  /// Get short direction format (N, NE, E, SE, S, SW, W, NW)
  String _getShortDirection(String fullDirection) {
    switch (fullDirection) {
      case 'North':
        return 'N';
      case 'Northeast':
        return 'NE';
      case 'East':
        return 'E';
      case 'Southeast':
        return 'SE';
      case 'South':
        return 'S';
      case 'Southwest':
        return 'SW';
      case 'West':
        return 'W';
      case 'Northwest':
        return 'NW';
      default:
        return 'N';
    }
  }

  /// Show compass calibration guidance
  void _showCalibrationGuidance() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.compass_calibration, color: Colors.orange),
            SizedBox(width: 8),
            Text('Calibrate Compass'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To calibrate your device compass:'),
            SizedBox(height: 12),
            Text('1. Hold your device flat'),
            Text('2. Move it in a figure-8 pattern'),
            Text('3. Rotate it slowly in all directions'),
            Text('4. Keep moving until the compass works'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'This helps the device understand its orientation relative to Earth\'s magnetic field.',
                style: TextStyle(fontSize: 12, color: Colors.orange[700]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkLocationPermission();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _trackingService = Provider.of<LiveGroupTracking>(
          context,
          listen: false,
        );
        _startGroupTracking();
        _loadTripData(); // Load trip data for all members
        _loadTripRoute(); // Load trip route if available
        _calculateDistanceToStart(); // Calculate distance to start
        _checkLocationSharingStatus(); // Check if user is already sharing location

        // Ensure route loads after a short delay to allow trip data to load
        Future.delayed(Duration(milliseconds: 500), () {
          if (mounted) {
            _loadTripRoute();
          }
        });
      }
    });
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(begin: Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeController.forward();
    _slideController.forward();
  }

  Future<void> _checkLocationPermission() async {
    try {
      final hasPermission = await LocationPermissionManager.ensurePermission(
        context,
        title: 'Location Access Required',
        message:
            'We need your location to show your position on the map and help with group coordination.',
      );

      setState(() {
        _hasLocationPermission = hasPermission;
        _isLoading = false;
      });

      if (hasPermission) {
        _getCurrentLocation();
      } else {
        setState(() {
          _error =
              'Location permission is required to show your position on the map';
          _isLoading = false;
        });
      }
    } on PlatformException catch (e) {
      debugPrint('Platform exception in live map screen: $e');
      setState(() {
        _error = 'Location service is unavailable. Please restart the app.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to check location permission';
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() => _isLoading = true);

      debugPrint('Getting current location...');

      // Test location access first
      final canAccessLocation =
          await LocationPermissionManager.testLocationAccess();
      if (!canAccessLocation) {
        setState(() {
          _error =
              'Location access failed. Please check your location settings.';
          _isLoading = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      debugPrint(
        'Location obtained: ${position.latitude}, ${position.longitude}',
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _currentHeading = position.heading;
        _currentDirection = _getCardinalDirection(_currentHeading!);
        _isLoading = false;
      });

      _centerMapOnLocation();
      _calculateDistanceToStart(); // Calculate distance to start

      // Start location stream for continuous updates including heading
      _startLocationStream();
    } on PlatformException catch (e) {
      debugPrint('Platform exception getting current location: $e');
      setState(() {
        _error = 'Location service is unavailable. Please restart the app.';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error getting current location: $e');
      setState(() {
        _error = 'Failed to get current location: $e';
        _isLoading = false;
      });
    }
  }

  void _startLocationStream() {
    _locationSubscription?.cancel();
    _compassSubscription?.cancel();

    // Start location stream for position updates
    _locationSubscription =
        Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5, // Update every 5 meters
            timeLimit: Duration(seconds: 30),
          ),
        ).listen(
          (Position position) {
            debugPrint(
              'Location update - Accuracy: ${position.accuracy}m, Speed: ${position.speed}m/s',
            );

            setState(() {
              _currentLocation = LatLng(position.latitude, position.longitude);
            });

            _calculateDistanceToStart();
          },
          onError: (e) {
            debugPrint('Error in location stream: $e');
          },
        );

    // Start compass stream for heading updates
    _compassSubscription = FlutterCompass.events?.listen(
      (CompassEvent event) {
        if (event.heading != null) {
          debugPrint('Compass update - Heading: ${event.heading}°');

          setState(() {
            _currentHeading = event.heading;
            _currentDirection = _getCardinalDirection(event.heading!);
            _compassNeedsCalibration =
                false; // Reset calibration flag when we get data
          });
        } else {
          // Handle calibration issues
          debugPrint('Compass needs calibration or is unreliable');
          setState(() {
            _compassNeedsCalibration = true;
          });
        }
      },
      onError: (e) {
        debugPrint('Error in compass stream: $e');
        setState(() {
          _compassNeedsCalibration = true;
        });
      },
    );
  }

  void _startGroupTracking() {
    _trackingService?.startTracking(widget.groupCode);
  }

  void _centerMapOnLocation() {
    if (_currentLocation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _mapController.move(_currentLocation!, 15);
        } catch (e) {
          debugPrint('Map not ready yet, will retry: $e');
          Future.delayed(Duration(milliseconds: 500), () {
            try {
              _mapController.move(_currentLocation!, 15);
            } catch (e) {
              debugPrint('Map still not ready: $e');
            }
          });
        }
      });
    }
  }

  void _toggleLocationSharing() async {
    HapticService.mediumImpact();

    if (!LocationPermissionManager.hasPermission) {
      final granted = await LocationPermissionManager.ensurePermission(
        context,
        title: 'Location Access Required',
        message: 'We need your location to share your position with the group.',
      );

      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location permission required to share location'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
        return;
      }
    }

    if (_isSharingLocation) {
      await _trackingService?.stopLocationSharing();
      setState(() {
        _isSharingLocation = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Location sharing stopped'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } else {
      if (_currentLocation != null) {
        await _trackingService?.updateMyLocation(_currentLocation!);
        await _trackingService?.startLocationSharing();
        setState(() {
          _isSharingLocation = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location sharing started'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please enable location access first'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  void _updateMyStatus(String status) async {
    HapticService.mediumImpact();
    await _trackingService?.updateMyStatus(status);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Status updated: $status'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _buildMarkers() {
    _markers.clear();
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    final isLeader = tripProvider.isLeader;
    final currentUser = Provider.of<AuthProvider>(context, listen: false).user;
    final currentUserId = currentUser?.uid;

    // Track which users are already represented by member markers
    Set<String> usersWithMarkers = {};
    bool isCurrentUserInMembers = false;

    // Add member markers with enhanced identification
    for (final member in _trackingService?.memberLocations ?? []) {
      final isCurrentUser = member.userId == currentUserId;
      if (isCurrentUser) isCurrentUserInMembers = true;

      // Use enhanced member marker for all users
      _markers.add(
        MapMarkers.buildMemberMarker(member, isCurrentUser: isCurrentUser),
      );
      usersWithMarkers.add(member.userId);
    }

    // Add trip point markers if available
    if (tripProvider.hasActiveTrip) {
      // Start point
      if (tripProvider.startPoint != null) {
        _markers.add(
          MapMarkers.buildStartMarker(
            tripProvider.startPoint!.coordinates,
            tripProvider.startPoint!.name,
          ),
        );
      }

      // End point
      if (tripProvider.endPoint != null) {
        _markers.add(
          MapMarkers.buildEndMarker(
            tripProvider.endPoint!.coordinates,
            tripProvider.endPoint!.name,
          ),
        );
      }

      // Break points
      for (final breakPoint in tripProvider.breakPoints) {
        _markers.add(
          MapMarkers.buildBreakMarker(breakPoint.coordinates, breakPoint.name),
        );
      }
    }

    // Only add current user marker if:
    // 1. We have current location
    // 2. User is NOT sharing location
    // 3. User is NOT already represented by a member marker
    if (_currentLocation != null &&
        (!_isSharingLocation && !isCurrentUserInMembers)) {
      _markers.add(
        MapMarkers.buildCurrentUserMarker(
          _currentLocation!,
          heading: _currentHeading,
        ),
      );
    }
  }

  void _loadTripRoute() {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    if (tripProvider.hasActiveTrip && tripProvider.selectedRoute != null) {
      debugPrint('Loading trip route for all members');
      // Decode polyline from selected route
      final polylineString = tripProvider.selectedRoute!.polyline;
      if (polylineString.isNotEmpty) {
        final points = polylineString.split('|').map((point) {
          final coords = point.split(',');
          return LatLng(double.parse(coords[0]), double.parse(coords[1]));
        }).toList();

        setState(() {
          _routePolylines = [
            Polyline(
              points: points,
              color: AppColors.primary.withOpacity(0.7),
              strokeWidth: 4,
            ),
          ];
        });
        debugPrint('Route loaded with ${points.length} points');
      } else {
        debugPrint('Route polyline is empty');
      }
    } else {
      debugPrint('No active trip or selected route');
      // Try to load trip data again if not available
      if (!tripProvider.hasActiveTrip) {
        _loadTripData();
      }
    }
  }

  void _loadTripData() {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    // Load trip data for all members, not just leaders
    tripProvider.loadTripData(widget.groupCode);
    debugPrint('Loading trip data for group: ${widget.groupCode}');
  }

  void _calculateDistanceToStart() {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    if (_currentLocation != null &&
        tripProvider.hasActiveTrip &&
        tripProvider.startPoint != null) {
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

      // If far from start point, calculate route to start
      if (distance > 1000) {
        _calculateRouteToStart();
      }

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

        // Get member locations for meeting point calculation
        final memberLocations =
            _trackingService?.memberLocations
                .map((member) => member.coordinates)
                .toList() ??
            [];

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
    // Clear mid-journey routes
    setState(() {
      _routeToStart = null;
      _routeToMeetingPoint = null;
      _meetingPoint = null;
    });

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
    // Clear mid-journey routes
    setState(() {
      _routeToStart = null;
      _routeToMeetingPoint = null;
      _meetingPoint = null;
    });

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
    // Clear mid-journey routes
    setState(() {
      _routeToStart = null;
      _routeToMeetingPoint = null;
      _meetingPoint = null;
      _hasShownMidJourneyDialog = false;
    });
    // Reset the flag to allow showing dialog again if needed
  }

  Future<void> _calculateRouteToStart() async {
    final tripProvider = Provider.of<TripProvider>(context, listen: false);
    if (_currentLocation == null || tripProvider.startPoint == null) {
      return;
    }

    try {
      debugPrint('Calculating route from current location to start point');

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

          setState(() {
            _directionsToStartPolylines = [
              Polyline(
                points: points,
                color: Colors.blue.withOpacity(
                  0.8,
                ), // Changed from orange to blue
                strokeWidth: 3,
              ),
            ];
          });

          debugPrint(
            'Route to start point calculated with ${points.length} points',
          );
        }
      }
    } catch (e) {
      debugPrint('Error calculating route to start: $e');
    }
  }

  Future<void> _showMeetingPointSuggestions() async {
    // Only show meeting point suggestions if someone joins on the way
    // For now, this feature is disabled
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Meeting point suggestions will be available when members join on the way',
        ),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _checkLocationSharingStatus() {
    // Check if user is already sharing location
    final currentUser = Provider.of<AuthProvider>(context, listen: false).user;
    final currentUserId = currentUser?.uid;

    if (currentUserId != null) {
      final isSharing =
          _trackingService?.memberLocations.any(
            (member) => member.userId == currentUserId,
          ) ??
          false;

      setState(() {
        _isSharingLocation = isSharing;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Group Map', style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          if (_currentLocation != null)
            IconButton(
              icon: Icon(Icons.my_location),
              onPressed: () {
                HapticService.selection();
                _centerMapOnLocation();
              },
              tooltip: 'Center on My Location',
            ),
          // Mid-journey detection button
          if (_currentLocation != null)
            IconButton(
              icon: Icon(Icons.join_full),
              onPressed: () {
                HapticService.mediumImpact();
                setState(() {
                  _hasShownMidJourneyDialog = false;
                });
                _checkMidJourneyStatus();
              },
              tooltip: 'Check Mid-Journey Status',
            ),
          PopupMenuButton<String>(
            onSelected: _updateMyStatus,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'riding',
                child: Row(
                  children: [
                    Icon(Icons.directions_bike, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Riding'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'at_break',
                child: Row(
                  children: [
                    Icon(Icons.coffee, color: AppColors.warning),
                    SizedBox(width: 8),
                    Text('At Break'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'arrived',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: AppColors.secondary),
                    SizedBox(width: 8),
                    Text('Arrived'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'stopped',
                child: Row(
                  children: [
                    Icon(Icons.stop, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Stopped'),
                  ],
                ),
              ),
            ],
            icon: Icon(Icons.more_vert),
            tooltip: 'Update Status',
          ),
        ],
      ),
      body: _isLoading
          ? _buildAnimatedLoadingScreen(theme)
          : _error != null
          ? _buildErrorScreen(theme)
          : FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    // Group Info and Controls
                    Consumer<GroupProvider>(
                      builder: (context, groupProvider, child) {
                        final group = groupProvider.activeGroupData;
                        if (group == null) return SizedBox.shrink();

                        return Card(
                          margin: EdgeInsets.all(16),
                          elevation: 4,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Group: ${group['code']}',
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            'Code: ${group['code']}',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: Colors.grey[600],
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      children: [
                                        Consumer<LiveGroupTracking>(
                                          builder: (context, tracking, child) {
                                            return Text(
                                              '${tracking.onlineMembers.length} online',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: Colors.grey[600],
                                                  ),
                                            );
                                          },
                                        ),
                                        Switch(
                                          value: _isSharingLocation,
                                          onChanged: (value) =>
                                              _toggleLocationSharing(),
                                          activeColor: AppColors.primary,
                                          activeTrackColor: AppColors.primary
                                              .withOpacity(0.3),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isSharingLocation
                                        ? Colors.green.withOpacity(0.1)
                                        : Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _isSharingLocation
                                          ? Colors.green.withOpacity(0.3)
                                          : Colors.grey.withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _isSharingLocation
                                            ? Icons.location_on
                                            : Icons.location_off,
                                        size: 16,
                                        color: _isSharingLocation
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Location Sharing: ${_isSharingLocation ? 'ON' : 'OFF'}',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: _isSharingLocation
                                                  ? Colors.green
                                                  : Colors.grey,
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // Distance to Start
                    if (_distanceToStart != null &&
                        _distanceToStart! > 1000) // Show if more than 1km away
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Icon(
                                      Icons.directions,
                                      color: _routeToMeetingPoint != null
                                          ? Colors.purple
                                          : Colors.blue,
                                      size: 24,
                                    ),
                                    Text(
                                      _routeToMeetingPoint != null
                                          ? 'Route to Meeting Point'
                                          : 'Route to Start Point',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'You are ${_distanceToStart!.round()}m from the start point.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Estimated time to start: $_etaToStart',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                                ),
                                SizedBox(height: 8),
                                Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color:
                                        (_routeToMeetingPoint != null
                                                ? Colors.purple
                                                : Colors.blue)
                                            .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          (_routeToMeetingPoint != null
                                                  ? Colors.purple
                                                  : Colors.blue)
                                              .withOpacity(0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: _routeToMeetingPoint != null
                                            ? Colors.purple
                                            : Colors.blue,
                                        size: 16,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _routeToMeetingPoint != null
                                              ? 'The purple line shows the route to the meeting point.'
                                              : 'The blue line shows the route from your current location to the trip start point.',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color:
                                                    _routeToMeetingPoint != null
                                                    ? Colors.purple[700]
                                                    : Colors.blue[700],
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Compass Calibration Guidance
                    if (_compassNeedsCalibration)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Card(
                          color: Colors.orange.shade50,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.compass_calibration,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Compass Calibration Needed',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.orange[800],
                                            ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Move your device in a figure-8 pattern to calibrate the compass',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: Colors.orange[700],
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _compassNeedsCalibration = false;
                                    });
                                  },
                                  icon: Icon(Icons.close, color: Colors.orange),
                                  tooltip: 'Dismiss',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_compassNeedsCalibration) SizedBox(height: 8),

                    // Map
                    Expanded(
                      child: Consumer2<LiveGroupTracking, TripProvider>(
                        builder: (context, tracking, tripProvider, child) {
                          _buildMarkers();

                          // Reload route if trip data changes
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (tripProvider.hasActiveTrip &&
                                _routePolylines.isEmpty) {
                              _loadTripRoute();
                            }
                          });

                          return Stack(
                            children: [
                              FlutterMap(
                                mapController: _mapController,
                                options: MapOptions(
                                  initialCenter:
                                      _currentLocation ??
                                      LatLng(20.5937, 78.9629),
                                  initialZoom: _currentLocation != null
                                      ? 15
                                      : 5,
                                  // Remove empty callback that might interfere with zoom
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                    userAgentPackageName:
                                        'com.example.rider_buddies', // Rider Buddies app
                                  ),
                                  MarkerLayer(markers: _markers),
                                  // Single polyline layer with all routes
                                  PolylineLayer(
                                    polylines: _buildAllPolylines(),
                                  ),
                                ],
                              ),
                              // Compass indicator in top-right corner
                              if (_currentHeading != null)
                                Positioned(
                                  top: 16,
                                  right: 16,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.primary,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Transform.rotate(
                                      angle: (_currentHeading! * 3.14159) / 180,
                                      child: Icon(
                                        Icons.navigation,
                                        color: AppColors.primary,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                ),
                              // Compass status indicator
                              Positioned(
                                top: 16,
                                left: 16,
                                child: GestureDetector(
                                  onTap: _compassNeedsCalibration
                                      ? _showCalibrationGuidance
                                      : null,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _compassNeedsCalibration
                                          ? Colors.orange.withOpacity(0.8)
                                          : FlutterCompass.events != null
                                          ? Colors.green.withOpacity(0.8)
                                          : Colors.red.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _compassNeedsCalibration
                                              ? Icons.compass_calibration
                                              : Icons.compass_calibration,
                                          color: Colors.white,
                                          size: 12,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          _compassNeedsCalibration
                                              ? 'Calibrate'
                                              : FlutterCompass.events != null
                                              ? 'Compass'
                                              : 'No Compass',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // Legend
                    Container(
                      padding: EdgeInsets.all(16),
                      child: Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Member legend
                              if (_trackingService
                                      ?.memberLocations
                                      .isNotEmpty ==
                                  true) ...[
                                Text(
                                  'Group Members',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: _trackingService!.memberLocations
                                      .map((member) {
                                        final isCurrentUser =
                                            member.userId ==
                                            Provider.of<AuthProvider>(
                                              context,
                                              listen: false,
                                            ).user?.uid;
                                        final memberColor =
                                            MapMarkers.getMemberColor(
                                              member.userId,
                                            );
                                        final initials = MapMarkers.getInitials(
                                          member.name,
                                        );

                                        return Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isCurrentUser
                                                ? AppColors.primary
                                                : memberColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: isCurrentUser
                                                  ? AppColors.primary
                                                  : memberColor,
                                              width: 1,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 16,
                                                height: 16,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    initials,
                                                    style: TextStyle(
                                                      color: isCurrentUser
                                                          ? AppColors.primary
                                                          : memberColor,
                                                      fontSize: 8,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 4),
                                              Text(
                                                member.name,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              if (isCurrentUser) ...[
                                                SizedBox(width: 4),
                                                Icon(
                                                  Icons.my_location,
                                                  color: Colors.white,
                                                  size: 10,
                                                ),
                                              ],
                                            ],
                                          ),
                                        );
                                      })
                                      .toList(),
                                ),
                                SizedBox(height: 12),
                                Divider(),
                                SizedBox(height: 8),
                              ],
                              // Route legend
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                alignment: WrapAlignment.spaceEvenly,
                                children: [
                                  _buildLegendItem(
                                    Icons.trip_origin,
                                    AppColors.primary,
                                    'Start',
                                  ),
                                  _buildLegendItem(
                                    Icons.flag,
                                    Colors.red,
                                    'End',
                                  ),
                                  _buildLegendItem(
                                    Icons.coffee,
                                    AppColors.warning,
                                    'Break',
                                  ),
                                  _buildLegendItem(
                                    Icons.directions_bike,
                                    Colors.green,
                                    'Riding',
                                  ),
                                  _buildLegendItem(
                                    Icons.check_circle,
                                    AppColors.secondary,
                                    'Arrived',
                                  ),
                                  _buildLegendItem(
                                    Icons.stop,
                                    Colors.red,
                                    'Stopped',
                                  ),
                                  _buildLegendItem(
                                    Icons.route,
                                    AppColors.primary,
                                    'Route',
                                  ),
                                  _buildLegendItem(
                                    Icons.my_location,
                                    AppColors.primary,
                                    'You',
                                  ),
                                  if (_currentHeading != null)
                                    _buildLegendItem(
                                      Icons.navigation,
                                      AppColors.primary,
                                      'Direction',
                                    ),
                                  // Show only the relevant route type
                                  if (_routeToMeetingPoint != null)
                                    _buildLegendItem(
                                      Icons.join_full,
                                      Colors.purple,
                                      'To Meeting',
                                    )
                                  else if (_routeToStart != null ||
                                      _directionsToStartPolylines.isNotEmpty)
                                    _buildLegendItem(
                                      Icons.directions,
                                      Colors.blue,
                                      'To Start',
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAnimatedLoadingScreen(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary.withOpacity(0.1), Colors.white],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated map icon
            TweenAnimationBuilder<double>(
              duration: Duration(seconds: 2),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(Icons.map, size: 60, color: AppColors.primary),
                  ),
                );
              },
            ),
            SizedBox(height: 32),

            // Animated location pin
            TweenAnimationBuilder<double>(
              duration: Duration(milliseconds: 1500),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, -10 * (1 - value)),
                  child: Opacity(
                    opacity: value,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            color: AppColors.primary,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Finding your location...',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: 24),

            // Animated dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (index) {
                return TweenAnimationBuilder<double>(
                  duration: Duration(milliseconds: 600),
                  tween: Tween(begin: 0.0, end: 1.0),
                  builder: (context, value, child) {
                    return Container(
                      margin: EdgeInsets.symmetric(horizontal: 4),
                      child: Transform.scale(
                        scale: 0.5 + (0.5 * value),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(
                              0.3 + (0.7 * value),
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
            SizedBox(height: 32),

            // Cycling friendly messages
            TweenAnimationBuilder<double>(
              duration: Duration(seconds: 3),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Column(
                      children: [
                        Text(
                          'Getting ready for your ride!',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'We\'re setting up your map and connecting with your group',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary.withOpacity(0.1), Colors.white],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated error icon
            TweenAnimationBuilder<double>(
              duration: Duration(milliseconds: 500),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.scale(
                  scale: 0.8 + (0.2 * value),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.error,
                      size: 50,
                      color: AppColors.primary,
                    ),
                  ),
                );
              },
            ),
            SizedBox(height: 24),

            // Error message
            Text(
              _error!,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.red[700],
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),

            // Retry button
            ElevatedButton.icon(
              onPressed: () {
                HapticService.mediumImpact();
                _checkLocationPermission();
              },
              icon: Icon(Icons.refresh),
              label: Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, Color color, String label) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  List<Polyline> _buildAllPolylines() {
    List<Polyline> polylines = [];

    // Main trip route (if available)
    polylines.addAll(_routePolylines);

    // Priority order for additional routes:
    // 1. Mid-journey meeting point route (purple) - highest priority
    // 2. Mid-journey route to start (blue) - medium priority
    // 3. Regular directions to start (blue) - lowest priority

    // Show mid-journey meeting point route if available
    if (_routeToMeetingPoint != null) {
      polylines.add(
        Polyline(
          points: _routeToMeetingPoint!.points,
          color: Colors.purple.withOpacity(0.8),
          strokeWidth: 4,
        ),
      );
    }
    // Show mid-journey route to start if available (and no meeting point route)
    else if (_routeToStart != null) {
      polylines.add(
        Polyline(
          points: _routeToStart!.points,
          color: Colors.blue.withOpacity(0.8),
          strokeWidth: 4,
        ),
      );
    }
    // Show regular directions to start if available (and no mid-journey routes)
    else if (_directionsToStartPolylines.isNotEmpty) {
      polylines.addAll(_directionsToStartPolylines);
    }

    return polylines;
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _trackingService?.cancelSubscription();
    _locationSubscription?.cancel(); // Cancel location stream
    _compassSubscription?.cancel(); // Cancel compass stream
    super.dispose();
  }
}
