import 'package:flutter/material.dart';
import '../../core/services/haptic_service.dart';
import '../group/group_management_screen.dart';
import '../profile/profile_screen.dart';

class ModeSelectionScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Select Mode', style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () {
              HapticService.selection();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProfileScreen()),
              );
            },
            tooltip: 'Profile',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ModeButton(
              label: 'Bike',
              icon: Icons.motorcycle,
              color: theme.colorScheme.primary,
              onTap: () {
                HapticService.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupManagementScreen(mode: 'Bike'),
                  ),
                );
              },
            ),
            SizedBox(height: 24),
            _ModeButton(
              label: 'Bicycle',
              icon: Icons.pedal_bike,
              color: theme.colorScheme.secondary,
              onTap: () {
                HapticService.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupManagementScreen(mode: 'Bicycle'),
                  ),
                );
              },
            ),
            SizedBox(height: 24),
            _ModeButton(
              label: 'Random',
              icon: Icons.shuffle,
              color: theme.colorScheme.tertiary,
              onTap: () {
                HapticService.mediumImpact();
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupManagementScreen(mode: 'Random'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 2),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 36),
              SizedBox(width: 24),
              Text(
                label,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
