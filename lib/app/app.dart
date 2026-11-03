import 'package:flutter/material.dart';

import '../core/platform_info.dart';
import 'router.dart';
import 'theme.dart';

class YesXtreamApp extends StatelessWidget {
  const YesXtreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'YesXtream',
      debugShowCheckedModeBanner: false,
      theme: YesXtreamTheme.dark,
      routerConfig: router,
      builder: (context, child) {
        // Detect TV mode from the first MediaQuery context
        PlatformInfo.detectFromContext(context);
        return child ?? const SizedBox.shrink();
      },
    );
  }
}

typedef ClubTiviApp = YesXtreamApp;
