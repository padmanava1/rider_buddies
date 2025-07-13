import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class GroupProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _activeGroupCode;
  Map<String, dynamic>? _activeGroupData;
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

  // Load active group for current user
  Future<void> _loadActiveGroup() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Check if user is part of any active group
      final userGroups = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      if (userGroups.exists) {
        final userData = userGroups.data();
        if (userData != null) {
          final activeGroup = userData['activeGroupCode'] as String?;

          if (activeGroup != null) {
            // Verify group still exists and user is still a member
            final groupDoc = await _firestore
                .collection('groups')
                .doc(activeGroup)
                .get();

            if (groupDoc.exists) {
              final groupData = groupDoc.data();
              if (groupData != null) {
                final members = List<String>.from(groupData['members'] ?? []);

                if (members.contains(user.uid)) {
                  _activeGroupCode = activeGroup;
                  _activeGroupData = groupData as Map<String, dynamic>;
                  notifyListeners();
                  return;
                }
              }
            }
          }
        }
      }

      // No active group found
      _activeGroupCode = null;
      _activeGroupData = null;
      notifyListeners();
    } catch (e) {
      print('Error loading active group: $e');
      _error = 'Failed to load active group';
      notifyListeners();
    }
  }

  // Create a new group
  Future<bool> createGroup(String mode) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final user = _auth.currentUser;
      if (user == null) {
        _error = 'User not authenticated';
        return false;
      }

      // Generate group code
      final code = _generateGroupCode();

      // Get user profile
      final userProfile = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userProfile.data() as Map<String, dynamic>?;
      final userName = userData?['name'] ?? 'Unknown User';

      final groupData = {
        'code': code,
        'mode': mode,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'members': [user.uid],
        'leader': user.uid,
        'memberDetails': {
          user.uid: {
            'name': userName,
            'email': user.email,
            'joinedAt': FieldValue.serverTimestamp(),
            'lastSeen': FieldValue.serverTimestamp(),
          },
        },
      };

      // Create group
      await _firestore.collection('groups').doc(code).set(groupData);

      // Update user's active group
      await _firestore.collection('users').doc(user.uid).update({
        'activeGroupCode': code,
        'lastActive': FieldValue.serverTimestamp(),
      });

      _activeGroupCode = code;
      _activeGroupData = groupData;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to create group';
      _isLoading = false;
      print('Error creating group: $e');
      notifyListeners();
      return false;
    }
  }

  // Join an existing group
  Future<bool> joinGroup(String code) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final user = _auth.currentUser;
      if (user == null) {
        _error = 'User not authenticated';
        return false;
      }

      // Check if group exists
      final groupDoc = await _firestore.collection('groups').doc(code).get();

      if (!groupDoc.exists) {
        _error = 'Group not found';
        return false;
      }

      final groupData = groupDoc.data();
      if (groupData == null) {
        _error = 'Invalid group data';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final members = List<String>.from(groupData['members'] ?? []);

      // Check if user is already a member
      if (members.contains(user.uid)) {
        _activeGroupCode = code;
        _activeGroupData = groupData as Map<String, dynamic>;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Get user profile
      final userProfile = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userProfile.data();
      final userName = userData?['name']?.toString() ?? 'Unknown User';

      // Add user to group
      members.add(user.uid);
      final memberDetails = Map<String, dynamic>.from(
        groupData['memberDetails'] ?? {},
      );
      memberDetails[user.uid] = {
        'name': userName,
        'email': user.email,
        'joinedAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('groups').doc(code).update({
        'members': members,
        'memberDetails': memberDetails,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update user's active group
      await _firestore.collection('users').doc(user.uid).update({
        'activeGroupCode': code,
        'lastActive': FieldValue.serverTimestamp(),
      });

      _activeGroupCode = code;
      _activeGroupData = groupData;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to join group';
      _isLoading = false;
      print('Error joining group: $e');
      notifyListeners();
      return false;
    }
  }

  // Leave current group
  Future<bool> leaveGroup() async {
    try {
      if (_activeGroupCode == null) return true;

      final user = _auth.currentUser;
      if (user == null) return false;

      // Remove user from group
      final groupDoc = await _firestore
          .collection('groups')
          .doc(_activeGroupCode)
          .get();

      if (groupDoc.exists) {
        final groupData = groupDoc.data();
        if (groupData != null) {
          final members = List<String>.from(groupData['members'] ?? []);
          final memberDetails = Map<String, dynamic>.from(
            groupData['memberDetails'] ?? {},
          );

          members.remove(user.uid);
          memberDetails.remove(user.uid);

          if (members.isEmpty) {
            // Delete group if no members left
            await _firestore
                .collection('groups')
                .doc(_activeGroupCode)
                .delete();
          } else {
            // Update group
            await _firestore.collection('groups').doc(_activeGroupCode).update({
              'members': members,
              'memberDetails': memberDetails,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      // Remove active group from user
      await _firestore.collection('users').doc(user.uid).update({
        'activeGroupCode': null,
        'lastActive': FieldValue.serverTimestamp(),
      });

      _activeGroupCode = null;
      _activeGroupData = null;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to leave group';
      print('Error leaving group: $e');
      notifyListeners();
      return false;
    }
  }

  // Refresh active group data
  Future<void> refreshActiveGroup() async {
    if (_activeGroupCode == null) return;

    try {
      final groupDoc = await _firestore
          .collection('groups')
          .doc(_activeGroupCode)
          .get();

      if (groupDoc.exists) {
        final groupData = groupDoc.data();
        if (groupData != null) {
          _activeGroupData = groupData as Map<String, dynamic>;
          notifyListeners();
        } else {
          // Group data is null, leave the group
          await leaveGroup();
        }
      } else {
        // Group no longer exists
        await leaveGroup();
      }
    } catch (e) {
      print('Error refreshing active group: $e');
    }
  }

  // Generate unique group code
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
