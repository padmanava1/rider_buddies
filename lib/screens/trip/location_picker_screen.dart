import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../../core/services/haptic_service.dart';
import '../../core/services/location_permission_manager.dart';
import '../../core/services/ola_maps_service.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/location_permission_dialog.dart';

class LocationPickerScreen extends StatefulWidget {
  final String title;
  const LocationPickerScreen({required this.title});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  String? _error;
  LatLng? _currentLocation;
  bool _hasLocationPermission = false;
  bool _showMap = false;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    try {
      // Use the new permission manager
      final hasPermission = await LocationPermissionManager.ensurePermission(
        context,
        title: 'Location Access Required',
        message:
            'We need your location to help you select starting and ending points for your trip.',
      );

      setState(() {
        _hasLocationPermission = hasPermission;
        _isLoading = false;
      });

      if (hasPermission) {
        _getCurrentLocation();
      } else {
        setState(() {
          _error = 'Location permission is required to use current location';
          _isLoading = false;
        });
      }
    } on PlatformException catch (e) {
      debugPrint('Platform exception in location picker: $e');
      setState(() {
        _error = 'Location service is unavailable. Please restart the app.';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to check location permission';
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() => _isLoading = true);

      debugPrint('Getting current location in picker...');

      // Test location access first
      final canAccessLocation =
          await LocationPermissionManager.testLocationAccess();
      if (!canAccessLocation) {
        setState(() {
          _error =
              'Location access failed. Please check your location settings.';
          _isLoading = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      debugPrint(
        'Location obtained in picker: ${position.latitude}, ${position.longitude}',
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });

      // Get address for current location
      await _searchLocation('${position.latitude}, ${position.longitude}');
    } on PlatformException catch (e) {
      debugPrint('Platform exception getting current location in picker: $e');
      setState(() {
        _error = 'Location service is unavailable. Please restart the app.';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error getting current location in picker: $e');
      setState(() {
        _error = 'Failed to get current location: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    try {
      setState(() => _isLoading = true);
      debugPrint('Searching for location: $query');

      // Try Ola Maps API first
      final olaResults = await OlaMapsService.searchPlaces(query);
      debugPrint('Ola Maps results: ${olaResults.length}');

      if (olaResults.isNotEmpty) {
        debugPrint('Using Ola Maps results');
        setState(() {
          _searchResults = olaResults;
          _isLoading = false;
        });
        return;
      }

      debugPrint('Ola Maps returned no results, trying fallback');

      // Fallback to geocoding
      List<Location> locations = await locationFromAddress(query);
      debugPrint('Geocoding results: ${locations.length}');

      List<Map<String, dynamic>> results = [];
      for (Location location in locations.take(5)) {
        try {
          List<Placemark> placemarks = await placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );

          if (placemarks.isNotEmpty) {
            Placemark place = placemarks[0];
            String address = [
              place.street,
              place.locality,
              place.administrativeArea,
            ].where((part) => part != null && part.isNotEmpty).join(', ');

            results.add({
              'name': place.name ?? place.locality ?? 'Unknown Location',
              'address': address,
              'coordinates': LatLng(location.latitude, location.longitude),
              'source': 'Geocoding Fallback',
            });
          }
        } catch (e) {
          debugPrint('Error getting placemark: $e');
        }
      }

      debugPrint('Final results: ${results.length}');
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Search error: $e');
      setState(() {
        _error = 'Search failed: $e';
        _isLoading = false;
      });
    }
  }

  void _selectLocation(Map<String, dynamic> location) {
    HapticService.mediumImpact();
    Navigator.pop(context, location);
  }

  void _useCurrentLocation() {
    if (_currentLocation != null) {
      HapticService.mediumImpact();
      Navigator.pop(context, {
        'name': 'Current Location',
        'address': 'Your current location',
        'coordinates': _currentLocation,
      });
    }
  }

  void _requestLocationPermission() async {
    final granted = await LocationPermissionManager.ensurePermission(
      context,
      title: 'Location Access Required',
      message:
          'We need your location to help you select starting and ending points for your trip.',
    );

    if (granted) {
      setState(() {
        _hasLocationPermission = true;
        _error = null;
      });
      _getCurrentLocation();
    }
  }

  void _toggleMapView() {
    setState(() {
      _showMap = !_showMap;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: Icon(_showMap ? Icons.list : Icons.map),
            onPressed: _toggleMapView,
            tooltip: _showMap ? 'Show List' : 'Show Map',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search for a location...',
                prefixIcon: Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchResults = []);
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                if (value.length > 2) {
                  _searchLocation(value);
                } else {
                  setState(() => _searchResults = []);
                }
              },
              onSubmitted: (value) => _searchLocation(value),
            ),
          ),

          // API Status (if not configured)
          if (!OlaMapsService.isConfigured)
            Container(
              margin: EdgeInsets.symmetric(horizontal: 16),
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Using basic search. Configure Ola Maps API for better results.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Current Location Button
          if (_hasLocationPermission && _currentLocation != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _useCurrentLocation,
                  icon: Icon(Icons.my_location),
                  label: Text('Use Current Location'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),

          // Location Permission Button
          if (!_hasLocationPermission)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _requestLocationPermission,
                  icon: Icon(Icons.location_on),
                  label: Text('Enable Location Access'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),

          SizedBox(height: 8),

          // Results
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error, size: 64, color: Colors.red),
                        SizedBox(height: 16),
                        Text(
                          _error!,
                          style: theme.textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 16),
                        if (!_hasLocationPermission)
                          ElevatedButton(
                            onPressed: _requestLocationPermission,
                            child: Text('Enable Location'),
                          )
                        else
                          ElevatedButton(
                            onPressed: _getCurrentLocation,
                            child: Text('Retry'),
                          ),
                      ],
                    ),
                  )
                : _searchResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Search for a location to get started',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.grey,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final location = _searchResults[index];
                      final source = location['source'] ?? 'Unknown';
                      final isOlaMaps = source == 'Ola Maps';

                      return Card(
                        margin: EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isOlaMaps
                                  ? Colors.green.withOpacity(0.1)
                                  : AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isOlaMaps ? Icons.map : Icons.location_on,
                              color: isOlaMaps
                                  ? Colors.green
                                  : AppColors.primary,
                              size: 20,
                            ),
                          ),
                          title: Text(location['name']),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(location['address']),
                              SizedBox(height: 2),
                              Text(
                                'Source: $source',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isOlaMaps ? Colors.green : Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _selectLocation(location),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }
}
