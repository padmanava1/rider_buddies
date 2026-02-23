import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/services/location_permission_manager.dart';
import '../core/services/haptic_service.dart';
import '../core/theme/app_colors.dart';

class LocationPermissionDialog extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onGranted;
  final VoidCallback? onDenied;

  const LocationPermissionDialog({
    required this.title,
    required this.message,
    this.onGranted,
    this.onDenied,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.location_on, color: AppColors.primary, size: 28),
          SizedBox(width: 12),
          Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: theme.textTheme.bodyLarge),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Why we need location access:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                _buildFeatureItem('📍 Find your current location'),
                _buildFeatureItem('🗺️ Show your position on the map'),
                _buildFeatureItem('🚗 Plan routes from your location'),
                _buildFeatureItem('👥 Share your location with group'),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            HapticService.lightImpact();
            onDenied?.call();
            Navigator.of(context).pop(false);
          },
          child: Text('Not Now'),
        ),
        ElevatedButton(
          onPressed: () async {
            HapticService.mediumImpact();
            try {
              final granted = await LocationPermissionManager.requestPermission(
                context,
              );

              if (granted) {
                onGranted?.call();
                Navigator.of(context).pop(true);
              } else {
                // Show settings dialog if permission denied
                _showSettingsDialog(context);
              }
            } on PlatformException catch (e) {
              debugPrint('Platform exception in permission dialog: $e');
              _showPluginErrorDialog(context);
            } catch (e) {
              debugPrint('Error in permission dialog: $e');
              _showSettingsDialog(context);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text('Allow Location'),
        ),
      ],
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: AppColors.primary, size: 16),
          SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Location Permission Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Location access is needed for this feature. Please enable location permission in your device settings.',
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How to enable location:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('1. Go to Settings > Apps > Rider Buddies'),
                  Text('2. Tap Permissions > Location'),
                  Text('3. Select "Allow while using app"'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await LocationPermissionManager.requestPermission(
                  context,
                  showDialog: false,
                );
                Navigator.of(context).pop();
              } on PlatformException catch (e) {
                debugPrint('Cannot open settings: $e');
                Navigator.of(context).pop();
                _showManualSettingsInstructions(context);
              } catch (e) {
                debugPrint('Error opening settings: $e');
                Navigator.of(context).pop();
                _showManualSettingsInstructions(context);
              }
            },
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showPluginErrorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Location Service Unavailable'),
        content: Text(
          'The location service is currently unavailable. Please restart the app and try again.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showManualSettingsInstructions(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Manual Settings Required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please manually enable location permissions:'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Steps:', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('1. Open your device Settings'),
                  Text('2. Find "Apps" or "Application Manager"'),
                  Text('3. Find "Rider Buddies" in the list'),
                  Text('4. Tap "Permissions"'),
                  Text('5. Enable "Location" permission'),
                  Text('6. Return to the app'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('I Understand'),
          ),
        ],
      ),
    );
  }
}

// Helper function to show location permission dialog
Future<bool> showLocationPermissionDialog(
  BuildContext context, {
  String title = 'Location Access Required',
  String message =
      'This app needs location access to provide you with the best experience.',
  VoidCallback? onGranted,
  VoidCallback? onDenied,
}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => LocationPermissionDialog(
          title: title,
          message: message,
          onGranted: onGranted,
          onDenied: onDenied,
        ),
      ) ??
      false;
}
