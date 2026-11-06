import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/datasources/remote/tmdb_client.dart';
import '../../data/services/playback_history_service.dart';
import '../playlists/playlist_providers.dart';
import '../providers/provider_manager.dart';

enum MovieSortOption { recent, alphabetical, year }

class MoviesScreen extends ConsumerStatefulWidget {
  const MoviesScreen({super.key});

  @override
  ConsumerState<MoviesScreen> createState() => _MoviesScreenState();
}

class _MoviesScreenState extends ConsumerState<MoviesScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  String _categorySearchQuery = '';
  MovieSortOption _sortOption = MovieSortOption.recent;
  final _searchController = TextEditingController();
  final _categorySearchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _categorySearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activePlaylist = ref.watch(activePlaylistProvider);
    final dbInstance = ref.watch(databaseProvider);
    final history = ref.watch(watchHistoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: FutureBuilder<List<db.Channel>>(
        future: activePlaylist != null
            ? (dbInstance.select(dbInstance.channels)
                  ..where((t) =>
                      t.providerId.equals(activePlaylist.id) &
                      t.streamType.equals('vod')))
                .get()
            : (dbInstance.select(dbInstance.channels)
                  ..where((t) => t.streamType.equals('vod')))
                .get(),
        builder: (context, snapshot) {
          final allMovies = snapshot.data ?? [];

          // If no local VOD channels in playlist, fetch TMDB trending movies as fallback
          if (snapshot.connectionState == ConnectionState.done && allMovies.isEmpty) {
            return _buildTmdbFallbackView(context);
          }

          // Extract distinct categories and counts
          final categoryCounts = <String, int>{};
          for (final m in allMovies) {
            final g = m.groupTitle;
            if (g != null && g.isNotEmpty) {
              categoryCounts[g] = (categoryCounts[g] ?? 0) + 1;
            }
          }
          final favCount = allMovies.where((m) => m.favorite).length;
          final recentCount = history.where((h) => allMovies.any((m) => m.id == h.id)).length;
          final allCount = allMovies.length;

          final sortedGroups = categoryCounts.keys.toList()..sort();

          // Filter by category
          var filtered = allMovies.where((m) {
            if (_selectedCategory == 'Recently Viewed') {
              return history.any((h) => h.id == m.id);
            }
            if (_selectedCategory == 'Favorites') return m.favorite;
            if (_selectedCategory == 'All') return true;
            return m.groupTitle == _selectedCategory;
          }).toList();

          // Filter by search query
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            filtered = filtered
                .where((m) => m.name.toLowerCase().contains(q))
                .toList();
          }

          // Sort
          switch (_sortOption) {
            case MovieSortOption.recent:
              break;
            case MovieSortOption.alphabetical:
              filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
              break;
            case MovieSortOption.year:
              filtered.sort((a, b) => b.name.compareTo(a.name));
              break;
          }

          // Filter categories by search
          final catQuery = _categorySearchQuery.trim().toLowerCase();
          final visibleGroups = sortedGroups.where((g) {
            if (catQuery.isEmpty) return true;
            return g.toLowerCase().contains(catQuery);
          }).toList();

          return LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 750;
              if (isCompact) {
                return _buildCompactLayout(
                  context,
                  sortedGroups,
                  categoryCounts,
                  allCount,
                  favCount,
                  recentCount,
                  filtered,
                  history,
                  constraints,
                );
              }

              return Row(
                children: [
                  // ── Left Sidebar Categories (Screenshot 2) ──
              Container(
                width: 260,
                decoration: const BoxDecoration(
                  color: Color(0xFF0E0D1B),
                  border: Border(
                    right: BorderSide(color: Color(0xFF1E1D2F), width: 1),
                  ),
                ),
                child: Column(
                  children: [
                    // Header: Clapperboard Icon + Retour / Rechercher buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.movie_filter_rounded,
                            size: 44,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => context.go('/home'),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1B1A2C),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF2A2840)),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.arrow_back_rounded, size: 14, color: Colors.white70),
                                        SizedBox(width: 4),
                                        Text('Back', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () => context.go('/search'),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1B1A2C),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF2A2840)),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.search_rounded, size: 14, color: Colors.white70),
                                        SizedBox(width: 4),
                                        Text('Search', style: TextStyle(color: Colors.white70, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Search categories input
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          controller: _categorySearchController,
                          onChanged: (val) => setState(() => _categorySearchQuery = val.trim()),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Search categories…',
                            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                            prefixIcon: const Icon(Icons.search_rounded, size: 14, color: Colors.white24),
                            prefixIconConstraints: const BoxConstraints(minWidth: 28),
                            suffixIcon: _categorySearchQuery.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      _categorySearchController.clear();
                                      setState(() => _categorySearchQuery = '');
                                    },
                                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white24),
                                  )
                                : null,
                            suffixIconConstraints: const BoxConstraints(minWidth: 28),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFF1E1D2F)),

                    // Categories list with counts
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          if (recentCount > 0)
                            _buildVodCategoryItem(
                              title: 'Recently Viewed',
                              count: recentCount,
                              isSelected: _selectedCategory == 'Recently Viewed',
                              onTap: () => setState(() => _selectedCategory = 'Recently Viewed'),
                            ),
                          _buildVodCategoryItem(
                            title: 'All',
                            count: allCount,
                            isSelected: _selectedCategory == 'All',
                            onTap: () => setState(() => _selectedCategory = 'All'),
                          ),
                          _buildVodCategoryItem(
                            title: 'Favorites',
                            count: favCount,
                            isSelected: _selectedCategory == 'Favorites',
                            onTap: () => setState(() => _selectedCategory = 'Favorites'),
                          ),
                          for (final group in visibleGroups)
                            _buildVodCategoryItem(
                              title: group,
                              count: categoryCounts[group] ?? 0,
                              isSelected: _selectedCategory == group,
                              onTap: () => setState(() => _selectedCategory = group),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Main Area: Toolbar & Cards Grid ──
              Expanded(
                child: Column(
                  children: [
                    _buildTopToolbar(filtered.length),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No movies found in this category',
                                style: TextStyle(color: Colors.white38),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(20),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 180,
                                childAspectRatio: 0.65,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final movie = filtered[index];
                                final historyItem = history
                                    .where((h) => h.id == movie.id)
                                    .firstOrNull;

                                return _MovieCard(
                                  movie: movie,
                                  historyItem: historyItem,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
        },
      ),
    );
  }

  Widget _buildCompactLayout(
    BuildContext context,
    List<String> sortedGroups,
    Map<String, int> categoryCounts,
    int allCount,
    int favCount,
    int recentCount,
    List<db.Channel> filtered,
    List<WatchHistoryItem> history,
    BoxConstraints constraints,
  ) {
    final chips = <Map<String, dynamic>>[
      if (recentCount > 0) {'title': 'Recently Viewed', 'count': recentCount},
      {'title': 'All', 'count': allCount},
      {'title': 'Favorites', 'count': favCount},
      ...sortedGroups.map((g) => {'title': g, 'count': categoryCounts[g] ?? 0}),
    ];

    final isVerySmall = constraints.maxWidth < 420;
    final crossAxisCount = isVerySmall ? 2 : (constraints.maxWidth < 650 ? 3 : 4);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            // Compact Header: Back, Search, Sort
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF0F0E1A),
                border: Border(bottom: BorderSide(color: Color(0xFF1E1D2F), width: 1)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                    onPressed: () => context.go('/home'),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search movies…',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                          prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
                          prefixIconConstraints: const BoxConstraints(minWidth: 32),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  child: const Icon(Icons.clear, size: 16, color: Colors.white54),
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFF1B1A2C),
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF2A2840)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: Color(0xFF2A2840)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Sort Icon / Dropdown
                  Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1A2C),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2A2840)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<MovieSortOption>(
                        value: _sortOption,
                        isDense: true,
                        dropdownColor: const Color(0xFF1B1A2C),
                        icon: const Icon(Icons.sort_rounded, color: Color(0xFF6C5CE7), size: 18),
                        items: const [
                          DropdownMenuItem(value: MovieSortOption.recent, child: Text('Added', style: TextStyle(color: Colors.white, fontSize: 12))),
                          DropdownMenuItem(value: MovieSortOption.alphabetical, child: Text('A-Z', style: TextStyle(color: Colors.white, fontSize: 12))),
                          DropdownMenuItem(value: MovieSortOption.year, child: Text('Year', style: TextStyle(color: Colors.white, fontSize: 12))),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _sortOption = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Horizontal Category Chips Bar
            Container(
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF0C0B16),
                border: Border(bottom: BorderSide(color: Color(0xFF1E1D2F), width: 1)),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                itemCount: chips.length,
                itemBuilder: (context, index) {
                  final chip = chips[index];
                  final title = chip['title'] as String;
                  final count = chip['count'] as int;
                  final isSelected = _selectedCategory == title;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() => _selectedCategory = title),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF6C5CE7).withValues(alpha: 0.3)
                              : const Color(0xFF181728),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFFFD32A)
                                : const Color(0xFF2A2840),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                color: isSelected ? const Color(0xFFFFD32A) : Colors.white,
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '($count)',
                              style: TextStyle(
                                color: isSelected ? const Color(0xFFFFD32A) : Colors.white38,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Main Movie Grid (Full Screen Width)
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'No movies found in this category',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.65,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final movie = filtered[index];
                        final historyItem = history
                            .where((h) => h.id == movie.id)
                            .firstOrNull;

                        return _MovieCard(
                          movie: movie,
                          historyItem: historyItem,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVodCategoryItem({
    required String title,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6C5CE7).withValues(alpha: 0.22)
              : Colors.transparent,
          border: Border(
            bottom: const BorderSide(color: Color(0xFF1E1D2F), width: 1),
            left: isSelected
                ? const BorderSide(color: Color(0xFFFFD32A), width: 3.5)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? const Color(0xFFFFD32A) : Colors.white,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                color: isSelected ? const Color(0xFFFFD32A) : Colors.white38,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopToolbar(int resultCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0E1A),
        border: Border(bottom: BorderSide(color: Color(0xFF1E1D2F), width: 1)),
      ),
      child: Row(
        children: [
          // Sort Dropdown Pill (Screenshot 2: Trier par ajout ▾)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1A2C),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2A2840)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<MovieSortOption>(
                value: _sortOption,
                isDense: true,
                dropdownColor: const Color(0xFF1B1A2C),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(value: MovieSortOption.recent, child: Text('Sort by Added')),
                  DropdownMenuItem(value: MovieSortOption.alphabetical, child: Text('Sort by A-Z')),
                  DropdownMenuItem(value: MovieSortOption.year, child: Text('Sort by Year')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _sortOption = val);
                },
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Search in selected category
          SizedBox(
            width: 220,
            height: 34,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Search in $_selectedCategory…',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1B1A2C),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF2A2840)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF2A2840)),
                ),
              ),
            ),
          ),
          const Spacer(),
          // Category Title + Total Count on right (Screenshot 2: Tout(27106))
          Text(
            '$_selectedCategory ($resultCount)',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTmdbFallbackView(BuildContext context) {
    return FutureBuilder<List<TmdbSearchResult>>(
      future: TmdbClient.defaultClient.getPopularMovie(),
      builder: (context, snapshot) {
        final tmdbList = snapshot.data ?? [];
        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1C1A2E),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF6C5CE7), size: 20),
                  SizedBox(width: 10),
                  Text(
                    'No local VOD playlist loaded. Showing popular movies from TMDB:',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            Expanded(
              child: snapshot.connectionState == ConnectionState.waiting
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        childAspectRatio: 0.65,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: tmdbList.length,
                      itemBuilder: (context, index) {
                        final item = tmdbList[index];
                        final movieChannel = db.Channel(
                          id: 'tmdb_${item.id}',
                          providerId: 'tmdb',
                          name: item.displayName,
                          streamUrl: '',
                          streamType: 'vod',
                          tvgLogo: item.posterUrl,
                          groupTitle: 'Popular',
                          favorite: false,
                          hidden: false,
                          sortOrder: 0,
                        );
                        return _MovieCard(movie: movieChannel);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _MovieCard extends ConsumerStatefulWidget {
  final db.Channel movie;
  final WatchHistoryItem? historyItem;

  const _MovieCard({
    required this.movie,
    this.historyItem,
  });

  @override
  ConsumerState<_MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends ConsumerState<_MovieCard> {
  bool _isHovered = false;
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.movie.favorite;
  }

  @override
  void didUpdateWidget(covariant _MovieCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.movie.favorite != oldWidget.movie.favorite) {
      _isFavorite = widget.movie.favorite;
    }
  }

  Future<void> _toggleFavorite() async {
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    try {
      final dbInstance = ref.read(databaseProvider);
      await (dbInstance.update(dbInstance.channels)
            ..where((t) => t.id.equals(widget.movie.id)))
          .write(db.ChannelsCompanion(
        favorite: Value(next),
      ));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6C5CE7);
    final movie = widget.movie;
    final history = widget.historyItem;

    final isWatched = history != null && history.progressFraction >= 0.90;
    final hasProgress = history != null &&
        history.progressFraction > 0.05 &&
        history.progressFraction < 0.90;

    return Focus(
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;

          return MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: InkWell(
              onTap: () {
                context.push('/movies/detail', extra: movie);
              },
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: const Color(0xFF141322),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: hasFocus
                        ? Colors.white
                        : (_isHovered ? accent : const Color(0xFF26243A)),
                    width: hasFocus ? 2.5 : (_isHovered ? 1.5 : 1),
                  ),
                  boxShadow: hasFocus || _isHovered
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          movie.tvgLogo != null && movie.tvgLogo!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: movie.tvgLogo!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Center(
                                    child: Icon(Icons.movie_rounded,
                                        size: 40, color: Colors.white24),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.movie_rounded,
                                      size: 40, color: Colors.white24),
                                ),
                          // Watched badge
                          if (isWatched)
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check, size: 12, color: Colors.black),
                                    SizedBox(width: 2),
                                    Text(
                                      'WATCHED',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // High-contrast clean favorite badge
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _toggleFavorite,
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.72),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _isFavorite
                                          ? const Color(0xFFFFD32A)
                                          : Colors.white38,
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.5),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    _isFavorite
                                        ? Icons.star_rounded
                                        : Icons.star_border_rounded,
                                    color: _isFavorite
                                        ? const Color(0xFFFFD32A)
                                        : Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Floating blue rating pill badge (Only shown if a REAL rating exists)
                          if (_extractRating(movie.name) != null)
                            Positioned(
                              bottom: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E88E5),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _extractRating(movie.name)!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Progress bar if partially watched
                    if (hasProgress)
                      LinearProgressIndicator(
                        value: history.progressFraction,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF6C5CE7)),
                        minHeight: 4,
                      ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        movie.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String? _extractRating(String name) {
    // 1. Look for explicit IMDb/TMDB or Star ratings: e.g. "IMDb: 7.8", "Rating: 8.2", "★ 7.5", "8.2/10"
    final explicitMatch = RegExp(
      r'(?:imdb|tmdb|rating|rate|\*|★)\s*[:\-]?\s*([1-9](?:\.\d)?|10(?:\.0)?)',
      caseSensitive: false,
    ).firstMatch(name);
    if (explicitMatch != null) {
      final val = double.tryParse(explicitMatch.group(1) ?? '');
      if (val != null && val >= 1.0 && val <= 10.0) {
        return val.toStringAsFixed(1);
      }
    }

    // 2. Look for bracketed rating: e.g. "[7.8]" or "(8.2)" (ignoring 4-digit years like [2024])
    final bracketMatch = RegExp(r'[\[\(]([1-9]\.\d)(?:\s*\/\s*10)?[\]\)]').firstMatch(name);
    if (bracketMatch != null) {
      final val = double.tryParse(bracketMatch.group(1) ?? '');
      if (val != null && val >= 1.0 && val <= 10.0) {
        return val.toStringAsFixed(1);
      }
    }

    // 3. Look for explicit "/10" rating: e.g. "8.5/10" or "7/10"
    final slashMatch = RegExp(r'\b([1-9](?:\.\d)?|10)\s*\/\s*10\b').firstMatch(name);
    if (slashMatch != null) {
      final val = double.tryParse(slashMatch.group(1) ?? '');
      if (val != null && val >= 1.0 && val <= 10.0) {
        return val.toStringAsFixed(1);
      }
    }

    return null;
  }
}
