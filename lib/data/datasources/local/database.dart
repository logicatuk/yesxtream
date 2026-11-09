import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'tables.dart';

part 'database.g.dart';

const _uuid = Uuid();

@DriftDatabase(tables: [
  Providers,
  Channels,
  EpgSources,
  EpgChannels,
  EpgProgrammes,
  EpgMappings,
  ChannelGroups,
  FavoriteLists,
  FavoriteListChannels,
  EpgReminders,
  ScheduledRecordings,
  FailoverGroups,
  FailoverGroupChannels,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON;');
          await customStatement('PRAGMA journal_mode = WAL;');
          await customStatement('PRAGMA synchronous = NORMAL;');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_channels_provider_stream ON channels(provider_id, stream_type);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_channels_group ON channels(provider_id, group_title);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_channels_prov_strm_sort ON channels(provider_id, stream_type, sort_order);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_channels_strm_sort ON channels(stream_type, sort_order);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_channels_prov_strm_grp_sort ON channels(provider_id, stream_type, group_title, sort_order);');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_epg_prog_range ON epg_programmes(epg_channel_id, start, stop);');
          // Purge any orphaned channels from deleted providers
          await customStatement('DELETE FROM channels WHERE provider_id NOT IN (SELECT id FROM providers);');
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(favoriteLists);
            await m.createTable(favoriteListChannels);
          }
          if (from < 3) {
            await m.createTable(epgReminders);
            await m.createTable(scheduledRecordings);
          }
          if (from < 4) {
            await m.addColumn(epgProgrammes, epgProgrammes.subtitle);
            await m.addColumn(epgProgrammes, epgProgrammes.episodeNum);
          }
          if (from < 5) {
            await m.createTable(failoverGroups);
            await m.createTable(failoverGroupChannels);
          }
        },
      );

  // --- Provider queries ---

  Future<List<Provider>> getAllProviders() => select(providers).get();

  Future<void> upsertProvider(ProvidersCompanion entry) =>
      into(providers).insertOnConflictUpdate(entry);

  Future<void> deleteProvider(String id) async {
    await customStatement('PRAGMA foreign_keys = OFF;');
    try {
      await transaction(() async {
        // 1. Delete EPG mappings associated with this provider or any of its channels
        await customStatement(
          'DELETE FROM epg_mappings WHERE provider_id = ? OR channel_id IN (SELECT id FROM channels WHERE provider_id = ?);',
          [id, id],
        );

        // 2. Delete favorite list references to this provider's channels
        await customStatement(
          'DELETE FROM favorite_list_channels WHERE channel_id IN (SELECT id FROM channels WHERE provider_id = ?);',
          [id],
        );

        // 3. Delete failover group references to this provider's channels
        await customStatement(
          'DELETE FROM failover_group_channels WHERE channel_id IN (SELECT id FROM channels WHERE provider_id = ?);',
          [id],
        );

        // 4. Delete reminders and scheduled recordings for this provider's channels
        await customStatement(
          'DELETE FROM epg_reminders WHERE channel_id IN (SELECT id FROM channels WHERE provider_id = ?);',
          [id],
        );
        await customStatement(
          'DELETE FROM scheduled_recordings WHERE channel_id IN (SELECT id FROM channels WHERE provider_id = ?);',
          [id],
        );

        // 5. Delete all channels belonging to this provider
        await customStatement(
          'DELETE FROM channels WHERE provider_id = ?;',
          [id],
        );

        // 6. Delete the provider itself
        await (delete(providers)..where((t) => t.id.equals(id))).go();
      });
    } finally {
      await customStatement('PRAGMA foreign_keys = ON;');
    }
  }

  // --- Channel queries ---

  Future<List<Channel>> getChannelsForProvider(String providerId) =>
      (select(channels)..where((t) => t.providerId.equals(providerId))).get();

  /// Get live channels for a provider (or all providers if null).
  Future<List<Channel>> getLiveChannels({String? providerId}) {
    if (providerId != null) {
      return (select(channels)
            ..where((t) => t.providerId.equals(providerId) & t.streamType.equals('live'))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();
    }
    return (select(channels)
          ..where((t) => t.streamType.equals('live'))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
        .get();
  }

  Future<List<Channel>> getChannelsByIds(Set<String> ids) =>
      (select(channels)..where((t) => t.id.isIn(ids))).get();

  /// Get distinct live group names per provider.
  Future<Map<String, List<String>>> getProviderGroups() async {
    final rows = await customSelect(
      'SELECT DISTINCT provider_id, group_title FROM channels '
      'WHERE stream_type = \'live\' AND group_title IS NOT NULL AND group_title != \'\' '
      'ORDER BY provider_id, group_title',
    ).get();
    final result = <String, List<String>>{};
    for (final row in rows) {
      final pid = row.read<String>('provider_id');
      final g = row.read<String>('group_title');
      (result[pid] ??= []).add(g);
    }
    return result;
  }

  /// Get distinct live groups and channel counts for a provider.
  Future<Map<String, int>> getLiveGroupCounts({String? providerId}) async {
    final sql = providerId != null
        ? 'SELECT group_title, COUNT(*) as cnt FROM channels WHERE provider_id = ? AND stream_type = \'live\' AND group_title IS NOT NULL AND group_title != \'\' GROUP BY group_title ORDER BY group_title'
        : 'SELECT group_title, COUNT(*) as cnt FROM channels WHERE stream_type = \'live\' AND group_title IS NOT NULL AND group_title != \'\' GROUP BY group_title ORDER BY group_title';
    final rows = await customSelect(
      sql,
      variables: providerId != null ? [Variable.withString(providerId)] : const [],
    ).get();
    final result = <String, int>{};
    for (final row in rows) {
      final g = row.read<String>('group_title');
      final c = row.read<int>('cnt');
      result[g] = c;
    }
    return result;
  }

  /// Get distinct VOD movie groups and counts for a provider.
  Future<Map<String, int>> getVodGroupCounts({String? providerId}) async {
    final sql = providerId != null
        ? 'SELECT group_title, COUNT(*) as cnt FROM channels WHERE provider_id = ? AND stream_type = \'vod\' AND group_title IS NOT NULL AND group_title != \'\' GROUP BY group_title ORDER BY group_title'
        : 'SELECT group_title, COUNT(*) as cnt FROM channels WHERE stream_type = \'vod\' AND group_title IS NOT NULL AND group_title != \'\' GROUP BY group_title ORDER BY group_title';
    final rows = await customSelect(
      sql,
      variables: providerId != null ? [Variable.withString(providerId)] : const [],
    ).get();
    final result = <String, int>{};
    for (final row in rows) {
      final g = row.read<String>('group_title');
      final c = row.read<int>('cnt');
      result[g] = c;
    }
    return result;
  }

  /// Get distinct Series groups and counts for a provider.
  Future<Map<String, int>> getSeriesGroupCounts({String? providerId}) async {
    final sql = providerId != null
        ? 'SELECT group_title, COUNT(*) as cnt FROM channels WHERE provider_id = ? AND stream_type = \'series\' AND group_title IS NOT NULL AND group_title != \'\' GROUP BY group_title ORDER BY group_title'
        : 'SELECT group_title, COUNT(*) as cnt FROM channels WHERE stream_type = \'series\' AND group_title IS NOT NULL AND group_title != \'\' GROUP BY group_title ORDER BY group_title';
    final rows = await customSelect(
      sql,
      variables: providerId != null ? [Variable.withString(providerId)] : const [],
    ).get();
    final result = <String, int>{};
    for (final row in rows) {
      final g = row.read<String>('group_title');
      final c = row.read<int>('cnt');
      result[g] = c;
    }
    return result;
  }

  Future<int> getVodTotalCount({String? providerId}) async {
    final sql = providerId != null
        ? 'SELECT COUNT(*) as cnt FROM channels WHERE provider_id = ? AND stream_type = \'vod\''
        : 'SELECT COUNT(*) as cnt FROM channels WHERE stream_type = \'vod\'';
    final rows = await customSelect(
      sql,
      variables: providerId != null ? [Variable.withString(providerId)] : const [],
    ).get();
    return rows.isNotEmpty ? rows.first.read<int>('cnt') : 0;
  }

  Future<int> getSeriesTotalCount({String? providerId}) async {
    final sql = providerId != null
        ? 'SELECT COUNT(*) as cnt FROM channels WHERE provider_id = ? AND stream_type = \'series\''
        : 'SELECT COUNT(*) as cnt FROM channels WHERE stream_type = \'series\'';
    final rows = await customSelect(
      sql,
      variables: providerId != null ? [Variable.withString(providerId)] : const [],
    ).get();
    return rows.isNotEmpty ? rows.first.read<int>('cnt') : 0;
  }

  Future<int> getVodFavoriteCount({String? providerId}) async {
    final sql = providerId != null
        ? 'SELECT COUNT(*) as cnt FROM channels WHERE provider_id = ? AND stream_type = \'vod\' AND favorite = 1'
        : 'SELECT COUNT(*) as cnt FROM channels WHERE stream_type = \'vod\' AND favorite = 1';
    final rows = await customSelect(
      sql,
      variables: providerId != null ? [Variable.withString(providerId)] : const [],
    ).get();
    return rows.isNotEmpty ? rows.first.read<int>('cnt') : 0;
  }

  Future<int> getSeriesFavoriteCount({String? providerId}) async {
    final sql = providerId != null
        ? 'SELECT COUNT(*) as cnt FROM channels WHERE provider_id = ? AND stream_type = \'series\' AND favorite = 1'
        : 'SELECT COUNT(*) as cnt FROM channels WHERE stream_type = \'series\' AND favorite = 1';
    final rows = await customSelect(
      sql,
      variables: providerId != null ? [Variable.withString(providerId)] : const [],
    ).get();
    return rows.isNotEmpty ? rows.first.read<int>('cnt') : 0;
  }

  Future<List<Channel>> getVodMoviesPaged({
    String? providerId,
    String? groupTitle,
    String? searchQuery,
    bool favoritesOnly = false,
    int limit = 120,
    int offset = 0,
    String sortBy = 'recent',
  }) async {
    final query = select(channels);
    query.where((t) => t.streamType.equals('vod'));
    if (providerId != null && providerId.isNotEmpty) {
      query.where((t) => t.providerId.equals(providerId));
    }
    if (favoritesOnly) {
      query.where((t) => t.favorite.equals(true));
    } else if (groupTitle != null && groupTitle.isNotEmpty && groupTitle != 'All') {
      query.where((t) => t.groupTitle.equals(groupTitle));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim().toLowerCase()}%';
      query.where((t) => t.name.lower().like(q));
    }
    if (sortBy == 'alphabetical') {
      query.orderBy([(t) => OrderingTerm(expression: t.name)]);
    } else if (sortBy == 'year') {
      query.orderBy([(t) => OrderingTerm(expression: t.name, mode: OrderingMode.desc)]);
    } else {
      query.orderBy([(t) => OrderingTerm(expression: t.sortOrder)]);
    }
    query.limit(limit, offset: offset);
    return query.get();
  }

  Future<List<Channel>> getSeriesPaged({
    String? providerId,
    String? groupTitle,
    String? searchQuery,
    bool favoritesOnly = false,
    int limit = 120,
    int offset = 0,
    String sortBy = 'recent',
  }) async {
    final query = select(channels);
    query.where((t) => t.streamType.equals('series'));
    if (providerId != null && providerId.isNotEmpty) {
      query.where((t) => t.providerId.equals(providerId));
    }
    if (favoritesOnly) {
      query.where((t) => t.favorite.equals(true));
    } else if (groupTitle != null && groupTitle.isNotEmpty && groupTitle != 'All') {
      query.where((t) => t.groupTitle.equals(groupTitle));
    }
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = '%${searchQuery.trim().toLowerCase()}%';
      query.where((t) => t.name.lower().like(q));
    }
    if (sortBy == 'alphabetical') {
      query.orderBy([(t) => OrderingTerm(expression: t.name)]);
    } else if (sortBy == 'year') {
      query.orderBy([(t) => OrderingTerm(expression: t.name, mode: OrderingMode.desc)]);
    } else {
      query.orderBy([(t) => OrderingTerm(expression: t.sortOrder)]);
    }
    query.limit(limit, offset: offset);
    return query.get();
  }

  /// Get channels for a specific provider and group.
  Future<List<Channel>> getChannelsForProviderGroup(String providerId, String groupTitle) =>
      (select(channels)..where((t) =>
          t.providerId.equals(providerId) & t.groupTitle.equals(groupTitle))).get();

  Future<List<Channel>> getFavoriteChannels() =>
      (select(channels)..where((t) => t.favorite.equals(true))).get();

  Future<void> upsertChannels(List<ChannelsCompanion> entries) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(channels, entries);
    });
  }

  Future<void> updateChannelLogo(String channelId, String logoUrl) =>
      (update(channels)..where((t) => t.id.equals(channelId)))
          .write(ChannelsCompanion(tvgLogo: Value(logoUrl)));

  /// Batch-update logos for multiple channels in a single transaction.
  Future<void> updateChannelLogos(Map<String, String> idToLogoUrl) async {
    await batch((b) {
      for (final entry in idToLogoUrl.entries) {
        b.update(channels, ChannelsCompanion(tvgLogo: Value(entry.value)),
            where: (t) => t.id.equals(entry.key));
      }
    });
  }

  Future<void> renameChannel(String channelId, String providerId, String newName) =>
      (update(channels)..where((t) => t.id.equals(channelId)))
          .write(ChannelsCompanion(name: Value(newName)));

  Future<void> toggleFavorite(String channelId) async {
    final channel =
        await (select(channels)..where((t) => t.id.equals(channelId)))
            .getSingle();
    await (update(channels)..where((t) => t.id.equals(channelId)))
        .write(ChannelsCompanion(favorite: Value(!channel.favorite)));
  }

  // --- EPG Source queries ---

  Future<List<EpgSource>> getAllEpgSources() => select(epgSources).get();

  Future<void> upsertEpgSource(EpgSourcesCompanion entry) =>
      into(epgSources).insertOnConflictUpdate(entry);

  // --- EPG Channel queries ---

  Future<List<EpgChannel>> getEpgChannelsForSource(String sourceId) =>
      (select(epgChannels)..where((t) => t.sourceId.equals(sourceId))).get();

  Future<void> upsertEpgChannels(List<EpgChannelsCompanion> entries) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(epgChannels, entries);
    });
  }

  // --- EPG Programme queries ---

  Future<List<EpgProgramme>> getProgrammes({
    required String epgChannelId,
    required DateTime start,
    required DateTime end,
  }) =>
      (select(epgProgrammes)
            ..where((t) =>
                t.epgChannelId.equals(epgChannelId) &
                t.start.isBiggerOrEqualValue(start) &
                t.stop.isSmallerOrEqualValue(end))
            ..orderBy([(t) => OrderingTerm.asc(t.start)]))
          .get();

  /// Get what's on now for a list of EPG channel IDs.
  Future<List<EpgProgramme>> getNowPlaying(List<String> epgChannelIds) {
    final now = DateTime.now();
    return (select(epgProgrammes)
          ..where((t) =>
              t.epgChannelId.isIn(epgChannelIds) &
              t.start.isSmallerOrEqualValue(now) &
              t.stop.isBiggerOrEqualValue(now)))
        .get();
  }

  Future<List<EpgProgramme>> getNowPlayingWindow(
    List<String> epgChannelIds, DateTime from, DateTime to,
  ) {
    return (select(epgProgrammes)
          ..where((t) =>
              t.epgChannelId.isIn(epgChannelIds) &
              t.start.isSmallerOrEqualValue(to) &
              t.stop.isBiggerOrEqualValue(from)))
        .get();
  }

  Future<void> insertProgrammes(List<EpgProgrammesCompanion> entries) async {
    await batch((b) {
      b.insertAll(epgProgrammes, entries, mode: InsertMode.insertOrReplace);
    });
  }

  Future<void> deleteEpgProgrammesForSource(String sourceId) =>
      (delete(epgProgrammes)..where((t) => t.sourceId.equals(sourceId))).go();

  Future<void> insertEpgProgrammes(List<EpgProgrammesCompanion> entries) async {
    await batch((b) {
      b.insertAll(epgProgrammes, entries);
    });
  }

  Future<void> updateEpgSourceRefreshTime(String id) =>
      (update(epgSources)..where((t) => t.id.equals(id)))
          .write(EpgSourcesCompanion(lastRefresh: Value(DateTime.now())));

  Future<void> deleteEpgSource(String id) async {
    await deleteEpgProgrammesForSource(id);
    await (delete(epgChannels)..where((t) => t.sourceId.equals(id))).go();
    await (delete(epgSources)..where((t) => t.id.equals(id))).go();
  }

  Future<List<Channel>> getAllChannels() => select(channels).get();

  /// Delete old programmes to keep DB size manageable.
  Future<void> pruneOldProgrammes({Duration maxAge = const Duration(days: 7)}) {
    final cutoff = DateTime.now().subtract(maxAge);
    return (delete(epgProgrammes)
          ..where((t) => t.stop.isSmallerThanValue(cutoff)))
        .go();
  }

  // --- EPG Mapping queries ---

  Future<List<EpgMapping>> getAllMappings() => select(epgMappings).get();

  Future<void> upsertMapping(EpgMappingsCompanion entry) =>
      into(epgMappings).insertOnConflictUpdate(entry);

  Future<void> upsertMappings(List<EpgMappingsCompanion> entries) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(epgMappings, entries);
    });
  }

  Future<void> deleteMapping(String channelId, String providerId) =>
      (delete(epgMappings)
            ..where((t) =>
                t.channelId.equals(channelId) &
                t.providerId.equals(providerId)))
          .go();

  Future<void> deleteAllMappings() => delete(epgMappings).go();

  /// Get mapping stats.
  Future<Map<String, int>> getMappingStats() async {
    final all = await select(epgMappings).get();
    int mapped = 0, suggested = 0;
    for (final m in all) {
      if (m.source == 'auto' || m.source == 'manual') {
        mapped++;
      } else {
        suggested++;
      }
    }
    return {'mapped': mapped, 'suggested': suggested};
  }

  // --- Favorite List queries ---

  Future<List<FavoriteList>> getAllFavoriteLists() =>
      (select(favoriteLists)..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

  Future<List<Channel>> getChannelsInList(String listId) async {
    final query = select(channels).join([
      innerJoin(favoriteListChannels,
          favoriteListChannels.channelId.equalsExp(channels.id)),
    ])
      ..where(favoriteListChannels.listId.equals(listId))
      ..orderBy([OrderingTerm.asc(favoriteListChannels.sortOrder)]);
    final rows = await query.get();
    return rows.map((row) => row.readTable(channels)).toList();
  }

  Future<void> addChannelToList(String listId, String channelId) =>
      into(favoriteListChannels).insertOnConflictUpdate(
        FavoriteListChannelsCompanion.insert(
          listId: listId,
          channelId: channelId,
        ),
      );

  Future<void> removeChannelFromList(String listId, String channelId) =>
      (delete(favoriteListChannels)
            ..where(
                (t) => t.listId.equals(listId) & t.channelId.equals(channelId)))
          .go();

  Future<FavoriteList> createFavoriteList(String name) async {
    final id = _uuid.v4();
    final count = await (select(favoriteLists)..limit(1000)).get();
    final entry = FavoriteListsCompanion.insert(
      id: id,
      name: name,
      sortOrder: Value(count.length),
    );
    await into(favoriteLists).insert(entry);
    return (select(favoriteLists)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> renameFavoriteList(String id, String name) =>
      (update(favoriteLists)..where((t) => t.id.equals(id)))
          .write(FavoriteListsCompanion(name: Value(name)));

  Future<void> deleteFavoriteList(String id) async {
    await (delete(favoriteListChannels)..where((t) => t.listId.equals(id)))
        .go();
    await (delete(favoriteLists)..where((t) => t.id.equals(id))).go();
  }

  Future<bool> isChannelInList(String listId, String channelId) async {
    final row = await (select(favoriteListChannels)
          ..where(
              (t) => t.listId.equals(listId) & t.channelId.equals(channelId)))
        .getSingleOrNull();
    return row != null;
  }

  Future<List<FavoriteList>> getListsForChannel(String channelId) async {
    final query = select(favoriteLists).join([
      innerJoin(favoriteListChannels,
          favoriteListChannels.listId.equalsExp(favoriteLists.id)),
    ])
      ..where(favoriteListChannels.channelId.equals(channelId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(favoriteLists)).toList();
  }

  /// Get all channel IDs that belong to any favorite list.
  Future<Set<String>> getAllFavoritedChannelIds() async {
    final rows = await select(favoriteListChannels).get();
    return rows.map((r) => r.channelId).toSet();
  }

  // --- Reminder queries ---

  Future<void> addReminder(EpgRemindersCompanion entry) =>
      into(epgReminders).insertOnConflictUpdate(entry);

  Future<void> deleteReminder(String id) =>
      (delete(epgReminders)..where((t) => t.id.equals(id))).go();

  Future<List<EpgReminder>> getActiveReminders() =>
      (select(epgReminders)..where((t) => t.fired.equals(false))).get();

  Future<List<EpgReminder>> getRemindersForTimeRange(DateTime start, DateTime end) =>
      (select(epgReminders)
            ..where((t) => t.programmeStart.isBiggerOrEqualValue(start) &
                t.programmeStart.isSmallerOrEqualValue(end)))
          .get();

  Future<void> markReminderFired(String id) =>
      (update(epgReminders)..where((t) => t.id.equals(id)))
          .write(const EpgRemindersCompanion(fired: Value(true)));

  // --- Scheduled Recording queries ---

  Future<void> addScheduledRecording(ScheduledRecordingsCompanion entry) =>
      into(scheduledRecordings).insertOnConflictUpdate(entry);

  Future<void> deleteScheduledRecording(String id) =>
      (delete(scheduledRecordings)..where((t) => t.id.equals(id))).go();

  Future<List<ScheduledRecording>> getAllScheduledRecordings() =>
      select(scheduledRecordings).get();

  Future<List<ScheduledRecording>> getScheduledRecordingsForTimeRange(
          DateTime start, DateTime end) =>
      (select(scheduledRecordings)
            ..where((t) => t.programmeStart.isBiggerOrEqualValue(start) &
                t.programmeStart.isSmallerOrEqualValue(end)))
          .get();

  Future<void> updateRecordingStatus(String id, String status) =>
      (update(scheduledRecordings)..where((t) => t.id.equals(id)))
          .write(ScheduledRecordingsCompanion(status: Value(status)));

  // --- Failover Group queries ---

  Future<List<FailoverGroup>> getAllFailoverGroups() =>
      (select(failoverGroups)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<FailoverGroup> createFailoverGroup(String name) async {
    final id = await into(failoverGroups).insert(
      FailoverGroupsCompanion.insert(name: name),
    );
    return (select(failoverGroups)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> addChannelsToFailoverGroup(int groupId, List<String> channelIds) async {
    await batch((b) {
      for (var i = 0; i < channelIds.length; i++) {
        b.insert(
          failoverGroupChannels,
          FailoverGroupChannelsCompanion.insert(
            groupId: groupId,
            channelId: channelIds[i],
            priority: Value(i),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<List<FailoverGroupChannel>> getFailoverGroupMembers(int groupId) =>
      (select(failoverGroupChannels)
            ..where((t) => t.groupId.equals(groupId))
            ..orderBy([(t) => OrderingTerm.asc(t.priority)]))
          .get();

  /// Get all failover group memberships keyed by channel ID for fast lookup.
  Future<Map<String, List<FailoverGroupMembership>>> getFailoverGroupIndex() async {
    final groups = await getAllFailoverGroups();
    final members = await select(failoverGroupChannels).get();
    final groupMap = {for (final g in groups) g.id: g};
    final index = <String, List<FailoverGroupMembership>>{};
    for (final m in members) {
      final group = groupMap[m.groupId];
      if (group == null) continue;
      index.putIfAbsent(m.channelId, () => []).add(
        FailoverGroupMembership(group: group, priority: m.priority),
      );
    }
    return index;
  }

  Future<void> deleteFailoverGroup(int groupId) async {
    await (delete(failoverGroupChannels)..where((t) => t.groupId.equals(groupId))).go();
    await (delete(failoverGroups)..where((t) => t.id.equals(groupId))).go();
  }

  Future<void> renameFailoverGroup(int groupId, String name) =>
      (update(failoverGroups)..where((t) => t.id.equals(groupId)))
          .write(FailoverGroupsCompanion(name: Value(name)));

  Future<void> removeChannelFromFailoverGroup(int groupId, String channelId) =>
      (delete(failoverGroupChannels)
            ..where((t) => t.groupId.equals(groupId) & t.channelId.equals(channelId)))
          .go();
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'clubtivi',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}

/// Lightweight struct for failover group membership lookups.
class FailoverGroupMembership {
  final FailoverGroup group;
  final int priority;
  const FailoverGroupMembership({required this.group, required this.priority});
}
