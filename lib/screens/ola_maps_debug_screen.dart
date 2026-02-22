import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';
import '../core/services/ola_maps_service.dart';
import '../core/theme/app_colors.dart';

class OlaMapsDebugScreen extends StatefulWidget {
  const OlaMapsDebugScreen({super.key});

  @override
  _OlaMapsDebugScreenState createState() => _OlaMapsDebugScreenState();
}

class _OlaMapsDebugScreenState extends State<OlaMapsDebugScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _placeIdController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<String> _logs = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _addLog('Ola Maps Debug Screen initialized');
    _addLog('API Configuration: ${OlaMapsService.configurationStatus}');
  }

  void _addLog(String message) {
    setState(() {
      _logs.add('${DateTime.now().toString().substring(11, 19)}: $message');
      if (_logs.length > 100) {
        _logs.removeAt(0);
      }
    });
    debugPrint(message);
  }

  void _clearLogs() {
    setState(() {
      _logs.clear();
    });
  }

  Future<void> _testApiConnection() async {
    setState(() => _isLoading = true);
    _addLog('Testing API connection...');

    try {
      final isConnected = await OlaMapsService.testApiConnection();
      _addLog('API Connection: ${isConnected ? 'SUCCESS' : 'FAILED'}');
    } catch (e) {
      _addLog('API Connection Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testSearch() async {
    if (_searchController.text.isEmpty) {
      _addLog('Please enter a search query');
      return;
    }

    setState(() => _isLoading = true);
    _addLog('Searching for: ${_searchController.text}');

    try {
      final results = await OlaMapsService.searchPlaces(_searchController.text);
      _addLog('Search completed: ${results.length} results found');

      for (var result in results.take(3)) {
        _addLog('- ${result['name']} (${result['source']})');
      }
    } catch (e) {
      _addLog('Search Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testPlaceDetails() async {
    if (_placeIdController.text.isEmpty) {
      _addLog('Please enter a place_id');
      return;
    }

    setState(() => _isLoading = true);
    _addLog('Getting place details for: ${_placeIdController.text}');

    try {
      final details = await OlaMapsService.getPlaceDetailsById(
        _placeIdController.text,
      );

      if (details != null) {
        _addLog('Place Details: SUCCESS');
        _addLog('- Name: ${details['name']}');
        _addLog('- Address: ${details['formatted_address']}');
        _addLog('- Rating: ${details['rating']}');
      } else {
        _addLog('Place Details: FAILED - No data returned');
      }
    } catch (e) {
      _addLog('Place Details Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testNearbySearch() async {
    setState(() => _isLoading = true);
    _addLog('Testing nearby search in Mumbai...');

    try {
      final results = await OlaMapsService.searchNearbyPlaces(
        LatLng(19.0760, 72.8777), // Mumbai coordinates
        type: 'restaurant',
        radius: 5000,
      );
      _addLog('Nearby Search: ${results.length} results found');

      for (var result in results.take(3)) {
        _addLog('- ${result['name']} (${result['rating']} stars)');
      }
    } catch (e) {
      _addLog('Nearby Search Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testRouting() async {
    setState(() => _isLoading = true);
    _addLog('Testing routing from Mumbai to Mumbai Airport...');

    try {
      final route = await OlaMapsService.getRoute(
        LatLng(19.0760, 72.8777), // Mumbai
        LatLng(19.0896, 72.8656), // Mumbai Airport
      );

      if (route != null) {
        _addLog('Routing: SUCCESS');
        _addLog(
          '- Distance: ${(route['distance'] / 1000).toStringAsFixed(2)} km',
        );
        _addLog(
          '- Duration: ${(route['duration'] / 60).toStringAsFixed(1)} minutes',
        );
        _addLog('- Coordinates: ${route['coordinates'].length} points');
      } else {
        _addLog('Routing: FAILED - No route returned');
      }
    } catch (e) {
      _addLog('Routing Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testSnapToRoad() async {
    setState(() => _isLoading = true);
    _addLog('Testing SnapToRoad...');

    try {
      final coordinates = [LatLng(19.0760, 72.8777), LatLng(19.0896, 72.8656)];

      final snapped = await OlaMapsService.snapToRoad(coordinates);
      _addLog('SnapToRoad: ${snapped.length} coordinates snapped');
    } catch (e) {
      _addLog('SnapToRoad Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testRouteOptimization() async {
    setState(() => _isLoading = true);
    _addLog('Testing route optimization...');

    try {
      final waypoints = [
        LatLng(19.0896, 72.8656), // Mumbai Airport
        LatLng(19.0760, 72.8777), // Mumbai
      ];

      final optimized = await OlaMapsService.optimizeRoute(
        LatLng(19.0760, 72.8777), // Start
        LatLng(19.0896, 72.8656), // End
        waypoints,
      );

      if (optimized != null) {
        _addLog('Route Optimization: SUCCESS');
        _addLog(
          '- Distance: ${(optimized['distance'] / 1000).toStringAsFixed(2)} km',
        );
        _addLog(
          '- Duration: ${(optimized['duration'] / 60).toStringAsFixed(1)} minutes',
        );
      } else {
        _addLog('Route Optimization: FAILED - No route returned');
      }
    } catch (e) {
      _addLog('Route Optimization Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testElevation() async {
    setState(() => _isLoading = true);
    _addLog('Testing elevation data...');

    try {
      final locations = [LatLng(19.0760, 72.8777), LatLng(19.0896, 72.8656)];

      final elevation = await OlaMapsService.getElevation(locations);
      _addLog('Elevation: ${elevation.length} values retrieved');
    } catch (e) {
      _addLog('Elevation Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _testAllApis() async {
    setState(() => _isLoading = true);
    _addLog('Testing all APIs...');

    try {
      await OlaMapsService.testAllApis();
      _addLog('All API tests completed');
    } catch (e) {
      _addLog('All APIs Test Error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ola Maps Debug'),
        actions: [
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: _clearLogs,
            tooltip: 'Clear Logs',
          ),
        ],
      ),
      body: Column(
        children: [
          // API Status
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Row(
              children: [
                Icon(
                  OlaMapsService.isConfigured
                      ? Icons.check_circle
                      : Icons.error,
                  color: OlaMapsService.isConfigured
                      ? Colors.green
                      : Colors.red,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    OlaMapsService.configurationStatus,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // Test Buttons
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // API Connection Test
                  ElevatedButton(
                    onPressed: _isLoading ? null : _testApiConnection,
                    child: Text('Test API Connection'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  SizedBox(height: 8),

                  // Search Test
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search Query',
                      border: OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.search),
                        onPressed: _testSearch,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),

                  // Place Details Test
                  TextField(
                    controller: _placeIdController,
                    decoration: InputDecoration(
                      labelText: 'Place ID',
                      border: OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.info),
                        onPressed: _testPlaceDetails,
                      ),
                    ),
                  ),
                  SizedBox(height: 16),

                  // API Test Buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton(
                        onPressed: _isLoading ? null : _testNearbySearch,
                        child: Text('Nearby Search'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _testRouting,
                        child: Text('Routing'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _testSnapToRoad,
                        child: Text('SnapToRoad'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _testRouteOptimization,
                        child: Text('Route Optimize'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _testElevation,
                        child: Text('Elevation'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _testAllApis,
                        child: Text('Test All APIs'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.secondary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Logs
          Container(
            height: 200,
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey)),
            ),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: Row(
                    children: [
                      Text(
                        'Logs (${_logs.length})',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Spacer(),
                      if (_isLoading) CircularProgressIndicator(strokeWidth: 2),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Text(
                          _logs[index],
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
                ),
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
    _placeIdController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
