import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin/admin_app.dart';
import 'core/config/supabase_config.dart';

/// Entry point for the Qurb admin web console.
///
/// Run locally:
///   flutter run -d chrome
///
/// Build for production:
///   flutter build web --release
///
/// This is a SEPARATE binary from the main Qurb app. It uses the same
/// Supabase project but signs in with email/password (the main app
/// uses anonymous sign-in). The admin allow-list is enforced by the
/// `_is_admin(auth.uid())` gate inside every admin_* RPC, so even if
/// a non-admin user accidentally signs in here they get
/// `not_authorized` from every action.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    debug: false,
  );

  runApp(const ProviderScope(child: AdminApp()));
}
