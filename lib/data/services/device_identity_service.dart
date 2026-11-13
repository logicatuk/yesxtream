import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentity {
  final String macAddress; // Format: AA:BB:CC:DD:EE:FF
  final String deviceKey; // 6-digit numeric string (e.g. 842195)

  const DeviceIdentity({
    required this.macAddress,
    required this.deviceKey,
  });
}

class DeviceIdentityService {
  static const _kMacKey = 'device_mac_address';
  static const _kDeviceKey = 'device_activation_key';

  static final RegExp _macFormat = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');

  /// Returns the stable virtual MAC and 6-digit device key, creating and persisting them if not present.
  static Future<DeviceIdentity> getIdentity() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. MAC address (format AA:BB:CC:DD:EE:FF)
    String? mac = prefs.getString(_kMacKey)?.trim().toUpperCase();
    if (mac == null || !_macFormat.hasMatch(mac)) {
      mac = _generateVirtualMac();
      await prefs.setString(_kMacKey, mac);
    }

    // 2. 6-digit Device Key
    String? key = prefs.getString(_kDeviceKey)?.trim();
    if (key == null || key.length != 6 || int.tryParse(key) == null) {
      key = _generate6DigitKey();
      await prefs.setString(_kDeviceKey, key);
    }

    return DeviceIdentity(macAddress: mac, deviceKey: key);
  }

  /// Generate a random virtual MAC in standard format AA:BB:CC:DD:EE:FF
  /// (with locally administered unicast bits set: byte 0 bit 1 = 1, bit 0 = 0)
  static String _generateVirtualMac() {
    final rand = Random.secure();
    final bytes = List<int>.generate(6, (_) => rand.nextInt(256));
    bytes[0] = (bytes[0] & 0xFE) | 0x02;
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
  }

  /// Generate a secure 6-digit numeric key (100000 - 999999)
  static String _generate6DigitKey() {
    final rand = Random.secure();
    final num = 100000 + rand.nextInt(900000);
    return num.toString();
  }
}

final deviceIdentityProvider = FutureProvider<DeviceIdentity>((ref) async {
  return DeviceIdentityService.getIdentity();
});

