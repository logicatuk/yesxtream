import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/datasources/local/database.dart' as db;
import '../data/models/show.dart';
import '../features/catchup/catchup_screen.dart';
import '../features/channels/channels_screen.dart';
import '../features/continue_watching/continue_watching_screen.dart';
import '../features/epg_mapping/epg_mapping_screen.dart';
import '../features/favorites/favorites_screen.dart';
import '../features/guide/guide_screen.dart';
import '../features/home/home_screen.dart';
import '../features/navigation/yes_shell.dart';
import '../features/player/player_screen.dart';
import '../features/playlists/playlist_manager_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/debrid_services_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shows/show_detail_screen.dart';
import '../features/shows/shows_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/vod/movie_detail_screen.dart';
import '../features/vod/movies_screen.dart';
import '../features/vod/series_detail_screen.dart';
import '../features/vod/series_screen.dart';
import '../features/vod/vod_player_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

GoRouter createRouter() {
  // Routes wrapped inside the branded YesShell (top bar & navigation rail)
  final shellRoutes = [
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/live',
      builder: (context, state) => const ChannelsScreen(),
    ),
    GoRoute(
      path: '/guide',
      builder: (context, state) => const GuideScreen(),
    ),
    GoRoute(
      path: '/catchup',
      builder: (context, state) => CatchupScreen(
        initialChannel: state.extra is db.Channel ? state.extra as db.Channel : null,
      ),
    ),
    GoRoute(
      path: '/movies',
      builder: (context, state) => const MoviesScreen(),
    ),
    GoRoute(
      path: '/series',
      builder: (context, state) => const SeriesScreen(),
    ),
    GoRoute(
      path: '/favorites',
      builder: (context, state) => const FavoritesScreen(),
    ),
    GoRoute(
      path: '/playlists',
      builder: (context, state) => const PlaylistManagerScreen(),
    ),
    GoRoute(
      path: '/continue-watching',
      builder: (context, state) => const ContinueWatchingScreen(),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const SearchScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/device-info',
      builder: (context, state) =>
          const SettingsScreen(initialGroup: SettingsGroup.deviceLicense),
    ),
    GoRoute(
      path: '/parental-controls',
      builder: (context, state) =>
          const SettingsScreen(initialGroup: SettingsGroup.parentalControls),
    ),
    GoRoute(
      path: '/help',
      builder: (context, state) =>
          const SettingsScreen(initialGroup: SettingsGroup.helpAbout),
    ),
    GoRoute(
      path: '/epg-mapping',
      builder: (context, state) => const EpgMappingScreen(),
    ),
    GoRoute(
      path: '/debrid-services',
      builder: (context, state) => const DebridServicesScreen(),
    ),
  ];

  // Fullscreen / standalone routes outside YesShell
  final standaloneRoutes = [
    GoRoute(
      path: '/',
      redirect: (_, __) => '/home',
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/splash',
      pageBuilder: (context, state) => MaterialPage(
        key: UniqueKey(),
        child: const SplashScreen(),
      ),
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/player',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return MaterialPage(
          key: UniqueKey(),
          child: PlayerScreen(
            streamUrl: extra['streamUrl'] as String? ?? '',
            channelName: extra['channelName'] as String? ?? '',
            channelLogo: extra['channelLogo'] as String?,
            alternativeUrls:
                (extra['alternativeUrls'] as List<String>?) ?? const [],
            channels:
                (extra['channels'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                const [],
            currentIndex: extra['currentIndex'] as int? ?? 0,
            stopOnExit: extra['stopOnExit'] as bool?,
          ),
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/vod-player',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return MaterialPage(
          key: UniqueKey(),
          child: VodPlayerScreen(
            id: extra['id'] as String? ?? '',
            title: extra['title'] as String? ?? '',
            streamUrl: extra['streamUrl'] as String? ?? '',
            streamType: extra['streamType'] as String? ?? 'vod',
            posterUrl: extra['posterUrl'] as String?,
            backdropUrl: extra['backdropUrl'] as String?,
            seriesName: extra['seriesName'] as String?,
            seasonNumber: extra['seasonNumber'] as int?,
            episodeNumber: extra['episodeNumber'] as int?,
            episodeTitle: extra['episodeTitle'] as String?,
            nextEpisode: extra['nextEpisode'] as Map<String, dynamic>?,
            initialPositionMs: extra['initialPositionMs'] as int? ?? 0,
          ),
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/movies/detail',
      pageBuilder: (context, state) {
        if (state.extra is db.Channel) {
          return MaterialPage(
            key: UniqueKey(),
            child: MovieDetailScreen(movie: state.extra as db.Channel),
          );
        }
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final movie = db.Channel(
          id: extra['id']?.toString() ?? '',
          providerId: extra['providerId']?.toString() ?? '',
          name: extra['title'] as String? ?? extra['name'] as String? ?? '',
          streamUrl: extra['streamUrl'] as String? ?? '',
          streamType: 'vod',
          tvgLogo: extra['posterUrl'] as String? ?? extra['backdropUrl'] as String?,
          favorite: false,
          hidden: false,
          sortOrder: 0,
        );
        return MaterialPage(
          key: UniqueKey(),
          child: MovieDetailScreen(movie: movie),
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/series/detail',
      pageBuilder: (context, state) {
        if (state.extra is db.Channel) {
          return MaterialPage(
            key: UniqueKey(),
            child: SeriesDetailScreen(series: state.extra as db.Channel),
          );
        }
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final series = db.Channel(
          id: extra['id']?.toString() ?? '',
          providerId: extra['providerId']?.toString() ?? '',
          name: extra['name'] as String? ?? extra['title'] as String? ?? '',
          streamUrl: extra['streamUrl'] as String? ?? '',
          streamType: 'series',
          tvgLogo: extra['posterUrl'] as String? ?? extra['backdropUrl'] as String?,
          favorite: false,
          hidden: false,
          sortOrder: 0,
        );
        return MaterialPage(
          key: UniqueKey(),
          child: SeriesDetailScreen(series: series),
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/shows',
      builder: (context, state) => const ShowsScreen(),
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/shows/:id',
      builder: (context, state) {
        final traktId = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
        final show = state.extra as Show?;
        return ShowDetailScreen(traktId: traktId, initialShow: show);
      },
    ),
  ];

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    routes: [
      ShellRoute(
        navigatorKey: shellNavigatorKey,
        builder: (context, state, child) => YesShell(child: child),
        routes: shellRoutes,
      ),
      ...standaloneRoutes,
    ],
  );
}

/// Global router instance — initialized lazily.
late final GoRouter router = createRouter();
