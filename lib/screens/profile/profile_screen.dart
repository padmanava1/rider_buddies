import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/haptic_service.dart';
import '../../providers/auth_provider.dart';
import 'edit_profile_screen.dart';
import 'dart:convert'; // Added for base64Decode

class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(begin: Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Interval(0.2, 0.8, curve: Curves.easeOut),
          ),
        );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Interval(0.4, 1.0, curve: Curves.elasticOut),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary,
              AppColors.primary.withValues(alpha: 0.8),
              AppColors.secondary,
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Consumer<AuthProvider>(
                builder: (context, authProvider, child) {
                  final user = authProvider.user;
                  final userProfile = authProvider.getUserProfile();

                  return CustomScrollView(
                    slivers: [
                      // App Bar
                      SliverAppBar(
                        expandedHeight: 200,
                        floating: false,
                        pinned: true,
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        flexibleSpace: FlexibleSpaceBar(
                          background: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppColors.primary,
                                  AppColors.primary.withValues(alpha: 0.8),
                                ],
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ScaleTransition(
                                  scale: _scaleAnimation,
                                  child: Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.2),
                                          blurRadius: 20,
                                          offset: Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.person,
                                      size: 60,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  user?.email ?? 'User',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        leading: IconButton(
                          icon: Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () {
                            HapticService.lightImpact();
                            Navigator.pop(context);
                          },
                        ),
                        actions: [
                          IconButton(
                            icon: Icon(Icons.edit, color: Colors.white),
                            onPressed: () {
                              HapticService.selection();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditProfileScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      // Profile Content
                      SliverToBoxAdapter(
                        child: Container(
                          margin: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 20,
                                offset: Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Profile Image Section
                              Container(
                                padding: EdgeInsets.all(24),
                                child: Column(
                                  children: [
                                    GestureDetector(
                                      onTap: () async {
                                        HapticService.mediumImpact();
                                        final authProvider =
                                            Provider.of<AuthProvider>(
                                              context,
                                              listen: false,
                                            );
                                        final imageUrl = await authProvider
                                            .uploadProfileImageBase64();
                                        if (imageUrl != null) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Profile image updated successfully!',
                                              ),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        } else if (authProvider.error != null) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                authProvider.error!,
                                              ),
                                              backgroundColor: Colors.red,
                                            ),
                                          );
                                        }
                                      },
                                      child: Container(
                                        width: 100,
                                        height: 100,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.1,
                                          ),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.primary,
                                            width: 3,
                                          ),
                                        ),
                                        child: Consumer<AuthProvider>(
                                          builder: (context, authProvider, child) {
                                            if (authProvider.isLoading) {
                                              return Center(
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(AppColors.primary),
                                                ),
                                              );
                                            }
                                            return authProvider
                                                        .profileImageUrl !=
                                                    null
                                                ? ClipOval(
                                                    child:
                                                        authProvider
                                                            .profileImageUrl!
                                                            .startsWith('data:')
                                                        ? Image.memory(
                                                            base64Decode(
                                                              authProvider
                                                                  .profileImageUrl!
                                                                  .split(
                                                                    ',',
                                                                  )[1],
                                                            ),
                                                            width: 100,
                                                            height: 100,
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (
                                                                  context,
                                                                  error,
                                                                  stackTrace,
                                                                ) {
                                                                  return Icon(
                                                                    Icons
                                                                        .person,
                                                                    color: AppColors
                                                                        .primary,
                                                                    size: 40,
                                                                  );
                                                                },
                                                          )
                                                        : Image.network(
                                                            authProvider
                                                                .profileImageUrl!,
                                                            width: 100,
                                                            height: 100,
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (
                                                                  context,
                                                                  error,
                                                                  stackTrace,
                                                                ) {
                                                                  return Icon(
                                                                    Icons
                                                                        .person,
                                                                    color: AppColors
                                                                        .primary,
                                                                    size: 40,
                                                                  );
                                                                },
                                                          ),
                                                  )
                                                : Icon(
                                                    Icons.camera_alt,
                                                    color: AppColors.primary,
                                                    size: 40,
                                                  );
                                          },
                                        ),
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Tap to upload photo',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Divider(height: 1),

                              // Profile Information
                              FutureBuilder<Map<String, dynamic>?>(
                                future: userProfile,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }

                                  final profile = snapshot.data;
                                  final name = profile?['name'] ?? 'Not set';
                                  final phone = profile?['phone'] ?? 'Not set';
                                  final email = user?.email ?? 'Not set';

                                  return Column(
                                    children: [
                                      _buildProfileItem(
                                        icon: Icons.person,
                                        title: 'Name',
                                        value: name,
                                        onTap: () {
                                          HapticService.selection();
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  EditProfileScreen(),
                                            ),
                                          );
                                        },
                                      ),
                                      _buildProfileItem(
                                        icon: Icons.email,
                                        title: 'Email',
                                        value: email,
                                        onTap: null,
                                      ),
                                      _buildProfileItem(
                                        icon: Icons.phone,
                                        title: 'Phone',
                                        value: phone,
                                        onTap: () {
                                          HapticService.selection();
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  EditProfileScreen(),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  );
                                },
                              ),

                              Divider(height: 1),

                              // Settings Section
                              Column(
                                children: [
                                  _buildSettingsItem(
                                    icon: Icons.notifications,
                                    title: 'Notifications',
                                    onTap: () {
                                      HapticService.selection();
                                      // TODO: Implement notifications settings
                                    },
                                  ),
                                  _buildSettingsItem(
                                    icon: Icons.security,
                                    title: 'Privacy',
                                    onTap: () {
                                      HapticService.selection();
                                      // TODO: Implement privacy settings
                                    },
                                  ),
                                  _buildSettingsItem(
                                    icon: Icons.help,
                                    title: 'Help & Support',
                                    onTap: () {
                                      HapticService.selection();
                                      // TODO: Implement help & support
                                    },
                                  ),
                                  _buildSettingsItem(
                                    icon: Icons.info,
                                    title: 'About',
                                    onTap: () {
                                      HapticService.selection();
                                      // TODO: Implement about screen
                                    },
                                  ),
                                ],
                              ),

                              SizedBox(height: 24),

                              // Sign Out Button
                              Container(
                                margin: EdgeInsets.symmetric(horizontal: 24),
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    HapticService.warning();
                                    final shouldSignOut = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text('Sign Out'),
                                        content: Text(
                                          'Are you sure you want to sign out?',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: Text('Cancel'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: Text('Sign Out'),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (shouldSignOut == true) {
                                      await authProvider.signOut();
                                      Navigator.of(
                                        context,
                                      ).pushReplacementNamed('/login');
                                    }
                                  },
                                  icon: Icon(Icons.logout),
                                  label: Text('Sign Out'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),

                              SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileItem({
    required IconData icon,
    required String title,
    required String value,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(value, style: TextStyle(color: Colors.grey.shade600)),
      trailing: onTap != null
          ? Icon(Icons.edit, color: AppColors.primary)
          : null,
      onTap: onTap,
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
      trailing: Icon(
        Icons.arrow_forward_ios,
        color: Colors.grey.shade400,
        size: 16,
      ),
      onTap: onTap,
    );
  }
}
