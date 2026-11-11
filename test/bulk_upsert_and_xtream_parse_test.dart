import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yesxtream/data/datasources/local/database.dart';
import 'package:yesxtream/data/datasources/remote/xtream_client.dart';
import 'package:yesxtream/data/models/channel.dart';

void main() {
  group('AppDatabase bulk upsert & lightweight stats queries', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.upsertProvider(
        const ProvidersCompanion(
          id: Value('p1'),
          name: Value('Test Playlist'),
          type: Value('xtream'),
          url: Value('http://example.com'),
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    test('upsertChannels (>300) inserts chunks, recreates indexes, and aggregates stats cleanly', () async {
      final entries = <ChannelsCompanion>[
        for (int i = 0; i < 400; i++)
          ChannelsCompanion(
            id: Value('p1_live_$i'),
            providerId: const Value('p1'),
            name: Value('Live $i'),
            streamUrl: Value('http://example.com/live/$i.ts'),
            streamType: const Value('live'),
            tvgLogo: Value(i.isEven ? '' : 'http://example.com/logo/$i.png'),
            sortOrder: Value(i),
          ),
        for (int i = 0; i < 650; i++)
          ChannelsCompanion(
            id: Value('p1_vod_$i'),
            providerId: const Value('p1'),
            name: Value('Movie $i'),
            streamUrl: Value('http://example.com/movie/$i.mp4'),
            streamType: const Value('vod'),
            tvgLogo: const Value(''),
            sortOrder: Value(400 + i),
          ),
        for (int i = 0; i < 450; i++)
          ChannelsCompanion(
            id: Value('p1_series_$i'),
            providerId: const Value('p1'),
            name: Value('Series $i'),
            streamUrl: Value('http://example.com/series/$i'),
            streamType: const Value('series'),
            sortOrder: Value(1050 + i),
          ),
      ];

      final progressSteps = <(int, int)>[];
      await db.upsertChannels(
        entries,
        onProgress: (inserted, total) => progressSteps.add((inserted, total)),
      );

      expect(progressSteps, isNotEmpty);
      expect(progressSteps.last, (1500, 1500));

      final counts = await db.getChannelCountsByType('p1');
      expect(counts['live'], 400);
      expect(counts['vod'], 650);
      expect(counts['series'], 450);

      expect(await db.hasStreamType('p1', 'vod'), isTrue);
      expect(await db.hasStreamType('p1', 'series'), isTrue);

      final missingLogos = await db.getLiveChannelsMissingLogos();
      expect(missingLogos.length, 200);
      expect(missingLogos.every((c) => c.streamType == 'live'), isTrue);

      // Re-upserting with ON CONFLICT DO UPDATE should preserve counts and update names
      await db.upsertChannels([
        for (int i = 0; i < 310; i++)
          ChannelsCompanion(
            id: Value('p1_live_$i'),
            providerId: const Value('p1'),
            name: Value('Updated Live $i'),
            streamUrl: Value('http://example.com/live/$i.ts'),
            streamType: const Value('live'),
            sortOrder: Value(i),
          ),
      ]);
      final updatedCounts = await db.getChannelCountsByType('p1');
      expect(updatedCounts['live'], 400);

      final updatedRows = await db.getChannelsByIds({'p1_live_0'});
      expect(updatedRows.single.name, 'Updated Live 0');
    });
  });

  group('XtreamClient tolerant string & dynamic JSON parsing', () {
    test('parses live, vod, and series when JSON arrives as String with mixed ID types', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final action = options.queryParameters['action'];
            if (action == 'get_live_categories') {
              return handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: jsonEncode([
                  {'category_id': 10, 'category_name': 'Sports'},
                ]),
              ));
            }
            if (action == 'get_live_streams') {
              return handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: jsonEncode([
                  {
                    'stream_id': '1001',
                    'num': '1',
                    'name': 'Sport One',
                    'category_id': 10,
                    'stream_icon': null,
                    'epg_channel_id': 42,
                  },
                  {'stream_id': 'invalid_id', 'name': 'Corrupt Entry'},
                ]),
              ));
            }
            if (action == 'get_vod_streams') {
              return handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: jsonEncode([
                  {
                    'stream_id': 2002,
                    'name': 'Big Movie',
                    'category_id': '20',
                    'container_extension': null,
                    'stream_icon': 'http://img.example.com/m.jpg',
                  },
                ]),
              ));
            }
            if (action == 'get_series') {
              return handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: jsonEncode([
                  {
                    'series_id': '3003',
                    'name': 'Show One',
                    'category_id': 30,
                    'cover': 'http://img.example.com/s.jpg',
                  },
                ]),
              ));
            }
            return handler.resolve(
              Response(requestOptions: options, statusCode: 200, data: '[]'),
            );
          },
        ),
      );

      final client = XtreamClient(
        baseUrl: 'http://iptv.example.com',
        username: 'u',
        password: 'p',
        dio: dio,
      );

      final liveCats = await client.getLiveCategories();
      final liveCatMap = {for (final c in liveCats) c.id: c.name};
      expect(liveCatMap['10'], 'Sports');

      final live = await client.getLiveStreams(providerId: 'p1', categoryMap: liveCatMap);
      expect(live.length, 1);
      expect(live.first.id, 'p1_1001');
      expect(live.first.channelNumber, 1);
      expect(live.first.groupTitle, 'Sports');

      final vod = await client.getVodStreams(providerId: 'p1', categoryMap: {'20': 'Action'});
      expect(vod.length, 1);
      expect(vod.first.streamType, StreamType.vod);
      expect(vod.first.streamUrl, endsWith('/2002.mp4'));

      final series = await client.getSeriesStreams(providerId: 'p1', categoryMap: {'30': 'Drama'});
      expect(series.length, 1);
      expect(series.first.streamType, StreamType.series);
      expect(series.first.id, 'p1_series_3003');
    });
  });
}
