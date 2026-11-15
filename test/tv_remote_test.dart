import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:yesxtream/app/app.dart';
import 'package:yesxtream/core/platform_info.dart';
import 'package:yesxtream/core/tv_back_handler.dart';
import 'package:yesxtream/core/tv_remote.dart';
import 'package:yesxtream/data/datasources/local/database.dart' as db;
import 'package:yesxtream/features/home/home_screen.dart';
import 'package:yesxtream/features/playlists/playlist_providers.dart';

void main() {
  test('OK key matches Samsung Enter, LG Enter, and Fire Stick Select', () {
    expect(tvIsOkKey(LogicalKeyboardKey.enter), isTrue);
    expect(tvIsOkKey(LogicalKeyboardKey.numpadEnter), isTrue);
    expect(tvIsOkKey(LogicalKeyboardKey.select), isTrue);
    expect(tvIsOkKey(LogicalKeyboardKey.gameButtonA), isTrue);
    expect(tvIsOkKey(LogicalKeyboardKey.arrowDown), isFalse);
    expect(tvIsOkKey(LogicalKeyboardKey.escape), isFalse);
  });

  test('focused row counts as on-screen only between its reveal offsets', () {
    expect(
      tvScrollOffsetKeepsChildVisible(
        pixels: 500,
        revealAtStart: 1000,
        revealAtEnd: 350,
      ),
      isTrue,
    );
    expect(
      tvScrollOffsetKeepsChildVisible(
        pixels: 0,
        revealAtStart: 1000,
        revealAtEnd: 350,
      ),
      isFalse,
    );
    expect(
      tvScrollOffsetKeepsChildVisible(
        pixels: 1200,
        revealAtStart: 1000,
        revealAtEnd: 350,
      ),
      isFalse,
    );
  });

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

      // Dialog title from add_provider_dialog.dart
      expect(find.text('Add Provider'), findsWidgets);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('TvBackHandler navigates to fallbackRoute on Escape (Samsung Tizen Return)',
      (WidgetTester tester) async {
    final testRouter = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('Home Page')),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const TvBackHandler(
            child: Scaffold(body: Text('Settings Page')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
    await tester.pumpAndSettle();
    expect(find.text('Settings Page'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Home Page'), findsOneWidget);
  });

  testWidgets('TvBackHandler on Movie detail navigates to /movies on back key',
      (WidgetTester tester) async {
    final testRouter = GoRouter(
      initialLocation: '/movie-detail',
      routes: [
        GoRoute(
          path: '/movies',
          builder: (_, __) => const Scaffold(body: Text('Movies Grid')),
        ),
        GoRoute(
          path: '/movie-detail',
          builder: (_, __) => const TvBackHandler(
            fallbackRoute: '/movies',
            child: Scaffold(body: Text('Movie Details')),
          ),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: testRouter));
    await tester.pumpAndSettle();
    expect(find.text('Movie Details'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Movies Grid'), findsOneWidget);
  });
}
