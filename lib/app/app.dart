import 'dart:ui';
import 'package:flutter/material.dart';
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
    _lifecycleListener = AppLifecycleListener(
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
      builder: (context, child) {
        // Detect TV mode from the first MediaQuery context
        PlatformInfo.detectFromContext(context);
        return Directionality(
          textDirection: settings.isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

typedef ClubTiviApp = YesXtreamApp;
