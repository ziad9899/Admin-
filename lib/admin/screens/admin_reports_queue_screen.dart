import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/admin_repository.dart';

final _statusFilterProvider = StateProvider<String?>((_) => 'open');

final reportsQueueProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final status = ref.watch(_statusFilterProvider);
  return ref.read(adminRepositoryProvider).listReports(
        status: status,
        limit: 100,
      );
});

class AdminReportsQueueScreen extends ConsumerWidget {
  const AdminReportsQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportsQueueProvider);
    final status = ref.watch(_statusFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports queue'),
        actions: [
          PopupMenuButton<String?>(
            tooltip: 'Status filter',
            initialValue: status,
            icon: const Icon(Icons.filter_alt_outlined),
            onSelected: (v) =>
                ref.read(_statusFilterProvider.notifier).state = v,
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'open', child: Text('Open')),
              PopupMenuItem(value: 'reviewed', child: Text('Reviewed')),
              PopupMenuItem(value: 'dismissed', child: Text('Dismissed')),
              PopupMenuItem(value: null, child: Text('All')),
            ],
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(reportsQueueProvider),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: reports.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorPanel(
            error: e, onRetry: () => ref.invalidate(reportsQueueProvider)),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No reports match the current filter.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) => _ReportTile(report: rows[i]),
          );
        },
      ),
    );
  }
}

/// One row in the reports queue. The tappable body is in its own
/// InkWell column, separate from the quick-actions PopupMenu column,
/// so the two gestures never fight: tapping the three-dot menu
/// never accidentally opens the target.
class _ReportTile extends ConsumerWidget {
  const _ReportTile({required this.report});

  final Map<String, dynamic> report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = report['id'] as int;
    final targetType = report['target_type'] as String;
    final targetId = report['target_id'] as int?;
    final targetNumeric = report['target_numeric_id'] as int?;
    final reporterNumeric = report['reporter_numeric_id'] as int?;
    final reason = report['reason'] as String;
    final note = report['note'] as String?;
    final status = report['status'] as String;
    final preview = report['target_preview'] as String?;
    final postId = report['post_id'] as int?;
    final chatId = report['chat_id'] as int?;
    final createdAt = DateTime.parse(report['created_at'] as String);

    final age = DateTime.now().difference(createdAt);
    final ageStr = _humanAge(age);

    final destination =
        _routeFor(targetType, targetId, targetNumeric, postId, chatId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SeverityDot(age: age),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: destination == null
                  ? null
                  : () => context.push(destination),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Chip(
                          label: targetType,
                          color: _typeColor(targetType),
                        ),
                        const SizedBox(width: 6),
                        _Chip(label: reason, color: Colors.orange.shade100),
                        const SizedBox(width: 6),
                        _Chip(
                          label: status,
                          color: status == 'open'
                              ? Colors.red.shade100
                              : Colors.grey.shade200,
                        ),
                        const Spacer(),
                        Text('#$id',
                            style: Theme.of(context).textTheme.labelSmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (preview != null && preview.isNotEmpty)
                      Text(
                        preview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    if (note != null && note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Reporter note: $note',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'By #${reporterNumeric ?? "?"} → #${targetNumeric ?? "?"} · $ageStr · ${DateFormat('MMM d, HH:mm').format(createdAt.toLocal())}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (status == 'open') _QuickActionsMenu(reportId: id),
        ],
      ),
    );
  }

  String? _routeFor(
    String type,
    int? targetId,
    int? numericId,
    int? postId,
    int? chatId,
  ) {
    switch (type) {
      case 'post':
        return targetId != null ? '/post/$targetId' : null;
      case 'comment':
        // Land on the post containing the comment so the admin sees
        // the full thread and can act on the comment from there.
        return postId != null ? '/post/$postId' : null;
      case 'user':
        return numericId != null ? '/user/$numericId' : null;
      case 'message':
        // Land on the chat containing the reported message. The
        // /chat screen prompts for a reason, then renders the
        // messages with the reported ones flagged.
        return chatId != null ? '/chat/$chatId' : null;
    }
    return null;
  }

  String _humanAge(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m old';
    if (d.inHours < 24) return '${d.inHours}h old';
    return '${d.inDays}d old';
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'post':
        return Colors.blue.shade100;
      case 'comment':
        return Colors.purple.shade100;
      case 'user':
        return Colors.red.shade100;
      case 'message':
        return Colors.teal.shade100;
      default:
        return Colors.grey.shade200;
    }
  }
}

class _SeverityDot extends StatelessWidget {
  const _SeverityDot({required this.age});
  final Duration age;

  @override
  Widget build(BuildContext context) {
    final color = age.inHours >= 24
        ? Colors.red
        : age.inHours >= 4
            ? Colors.orange
            : Colors.green;
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
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

class _QuickActionsMenu extends ConsumerWidget {
  const _QuickActionsMenu({required this.reportId});
  final int reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Quick action',
      icon: const Icon(Icons.more_vert),
      onSelected: (action) async {
        try {
          await ref.read(adminRepositoryProvider).resolveReport(
                reportId: reportId,
                action: action,
              );
          ref.invalidate(reportsQueueProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Report #$reportId marked $action')),
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
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'reviewed', child: Text('Mark reviewed')),
        PopupMenuItem(value: 'dismissed', child: Text('Dismiss')),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 48),
            const SizedBox(height: 12),
            Text(error.toString(), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
