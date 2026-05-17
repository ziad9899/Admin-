import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth/admin_auth.dart';
import 'screens/admin_audit_log_screen.dart';
import 'screens/admin_chat_review_screen.dart';
import 'screens/admin_chats_queue_screen.dart';
import 'screens/admin_login_screen.dart';
import 'screens/admin_pending_images_screen.dart';
import 'screens/admin_post_review_screen.dart';
import 'screens/admin_reports_queue_screen.dart';
import 'screens/admin_shell.dart';
import 'screens/admin_user_review_screen.dart';

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_adminRouterProvider);
    return MaterialApp.router(
      title: 'Qurb Admin',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD84D),
          brightness: Brightness.light,
        ),
        visualDensity: VisualDensity.compact,
      ),
      routerConfig: router,
    );
  }
}

final _adminRouterProvider = Provider<GoRouter>((ref) {
  // The router itself is built once; auth-driven re-evaluation of the
  // `redirect` happens via the _AuthListenable wired into
  // refreshListenable, not by rebuilding this provider (which would
  // throw away router state).
  return GoRouter(
    initialLocation: '/reports',
    refreshListenable: _AuthListenable(ref),
    redirect: (context, state) {
      final session = ref.read(adminSessionProvider);
      final loggingIn = state.matchedLocation == '/login';
      if (session == null) return loggingIn ? null : '/login';
      if (loggingIn) return '/reports';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const AdminLoginScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => AdminShell(
          location: state.matchedLocation,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/reports',
            builder: (context, state) => const AdminReportsQueueScreen(),
          ),
          GoRoute(
            path: '/chats',
            builder: (context, state) => const AdminChatsQueueScreen(),
          ),
          GoRoute(
            path: '/images',
            builder: (context, state) => const AdminPendingImagesScreen(),
          ),
          GoRoute(
            path: '/audit',
            builder: (context, state) => const AdminAuditLogScreen(),
          ),
          GoRoute(
            path: '/post/:id',
            builder: (context, state) => AdminPostReviewScreen(
              postId: int.parse(state.pathParameters['id']!),
            ),
          ),
          GoRoute(
            path: '/user/:numericId',
            builder: (context, state) => AdminUserReviewScreen(
              numericId: int.parse(state.pathParameters['numericId']!),
            ),
          ),
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) => AdminChatReviewScreen(
              chatId: int.parse(state.pathParameters['id']!),
            ),
          ),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod's AsyncValue stream to a ChangeNotifier so go_router
/// re-evaluates `redirect` whenever auth changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _sub = _ref.listen<AsyncValue<dynamic>>(
      adminAuthStateProvider,
      (_, _) => notifyListeners(),
    );
  }
  final Ref _ref;
  late final ProviderSubscription<AsyncValue<dynamic>> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
