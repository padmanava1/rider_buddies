import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/location_permission_manager.dart';
import '../../core/services/ola_maps_service.dart';
import '../../core/theme/app_colors.dart';

class LocationPickerScreen extends StatefulWidget {
  final String title;
  const LocationPickerScreen({required this.title});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final MapController _mapController = MapController();

  List<Map<String, dynamic>> _searchResults = [];
  bool _isLoading = false;
  String? _error;
  LatLng? _currentLocation;
  LatLng? _selectedLocation;
  String? _selectedLocationName;
  String? _selectedLocationAddress;
  bool _hasLocationPermission = false;
  bool _isLoadingAddress = false;
  bool _isMapExpanded = false;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    try {
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

      final currentLoc = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentLocation = currentLoc;
        _selectedLocation = currentLoc;
        _isLoading = false;
      });

      // Get address for current location
      _getAddressForLocation(currentLoc);
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

  Future<void> _getAddressForLocation(LatLng location) async {
    setState(() => _isLoadingAddress = true);
    try {
      final placeDetails = await OlaMapsService.getPlaceDetails(location);
      if (placeDetails != null && mounted) {
        setState(() {
          _selectedLocationName = placeDetails['name'] ?? 'Selected Location';
          _selectedLocationAddress = placeDetails['address'] ??
              'Lat: ${location.latitude.toStringAsFixed(6)}, Lng: ${location.longitude.toStringAsFixed(6)}';
          _isLoadingAddress = false;
        });
      } else {
        // Fallback to geocoding
        List<Placemark> placemarks = await placemarkFromCoordinates(
          location.latitude,
          location.longitude,
        );
        if (placemarks.isNotEmpty && mounted) {
          Placemark place = placemarks[0];
          String address = [
            place.street,
            place.locality,
            place.administrativeArea,
          ].where((part) => part != null && part.isNotEmpty).join(', ');
          setState(() {
            _selectedLocationName = place.name ?? place.locality ?? 'Selected Location';
            _selectedLocationAddress = address.isNotEmpty ? address :
                'Lat: ${location.latitude.toStringAsFixed(6)}, Lng: ${location.longitude.toStringAsFixed(6)}';
            _isLoadingAddress = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
      if (mounted) {
        setState(() {
          _selectedLocationName = 'Selected Location';
          _selectedLocationAddress = 'Lat: ${location.latitude.toStringAsFixed(6)}, Lng: ${location.longitude.toStringAsFixed(6)}';
          _isLoadingAddress = false;
        });
      }
    }
  }

  /// Debounced search - use for onChanged to prevent rapid API calls
  Future<void> _searchLocationDebounced(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    try {
      setState(() => _isLoading = true);
      debugPrint('Debounced search for: $query');

      // Use debounced search - waits 500ms after last keystroke
      final results = await OlaMapsService.searchPlacesDebounced(query);

      if (mounted) {
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Cancelled searches throw errors - ignore them
      if (e.toString() != 'Cancelled' && mounted) {
        debugPrint('Debounced search error: $e');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Immediate search - use for onSubmitted for instant results
  Future<void> _searchLocation(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    try {
      setState(() => _isLoading = true);
      debugPrint('Searching for location: $query');

      // Try Ola Maps API (with caching)
      final olaResults = await OlaMapsService.searchPlaces(query);
      debugPrint('Ola Maps results: ${olaResults.length}');

      if (mounted) {
        setState(() {
          _searchResults = olaResults;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        setState(() {
          _error = 'Search failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _selectSearchResult(Map<String, dynamic> location) {
    HapticService.lightImpact();
    final coords = location['coordinates'] as LatLng;
    setState(() {
      _selectedLocation = coords;
      _selectedLocationName = location['name'];
      _selectedLocationAddress = location['address'];
      _searchResults = []; // Clear search results
      _searchController.clear();
    });

    // Move map to selected location
    try {
      _mapController.move(coords, 16.0);
    } catch (e) {
      debugPrint('Error moving map: $e');
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng location) {
    HapticService.lightImpact();
    setState(() {
      _selectedLocation = location;
    });
    _getAddressForLocation(location);
  }

  void _confirmSelection() {
    if (_selectedLocation != null) {
      HapticService.mediumImpact();
      Navigator.pop(context, {
        'name': _selectedLocationName ?? 'Selected Location',
        'address': _selectedLocationAddress ?? 'Selected Location',
        'coordinates': _selectedLocation,
      });
    }
  }

  void _useCurrentLocation() {
    if (_currentLocation != null) {
      HapticService.lightImpact();
      setState(() {
        _selectedLocation = _currentLocation;
      });
      _getAddressForLocation(_currentLocation!);
      try {
        _mapController.move(_currentLocation!, 16.0);
      } catch (e) {
        debugPrint('Error moving map: $e');
      }
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

  void _toggleMapExpanded() {
    HapticService.lightImpact();
    setState(() {
      _isMapExpanded = !_isMapExpanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mapCenter = _selectedLocation ?? _currentLocation ?? LatLng(19.0760, 72.8777);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
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
                  _searchLocationDebounced(value); // Debounced to prevent rapid API calls
                } else {
                  setState(() => _searchResults = []);
                }
              },
              onSubmitted: (value) => _searchLocation(value),
            ),
          ),

          // Current Location Button
          if (_hasLocationPermission && _currentLocation != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _useCurrentLocation,
                  icon: Icon(Icons.my_location, size: 18),
                  label: Text('Use Current Location'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),

          // Location Permission Button
          if (!_hasLocationPermission)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _requestLocationPermission,
                  icon: Icon(Icons.location_on, size: 18),
                  label: Text('Enable Location Access'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),

          SizedBox(height: 8),

          // Search Results (if any)
          if (_searchResults.isNotEmpty)
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.symmetric(horizontal: 16),
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final location = _searchResults[index];
                  final source = location['source'] ?? 'Unknown';
                  final isOlaMaps = source.toString().contains('Ola Maps');

                  return Card(
                    margin: EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isOlaMaps
                              ? Colors.green.withValues(alpha: 0.1)
                              : AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.location_on,
                          color: isOlaMaps ? Colors.green : AppColors.primary,
                          size: 20,
                        ),
                      ),
                      title: Text(location['name'], maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(location['address'], maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _selectSearchResult(location),
                    ),
                  );
                },
              ),
            ),

          // Map Preview and Selection Area (when no search results)
          if (_searchResults.isEmpty)
            Expanded(
              child: Column(
                children: [
                  // Map Preview
                  Expanded(
                    flex: _isMapExpanded ? 3 : 2,
                    child: Container(
                      margin: EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: _mapController,
                            options: MapOptions(
                              initialCenter: mapCenter,
                              initialZoom: 16.0,
                              onTap: _onMapTap,
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.riderbuddies.app',
                              ),
                              // Current location marker (blue pulse)
                              if (_currentLocation != null && _selectedLocation != _currentLocation)
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _currentLocation!,
                                      width: 20,
                                      height: 20,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(alpha: 0.3),
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.blue, width: 2),
                                        ),
                                        child: Center(
                                          child: Container(
                                            width: 6,
                                            height: 6,
                                            decoration: BoxDecoration(
                                              color: Colors.blue,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              // Selected location marker (red pin)
                              if (_selectedLocation != null)
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: _selectedLocation!,
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.topCenter,
                                      child: Icon(
                                        Icons.location_pin,
                                        color: Colors.red,
                                        size: 40,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                          // Expand/collapse button
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: _toggleMapExpanded,
                              child: Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  _isMapExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
                                  size: 20,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          // Instruction overlay
                          Positioned(
                            bottom: 8,
                            left: 8,
                            right: 8,
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.touch_app, color: Colors.white, size: 14),
                                  SizedBox(width: 6),
                                  Text(
                                    'Tap to select location',
                                    style: TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 12),

                  // Selected Location Card
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 16),
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _selectedLocation != null
                            ? AppColors.primary.withValues(alpha: 0.3)
                            : Colors.grey.shade300,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _selectedLocation != null
                                ? Colors.red.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.location_pin,
                            color: _selectedLocation != null ? Colors.red : Colors.grey,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedLocation != null
                                    ? 'Selected Location'
                                    : 'No Location Selected',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey,
                                ),
                              ),
                              SizedBox(height: 2),
                              _isLoadingAddress
                                  ? Row(
                                      children: [
                                        SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                        SizedBox(width: 8),
                                        Text('Getting address...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                      ],
                                    )
                                  : Text(
                                      _selectedLocationName ?? 'Tap on the map to select',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              if (_selectedLocationAddress != null && !_isLoadingAddress)
                                Text(
                                  _selectedLocationAddress!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[600],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 12),

                  // Confirm Button
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _selectedLocation != null ? _confirmSelection : null,
                          icon: Icon(Icons.check),
                          label: Text('Confirm Location'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey[300],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 8),
                ],
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
