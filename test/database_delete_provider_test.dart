import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yesxtream/data/datasources/local/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON;');
  });

  tearDown(() async {
    await db.close();
  });

  test('deleteProvider removes provider and all related records without foreign key errors', () async {
    const providerId = 'prov-1';
    const channelId1 = 'ch-1';
    const channelId2 = 'ch-2';
    const epgSourceId = 'epg-src-1';

    // 1. Insert provider
    await db.into(db.providers).insert(
      ProvidersCompanion.insert(
        id: providerId,
        name: 'Test Provider',
        type: 'xtream',
      ),
    );

    // 2. Insert channels
    await db.into(db.channels).insert(
      ChannelsCompanion.insert(
        id: channelId1,
        providerId: providerId,
        name: 'Channel 1',
        streamUrl: 'http://test/1.m3u8',
      ),
    );
    await db.into(db.channels).insert(
      ChannelsCompanion.insert(
        id: channelId2,
        providerId: providerId,
        name: 'Channel 2',
        streamUrl: 'http://test/2.m3u8',
      ),
    );

    // 3. Insert EPG source & channel & mapping referencing channelId1
    await db.into(db.epgSources).insert(
      EpgSourcesCompanion.insert(
        id: epgSourceId,
        name: 'Test EPG Source',
        url: 'http://test/epg.xml',
      ),
    );
    await db.into(db.epgMappings).insert(
      EpgMappingsCompanion.insert(
        channelId: channelId1,
        providerId: providerId,
        epgChannelId: 'epg-ch-1',
        epgSourceId: epgSourceId,
      ),
    );

    // 4. Insert Favorite list and channel
    const favListId = 'fav-1';
    await db.into(db.favoriteLists).insert(
      FavoriteListsCompanion.insert(
        id: favListId,
        name: 'My Favorites',
      ),
    );
    await db.into(db.favoriteListChannels).insert(
      FavoriteListChannelsCompanion.insert(
        listId: favListId,
        channelId: channelId1,
      ),
    );

    // 5. Insert Failover group and channel
    final groupId = await db.into(db.failoverGroups).insert(
      FailoverGroupsCompanion.insert(
        name: 'Failover Group 1',
      ),
    );
    await db.into(db.failoverGroupChannels).insert(
      FailoverGroupChannelsCompanion.insert(
        groupId: groupId,
        channelId: channelId2,
      ),
    );

    // Verify all are present before delete
    final provBefore = await (db.select(db.providers)..where((t) => t.id.equals(providerId))).get();
    expect(provBefore.length, 1);
    final chBefore = await (db.select(db.channels)..where((t) => t.providerId.equals(providerId))).get();
    expect(chBefore.length, 2);

    // Perform deletion
    await db.deleteProvider(providerId);

    // Verify provider and channels are deleted
    final provAfter = await (db.select(db.providers)..where((t) => t.id.equals(providerId))).get();
    expect(provAfter, isEmpty);
    final chAfter = await (db.select(db.channels)..where((t) => t.providerId.equals(providerId))).get();
    expect(chAfter, isEmpty);

    // Verify mappings and associations are cleaned up
    final mappings = await (db.select(db.epgMappings)..where((t) => t.providerId.equals(providerId))).get();
    expect(mappings, isEmpty);
    final favChannels = await (db.select(db.favoriteListChannels)..where((t) => t.channelId.equals(channelId1))).get();
    expect(favChannels, isEmpty);
    final failoverChs = await (db.select(db.failoverGroupChannels)..where((t) => t.channelId.equals(channelId2))).get();
    expect(failoverChs, isEmpty);
  });
}
