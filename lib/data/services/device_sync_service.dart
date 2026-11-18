import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/platform_info.dart';
import '../datasources/local/database.dart' as db;
import '../../features/providers/provider_manager.dart';
import 'app_update_service.dart';
import 'device_identity_service.dart';

class DeviceEntitlementState {
  final String status; // 'trial', 'active', 'expired'
  final String? plan;
  final int trialDays;
  final int daysRemaining;
  final DateTime? trialEndsAt;
  final DateTime? expiresAt;
  final DateTime? serverTime;
  final String? portalLoginUrl;
  final int configVersion;
  final bool isSyncing;
  final String? lastError;
  final DateTime? lastSyncTime;
  final int remotePlaylistsCount;
  final Set<String> lockedProviderIds;

  const DeviceEntitlementState({
    this.status = 'trial',
    this.plan,
    this.trialDays = 7,
    this.daysRemaining = 7,
    this.trialEndsAt,
    this.expiresAt,
    this.serverTime,
    this.portalLoginUrl,
    this.configVersion = 0,
    this.isSyncing = false,
    this.lastError,
    this.lastSyncTime,
    this.remotePlaylistsCount = 0,
    this.lockedProviderIds = const {},
  });

  bool get isTrial => status.toLowerCase() == 'trial';
  bool get isActive => status.toLowerCase() == 'active';
  bool get isExpired => status.toLowerCase() == 'expired';

  String get formattedStatusBadge {
    if (isActive) {
      return (plan != null && plan!.isNotEmpty) ? 'Active · $plan' : 'Active (Lifetime)';
    }
    if (isExpired) {
      return 'Trial Expired';
    }
    final days = daysRemaining.clamp(0, 365);
    return 'Trial · $days ${days == 1 ? 'day' : 'days'} left (of $trialDays-day trial)';
  }

  DeviceEntitlementState copyWith({
    String? status,
    String? plan,
    int? trialDays,
    int? daysRemaining,
    DateTime? trialEndsAt,
    DateTime? expiresAt,
    DateTime? serverTime,
    String? portalLoginUrl,
    int? configVersion,
    bool? isSyncing,
    String? lastError,
    DateTime? lastSyncTime,
    int? remotePlaylistsCount,
    Set<String>? lockedProviderIds,
  }) {
    return DeviceEntitlementState(
      status: status ?? this.status,
      plan: plan ?? this.plan,
      trialDays: trialDays ?? this.trialDays,
      daysRemaining: daysRemaining ?? this.daysRemaining,
      trialEndsAt: trialEndsAt ?? this.trialEndsAt,
      expiresAt: expiresAt ?? this.expiresAt,
      serverTime: serverTime ?? this.serverTime,
      portalLoginUrl: portalLoginUrl ?? this.portalLoginUrl,
      configVersion: configVersion ?? this.configVersion,
      isSyncing: isSyncing ?? this.isSyncing,
      lastError: lastError,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      remotePlaylistsCount: remotePlaylistsCount ?? this.remotePlaylistsCount,
      lockedProviderIds: lockedProviderIds ?? this.lockedProviderIds,
    );
  }
}

class DeviceSyncNotifier extends StateNotifier<DeviceEntitlementState> with WidgetsBindingObserver {
  final db.AppDatabase _db;
  final ProviderManager _manager;

  Timer? _periodicTimer;
  StreamSubscription? _sseSub;
  bool _initialized = false;
  bool _isMutatingCloud = false;
  int _lastConfigVersion = 0;

  DeviceSyncNotifier(this._db, this._manager) : super(const DeviceEntitlementState()) {
    _init();
  }

  bool get _isTestMode {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;

    WidgetsBinding.instance.addObserver(this);

    // 1. Load cached entitlement immediately
    await _loadCachedEntitlement();

    if (_isTestMode) return;

    // 2. Perform initial sync
    await sync();

    // 3. Start 60-second periodic timer
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      sync();
    });

    // 4. Connect to SSE event stream
    _connectSse();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[DeviceSync] App resumed — triggering sync');
      sync();
      _connectSse();
    } else if (state == AppLifecycleState.paused) {
      _sseSub?.cancel();
      _sseSub = null;
    }
  }

  Future<void> _loadCachedEntitlement() async {
    final prefs = await SharedPreferences.getInstance();
    final status = prefs.getString('device_status') ?? 'trial';
    final plan = prefs.getString('device_plan');
    final trialDays = prefs.getInt('device_trial_days') ?? 7;
    final configVersion = prefs.getInt('device_config_version') ?? 0;
    _lastConfigVersion = configVersion;
    final portalUrl = prefs.getString('device_portal_url');
    final lockedList = prefs.getStringList('device_locked_provider_ids') ?? [];
    final lockedSet = lockedList.toSet();

    DateTime? trialEndsAt;
    final trialStr = prefs.getString('device_trial_ends_at');
    if (trialStr != null) trialEndsAt = DateTime.tryParse(trialStr);

    DateTime? expiresAt;
    final expStr = prefs.getString('device_expires_at');
    if (expStr != null) expiresAt = DateTime.tryParse(expStr);

    final now = DateTime.now();
    final remaining = trialEndsAt != null ? trialEndsAt.difference(now).inDays : trialDays;

    state = state.copyWith(
      status: status,
      plan: plan,
      trialDays: trialDays,
      daysRemaining: remaining,
      trialEndsAt: trialEndsAt,
      expiresAt: expiresAt,
      configVersion: configVersion,
      portalLoginUrl: portalUrl,
      lockedProviderIds: lockedSet,
    );
  }

  /// Push local and cloud playlists to the backend cloud so
  /// Resellers/Sub-Resellers see them in /panel/devices.
  Future<void> pushLocalPlaylistsToCloud() async {
    if (_isTestMode) return;
    if (_isMutatingCloud) return;
    _isMutatingCloud = true;
    try {
      final identity = await DeviceIdentityService.getIdentity();
      if (!identity.serverRegistered || identity.credential.isEmpty) {
        debugPrint('[DeviceSync] pushLocalPlaylistsToCloud skipped: device not registered yet');
        return;
      }

      final allProviders = await _db.getAllProviders();

      final payload = {
        'playlists': allProviders.map((p) {
          final isRemote = p.id.startsWith('remote_');
          final serverId = isRemote ? p.id.replaceFirst('remote_', '') : null;
          final cleanUrl = normalizeProviderUrl(p.url ?? '');
          return {
            if (serverId != null) 'id': serverId,
            'localId': p.id,
            'name': p.name,
            'type': p.type.toLowerCase() == 'm3u' ? 'm3u' : 'xtream',
            'url': cleanUrl,
            'username': p.username ?? '',
            'password': p.password ?? '',
          };
        }).toList(),
      };

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${identity.credential}',
          },
        ),
      );

      final res = await dio.post(
        '$kYestreamApiBase/device/playlists/sync',
        data: payload,
      );

      if (res.statusCode == 200 && res.data is Map) {
        final version = res.data['configVersion'];
        if (version is int && version > _lastConfigVersion) {
          _lastConfigVersion = version;
          state = state.copyWith(configVersion: version);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('device_config_version', version);
        }
      }

      debugPrint('[DeviceSync] pushLocalPlaylistsToCloud success: HTTP ${res.statusCode}');
    } catch (e) {
      debugPrint('[DeviceSync] pushLocalPlaylistsToCloud warning: $e');
    } finally {
      _isMutatingCloud = false;
    }
  }

  /// Deletes a playlist from the cloud backend.
  /// If the playlist originated from the server (remote_<id>), calls DELETE /device/playlists/<id>.
  /// Afterwards, pushes current local state to cloud.
  Future<bool> deleteRemotePlaylistFromCloud(String providerId) async {
    if (_isTestMode) return true;
    _isMutatingCloud = true;
    try {
      final identity = await DeviceIdentityService.getIdentity();
      if (!identity.serverRegistered || identity.credential.isEmpty) {
        return false;
      }

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Authorization': 'Bearer ${identity.credential}',
          },
        ),
      );

      if (providerId.startsWith('remote_')) {
        final serverId = providerId.replaceFirst('remote_', '');
        try {
          final res = await dio.delete('$kYestreamApiBase/device/playlists/$serverId');
          if (res.data is Map && res.data['configVersion'] is int) {
            _lastConfigVersion = res.data['configVersion'] as int;
          }
        } catch (e) {
          debugPrint('[DeviceSync] Server DELETE warning: $e');
        }
      }

      // Also push remaining local providers to server
      _isMutatingCloud = false;
      await pushLocalPlaylistsToCloud();
      return true;
    } catch (e) {
      debugPrint('[DeviceSync] deleteRemotePlaylistFromCloud error: $e');
      return false;
    } finally {
      _isMutatingCloud = false;
    }
  }

  /// Manually or automatically performs heartbeat, entitlement check, and Drift provider reconciliation.
  Future<void> sync({bool force = false}) async {
    if (state.isSyncing || _isMutatingCloud) return;
    state = state.copyWith(isSyncing: true, lastError: null);

    try {
      // 0. Push local playlists to cloud first so server has current TV state
      await pushLocalPlaylistsToCloud();

      final identity = await DeviceIdentityService.getIdentity();

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 15),
          headers: {
            'Content-Type': 'application/json',
            if (identity.credential.isNotEmpty) 'Authorization': 'Bearer ${identity.credential}',
          },
        ),
      );

      // 1. POST /device/heartbeat
      final hardware = await _getTelemetryHardware();
      try {
        await dio.post(
          '$kYestreamApiBase/device/heartbeat',
          data: {
            'platform': hardware.platform,
            'model': hardware.model,
            'os': hardware.os,
            'appVersion': AppUpdateService.currentVersion,
            'hardwareFingerprint': identity.hardwareFingerprint,
          },
        );
      } catch (e) {
        debugPrint('[DeviceSync] Heartbeat warning: $e');
      }

      // 2. GET /device/sync?sinceVersion=<lastConfigVersion>
      final syncUrl = '$kYestreamApiBase/device/sync?sinceVersion=${state.configVersion}';
      final syncRes = await dio.get(syncUrl);

      if (syncRes.statusCode == 200 && syncRes.data is Map) {
        final data = Map<String, dynamic>.from(syncRes.data as Map);

        // Refresh key6 and portalLoginUrl if returned by server
        final deviceData = data['device'] is Map
            ? Map<String, dynamic>.from(data['device'] as Map)
            : data;
        final freshKey = (deviceData['key6'] ?? data['key6'] ?? deviceData['deviceKey'])?.toString().trim();
        final freshPortalUrl = (deviceData['portalLoginUrl'] ?? data['portalLoginUrl'])?.toString().trim();
        if (freshKey != null && freshKey.length == 6) {
          await DeviceIdentityService.updateServerKeyAndPortalUrl(
            key6: freshKey,
            portalUrl: freshPortalUrl,
          );
        }

        final serverTimeStr = data['serverTime']?.toString();
        final serverTime = serverTimeStr != null ? DateTime.tryParse(serverTimeStr) : DateTime.now();

        final trialDays = data['trialDays'] is int ? data['trialDays'] as int : identity.trialDays;
        final status = data['status']?.toString() ?? identity.status;
        final plan = data['plan']?.toString() ?? identity.plan;
        final configVersion = data['configVersion'] is int ? data['configVersion'] as int : state.configVersion;
        final portalUrl = (freshPortalUrl != null && freshPortalUrl.isNotEmpty)
            ? freshPortalUrl
            : (data['portalLoginUrl']?.toString() ?? identity.portalLoginUrl ?? '');

        DateTime? trialEndsAt;
        if (data['trialEndsAt'] != null) {
          trialEndsAt = DateTime.tryParse(data['trialEndsAt'].toString());
        }

        DateTime? expiresAt;
        if (data['expiresAt'] != null) {
          expiresAt = DateTime.tryParse(data['expiresAt'].toString());
        }

        // Calculate days remaining strictly from serverTime and trialEndsAt
        int remaining = trialDays;
        if (trialEndsAt != null && serverTime != null) {
          remaining = trialEndsAt.difference(serverTime).inDays;
          if (trialEndsAt.isAfter(serverTime) && remaining == 0) {
            remaining = 1; // within final 24h
          }
        }

        // 3. Reconcile remote playlists into Drift AppDatabase
        int remoteCount = 0;
        final lockedIds = <String>{};
        final rawPlaylists = data['playlists'];
        if (rawPlaylists is List) {
          final activeRemoteIds = <String>{};
          final existingProviders = await _db.getAllProviders();
          final localProviderMap = {for (final p in existingProviders) p.id: p};

          for (final item in rawPlaylists) {
            if (item is! Map) continue;
            final map = Map<String, dynamic>.from(item);

            final pId = map['id']?.toString() ?? '';
            final localId = map['localId']?.toString();
            var pHost = (map['url'] ?? map['host'])?.toString().trim() ?? '';
            if (pId.isEmpty && (localId == null || localId.isEmpty)) continue;
            if (pHost.isNotEmpty &&
                !pHost.toLowerCase().startsWith('http://') &&
                !pHost.toLowerCase().startsWith('https://')) {
              pHost = 'http://$pHost';
            }

            final pName = map['name']?.toString() ?? 'Remote Playlist';
            final pType = (map['type']?.toString().toLowerCase() == 'm3u') ? 'm3u' : 'xtream';
            final pUser = map['username']?.toString();
            final pPass = map['password']?.toString();
            final isLocked = map['lockedByReseller'] == true || map['locked'] == true;

            // Check if this playlist already exists locally (matched by localId)
            if (localId != null && localProviderMap.containsKey(localId)) {
              if (isLocked) lockedIds.add(localId);
              // Update existing local row if remote metadata changed
              final existing = localProviderMap[localId]!;
              if (existing.name != pName ||
                  existing.url != pHost ||
                  existing.username != pUser ||
                  existing.password != pPass) {
                await _db.upsertProvider(db.ProvidersCompanion(
                  id: Value(localId),
                  name: Value(pName),
                  type: Value(pType),
                  url: Value(pHost),
                  username: Value(pUser),
                  password: Value(pPass),
                ));
              }
              continue; // Do NOT insert a duplicate remote_<pId> row!
            }

            final remoteDbId = 'remote_$pId';
            activeRemoteIds.add(remoteDbId);
            if (isLocked) lockedIds.add(remoteDbId);

            final prev = existingProviders.where((x) => x.id == remoteDbId).firstOrNull;

            await _db.upsertProvider(db.ProvidersCompanion.insert(
              id: remoteDbId,
              name: pName,
              type: pType,
              url: Value(pHost),
              username: Value(pUser),
              password: Value(pPass),
            ));

            final needsRefresh = prev == null ||
                prev.url != pHost ||
                prev.username != pUser ||
                prev.password != pPass;

            if (needsRefresh) {
              _manager.refreshProvider(remoteDbId).catchError((e) {
                debugPrint('[DeviceSync] Error refreshing provider $remoteDbId: $e');
                return 0;
              });
            }
          }

          // Delete orphaned remote playlists (never delete local non-remote playlists)
          final all = await _db.getAllProviders();
          for (final prov in all) {
            if (prov.id.startsWith('remote_') && !activeRemoteIds.contains(prov.id)) {
              await _manager.deleteProvider(prov.id).catchError((_) {});
            }
          }

          remoteCount = activeRemoteIds.length;
        }

        _lastConfigVersion = configVersion;

        // 4. Update state & persist locally
        state = state.copyWith(
          status: status,
          plan: plan,
          trialDays: trialDays,
          daysRemaining: remaining,
          trialEndsAt: trialEndsAt,
          expiresAt: expiresAt,
          serverTime: serverTime,
          portalLoginUrl: portalUrl,
          configVersion: configVersion,
          isSyncing: false,
          lastSyncTime: DateTime.now(),
          remotePlaylistsCount: remoteCount,
          lockedProviderIds: lockedIds,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('device_status', status);
        if (plan != null) await prefs.setString('device_plan', plan);
        await prefs.setInt('device_trial_days', trialDays);
        await prefs.setInt('device_config_version', configVersion);
        await prefs.setStringList('device_locked_provider_ids', lockedIds.toList());
        if (portalUrl.isNotEmpty) await prefs.setString('device_portal_url', portalUrl);
        if (trialEndsAt != null) {
          await prefs.setString('device_trial_ends_at', trialEndsAt.toIso8601String());
        }
        if (expiresAt != null) {
          await prefs.setString('device_expires_at', expiresAt.toIso8601String());
        }
      } else {
        state = state.copyWith(isSyncing: false);
      }
    } catch (e) {
      debugPrint('[DeviceSync] Sync warning: $e');
      state = state.copyWith(isSyncing: false, lastError: e.toString());
    }
  }

  void _connectSse() async {
    _sseSub?.cancel();
    _sseSub = null;

    final identity = await DeviceIdentityService.getIdentity();
    if (identity.credential.isEmpty) return;

    try {
      final dio = Dio(BaseOptions(
        responseType: ResponseType.stream,
        headers: {
          'Authorization': 'Bearer ${identity.credential}',
          'Accept': 'text/event-stream',
        },
      ));

      final response = await dio.get<ResponseBody>('$kYestreamApiBase/device/events');
      if (response.statusCode == 200 && response.data != null) {
        final stream = response.data!.stream;
        _sseSub = stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
          (line) {
            if (line.contains('device.configuration.changed') || line.contains('license.changed')) {
              if (_isMutatingCloud) {
                debugPrint('[DeviceSync] SSE event ignored: mutating cloud in progress');
                return;
              }
              // Ignore stale configVersion events
              try {
                if (line.startsWith('data:')) {
                  final dataStr = line.substring(5).trim();
                  final decoded = jsonDecode(dataStr);
                  if (decoded is Map && decoded['configVersion'] is int) {
                    final eventVer = decoded['configVersion'] as int;
                    if (eventVer <= _lastConfigVersion) {
                      debugPrint('[DeviceSync] SSE event ignored: eventVer $eventVer <= $_lastConfigVersion');
                      return;
                    }
                  }
                }
              } catch (_) {}

              debugPrint('[DeviceSync] SSE Event received: $line — triggering sync');
              sync();
            }
          },
          onError: (err) {
            debugPrint('[DeviceSync] SSE stream closed/error: $err');
          },
          cancelOnError: true,
        );
      }
    } catch (e) {
      debugPrint('[DeviceSync] SSE connection skipped: $e');
    }
  }

  Future<({String platform, String model, String os})> _getTelemetryHardware() async {
    final deviceInfo = DeviceInfoPlugin();
    String platformName = 'Android TV';
    String modelName = 'Generic TV';
    String osVersion = 'Unknown OS';

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
      } else if (PlatformInfo.isAndroid) {
        final android = await deviceInfo.androidInfo;
        platformName = PlatformInfo.isTV ? 'Android TV' : 'Android';
        modelName = '${android.brand} ${android.model}'.trim();
        osVersion = 'Android ${android.version.release} (API ${android.version.sdkInt})';
      } else if (PlatformInfo.isMacOS) {
        final mac = await deviceInfo.macOsInfo;
        platformName = 'macOS';
        modelName = mac.model;
        osVersion = mac.osRelease;
      } else if (PlatformInfo.isWindows) {
        final win = await deviceInfo.windowsInfo;
        platformName = 'Windows';
        modelName = win.computerName;
        osVersion = win.productName;
      }
    } catch (_) {}

    return (platform: platformName, model: modelName, os: osVersion);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicTimer?.cancel();
    _sseSub?.cancel();
    super.dispose();
  }
}

final deviceEntitlementProvider =
    StateNotifierProvider<DeviceSyncNotifier, DeviceEntitlementState>((ref) {
  final dbInstance = ref.watch(databaseProvider);
  final manager = ref.watch(providerManagerProvider);
  return DeviceSyncNotifier(dbInstance, manager);
});
