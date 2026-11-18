import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/platform_info.dart';
import 'app_update_service.dart';

const String kYestreamApiBase = 'https://yestream.ai.studio/api/v1';

class DeviceIdentity {
  final String deviceId;
  final String macAddress; // Format: 02:XX:XX:XX:XX:XX
  final String? deviceKey; // 6-digit numeric string (e.g. 842195) returned by server; null if not synced
  final String credential;
  final String hardwareFingerprint;
  final String? portalLoginUrl;
  final String status; // 'trial', 'active', 'expired'
  final String? plan;
  final int trialDays;
  final DateTime? trialEndsAt;
  final DateTime? expiresAt;
  final int configVersion;
  final bool serverRegistered;

  const DeviceIdentity({
    required this.deviceId,
    required this.macAddress,
    this.deviceKey,
    required this.credential,
    required this.hardwareFingerprint,
    this.portalLoginUrl,
    this.status = 'trial',
    this.plan,
    this.trialDays = 7,
    this.trialEndsAt,
    this.expiresAt,
    this.configVersion = 0,
    this.serverRegistered = false,
  });

  DeviceIdentity copyWith({
    String? deviceId,
    String? macAddress,
    String? deviceKey,
    String? credential,
    String? hardwareFingerprint,
    String? portalLoginUrl,
    String? status,
    String? plan,
    int? trialDays,
    DateTime? trialEndsAt,
    DateTime? expiresAt,
    int? configVersion,
    bool? serverRegistered,
  }) {
    return DeviceIdentity(
      deviceId: deviceId ?? this.deviceId,
      macAddress: macAddress ?? this.macAddress,
      deviceKey: deviceKey ?? this.deviceKey,
      credential: credential ?? this.credential,
      hardwareFingerprint: hardwareFingerprint ?? this.hardwareFingerprint,
      portalLoginUrl: portalLoginUrl ?? this.portalLoginUrl,
      status: status ?? this.status,
      plan: plan ?? this.plan,
      trialDays: trialDays ?? this.trialDays,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      expiresAt: expiresAt ?? this.expiresAt,
      configVersion: configVersion ?? this.configVersion,
      serverRegistered: serverRegistered ?? this.serverRegistered,
    );
  }
}

class DeviceIdentityService {
  static const _kMacKey = 'device_mac_address';
  static const _kDeviceKey = 'device_activation_key';
  static const _kCredentialKey = 'device_credential';
  static const _kFingerprintKey = 'device_hardware_fingerprint';
  static const _kDeviceIdKey = 'device_id';
  static const _kPortalUrlKey = 'device_portal_url';
  static const _kStatusKey = 'device_status';
  static const _kPlanKey = 'device_plan';
  static const _kTrialDaysKey = 'device_trial_days';
  static const _kTrialEndsAtKey = 'device_trial_ends_at';
  static const _kExpiresAtKey = 'device_expires_at';
  static const _kConfigVersionKey = 'device_config_version';
  static const _kInstallUuidKey = 'device_install_uuid';
  static const _kServerRegisteredKey = 'device_server_registered';

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    mOptions: MacOsOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static DeviceIdentity? _cachedIdentity;

  static String buildDefaultPortalUrl(String mac, String key) {
    try {
      final uri = Uri.parse(kYestreamApiBase);
      final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'https';
      final host = uri.host;
      return '$scheme://$host/customer/login?mac=$mac&key=$key&redirect=/me/playlists';
    } catch (_) {
      return 'https://yestream.app/customer/login?mac=$mac&key=$key&redirect=/me/playlists';
    }
  }

  /// Returns the current device identity, registering or recovering with the backend.
  static Future<DeviceIdentity> getIdentity({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedIdentity != null) {
      return _cachedIdentity!;
    }

    final prefs = await SharedPreferences.getInstance();

    // 1. Persistent install UUID for native platforms only
    String? installUuid;
    if (!kIsWeb) {
      try {
        installUuid = await _secureStorage.read(key: _kInstallUuidKey);
      } catch (_) {}
      installUuid ??= prefs.getString(_kInstallUuidKey);
      if (installUuid == null || installUuid.isEmpty) {
        installUuid = const Uuid().v4();
        try {
          await _secureStorage.write(key: _kInstallUuidKey, value: installUuid);
        } catch (_) {}
        await prefs.setString(_kInstallUuidKey, installUuid);
      }
    }

    // 2. Compute hardware fingerprint deterministically
    final hardwareInfo = await _extractHardwareInfo(installUuid);
    final hardwareFingerprint = hardwareInfo.fingerprint;

    // 3. Derive deterministic MAC for web or read stored MAC for native
    String? mac;
    if (kIsWeb) {
      // Deterministic MAC strictly matching web hardwareFingerprint
      mac = _deriveDeterministicMac(hardwareFingerprint);
    } else {
      try {
        mac = await _secureStorage.read(key: _kMacKey);
      } catch (_) {}
      mac ??= prefs.getString(_kMacKey)?.trim().toUpperCase();

      final macRegex = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');
      if (mac == null || !macRegex.hasMatch(mac)) {
        mac = _deriveDeterministicMac(hardwareFingerprint);
        try {
          await _secureStorage.write(key: _kMacKey, value: mac);
        } catch (_) {}
        await prefs.setString(_kMacKey, mac);
      }
    }

    // 4. Cached server registration state (NEVER generate a local fallback 6-digit key)
    final bool cachedServerRegistered = prefs.getBool(_kServerRegisteredKey) ?? false;
    String? cachedKey;
    if (cachedServerRegistered) {
      try {
        cachedKey = await _secureStorage.read(key: _kDeviceKey);
      } catch (_) {}
      cachedKey ??= prefs.getString(_kDeviceKey)?.trim();
      if (cachedKey != null && (cachedKey.length != 6 || int.tryParse(cachedKey) == null)) {
        cachedKey = null;
      }
    }

    // 5. Read cached credential and metadata
    String? credential;
    try {
      credential = await _secureStorage.read(key: _kCredentialKey);
    } catch (_) {}
    credential ??= prefs.getString(_kCredentialKey);

    String? deviceId = prefs.getString(_kDeviceIdKey) ?? mac;
    String? portalUrl = (cachedKey != null && cachedKey.isNotEmpty)
        ? (prefs.getString(_kPortalUrlKey) ?? buildDefaultPortalUrl(mac, cachedKey))
        : null;
    String status = prefs.getString(_kStatusKey) ?? 'trial';
    String? plan = prefs.getString(_kPlanKey);
    int trialDays = prefs.getInt(_kTrialDaysKey) ?? 7;
    int configVersion = prefs.getInt(_kConfigVersionKey) ?? 0;

    DateTime? trialEndsAt;
    final trialStr = prefs.getString(_kTrialEndsAtKey);
    if (trialStr != null) trialEndsAt = DateTime.tryParse(trialStr);

    DateTime? expiresAt;
    final expStr = prefs.getString(_kExpiresAtKey);
    if (expStr != null) expiresAt = DateTime.tryParse(expStr);

    var identity = DeviceIdentity(
      deviceId: deviceId,
      macAddress: mac,
      deviceKey: cachedKey,
      credential: credential ?? '',
      hardwareFingerprint: hardwareFingerprint,
      portalLoginUrl: portalUrl,
      status: status,
      plan: plan,
      trialDays: trialDays,
      trialEndsAt: trialEndsAt,
      expiresAt: expiresAt,
      configVersion: configVersion,
      serverRegistered: cachedServerRegistered && cachedKey != null,
    );

    // 6. Contact backend: POST /devices/register
    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Content-Type': 'application/json'},
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      final response = await dio.post(
        '$kYestreamApiBase/devices/register',
        data: {
          'mac': mac,
          'hardwareFingerprint': hardwareFingerprint,
          'credential': credential?.isNotEmpty == true ? credential : null,
          'platform': hardwareInfo.platform,
          'model': hardwareInfo.model,
          'os': hardwareInfo.os,
          'appVersion': AppUpdateService.currentVersion,
        },
      );

      if ((response.statusCode == 200 || response.statusCode == 201) && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);

        final returnedKey = (data['key6'] ?? data['deviceKey'])?.toString().trim();
        final returnedCred = data['credential']?.toString();
        final returnedTrialDays = data['trialDays'] is int ? data['trialDays'] as int : null;
        final returnedStatus = data['status']?.toString();
        final returnedPlan = data['plan']?.toString();
        final returnedCfgVer = data['configVersion'] is int ? data['configVersion'] as int : null;
        final returnedPortalUrl = data['portalLoginUrl']?.toString();
        final returnedDeviceId = (data['deviceId'] ?? data['id'])?.toString();
        final returnedMac = (data['mac'] ?? data['macAddress'])?.toString().trim().toUpperCase();

        DateTime? returnedTrialEnds;
        if (data['trialEndsAt'] != null) {
          returnedTrialEnds = DateTime.tryParse(data['trialEndsAt'].toString());
        }

        DateTime? returnedExpires;
        if (data['expiresAt'] != null) {
          returnedExpires = DateTime.tryParse(data['expiresAt'].toString());
        }

        final isValidKey = returnedKey != null && returnedKey.length == 6 && int.tryParse(returnedKey) != null;
        final effectiveMac = returnedMac ?? mac;

        identity = identity.copyWith(
          deviceId: returnedDeviceId ?? identity.deviceId,
          macAddress: effectiveMac,
          deviceKey: isValidKey ? returnedKey : identity.deviceKey,
          credential: returnedCred ?? identity.credential,
          trialDays: returnedTrialDays ?? identity.trialDays,
          status: returnedStatus ?? identity.status,
          plan: returnedPlan ?? identity.plan,
          configVersion: returnedCfgVer ?? identity.configVersion,
          portalLoginUrl: (returnedPortalUrl != null && returnedPortalUrl.isNotEmpty)
              ? returnedPortalUrl
              : (isValidKey ? buildDefaultPortalUrl(effectiveMac, returnedKey) : null),
          trialEndsAt: returnedTrialEnds ?? identity.trialEndsAt,
          expiresAt: returnedExpires ?? identity.expiresAt,
          serverRegistered: isValidKey,
        );

        if (identity.serverRegistered) {
          await _saveIdentityLocally(identity);
        }
      } else {
        debugPrint('[DeviceIdentityService] Register returned HTTP ${response.statusCode}');
        identity = identity.copyWith(
          serverRegistered: false,
          deviceKey: null,
          portalLoginUrl: null,
        );
      }
    } catch (e) {
      debugPrint('[DeviceIdentityService] Register check error: $e');
      identity = identity.copyWith(
        serverRegistered: false,
        deviceKey: null,
        portalLoginUrl: null,
      );
    }

    _cachedIdentity = identity;
    return identity;
  }

  /// Refreshes registration against the backend immediately.
  static Future<DeviceIdentity> refreshRegistration() async {
    _cachedIdentity = null;
    return getIdentity(forceRefresh: true);
  }

  /// Updates server-verified key6 & portalLoginUrl from live sync responses.
  static Future<void> updateServerKeyAndPortalUrl({
    required String key6,
    String? portalUrl,
  }) async {
    final cleanKey = key6.trim();
    if (cleanKey.length != 6) return;

    if (_cachedIdentity != null) {
      _cachedIdentity = _cachedIdentity!.copyWith(
        deviceKey: cleanKey,
        portalLoginUrl: (portalUrl != null && portalUrl.isNotEmpty)
            ? portalUrl
            : buildDefaultPortalUrl(_cachedIdentity!.macAddress, cleanKey),
        serverRegistered: true,
      );
      await _saveIdentityLocally(_cachedIdentity!);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDeviceKey, cleanKey);
      await prefs.setBool(_kServerRegisteredKey, true);
      if (portalUrl != null && portalUrl.isNotEmpty) {
        await prefs.setString(_kPortalUrlKey, portalUrl);
      }
      try {
        await _secureStorage.write(key: _kDeviceKey, value: cleanKey);
      } catch (_) {}
    }
  }

  static Future<void> _saveIdentityLocally(DeviceIdentity identity) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_kMacKey, identity.macAddress);
    if (identity.deviceKey != null) {
      await prefs.setString(_kDeviceKey, identity.deviceKey!);
    } else {
      await prefs.remove(_kDeviceKey);
    }
    await prefs.setString(_kCredentialKey, identity.credential);
    await prefs.setString(_kDeviceIdKey, identity.deviceId);
    await prefs.setString(_kFingerprintKey, identity.hardwareFingerprint);
    if (identity.portalLoginUrl != null) {
      await prefs.setString(_kPortalUrlKey, identity.portalLoginUrl!);
    } else {
      await prefs.remove(_kPortalUrlKey);
    }
    await prefs.setString(_kStatusKey, identity.status);
    if (identity.plan != null) {
      await prefs.setString(_kPlanKey, identity.plan!);
    }
    await prefs.setInt(_kTrialDaysKey, identity.trialDays);
    await prefs.setInt(_kConfigVersionKey, identity.configVersion);
    await prefs.setBool(_kServerRegisteredKey, identity.serverRegistered);

    if (identity.trialEndsAt != null) {
      await prefs.setString(_kTrialEndsAtKey, identity.trialEndsAt!.toIso8601String());
    }
    if (identity.expiresAt != null) {
      await prefs.setString(_kExpiresAtKey, identity.expiresAt!.toIso8601String());
    }

    try {
      await _secureStorage.write(key: _kMacKey, value: identity.macAddress);
      if (identity.deviceKey != null) {
        await _secureStorage.write(key: _kDeviceKey, value: identity.deviceKey!);
      } else {
        await _secureStorage.delete(key: _kDeviceKey);
      }
      await _secureStorage.write(key: _kCredentialKey, value: identity.credential);
      await _secureStorage.write(key: _kFingerprintKey, value: identity.hardwareFingerprint);
    } catch (_) {}
  }

  static Future<({String platform, String model, String os, String fingerprint})>
      _extractHardwareInfo(String? installUuid) async {
    final deviceInfo = DeviceInfoPlugin();
    String platformName = 'Android TV';
    String modelName = 'Generic TV';
    String osVersion = 'Unknown OS';
    final entropyParts = <String>[];

    try {
      if (kIsWeb) {
        final web = await deviceInfo.webBrowserInfo;
        final ua = web.userAgent ?? '';
        if (ua.contains('Web0S') || ua.contains('webOS')) {
          platformName = 'LG webOS';
        } else if (ua.contains('Tizen')) {
          platformName = 'Samsung Tizen';
        } else {
          platformName = 'Web';
        }
        modelName = web.browserName.name;
        osVersion = web.platform ?? 'Web';
        // Deterministic browser entropy: userAgent, vendor, hardwareConcurrency, platform (NO random UUID)
        entropyParts.addAll([
          ua,
          web.vendor ?? '',
          '${web.hardwareConcurrency}',
          web.platform ?? '',
        ]);
      } else if (PlatformInfo.isAndroid) {
        if (installUuid != null && installUuid.isNotEmpty) entropyParts.add(installUuid);
        final android = await deviceInfo.androidInfo;
        platformName = PlatformInfo.isTV ? 'Android TV' : 'Android';
        modelName = '${android.brand} ${android.model}'.trim();
        osVersion = 'Android ${android.version.release} (API ${android.version.sdkInt})';
        entropyParts.addAll([
          android.id,
          android.fingerprint,
          android.hardware,
          android.board,
          android.model,
        ]);
      } else if (PlatformInfo.isMacOS) {
        if (installUuid != null && installUuid.isNotEmpty) entropyParts.add(installUuid);
        final mac = await deviceInfo.macOsInfo;
        platformName = 'macOS';
        modelName = mac.model;
        osVersion = '${mac.osRelease} (${mac.kernelVersion})';
        entropyParts.addAll([mac.systemGUID ?? '', mac.model]);
      } else if (PlatformInfo.isWindows) {
        if (installUuid != null && installUuid.isNotEmpty) entropyParts.add(installUuid);
        final win = await deviceInfo.windowsInfo;
        platformName = 'Windows';
        modelName = win.computerName;
        osVersion = win.productName;
        entropyParts.addAll([win.deviceId, win.computerName]);
      } else if (PlatformInfo.isLinux) {
        if (installUuid != null && installUuid.isNotEmpty) entropyParts.add(installUuid);
        final linux = await deviceInfo.linuxInfo;
        platformName = 'Linux';
        modelName = linux.name;
        osVersion = linux.versionId ?? linux.version ?? 'Linux';
        entropyParts.addAll([linux.machineId ?? '', linux.name]);
      } else if (PlatformInfo.isIOS) {
        if (installUuid != null && installUuid.isNotEmpty) entropyParts.add(installUuid);
        final ios = await deviceInfo.iosInfo;
        platformName = 'iOS';
        modelName = ios.utsname.machine;
        osVersion = '${ios.systemName} ${ios.systemVersion}';
        entropyParts.addAll([ios.identifierForVendor ?? '', ios.model]);
      }
    } catch (e) {
      debugPrint('[DeviceIdentityService] Hardware detection fallback: $e');
      entropyParts.add('fallback_${PlatformInfo.isTV ? 'tv' : 'device'}');
    }

    final rawString = entropyParts.join('|');
    final fingerprint = sha256.convert(utf8.encode(rawString)).toString();

    return (
      platform: platformName,
      model: modelName,
      os: osVersion,
      fingerprint: fingerprint,
    );
  }

  /// Derives a deterministic IEEE 802 locally-administered unicast MAC: 02:XX:XX:XX:XX:XX
  static String _deriveDeterministicMac(String fingerprint) {
    final digest = sha256.convert(utf8.encode(fingerprint)).bytes;
    final bytes = List<int>.from(digest.sublist(0, 6));
    bytes[0] = 0x02; // Always format as 02:XX:XX:XX:XX:XX
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
  }
}

final deviceIdentityProvider = FutureProvider<DeviceIdentity>((ref) async {
  return DeviceIdentityService.getIdentity();
});
