import 'package:flutter_test/flutter_test.dart';
import 'package:yesxtream/core/parental_guard.dart';
import 'package:yesxtream/data/services/app_settings.dart';

void main() {
  group('ParentalGuard & Session Cache', () {
    test('isLockedGroup detects adult keywords when enabled', () {
      final enabledSettings = const AppSettings(
        parentalControlsEnabled: true,
        parentalPin: '1234',
        lockedCategories: ['Private'],
      );

      expect(ParentalGuard.isLockedGroup(enabledSettings, 'XXX Adult Channel'), isTrue);
      expect(ParentalGuard.isLockedGroup(enabledSettings, 'Private Live'), isTrue);
      expect(ParentalGuard.isLockedGroup(enabledSettings, 'News Channel'), isFalse);
    });

    test('isLockedGroup returns false when parental controls disabled', () {
      final disabledSettings = const AppSettings(
        parentalControlsEnabled: false,
        parentalPin: '1234',
        lockedCategories: ['Private'],
      );

      expect(ParentalGuard.isLockedGroup(disabledSettings, 'XXX Adult Channel'), isFalse);
    });

    test('Session unlock window handles reset', () {
      ParentalGuard.resetSession();
      expect(ParentalGuard.isSessionUnlocked, isFalse);
    });
  });
}

