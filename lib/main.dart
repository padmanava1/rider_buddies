import 'package:flutter/material.dart';
import 'app.dart';
import 'core/config/env_config.dart';
import 'core/services/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await EnvConfig.load();

  // Initialize Supabase
  await SupabaseService.initialize();

  runApp(RideBuddiesApp());
}
