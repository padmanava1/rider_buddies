import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';
import '../core/services/supabase_service.dart';

class GroupProvider extends ChangeNotifier {
  final SupabaseClient _supabase = SupabaseService.client;

  String? _activeGroupCode;
  Map<String, dynamic>? _activeGroupData;
  String? _currentUserId;
  bool _isLoading = false;
  String? _error;

  String? get activeGroupCode => _activeGroupCode;
  Map<String, dynamic>? get activeGroupData => _activeGroupData;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasActiveGroup => _activeGroupCode != null;

  GroupProvider() {
    _loadActiveGroup();
  }

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

  Future<void> _loadActiveGroup() async {
    try {
      final userId = await _getCurrentUserId();
      if (userId == null) return;

      // Get user's active group code
      final userResponse = await _supabase
          .from('users')
          .select('active_group_code')
          .eq('id', userId)
          .maybeSingle();

      if (userResponse == null) return;

      final activeGroupCode = userResponse['active_group_code'] as String?;
      if (activeGroupCode == null) {
        _activeGroupCode = null;
        _activeGroupData = null;
        notifyListeners();
        return;
      }

      // Verify group exists and user is a member
      final groupResponse = await _supabase
          .from('groups')
          .select()
          .eq('code', activeGroupCode)
          .maybeSingle();

      if (groupResponse == null) {
        _activeGroupCode = null;
        _activeGroupData = null;
        notifyListeners();
        return;
      }

      // Check if user is a member
      final memberCheck = await _supabase
          .from('group_members')
          .select()
          .eq('group_code', activeGroupCode)
          .eq('user_id', userId)
          .maybeSingle();

      if (memberCheck != null) {
        _activeGroupCode = activeGroupCode;
        _activeGroupData = groupResponse;

        // Load member details
        final members = await _supabase
            .from('group_members')
            .select()
            .eq('group_code', activeGroupCode);

        _activeGroupData!['members'] = members;
        notifyListeners();
      } else {
        _activeGroupCode = null;
        _activeGroupData = null;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading active group: $e');
      _error = 'Failed to load active group';
      notifyListeners();
    }
  }

  Future<bool> createGroup(String mode) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final userId = await _getCurrentUserId();
      if (userId == null) {
        _error = 'User not authenticated';
        return false;
      }

      // Generate group code
      final code = _generateGroupCode();

      // Get user profile
      final userProfile = await _supabase
          .from('users')
          .select('name, email')
          .eq('id', userId)
          .single();

      final userName = userProfile['name'] ?? 'Unknown User';
      final userEmail = userProfile['email'];

      // Create group
      await _supabase.from('groups').insert({
        'code': code,
        'mode': mode,
        'is_active': true,
        'leader_id': userId,
        'created_at': DateTime.now().toIso8601String(),
        'last_updated': DateTime.now().toIso8601String(),
      });

      // Add user as member
      await _supabase.from('group_members').insert({
        'group_code': code,
        'user_id': userId,
        'name': userName,
        'email': userEmail,
        'joined_at': DateTime.now().toIso8601String(),
        'last_seen': DateTime.now().toIso8601String(),
      });

      // Update user's active group
      await _supabase.from('users').update({
        'active_group_code': code,
        'last_active': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      _activeGroupCode = code;
      _activeGroupData = {
        'code': code,
        'mode': mode,
        'is_active': true,
        'leader_id': userId,
      };

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to create group';
      _isLoading = false;
      debugPrint('Error creating group: $e');
      notifyListeners();
      return false;
    }
  }

  Future<bool> joinGroup(String code) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final userId = await _getCurrentUserId();
      if (userId == null) {
        _error = 'User not authenticated';
        return false;
      }

      // Check if group exists
      final groupResponse = await _supabase
          .from('groups')
          .select()
          .eq('code', code)
          .maybeSingle();

      if (groupResponse == null) {
        _error = 'Group not found';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Check if user is already a member
      final existingMember = await _supabase
          .from('group_members')
          .select()
          .eq('group_code', code)
          .eq('user_id', userId)
          .maybeSingle();

      if (existingMember != null) {
        // Already a member, just update active group
        await _supabase.from('users').update({
          'active_group_code': code,
          'last_active': DateTime.now().toIso8601String(),
        }).eq('id', userId);

        _activeGroupCode = code;
        _activeGroupData = groupResponse;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Get user profile
      final userProfile = await _supabase
          .from('users')
          .select('name, email')
          .eq('id', userId)
          .single();

      final userName = userProfile['name'] ?? 'Unknown User';
      final userEmail = userProfile['email'];

      // Add user to group
      await _supabase.from('group_members').insert({
        'group_code': code,
        'user_id': userId,
        'name': userName,
        'email': userEmail,
        'joined_at': DateTime.now().toIso8601String(),
        'last_seen': DateTime.now().toIso8601String(),
      });

      // Update group last_updated
      await _supabase.from('groups').update({
        'last_updated': DateTime.now().toIso8601String(),
      }).eq('code', code);

      // Update user's active group
      await _supabase.from('users').update({
        'active_group_code': code,
        'last_active': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      _activeGroupCode = code;
      _activeGroupData = groupResponse;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to join group';
      _isLoading = false;
      debugPrint('Error joining group: $e');
      notifyListeners();
      return false;
    }
  }

  Future<bool> leaveGroup() async {
    try {
      if (_activeGroupCode == null) return true;

      final userId = await _getCurrentUserId();
      if (userId == null) return false;

      // Remove user from group_members
      await _supabase
          .from('group_members')
          .delete()
          .eq('group_code', _activeGroupCode!)
          .eq('user_id', userId);

      // Remove user from member_locations
      await _supabase
          .from('member_locations')
          .delete()
          .eq('group_code', _activeGroupCode!)
          .eq('user_id', userId);

      // Check if group has any remaining members
      final remainingMembers = await _supabase
          .from('group_members')
          .select()
          .eq('group_code', _activeGroupCode!);

      if ((remainingMembers as List).isEmpty) {
        // Delete group and related data
        await _supabase
            .from('trip_notifications')
            .delete()
            .eq('group_code', _activeGroupCode!);

        // Delete trips and related data
        final trips = await _supabase
            .from('trips')
            .select('id')
            .eq('group_code', _activeGroupCode!);

        for (final trip in trips as List) {
          await _supabase.from('trip_points').delete().eq('trip_id', trip['id']);
          await _supabase.from('trip_routes').delete().eq('trip_id', trip['id']);
        }

        await _supabase.from('trips').delete().eq('group_code', _activeGroupCode!);
        await _supabase
            .from('member_locations')
            .delete()
            .eq('group_code', _activeGroupCode!);
        await _supabase.from('groups').delete().eq('code', _activeGroupCode!);
      } else {
        // Update group
        await _supabase.from('groups').update({
          'last_updated': DateTime.now().toIso8601String(),
        }).eq('code', _activeGroupCode!);
      }

      // Remove active group from user
      await _supabase.from('users').update({
        'active_group_code': null,
        'last_active': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      _activeGroupCode = null;
      _activeGroupData = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to leave group';
      debugPrint('Error leaving group: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshActiveGroup() async {
    if (_activeGroupCode == null) return;

    try {
      final groupResponse = await _supabase
          .from('groups')
          .select()
          .eq('code', _activeGroupCode!)
          .maybeSingle();

      if (groupResponse != null) {
        _activeGroupData = groupResponse;

        // Load member details
        final members = await _supabase
            .from('group_members')
            .select()
            .eq('group_code', _activeGroupCode!);

        _activeGroupData!['members'] = members;
        notifyListeners();
      } else {
        // Group no longer exists
        await leaveGroup();
      }
    } catch (e) {
      debugPrint('Error refreshing active group: $e');
    }
  }

  String _generateGroupCode([int length = 6]) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(
      length,
      (index) => chars[rand.nextInt(chars.length)],
    ).join();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
