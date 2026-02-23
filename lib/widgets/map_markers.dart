import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../models/group_member_location.dart';
import '../core/theme/app_colors.dart';

class MapMarkers {
  // Predefined colors for different members - more diverse and aesthetically appealing
  static const List<Color> memberColors = [
    Color(0xFF2196F3), // Blue
    Color(0xFFE91E63), // Pink
    Color(0xFF9C27B0), // Purple
    Color(0xFF673AB7), // Deep Purple
    Color(0xFF3F51B5), // Indigo
    Color(0xFF00BCD4), // Cyan
    Color(0xFF009688), // Teal
    Color(0xFF4CAF50), // Green
    Color(0xFF8BC34A), // Light Green
    Color(0xFFCDDC39), // Lime
    Color(0xFFFFEB3B), // Yellow
    Color(0xFFFF9800), // Orange
    Color(0xFFFF5722), // Deep Orange
    Color(0xFF795548), // Brown
    Color(0xFF607D8B), // Blue Grey
    Color(0xFF9E9E9E), // Grey
  ];

  // Get color for a specific member based on their ID
  static Color getMemberColor(String userId) {
    final hash = userId.hashCode;
    return memberColors[hash % memberColors.length];
  }

  // Get initials from name
  static String getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.length == 1 && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  // Member marker with profile image and name
  static Marker buildMemberMarker(
    GroupMemberLocation member, {
    bool isCurrentUser = false,
  }) {
    final memberColor = getMemberColor(member.userId);
    final initials = getInitials(member.name);

    return Marker(
      point: member.coordinates,
      width: 45,
      height: 45,
      child: Stack(
        children: [
          // Background circle with member-specific color
          Container(
            decoration: BoxDecoration(
              color: isCurrentUser ? AppColors.primary : memberColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: isCurrentUser ? AppColors.primary : memberColor,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child:
                member.profileImage != null && member.profileImage!.isNotEmpty
                ? ClipOval(
                    child: Image.memory(
                      _decodeBase64Image(member.profileImage!),
                      width: 41,
                      height: 41,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint(
                          'Failed to load profile image for ${member.name}: $error',
                        );
                        // Fallback to initials if image fails to load
                        return Container(
                          width: 41,
                          height: 41,
                          decoration: BoxDecoration(
                            color: memberColor,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : Container(
                    width: 41,
                    height: 41,
                    decoration: BoxDecoration(
                      color: memberColor,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
          ),
          // Status indicator (only show if not current user, to avoid multiple icons)
          if (member.status != null && !isCurrentUser)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: _getStatusColor(member.status!),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Icon(
                  _getStatusIcon(member.status!),
                  color: Colors.white,
                  size: 8,
                ),
              ),
            ),
          // Current user indicator (only for current user)
          if (isCurrentUser)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: Icon(Icons.my_location, color: Colors.white, size: 8),
              ),
            ),
          // Name label with better positioning
          Positioned(
            top: -25,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCurrentUser ? AppColors.primary : memberColor,
                  width: 1,
                ),
              ),
              child: Text(
                member.name,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Start point marker
  static Marker buildStartMarker(LatLng coordinates, String name) {
    return Marker(
      point: coordinates,
      width: 40,
      height: 40,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.trip_origin, color: Colors.white, size: 20),
          ),
          Positioned(
            top: -20,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Start: $name',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // End point marker
  static Marker buildEndMarker(LatLng coordinates, String name) {
    return Marker(
      point: coordinates,
      width: 40,
      height: 40,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.flag, color: Colors.white, size: 20),
          ),
          Positioned(
            top: -20,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'End: $name',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Break point marker
  static Marker buildBreakMarker(LatLng coordinates, String name) {
    return Marker(
      point: coordinates,
      width: 35,
      height: 35,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.warning,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(Icons.coffee, color: Colors.white, size: 18),
          ),
          Positioned(
            top: -18,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Break: $name',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Current user location marker with direction indicator
  static Marker buildCurrentUserMarker(LatLng coordinates, {double? heading}) {
    return Marker(
      point: coordinates,
      width: 50,
      height: 50,
      child: Stack(
        children: [
          // Main location circle
          Container(
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(Icons.my_location, color: Colors.white, size: 22),
          ),
          // Direction triangle (only show if heading is available)
          if (heading != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: Transform.rotate(
                  angle:
                      (heading * 3.14159) / 180, // Convert degrees to radians
                  child: Container(
                    width: 0,
                    height: 0,
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: Colors.white, width: 8),
                        right: BorderSide(color: Colors.white, width: 8),
                        bottom: BorderSide(
                          color: Colors.transparent,
                          width: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Helper methods
  static Uint8List _decodeBase64Image(String base64String) {
    try {
      debugPrint(
        'Attempting to decode base64 image, length: ${base64String.length}',
      );
      final decoded = base64Decode(base64String);
      debugPrint('Successfully decoded image, size: ${decoded.length} bytes');
      return decoded;
    } catch (e) {
      debugPrint('Error decoding base64 image: $e');
      return Uint8List(0);
    }
  }

  static Color _getStatusColor(String status) {
    switch (status) {
      case 'riding':
        return Colors.green;
      case 'at_break':
        return AppColors.warning;
      case 'arrived':
        return AppColors.secondary;
      case 'stopped':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static IconData _getStatusIcon(String status) {
    switch (status) {
      case 'riding':
        return Icons.directions_bike;
      case 'at_break':
        return Icons.coffee;
      case 'arrived':
        return Icons.check_circle;
      case 'stopped':
        return Icons.stop;
      default:
        return Icons.info;
    }
  }
}
