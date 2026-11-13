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

    test('generates valid virtual MAC (AA:BB:CC:DD:EE:FF) and 6-digit device key', () async {
      final identity = await DeviceIdentityService.getIdentity();

      final macRegex = RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){5}$');
      expect(macRegex.hasMatch(identity.macAddress), isTrue,
          reason: 'MAC address must match AA:BB:CC:DD:EE:FF format');

      final keyRegex = RegExp(r'^\d{6}$');
      expect(keyRegex.hasMatch(identity.deviceKey), isTrue,
          reason: 'Device key must be exactly 6 numeric digits');
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

