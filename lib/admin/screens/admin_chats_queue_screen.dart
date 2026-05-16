import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/admin_repository.dart';

final _chatsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminRepositoryProvider).listChatsWithOpenReports();
});

class AdminChatsQueueScreen extends ConsumerWidget {
  const AdminChatsQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(_chatsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats with reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(_chatsProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: chats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No private chats currently have an open report.\n\n'
                  'Admins cannot freely browse user DMs. A chat appears here '
                  'only when a participant or third party files a report '
                  'against one of its messages or against a participant.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) => _ChatRow(row: rows[i]),
          );
        },
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final chatId = row['chat_id'] as int;
    final a = row['user_a_numeric_id'] as int;
    final b = row['user_b_numeric_id'] as int;
    final msgCount = row['message_count'] as int;
    final reportCount = row['message_report_count'] as int;
    final reason = row['reason_source'] as String?;
    final lastAt = row['last_message_at'] != null
        ? DateTime.parse(row['last_message_at'] as String)
        : null;

    return ListTile(
      onTap: () => context.push('/chat/$chatId'),
      leading: const Icon(Icons.chat_bubble_outline),
      title: Text('Chat #$chatId — #$a ↔ #$b'),
      subtitle: Text(
        [
          '$msgCount messages',
          if (reportCount > 0) '$reportCount reported',
          if (reason != null) 'source: $reason',
          if (lastAt != null) 'last ${DateFormat('MMM d HH:mm').format(lastAt.toLocal())}',
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
