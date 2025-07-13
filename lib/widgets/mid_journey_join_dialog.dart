import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/services/haptic_service.dart';
import '../core/services/mid_journey_detection_service.dart';
import '../core/theme/app_colors.dart';
import 'package:latlong2/latlong.dart';

class MidJourneyJoinDialog extends StatefulWidget {
  final MidJourneyStatus status;
  final MidJourneyRoute? routeToStart;
  final MeetingPoint? meetingPoint;
  final MidJourneyRoute? routeToMeetingPoint;
  final VoidCallback? onJoinAtStart;
  final VoidCallback? onJoinMidJourney;
  final VoidCallback? onCancel;

  const MidJourneyJoinDialog({
    Key? key,
    required this.status,
    this.routeToStart,
    this.meetingPoint,
    this.routeToMeetingPoint,
    this.onJoinAtStart,
    this.onJoinMidJourney,
    this.onCancel,
  }) : super(key: key);

  @override
  State<MidJourneyJoinDialog> createState() => _MidJourneyJoinDialogState();
}

class _MidJourneyJoinDialogState extends State<MidJourneyJoinDialog>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    HapticService.mediumImpact();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: Duration(milliseconds: 400),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(begin: Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.elasticOut),
    );

    _fadeController.forward();
    _slideController.forward();
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: theme.scaffoldBackgroundColor,
            elevation: 8,
            content: Container(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header with animated icon
                  _buildHeader(theme),
                  SizedBox(height: 24),

                  // Status information
                  _buildStatusInfo(theme),
                  SizedBox(height: 20),

                  // Route information
                  if (widget.routeToStart != null ||
                      widget.routeToMeetingPoint != null)
                    _buildRouteInfo(theme),
                  SizedBox(height: 24),

                  // Action buttons
                  _buildActionButtons(theme),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      children: [
        // Animated icon
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: widget.status.isMidJourney
                      ? AppColors.warning.withOpacity(0.1)
                      : AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.status.isMidJourney ? Icons.location_on : Icons.flag,
                  size: 32,
                  color: widget.status.isMidJourney
                      ? AppColors.warning
                      : AppColors.primary,
                ),
              ),
            );
          },
        ),
        SizedBox(height: 16),

        // Title
        Text(
          widget.status.isMidJourney ? 'Join Mid-Journey' : 'Join at Start',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: widget.status.isMidJourney
                ? AppColors.warning
                : AppColors.primary,
          ),
        ),
        SizedBox(height: 8),

        // Subtitle
        Text(
          widget.status.recommendedAction,
          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildStatusInfo(ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.straighten, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Distance to Start',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(widget.status.distanceToStart / 1000).toStringAsFixed(1)} km',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.timer, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Estimated Time',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _calculateETA(widget.status.distanceToStart),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (widget.meetingPoint != null) ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.people, color: AppColors.secondary, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Meeting Point',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${(widget.meetingPoint!.distanceFromCurrent / 1000).toStringAsFixed(1)} km',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRouteInfo(ThemeData theme) {
    final route = widget.routeToMeetingPoint ?? widget.routeToStart;
    if (route == null) return SizedBox.shrink();

    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.route, color: AppColors.primary, size: 20),
              SizedBox(width: 8),
              Text(
                'Route Information',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildRouteDetail(
                  'Distance',
                  '${(route.distance / 1000).toStringAsFixed(1)} km',
                  Icons.straighten,
                ),
              ),
              Expanded(
                child: _buildRouteDetail(
                  'Duration',
                  _formatDuration(route.duration),
                  Icons.timer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteDetail(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 16),
        SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Column(
      children: [
        if (widget.status.isMidJourney && widget.meetingPoint != null) ...[
          // Join at meeting point button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticService.success();
                widget.onJoinMidJourney?.call();
                Navigator.of(context).pop();
              },
              icon: Icon(Icons.location_on),
              label: Text('Join at Meeting Point'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
            ),
          ),
          SizedBox(height: 12),
        ],

        // Join at start button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              HapticService.success();
              widget.onJoinAtStart?.call();
              Navigator.of(context).pop();
            },
            icon: Icon(Icons.flag),
            label: Text('Join at Start Point'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
          ),
        ),
        SizedBox(height: 12),

        // Cancel button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              HapticService.lightImpact();
              widget.onCancel?.call();
              Navigator.of(context).pop();
            },
            child: Text('Cancel'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              side: BorderSide(color: Colors.grey[300]!),
            ),
          ),
        ),
      ],
    );
  }

  String _calculateETA(double distanceInMeters) {
    // Assuming average speed of 20 km/h for cycling
    final speedKmh = 20.0;
    final distanceKm = distanceInMeters / 1000;
    final timeHours = distanceKm / speedKmh;
    final timeMinutes = (timeHours * 60).round();

    if (timeMinutes < 1) return 'Less than 1 min';
    if (timeMinutes < 60) return '$timeMinutes min';

    final hours = timeMinutes ~/ 60;
    final minutes = timeMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min';

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    return '${hours}h ${remainingMinutes}m';
  }
}
