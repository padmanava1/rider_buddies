import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/env_config.dart';

/// Supabase service wrapper for centralized client access
class SupabaseService {
  static SupabaseClient? _client;

  /// Get the Supabase client instance
  /// Throws if not initialized
  static SupabaseClient get client {
    if (_client == null) {
      throw Exception('Supabase not initialized. Call initialize() first.');
    }
    return _client!;
  }

  /// Initialize Supabase with credentials from environment
  static Future<void> initialize() async {
    if (!EnvConfig.isSupabaseConfigured) {
      throw Exception(
        'Supabase not configured. Please update .env file with your Supabase credentials.',
      );
    }

    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
    _client = Supabase.instance.client;
  }

  /// Get the current authenticated user
  static User? get currentUser => _client?.auth.currentUser;

  /// Check if a user is authenticated
  static bool get isAuthenticated => currentUser != null;

  /// Get the current session
  static Session? get currentSession => _client?.auth.currentSession;

  /// Stream of auth state changes
  static Stream<AuthState> get authStateChanges =>
      _client?.auth.onAuthStateChange ?? const Stream.empty();

  /// Sign out the current user
  static Future<void> signOut() async {
    await _client?.auth.signOut();
  }
}
