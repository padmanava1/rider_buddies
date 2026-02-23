import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import '../../models/group_member_location.dart';
import 'supabase_service.dart';

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
  final SupabaseClient _supabase = SupabaseService.client;

  String? _activeGroupCode;
  List<GroupMemberLocation> _memberLocations = [];
  bool _isTracking = false;
  String? _error;
  RealtimeChannel? _locationChannel;
  StreamSubscription<Position>? _positionStreamSubscription;
  double? _lastSpeed;
  bool _isFirstLocationUpdate = true;
  String? _currentUserId;

  String? get activeGroupCode => _activeGroupCode;
  List<GroupMemberLocation> get memberLocations => _memberLocations;
  bool get isTracking => _isTracking;
  String? get error => _error;

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

  // Start tracking for a group
  Future<void> startTracking(String groupCode) async {
    try {
      _activeGroupCode = groupCode;
      _isTracking = true;
      _error = null;

      await _getCurrentUserId();

      // Defer notifyListeners to avoid setState during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });

      // Initial fetch of online members
      await _fetchOnlineMembers();

      // Subscribe to real-time updates using Supabase Realtime
      _locationChannel = _supabase
          .channel('member_locations:$groupCode')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'member_locations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'group_code',
              value: groupCode,
            ),
            callback: (payload) {
              _handleLocationChange(payload);
            },
          )
          .subscribe();

      debugPrint('Started tracking for group: $groupCode');
    } catch (e) {
      _error = 'Failed to start tracking';
      debugPrint('Error starting tracking: $e');
      notifyListeners();
    }
  }

  Future<void> _fetchOnlineMembers() async {
    try {
      final response = await _supabase
          .from('member_locations')
          .select()
          .eq('group_code', _activeGroupCode!)
          .eq('is_online', true);

      _memberLocations = (response as List)
          .map((data) => GroupMemberLocation.fromSupabaseMap(data))
          .toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching online members: $e');
    }
  }

  void _handleLocationChange(PostgresChangePayload payload) {
    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final newData = payload.newRecord;
          if (newData['is_online'] == true) {
            final location = GroupMemberLocation.fromSupabaseMap(newData);
            final index = _memberLocations.indexWhere(
              (m) => m.userId == location.userId,
            );
            if (index >= 0) {
              _memberLocations[index] = location;
            } else {
              _memberLocations.add(location);
            }
          } else {
            // Member went offline, remove from list
            _memberLocations.removeWhere(
              (m) => m.userId == newData['user_id'],
            );
          }
          break;
        case PostgresChangeEvent.delete:
          final oldData = payload.oldRecord;
          _memberLocations.removeWhere(
            (m) => m.userId == oldData['user_id'],
          );
          break;
        default:
          break;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error handling location change: $e');
    }
  }

  // Stop tracking
  void stopTracking() {
    _locationChannel?.unsubscribe();
    _locationChannel = null;
    _isTracking = false;
    _activeGroupCode = null;
    _memberLocations = [];

    try {
      notifyListeners();
    } catch (e) {
      debugPrint('Ignoring notifyListeners error during disposal: $e');
    }
  }

  // Cancel subscription only (for safe disposal)
  void cancelSubscription() {
    _locationChannel?.unsubscribe();
    _locationChannel = null;
  }

  // Update current user's location using delta updates
  Future<void> updateMyLocation(LatLng coordinates, {String? status}) async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null || _activeGroupCode == null) return;

      final now = DateTime.now().toIso8601String();

      if (!_isFirstLocationUpdate) {
        // Delta update: only send coordinates, timestamp, and status
        await _supabase
            .from('member_locations')
            .update({
              'latitude': coordinates.latitude,
              'longitude': coordinates.longitude,
              'last_updated': now,
              'is_online': true,
              'status': status ?? 'riding',
            })
            .eq('group_code', _activeGroupCode!)
            .eq('user_id', userId);

        debugPrint('Delta update: sent only location changes');
      } else {
        // First update: send full document with upsert
        final userProfile = await _supabase
            .from('users')
            .select('name, profile_image_url, email')
            .eq('id', userId)
            .maybeSingle();

        await _supabase.from('member_locations').upsert({
          'group_code': _activeGroupCode,
          'user_id': userId,
          'name': userProfile?['name'] ?? 'Unknown User',
          'profile_image': userProfile?['profile_image_url'],
          'email': userProfile?['email'],
          'latitude': coordinates.latitude,
          'longitude': coordinates.longitude,
          'is_online': true,
          'status': status ?? 'riding',
          'last_updated': now,
        }, onConflict: 'group_code,user_id');

        _isFirstLocationUpdate = false;
        debugPrint('Full update: created/updated complete document');
      }
    } catch (e) {
      // If update fails, try full upsert
      if (e.toString().contains('not found') || e.toString().contains('0 rows')) {
        _isFirstLocationUpdate = true;
        await updateMyLocation(coordinates, status: status);
      } else {
        debugPrint('Error updating my location: $e');
      }
    }
  }

  /// Get adaptive location settings based on current speed
  LocationSettings _getAdaptiveLocationSettings(double? currentSpeed) {
    if (currentSpeed == null || currentSpeed < 1.4) {
      debugPrint('Location mode: LOW_POWER (speed: ${currentSpeed?.toStringAsFixed(1) ?? "unknown"} m/s)');
      return LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 50,
      );
    } else if (currentSpeed < 4.2) {
      debugPrint('Location mode: BALANCED (speed: ${currentSpeed.toStringAsFixed(1)} m/s)');
      return LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      );
    } else {
      debugPrint('Location mode: HIGH_ACCURACY (speed: ${currentSpeed.toStringAsFixed(1)} m/s)');
      return LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      );
    }
  }

  // Start location sharing for current user with adaptive settings
  Future<void> startLocationSharing() async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null || _activeGroupCode == null) return;

      await _positionStreamSubscription?.cancel();
      _isFirstLocationUpdate = true;

      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: _getAdaptiveLocationSettings(_lastSpeed),
      ).listen(
        (Position position) async {
          _lastSpeed = position.speed;
          await updateMyLocation(
            LatLng(position.latitude, position.longitude),
            status: 'riding',
          );
        },
        onError: (e) {
          debugPrint('Error in location stream: $e');
        },
      );

      debugPrint('Location sharing started with adaptive settings');
    } catch (e) {
      debugPrint('Error starting location sharing: $e');
    }
  }

  // Stop location sharing for current user
  Future<void> stopLocationSharing() async {
    try {
      await _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      _isFirstLocationUpdate = true;
      _lastSpeed = null;

      final userId = await _getCurrentUserId();
      if (userId == null || _activeGroupCode == null) return;

      // Update isOnline to false
      await _supabase
          .from('member_locations')
          .update({
            'is_online': false,
            'last_updated': DateTime.now().toIso8601String(),
          })
          .eq('group_code', _activeGroupCode!)
          .eq('user_id', userId);

      debugPrint('Location sharing stopped, set offline status');
    } catch (e) {
      // If update fails, try to delete the document
      try {
        final userId = _currentUserId;
        if (userId != null && _activeGroupCode != null) {
          await _supabase
              .from('member_locations')
              .delete()
              .eq('group_code', _activeGroupCode!)
              .eq('user_id', userId);
        }
      } catch (_) {}
      debugPrint('Error stopping location sharing: $e');
    }
  }

  // Update user status (at break, arrived, etc.)
  Future<void> updateMyStatus(String status) async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null || _activeGroupCode == null) return;

      final currentLocation = _memberLocations.firstWhere(
        (member) => member.userId == userId,
        orElse: () => GroupMemberLocation(
          userId: userId,
          name: 'Unknown User',
          coordinates: LatLng(0, 0),
          lastUpdated: DateTime.now(),
        ),
      );

      await updateMyLocation(currentLocation.coordinates, status: status);
    } catch (e) {
      debugPrint('Error updating status: $e');
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
    if (_currentUserId == null) return null;
    return getMemberById(_currentUserId!);
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
    try {
      notifyListeners();
    } catch (e) {
      debugPrint('Ignoring notifyListeners error during disposal: $e');
    }
  }

  @override
  void dispose() {
    _locationChannel?.unsubscribe();
    _locationChannel = null;
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    super.dispose();
  }
}
