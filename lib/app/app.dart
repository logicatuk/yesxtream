import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform_info.dart';
import '../data/services/app_settings.dart';
import '../features/player/active_player_registry.dart';
import '../features/player/player_service.dart';
import 'router.dart';
import 'theme.dart';

class YesXtreamApp extends ConsumerStatefulWidget {
  const YesXtreamApp({super.key});

  @override
  ConsumerState<YesXtreamApp> createState() => _YesXtreamAppState();
}

class _YesXtreamAppState extends ConsumerState<YesXtreamApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // Maintain true fullscreen immersive sticky mode across app lifecycle
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      },
      onExitRequested: _handleExitRequested,
      onDetach: _handleDetach,
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<AppExitResponse> _handleExitRequested() async {
    debugPrint('[AppLifecycle] onExitRequested: stopping and disposing all players before exit...');
    try {
      // 1. Dispose the main player service (stops mpv core threads cleanly)
      await ref.read(playerServiceProvider).dispose();
      // 2. Ensure any other players (multi-view, warm pre-buffer) are disposed
      await ActivePlayerRegistry.disposeAll();
      // 3. Small delay to let native mpv core threads exit their run loops cleanly
      await Future.delayed(const Duration(milliseconds: 150));
    } catch (e) {
      debugPrint('[AppLifecycle] Error during exit teardown: $e');
    }
    return AppExitResponse.exit;
  }

  void _handleDetach() {
    debugPrint('[AppLifecycle] onDetach: performing sync teardown...');
    try {
      ref.read(playerServiceProvider).disposeSync();
      ActivePlayerRegistry.disposeAllSync();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);

    return MaterialApp.router(
      title: 'YesXtream',
      debugShowCheckedModeBanner: false,
      theme: YesXtreamTheme.dark,
      routerConfig: router,
      // On Web (LG webOS / Samsung Tizen), _defaultWebShortcuts maps Enter to
      // ButtonActivateIntent and Arrow keys to ScrollIntent, breaking TV remote
      // OK/D-pad activation on FocusableActionDetector tiles and focus traversal.
      shortcuts: kIsWeb
          ? <ShortcutActivator, Intent>{
              ...WidgetsApp.defaultShortcuts,
              const SingleActivator(LogicalKeyboardKey.enter):
                  const ActivateIntent(),
              const SingleActivator(LogicalKeyboardKey.numpadEnter):
                  const ActivateIntent(),
              const SingleActivator(LogicalKeyboardKey.select):
                  const ActivateIntent(),
              const SingleActivator(LogicalKeyboardKey.gameButtonA):
                  const ActivateIntent(),
              const SingleActivator(LogicalKeyboardKey.arrowLeft):
                  const DirectionalFocusIntent(TraversalDirection.left),
              const SingleActivator(LogicalKeyboardKey.arrowRight):
                  const DirectionalFocusIntent(TraversalDirection.right),
              const SingleActivator(LogicalKeyboardKey.arrowUp):
                  const DirectionalFocusIntent(TraversalDirection.up),
              const SingleActivator(LogicalKeyboardKey.arrowDown):
                  const DirectionalFocusIntent(TraversalDirection.down),
            }
          : null,
      builder: (context, child) {
        // Detect TV mode from the first MediaQuery context
        PlatformInfo.detectFromContext(context);

        // ── Global TV Scale ──────────────────────────────────────────────────
        // On LG webOS, Samsung Tizen, and Android TV the canvas is 1920×1080
        // but the physical screen is 55–75", so all widget sizes appear tiny.
        // We override the MediaQuery with a boosted textScaler and apply the
        // same factor to our layout via tvScaleFactor().
        final scale = PlatformInfo.tvScaleFactor(context);
        Widget result = Directionality(
          textDirection: settings.isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
        if (scale > 1.0) {
          final mq = MediaQuery.of(context);
          result = MediaQuery(
            data: mq.copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: Theme(
              data: YesXtreamTheme.scaled(scale),
              child: result,
            ),
          );
        }
        return result;
      },
    );
  }
}

typedef ClubTiviApp = YesXtreamApp;
