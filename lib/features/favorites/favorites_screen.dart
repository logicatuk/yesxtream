import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/datasources/local/database.dart' as db;
import '../../data/services/playback_history_service.dart';
import '../providers/provider_manager.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<db.Channel> _favoriteChannels = [];
  bool _loadingChannels = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    try {
      final database = ref.read(databaseProvider);
      final channels = await database.getFavoriteChannels();
      if (mounted) {
        setState(() {
          _favoriteChannels = channels;
          _loadingChannels = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingChannels = false);
    }
  }

  Future<void> _removeChannelFavorite(String channelId) async {
    final database = ref.read(databaseProvider);
    await database.toggleFavorite(channelId);
    _loadChannels();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We can also retrieve favorite movies/series from history or saved items
    final history = ref.watch(watchHistoryProvider);
    final favMovies = history.where((h) => h.streamType == 'vod').toList();
    final favSeries = history.where((h) => h.streamType == 'series').toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.star_rounded, color: Colors.amber, size: 24),
            SizedBox(width: 10),
            Text(
              'Favorites',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF6C5CE7),
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          tabs: [
            Tab(text: 'Channels (${_favoriteChannels.length})'),
            Tab(text: 'Movies (${favMovies.length})'),
            Tab(text: 'Series (${favSeries.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChannelsTab(),
          _buildMoviesTab(favMovies),
          _buildSeriesTab(favSeries),
        ],
      ),
    );
  }

  Widget _buildChannelsTab() {
    if (_loadingChannels) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7)));
    }
    if (_favoriteChannels.isEmpty) {
      return _buildEmptyState('No favorite channels added yet');
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _favoriteChannels.length,
      separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E1E2E), height: 1),
      itemBuilder: (context, index) {
        final ch = _favoriteChannels[index];
        return ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF161524),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ch.tvgLogo != null && ch.tvgLogo!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      ch.tvgLogo!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.live_tv_rounded, color: Colors.white38, size: 22),
                    ),
                  )
                : const Icon(Icons.live_tv_rounded, color: Colors.white38, size: 22),
          ),
          title: Text(ch.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: ch.groupTitle != null
              ? Text(ch.groupTitle!, style: const TextStyle(color: Colors.white38, fontSize: 12))
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.star_rounded, color: Colors.amber),
                tooltip: 'Remove from favorites',
                onPressed: () => _removeChannelFavorite(ch.id),
              ),
              IconButton(
                icon: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF6C5CE7), size: 28),
                tooltip: 'Play channel',
                onPressed: () {
                  context.push('/player', extra: {
                    'streamUrl': ch.streamUrl,
                    'channelName': ch.name,
                    'channelLogo': ch.tvgLogo,
                    'channels': [
                      {
                        'id': ch.id,
                        'name': ch.name,
                        'streamUrl': ch.streamUrl,
                        'tvgLogo': ch.tvgLogo,
                      }
                    ],
                    'currentIndex': 0,
                  });
                },
              ),
            ],
          ),
          onTap: () {
            context.push('/player', extra: {
              'streamUrl': ch.streamUrl,
              'channelName': ch.name,
              'channelLogo': ch.tvgLogo,
              'channels': [
                {
                  'id': ch.id,
                  'name': ch.name,
                  'streamUrl': ch.streamUrl,
                  'tvgLogo': ch.tvgLogo,
                }
              ],
              'currentIndex': 0,
            });
          },
        );
      },
    );
  }

  Widget _buildMoviesTab(List<WatchHistoryItem> movies) {
    if (movies.isEmpty) {
      return _buildEmptyState('No favorite movies yet');
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.65,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: movies.length,
      itemBuilder: (context, index) {
        final item = movies[index];
        return Card(
          color: const Color(0xFF161524),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: InkWell(
            onTap: () {
              context.push('/vod-player', extra: {
                'id': item.id,
                'title': item.title,
                'streamUrl': item.streamUrl,
                'streamType': 'vod',
                'posterUrl': item.posterUrl,
                'backdropUrl': item.backdropUrl,
                'initialPositionMs': item.positionMs,
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      item.posterUrl != null
                          ? Image.network(
                              item.posterUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.movie_rounded, color: Colors.white24, size: 36)),
                            )
                          : const Center(
                              child: Icon(Icons.movie_rounded, color: Colors.white24, size: 36)),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          icon: const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                          tooltip: 'Remove',
                          onPressed: () {
                            ref.read(watchHistoryProvider.notifier).removeHistory(item.id);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeriesTab(List<WatchHistoryItem> series) {
    if (series.isEmpty) {
      return _buildEmptyState('No favorite series yet');
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.65,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: series.length,
      itemBuilder: (context, index) {
        final item = series[index];
        return Card(
          color: const Color(0xFF161524),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: InkWell(
            onTap: () {
              context.push('/vod-player', extra: {
                'id': item.id,
                'title': item.title,
                'streamUrl': item.streamUrl,
                'streamType': 'series',
                'seriesName': item.seriesName ?? item.title,
                'seasonNumber': item.seasonNumber,
                'episodeNumber': item.episodeNumber,
                'posterUrl': item.posterUrl,
                'backdropUrl': item.backdropUrl,
                'initialPositionMs': item.positionMs,
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      item.posterUrl != null
                          ? Image.network(
                              item.posterUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.tv_rounded, color: Colors.white24, size: 36)),
                            )
                          : const Center(
                              child: Icon(Icons.tv_rounded, color: Colors.white24, size: 36)),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          icon: const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                          tooltip: 'Remove',
                          onPressed: () {
                            ref.read(watchHistoryProvider.notifier).removeHistory(item.id);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.seriesName ?? item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      if (item.seasonNumber != null && item.episodeNumber != null)
                        Text(
                          'S${item.seasonNumber} • E${item.episodeNumber}',
                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_border_rounded, size: 64, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white38, fontSize: 16)),
        ],
      ),
    );
  }
}
