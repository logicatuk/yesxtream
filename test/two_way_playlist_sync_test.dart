import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yesxtream/data/datasources/local/database.dart' as db;
import 'package:yesxtream/data/services/device_identity_service.dart';
import 'package:yesxtream/data/services/device_sync_service.dart';
import 'package:yesxtream/features/providers/provider_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Two-Way Playlist Sync and Key Integrity', () {
    late db.AppDatabase database;
    late ProviderManager manager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      database = db.AppDatabase.forTesting(NativeDatabase.memory());
      manager = ProviderManager(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('Local customer playlists are distinguished from remote playlists for sync', () async {
      // 1. Add a customer-created local playlist
      await database.upsertProvider(
        const db.ProvidersCompanion(
          id: Value('local_p1'),
          name: Value('Living Room M3U'),
          type: Value('m3u'),
          url: Value('http://myiptv.com/list.m3u'),
        ),
      );

      // 2. Add a remote server playlist (id starts with remote_)
      await database.upsertProvider(
        const db.ProvidersCompanion(
          id: Value('remote_srv123'),
          name: Value('Reseller Assigned List'),
          type: Value('xtream'),
          url: Value('http://provider.tv:8080'),
          username: Value('client1'),
          password: Value('pass1'),
        ),
      );

      final all = await database.getAllProviders();
      final localOnly = all.where((p) => !p.id.startsWith('remote_')).toList();

      expect(all.length, equals(2));
      expect(localOnly.length, equals(1));
      expect(localOnly.first.id, equals('local_p1'));
      expect(localOnly.first.name, equals('Living Room M3U'));
    });

    test('DeviceIdentity updates key6 and portalLoginUrl from server response', () async {
      final initial = await DeviceIdentityService.getIdentity();
      expect(initial.macAddress.startsWith('02:'), isTrue);

      await DeviceIdentityService.updateServerKeyAndPortalUrl(
        key6: '739102',
        portalUrl: 'https://yestream.ai.studio/customer/login?mac=${initial.macAddress}&key=739102&redirect=/me/playlists',
      );

      final updated = await DeviceIdentityService.getIdentity();
      expect(updated.serverRegistered, isTrue);
      expect(updated.deviceKey, equals('739102'));
      expect(updated.portalLoginUrl, contains('key=739102'));
    });
  });
}

