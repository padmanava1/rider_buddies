import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ImagePicker _picker = ImagePicker();

  User? _user;
  bool _isLoading = false;
  String? _error;
  String? _profileImageUrl;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;
  String? get profileImageUrl => _profileImageUrl;

  AuthProvider() {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      if (user != null) {
        _loadUserProfile();
      }
      notifyListeners();
    });
  }

  Future<void> _loadUserProfile() async {
    if (_user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(_user!.uid).get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          _profileImageUrl = data['profileImageUrl']?.toString();
          notifyListeners();
        }
      }
    } catch (e) {
      print('Error loading user profile: $e');
    }
  }

  Future<bool> signInWithEmailAndPassword(String email, String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _getErrorMessage(e.code);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Temporary method to test authentication without reCAPTCHA
  Future<bool> createUserWithEmailAndPasswordSimple(
    String email,
    String password,
    String name,
    String phone,
  ) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Create user with minimal settings
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create user profile in Firestore
      await _firestore.collection('users').doc(result.user!.uid).set({
        'name': name,
        'email': email,
        'phone': phone,
        'createdAt': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
        'profileImageUrl': null,
      });

      return true;
    } on FirebaseAuthException catch (e) {
      _error = _getErrorMessage(e.code);
      print('Firebase Auth Error: ${e.code} - ${e.message}');
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred. Please try again.';
      print('Unexpected error during signup: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createUserWithEmailAndPassword(
    String email,
    String password,
    String name,
    String phone,
  ) async {
    // Use the simple version for now to bypass reCAPTCHA issues
    return createUserWithEmailAndPasswordSimple(email, password, name, phone);
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      _profileImageUrl = null;
    } catch (e) {
      _error = 'Failed to sign out';
      notifyListeners();
    }
  }

  Future<void> updateUserProfile({String? name, String? phone}) async {
    try {
      if (_user == null) return;

      Map<String, dynamic> updates = {};
      if (name != null) updates['name'] = name;
      if (phone != null) updates['phone'] = phone;
      updates['lastActive'] = FieldValue.serverTimestamp();

      await _firestore.collection('users').doc(_user!.uid).update(updates);
    } catch (e) {
      _error = 'Failed to update profile';
      notifyListeners();
    }
  }

  // Test method to check Firebase Storage connectivity
  Future<bool> testFirebaseStorage() async {
    try {
      // This method is no longer needed as Firebase Storage is removed.
      // Keeping it for now to avoid breaking existing calls, but it will always return true.
      return true;
    } catch (e) {
      print('Firebase Storage test failed: $e');
      return false;
    }
  }

  Future<String?> uploadProfileImage() async {
    try {
      if (_user == null) return null;

      // Test Firebase Storage first
      final storageAvailable = await testFirebaseStorage();
      if (!storageAvailable) {
        _error =
            'Storage service not available. Please check your internet connection.';
        notifyListeners();
        return null;
      }

      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 512,
        maxHeight: 512,
      );

      if (pickedFile == null) return null;

      final file = File(pickedFile.path);
      final fileName =
          '${_user!.uid}_profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      // final ref = _storage.ref().child('profile_images/$fileName'); // Removed Firebase Storage

      // Show loading state
      _isLoading = true;
      notifyListeners();

      // Upload file
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      final dataUrl = 'data:image/jpeg;base64,$base64String';

      // Update Firestore
      await _firestore.collection('users').doc(_user!.uid).update({
        'profileImageUrl': dataUrl,
        'lastActive': FieldValue.serverTimestamp(),
      });

      _profileImageUrl = dataUrl;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return dataUrl;
    } catch (e) {
      _error = 'Failed to upload profile image. Please try again.';
      _isLoading = false;
      print('Error uploading profile image: $e');
      notifyListeners();
      return null;
    }
  }

  // Fallback method for testing without Firebase Storage
  Future<String?> uploadProfileImageFallback() async {
    try {
      if (_user == null) return null;

      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 512,
        maxHeight: 512,
      );

      if (pickedFile == null) return null;

      // For testing, just return a placeholder URL
      final placeholderUrl =
          'https://via.placeholder.com/200x200/4CAF50/FFFFFF?text=Profile';

      // Update Firestore with placeholder
      await _firestore.collection('users').doc(_user!.uid).update({
        'profileImageUrl': placeholderUrl,
        'lastActive': FieldValue.serverTimestamp(),
      });

      _profileImageUrl = placeholderUrl;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return placeholderUrl;
    } catch (e) {
      _error = 'Failed to upload profile image. Please try again.';
      _isLoading = false;
      print('Error uploading profile image: $e');
      notifyListeners();
      return null;
    }
  }

  // Base64 image upload method (free alternative to Firebase Storage)
  Future<String?> uploadProfileImageBase64() async {
    try {
      if (_user == null) return null;

      final pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 60, // Lower quality to reduce size
        maxWidth: 300,
        maxHeight: 300,
      );

      if (pickedFile == null) return null;

      final file = File(pickedFile.path);
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);

      // Create a data URL
      final dataUrl = 'data:image/jpeg;base64,$base64String';

      // Show loading state
      _isLoading = true;
      notifyListeners();

      // Store in Firestore
      await _firestore.collection('users').doc(_user!.uid).update({
        'profileImageUrl': dataUrl,
        'lastActive': FieldValue.serverTimestamp(),
      });

      _profileImageUrl = dataUrl;
      _error = null;
      _isLoading = false;
      notifyListeners();
      return dataUrl;
    } catch (e) {
      _error = 'Failed to upload profile image. Please try again.';
      _isLoading = false;
      print('Error uploading profile image: $e');
      notifyListeners();
      return null;
    }
  }

  // Remove profile image (base64 version)
  Future<void> removeProfileImageBase64() async {
    try {
      if (_user == null) return;

      // Update user profile
      await _firestore.collection('users').doc(_user!.uid).update({
        'profileImageUrl': null,
        'lastActive': FieldValue.serverTimestamp(),
      });

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

      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(_user!.uid)
          .get();

      return doc.data() as Map<String, dynamic>?;
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

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Wrong password provided.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'configuration-not-found':
        return 'Authentication configuration error. Please try again.';
      case 'recaptcha-not-enabled':
        return 'Security verification is not enabled. Please try again.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      default:
        return 'An error occurred. Please try again.';
    }
  }
}
