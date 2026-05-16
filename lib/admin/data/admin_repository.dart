import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around every admin_* RPC. Returns Dart maps/lists
/// straight from the Supabase response — the screens shape them.
///
/// All RPCs are SECURITY DEFINER and gated server-side by
/// `_is_admin(auth.uid())`, so a non-admin signed-in user will get
/// `not_authorized` from PostgrestException.code='P0001' (raise).
class AdminRepository {
  AdminRepository(this._client);
  final SupabaseClient _client;

  // ---- Reports -----------------------------------------------------------

  /// Returns rows: id, reporter_numeric_id, target_type, target_id,
  /// target_numeric_id, reason, note, status, created_at, target_preview.
  Future<List<Map<String, dynamic>>> listReports({
    String? status = 'open',
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _client.rpc('admin_list_reports', params: {
      'p_status': status,
      'p_limit': limit,
      'p_offset': offset,
    });
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> resolveReport({
    required int reportId,
    required String action, // 'reviewed' | 'dismissed'
    String? note,
  }) async {
    await _client.rpc('admin_resolve_report', params: {
      'p_report_id': reportId,
      'p_action': action,
      'p_note': note,
    });
  }

  // ---- Post / comment review --------------------------------------------

  Future<Map<String, dynamic>> getPostWithContext(int postId) async {
    final res = await _client.rpc(
      'admin_get_post_with_context',
      params: {'p_post_id': postId},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> removePost({required int postId, required String reason}) async {
    await _client.rpc('admin_remove_post', params: {
      'p_post_id': postId,
      'p_reason': reason,
    });
  }

  Future<void> removeComment({
    required int commentId,
    required String reason,
  }) async {
    await _client.rpc('admin_remove_comment', params: {
      'p_comment_id': commentId,
      'p_reason': reason,
    });
  }

  // ---- User review ------------------------------------------------------

  Future<Map<String, dynamic>> getUserSummary(int numericId) async {
    final res = await _client.rpc(
      'admin_get_user_summary',
      params: {'p_numeric_id': numericId},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  Future<void> banUser({required int numericId, required String reason}) async {
    await _client.rpc('admin_ban_user', params: {
      'p_numeric_id': numericId,
      'p_reason': reason,
    });
  }

  Future<void> unbanUser({
    required int numericId,
    required String reason,
  }) async {
    await _client.rpc('admin_unban_user', params: {
      'p_numeric_id': numericId,
      'p_reason': reason,
    });
  }

  // ---- Chats / whispers -------------------------------------------------

  Future<List<Map<String, dynamic>>> listChatsWithOpenReports({
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _client.rpc(
      'admin_list_chats_with_open_reports',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Server refuses with `no_open_report_against_chat` unless there is
  /// at least one open or reviewed report tied to this chat. Audit log
  /// is written even on the failure path? No — the audit only writes on
  /// the happy path inside the RPC. The failed call returns immediately.
  Future<Map<String, dynamic>> openChatForReview({
    required int chatId,
    required String reason,
  }) async {
    final res = await _client.rpc('admin_open_chat_for_review', params: {
      'p_chat_id': chatId,
      'p_reason': reason,
    });
    return Map<String, dynamic>.from(res as Map);
  }

  // ---- Audit log + admin roster -----------------------------------------

  Future<List<Map<String, dynamic>>> listAuditLog({
    int limit = 100,
    int offset = 0,
  }) async {
    final rows = await _client.rpc(
      'admin_list_audit_log',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> listAdmins() async {
    final rows = await _client.rpc('admin_list_admins');
    return (rows as List).cast<Map<String, dynamic>>();
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(Supabase.instance.client);
});
