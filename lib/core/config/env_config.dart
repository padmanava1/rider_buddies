import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Environment configuration loader
/// Loads API keys and service URLs from .env file
class EnvConfig {
  /// Supabase project URL
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';

  /// Supabase anonymous key for client-side access
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  /// Ola Maps API key
  static String get olaMapsApiKey => dotenv.env['OLA_MAPS_API_KEY'] ?? '';

  /// Google OAuth client IDs
  static String get googleWebClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
  static String get googleIosClientId => dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? '';

  /// Load environment variables from .env file
  static Future<void> load() async {
    await dotenv.load(fileName: ".env");
  }

  /// Check if Supabase is properly configured
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      !supabaseUrl.contains('your-project');

  /// Check if Ola Maps is properly configured
  static bool get isOlaMapsConfigured =>
      olaMapsApiKey.isNotEmpty && olaMapsApiKey != 'YOUR_OLA_MAPS_API_KEY';
}
