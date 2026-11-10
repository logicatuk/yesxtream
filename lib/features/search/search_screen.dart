import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/datasources/local/database.dart' as db;
import '../../data/datasources/remote/tmdb_client.dart';
import '../providers/provider_manager.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  String _query = '';
  bool _searching = false;

  List<db.Channel> _channelResults = [];
  List<TmdbSearchResult> _movieResults = [];
  List<TmdbSearchResult> _seriesResults = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      final q = val.trim();
      setState(() => _query = q);
      if (q.isNotEmpty) {
        _performSearch(q);
      } else {
        setState(() {
          _channelResults = [];
          _movieResults = [];
          _seriesResults = [];
          _searching = false;
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _searching = true);

    try {
      final database = ref.read(databaseProvider);
      final allChannels = await database.getAllChannels();
      final lower = query.toLowerCase();

      final matchedChannels = allChannels
          .where((c) =>
              c.name.toLowerCase().contains(lower) ||
              (c.tvgName != null && c.tvgName!.toLowerCase().contains(lower)) ||
              (c.groupTitle != null && c.groupTitle!.toLowerCase().contains(lower)))
          .take(50)
          .toList();

      final tmdb = TmdbClient.defaultClient;
      final movieSearch = await tmdb.searchMovies(query);
      final seriesSearch = await tmdb.searchTv(query);

      if (mounted) {
        setState(() {
          _channelResults = matchedChannels;
          _movieResults = movieSearch;
          _seriesResults = seriesSearch;
          _searching = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        left: false,
        right: false,
        top: false,
        bottom: false,
        child: Column(
          children: [
            // ── Search Input Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF161524),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2C2A42)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: 'Search channels, movies, and series…',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6C5CE7)),
                          suffixIcon: _query.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Colors.white54),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        onChanged: _onSearchChanged,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Tabs ──
            TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF6C5CE7),
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.live_tv_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text('Channels (${_channelResults.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.movie_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text('Movies (${_movieResults.length})'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.tv_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text('Series (${_seriesResults.length})'),
                    ],
                  ),
                ),
              ],
            ),

            // ── Content Area ──
            Expanded(
              child: _searching
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
                    )
                  : _query.isEmpty
                      ? _buildEmptyPrompt()
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildChannelsTab(),
                            _buildMoviesTab(),
                            _buildSeriesTab(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, size: 64, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          const Text(
            'Type to search content',
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelsTab() {
    if (_channelResults.isEmpty) {
      return const Center(
        child: Text('No channels found', style: TextStyle(color: Colors.white38)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _channelResults.length,
      separatorBuilder: (_, __) => const Divider(color: Color(0xFF1E1E2E), height: 1),
      itemBuilder: (context, index) {
        final ch = _channelResults[index];
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
          title: Text(
            ch.name,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: ch.groupTitle != null
              ? Text(ch.groupTitle!, style: const TextStyle(color: Colors.white38, fontSize: 12))
              : null,
          trailing: const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF6C5CE7)),
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

  Widget _buildMoviesTab() {
    if (_movieResults.isEmpty) {
      return const Center(
        child: Text('No movies found', style: TextStyle(color: Colors.white38)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.65,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _movieResults.length,
      itemBuilder: (context, index) {
        final movie = _movieResults[index];
        return InkWell(
          onTap: () {
            context.push('/movies/detail', extra: {
              'id': movie.id.toString(),
              'title': movie.displayName,
              'overview': movie.overview,
              'posterUrl': movie.posterUrl,
              'backdropUrl': movie.backdropUrl,
              'year': movie.year?.toString(),
              'rating': movie.voteAverage,
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: movie.posterPath != null
                      ? Image.network(
                          movie.posterUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => _buildPosterPlaceholder(movie.displayName),
                        )
                      : _buildPosterPlaceholder(movie.displayName),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                movie.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (movie.year != null)
                Text(
                  '${movie.year}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSeriesTab() {
    if (_seriesResults.isEmpty) {
      return const Center(
        child: Text('No series found', style: TextStyle(color: Colors.white38)),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.65,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _seriesResults.length,
      itemBuilder: (context, index) {
        final show = _seriesResults[index];
        return InkWell(
          onTap: () {
            context.push('/series/detail', extra: {
              'id': show.id.toString(),
              'name': show.displayName,
              'overview': show.overview,
              'posterUrl': show.posterUrl,
              'backdropUrl': show.backdropUrl,
              'rating': show.voteAverage,
              'year': show.year?.toString(),
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: show.posterPath != null
                      ? Image.network(
                          show.posterUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => _buildPosterPlaceholder(show.displayName),
                        )
                      : _buildPosterPlaceholder(show.displayName),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                show.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              if (show.year != null)
                Text(
                  '${show.year}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPosterPlaceholder(String title) {
    return Container(
      color: const Color(0xFF1A192A),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
    );
  }
}
