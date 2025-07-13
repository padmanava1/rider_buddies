import 'package:flutter/material.dart';
import 'dart:math';
import '../../core/constants/assets.dart';
import '../../core/services/location_permission_manager.dart';
import '../auth/login_screen.dart';

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _raysOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 2),
    );
    _scaleAnimation = Tween<double>(begin: 0.7, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _raysOpacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.forward();

    // Initialize location permissions during splash
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Initialize location permission manager
      await LocationPermissionManager.initialize();

      // Wait for splash animation to complete
      await Future.delayed(Duration(milliseconds: 2500));

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
      }
    } catch (e) {
      debugPrint('Error initializing app: $e');
      // Continue to login screen even if initialization fails
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => LoginScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: _raysOpacity.value,
                    child: CustomPaint(
                      size: Size(300, 300),
                      painter: _RaysPainter(),
                    ),
                  ),
                  Image.asset(AppAssets.logo, width: 220, height: 220),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.amber.withOpacity(0.3)
      ..strokeWidth = 3;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    for (int i = 0; i < 24; i++) {
      final angle = (i * 15) * 3.14159 / 180;
      final start = Offset(
        center.dx + radius * 0.7 * cos(angle),
        center.dy + radius * 0.7 * sin(angle),
      );
      final end = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
