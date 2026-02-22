import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../../models/group_member_location.dart';

/// Location accuracy mode for battery optimization
enum LocationMode {
  /// High accuracy for active ride tracking
  highAccuracy,
  /// Balanced mode for normal use
  balanced,
  /// Low power mode for stationary/slow movement
  lowPower,
}

class LiveGroupTracking extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _activeGroupCode;
  List<GroupMemberLocation> _memberLocations = [];
  bool _isTracking = false;
  String? _error;
  StreamSubscription<QuerySnapshot>? _locationSubscription;
  StreamSubscription<Position>? _positionStreamSubscription; // Fix: store position stream
  double? _lastSpeed; // Track speed for adaptive settings
  bool _isFirstLocationUpdate = true; // Track if this is the first update

  String? get activeGroupCode => _activeGroupCode;
  List<GroupMemberLocation> get memberLocations => _memberLocations;
  bool get isTracking => _isTracking;
  String? get error => _error;

  // Start tracking for a group
  Future<void> startTracking(String groupCode) async {
    try {
      _activeGroupCode = groupCode;
      _isTracking = true;
      _error = null;

      // Defer notifyListeners to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });

      // Listen to member locations with server-side filtering
      // Only fetch online members to reduce data transfer
      _locationSubscription = _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('memberLocations')
          .where('isOnline', isEqualTo: true) // Query-level filtering
          .snapshots()
          .listen(
            (snapshot) {
              _memberLocations = snapshot.docs
                  .map(
                    (doc) => GroupMemberLocation.fromMap({
                      'userId': doc.id,
                      ...doc.data(),
                    }),
                  )
                  .toList(); // No need for client-side filter anymore
              notifyListeners();
            },
            onError: (error) {
              _error = 'Failed to track member locations';
              print('Error tracking member locations: $error');
              notifyListeners();
            },
          );
    } catch (e) {
      _error = 'Failed to start tracking';
      print('Error starting tracking: $e');
      notifyListeners();
    }
  }

  // Stop tracking
  void stopTracking() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _isTracking = false;
    _activeGroupCode = null;
    _memberLocations = [];

    // Safely call notifyListeners, ignore if widget tree is locked
    try {
      notifyListeners();
    } catch (e) {
      // Ignore errors during disposal
      print('Ignoring notifyListeners error during disposal: $e');
    }
  }

  // Cancel subscription only (for safe disposal)
  void cancelSubscription() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
  }

  // Update current user's location using delta updates
  Future<void> updateMyLocation(LatLng coordinates, {String? status}) async {
    try {
      final user = _auth.currentUser;
      if (user == null || _activeGroupCode == null) return;

      final docRef = _firestore
          .collection('groups')
          .doc(_activeGroupCode)
          .collection('memberLocations')
          .doc(user.uid);

      // Use delta update for subsequent updates (only send changed fields)
      if (!_isFirstLocationUpdate) {
        // Delta update: only send coordinates, timestamp, and status
        await docRef.update({
          'coordinates': {
            'latitude': coordinates.latitude,
            'longitude': coordinates.longitude,
          },
          'lastUpdated': FieldValue.serverTimestamp(),
          'isOnline': true,
          'status': status ?? 'riding',
        });
        debugPrint('Delta update: sent only location changes');
      } else {
        // First update: send full document with merge to create if doesn't exist
        final userDoc = await _firestore.collection('users').doc(user.uid).get();
        final userData = userDoc.data();
        final userName = userData?['name'] ?? 'Unknown User';
        final profileImage = userData?['profileImage'];

        final memberLocation = GroupMemberLocation(
          userId: user.uid,
          name: userName,
          profileImage: profileImage,
          email: user.email,
          coordinates: coordinates,
          lastUpdated: DateTime.now(),
          isOnline: true,
          status: status,
        );

        await docRef.set(memberLocation.toMap(), SetOptions(merge: true));
        _isFirstLocationUpdate = false;
        debugPrint('Full update: created/updated complete document');
      }
    } catch (e) {
      // If update fails (doc doesn't exist), fall back to set with merge
      if (e.toString().contains('NOT_FOUND') || e.toString().contains('not-found')) {
        _isFirstLocationUpdate = true;
        await updateMyLocation(coordinates, status: status);
      } else {
        print('Error updating my location: $e');
      }
    }
  }

  /// Get adaptive location settings based on current speed
  /// This optimizes battery usage by reducing update frequency when stationary
  LocationSettings _getAdaptiveLocationSettings(double? currentSpeed) {
    // Speed is in m/s, convert thresholds:
    // < 1.4 m/s = < 5 km/h (stationary/walking)
    // < 4.2 m/s = < 15 km/h (slow cycling)
    // >= 4.2 m/s = >= 15 km/h (fast cycling/driving)

    if (currentSpeed == null || currentSpeed < 1.4) {
      // Stationary or very slow: use low power mode
      debugPrint('Location mode: LOW_POWER (speed: ${currentSpeed?.toStringAsFixed(1) ?? "unknown"} m/s)');
      return LocationSettings(
        accuracy: LocationAccuracy.medium, // Reduced accuracy
        distanceFilter: 50, // Update every 50m
      );
    } else if (currentSpeed < 4.2) {
      // Walking/slow cycling: balanced mode
      debugPrint('Location mode: BALANCED (speed: ${currentSpeed.toStringAsFixed(1)} m/s)');
      return LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20, // Update every 20m
      );
    } else {
      // Fast cycling/driving: high accuracy mode
      debugPrint('Location mode: HIGH_ACCURACY (speed: ${currentSpeed.toStringAsFixed(1)} m/s)');
      return LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10m
      );
    }
  }

  // Start location sharing for current user with adaptive settings
  Future<void> startLocationSharing() async {
    try {
      final user = _auth.currentUser;
      if (user == null || _activeGroupCode == null) return;

      // Cancel any existing subscription first
      await _positionStreamSubscription?.cancel();
      _isFirstLocationUpdate = true; // Reset for new session

      // Start with balanced settings, will adapt based on speed
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: _getAdaptiveLocationSettings(_lastSpeed),
      ).listen(
        (Position position) async {
          // Update speed for next adaptive calculation
          _lastSpeed = position.speed;

          await updateMyLocation(
            LatLng(position.latitude, position.longitude),
            status: 'riding',
          );
        },
        onError: (e) {
          print('Error in location stream: $e');
        },
      );

      debugPrint('Location sharing started with adaptive settings');
    } catch (e) {
      print('Error starting location sharing: $e');
    }
  }

  // Stop location sharing for current user
  Future<void> stopLocationSharing() async {
    try {
      // Cancel the position stream subscription (fix for memory leak)
      await _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      _isFirstLocationUpdate = true; // Reset for next session
      _lastSpeed = null;

      final user = _auth.currentUser;
      if (user == null || _activeGroupCode == null) return;

      // Update isOnline to false instead of deleting (allows query filtering to work)
      await _firestore
          .collection('groups')
          .doc(_activeGroupCode)
          .collection('memberLocations')
          .doc(user.uid)
          .update({
            'isOnline': false,
            'lastUpdated': FieldValue.serverTimestamp(),
          });

      debugPrint('Location sharing stopped, set offline status');
    } catch (e) {
      // If update fails, try to delete the document
      try {
        final user = _auth.currentUser;
        if (user != null && _activeGroupCode != null) {
          await _firestore
              .collection('groups')
              .doc(_activeGroupCode)
              .collection('memberLocations')
              .doc(user.uid)
              .delete();
        }
      } catch (_) {}
      print('Error stopping location sharing: $e');
    }
  }

  // Update user status (at break, arrived, etc.)
  Future<void> updateMyStatus(String status) async {
    try {
      final user = _auth.currentUser;
      if (user == null || _activeGroupCode == null) return;

      // Get current location if available
      final currentLocation = _memberLocations.firstWhere(
        (member) => member.userId == user.uid,
        orElse: () => GroupMemberLocation(
          userId: user.uid,
          name: 'Unknown User',
          coordinates: LatLng(0, 0),
          lastUpdated: DateTime.now(),
        ),
      );

      await updateMyLocation(currentLocation.coordinates, status: status);
    } catch (e) {
      print('Error updating status: $e');
    }
  }

  // Get member by ID
  GroupMemberLocation? getMemberById(String userId) {
    try {
      return _memberLocations.firstWhere((member) => member.userId == userId);
    } catch (e) {
      return null;
    }
  }

  // Get current user's location
  GroupMemberLocation? getMyLocation() {
    final user = _auth.currentUser;
    if (user == null) return null;
    return getMemberById(user.uid);
  }

  // Check if member is online (location updated in last 5 minutes)
  bool isMemberOnline(GroupMemberLocation member) {
    final now = DateTime.now();
    final timeDifference = now.difference(member.lastUpdated);
    return timeDifference.inMinutes < 5;
  }

  // Get online members
  List<GroupMemberLocation> get onlineMembers {
    return _memberLocations.where((member) => isMemberOnline(member)).toList();
  }

  void clearError() {
    _error = null;
    // Safely call notifyListeners, ignore if widget tree is locked
    try {
      notifyListeners();
    } catch (e) {
      // Ignore errors during disposal
      print('Ignoring notifyListeners error during disposal: $e');
    }
  }

  @override
  void dispose() {
    // Cancel all subscriptions, don't call stopTracking to avoid notifyListeners
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    super.dispose();
  }
}
