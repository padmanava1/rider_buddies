import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'location_permission_manager.dart';

class LocationService extends ChangeNotifier {
  LatLng? _currentLocation;
  bool _isLoading = false;
  String? _error;
  bool _hasPermission = false;

  LatLng? get currentLocation => _currentLocation;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasPermission => _hasPermission;

  // Initialize location service
  Future<void> initialize(BuildContext context) async {
    try {
      // Use the new permission manager
      final hasPermission = await LocationPermissionManager.ensurePermission(
        context,
        title: 'Location Access Required',
        message:
            'We need your location to provide you with the best experience.',
      );

      _hasPermission = hasPermission;
      notifyListeners();

      if (hasPermission) {
        await getCurrentLocation();
      }
    } catch (e) {
      _error = 'Failed to initialize location service';
      notifyListeners();
    }
  }

  // Get current location
  Future<LatLng?> getCurrentLocation() async {
    try {
      if (!_hasPermission) {
        _error = 'Location permission not granted';
        notifyListeners();
        return null;
      }

      _isLoading = true;
      _error = null;
      notifyListeners();

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      _currentLocation = LatLng(position.latitude, position.longitude);
      _isLoading = false;
      notifyListeners();

      return _currentLocation;
    } on PlatformException catch (e) {
      print('Platform exception getting current location: $e');
      _error = 'Location service is unavailable. Please restart the app.';
      _isLoading = false;
      notifyListeners();
      return null;
    } catch (e) {
      _error = 'Failed to get current location';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  // Check if location services are enabled
  Future<bool> isLocationServiceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (e) {
      return false;
    }
  }

  // Get location permission status
  Future<bool> checkLocationPermission() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      return permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
    } catch (e) {
      return false;
    }
  }

  // Request location permission
  Future<bool> requestLocationPermission(BuildContext context) async {
    try {
      final granted = await LocationPermissionManager.ensurePermission(
        context,
        title: 'Location Access Required',
        message:
            'We need your location to provide you with the best experience.',
      );

      _hasPermission = granted;
      notifyListeners();

      if (granted) {
        await getCurrentLocation();
      }

      return granted;
    } catch (e) {
      _error = 'Failed to request location permission';
      notifyListeners();
      return false;
    }
  }

  // Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Reset location service
  void reset() {
    _currentLocation = null;
    _isLoading = false;
    _error = null;
    _hasPermission = false;
    notifyListeners();
  }
}
