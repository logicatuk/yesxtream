import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yesxtream/app/app.dart';
import 'package:yesxtream/core/platform_info.dart';
import 'package:yesxtream/data/datasources/local/database.dart' as db;
import 'package:yesxtream/features/home/home_screen.dart';
import 'package:yesxtream/features/playlists/playlist_providers.dart';

void main() {
  tearDown(() {
    PlatformInfo.setTvOverride(false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  testWidgets(
    'Android TV / Fire Stick enables TV shortcuts & traditional focus',
    (WidgetTester tester) async {
      PlatformInfo.setTvOverride(true);

      await tester.pumpWidget(
        const ProviderScope(child: YesXtreamApp()),
      );
      await tester.pump();

      expect(PlatformInfo.isTV, isTrue);
      expect(PlatformInfo.isMobile, isFalse);
      expect(
        FocusManager.instance.highlightStrategy,
        FocusHighlightStrategy.alwaysTraditional,
      );

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.shortcuts, isNotNull);
      expect(
        materialApp.shortcuts![const SingleActivator(LogicalKeyboardKey.select)],
        isA<ActivateIntent>(),
      );
      expect(
        materialApp.shortcuts![const SingleActivator(LogicalKeyboardKey.enter)],
        isA<ActivateIntent>(),
      );
      expect(
        materialApp
            .shortcuts![const SingleActivator(LogicalKeyboardKey.arrowDown)],
        const DirectionalFocusIntent(TraversalDirection.down),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'HomeScreen empty state autofocuses button and opens Add Provider on Select key',
    (WidgetTester tester) async {
      PlatformInfo.setTvOverride(true);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allPlaylistsProvider.overrideWith(
              (ref) => Stream.value(<db.Provider>[]),
            ),
          ],
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FilledButton), findsOneWidget);
      final buttonElement = tester.element(find.byType(FilledButton));
      expect(Focus.of(buttonElement).hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.text('Add Provider'), findsWidgets);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
