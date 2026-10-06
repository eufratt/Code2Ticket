import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provides access to the Supabase client instance.
/// Used purely for direct PostgreSQL queries and real-time database access,
/// NOT for 3rd party authentication services.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
