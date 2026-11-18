import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/datasources/parsers/m3u_parser.dart';
import '../../data/datasources/remote/xtream_client.dart';
import '../../data/models/channel.dart' hide Provider;
import '../../data/services/logo_resolver_service.dart';
import '../../data/services/epg_refresh_service.dart';
import '../../core/feature_gate.dart';
import 'package:dio/dio.dart';

/// Parse Xtream credentials from an M3U URL if present (e.g. get.php?username=...&password=...)
({String baseUrl, String username, String password})? parseXtreamFromM3uUrl(String url) {
  try {
    final uri = Uri.parse(url.trim());
    final username = uri.queryParameters['username'];
    final password = uri.queryParameters['password'];
    if (username != null && username.isNotEmpty && password != null && password.isNotEmpty) {
      final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
      final host = uri.host;
      final port = uri.hasPort ? ':${uri.port}' : '';
      final baseUrl = '$scheme://$host$port';
      return (baseUrl: baseUrl, username: username, password: password);
    }
  } catch (_) {}
  return null;
}

/// Normalize IPTV URL to ensure it always includes http:// or https://
String normalizeProviderUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  if (!trimmed.toLowerCase().startsWith('http://') &&
      !trimmed.toLowerCase().startsWith('https://')) {
    return 'http://$trimmed';
  }
  return trimmed;
}

/// Manages IPTV providers: adding, refreshing, channel loading.
class ProviderManager {
  final db.AppDatabase _db;
  final M3uParser _m3uParser = M3uParser();

  ProviderManager(this._db);

  /// Check provider count against tier limit.
  Future<void> _checkProviderLimit([String? allowExistingId]) async {
    final existing = await _db.getAllProviders();
    if (allowExistingId != null && existing.any((p) => p.id == allowExistingId)) {
      return;
    }
    if (existing.length >= FeatureGate.maxProviders) {
      throw ProviderLimitException(FeatureGate.maxProviders);
    }
  }

  /// Add an M3U provider. Verifies the playlist and parses channels before saving to DB.
  Future<int> addM3uProvider({
    required String id,
    required String name,
    required String url,
    void Function(int step, String message)? onProgress,
  }) async {
    final cleanUrl = normalizeProviderUrl(url);
    await _checkProviderLimit(id);
    // Auto-detect Xtream link disguised as M3U
    final xtreamCreds = parseXtreamFromM3uUrl(cleanUrl);
    if (xtreamCreds != null) {
      return addXtreamProvider(
        id: id,
        name: name,
        url: xtreamCreds.baseUrl,
        username: xtreamCreds.username,
        password: xtreamCreds.password,
        onProgress: onProgress,
      );
    }

    final tempProvider = db.Provider(
      id: id,
      name: name,
      type: 'm3u',
      url: cleanUrl,
      username: null,
      password: null,
      sortOrder: 0,
      enabled: true,
      lastRefresh: null,
      createdAt: DateTime.now(),
    );

    // Verify & fetch channels FIRST before adding to DB
    final channels = await _refreshM3u(tempProvider, onProgress: onProgress);
    if (channels.isEmpty) {
      throw Exception('No playable channels found in this M3U playlist.');
    }

    await _saveProviderWithChannels(
      providerEntry: db.ProvidersCompanion.insert(
        id: id,
        name: name,
        type: 'm3u',
        url: Value(cleanUrl),
      ),
      providerId: id,
      channels: channels,
      onProgress: onProgress,
    );
    return channels.length;
  }

  /// Add an Xtream Codes provider. Verifies login credentials and streams before saving to DB.
  Future<int> addXtreamProvider({
    required String id,
    required String name,
    required String url,
    required String username,
    required String password,
    void Function(int step, String message)? onProgress,
  }) async {
    final cleanUrl = normalizeProviderUrl(url);
    await _checkProviderLimit(id);

    final tempProvider = db.Provider(
      id: id,
      name: name,
      type: 'xtream',
      url: cleanUrl,
      username: username,
      password: password,
      sortOrder: 0,
      enabled: true,
      lastRefresh: null,
      createdAt: DateTime.now(),
    );

    // Verify & fetch channels FIRST before adding to DB
    final channels = await _refreshXtream(tempProvider, onProgress: onProgress);
    if (channels.isEmpty) {
      throw const XtreamException('No channels or streams found on this IPTV account.');
    }

    await _saveProviderWithChannels(
      providerEntry: db.ProvidersCompanion.insert(
        id: id,
        name: name,
        type: 'xtream',
        url: Value(cleanUrl),
        username: Value(username),
        password: Value(password),
      ),
      providerId: id,
      channels: channels,
      onProgress: onProgress,
    );
    return channels.length;
  }

  /// Persists a newly verified provider and its channels cleanly.
  /// Rolls back the provider row if saving channels fails so empty 0/0/0 playlists never remain.
  Future<void> _saveProviderWithChannels({
    required db.ProvidersCompanion providerEntry,
    required String providerId,
    required List<Channel> channels,
    void Function(int step, String message)? onProgress,
  }) async {
    onProgress?.call(4, 'Saving ${channels.length} items...');
    await _db.upsertProvider(providerEntry);
    try {
      const batchSize = 3000;
      final total = channels.length;
      for (var i = 0; i < total; i += batchSize) {
        final end = (i + batchSize < total) ? i + batchSize : total;
        final slice = channels.sublist(i, end);
        final companions = List<db.ChannelsCompanion>.generate(slice.length, (idx) {
          final c = slice[idx];
          return db.ChannelsCompanion.insert(
            id: c.id,
            providerId: c.providerId,
            name: c.name,
            tvgId: Value(c.tvgId),
            tvgName: Value(c.tvgName),
            tvgLogo: Value(c.tvgLogo),
            groupTitle: Value(c.groupTitle),
            channelNumber: Value(c.channelNumber),
            streamUrl: c.streamUrl,
            streamType: Value(c.streamType.name),
            sortOrder: Value(i + idx),
          );
        });

        await _db.upsertChannels(
          companions,
          onProgress: (saved, _) {
            onProgress?.call(4, 'Saving ${i + saved} / $total...');
          },
        );
        // Yield so Android / Fire TV garbage collector can free intermediate companions
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    } catch (e) {
      // Roll back the orphaned provider row so UI never shows 0 Live / 0 Movies / 0 Series
      try {
        await _db.deleteProvider(providerId);
      } catch (_) {}
      rethrow;
    }

    final liveOnly = channels.where((c) => c.streamType == StreamType.live).take(250).toList();
    if (liveOnly.isNotEmpty) {
      _resolveChannelLogos(liveOnly).catchError((_) {});
    }

    // Auto-sync and refresh EPG from provider credentials
    final epgService = EpgRefreshService(_db);
    epgService.syncProviderEpgSources().then((_) {
      epgService.refreshSource('epg_$providerId').catchError((_) {});
    }).catchError((_) {});
  }

  /// Refresh a provider's channels from its source.
  Future<int> refreshProvider(String providerId) async {
    final providers = await _db.getAllProviders();
    final provider = providers.firstWhere((p) => p.id == providerId);

    List<Channel> channels;
    if (provider.type == 'm3u') {
      channels = await _refreshM3u(provider);
    } else if (provider.type == 'xtream') {
      channels = await _refreshXtream(provider);
    } else {
      return 0;
    }

    if (channels.isEmpty) {
      throw Exception('No channels found for this provider.');
    }

    // Save channels to database in chunks to prevent heap explosion on TV
    const batchSize = 3000;
    final total = channels.length;
    for (var i = 0; i < total; i += batchSize) {
      final end = (i + batchSize < total) ? i + batchSize : total;
      final slice = channels.sublist(i, end);
      final companions = List<db.ChannelsCompanion>.generate(slice.length, (idx) {
        final c = slice[idx];
        return db.ChannelsCompanion.insert(
          id: c.id,
          providerId: c.providerId,
          name: c.name,
          tvgId: Value(c.tvgId),
          tvgName: Value(c.tvgName),
          tvgLogo: Value(c.tvgLogo),
          groupTitle: Value(c.groupTitle),
          channelNumber: Value(c.channelNumber),
          streamUrl: c.streamUrl,
          streamType: Value(c.streamType.name),
          sortOrder: Value(i + idx),
        );
      });
      await _db.upsertChannels(companions);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    // Resolve missing logos in background (capped to 250 to keep TV smooth)
    final liveOnly = channels.where((c) => c.streamType == StreamType.live).take(250).toList();
    if (liveOnly.isNotEmpty) {
      _resolveChannelLogos(liveOnly).catchError((_) {});
    }

    // Auto-sync and refresh EPG from provider credentials
    final epgService = EpgRefreshService(_db);
    epgService.syncProviderEpgSources().then((_) {
      epgService.refreshSource('epg_$providerId').catchError((_) {});
    }).catchError((_) {});

    return channels.length;
  }

  Future<List<Channel>> _refreshM3u(
    db.Provider provider, {
    void Function(int step, String message)? onProgress,
  }) async {
    final xtreamCreds = parseXtreamFromM3uUrl(provider.url ?? '');
    if (xtreamCreds != null) {
      final client = XtreamClient(
        baseUrl: xtreamCreds.baseUrl,
        username: xtreamCreds.username,
        password: xtreamCreds.password,
      );
      try {
        onProgress?.call(1, 'Verifying Xtream credentials...');
        await client.authenticate();

        onProgress?.call(2, 'Loading categories...');
        final liveCats = await client.getLiveCategories();
        final liveCatMap = {for (final c in liveCats) c.id: c.name};
        final vodCats = await client.getVodCategories();
        final seriesCats = await client.getSeriesCategories();

        final prefs = await SharedPreferences.getInstance();
        if (vodCats.isNotEmpty) {
          await prefs.setString(
            'xtream_vod_cats_${provider.id}',
            jsonEncode(vodCats.map((c) => {'id': c.id, 'name': c.name}).toList()),
          );
        }
        if (seriesCats.isNotEmpty) {
          await prefs.setString(
            'xtream_series_cats_${provider.id}',
            jsonEncode(seriesCats.map((c) => {'id': c.id, 'name': c.name}).toList()),
          );
        }

        onProgress?.call(3, 'Loading Live channels...');
        final lives = await client.getLiveStreams(providerId: provider.id, categoryMap: liveCatMap);
        if (lives.isNotEmpty) return lives;
      } catch (e) {
        debugPrint('[M3uXtream] Xtream API check failed: $e; falling back to direct download');
      } finally {
        client.dispose();
      }
    }

    onProgress?.call(1, 'Connecting to M3U URL...');
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)',
          'Accept': '*/*',
        },
      ),
    );
    try {
      final cleanUrl = normalizeProviderUrl(provider.url ?? '');
      final response = await dio.get<String>(cleanUrl);
      if (response.statusCode != null && (response.statusCode! < 200 || response.statusCode! >= 300)) {
        throw Exception('Server returned HTTP ${response.statusCode} when loading M3U');
      }

      final body = response.data?.trim() ?? '';
      if (body.isEmpty) {
        throw Exception('M3U playlist is empty (0 bytes received)');
      }

      if (body.startsWith('<!DOCTYPE') || body.startsWith('<html') || body.startsWith('<?xml') || body.startsWith('{')) {
        throw Exception('URL returned a web page or invalid document instead of an M3U playlist');
      }

      onProgress?.call(2, 'Parsing playlist...');
      final result = _m3uParser.parse(body, providerId: provider.id);
      if (result.channels.isEmpty) {
        final err = result.errors.isNotEmpty ? result.errors.first : 'No valid channels found in M3U file';
        throw Exception(err);
      }

      onProgress?.call(3, 'Parsed ${result.channels.length} channels');
      return result.channels;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw Exception('M3U playlist requires login (wrong username/password or protected URL)');
      }
      if (code == 404) {
        throw Exception('M3U playlist not found (HTTP 404)');
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw Exception('Could not reach playlist URL: connection timed out');
        case DioExceptionType.connectionError:
          throw Exception('Could not reach playlist URL: connection failed');
        default:
          final msg = e.message ?? e.type.name;
          if (msg.toLowerCase().contains('xmlhttprequest') ||
              msg.toLowerCase().contains('network layer')) {
            throw Exception('Could not reach playlist URL: connection failed');
          }
          throw Exception('Could not reach playlist URL: $msg');
      }
    } finally {
      dio.close();
    }
  }

  Future<List<Channel>> _refreshXtream(
    db.Provider provider, {
    void Function(int step, String message)? onProgress,
  }) async {
    final cleanUrl = normalizeProviderUrl(provider.url ?? '');
    final client = XtreamClient(
      baseUrl: cleanUrl,
      username: provider.username ?? '',
      password: provider.password ?? '',
    );
    try {
      // 1. Authenticate FIRST! If credentials are fake, this will throw XtreamAuthException immediately!
      onProgress?.call(1, 'Authenticating credentials with Xtream server...');
      final auth = await client.authenticate();
      debugPrint('[Xtream] Authentication verified: status=${auth.status}, user=${provider.username}');

      // 2. Fetch category mappings in parallel
      onProgress?.call(2, 'Loading categories...');
      final catResults = await Future.wait([
        client.getLiveCategories().catchError((Object e) {
          debugPrint('[Xtream] Could not fetch live categories: $e');
          return <XtreamCategory>[];
        }),
        client.getVodCategories().catchError((Object e) {
          debugPrint('[Xtream] Could not fetch VOD categories: $e');
          return <XtreamCategory>[];
        }),
        client.getSeriesCategories().catchError((Object e) {
          debugPrint('[Xtream] Could not fetch series categories: $e');
          return <XtreamCategory>[];
        }),
      ]);
      final liveCatMap = {for (final c in catResults[0]) c.id: c.name};
      final vodCats = catResults[1];
      final seriesCats = catResults[2];

      // Persist VOD and Series categories metadata for instant on-demand lazy loading
      final prefs = await SharedPreferences.getInstance();
      if (vodCats.isNotEmpty) {
        await prefs.setString(
          'xtream_vod_cats_${provider.id}',
          jsonEncode(vodCats.map((c) => {'id': c.id, 'name': c.name}).toList()),
        );
      }
      if (seriesCats.isNotEmpty) {
        await prefs.setString(
          'xtream_series_cats_${provider.id}',
          jsonEncode(seriesCats.map((c) => {'id': c.id, 'name': c.name}).toList()),
        );
      }

      // 3. Fetch Live TV streams only (Movies and Series are loaded on demand per category)
      onProgress?.call(3, 'Downloading Live TV channels...');
      List<Channel> lives = [];
      Object? liveErr;
      try {
        lives = await client.getLiveStreams(
          providerId: provider.id,
          categoryMap: liveCatMap,
        );
      } catch (e) {
        liveErr = e;
        debugPrint('[Xtream] Failed to fetch live streams: $e');
      }

      if (lives.isEmpty) {
        // If live stream fetch failed, try fetching first VOD category as fallback
        if (vodCats.isNotEmpty) {
          try {
            final firstCatId = vodCats.first.id;
            final fallbackVods = await client.getVodStreams(
              categoryId: firstCatId,
              providerId: provider.id,
              categoryMap: {firstCatId: vodCats.first.name},
            );
            if (fallbackVods.isNotEmpty) return fallbackVods;
          } catch (_) {}
        }
        if (liveErr != null) {
          throw XtreamServerException('Failed to download streams: $liveErr');
        }
        throw const XtreamException('Authentication succeeded, but no streams or channels were found on this account.');
      }

      return lives;
    } finally {
      client.dispose();
    }
  }

  Future<void> deleteProvider(String id) async {
    await _db.deleteProvider(id);
    await _db.deleteEpgSource('epg_$id').catchError((_) {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('xtream_vod_cats_$id');
    await prefs.remove('xtream_series_cats_$id');
    if (prefs.getString('active_playlist_id') == id) {
      await prefs.remove('active_playlist_id');
    }
  }

  static final _prefixRe1 = RegExp(r'^[a-z]{2}[-]?[a-z]?\|\s*');
  static final _prefixRe2 = RegExp(r'^[a-z]{2}:\s+');
  static final _prefixRe3 = RegExp(r'^\[?[a-z]{2}\]?\s+');
  static final _prefixRe4 = RegExp(r'^[a-z]{2}\s+');

  /// Resolve missing logos in background after provider refresh.
  Future<void> _resolveChannelLogos(List<Channel> channels) async {
    await resolveLogosForChannels(channels);
  }

  /// Resolve missing logos for a set of channels.
  /// Public so it can be called at startup for existing DB channels.
  Future<void> resolveLogosForChannels(List<Channel> channels) async {
    // Only resolve the first 250 missing logos to avoid thrashing CPU/memory on TV devices
    final needsLogo = channels
        .where((c) => c.tvgLogo == null || c.tvgLogo!.isEmpty)
        .take(250)
        .map((c) => (id: c.id, name: c.name, tvgLogo: c.tvgLogo))
        .toList();

    if (needsLogo.isEmpty) return;
    debugPrint('[Logo] ${needsLogo.length} channels need logos');

    final resolved = <String, String>{};

    // First try EPG icons for channels that have EPG mappings
    try {
      final epgChannels = await _db.select(_db.epgChannels).get();
      final epgIconMap = <String, String>{};
      for (final ec in epgChannels) {
        if (ec.iconUrl != null && ec.iconUrl!.isNotEmpty) {
          epgIconMap[ec.displayName.toLowerCase()] = ec.iconUrl!;
          epgIconMap[ec.channelId.toLowerCase()] = ec.iconUrl!;
        }
      }
      for (final ch in needsLogo.toList()) {
        final lower = ch.name.toLowerCase();
        final stripped = lower
            .replaceAll(_prefixRe1, '')
            .replaceAll(_prefixRe2, '')
            .replaceAll(_prefixRe3, '')
            .replaceAll(_prefixRe4, '');
        final icon = epgIconMap[lower] ?? epgIconMap[stripped];
        if (icon != null) {
          resolved[ch.id] = icon;
          needsLogo.removeWhere((c) => c.id == ch.id);
        }
      }
      debugPrint('[Logo] EPG icons resolved ${resolved.length} channels');
    } catch (_) {}

    // Then resolve remaining from tv-logo/tv-logos GitHub repo
    if (needsLogo.isNotEmpty) {
      debugPrint('[Logo] Resolving ${needsLogo.length} via GitHub tv-logos...');
      final ghResolved = await LogoResolverService.resolveLogosForChannels(needsLogo);
      debugPrint('[Logo] GitHub resolved ${ghResolved.length} logos');
      resolved.addAll(ghResolved);
    }

    // Batch-write all resolved logos in a single transaction
    if (resolved.isNotEmpty) {
      await _db.updateChannelLogos(resolved);
    }
  }

  static const _logoResolvedKey = 'logo_last_resolved';
  static const _logoChannelCountKey = 'logo_channel_count';
  static const _logoCooldown = Duration(hours: 6);
  static const _logoBatchSize = 200;

  /// Resolve missing logos progressively: favorites first, then the rest
  /// in small batches so the UI stays responsive.
  /// Skips entirely if resolved recently and channel count hasn't changed.
  Future<void> resolveAllMissingLogos() async {
    final prefs = await SharedPreferences.getInstance();
    final lastResolved = prefs.getInt(_logoResolvedKey) ?? 0;
    final lastCount = prefs.getInt(_logoChannelCountKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - lastResolved;

    final missingLive = await _db.getLiveChannelsMissingLogos();

    // Skip if resolved recently AND count hasn't changed
    if (age < _logoCooldown.inMilliseconds && missingLive.length == lastCount) {
      return;
    }

    final needsLogo = missingLive
        .map((c) => (id: c.id, name: c.name, tvgLogo: c.tvgLogo))
        .toList();

    if (needsLogo.isEmpty) {
      await prefs.setInt(_logoResolvedKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_logoChannelCountKey, 0);
      return;
    }

    // Build lookup maps once
    final epgIconMap = await _buildEpgIconMap();
    await LogoResolverService.ensureIndex(); // pre-load GitHub index

    // Partition: favorites first, then the rest
    final favIds = await _db.getAllFavoritedChannelIds();
    final favorites = needsLogo.where((c) => favIds.contains(c.id)).toList();
    final rest = needsLogo.where((c) => !favIds.contains(c.id)).toList();

    debugPrint('[Logo] ${needsLogo.length} missing (${favorites.length} favorites, ${rest.length} other)');

    // Resolve favorites immediately
    if (favorites.isNotEmpty) {
      final resolved = await _resolveLogoBatch(favorites, epgIconMap);
      if (resolved.isNotEmpty) {
        await _db.updateChannelLogos(resolved);
        debugPrint('[Logo] Favorites: resolved ${resolved.length} logos');
      }
    }

    // Resolve rest in small batches with yields between
    for (var i = 0; i < rest.length; i += _logoBatchSize) {
      final batch = rest.sublist(i, (i + _logoBatchSize).clamp(0, rest.length));
      final resolved = await _resolveLogoBatch(batch, epgIconMap);
      if (resolved.isNotEmpty) {
        await _db.updateChannelLogos(resolved);
      }
      // Yield to UI between batches
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    debugPrint('[Logo] Resolution complete');
    await prefs.setInt(_logoResolvedKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(_logoChannelCountKey, missingLive.length);
  }

  /// Build EPG icon lookup map (display name / channel ID → icon URL).
  Future<Map<String, String>> _buildEpgIconMap() async {
    final map = <String, String>{};
    try {
      final epgChannels = await _db.select(_db.epgChannels).get();
      for (final ec in epgChannels) {
        if (ec.iconUrl != null && ec.iconUrl!.isNotEmpty) {
          map[ec.displayName.toLowerCase()] = ec.iconUrl!;
          map[ec.channelId.toLowerCase()] = ec.iconUrl!;
        }
      }
    } catch (_) {}
    return map;
  }

  /// Resolve logos for a batch of channels using EPG icons + GitHub tv-logos.
  Future<Map<String, String>> _resolveLogoBatch(
    List<({String id, String name, String? tvgLogo})> channels,
    Map<String, String> epgIconMap,
  ) async {
    final resolved = <String, String>{};
    final remaining = <({String id, String name, String? tvgLogo})>[];

    for (final ch in channels) {
      final stripped = ch.name.toLowerCase()
          .replaceAll(RegExp(r'^[a-z]{2}[-]?[a-z]?\|\s*'), '')
          .replaceAll(RegExp(r'^[a-z]{2}:\s+'), '')
          .replaceAll(RegExp(r'^\[?[a-z]{2}\]?\s+'), '')
          .replaceAll(RegExp(r'^[a-z]{2}\s+'), '');
      final icon = epgIconMap[ch.name.toLowerCase()] ?? epgIconMap[stripped];
      if (icon != null) {
        resolved[ch.id] = icon;
      } else {
        remaining.add(ch);
      }
    }

    if (remaining.isNotEmpty) {
      final ghResolved = await LogoResolverService.resolveLogosForChannels(remaining);
      resolved.addAll(ghResolved);
    }

    return resolved;
  }
}

class ProviderLimitException implements Exception {
  final int limit;
  const ProviderLimitException(this.limit);

  @override
  String toString() =>
      'Provider limit reached ($limit). Upgrade to Pro for unlimited providers.';
}

/// Riverpod provider for the database.
final databaseProvider = Provider<db.AppDatabase>((ref) {
  final database = db.AppDatabase();
  ref.onDispose(() => database.close());
  return database;
});

/// Riverpod provider for the provider manager.
final providerManagerProvider = Provider<ProviderManager>((ref) {
  return ProviderManager(ref.watch(databaseProvider));
});
