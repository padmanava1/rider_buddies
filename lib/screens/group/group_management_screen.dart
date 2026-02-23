import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/haptic_service.dart';
import '../../providers/group_provider.dart';
import '../../core/theme/app_colors.dart';
import 'join_group_screen.dart';
import 'group_status_screen.dart';

class GroupManagementScreen extends StatelessWidget {
  final String mode;
  const GroupManagementScreen({required this.mode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Group Management', style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Mode: $mode', style: theme.textTheme.bodyLarge),
            SizedBox(height: 32),
            ElevatedButton.icon(
              icon: Icon(Icons.group_add),
              label: Text('Create Group'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 18),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              onPressed: () async {
                HapticService.mediumImpact();
                final groupProvider = Provider.of<GroupProvider>(
                  context,
                  listen: false,
                );
                final success = await groupProvider.createGroup(mode);

                if (success) {
                  // Navigate to group status screen
                  Navigator.pushReplacement(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          GroupStatusScreen(
                            groupCode: groupProvider.activeGroupCode!,
                          ),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                            return SlideTransition(
                              position:
                                  Tween<Offset>(
                                    begin: Offset(1.0, 0.0),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: Curves.easeInOut,
                                    ),
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
                      content: Text(
                        groupProvider.error ?? 'Failed to create group',
                      ),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  );
                }
              },
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              icon: Icon(Icons.qr_code_scanner),
              label: Text('Join Group'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 18),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              onPressed: () {
                HapticService.mediumImpact();
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        JoinGroupScreen(mode: mode),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return SlideTransition(
                            position:
                                Tween<Offset>(
                                  begin: Offset(1.0, 0.0),
                                  end: Offset.zero,
                                ).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeInOut,
                                  ),
                                ),
                            child: child,
                          );
                        },
                    transitionDuration: Duration(milliseconds: 300),
                  ),
                );
              },
            ),
            SizedBox(height: 24),
            OutlinedButton(
              child: Text('Skip'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
              ),
              onPressed: () {
                HapticService.lightImpact();
                // TODO: Skip group and proceed
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Skipping group creation'),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
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
