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

enum SeriesSortOption { recent, alphabetical, year }

class SeriesScreen extends ConsumerStatefulWidget {
  const SeriesScreen({super.key});

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  String _selectedCategory = 'All';
  String _searchQuery = '';
  String _categorySearchQuery = '';
  SeriesSortOption _sortOption = SeriesSortOption.recent;
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
                      t.streamType.equals('series')))
                .get()
            : (dbInstance.select(dbInstance.channels)
                  ..where((t) => t.streamType.equals('series')))
                .get(),
        builder: (context, snapshot) {
          final allSeries = snapshot.data ?? [];

          // If no local series in playlist, show TMDB popular TV shows as fallback
          if (snapshot.connectionState == ConnectionState.done && allSeries.isEmpty) {
            return _buildTmdbFallbackView(context);
          }

          // Extract distinct categories and counts
          final categoryCounts = <String, int>{};
          for (final s in allSeries) {
            final g = s.groupTitle;
            if (g != null && g.isNotEmpty) {
              categoryCounts[g] = (categoryCounts[g] ?? 0) + 1;
            }
          }
          final favCount = allSeries.where((s) => s.favorite).length;
          final recentCount = history.where((h) => allSeries.any((s) => s.id == h.id)).length;
          final allCount = allSeries.length;

          final sortedGroups = categoryCounts.keys.toList()..sort();

          // Filter by category
          var filtered = allSeries.where((s) {
            if (_selectedCategory == 'Recently Viewed') {
              return history.any((h) => h.id == s.id);
            }
            if (_selectedCategory == 'Favorites') return s.favorite;
            if (_selectedCategory == 'All') return true;
            return s.groupTitle == _selectedCategory;
          }).toList();

          // Filter by search query
          if (_searchQuery.isNotEmpty) {
            final q = _searchQuery.toLowerCase();
            filtered = filtered
                .where((s) => s.name.toLowerCase().contains(q))
                .toList();
          }

          // Sort
          switch (_sortOption) {
            case SeriesSortOption.recent:
              break;
            case SeriesSortOption.alphabetical:
              filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
              break;
            case SeriesSortOption.year:
              filtered.sort((a, b) => b.name.compareTo(a.name));
              break;
          }

          // Filter categories by search
          final catQuery = _categorySearchQuery.trim().toLowerCase();
          final visibleGroups = sortedGroups.where((g) {
            if (catQuery.isEmpty) return true;
            return g.toLowerCase().contains(catQuery);
          }).toList();

          return Row(
            children: [
              // ── Left Sidebar Categories (IBO Player Pro Style) ──
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
                    // Header: TV/Clapperboard Icon + Back / Search buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.live_tv_rounded,
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

                    // Category Search Input Field
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          controller: _categorySearchController,
                          onChanged: (val) => setState(() => _categorySearchQuery = val),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Search categories…',
                            hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                            prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
                            suffixIcon: _categorySearchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 14, color: Colors.white54),
                                    onPressed: () {
                                      _categorySearchController.clear();
                                      setState(() => _categorySearchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFF151426),
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: Color(0xFF232238)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: Color(0xFF232238)),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const Divider(height: 1, color: Color(0xFF1E1D2F)),

                    // Categories List with Right-aligned Counts (Screenshot 2)
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          if (recentCount > 0)
                            _buildCategoryRow('Recently Viewed', 'Recently Viewed', recentCount),
                          _buildCategoryRow('All', 'All', allCount),
                          _buildCategoryRow('Favorites', 'Favorites', favCount),
                          ...visibleGroups.map((group) {
                            final count = categoryCounts[group] ?? 0;
                            return _buildCategoryRow(group, group, count);
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Main Content Area: Top Toolbar & Full Grid ──
              Expanded(
                child: Column(
                  children: [
                    _buildTopToolbar(filtered.length),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(
                              child: Text(
                                'No series found in this category',
                                style: TextStyle(color: Colors.white38),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 180,
                                childAspectRatio: 0.62,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                              ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final s = filtered[index];
                                return _SeriesCard(series: s);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategoryRow(String key, String displayName, int count) {
    final isSelected = _selectedCategory == key;
    return InkWell(
      onTap: () => setState(() => _selectedCategory = key),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C5CE7).withValues(alpha: 0.22) : Colors.transparent,
          border: const Border(
            bottom: BorderSide(color: Color(0xFF1A192A), width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? const Color(0xFFFFD32A) : Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
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
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0F0E1C),
        border: Border(bottom: BorderSide(color: Color(0xFF1E1D2F), width: 1)),
      ),
      child: Row(
        children: [
          // Sort Dropdown Pill (Screenshot 2: "Trier par ajout ▾")
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1A2C),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2A2840)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<SeriesSortOption>(
                value: _sortOption,
                isDense: true,
                dropdownColor: const Color(0xFF1B1A2C),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(value: SeriesSortOption.recent, child: Text('Sort by Added')),
                  DropdownMenuItem(value: SeriesSortOption.alphabetical, child: Text('Sort by A-Z')),
                  DropdownMenuItem(value: SeriesSortOption.year, child: Text('Sort by Year')),
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
      future: TmdbClient.defaultClient.getPopularTv(),
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
                    'No series found in current playlist. Showing popular shows from TMDB:',
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
                        childAspectRatio: 0.62,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: tmdbList.length,
                      itemBuilder: (context, index) {
                        final item = tmdbList[index];
                        final showChannel = db.Channel(
                          id: 'tmdb_tv_${item.id}',
                          providerId: 'tmdb',
                          name: item.displayName,
                          streamUrl: '',
                          streamType: 'series',
                          tvgLogo: item.posterUrl,
                          groupTitle: 'Popular',
                          favorite: false,
                          hidden: false,
                          sortOrder: 0,
                        );
                        return _SeriesCard(series: showChannel);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SeriesCard extends ConsumerStatefulWidget {
  final db.Channel series;
  const _SeriesCard({required this.series});

  @override
  ConsumerState<_SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends ConsumerState<_SeriesCard> {
  bool _isHovered = false;
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.series.favorite;
  }

  @override
  void didUpdateWidget(covariant _SeriesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.series.favorite != oldWidget.series.favorite) {
      _isFavorite = widget.series.favorite;
    }
  }

  Future<void> _toggleFavorite() async {
    final next = !_isFavorite;
    setState(() => _isFavorite = next);
    try {
      final dbInstance = ref.read(databaseProvider);
      await (dbInstance.update(dbInstance.channels)
            ..where((t) => t.id.equals(widget.series.id)))
          .write(db.ChannelsCompanion(
        favorite: Value(next),
      ));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6C5CE7);
    final s = widget.series;

    return Focus(
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;

          return MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: InkWell(
              onTap: () {
                context.push('/series/detail', extra: s);
              },
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: const Color(0xFF141322),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasFocus
                        ? Colors.white
                        : (_isHovered ? accent : const Color(0xFF26243A)),
                    width: hasFocus ? 2.5 : (_isHovered ? 1.5 : 1),
                  ),
                  boxShadow: hasFocus || _isHovered
                      ? [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.35),
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
                          s.tvgLogo != null && s.tvgLogo!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: s.tvgLogo!,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Center(
                                    child: Icon(Icons.tv_rounded,
                                        size: 40, color: Colors.white24),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.tv_rounded,
                                      size: 40, color: Colors.white24),
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
                          if (_extractRating(s.name) != null)
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
                                  _extractRating(s.name)!,
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
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        s.name,
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
