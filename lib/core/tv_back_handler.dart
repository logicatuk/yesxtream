import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Ensures Samsung Tizen Return (`Escape`), LG webOS Back (`Escape`), and
/// Android/Fire TV Back (`GoBack`) return cleanly from sub-screens when inner
/// modals/inputs do not consume the key.
class TvBackHandler extends StatelessWidget {
  final Widget child;
  final String fallbackRoute;

  const TvBackHandler({
    super.key,
    required this.child,
    this.fallbackRoute = '/home',
  });

  void _handleBack(BuildContext context) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallbackRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack(context);
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _handleBack(context),
          const SingleActivator(LogicalKeyboardKey.goBack): () =>
              _handleBack(context),
        },
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: child,
        ),
      ),
    );
  }
}
