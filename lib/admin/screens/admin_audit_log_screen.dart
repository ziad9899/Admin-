import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/admin_repository.dart';

final _auditProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminRepositoryProvider).listAuditLog(limit: 200);
});

class AdminAuditLogScreen extends ConsumerWidget {
  const AdminAuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(_auditProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(_auditProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: entries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No moderator actions have been recorded yet.\n\n'
                  'Every ban, post removal, comment removal, report resolution, '
                  'and chat access writes an entry here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) => _AuditRow(row: rows[i]),
          );
        },
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as int;
    final adminEmail = row['admin_email'] as String?;
    final action = row['action'] as String;
    final targetType = row['target_type'] as String?;
    final targetId = row['target_id'];
    final reason = row['reason'] as String?;
    final createdAt = DateTime.parse(row['created_at'] as String);

    return ListTile(
      dense: true,
      leading: _ActionIcon(action: action),
      title: Row(
        children: [
          Text(action, style: Theme.of(context).textTheme.titleSmall),
          if (targetType != null) ...[
            const SizedBox(width: 6),
            Text('· $targetType #${targetId ?? "?"}',
                style: Theme.of(context).textTheme.labelSmall),
          ],
          const Spacer(),
          Text('#$id', style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
      subtitle: Text(
        [
          'by ${adminEmail ?? "(deleted admin)"}',
          if (reason != null && reason.isNotEmpty) reason,
          DateFormat('MMM d, yyyy HH:mm:ss').format(createdAt.toLocal()),
        ].join(' · '),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.action});
  final String action;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (action) {
      'ban_user' => (Icons.block, Colors.red),
      'unban_user' => (Icons.lock_open, Colors.green),
      'remove_post' => (Icons.delete, Colors.orange),
      'remove_comment' => (Icons.delete_outline, Colors.orange),
      'resolve_report' => (Icons.check_circle_outline, Colors.blue),
      'open_chat_for_review' => (Icons.visibility, Colors.purple),
      _ => (Icons.history, Colors.grey),
    };
    return CircleAvatar(
      radius: 14,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(icon, size: 14, color: color),
    );
  }
}
