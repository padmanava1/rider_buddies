import 'package:latlong2/latlong.dart';

class GroupMemberLocation {
  final String userId;
  final String name;
  final String? profileImage;
  final String? email;
  final LatLng coordinates;
  final DateTime lastUpdated;
  final bool isOnline;
  final String? status; // "riding", "at_break", "arrived", etc.

  GroupMemberLocation({
    required this.userId,
    required this.name,
    this.profileImage,
    this.email,
    required this.coordinates,
    required this.lastUpdated,
    this.isOnline = true,
    this.status,
  });

  factory GroupMemberLocation.fromMap(Map<String, dynamic> map) {
    return GroupMemberLocation(
      userId: map['userId'] ?? '',
      name: map['name'] ?? 'Unknown User',
      profileImage: map['profileImage'],
      email: map['email'],
      coordinates: LatLng(
        (map['coordinates']?['latitude'] ?? 0.0).toDouble(),
        (map['coordinates']?['longitude'] ?? 0.0).toDouble(),
      ),
      lastUpdated: map['lastUpdated']?.toDate() ?? DateTime.now(),
      isOnline: map['isOnline'] ?? true,
      status: map['status'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'profileImage': profileImage,
      'email': email,
      'coordinates': {
        'latitude': coordinates.latitude,
        'longitude': coordinates.longitude,
      },
      'lastUpdated': lastUpdated,
      'isOnline': isOnline,
      'status': status,
    };
  }

  GroupMemberLocation copyWith({
    String? userId,
    String? name,
    String? profileImage,
    String? email,
    LatLng? coordinates,
    DateTime? lastUpdated,
    bool? isOnline,
    String? status,
  }) {
    return GroupMemberLocation(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      profileImage: profileImage ?? this.profileImage,
      email: email ?? this.email,
      coordinates: coordinates ?? this.coordinates,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isOnline: isOnline ?? this.isOnline,
      status: status ?? this.status,
    );
  }
}
