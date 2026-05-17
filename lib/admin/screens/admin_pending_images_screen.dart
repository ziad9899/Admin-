import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/admin_repository.dart';

/// Queue of image attachments awaiting moderation. Each card shows
/// the image, the post body, and approve / reject buttons. Approving
/// makes the image visible in the consumer feed; rejecting removes
/// both the image and the parent post. Both actions write an entry
/// to mod_audit_log via the server RPC.
final pendingImagesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.read(adminRepositoryProvider).listPendingImages(limit: 100);
});

final _signedUrlProvider =
    FutureProvider.autoDispose.family<String, String>((ref, path) {
  return ref.read(adminRepositoryProvider).postImageSignedUrl(path);
});

class AdminPendingImagesScreen extends ConsumerWidget {
  const AdminPendingImagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingImagesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending images'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(pendingImagesProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: pending.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No images awaiting review.\n\n'
                  'New photo posts will land here until they\'re approved. '
                  'Aim for under 24 hours per Apple Guideline 1.2.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return LayoutBuilder(
            builder: (ctx, cons) {
              // Two columns on wide windows so moderators see more
              // images at a glance. Single column otherwise.
              final cross = cons.maxWidth >= 900 ? 2 : 1;
              return GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cross,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.55,
                ),
                itemCount: rows.length,
                itemBuilder: (ctx, i) => _PendingImageCard(row: rows[i]),
              );
            },
          );
        },
      ),
    );
  }
}

class _PendingImageCard extends ConsumerWidget {
  const _PendingImageCard({required this.row});
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postId = row['post_id'] as int;
    final storagePath = row['storage_path'] as String;
    final body = row['body'] as String;
    final tag = row['tag'] as String?;
    final authorNumeric = row['author_numeric_id'] as int;
    final byteSize = row['byte_size'] as int?;
    final createdAt = DateTime.parse(row['created_at'] as String);

    final age = DateTime.now().difference(createdAt);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _ImagePreview(storagePath: storagePath)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () => context.push('/user/$authorNumeric'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('#$authorNumeric',
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                    if (tag != null && tag.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('#$tag',
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                    const Spacer(),
                    _AgeChip(age: age),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (byteSize != null) '${(byteSize / 1024).round()} KB',
                    DateFormat('MMM d, HH:mm').format(createdAt.toLocal()),
                  ].join(' · '),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          foregroundColor: Colors.red.shade900,
                        ),
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => _confirmReject(context, ref, postId),
                        label: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.check, size: 18),
                        onPressed: () => _approve(context, ref, postId),
                        label: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approve(
    BuildContext context,
    WidgetRef ref,
    int postId,
  ) async {
    try {
      await ref.read(adminRepositoryProvider).approveImage(postId: postId);
      ref.invalidate(pendingImagesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Post #$postId approved')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approve failed: $e')),
        );
      }
    }
  }

  Future<void> _confirmReject(
    BuildContext context,
    WidgetRef ref,
    int postId,
  ) async {
    final reason = await _promptReason(context);
    if (reason == null || reason.length < 3 || !context.mounted) return;
    try {
      await ref
          .read(adminRepositoryProvider)
          .rejectImage(postId: postId, reason: reason);
      ref.invalidate(pendingImagesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Post #$postId rejected')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reject failed: $e')),
        );
      }
    }
  }
}

Future<String?> _promptReason(BuildContext context) async {
  final ctl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reject image — reason'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'e.g. nudity, hate symbols, doxxing, KSA prohibited',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
          child: const Text('Reject + remove post'),
        ),
      ],
    ),
  );
}

class _ImagePreview extends ConsumerWidget {
  const _ImagePreview({required this.storagePath});
  final String storagePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(_signedUrlProvider(storagePath));
    return url.when(
      loading: () => Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (e, _) => Container(
        color: Colors.red.shade50,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined),
      ),
      data: (u) => Image.network(
        u,
        fit: BoxFit.cover,
        errorBuilder: (ctx, _, _) => Container(
          color: Colors.red.shade50,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}

class _AgeChip extends StatelessWidget {
  const _AgeChip({required this.age});
  final Duration age;
  @override
  Widget build(BuildContext context) {
    final color = age.inHours >= 24
        ? Colors.red
        : age.inHours >= 4
            ? Colors.orange
            : Colors.green;
    final label = age.inMinutes < 60
        ? '${age.inMinutes}m'
        : age.inHours < 24
            ? '${age.inHours}h'
            : '${age.inDays}d';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
