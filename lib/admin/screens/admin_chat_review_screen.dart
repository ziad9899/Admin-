import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../data/admin_repository.dart';
import '../widgets/admin_back_button.dart';

/// Three states for the chat review screen:
/// 1. Initial — show a reason prompt + "Open chat" button. The server
///    will refuse the read unless there is an open report on this chat,
///    so we surface that gate to the admin up-front.
/// 2. Loaded — render the messages.
/// 3. Error — server refused (e.g. no_open_report_against_chat).
class AdminChatReviewScreen extends ConsumerStatefulWidget {
  const AdminChatReviewScreen({super.key, required this.chatId});
  final int chatId;

  @override
  ConsumerState<AdminChatReviewScreen> createState() =>
      _AdminChatReviewScreenState();
}

class _AdminChatReviewScreenState extends ConsumerState<AdminChatReviewScreen> {
  final _reason = TextEditingController();
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ref.read(adminRepositoryProvider).openChatForReview(
            chatId: widget.chatId,
            reason: _reason.text.trim(),
          );
      setState(() => _data = res);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat #${widget.chatId}'),
        leading: const AdminBackButton(fallbackPath: '/chats'),
      ),
      body: _data != null
          ? _ChatBody(data: _data!, chatId: widget.chatId)
          : _GatePanel(
              loading: _loading,
              error: _error,
              reasonController: _reason,
              onOpen: _open,
            ),
    );
  }
}

class _GatePanel extends StatelessWidget {
  const _GatePanel({
    required this.loading,
    required this.error,
    required this.reasonController,
    required this.onOpen,
  });
  final bool loading;
  final String? error;
  final TextEditingController reasonController;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.lock_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(
                'Private chat — access requires a reason',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Reading the contents of a 1:1 chat is logged. The server '
                'will refuse unless there is an open or reviewed report '
                'against one of its messages or participants.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason for opening (required)',
                  hintText: 'e.g. investigating harassment report #1234',
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: loading ? null : onOpen,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.visibility),
                label: const Text('Open chat for review'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBody extends StatelessWidget {
  const _ChatBody({required this.data, required this.chatId});
  final Map<String, dynamic> data;
  final int chatId;

  @override
  Widget build(BuildContext context) {
    final aNum = data['user_a_numeric_id'] as int;
    final bNum = data['user_b_numeric_id'] as int;
    final messages = (data['messages'] as List).cast<Map<String, dynamic>>();
    final createdAt = DateTime.parse(data['created_at'] as String);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.amber.shade50,
          child: Row(
            children: [
              const Icon(Icons.warning_amber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Reading messages between #$aNum ↔ #$bNum. '
                  'This access has been recorded in the audit log.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push('/user/$aNum'),
                icon: const Icon(Icons.person, size: 16),
                label: Text('Review #$aNum'),
              ),
              TextButton.icon(
                onPressed: () => context.push('/user/$bNum'),
                icon: const Icon(Icons.person, size: 16),
                label: Text('Review #$bNum'),
              ),
            ],
          ),
        ),
        Expanded(
          child: messages.isEmpty
              ? const Center(child: Text('Chat has no messages.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (ctx, i) {
                    final m = messages[i];
                    return _MessageBubble(
                      message: m,
                      aNum: aNum,
                      bNum: bNum,
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Text(
                'Chat opened ${DateFormat('MMM d, yyyy').format(createdAt.toLocal())} · ${messages.length} messages',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.aNum,
    required this.bNum,
  });
  final Map<String, dynamic> message;
  final int aNum;
  final int bNum;

  @override
  Widget build(BuildContext context) {
    final senderNumeric = message['sender_numeric_id'] as int;
    final body = message['body'] as String;
    final isUserA = message['is_user_a'] as bool;
    final createdAt = DateTime.parse(message['created_at'] as String);
    final reported = message['reported'] as bool? ?? false;

    final align =
        isUserA ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    final color = isUserA ? Colors.blue.shade50 : Colors.green.shade50;
    final senderLabel = '#$senderNumeric ${isUserA ? "(A)" : "(B)"}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.55,
            ),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: reported ? Colors.red.shade50 : color,
                borderRadius: BorderRadius.circular(12),
                border: reported
                    ? Border.all(color: Colors.red.shade200, width: 1)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(senderLabel,
                          style: Theme.of(context).textTheme.labelSmall),
                      if (reported) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.flag,
                            size: 12, color: Colors.red),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  SelectableText(body,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM d HH:mm').format(createdAt.toLocal()),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
