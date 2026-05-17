import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// AppBar back arrow that pops if there's a stack, otherwise routes to
/// a sensible fallback (defaults to /reports). Used by every detail
/// screen so the back button always lands the operator somewhere
/// actionable, including when arriving via a refreshed deep link.
class AdminBackButton extends StatelessWidget {
  const AdminBackButton({super.key, this.fallbackPath = '/reports'});

  final String fallbackPath;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(fallbackPath);
        }
      },
    );
  }
}
