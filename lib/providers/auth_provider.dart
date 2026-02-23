import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import '../core/services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  final SupabaseClient _supabase = SupabaseService.client;
  final ImagePicker _picker = ImagePicker();
  StreamSubscription<AuthState>? _authStateSubscription;

  User? _user;
  String? _userId; // Database user ID (UUID)
  Map<String, dynamic>? _userProfile;
  bool _isLoading = false;
  String? _error;
  String? _profileImageUrl;

  User? get user => _user;
  String? get userId => _userId;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  String? get profileImageUrl => _profileImageUrl;

  AuthProvider() {
    _authStateSubscription = _supabase.auth.onAuthStateChange.listen((data) {
      _user = data.session?.user;
      if (_user != null) {
        _loadUserProfile();
      } else {
        _userId = null;
        _userProfile = null;
        _profileImageUrl = null;
      }
      notifyListeners();
    });

    // Check initial session
    _user = _supabase.auth.currentUser;
    if (_user != null) {
      _loadUserProfile();
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    if (_user == null) return;

    try {
      final response = await _supabase
          .from('users')
          .select()
          .eq('auth_id', _user!.id)
          .maybeSingle();

      if (response != null) {
        _userProfile = response;
        _userId = response['id'];
        _profileImageUrl = response['profile_image_url'];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  Future<bool> signInWithEmailAndPassword(String email, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      return true;
    } on AuthException catch (e) {
      _error = _getErrorMessage(e.message);
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred. Please try again.';
      debugPrint('Unexpected error during login: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createUserWithEmailAndPasswordSimple(
    String email,
    String password,
    String name,
    String phone,
  ) async {
    return createUserWithEmailAndPassword(email, password, name, phone);
  }

  Future<bool> createUserWithEmailAndPassword(
    String email,
    String password,
    String name,
    String phone,
  ) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Create auth user
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (authResponse.user == null) {
        _error = 'Failed to create user';
        return false;
      }

      // Create user profile in database
      final insertResponse = await _supabase.from('users').insert({
        'auth_id': authResponse.user!.id,
        'name': name,
        'email': email,
        'phone': phone,
        'created_at': DateTime.now().toIso8601String(),
        'last_active': DateTime.now().toIso8601String(),
      }).select().single();

      _userId = insertResponse['id'];

      return true;
    } on AuthException catch (e) {
      _error = _getErrorMessage(e.message);
      debugPrint('Supabase Auth Error: ${e.message}');
      return false;
    } on PostgrestException catch (e) {
      _error = 'Failed to create profile: ${e.message}';
      debugPrint('Supabase Database Error: ${e.message}');
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred. Please try again.';
      debugPrint('Unexpected error during signup: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      _profileImageUrl = null;
      _userProfile = null;
      _userId = null;
    } catch (e) {
      _error = 'Failed to sign out';
      notifyListeners();
    }
  }

  Future<void> updateUserProfile({String? name, String? phone}) async {
    try {
      if (_user == null || _userId == null) return;

      final updates = <String, dynamic>{
        'last_active': DateTime.now().toIso8601String(),
      };
      if (name != null) updates['name'] = name;
      if (phone != null) updates['phone'] = phone;

      await _supabase.from('users').update(updates).eq('id', _userId!);

      // Reload profile
      await _loadUserProfile();
    } catch (e) {
      _error = 'Failed to update profile';
      notifyListeners();
    }
  }

  Future<bool> testFirebaseStorage() async {
    // Legacy method - always returns true for Supabase
    return true;
  }

  Future<String?> uploadProfileImage() async {
    try {
      if (_user == null || _userId == null) return null;

      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 512,
        maxHeight: 512,
      );

      if (pickedFile == null) return null;

      _isLoading = true;
      notifyListeners();

      final file = File(pickedFile.path);
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      final dataUrl = 'data:image/jpeg;base64,$base64String';

      await _supabase.from('users').update({
        'profile_image_url': dataUrl,
        'last_active': DateTime.now().toIso8601String(),
      }).eq('id', _userId!);

      _profileImageUrl = dataUrl;
      _error = null;
      return dataUrl;
    } catch (e) {
      _error = 'Failed to upload profile image. Please try again.';
      debugPrint('Error uploading profile image: $e');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> uploadProfileImageFallback() async {
    return uploadProfileImage();
  }

  Future<String?> uploadProfileImageBase64() async {
    return uploadProfileImage();
  }

  Future<void> removeProfileImageBase64() async {
    try {
      if (_user == null || _userId == null) return;

      await _supabase.from('users').update({
        'profile_image_url': null,
        'last_active': DateTime.now().toIso8601String(),
      }).eq('id', _userId!);

      _profileImageUrl = null;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to remove image';
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      if (_user == null) return null;

      if (_userProfile != null) return _userProfile;

      await _loadUserProfile();
      return _userProfile;
    } catch (e) {
      _error = 'Failed to load profile';
      notifyListeners();
      return null;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _getErrorMessage(String message) {
    final lowerMessage = message.toLowerCase();

    if (lowerMessage.contains('user not found') ||
        lowerMessage.contains('invalid login')) {
      return 'No user found with this email or wrong password.';
    }
    if (lowerMessage.contains('email already')) {
      return 'An account already exists with this email.';
    }
    if (lowerMessage.contains('weak password') ||
        lowerMessage.contains('password')) {
      return 'Password is too weak. Use at least 6 characters.';
    }
    if (lowerMessage.contains('invalid email')) {
      return 'Invalid email address.';
    }
    if (lowerMessage.contains('too many requests') ||
        lowerMessage.contains('rate limit')) {
      return 'Too many attempts. Please try again later.';
    }
    if (lowerMessage.contains('network')) {
      return 'Network error. Please check your internet connection.';
    }

    return message.isNotEmpty ? message : 'An error occurred. Please try again.';
  }
}
