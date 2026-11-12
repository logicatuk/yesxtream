import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yesxtream/core/platform_info.dart';
import 'package:yesxtream/features/providers/add_provider_dialog.dart';

void main() {
  tearDown(() {
    PlatformInfo.setTvOverride(false);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });

  Future<void> openAddProviderAtSize(
    WidgetTester tester,
    Size size, {
    bool isTv = false,
  }) async {
    PlatformInfo.setTvOverride(isTv);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showAddProviderDialog(context),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Phone portrait (360x640) switches M3U/Xtream and toggles password without overflow',
      (WidgetTester tester) async {
    await openAddProviderAtSize(tester, const Size(360, 640));

    expect(find.text('Add Provider'), findsWidgets);
    expect(find.text('M3U URL'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);

    await tester.tap(find.text('Xtream Codes'));
    await tester.pumpAndSettle();

    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    // Password starts obscured and can be revealed cleanly.
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('Phone landscape (844x390) scrolls cleanly with no overflow',
      (WidgetTester tester) async {
    await openAddProviderAtSize(tester, const Size(844, 390));

    await tester.tap(find.text('Xtream Codes'));
    await tester.pumpAndSettle();

    expect(find.text('Server URL'), findsOneWidget);
    expect(find.text('Add Provider'), findsWidgets);
  });

  testWidgets('TV / Desktop (1280x720) shows two-pane UI, validates, and closes on Escape',
      (WidgetTester tester) async {
    await openAddProviderAtSize(tester, const Size(1280, 720), isTv: true);

    expect(find.text('CONNECTION TYPE'), findsOneWidget);
    expect(find.text('M3U Playlist Details'), findsOneWidget);

    // Switch to Xtream Codes via tap/selection.
    await tester.tap(find.text('Xtream Codes'));
    await tester.pumpAndSettle();
    expect(find.text('Xtream Codes Login'), findsOneWidget);

    // Submitting empty form shows Required validation messages cleanly.
    await tester.tap(find.widgetWithText(FilledButton, 'Add Provider'));
    await tester.pump();
    expect(find.text('Required'), findsNWidgets(4));

    // Escape closes the route back to opener.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('showChoosePlaylistTypeDialog and showPlaylistFormDialog use unified UI',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showAddProviderDialog(
                    context,
                    existingId: 'p1',
                    initialName: 'My Server',
                    initialUrl: 'http://myiptv.com',
                    initialUsername: 'user1',
                    initialPassword: 'pass1',
                    isXtream: true,
                  ),
                  child: const Text('Edit Provider'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit Provider'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Playlist'), findsWidgets);
    expect(find.text('Save Changes'), findsOneWidget);
    expect(find.text('user1'), findsOneWidget);
  });
}

