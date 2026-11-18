import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yesxtream/data/services/app_settings.dart';
import 'package:yesxtream/data/services/device_identity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceIdentityService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('generates valid virtual MAC (02:XX:XX:XX:XX:XX) and handles server registration state', () async {
      final identity = await DeviceIdentityService.getIdentity();

      final macRegex = RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$');
      expect(macRegex.hasMatch(identity.macAddress), isTrue,
          reason: 'MAC address must match AA:BB:CC:DD:EE:FF format');
      expect(identity.macAddress.startsWith('02:'), isTrue,
          reason: 'MAC address must be locally administered (02:XX:XX:XX:XX:XX)');
    });

    test('updateServerKeyAndPortalUrl persists genuine 6-digit key and marks registered', () async {
      final initial = await DeviceIdentityService.getIdentity();
      await DeviceIdentityService.updateServerKeyAndPortalUrl(
        key6: '842195',
        portalUrl: 'https://yestream.ai.studio/customer/login?mac=${initial.macAddress}&key=842195&redirect=/me/playlists',
      );

      final updated = await DeviceIdentityService.getIdentity();
      expect(updated.serverRegistered, isTrue);
      expect(updated.deviceKey, equals('842195'));
      expect(updated.portalLoginUrl, contains('key=842195'));
    });

    test('identity is stable and persisted across multiple calls', () async {
      final first = await DeviceIdentityService.getIdentity();
      final second = await DeviceIdentityService.getIdentity();

      expect(second.macAddress, equals(first.macAddress));
      expect(second.deviceKey, equals(first.deviceKey));
    });
  });

  group('AppSettings defaults', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('autoRefreshOnStartup defaults to false', () async {
      const settings = AppSettings();
      expect(settings.autoRefreshOnStartup, isFalse);
    });
  });
}

