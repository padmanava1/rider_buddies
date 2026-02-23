import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/trip_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../map/live_group_map_screen.dart';
import '../trip/trip_planning_screen.dart';
import '../trip/trip_status_screen.dart';
import 'qr_code_display_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';

class GroupStatusScreen extends StatefulWidget {
  final String groupCode;
  const GroupStatusScreen({super.key, required this.groupCode});

  @override
  State<GroupStatusScreen> createState() => _GroupStatusScreenState();
}

class _GroupStatusScreenState extends State<GroupStatusScreen>
    with TickerProviderStateMixin {
  RealtimeChannel? _notificationChannel;
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final Set<String> _shownNotifications = {};

  Map<String, dynamic>? _groupData;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadGroupData();
    _listenToNotifications();
    _loadTripData();
  }

  void _loadTripData() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tripProvider = Provider.of<TripProvider>(context, listen: false);
      if (!tripProvider.hasActiveTrip && !tripProvider.isLoading) {
        tripProvider.loadTripData(widget.groupCode);
      }
    });
  }

  Future<void> _loadGroupData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final supabase = SupabaseService.client;

      // Load group data
      final groupResponse = await supabase
          .from('groups')
          .select()
          .eq('code', widget.groupCode)
          .maybeSingle();

      if (groupResponse == null) {
        setState(() {
          _error = 'Group not found';
          _isLoading = false;
        });
        return;
      }

      // Load group members
      final membersResponse = await supabase
          .from('group_members')
          .select()
          .eq('group_code', widget.groupCode);

      final members = membersResponse as List;
      final memberDetails = <String, dynamic>{};
      for (final member in members) {
        memberDetails[member['user_id']] = {
          'name': member['name'],
          'email': member['email'],
        };
      }

      setState(() {
        _groupData = {
          ...groupResponse,
          'members': members.map((m) => m['user_id']).toList(),
          'memberDetails': memberDetails,
          'leader': groupResponse['leader_id'],
        };
        _isLoading = false;
      });

      // Subscribe to group updates
      _subscribeToGroupUpdates();
    } catch (e) {
      setState(() {
        _error = 'Error loading group: $e';
        _isLoading = false;
      });
    }
  }

  void _subscribeToGroupUpdates() {
    final supabase = SupabaseService.client;

    supabase
        .channel('group_updates:${widget.groupCode}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'groups',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'code',
            value: widget.groupCode,
          ),
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.update) {
              _loadGroupData();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'group_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_code',
            value: widget.groupCode,
          ),
          callback: (payload) {
            _loadGroupData();
          },
        )
        .subscribe();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 400),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(begin: Offset(0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _fadeController.forward();
    _slideController.forward();
  }

  void _listenToNotifications() {
    _notificationChannel?.unsubscribe();

    final supabase = SupabaseService.client;
    _notificationChannel = supabase
        .channel('notifications:${widget.groupCode}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'trip_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'group_code',
            value: widget.groupCode,
          ),
          callback: (payload) {
            final notification = payload.newRecord;
            final notificationId = notification['id']?.toString() ?? '';

            if (!_shownNotifications.contains(notificationId)) {
              _shownNotifications.add(notificationId);
              _showNotificationDialog(notification);
            }
          },
        )
        .subscribe();
  }

  void _showNotificationDialog(Map<String, dynamic> notification) {
    final data = notification['data'];
    if (data is Map<String, dynamic>) {
      final message = data['message']?.toString() ?? 'No message';
      final type = notification['notification_type']?.toString() ?? 'unknown';

      if (!mounted) return;

      // Check if dialog is already showing
      if (Navigator.of(context).canPop()) {
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => AlertDialog(
          title: Text(_getNotificationTitle(type)),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  String _getNotificationTitle(String type) {
    switch (type) {
      case 'trip_created':
        return 'Trip Planning Started';
      case 'point_added':
        return 'Point Added';
      case 'point_removed':
        return 'Point Removed';
      case 'route_selected':
        return 'Route Selected';
      case 'trip_started':
        return 'Trip Started!';
      case 'trip_completed':
        return 'Trip Completed!';
      case 'trip_cancelled':
        return 'Trip Cancelled';
      default:
        return 'Notification';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Group Status', style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'leave') {
                HapticService.warning();
                final shouldLeave = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Leave Group'),
                    content: Text('Are you sure you want to leave this group?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text('Leave'),
                      ),
                    ],
                  ),
                );

                if (shouldLeave == true && mounted) {
                  final groupProvider = Provider.of<GroupProvider>(
                    context,
                    listen: false,
                  );
                  final success = await groupProvider.leaveGroup();

                  if (!mounted) return;
                  if (success) {
                    Navigator.pushReplacementNamed(context, '/mode-selection');
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to leave group'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    );
                  }
                }
              } else if (value == 'logout') {
                final authProvider = Provider.of<AuthProvider>(
                  context,
                  listen: false,
                );
                await authProvider.signOut();
                if (mounted) {
                  Navigator.of(context).pushReplacementNamed('/login');
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Leave Group'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ],
            child: Icon(Icons.more_vert),
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
            SizedBox(height: 16),
            Text(
              'Loading group...',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    if (_groupData == null) {
      return Center(child: Text('Group not found'));
    }

    final members = _groupData!['members'] as List<dynamic>? ?? [];
    final memberDetails = _groupData!['memberDetails'] as Map<String, dynamic>? ?? {};
    final leader = _groupData!['leader']?.toString();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final isLeader = authProvider.userId == leader;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Group Info Card
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Group Code: ${widget.groupCode}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Mode: ${_groupData!['mode'] ?? 'Unknown'}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Members: ${members.length}',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                      if (isLeader) ...[
                        SizedBox(height: 8),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.leader.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.leader.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            'Group Leader',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.leader.withValues(alpha: 0.8),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),

              // QR Code Card
              _buildQRCodeCard(theme),
              SizedBox(height: 16),

              // Trip Planning Button and Start Journey Button (for leader)
              if (isLeader) _buildLeaderButtons(theme),
              if (isLeader) SizedBox(height: 16),

              // Trip Status Button (for non-leaders)
              if (!isLeader) _buildMemberButtons(theme),
              if (!isLeader) SizedBox(height: 16),

              // Map Button
              _buildMapButton(theme),
              SizedBox(height: 16),

              // Debug Button (for development)
              if (isLeader) _buildDebugButton(theme),
              if (isLeader) SizedBox(height: 16),

              // Members List
              Expanded(
                child: _buildMembersList(theme, memberDetails, leader),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQRCodeCard(ThemeData theme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () {
          HapticService.mediumImpact();
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  QRCodeDisplayScreen(groupCode: widget.groupCode),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(1.0, 0.0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                  ),
                  child: child,
                );
              },
              transitionDuration: Duration(milliseconds: 300),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: QrImageView(
                  data: widget.groupCode,
                  version: QrVersions.auto,
                  size: 60.0,
                  backgroundColor: Colors.white,
                  dataModuleStyle: const QrDataModuleStyle(
                    color: Colors.black,
                    dataModuleShape: QrDataModuleShape.square,
                  ),
                  eyeStyle: const QrEyeStyle(
                    color: Colors.black,
                    eyeShape: QrEyeShape.square,
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Group QR Code',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tap to view full QR code',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Share with others to join',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[400],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderButtons(ThemeData theme) {
    return Consumer<TripProvider>(
      builder: (context, tripProvider, child) {
        final canStartTrip = tripProvider.startPoint != null &&
            tripProvider.endPoint != null &&
            tripProvider.selectedRoute != null &&
            tripProvider.tripData?['status'] == 'planning';

        final tripStatus = tripProvider.tripData?['status'];
        final isTripActive = tripStatus == 'active';

        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticService.mediumImpact();
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          TripPlanningScreen(groupCode: widget.groupCode),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        return SlideTransition(
                          position: Tween<Offset>(
                            begin: Offset(1.0, 0.0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                          ),
                          child: child,
                        );
                      },
                      transitionDuration: Duration(milliseconds: 300),
                    ),
                  );
                },
                icon: Icon(tripProvider.hasActiveTrip ? Icons.edit : Icons.route),
                label: Text(tripProvider.hasActiveTrip ? 'Edit Trip' : 'Plan Trip'),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  minimumSize: Size(double.infinity, 56),
                  backgroundColor: isTripActive ? Colors.grey : AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
              ),
            ),
            if (canStartTrip) ...[
              SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _handleStartJourney(tripProvider),
                  icon: Icon(Icons.play_arrow),
                  label: Text('Start Journey'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    minimumSize: Size(double.infinity, 56),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ],
            if (isTripActive) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.directions_bike, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'Journey in Progress',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _handleStartJourney(TripProvider tripProvider) async {
    HapticService.mediumImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Start Journey'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ready to start your trip?'),
            SizedBox(height: 12),
            Text(
              'From: ${tripProvider.startPoint!.name}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            Text(
              'To: ${tripProvider.endPoint!.name}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Text(
              'Distance: ${(tripProvider.selectedRoute!.distance / 1000).toStringAsFixed(1)} km',
              style: TextStyle(color: Colors.grey[600]),
            ),
            Text(
              'Duration: ${(tripProvider.selectedRoute!.duration / 60).round()} min',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 12),
            Text(
              'All group members will be notified.',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text('Start Journey'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await tripProvider.startTrip(widget.groupCode);
      if (!mounted) return;

      if (success) {
        HapticService.success();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Journey started! Opening live map...'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                LiveGroupMapScreen(groupCode: widget.groupCode),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                ),
                child: child,
              );
            },
            transitionDuration: Duration(milliseconds: 300),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tripProvider.error ?? 'Failed to start journey'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildMemberButtons(ThemeData theme) {
    return Consumer<TripProvider>(
      builder: (context, tripProvider, child) {
        return ElevatedButton.icon(
          onPressed: () {
            HapticService.mediumImpact();
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    TripStatusScreen(groupCode: widget.groupCode),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(1.0, 0.0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                    ),
                    child: child,
                  );
                },
                transitionDuration: Duration(milliseconds: 300),
              ),
            );
          },
          icon: Icon(Icons.info_outline),
          label: Text('Trip Status'),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.grey.shade200,
            foregroundColor: Colors.grey.shade800,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 1,
          ),
        );
      },
    );
  }

  Widget _buildMapButton(ThemeData theme) {
    return ElevatedButton.icon(
      onPressed: () {
        HapticService.mediumImpact();
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) =>
                LiveGroupMapScreen(groupCode: widget.groupCode),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(1.0, 0.0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(parent: animation, curve: Curves.easeInOut),
                ),
                child: child,
              );
            },
            transitionDuration: Duration(milliseconds: 300),
          ),
        );
      },
      icon: Icon(Icons.map),
      label: Text('Open Live Map'),
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(vertical: 16),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 2,
      ),
    );
  }

  Widget _buildDebugButton(ThemeData theme) {
    return OutlinedButton.icon(
      onPressed: () {
        HapticService.mediumImpact();
        Navigator.pushNamed(context, '/ola-maps-debug');
      },
      icon: Icon(Icons.bug_report),
      label: Text('Debug Ola Maps APIs'),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        side: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildMembersList(
    ThemeData theme,
    Map<String, dynamic> memberDetails,
    String? leader,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Group Members',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: memberDetails.length,
                itemBuilder: (context, index) {
                  final memberId = memberDetails.keys.elementAt(index);
                  final memberData = memberDetails[memberId] as Map<String, dynamic>;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary,
                      child: Text(
                        (memberData['name'] as String? ?? 'Unknown')[0].toUpperCase(),
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      memberData['name'] ?? 'Unknown',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      memberData['email'] ?? '',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    trailing: memberId == leader
                        ? Icon(Icons.star, color: AppColors.leader)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _notificationChannel?.unsubscribe();
    super.dispose();
  }
}
