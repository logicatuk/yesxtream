import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/platform_info.dart';
import '../data/datasources/local/database.dart' as db;
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
import '../features/settings/settings_screen.dart';
import '../features/splash/splash_screen.dart';
import '../features/vod/movie_detail_screen.dart';
import '../features/vod/movies_screen.dart';
import '../features/vod/series_detail_screen.dart';
import '../features/vod/series_screen.dart';
import '../features/vod/vod_player_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

Page<void> _buildShellPage(GoRouterState state, Widget child, {LocalKey? key}) {
  if (PlatformInfo.isTV) {
    return NoTransitionPage<void>(key: key ?? state.pageKey, child: child);
  }
  return MaterialPage<void>(key: key ?? state.pageKey, child: child);
}

GoRouter createRouter() {
  // Routes wrapped inside the branded YesShell (top bar & navigation rail)
  final shellRoutes = [
    GoRoute(
      path: '/home',
      pageBuilder: (context, state) => _buildShellPage(state, const HomeScreen()),
    ),
    GoRoute(
      path: '/live',
      pageBuilder: (context, state) => _buildShellPage(state, const ChannelsScreen()),
    ),
    GoRoute(
      path: '/guide',
      pageBuilder: (context, state) => _buildShellPage(state, const GuideScreen()),
    ),
    GoRoute(
      path: '/catchup',
      pageBuilder: (context, state) => _buildShellPage(
        state,
        CatchupScreen(
          initialChannel: state.extra is db.Channel ? state.extra as db.Channel : null,
        ),
      ),
    ),
    GoRoute(
      path: '/movies',
      pageBuilder: (context, state) => _buildShellPage(state, const MoviesScreen()),
    ),
    GoRoute(
      path: '/series',
      pageBuilder: (context, state) => _buildShellPage(state, const SeriesScreen()),
    ),
    GoRoute(
      path: '/favorites',
      pageBuilder: (context, state) => _buildShellPage(state, const FavoritesScreen()),
    ),
    GoRoute(
      path: '/playlists',
      pageBuilder: (context, state) => _buildShellPage(state, const PlaylistManagerScreen()),
    ),
    GoRoute(
      path: '/continue-watching',
      pageBuilder: (context, state) => _buildShellPage(state, const ContinueWatchingScreen()),
    ),
    GoRoute(
      path: '/search',
      pageBuilder: (context, state) => _buildShellPage(state, const SearchScreen()),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => _buildShellPage(state, const SettingsScreen()),
    ),
    GoRoute(
      path: '/device-info',
      pageBuilder: (context, state) => _buildShellPage(
        state,
        const SettingsScreen(initialGroup: SettingsGroup.deviceLicense),
      ),
    ),
    GoRoute(
      path: '/parental-controls',
      pageBuilder: (context, state) => _buildShellPage(
        state,
        const SettingsScreen(initialGroup: SettingsGroup.parentalControls),
      ),
    ),
    GoRoute(
      path: '/help',
      pageBuilder: (context, state) => _buildShellPage(
        state,
        const SettingsScreen(initialGroup: SettingsGroup.helpAbout),
      ),
    ),
    GoRoute(
      path: '/epg-mapping',
      pageBuilder: (context, state) => _buildShellPage(state, const EpgMappingScreen()),
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
      pageBuilder: (context, state) => _buildShellPage(
        state,
        const SplashScreen(),
        key: UniqueKey(),
      ),
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/player',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return _buildShellPage(
          state,
          PlayerScreen(
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
          key: UniqueKey(),
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/vod-player',
      pageBuilder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return _buildShellPage(
          state,
          VodPlayerScreen(
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
            initialPositionMs: (extra['initialPositionMs'] as int?) ?? (extra['position'] as int?) ?? 0,
          ),
          key: UniqueKey(),
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/movies/detail',
      pageBuilder: (context, state) {
        if (state.extra is db.Channel) {
          return _buildShellPage(
            state,
            MovieDetailScreen(movie: state.extra as db.Channel),
            key: UniqueKey(),
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
        return _buildShellPage(
          state,
          MovieDetailScreen(movie: movie),
          key: UniqueKey(),
        );
      },
    ),
    GoRoute(
      parentNavigatorKey: rootNavigatorKey,
      path: '/series/detail',
      pageBuilder: (context, state) {
        if (state.extra is db.Channel) {
          return _buildShellPage(
            state,
            SeriesDetailScreen(series: state.extra as db.Channel),
            key: UniqueKey(),
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
        return _buildShellPage(
          state,
          SeriesDetailScreen(series: series),
          key: UniqueKey(),
        );
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
