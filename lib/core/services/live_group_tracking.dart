import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../../models/group_member_location.dart';

class LiveGroupTracking extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _activeGroupCode;
  List<GroupMemberLocation> _memberLocations = [];
  bool _isTracking = false;
  String? _error;
  StreamSubscription<QuerySnapshot>? _locationSubscription;

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

      // Listen to member locations
      _locationSubscription = _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('memberLocations')
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
                  .where((member) => member.isOnline)
                  .toList();
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

  // Update current user's location
  Future<void> updateMyLocation(LatLng coordinates, {String? status}) async {
    try {
      final user = _auth.currentUser;
      if (user == null || _activeGroupCode == null) return;

      // Get user profile
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      final userData = userDoc.data() as Map<String, dynamic>?;
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

      await _firestore
          .collection('groups')
          .doc(_activeGroupCode)
          .collection('memberLocations')
          .doc(user.uid)
          .set(memberLocation.toMap());
    } catch (e) {
      print('Error updating my location: $e');
    }
  }

  // Start location sharing for current user
  Future<void> startLocationSharing() async {
    try {
      final user = _auth.currentUser;
      if (user == null || _activeGroupCode == null) return;

      // Start location tracking
      Geolocator.getPositionStream(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      ).listen((Position position) async {
        await updateMyLocation(
          LatLng(position.latitude, position.longitude),
          status: 'riding',
        );
      });
    } catch (e) {
      print('Error starting location sharing: $e');
    }
  }

  // Stop location sharing for current user
  Future<void> stopLocationSharing() async {
    try {
      final user = _auth.currentUser;
      if (user == null || _activeGroupCode == null) return;

      // Remove user's location from tracking
      await _firestore
          .collection('groups')
          .doc(_activeGroupCode)
          .collection('memberLocations')
          .doc(user.uid)
          .delete();
    } catch (e) {
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
    // Only cancel subscription, don't call stopTracking to avoid notifyListeners
    _locationSubscription?.cancel();
    _locationSubscription = null;
    super.dispose();
  }
}
