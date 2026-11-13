import 'dart:io';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../datasources/local/database.dart' as db;
import '../datasources/parsers/xmltv_parser.dart';
import '../models/epg.dart';
import '../../features/providers/provider_manager.dart';

/// Runs heavy XML parsing in a background isolate.
XmltvResult _parseInIsolate(_ParseArgs args) {
  return XmltvParser().parse(args.xml, sourceId: args.sourceId);
}

class _ParseArgs {
  final String xml;
  final String sourceId;
  const _ParseArgs(this.xml, this.sourceId);
}

class EpgRefreshService {
  final db.AppDatabase _db;
  bool _isRefreshing = false;

  EpgRefreshService(this._db);

  /// Refresh a single EPG source by ID.
  Future<void> refreshSource(String sourceId) async {
    final sources = await _db.getAllEpgSources();
    final source = sources.firstWhere((s) => s.id == sourceId);
    debugPrint('[EPG] Refreshing source: ${source.name} (${source.url})');

    // Download XMLTV data
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: kIsWeb
          ? null
          : const {
              'User-Agent': 'clubTivi/1.0 IPTV Player (compatible; XMLTV fetcher)',
            },
    ));
    try {
      final response = await dio.get<List<int>>(
        source.url,
        options: Options(responseType: ResponseType.bytes),
      );

      final bytes = response.data!;
      debugPrint('[EPG] Downloaded ${bytes.length} bytes');

      // Decompress + parse in background isolate to avoid ANR
      final result = await compute(_decompressAndParse, _DecompressParseArgs(bytes, sourceId));
      debugPrint('[EPG] Parsed ${result.channels.length} channels, ${result.programmes.length} programmes');

      // Store channels
      final channelCompanions = result.channels.map((c) {
        return db.EpgChannelsCompanion.insert(
          id: '${sourceId}_${c.id}',
          sourceId: sourceId,
          channelId: c.id,
          displayName: c.primaryName,
          iconUrl: Value(c.iconUrl),
        );
      }).toList();
      await _db.upsertEpgChannels(channelCompanions);

      // Delete old programmes for this source, then insert new ones in batches
      await _db.deleteEpgProgrammesForSource(sourceId);
      final programmeCompanions = result.programmes.map((p) {
        return db.EpgProgrammesCompanion.insert(
          epgChannelId: '${sourceId}_${p.channelId}',
          sourceId: sourceId,
          title: p.title,
          description: Value(p.description),
          category: Value(p.category),
          subtitle: Value(p.subtitle),
          episodeNum: Value(p.episodeNum),
          start: p.start,
          stop: p.stop,
        );
      }).toList();
      if (programmeCompanions.isNotEmpty) {
        // Insert in batches of 1000 to keep UI frame times responsive.
        for (var i = 0; i < programmeCompanions.length; i += 1000) {
          final end = (i + 1000).clamp(0, programmeCompanions.length);
          await _db.insertEpgProgrammes(programmeCompanions.sublist(i, end));
          // Yield to the event loop between batches
          await Future<void>.delayed(Duration.zero);
        }
      }

      // Update last refresh timestamp
      await _db.updateEpgSourceRefreshTime(sourceId);
    } finally {
      dio.close();
    }
  }

  /// Refresh all enabled EPG sources (skips sources refreshed within the last 4 hours).
  Future<void> refreshAllSources({bool force = false}) async {
    // Web/Smart TV browsers lack background Isolates, so automatic 40MB XMLTV
    // parsing blocks the single UI JS thread. Short EPG loads per channel on demand.
    if (kIsWeb && !force) return;
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final sources = await _db.getAllEpgSources();
      final now = DateTime.now();
      for (final source in sources.where((s) => s.enabled)) {
        if (!force &&
            source.lastRefresh != null &&
            now.difference(source.lastRefresh!).inHours < 4) {
          debugPrint('[EPG] Skipping ${source.name} — refreshed ${now.difference(source.lastRefresh!).inMinutes}m ago');
          continue;
        }
        try {
          await refreshSource(source.id);
        } catch (e) {
          debugPrint('[EPG] Error refreshing ${source.name}: $e');
        }
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// Legacy cleanup: remove any previously seeded third-party EPG sources (EPG comes from provider).
  Future<void> cleanupLegacyDefaultSources() async {
    final existing = await _db.getAllEpgSources();
    for (final s in existing) {
      final u = s.url.toLowerCase();
      final n = s.name.toLowerCase();
      if (u.contains('epg.best') ||
          u.contains('usa-locals') ||
          n.contains('epg.best') ||
          n.contains('usa locals')) {
        await _db.deleteEpgSource(s.id);
      }
    }
  }

  /// Automatically registers XMLTV EPG sources for Xtream / M3U providers in the database.
  Future<void> syncProviderEpgSources() async {
    await cleanupLegacyDefaultSources();
    final providers = await _db.getAllProviders();

    for (final p in providers) {
      String? epgUrl;
      if (p.type == 'xtream' && p.url != null && p.url!.isNotEmpty) {
        final cleanBase = p.url!.trim().replaceAll(RegExp(r'/+$'), '');
        final user = Uri.encodeComponent(p.username ?? '');
        final pass = Uri.encodeComponent(p.password ?? '');
        epgUrl = '$cleanBase/xmltv.php?username=$user&password=$pass';
      } else if (p.type == 'm3u' && p.url != null) {
        final creds = parseXtreamFromM3uUrl(p.url!);
        if (creds != null) {
          final cleanBase = creds.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
          final user = Uri.encodeComponent(creds.username);
          final pass = Uri.encodeComponent(creds.password);
          epgUrl = '$cleanBase/xmltv.php?username=$user&password=$pass';
        }
      }

      if (epgUrl != null && epgUrl.isNotEmpty) {
        final sourceId = 'epg_${p.id}';
        await _db.upsertEpgSource(db.EpgSourcesCompanion.insert(
          id: sourceId,
          name: '${p.name} EPG',
          url: epgUrl,
          enabled: const Value(true),
        ));
      }
    }
  }

  /// Kept for API compatibility; cleans up legacy third-party feeds without seeding external ones.
  Future<void> addDefaultSources() async {
    await syncProviderEpgSources();
  }

  /// Delete all existing sources.
  Future<void> resetToDefaultSources() async {
    final existing = await _db.getAllEpgSources();
    for (final s in existing) {
      await _db.deleteEpgSource(s.id);
    }
  }
}

final epgRefreshServiceProvider = Provider<EpgRefreshService>((ref) {
  return EpgRefreshService(ref.watch(databaseProvider));
});

/// Args for the background isolate (must be serializable).
class _DecompressParseArgs {
  final List<int> bytes;
  final String sourceId;
  const _DecompressParseArgs(this.bytes, this.sourceId);
}

/// Top-level function for compute() — runs decompression + XML parsing off the main thread.
XmltvResult _decompressAndParse(_DecompressParseArgs args) {
  List<int> decompressed;
  try {
    decompressed = gzip.decode(args.bytes);
  } catch (_) {
    decompressed = args.bytes;
  }
  final xmlContent = utf8.decode(decompressed, allowMalformed: true);
  return XmltvParser().parse(xmlContent, sourceId: args.sourceId);
}
