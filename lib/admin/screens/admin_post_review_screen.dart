import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/admin_repository.dart';
import '../widgets/admin_back_button.dart';

final _postProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, id) {
  return ref.read(adminRepositoryProvider).getPostWithContext(id);
});

class AdminPostReviewScreen extends ConsumerWidget {
  const AdminPostReviewScreen({super.key, required this.postId});

  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_postProvider(postId));

    return Scaffold(
      appBar: AppBar(
        title: Text('Post #$postId'),
        leading: const AdminBackButton(),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(_postProvider(postId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrText(e),
        data: (d) => _Body(data: d, postId: postId),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data, required this.postId});

  final Map<String, dynamic> data;
  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = data['post'] as Map<String, dynamic>;
    final comments = (data['comments'] as List).cast<Map<String, dynamic>>();
    final reports = (data['reports'] as List).cast<Map<String, dynamic>>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PostCard(post: post, postId: postId),
        const SizedBox(height: 16),
        _ReportsSection(reports: reports),
        const SizedBox(height: 16),
        _CommentsSection(comments: comments, postId: postId),
      ],
    );
  }
}

class _PostCard extends ConsumerWidget {
  const _PostCard({required this.post, required this.postId});

  final Map<String, dynamic> post;
  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final body = post['body'] as String;
    final status = post['status'] as String;
    final authorStatus = post['author_status'] as String?;
    final authorNumeric = post['author_numeric_id'] as int;
    final score = post['score'] as int;
    final commentsCount = post['comments_count'] as int;
    final tag = post['tag'] as String?;
    final proximity = post['proximity'] as String;
    final createdAt = DateTime.parse(post['created_at'] as String);
    final editedAt = post['edited_at'] != null
        ? DateTime.parse(post['edited_at'] as String)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: () => context.push('/user/$authorNumeric'),
                  child: _Chip(
                    label: '#$authorNumeric',
                    color: authorStatus == 'banned'
                        ? Colors.red.shade100
                        : Colors.green.shade100,
                  ),
                ),
                const SizedBox(width: 6),
                _Chip(label: proximity, color: Colors.blue.shade100),
                if (tag != null) ...[
                  const SizedBox(width: 6),
                  _Chip(label: '#$tag', color: Colors.grey.shade200),
                ],
                const SizedBox(width: 6),
                _Chip(
                  label: status,
                  color: status == 'active'
                      ? Colors.green.shade100
                      : Colors.red.shade100,
                ),
                const Spacer(),
                Text(
                  '↑ $score · 💬 $commentsCount',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(body, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(
              'Posted ${DateFormat('MMM d, yyyy HH:mm').format(createdAt.toLocal())}'
              '${editedAt != null ? " · edited ${DateFormat('MMM d HH:mm').format(editedAt.toLocal())}" : ""}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (status == 'active' || status == 'hidden')
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => _confirmRemove(context, ref),
                    label: const Text('Remove post'),
                  ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.person, size: 18),
                  onPressed: () => context.push('/user/$authorNumeric'),
                  label: Text('Review user #$authorNumeric'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final reason = await _promptReason(context, 'Remove post — reason');
    if (reason == null || !context.mounted) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .removePost(postId: postId, reason: reason);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post removed')),
        );
        // Pop back to where the admin came from (most likely the
        // reports queue). The post is now inert; lingering on this
        // page would just confuse the operator.
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/reports');
        }
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

class _ReportsSection extends StatelessWidget {
  const _ReportsSection({required this.reports});
  final List<Map<String, dynamic>> reports;

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reports against this post (${reports.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final r in reports) _ReportRow(report: r),
          ],
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report});
  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context) {
    final reason = report['reason'] as String;
    final note = report['note'] as String?;
    final status = report['status'] as String;
    final reporter = report['reporter_numeric_id'] as int?;
    final created = DateTime.parse(report['created_at'] as String);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Chip(label: reason, color: Colors.orange.shade100),
          const SizedBox(width: 6),
          _Chip(
            label: status,
            color: status == 'open' ? Colors.red.shade100 : Colors.grey.shade200,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note != null && note.isNotEmpty)
                  Text(note, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  'by #${reporter ?? "?"} · ${DateFormat('MMM d HH:mm').format(created.toLocal())}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentsSection extends ConsumerWidget {
  const _CommentsSection({required this.comments, required this.postId});

  final List<Map<String, dynamic>> comments;
  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (comments.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No comments.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Comments (${comments.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final c in comments)
              _CommentRow(comment: c, postId: postId),
          ],
        ),
      ),
    );
  }
}

class _CommentRow extends ConsumerWidget {
  const _CommentRow({required this.comment, required this.postId});
  final Map<String, dynamic> comment;
  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = comment['id'] as int;
    final body = comment['body'] as String;
    final status = comment['status'] as String;
    final parent = comment['parent_id'] as int?;
    final authorNumeric = comment['author_numeric_id'] as int;
    final created = DateTime.parse(comment['created_at'] as String);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: status != 'active' ? Colors.red.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => context.push('/user/$authorNumeric'),
                child: _Chip(label: '#$authorNumeric', color: Colors.grey.shade200),
              ),
              if (parent != null) ...[
                const SizedBox(width: 6),
                _Chip(label: 'reply', color: Colors.purple.shade100),
              ],
              const SizedBox(width: 6),
              _Chip(
                label: status,
                color: status == 'active'
                    ? Colors.green.shade100
                    : Colors.red.shade100,
              ),
              const Spacer(),
              Text('#$id', style: Theme.of(context).textTheme.labelSmall),
              if (status != 'removed')
                IconButton(
                  iconSize: 18,
                  tooltip: 'Remove comment',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final reason =
                        await _promptReason(context, 'Remove comment — reason');
                    if (reason == null || !context.mounted) return;
                    try {
                      await ref
                          .read(adminRepositoryProvider)
                          .removeComment(commentId: id, reason: reason);
                      ref.invalidate(_postProvider(postId));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Comment removed')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed: $e')),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(body, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            DateFormat('MMM d HH:mm').format(created.toLocal()),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
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
          hintText: 'e.g. profanity, doxxing, spam…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
}

class _ErrText extends StatelessWidget {
  const _ErrText(this.e);
  final Object e;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(e.toString(), textAlign: TextAlign.center),
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
