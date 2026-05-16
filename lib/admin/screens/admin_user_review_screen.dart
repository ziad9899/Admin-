import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/admin_repository.dart';

final _userProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) {
  return ref.read(adminRepositoryProvider).getUserSummary(id);
});

class AdminUserReviewScreen extends ConsumerWidget {
  const AdminUserReviewScreen({super.key, required this.numericId});
  final int numericId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_userProvider(numericId));
    return Scaffold(
      appBar: AppBar(
        title: Text('User #$numericId'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/reports'),
        ),
        actions: [
          IconButton(
            onPressed: () => ref.invalidate(_userProvider(numericId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (d) => _Body(data: d, numericId: numericId),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data, required this.numericId});
  final Map<String, dynamic> data;
  final int numericId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = data['profile'] as Map<String, dynamic>;
    final posts = (data['posts'] as List).cast<Map<String, dynamic>>();
    final comments = (data['comments'] as List).cast<Map<String, dynamic>>();
    final reportsAgainst =
        (data['reports_against'] as List).cast<Map<String, dynamic>>();
    final reportsFiledCount = data['reports_filed_count'] as int;
    final chatsCount = data['chats_count'] as int;

    final isBanned = profile['status'] == 'banned';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: isBanned ? Colors.red.shade50 : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(child: Text('#$numericId')),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#$numericId',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Row(
                            children: [
                              _Chip(
                                label: profile['status'] as String,
                                color: isBanned
                                    ? Colors.red.shade200
                                    : Colors.green.shade100,
                              ),
                              const SizedBox(width: 6),
                              if (profile['city_code'] != null)
                                _Chip(
                                  label: profile['city_code'] as String,
                                  color: Colors.blue.shade100,
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Joined ${DateFormat('MMM d, yyyy').format(DateTime.parse(profile['created_at'] as String).toLocal())} · '
                            'last seen ${DateFormat('MMM d HH:mm').format(DateTime.parse(profile['last_seen_at'] as String).toLocal())}',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    if (!isBanned)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor: Theme.of(context).colorScheme.onError,
                        ),
                        icon: const Icon(Icons.block, size: 18),
                        onPressed: () => _confirmBan(context, ref),
                        label: const Text('Ban user'),
                      ),
                    if (isBanned)
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.lock_open, size: 18),
                        onPressed: () => _confirmUnban(context, ref),
                        label: const Text('Unban user'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _StatsRow(
          posts: posts.length,
          comments: comments.length,
          reportsAgainst: reportsAgainst.length,
          reportsFiled: reportsFiledCount,
          chats: chatsCount,
        ),
        const SizedBox(height: 16),
        if (reportsAgainst.isNotEmpty) ...[
          _SectionHeader('Reports against (${reportsAgainst.length})'),
          for (final r in reportsAgainst) _ReportRow(report: r),
          const SizedBox(height: 16),
        ],
        if (posts.isNotEmpty) ...[
          _SectionHeader('Posts (${posts.length})'),
          for (final p in posts) _PostRow(post: p),
          const SizedBox(height: 16),
        ],
        if (comments.isNotEmpty) ...[
          _SectionHeader('Comments (${comments.length})'),
          for (final c in comments) _CommentRow(comment: c),
        ],
      ],
    );
  }

  Future<void> _confirmBan(BuildContext context, WidgetRef ref) async {
    final reason = await _promptReason(context, 'Ban user — reason');
    if (reason == null || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm ban'),
        content: Text(
            'Ban user #$numericId? All their active posts will be marked removed. They cannot post, comment, or send messages until unbanned.\n\nReason: $reason'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ban'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .banUser(numericId: numericId, reason: reason);
      ref.invalidate(_userProvider(numericId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User #$numericId banned')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  Future<void> _confirmUnban(BuildContext context, WidgetRef ref) async {
    final reason = await _promptReason(context, 'Unban user — reason');
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .unbanUser(numericId: numericId, reason: reason);
      ref.invalidate(_userProvider(numericId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User #$numericId unbanned')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({
    required this.posts,
    required this.comments,
    required this.reportsAgainst,
    required this.reportsFiled,
    required this.chats,
  });
  final int posts;
  final int comments;
  final int reportsAgainst;
  final int reportsFiled;
  final int chats;

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, int n) => Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text('$n',
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
        );
    return Row(children: [
      tile('Posts', posts),
      tile('Comments', comments),
      tile('Reports vs', reportsAgainst),
      tile('Reports by', reportsFiled),
      tile('Chats', chats),
    ]);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report});
  final Map<String, dynamic> report;
  @override
  Widget build(BuildContext context) {
    final reason = report['reason'] as String;
    final note = report['note'] as String?;
    final status = report['status'] as String;
    final targetType = report['target_type'] as String;
    final created = DateTime.parse(report['created_at'] as String);
    final reporter = report['reporter_numeric_id'] as int?;
    return Card(
      child: ListTile(
        title: Text('$reason · target=$targetType'),
        subtitle: Text(
          [
            if (note != null) note,
            'by #${reporter ?? "?"} · ${DateFormat('MMM d HH:mm').format(created.toLocal())} · $status',
          ].join('\n'),
        ),
      ),
    );
  }
}

class _PostRow extends StatelessWidget {
  const _PostRow({required this.post});
  final Map<String, dynamic> post;
  @override
  Widget build(BuildContext context) {
    final id = post['id'] as int;
    final body = post['body'] as String;
    final status = post['status'] as String;
    final created = DateTime.parse(post['created_at'] as String);
    return Card(
      color: status != 'active' ? Colors.red.shade50 : null,
      child: ListTile(
        onTap: () => context.push('/post/$id'),
        title: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            'Post #$id · $status · ${DateFormat('MMM d HH:mm').format(created.toLocal())}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment});
  final Map<String, dynamic> comment;
  @override
  Widget build(BuildContext context) {
    final id = comment['id'] as int;
    final postId = comment['post_id'] as int;
    final body = comment['body'] as String;
    final status = comment['status'] as String;
    final created = DateTime.parse(comment['created_at'] as String);
    return Card(
      color: status != 'active' ? Colors.red.shade50 : null,
      child: ListTile(
        onTap: () => context.push('/post/$postId'),
        title: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
            'Comment #$id · on post #$postId · $status · ${DateFormat('MMM d HH:mm').format(created.toLocal())}'),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

Future<String?> _promptReason(BuildContext context, String title) async {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'e.g. repeated harassment after warnings',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}
