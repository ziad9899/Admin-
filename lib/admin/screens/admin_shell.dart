import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/admin_auth.dart';

/// Top-level layout: a persistent left NavigationRail + the routed
/// child on the right. The rail stays visible on every authenticated
/// route — including detail pages — so the operator can switch tabs
/// without back-buttoning out of a deep view first.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider);
    final email = session?.user.email ?? '';
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: MediaQuery.of(context).size.width >= 900,
            selectedIndex: _indexFor(location),
            onDestinationSelected: (i) {
              switch (i) {
                case 0:
                  context.go('/reports');
                case 1:
                  context.go('/chats');
                case 2:
                  context.go('/images');
                case 3:
                  context.go('/audit');
              }
            },
            leading: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    child: const Text('Q'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Qurb Admin',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ],
              ),
            ),
            trailing: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Tooltip(
                    message: email,
                    child: const Icon(Icons.person_outline, size: 20),
                  ),
                  const SizedBox(height: 8),
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: () async {
                      await ref.read(adminAuthRepositoryProvider).signOut();
                    },
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.report_outlined),
                selectedIcon: Icon(Icons.report),
                label: Text('Reports'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: Text('Chats'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.image_search_outlined),
                selectedIcon: Icon(Icons.image_search),
                label: Text('Pending images'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: Text('Audit log'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  // When the operator is deep in a detail page (e.g. /post/123 or
  // /chat/45 or /images), the rail keeps the most logical queue
  // highlighted. Detail routes that have no obvious queue default
  // to Reports.
  int _indexFor(String loc) {
    if (loc.startsWith('/chats') || loc.startsWith('/chat/')) return 1;
    if (loc.startsWith('/images')) return 2;
    if (loc.startsWith('/audit')) return 3;
    return 0;
  }
}
