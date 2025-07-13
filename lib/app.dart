import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'providers/theme_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/group_provider.dart';
import 'providers/trip_provider.dart';
import 'core/services/location_service.dart';
import 'core/services/live_group_tracking.dart';
import 'core/services/location_permission_manager.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/mode_selection/mode_selection_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/group/group_status_screen.dart';
import 'screens/ola_maps_debug_screen.dart';

class RideBuddiesApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
        ChangeNotifierProvider<GroupProvider>(create: (_) => GroupProvider()),
        ChangeNotifierProvider<TripProvider>(create: (_) => TripProvider()),
        ChangeNotifierProvider<LocationService>(
          create: (_) => LocationService(),
        ),
        ChangeNotifierProvider<LiveGroupTracking>(
          create: (_) => LiveGroupTracking(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Rider Buddies',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: AuthWrapper(),
            debugShowCheckedModeBanner: false,
            routes: {
              '/login': (context) => LoginScreen(),
              '/mode-selection': (context) => ModeSelectionScreen(),
              '/profile': (context) => ProfileScreen(),
              '/ola-maps-debug': (context) => OlaMapsDebugScreen(),
            },
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize location permission manager
      await LocationPermissionManager.initialize();

      // Initialize location service
      final locationService = Provider.of<LocationService>(
        context,
        listen: false,
      );
      await locationService.initialize(context);

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('Error initializing app: $e');
      setState(() {
        _isInitialized = true;
      });
    }
  }

  Widget _buildAnimatedLoadingScreen(String message) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primary.withOpacity(0.1), Colors.white],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated app icon
              TweenAnimationBuilder<double>(
                duration: Duration(seconds: 2),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: 0.8 + (0.2 * value),
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.directions_bike,
                        size: 60,
                        color: AppColors.primary,
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 32),

              // Animated message
              TweenAnimationBuilder<double>(
                duration: Duration(milliseconds: 1500),
                tween: Tween(begin: 0.0, end: 1.0),
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, -10 * (1 - value)),
                    child: Opacity(
                      opacity: value,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          message,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              SizedBox(height: 24),

              // Animated dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  return TweenAnimationBuilder<double>(
                    duration: Duration(milliseconds: 600),
                    tween: Tween(begin: 0.0, end: 1.0),
                    builder: (context, value, child) {
                      return Container(
                        margin: EdgeInsets.symmetric(horizontal: 4),
                        child: Transform.scale(
                          scale: 0.5 + (0.5 * value),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(
                                0.3 + (0.7 * value),
                              ),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return _buildAnimatedLoadingScreen('Initializing...');
    }

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        if (authProvider.isLoading) {
          return _buildAnimatedLoadingScreen('Checking authentication...');
        }

        if (authProvider.isAuthenticated) {
          return Consumer<GroupProvider>(
            builder: (context, groupProvider, child) {
              if (groupProvider.isLoading) {
                return _buildAnimatedLoadingScreen('Loading your group...');
              }

              if (groupProvider.hasActiveGroup) {
                // User has an active group, navigate to group status
                return GroupStatusScreen(
                  groupCode: groupProvider.activeGroupCode!,
                );
              }

              // No active group, show mode selection
              return ModeSelectionScreen();
            },
          );
        }

        return SplashScreen();
      },
    );
  }
}
