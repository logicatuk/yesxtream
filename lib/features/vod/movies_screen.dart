import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/parental_guard.dart';
import '../../core/platform_info.dart';
import '../../data/services/app_settings.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/datasources/remote/tmdb_client.dart';
import '../../data/datasources/remote/xtream_client.dart';
import '../../data/services/playback_history_service.dart';
import '../player/player_service.dart';
import '../playlists/playlist_providers.dart';
import '../providers/provider_manager.dart';
import 'vod_cache_provider.dart';

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
  final _scrollController = ScrollController();
  late final FocusNode _categoryFilterFocusNode =
      FocusNode(skipTraversal: PlatformInfo.isTV);
  late final FocusNode _gridSearchFocusNode =
      FocusNode(skipTraversal: PlatformInfo.isTV);

  Map<String, int> _categoryCounts = {};
  final Map<String, String> _categoryNameToId = {};
  List<String> _sortedGroups = [];
  int _allCount = 0;
  int _favCount = 0;
  List<db.Channel> _movies = [];
  bool _loadingCategories = true;
  bool _loadingMovies = false;
  int _offset = 0;
  bool _hasMore = true;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    try {
      ref.read(playerServiceProvider).stop();
    } catch (_) {}

    _scrollController.addListener(_onScroll);

    final cache = ref.read(vodCacheProvider);
    final activePlaylist = ref.read(activePlaylistProvider);
    if (cache.isLoaded && cache.providerId == activePlaylist?.id) {
      _categoryCounts = cache.categoryCounts;
      _sortedGroups = cache.sortedGroups;
      _allCount = cache.allCount;
      _favCount = cache.favCount;
      _selectedCategory = cache.selectedCategory;
      _movies = cache.movies;
      _loadingCategories = false;
      _loadingMovies = false;
      _offset = cache.movies.length;
      _hasMore = cache.movies.length >= 120;
    } else {
      _loadCategories().then((_) {
        _loadMovies(reset: true);
      });
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      if (!_loadingMovies && _hasMore) {
        _loadMovies(reset: false);
      }
    }
  }

  void _updateCache() {
    final activePlaylist = ref.read(activePlaylistProvider);
    ref.read(vodCacheProvider.notifier).state = VodCacheState(
      providerId: activePlaylist?.id,
      categoryCounts: _categoryCounts,
      sortedGroups: _sortedGroups,
      allCount: _allCount,
      favCount: _favCount,
      selectedCategory: _selectedCategory,
      movies: _movies,
      isLoaded: true,
    );
  }

  Future<void> _loadCategories() async {
    final dbInstance = ref.read(databaseProvider);
    final activePlaylist = ref.read(activePlaylistProvider);
    final pid = activePlaylist?.id;

    try {
      final counts = await dbInstance.getVodGroupCounts(providerId: pid);
      final total = await dbInstance.getVodTotalCount(providerId: pid);
      final favs = await dbInstance.getVodFavoriteCount(providerId: pid);
      List<String> sorted = counts.keys.toList();

      if (pid != null) {
        final prefs = await SharedPreferences.getInstance();
        final rawCats = prefs.getString('xtream_vod_cats_$pid');
        if (rawCats != null && rawCats.isNotEmpty) {
          try {
            final List decoded = jsonDecode(rawCats) as List;
            for (final item in decoded) {
              final id = item['id']?.toString() ?? '';
              final name = item['name']?.toString() ?? '';
              if (id.isNotEmpty && name.isNotEmpty) {
                _categoryNameToId[name] = id;
              }
            }
            final combined = {...sorted, ..._categoryNameToId.keys};
            sorted = combined.toList();
          } catch (_) {}
        }
      }
      sorted.sort();

      var selectedCat = _selectedCategory;
      if ((selectedCat == 'All' || selectedCat.isEmpty) && counts.isEmpty && sorted.isNotEmpty) {
        selectedCat = sorted.first;
      }

      if (mounted) {
        setState(() {
          _categoryCounts = counts;
          _sortedGroups = sorted;
          _selectedCategory = selectedCat;
          _allCount = total > 0 ? total : _sortedGroups.length;
          _favCount = favs;
          _loadingCategories = false;
        });
        _updateCache();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  Future<void> _loadMovies({bool reset = false}) async {
    if (_loadingMovies) return;
    if (!reset && !_hasMore) return;

    final nextOffset = reset ? 0 : _offset;
    if (mounted) setState(() => _loadingMovies = true);

    final dbInstance = ref.read(databaseProvider);
    final activePlaylist = ref.read(activePlaylistProvider);
    final history = ref.read(watchHistoryProvider);
    final pid = activePlaylist?.id;

    List<db.Channel> fetched = [];

    try {
      if (_selectedCategory == 'Recently Viewed') {
        final historyIds = history.map((h) => h.id).toSet();
        if (historyIds.isNotEmpty) {
          final allRecent = await dbInstance.getChannelsByIds(historyIds);
          fetched = allRecent.where((c) => c.streamType == 'vod').toList();
        }
        _hasMore = false;
      } else {
        final sortStr = _sortOption == MovieSortOption.alphabetical
            ? 'alphabetical'
            : (_sortOption == MovieSortOption.year ? 'year' : 'recent');

        fetched = await dbInstance.getVodMoviesPaged(
          providerId: pid,
          groupTitle: _selectedCategory,
          searchQuery: _searchQuery,
          favoritesOnly: _selectedCategory == 'Favorites',
          limit: 120,
          offset: nextOffset,
          sortBy: sortStr,
        );

        // On-demand lazy fetch from Xtream server if category is not yet cached locally
        if (fetched.isEmpty &&
            nextOffset == 0 &&
            _searchQuery.isEmpty &&
            activePlaylist?.type == 'xtream' &&
            activePlaylist?.url != null &&
            activePlaylist?.username != null &&
            activePlaylist?.password != null &&
            pid != null &&
            _selectedCategory != 'Favorites') {
          final targetCatId = _categoryNameToId[_selectedCategory] ??
              (_selectedCategory == 'All' && _categoryNameToId.isNotEmpty
                  ? _categoryNameToId.values.first
                  : null);

          if (targetCatId != null && targetCatId.isNotEmpty) {
            final client = XtreamClient(
              baseUrl: activePlaylist!.url!,
              username: activePlaylist.username!,
              password: activePlaylist.password!,
            );
            try {
              final remoteStreams = await client.getVodStreams(
                categoryId: targetCatId,
                providerId: pid,
                categoryMap: {targetCatId: _selectedCategory},
              );
              if (remoteStreams.isNotEmpty) {
                final companions = remoteStreams.map((c) {
                  return db.ChannelsCompanion.insert(
                    id: c.id,
                    providerId: c.providerId,
                    name: c.name,
                    tvgId: Value(c.tvgId),
                    tvgName: Value(c.tvgName),
                    tvgLogo: Value(c.tvgLogo),
                    groupTitle: Value(c.groupTitle),
                    channelNumber: Value(c.channelNumber),
                    streamUrl: c.streamUrl,
                    streamType: const Value('vod'),
                  );
                }).toList();
                await dbInstance.upsertChannels(companions);
                _categoryCounts[_selectedCategory] = companions.length;
                fetched = await dbInstance.getVodMoviesPaged(
                  providerId: pid,
                  groupTitle: _selectedCategory,
                  limit: 120,
                  sortBy: sortStr,
                );
              }
            } catch (e) {
              debugPrint('[VodOnDemand] Failed to fetch category $targetCatId: $e');
            } finally {
              client.dispose();
            }
          }
        }

        _hasMore = fetched.length >= 120;
      }

      if (mounted) {
        setState(() {
          if (reset) {
            _movies = fetched;
            _offset = fetched.length;
          } else {
            _movies.addAll(fetched);
            _offset += fetched.length;
          }
          _loadingMovies = false;
        });
        _updateCache();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMovies = false);
    }
  }

  Future<void> _selectCategory(String cat) async {
    if (_selectedCategory == cat) return;
    final settings = ref.read(appSettingsProvider);
    if (!await ParentalGuard.unlockIfNeeded(context, settings, groupTitle: cat)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _selectedCategory = cat;
    });
    _loadMovies(reset: true);
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadMovies(reset: true);
    });
  }

  void _onSortChanged(MovieSortOption opt) {
    setState(() => _sortOption = opt);
    _loadMovies(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _categorySearchController.dispose();
    _categoryFilterFocusNode.dispose();
    _gridSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(watchHistoryProvider);
    final recentCount = history.where((h) => h.streamType == 'vod').length;

    if (_loadingCategories && _movies.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0F),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
        ),
      );
    }

    if (!_loadingCategories && _allCount == 0 && _movies.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: _buildTmdbFallbackView(context),
      );
    }

    final catQuery = _categorySearchQuery.trim().toLowerCase();
    final visibleGroups = _sortedGroups.where((g) {
      if (catQuery.isEmpty) return true;
      return g.toLowerCase().contains(catQuery);
    }).toList();

    void handleBack() {
      if (ModalRoute.of(context)?.isCurrent != true) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/home');
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) handleBack();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): handleBack,
          const SingleActivator(LogicalKeyboardKey.goBack): handleBack,
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = !PlatformInfo.isTV && constraints.maxWidth < 750;
          if (isCompact) {
            return _buildCompactLayout(
              context,
              _sortedGroups,
              _categoryCounts,
              _allCount,
              _favCount,
              recentCount,
              _movies,
              history,
              constraints,
            );
          }

          return Row(
            children: [
              // ── Left Sidebar Categories ──
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
                    // Header: Back / Search
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: FocusableActionDetector(
                              actions: {
                                ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                                  context.go('/home');
                                  return null;
                                }),
                                ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) {
                                  context.go('/home');
                                  return null;
                                }),
                              },
                              child: Builder(
                                builder: (btnCtx) {
                                  final hasFocus = Focus.of(btnCtx).hasFocus;
                                  return InkWell(
                                    onTap: () => context.go('/home'),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      decoration: BoxDecoration(
                                        color: hasFocus
                                            ? const Color(0xFF6C5CE7).withValues(alpha: 0.35)
                                            : const Color(0xFF1B1A2C),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: hasFocus ? Colors.white : const Color(0xFF2A2840),
                                          width: hasFocus ? 2.5 : 1.0,
                                        ),
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
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FocusableActionDetector(
                              actions: {
                                ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                                  context.go('/search');
                                  return null;
                                }),
                                ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) {
                                  context.go('/search');
                                  return null;
                                }),
                              },
                              child: Builder(
                                builder: (btnCtx) {
                                  final hasFocus = Focus.of(btnCtx).hasFocus;
                                  return InkWell(
                                    onTap: () => context.go('/search'),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      decoration: BoxDecoration(
                                        color: hasFocus
                                            ? const Color(0xFF6C5CE7).withValues(alpha: 0.35)
                                            : const Color(0xFF1B1A2C),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: hasFocus ? Colors.white : const Color(0xFF2A2840),
                                          width: hasFocus ? 2.5 : 1.0,
                                        ),
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
                                  );
                                },
                              ),
                            ),
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
                          focusNode: _categoryFilterFocusNode,
                          controller: _categorySearchController,
                          onChanged: (val) => setState(() => _categorySearchQuery = val),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: 'Filter categories…',
                            hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                            prefixIcon: const Icon(Icons.search, size: 14, color: Colors.white38),
                            prefixIconConstraints: const BoxConstraints(minWidth: 28),
                            suffixIcon: _categorySearchQuery.isNotEmpty
                                ? GestureDetector(
                                    onTap: () {
                                      _categorySearchController.clear();
                                      setState(() => _categorySearchQuery = '');
                                    },
                                    child: const Icon(Icons.clear, size: 14, color: Colors.white54),
                                  )
                                : null,
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
                              onTap: () => _selectCategory('Recently Viewed'),
                            ),
                          _buildVodCategoryItem(
                            title: 'All',
                            count: _allCount,
                            isSelected: _selectedCategory == 'All',
                            onTap: () => _selectCategory('All'),
                          ),
                          _buildVodCategoryItem(
                            title: 'Favorites',
                            count: _favCount,
                            isSelected: _selectedCategory == 'Favorites',
                            onTap: () => _selectCategory('Favorites'),
                          ),
                          for (final group in visibleGroups)
                            _buildVodCategoryItem(
                              title: group,
                              count: _categoryCounts[group] ?? 0,
                              isSelected: _selectedCategory == group,
                              onTap: () => _selectCategory(group),
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
                    _buildTopToolbar(_categoryCounts[_selectedCategory] ?? (_selectedCategory == 'All' ? _allCount : _movies.length)),
                    Expanded(
                      child: _movies.isEmpty && !_loadingMovies
                          ? const Center(
                              child: Text(
                                'No movies found in this category',
                                style: TextStyle(color: Colors.white38),
                              ),
                            )
                          : GridView.builder(
                              controller: _scrollController,
                              cacheExtent: PlatformInfo.isTV ? 200 : 500,
                              addAutomaticKeepAlives: !PlatformInfo.isTV,
                              padding: const EdgeInsets.all(20),
                              gridDelegate:
                                  SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: PlatformInfo.isTV ? 230 : 180,
                                childAspectRatio: 0.65,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                              itemCount: _movies.length + (_loadingMovies ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _movies.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
                                    ),
                                  );
                                }
                                final movie = _movies[index];
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
      ),
        ),
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
    List<db.Channel> movies,
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
        left: false,
        right: false,
        top: false,
        bottom: false,
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
                        onChanged: _onSearchChanged,
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
                                    _onSearchChanged('');
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
                          if (val != null) _onSortChanged(val);
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
                      onTap: () => _selectCategory(title),
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
              child: movies.isEmpty && !_loadingMovies
                  ? const Center(
                      child: Text(
                        'No movies found in this category',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.65,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: movies.length + (_loadingMovies ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == movies.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
                            ),
                          );
                        }
                        final movie = movies[index];
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
    return FocusableActionDetector(
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          onTap();
          return null;
        }),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) {
          onTap();
          return null;
        }),
      },
      child: Builder(
        builder: (itemCtx) {
          final hasFocus = Focus.of(itemCtx).hasFocus;
          return InkWell(
            autofocus: isSelected && PlatformInfo.isTV,
            onTap: onTap,
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: hasFocus
                    ? const Color(0xFF6C5CE7).withValues(alpha: 0.35)
                    : isSelected
                        ? const Color(0xFF6C5CE7).withValues(alpha: 0.22)
                        : Colors.transparent,
                border: hasFocus
                    ? Border.all(color: Colors.white, width: 2.5)
                    : Border(
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
                        color: isSelected
                            ? const Color(0xFFFFD32A)
                            : (hasFocus ? Colors.white : Colors.white.withValues(alpha: 0.9)),
                        fontSize: 13,
                        fontWeight: (isSelected || hasFocus) ? FontWeight.bold : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: isSelected ? const Color(0xFFFFD32A) : Colors.white54,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
                  if (val != null) _onSortChanged(val);
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
              focusNode: _gridSearchFocusNode,
              controller: _searchController,
              onChanged: _onSearchChanged,
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
                          _onSearchChanged('');
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
  static final _explicitRatingRegex = RegExp(
    r'(?:imdb|tmdb|rating|rate|\*|★)\s*[:\-]?\s*([1-9](?:\.\d)?|10(?:\.0)?)',
    caseSensitive: false,
  );
  static final _bracketRatingRegex = RegExp(r'[\[\(]([1-9]\.\d)(?:\s*\/\s*10)?[\]\)]');
  static final _slashRatingRegex = RegExp(r'\b([1-9](?:\.\d)?|10)\s*\/\s*10\b');

  bool _isHovered = false;
  late bool _isFavorite;
  String? _rating;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.movie.favorite;
    _rating = _extractRating(widget.movie.name);
  }

  @override
  void didUpdateWidget(covariant _MovieCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.movie.favorite != oldWidget.movie.favorite) {
      _isFavorite = widget.movie.favorite;
    }
    if (widget.movie.name != oldWidget.movie.name) {
      _rating = _extractRating(widget.movie.name);
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

    Future<void> openDetail() async {
      final settings = ref.read(appSettingsProvider);
      if (!await ParentalGuard.unlockIfNeeded(
        context,
        settings,
        groupTitle: movie.groupTitle,
      )) {
        return;
      }
      if (!context.mounted) return;
      context.push('/movies/detail', extra: movie);
    }

    return RepaintBoundary(
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            openDetail();
            return null;
          }),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) {
            openDetail();
            return null;
          }),
        },
        child: Builder(
          builder: (context) {
            final hasFocus = Focus.of(context).hasFocus;
            final isTV = PlatformInfo.isTV;

            return MouseRegion(
              onEnter: isTV ? null : (_) => setState(() => _isHovered = true),
              onExit: isTV ? null : (_) => setState(() => _isHovered = false),
              child: InkWell(
                onTap: openDetail,
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: isTV ? 0 : 150),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141322),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasFocus
                          ? Colors.white
                          : (_isHovered ? accent : const Color(0xFF26243A)),
                      width: hasFocus ? (isTV ? 3.2 : 2.5) : (_isHovered ? 1.5 : 1),
                    ),
                    boxShadow: (!isTV && (hasFocus || _isHovered))
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  clipBehavior: isTV ? Clip.hardEdge : Clip.antiAlias,
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
                                    memCacheWidth: PlatformInfo.isTV ? 160 : 320,
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
                          if (_rating != null)
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
                                  _rating!,
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
      ),
    );
  }

  static String? _extractRating(String name) {
    // 1. Look for explicit IMDb/TMDB or Star ratings: e.g. "IMDb: 7.8", "Rating: 8.2", "★ 7.5", "8.2/10"
    final explicitMatch = _explicitRatingRegex.firstMatch(name);
    if (explicitMatch != null) {
      final val = double.tryParse(explicitMatch.group(1) ?? '');
      if (val != null && val >= 1.0 && val <= 10.0) {
        return val.toStringAsFixed(1);
      }
    }

    // 2. Look for bracketed rating: e.g. "[7.8]" or "(8.2)" (ignoring 4-digit years like [2024])
    final bracketMatch = _bracketRatingRegex.firstMatch(name);
    if (bracketMatch != null) {
      final val = double.tryParse(bracketMatch.group(1) ?? '');
      if (val != null && val >= 1.0 && val <= 10.0) {
        return val.toStringAsFixed(1);
      }
    }

    // 3. Look for explicit "/10" rating: e.g. "8.5/10" or "7/10"
    final slashMatch = _slashRatingRegex.firstMatch(name);
    if (slashMatch != null) {
      final val = double.tryParse(slashMatch.group(1) ?? '');
      if (val != null && val >= 1.0 && val <= 10.0) {
        return val.toStringAsFixed(1);
      }
    }

    return null;
  }
}
