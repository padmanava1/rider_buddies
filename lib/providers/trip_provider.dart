import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';

class TripPoint {
  final String id;
  final String name;
  final String address;
  final LatLng coordinates;
  final String type; // 'start', 'end', 'break'
  final DateTime? scheduledTime;
  final String? notes;

  TripPoint({
    required this.id,
    required this.name,
    required this.address,
    required this.coordinates,
    required this.type,
    this.scheduledTime,
    this.notes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': coordinates.latitude,
      'longitude': coordinates.longitude,
      'type': type,
      'scheduledTime': scheduledTime?.toIso8601String(),
      'notes': notes,
    };
  }

  factory TripPoint.fromMap(Map<String, dynamic> map) {
    return TripPoint(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      coordinates: LatLng(
        (map['latitude'] as num?)?.toDouble() ?? 0.0,
        (map['longitude'] as num?)?.toDouble() ?? 0.0,
      ),
      type: map['type']?.toString() ?? 'unknown',
      scheduledTime: map['scheduledTime'] != null
          ? DateTime.tryParse(map['scheduledTime'].toString())
          : null,
      notes: map['notes']?.toString(),
    );
  }
}

class TripRoute {
  final String id;
  final String name;
  final List<LatLng> waypoints;
  final double distance; // in meters
  final int duration; // in seconds
  final String polyline;

  TripRoute({
    required this.id,
    required this.name,
    required this.waypoints,
    required this.distance,
    required this.duration,
    required this.polyline,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'waypoints': waypoints
          .map((wp) => {'latitude': wp.latitude, 'longitude': wp.longitude})
          .toList(),
      'distance': distance,
      'duration': duration,
      'polyline': polyline,
    };
  }

  factory TripRoute.fromMap(Map<String, dynamic> map) {
    final waypointsList = map['waypoints'] as List? ?? [];
    final waypoints = waypointsList
        .map((wp) {
          if (wp is Map<String, dynamic>) {
            return LatLng(
              (wp['latitude'] as num?)?.toDouble() ?? 0.0,
              (wp['longitude'] as num?)?.toDouble() ?? 0.0,
            );
          }
          return null;
        })
        .where((wp) => wp != null)
        .cast<LatLng>()
        .toList();

    return TripRoute(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      waypoints: waypoints,
      distance: (map['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      polyline: map['polyline']?.toString() ?? '',
    );
  }
}

class TripProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _activeTripId;
  Map<String, dynamic>? _tripData;
  List<TripPoint> _tripPoints = [];
  TripRoute? _selectedRoute;
  bool _isLoading = false;
  String? _error;
  bool _isLeader = false;

  String? get activeTripId => _activeTripId;
  Map<String, dynamic>? get tripData => _tripData;
  List<TripPoint> get tripPoints => _tripPoints;
  TripRoute? get selectedRoute => _selectedRoute;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLeader => _isLeader;
  bool get hasActiveTrip => _activeTripId != null;

  TripPoint? get startPoint =>
      _tripPoints.where((p) => p.type == 'start').firstOrNull;
  TripPoint? get endPoint =>
      _tripPoints.where((p) => p.type == 'end').firstOrNull;
  List<TripPoint> get breakPoints =>
      _tripPoints.where((p) => p.type == 'break').toList();

  // Load trip data for current group
  Future<void> loadTripData(String groupCode) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final user = _auth.currentUser;
      if (user == null) return;

      // Check if user is leader
      final groupDoc = await _firestore
          .collection('groups')
          .doc(groupCode)
          .get();
      if (groupDoc.exists) {
        final groupData = groupDoc.data();
        if (groupData != null) {
          _isLeader = groupData['leader'] == user.uid;
        }
      }

      // Load trip data
      final tripDoc = await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('trip')
          .doc('current')
          .get();

      if (tripDoc.exists) {
        final tripData = tripDoc.data();
        if (tripData != null) {
          _tripData = tripData as Map<String, dynamic>;
          _activeTripId = tripDoc.id;

          // Load trip points
          final pointsData = _tripData!['points'] as List<dynamic>? ?? [];
          _tripPoints = pointsData
              .map((p) {
                if (p is Map<String, dynamic>) {
                  return TripPoint.fromMap(p);
                } else {
                  debugPrint('Invalid point data: $p');
                  return null;
                }
              })
              .where((p) => p != null)
              .cast<TripPoint>()
              .toList();

          // Load selected route
          final selectedRouteData = _tripData!['selectedRoute'];
          if (selectedRouteData != null &&
              selectedRouteData is Map<String, dynamic>) {
            try {
              _selectedRoute = TripRoute.fromMap(selectedRouteData);
            } catch (e) {
              debugPrint('Error parsing selected route: $e');
              _selectedRoute = null;
            }
          } else {
            _selectedRoute = null;
          }
        } else {
          debugPrint('Trip document exists but data is null');
          _tripData = null;
          _activeTripId = null;
          _tripPoints = [];
          _selectedRoute = null;
        }
      } else {
        // No trip document exists
        _tripData = null;
        _activeTripId = null;
        _tripPoints = [];
        _selectedRoute = null;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load trip data';
      _isLoading = false;
      debugPrint('Error loading trip data: $e');
      notifyListeners();
    }
  }

  // Create new trip
  Future<bool> createTrip(String groupCode) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final user = _auth.currentUser;
      if (user == null) {
        _error = 'User not authenticated';
        return false;
      }

      final tripData = {
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
        'status': 'planning', // planning, active, completed, cancelled
        'points': [],
        'routes': [],
        'selectedRoute': null,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('trip')
          .doc('current')
          .set(tripData);

      _activeTripId = 'current';
      _tripData = tripData;
      _tripPoints = [];
      _selectedRoute = null;
      _isLoading = false;
      notifyListeners();

      // Only notify group members if user is a leader
      if (_isLeader) {
        await _notifyGroupMembers(groupCode, 'trip_created', {
          'message': 'Trip planning started',
          'createdBy': user.uid,
        });
      }

      return true;
    } catch (e) {
      _error = 'Failed to create trip';
      _isLoading = false;
      debugPrint('Error creating trip: $e');
      notifyListeners();
      return false;
    }
  }

  // Add trip point
  Future<bool> addTripPoint(String groupCode, TripPoint point) async {
    try {
      _tripPoints.add(point);

      final pointsData = _tripPoints.map((p) => p.toMap()).toList();

      await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('trip')
          .doc('current')
          .update({
            'points': pointsData,
            'lastUpdated': FieldValue.serverTimestamp(),
          });

      notifyListeners();

      // Only notify group members if user is a leader
      if (_isLeader) {
        await _notifyGroupMembers(groupCode, 'point_added', {
          'point': point.toMap(),
          'message': '${point.type} point added: ${point.name}',
        });
      }

      return true;
    } catch (e) {
      _error = 'Failed to add trip point';
      debugPrint('Error adding trip point: $e');
      notifyListeners();
      return false;
    }
  }

  // Remove trip point
  Future<bool> removeTripPoint(String groupCode, String pointId) async {
    try {
      final point = _tripPoints.firstWhere((p) => p.id == pointId);
      _tripPoints.removeWhere((p) => p.id == pointId);

      final pointsData = _tripPoints.map((p) => p.toMap()).toList();

      await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('trip')
          .doc('current')
          .update({
            'points': pointsData,
            'lastUpdated': FieldValue.serverTimestamp(),
          });

      notifyListeners();

      // Only notify group members if user is a leader
      if (_isLeader) {
        await _notifyGroupMembers(groupCode, 'point_removed', {
          'pointId': pointId,
          'message': '${point.type} point removed: ${point.name}',
        });
      }

      return true;
    } catch (e) {
      _error = 'Failed to remove trip point';
      debugPrint('Error removing trip point: $e');
      notifyListeners();
      return false;
    }
  }

  // Add break point
  Future<bool> addBreakPoint(String groupCode, TripPoint breakPoint) async {
    try {
      // Ensure break point has correct type
      final point = TripPoint(
        id: breakPoint.id,
        name: breakPoint.name,
        address: breakPoint.address,
        coordinates: breakPoint.coordinates,
        type: 'break',
        scheduledTime: breakPoint.scheduledTime,
        notes: breakPoint.notes,
      );

      return await addTripPoint(groupCode, point);
    } catch (e) {
      _error = 'Failed to add break point';
      debugPrint('Error adding break point: $e');
      notifyListeners();
      return false;
    }
  }

  // Set selected route
  Future<bool> setSelectedRoute(String groupCode, TripRoute route) async {
    try {
      _selectedRoute = route;

      await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('trip')
          .doc('current')
          .update({
            'selectedRoute': route.toMap(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });

      notifyListeners();

      // Only notify group members if user is a leader
      if (_isLeader) {
        await _notifyGroupMembers(groupCode, 'route_selected', {
          'route': route.toMap(),
          'message': 'Route selected: ${route.name}',
        });
      }

      return true;
    } catch (e) {
      _error = 'Failed to set selected route';
      debugPrint('Error setting selected route: $e');
      notifyListeners();
      return false;
    }
  }

  // Start trip
  Future<bool> startTrip(String groupCode) async {
    try {
      if (startPoint == null || endPoint == null) {
        _error = 'Start and end points are required';
        notifyListeners();
        return false;
      }

      await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('trip')
          .doc('current')
          .update({
            'status': 'active',
            'startedAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });

      _tripData?['status'] = 'active';
      notifyListeners();

      // Only notify group members if user is a leader
      if (_isLeader) {
        await _notifyGroupMembers(groupCode, 'trip_started', {
          'message': 'Trip has started!',
          'startPoint': startPoint!.toMap(),
          'endPoint': endPoint!.toMap(),
        });
      }

      return true;
    } catch (e) {
      _error = 'Failed to start trip';
      debugPrint('Error starting trip: $e');
      notifyListeners();
      return false;
    }
  }

  // Complete trip
  Future<bool> completeTrip(String groupCode) async {
    try {
      await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('trip')
          .doc('current')
          .update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });

      _tripData?['status'] = 'completed';
      notifyListeners();

      // Only notify group members if user is a leader
      if (_isLeader) {
        await _notifyGroupMembers(groupCode, 'trip_completed', {
          'message': 'Trip completed!',
        });
      }

      return true;
    } catch (e) {
      _error = 'Failed to complete trip';
      debugPrint('Error completing trip: $e');
      notifyListeners();
      return false;
    }
  }

  // Cancel trip
  Future<bool> cancelTrip(String groupCode) async {
    try {
      await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('trip')
          .doc('current')
          .update({
            'status': 'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
            'lastUpdated': FieldValue.serverTimestamp(),
          });

      _tripData?['status'] = 'cancelled';
      notifyListeners();

      // Only notify group members if user is a leader
      if (_isLeader) {
        await _notifyGroupMembers(groupCode, 'trip_cancelled', {
          'message': 'Trip cancelled',
        });
      }

      return true;
    } catch (e) {
      _error = 'Failed to cancel trip';
      debugPrint('Error cancelling trip: $e');
      notifyListeners();
      return false;
    }
  }

  // Notify group members
  Future<void> _notifyGroupMembers(
    String groupCode,
    String type,
    Map<String, dynamic> data,
  ) async {
    try {
      final notification = {
        'type': type,
        'data': data,
        'timestamp': FieldValue.serverTimestamp(),
        'createdBy': _auth.currentUser?.uid,
      };

      await _firestore
          .collection('groups')
          .doc(groupCode)
          .collection('notifications')
          .add(notification);
    } catch (e) {
      debugPrint('Error notifying group members: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearTrip() {
    _activeTripId = null;
    _tripData = null;
    _tripPoints = [];
    _selectedRoute = null;
    _isLeader = false;
    notifyListeners();
  }
}
