import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../core/services/haptic_service.dart';
import '../../core/theme/app_colors.dart';
import 'group_status_screen.dart';

class JoinGroupScreen extends StatefulWidget {
  final String mode;
  const JoinGroupScreen({required this.mode});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  final TextEditingController _codeController = TextEditingController();
  String? errorText;
  bool isLoading = false;
  bool showScanner = false;

  Future<void> _joinGroup(String code) async {
    setState(() {
      isLoading = true;
      errorText = null;
    });

    final groupProvider = Provider.of<GroupProvider>(context, listen: false);
    final success = await groupProvider.joinGroup(code);

    if (success) {
      // Navigate to group status screen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              GroupStatusScreen(groupCode: groupProvider.activeGroupCode!),
        ),
      );
    } else {
      setState(() {
        errorText = groupProvider.error ?? 'Failed to join group';
        isLoading = false;
      });
    }
  }

  void _onQRViewCreated(QRViewController controller) {
    controller.scannedDataStream.listen((scanData) {
      controller.pauseCamera();
      setState(() {
        showScanner = false;
        _codeController.text = scanData.code ?? '';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Join Group', style: theme.textTheme.titleLarge),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      body: showScanner
          ? Column(
              children: [
                Expanded(
                  child: QRView(
                    key: GlobalKey(debugLabel: 'QR'),
                    onQRViewCreated: _onQRViewCreated,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => showScanner = false),
                  child: Text('Cancel'),
                ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 24.0,
                vertical: 32.0,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Enter group code or scan QR:',
                    style: theme.textTheme.bodyLarge,
                  ),
                  SizedBox(height: 16),
                  TextField(
                    controller: _codeController,
                    decoration: InputDecoration(
                      labelText: 'Group Code',
                      errorText: errorText,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: Icon(Icons.qr_code_scanner),
                    label: Text('Scan QR Code'),
                    onPressed: () => setState(() => showScanner = true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 32,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  SizedBox(height: 24),
                  isLoading
                      ? CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: () {
                            final code = _codeController.text
                                .trim()
                                .toUpperCase();
                            if (code.isEmpty) {
                              setState(
                                () => errorText = 'Please enter a code.',
                              );
                              return;
                            }
                            _joinGroup(code);
                          },
                          child: Text('Join Group'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 32,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                ],
              ),
            ),
    );
  }
}
