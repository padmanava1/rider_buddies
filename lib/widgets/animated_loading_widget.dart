import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class AnimatedLoadingWidget extends StatefulWidget {
  final String message;
  final IconData icon;
  final Color? primaryColor;
  final Duration? animationDuration;

  const AnimatedLoadingWidget({
    super.key,
    required this.message,
    this.icon = Icons.directions_bike,
    this.primaryColor,
    this.animationDuration,
  });

  @override
  State<AnimatedLoadingWidget> createState() => _AnimatedLoadingWidgetState();
}

class _AnimatedLoadingWidgetState extends State<AnimatedLoadingWidget>
    with TickerProviderStateMixin {
  late AnimationController _iconController;
  late AnimationController _messageController;
  late AnimationController _dotsController;
  late Animation<double> _iconAnimation;
  late Animation<double> _messageAnimation;
  late Animation<double> _dotsAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _iconController = AnimationController(
      duration: widget.animationDuration ?? Duration(seconds: 2),
      vsync: this,
    );
    _messageController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    _dotsController = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    );

    _iconAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _iconController, curve: Curves.easeOutBack),
    );
    _messageAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _messageController, curve: Curves.easeOutCubic),
    );
    _dotsAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _dotsController, curve: Curves.easeInOut),
    );

    _iconController.forward();
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) _messageController.forward();
    });
    Future.delayed(Duration(milliseconds: 1000), () {
      if (mounted) _dotsController.forward();
    });
  }

  @override
  void dispose() {
    _iconController.dispose();
    _messageController.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.primaryColor ?? AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [primaryColor.withOpacity(0.1), Colors.white],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon
            AnimatedBuilder(
              animation: _iconAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: 0.8 + (0.2 * _iconAnimation.value),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primaryColor.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Icon(widget.icon, size: 60, color: primaryColor),
                  ),
                );
              },
            ),
            SizedBox(height: 32),

            // Animated message
            AnimatedBuilder(
              animation: _messageAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, -10 * (1 - _messageAnimation.value)),
                  child: Opacity(
                    opacity: _messageAnimation.value,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: primaryColor.withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: primaryColor,
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
            AnimatedBuilder(
              animation: _dotsAnimation,
              builder: (context, child) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (index) {
                    final delay = index * 0.2;
                    final dotAnimation = Tween<double>(begin: 0.0, end: 1.0)
                        .animate(
                          CurvedAnimation(
                            parent: _dotsController,
                            curve: Interval(
                              delay,
                              delay + 0.3,
                              curve: Curves.easeInOut,
                            ),
                          ),
                        );

                    return AnimatedBuilder(
                      animation: dotAnimation,
                      builder: (context, child) {
                        return Container(
                          margin: EdgeInsets.symmetric(horizontal: 4),
                          child: Transform.scale(
                            scale: 0.5 + (0.5 * dotAnimation.value),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(
                                  0.3 + (0.7 * dotAnimation.value),
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
