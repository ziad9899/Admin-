import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Auth state stream — emits whenever a sign-in / sign-out happens.
/// Used by go_router's refreshListenable for the redirect gate.
final adminAuthStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

/// Current session, or null if signed out.
final adminSessionProvider = Provider<Session?>((ref) {
  ref.watch(adminAuthStateProvider);
  return Supabase.instance.client.auth.currentSession;
});

/// Whether the current signed-in user is in `admin_users`. Calls
/// `_is_admin(auth.uid())` server-side; null while loading; false
/// either when not signed in or when the user is not an admin.
final isCurrentUserAdminProvider = FutureProvider<bool>((ref) async {
  final session = ref.watch(adminSessionProvider);
  if (session == null) return false;
  final res = await Supabase.instance.client.rpc(
    '_is_admin',
    params: {'p_uid': session.user.id},
  );
  return res == true;
});

class AdminAuthRepository {
  AdminAuthRepository(this._client);
  final SupabaseClient _client;

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}

final adminAuthRepositoryProvider = Provider<AdminAuthRepository>((ref) {
  return AdminAuthRepository(Supabase.instance.client);
});
