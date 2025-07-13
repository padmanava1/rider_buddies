import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../widgets/location_permission_dialog.dart';
import '../theme/app_colors.dart';

class LocationPermissionManager {
  static bool _hasCheckedPermission = false;
  static bool _hasPermission = false;

  // Check if location permission is granted
  static bool get hasPermission => _hasPermission;

  // Initialize permission checking
  static Future<void> initialize() async {
    if (!_hasCheckedPermission) {
      await _checkPermissionStatus();
      _hasCheckedPermission = true;
    }
  }

  // Check current permission status
  static Future<bool> _checkPermissionStatus() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        _hasPermission = false;
        return false;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('Current location permission: $permission');

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        _hasPermission = true;
        return true;
      }

      _hasPermission = false;
      return false;
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      _hasPermission = false;
      return false;
    }
  }

  // Request location permission with automatic dialog
  static Future<bool> requestPermission(
    BuildContext context, {
    String title = 'Location Access Required',
    String message =
        'This app needs location access to provide you with the best experience.',
    bool showDialog = true,
  }) async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        if (showDialog) {
          _showLocationServiceDialog(context);
        }
        return false;
      }

      // Check current permission status
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('Current permission before request: $permission');

      if (permission == LocationPermission.denied) {
        // Request permission
        debugPrint('Requesting location permission...');
        permission = await Geolocator.requestPermission();
        debugPrint('Permission after request: $permission');
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission permanently denied');
        if (showDialog) {
          _showSettingsDialog(context);
        }
        _hasPermission = false;
        return false;
      }

      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        debugPrint('Location permission granted');
        _hasPermission = true;
        return true;
      }

      debugPrint('Location permission denied');
      _hasPermission = false;
      return false;
    } on PlatformException catch (e) {
      debugPrint('Platform exception requesting location permission: $e');
      _hasPermission = false;
      return false;
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      _hasPermission = false;
      return false;
    }
  }

  // Request permission with custom dialog
  static Future<bool> requestPermissionWithDialog(
    BuildContext context, {
    String title = 'Location Access Required',
    String message =
        'This app needs location access to provide you with the best experience.',
  }) async {
    return await showLocationPermissionDialog(
      context,
      title: title,
      message: message,
      onGranted: () async {
        final granted = await requestPermission(context, showDialog: false);
        if (granted) {
          _hasPermission = true;
        }
      },
    );
  }

  // Check and request permission automatically
  static Future<bool> ensurePermission(
    BuildContext context, {
    String title = 'Location Access Required',
    String message =
        'This app needs location access to provide you with the best experience.',
  }) async {
    // First check current status
    await _checkPermissionStatus();

    if (_hasPermission) {
      debugPrint('Location permission already granted');
      return true;
    }

    debugPrint('Location permission not granted, requesting...');
    // If no permission, request it
    return await requestPermissionWithDialog(
      context,
      title: title,
      message: message,
    );
  }

  // Test location access
  static Future<bool> testLocationAccess() async {
    try {
      debugPrint('Testing location access...');
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );
      debugPrint(
        'Location access successful: ${position.latitude}, ${position.longitude}',
      );
      return true;
    } catch (e) {
      debugPrint('Location access failed: $e');
      return false;
    }
  }

  // Show location service disabled dialog
  static void _showLocationServiceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Location Services Disabled'),
        content: Text(
          'Please enable location services in your device settings to use this feature.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Geolocator.openLocationSettings();
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Show settings dialog for permanently denied permissions
  static void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Location Permission Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location access is needed for this feature. Please enable location permission in your device settings.',
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How to enable location:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('1. Go to Settings > Apps > Rider Buddies'),
                  Text('2. Tap Permissions > Location'),
                  Text('3. Select "Allow while using app"'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await Geolocator.openAppSettings();
                Navigator.pop(context);
              } on PlatformException catch (e) {
                debugPrint('Cannot open settings: $e');
                Navigator.pop(context);
                _showManualSettingsInstructions(context);
              } catch (e) {
                debugPrint('Error opening settings: $e');
                Navigator.pop(context);
                _showManualSettingsInstructions(context);
              }
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // Show manual settings instructions
  static void _showManualSettingsInstructions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Manual Settings Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please manually enable location permissions:'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Steps:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('1. Open your device Settings'),
                  Text('2. Find "Apps" or "Application Manager"'),
                  Text('3. Find "Rider Buddies" in the list'),
                  Text('4. Tap "Permissions"'),
                  Text('5. Enable "Location" permission'),
                  Text('6. Return to the app'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('I Understand'),
          ),
        ],
      ),
    );
  }

  // Reset permission status (useful for testing)
  static void resetPermissionStatus() {
    _hasCheckedPermission = false;
    _hasPermission = false;
  }

  // Get permission status description
  static String getPermissionStatusDescription() {
    if (_hasPermission) {
      return 'Location permission granted';
    } else if (_hasCheckedPermission) {
      return 'Location permission denied';
    } else {
      return 'Location permission not checked';
    }
  }
}
