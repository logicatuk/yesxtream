import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/datasources/remote/tmdb_client.dart';
import '../../data/services/app_settings.dart';
import '../../data/services/playback_history_service.dart';
import '../player/player_service.dart';
import '../playlists/playlist_providers.dart';
import '../providers/provider_manager.dart';
import 'vod_cache_provider.dart';

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
  final _scrollController = ScrollController();

  Map<String, int> _categoryCounts = {};
  List<String> _sortedGroups = [];
  int _allCount = 0;
  int _favCount = 0;
  List<db.Channel> _series = [];
  bool _loadingCategories = true;
  bool _loadingSeries = false;
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

    final cache = ref.read(seriesCacheProvider);
    final activePlaylist = ref.read(activePlaylistProvider);
    if (cache.isLoaded && cache.providerId == activePlaylist?.id) {
      _categoryCounts = cache.categoryCounts;
      _sortedGroups = cache.sortedGroups;
      _allCount = cache.allCount;
      _favCount = cache.favCount;
      _selectedCategory = cache.selectedCategory;
      _series = cache.series;
      _loadingCategories = false;
      _loadingSeries = false;
      _offset = cache.series.length;
      _hasMore = cache.series.length >= 120;
    } else {
      _loadCategories();
      _loadSeries(reset: true);
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400) {
      if (!_loadingSeries && _hasMore) {
        _loadSeries(reset: false);
      }
    }
  }

  void _updateCache() {
    final activePlaylist = ref.read(activePlaylistProvider);
    ref.read(seriesCacheProvider.notifier).state = SeriesCacheState(
      providerId: activePlaylist?.id,
      categoryCounts: _categoryCounts,
      sortedGroups: _sortedGroups,
      allCount: _allCount,
      favCount: _favCount,
      selectedCategory: _selectedCategory,
      series: _series,
      isLoaded: true,
    );
  }

  Future<void> _loadCategories() async {
    final dbInstance = ref.read(databaseProvider);
    final activePlaylist = ref.read(activePlaylistProvider);
    final pid = activePlaylist?.id;

    try {
      final counts = await dbInstance.getSeriesGroupCounts(providerId: pid);
      final total = await dbInstance.getSeriesTotalCount(providerId: pid);
      final favs = await dbInstance.getSeriesFavoriteCount(providerId: pid);
      final sorted = counts.keys.toList()..sort();

      if (mounted) {
        setState(() {
          _categoryCounts = counts;
          _sortedGroups = sorted;
          _allCount = total;
          _favCount = favs;
          _loadingCategories = false;
        });
        _updateCache();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingCategories = false);
    }
  }

  Future<void> _loadSeries({bool reset = false}) async {
    if (_loadingSeries) return;
    if (!reset && !_hasMore) return;

    final nextOffset = reset ? 0 : _offset;
    if (mounted) setState(() => _loadingSeries = true);

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
          fetched = allRecent.where((c) => c.streamType == 'series').toList();
        }
        _hasMore = false;
      } else {
        final sortStr = _sortOption == SeriesSortOption.alphabetical
            ? 'alphabetical'
            : (_sortOption == SeriesSortOption.year ? 'year' : 'recent');

        fetched = await dbInstance.getSeriesPaged(
          providerId: pid,
          groupTitle: _selectedCategory,
          searchQuery: _searchQuery,
          favoritesOnly: _selectedCategory == 'Favorites',
          limit: 120,
          offset: nextOffset,
          sortBy: sortStr,
        );
        _hasMore = fetched.length >= 120;
      }

      if (mounted) {
        setState(() {
          if (reset) {
            _series = fetched;
            _offset = fetched.length;
          } else {
            _series.addAll(fetched);
            _offset += fetched.length;
          }
          _loadingSeries = false;
        });
        _updateCache();
      }
    } catch (_) {
      if (mounted) setState(() => _loadingSeries = false);
    }
  }

  void _selectCategory(String cat) {
    if (_selectedCategory == cat) return;
    setState(() {
      _selectedCategory = cat;
    });
    _loadSeries(reset: true);
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadSeries(reset: true);
    });
  }

  void _onSortChanged(SeriesSortOption opt) {
    setState(() => _sortOption = opt);
    _loadSeries(reset: true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _categorySearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(watchHistoryProvider);
    final settings = ref.watch(appSettingsProvider);
    final recentCount = history.where((h) => h.streamType == 'series').length;

    if (_loadingCategories && _series.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0F),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
        ),
      );
    }

    if (!_loadingCategories && _allCount == 0 && _series.isEmpty) {
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
          final isCompact = constraints.maxWidth < 750;
          if (isCompact) {
            return _buildCompactLayout(
              context,
              _sortedGroups,
              _categoryCounts,
              _allCount,
              _favCount,
              _series,
              constraints,
            );
          }

          return Row(
            children: [
              // ── Left Sidebar: Header & Categories ──
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
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.arrow_back_rounded, size: 14, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text(settings.tr('back'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.search_rounded, size: 14, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text(settings.tr('search'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Category Search Input
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          controller: _categorySearchController,
                          onChanged: (val) => setState(() => _categorySearchQuery = val),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                          decoration: InputDecoration(
                            hintText: settings.tr('filter_categories'),
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

                    // Categories List
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          if (recentCount > 0)
                            _buildCategoryRow('Recently Viewed', settings.tr('continue_watching'), recentCount),
                          _buildCategoryRow('All', settings.tr('all_categories'), _allCount),
                          _buildCategoryRow('Favorites', settings.tr('favorites'), _favCount),
                          ...visibleGroups.map((group) {
                            final count = _categoryCounts[group] ?? 0;
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
                    _buildTopToolbar(_categoryCounts[_selectedCategory] ?? (_selectedCategory == 'All' ? _allCount : _series.length)),
                    Expanded(
                      child: _series.isEmpty && !_loadingSeries
                          ? const Center(
                              child: Text(
                                'No series found in this category',
                                style: TextStyle(color: Colors.white38),
                              ),
                            )
                          : GridView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.all(16),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 180,
                                childAspectRatio: 0.62,
                                crossAxisSpacing: 14,
                                mainAxisSpacing: 14,
                              ),
                              itemCount: _series.length + (_loadingSeries ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _series.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
                                    ),
                                  );
                                }
                                final s = _series[index];
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
    List<db.Channel> series,
    BoxConstraints constraints,
  ) {
    final settings = ref.watch(appSettingsProvider);
    final chips = <Map<String, dynamic>>[
      {'title': 'All', 'count': allCount, 'label': settings.tr('all')},
      {'title': 'Favorites', 'count': favCount, 'label': settings.tr('favorites')},
      ...sortedGroups.map((g) => {'title': g, 'count': categoryCounts[g] ?? 0, 'label': g}),
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
                color: Color(0xFF0F0E1C),
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
                          hintText: settings.tr('search_series'),
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
                      child: DropdownButton<SeriesSortOption>(
                        value: _sortOption,
                        isDense: true,
                        dropdownColor: const Color(0xFF1B1A2C),
                        icon: const Icon(Icons.sort_rounded, color: Color(0xFF6C5CE7), size: 18),
                        items: [
                          DropdownMenuItem(value: SeriesSortOption.recent, child: Text(settings.tr('sort_recent'), style: const TextStyle(color: Colors.white, fontSize: 12))),
                          DropdownMenuItem(value: SeriesSortOption.alphabetical, child: Text(settings.tr('sort_alphabetical'), style: const TextStyle(color: Colors.white, fontSize: 12))),
                          DropdownMenuItem(value: SeriesSortOption.year, child: Text(settings.tr('sort_year'), style: const TextStyle(color: Colors.white, fontSize: 12))),
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
                  final label = chip['label'] as String;
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
                              label,
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

            // Main Series Grid (Full Screen Width)
            Expanded(
              child: series.isEmpty && !_loadingSeries
                  ? const Center(
                      child: Text(
                        'No series found in this category',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.62,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: series.length + (_loadingSeries ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == series.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16.0),
                              child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
                            ),
                          );
                        }
                        final s = series[index];
                        return _SeriesCard(series: s);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

    Widget _buildCategoryRow(String key, String displayName, int count) {
    final isSelected = _selectedCategory == key;
    return InkWell(
      onTap: () => _selectCategory(key),
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
    final settings = ref.watch(appSettingsProvider);
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
                items: [
                  DropdownMenuItem(value: SeriesSortOption.recent, child: Text(settings.tr('sort_recent'))),
                  DropdownMenuItem(value: SeriesSortOption.alphabetical, child: Text(settings.tr('sort_alphabetical'))),
                  DropdownMenuItem(value: SeriesSortOption.year, child: Text(settings.tr('sort_year'))),
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
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: '${settings.tr('search_in')} $_selectedCategory…',
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
      canRequestFocus: false,
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
