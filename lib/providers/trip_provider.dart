import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:latlong2/latlong.dart';
import '../core/services/supabase_service.dart';

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
      type: map['type']?.toString() ?? map['point_type']?.toString() ?? 'unknown',
      scheduledTime: map['scheduledTime'] != null
          ? DateTime.tryParse(map['scheduledTime'].toString())
          : map['scheduled_time'] != null
              ? DateTime.tryParse(map['scheduled_time'].toString())
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
  final SupabaseClient _supabase = SupabaseService.client;

  String? _activeTripId;
  Map<String, dynamic>? _tripData;
  List<TripPoint> _tripPoints = [];
  TripRoute? _selectedRoute;
  bool _isLoading = false;
  String? _error;
  bool _isLeader = false;
  String? _currentUserId;

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

  Future<String?> _getCurrentUserId() async {
    if (_currentUserId != null) return _currentUserId;

    final authUser = _supabase.auth.currentUser;
    if (authUser == null) return null;

    try {
      final response = await _supabase
          .from('users')
          .select('id')
          .eq('auth_id', authUser.id)
          .maybeSingle();

      if (response != null) {
        _currentUserId = response['id'];
      }
      return _currentUserId;
    } catch (e) {
      debugPrint('Error getting current user ID: $e');
      return null;
    }
  }

  Future<void> loadTripData(String groupCode) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final userId = await _getCurrentUserId();
      if (userId == null) return;

      // Check if user is leader
      final groupResponse = await _supabase
          .from('groups')
          .select('leader_id')
          .eq('code', groupCode)
          .maybeSingle();

      if (groupResponse != null) {
        _isLeader = groupResponse['leader_id'] == userId;
      }

      // Load trip data
      final tripResponse = await _supabase
          .from('trips')
          .select()
          .eq('group_code', groupCode)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (tripResponse != null) {
        _tripData = tripResponse;
        _activeTripId = tripResponse['id'];

        // Load trip points
        final pointsResponse = await _supabase
            .from('trip_points')
            .select()
            .eq('trip_id', _activeTripId!)
            .order('sort_order');

        _tripPoints = (pointsResponse as List)
            .map((p) => TripPoint.fromMap(p))
            .toList();

        // Load selected route
        final routeResponse = await _supabase
            .from('trip_routes')
            .select()
            .eq('trip_id', _activeTripId!)
            .eq('is_selected', true)
            .maybeSingle();

        if (routeResponse != null) {
          _selectedRoute = TripRoute.fromMap(routeResponse);
        } else {
          _selectedRoute = null;
        }
      } else {
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

  Future<bool> createTrip(String groupCode) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final userId = await _getCurrentUserId();
      if (userId == null) {
        _error = 'User not authenticated';
        return false;
      }

      final tripResponse = await _supabase.from('trips').insert({
        'group_code': groupCode,
        'created_by': userId,
        'status': 'planning',
        'created_at': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      }).select().single();

      _activeTripId = tripResponse['id'];
      _tripData = tripResponse;
      _tripPoints = [];
      _selectedRoute = null;
      _isLoading = false;
      notifyListeners();

      if (_isLeader) {
        await _notifyGroupMembers(groupCode, 'trip_created', {
          'message': 'Trip planning started',
          'createdBy': userId,
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

  Future<bool> addTripPoint(String groupCode, TripPoint point) async {
    try {
      if (_activeTripId == null) {
        _error = 'No active trip';
        return false;
      }

      final pointResponse = await _supabase.from('trip_points').insert({
        'trip_id': _activeTripId,
        'name': point.name,
        'address': point.address,
        'latitude': point.coordinates.latitude,
        'longitude': point.coordinates.longitude,
        'point_type': point.type,
        'scheduled_time': point.scheduledTime?.toIso8601String(),
        'notes': point.notes,
        'sort_order': _tripPoints.length,
      }).select().single();

      final newPoint = TripPoint(
        id: pointResponse['id'],
        name: point.name,
        address: point.address,
        coordinates: point.coordinates,
        type: point.type,
        scheduledTime: point.scheduledTime,
        notes: point.notes,
      );

      _tripPoints.add(newPoint);

      await _supabase.from('trips').update({
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('id', _activeTripId!);

      notifyListeners();

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

  Future<bool> removeTripPoint(String groupCode, String pointId) async {
    try {
      final point = _tripPoints.firstWhere((p) => p.id == pointId);

      await _supabase.from('trip_points').delete().eq('id', pointId);

      _tripPoints.removeWhere((p) => p.id == pointId);

      await _supabase.from('trips').update({
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('id', _activeTripId!);

      notifyListeners();

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

  Future<bool> addBreakPoint(String groupCode, TripPoint breakPoint) async {
    try {
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

  Future<bool> setSelectedRoute(String groupCode, TripRoute route) async {
    try {
      if (_activeTripId == null) {
        _error = 'No active trip';
        return false;
      }

      // Deselect all existing routes
      await _supabase
          .from('trip_routes')
          .update({'is_selected': false})
          .eq('trip_id', _activeTripId!);

      // Insert or update the selected route
      await _supabase.from('trip_routes').upsert({
        'trip_id': _activeTripId,
        'name': route.name,
        'polyline': route.polyline,
        'distance': route.distance,
        'duration': route.duration,
        'is_selected': true,
      });

      _selectedRoute = route;

      await _supabase.from('trips').update({
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('id', _activeTripId!);

      notifyListeners();

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

  Future<bool> startTrip(String groupCode) async {
    try {
      if (startPoint == null || endPoint == null) {
        _error = 'Start and end points are required';
        notifyListeners();
        return false;
      }

      if (_activeTripId == null) {
        _error = 'No active trip';
        return false;
      }

      await _supabase.from('trips').update({
        'status': 'active',
        'started_at': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('id', _activeTripId!);

      _tripData?['status'] = 'active';
      notifyListeners();

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

  Future<bool> completeTrip(String groupCode) async {
    try {
      if (_activeTripId == null) {
        _error = 'No active trip';
        return false;
      }

      await _supabase.from('trips').update({
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('id', _activeTripId!);

      _tripData?['status'] = 'completed';
      notifyListeners();

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

  Future<bool> cancelTrip(String groupCode) async {
    try {
      if (_activeTripId == null) {
        _error = 'No active trip';
        return false;
      }

      await _supabase.from('trips').update({
        'status': 'cancelled',
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('id', _activeTripId!);

      _tripData?['status'] = 'cancelled';
      notifyListeners();

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

  Future<void> _notifyGroupMembers(
    String groupCode,
    String type,
    Map<String, dynamic> data,
  ) async {
    try {
      final userId = await _getCurrentUserId();

      await _supabase.from('trip_notifications').insert({
        'group_code': groupCode,
        'notification_type': type,
        'data': data,
        'created_by': userId,
        'created_at': DateTime.now().toIso8601String(),
      });
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
