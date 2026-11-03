import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/datasources/remote/xtream_client.dart';
import '../providers/provider_manager.dart';

const _kActivePlaylistId = 'active_playlist_id';

/// Stream of all IPTV playlists
final allPlaylistsProvider = StreamProvider<List<db.Provider>>((ref) {
  final database = ref.watch(databaseProvider);
  return database.select(database.providers).watch();
});

/// Notifier for the currently active playlist ID
class ActivePlaylistNotifier extends StateNotifier<String?> {
  ActivePlaylistNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_kActivePlaylistId);
    state = savedId;
  }

  Future<void> selectPlaylist(String providerId) async {
    state = providerId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActivePlaylistId, providerId);
  }

  Future<void> clearIfDeleted(String providerId) async {
    if (state == providerId) {
      state = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kActivePlaylistId);
    }
  }
}

final activePlaylistIdProvider =
    StateNotifierProvider<ActivePlaylistNotifier, String?>((ref) {
  return ActivePlaylistNotifier();
});

/// Current active playlist object (falls back to the first available if not set)
final activePlaylistProvider = Provider<db.Provider?>((ref) {
  final playlistsAsync = ref.watch(allPlaylistsProvider);
  final activeId = ref.watch(activePlaylistIdProvider);

  return playlistsAsync.when(
    data: (list) {
      if (list.isEmpty) return null;
      if (activeId != null) {
        final match = list.where((p) => p.id == activeId);
        if (match.isNotEmpty) return match.first;
      }
      return list.first;
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

/// Checks if active playlist has VOD/Movies
final activePlaylistHasMoviesProvider = FutureProvider<bool>((ref) async {
  final playlist = ref.watch(activePlaylistProvider);
  if (playlist == null) return false;
  final dbInstance = ref.watch(databaseProvider);
  final count = await (dbInstance.select(dbInstance.channels)
        ..where((t) =>
            t.providerId.equals(playlist.id) & t.streamType.equals('vod')))
      .get();
  return count.isNotEmpty;
});

/// Checks if active playlist has Series
final activePlaylistHasSeriesProvider = FutureProvider<bool>((ref) async {
  final playlist = ref.watch(activePlaylistProvider);
  if (playlist == null) return false;
  final dbInstance = ref.watch(databaseProvider);
  final count = await (dbInstance.select(dbInstance.channels)
        ..where((t) =>
            t.providerId.equals(playlist.id) & t.streamType.equals('series')))
      .get();
  return count.isNotEmpty;
});

/// Channel counts for active playlist (live, vod, series)
class PlaylistStats {
  final int liveCount;
  final int moviesCount;
  final int seriesCount;

  const PlaylistStats({
    this.liveCount = 0,
    this.moviesCount = 0,
    this.seriesCount = 0,
  });

  int get total => liveCount + moviesCount + seriesCount;
}

final activePlaylistStatsProvider = FutureProvider<PlaylistStats>((ref) async {
  final playlist = ref.watch(activePlaylistProvider);
  if (playlist == null) return const PlaylistStats();
  final dbInstance = ref.watch(databaseProvider);
  final all = await (dbInstance.select(dbInstance.channels)
        ..where((t) => t.providerId.equals(playlist.id)))
      .get();

  int live = 0;
  int vod = 0;
  int series = 0;

  for (final c in all) {
    if (c.streamType == 'vod') {
      vod++;
    } else if (c.streamType == 'series') {
      series++;
    } else {
      live++;
    }
  }

  return PlaylistStats(
    liveCount: live,
    moviesCount: vod,
    seriesCount: series,
  );
});

/// Account information (status, expiration date, max connections)
class AccountInfo {
  final String? status;
  final DateTime? expDate;
  final int? maxConnections;
  final int? activeCons;
  final bool isTrial;

  const AccountInfo({
    this.status,
    this.expDate,
    this.maxConnections,
    this.activeCons,
    this.isTrial = false,
  });
}

/// Provider for active playlist account & subscription details
final activePlaylistAccountInfoProvider =
    FutureProvider<AccountInfo?>((ref) async {
  final playlist = ref.watch(activePlaylistProvider);
  if (playlist == null) return null;
  if (playlist.type != 'xtream' ||
      playlist.url == null ||
      playlist.username == null ||
      playlist.password == null) {
    return null;
  }

  final prefs = await SharedPreferences.getInstance();
  final expMillis = prefs.getInt('xtream_exp_${playlist.id}');
  final status = prefs.getString('xtream_status_${playlist.id}');
  final maxConn = prefs.getInt('xtream_max_conn_${playlist.id}');
  final activeConn = prefs.getInt('xtream_active_conn_${playlist.id}');
  final isTrial = prefs.getBool('xtream_is_trial_${playlist.id}') ?? false;

  AccountInfo? cached;
  if (expMillis != null || status != null) {
    cached = AccountInfo(
      status: status,
      expDate: expMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(expMillis)
          : null,
      maxConnections: maxConn,
      activeCons: activeConn,
      isTrial: isTrial,
    );
  }

  try {
    final client = XtreamClient(
      baseUrl: playlist.url!,
      username: playlist.username!,
      password: playlist.password!,
    );
    final serverInfo = await client.authenticate();
    client.dispose();

    if (serverInfo.expDate != null) {
      await prefs.setInt(
          'xtream_exp_${playlist.id}', serverInfo.expDate!.millisecondsSinceEpoch);
    }
    if (serverInfo.status != null) {
      await prefs.setString(
          'xtream_status_${playlist.id}', serverInfo.status!);
    }
    if (serverInfo.maxConnections != null) {
      await prefs.setInt(
          'xtream_max_conn_${playlist.id}', serverInfo.maxConnections!);
    }
    if (serverInfo.activeCons != null) {
      await prefs.setInt(
          'xtream_active_conn_${playlist.id}', serverInfo.activeCons!);
    }
    await prefs.setBool(
        'xtream_is_trial_${playlist.id}', serverInfo.isTrial);

    return AccountInfo(
      status: serverInfo.status,
      expDate: serverInfo.expDate,
      maxConnections: serverInfo.maxConnections,
      activeCons: serverInfo.activeCons,
      isTrial: serverInfo.isTrial,
    );
  } catch (_) {
    return cached;
  }
});

