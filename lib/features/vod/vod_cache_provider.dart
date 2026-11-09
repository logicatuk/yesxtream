import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/local/database.dart' as db;

class VodCacheState {
  final String? providerId;
  final Map<String, int> categoryCounts;
  final List<String> sortedGroups;
  final int allCount;
  final int favCount;
  final String selectedCategory;
  final List<db.Channel> movies;
  final bool isLoaded;

  const VodCacheState({
    this.providerId,
    this.categoryCounts = const {},
    this.sortedGroups = const [],
    this.allCount = 0,
    this.favCount = 0,
    this.selectedCategory = 'All',
    this.movies = const [],
    this.isLoaded = false,
  });

  VodCacheState copyWith({
    String? providerId,
    Map<String, int>? categoryCounts,
    List<String>? sortedGroups,
    int? allCount,
    int? favCount,
    String? selectedCategory,
    List<db.Channel>? movies,
    bool? isLoaded,
  }) {
    return VodCacheState(
      providerId: providerId ?? this.providerId,
      categoryCounts: categoryCounts ?? this.categoryCounts,
      sortedGroups: sortedGroups ?? this.sortedGroups,
      allCount: allCount ?? this.allCount,
      favCount: favCount ?? this.favCount,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      movies: movies ?? this.movies,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class SeriesCacheState {
  final String? providerId;
  final Map<String, int> categoryCounts;
  final List<String> sortedGroups;
  final int allCount;
  final int favCount;
  final String selectedCategory;
  final List<db.Channel> series;
  final bool isLoaded;

  const SeriesCacheState({
    this.providerId,
    this.categoryCounts = const {},
    this.sortedGroups = const [],
    this.allCount = 0,
    this.favCount = 0,
    this.selectedCategory = 'All',
    this.series = const [],
    this.isLoaded = false,
  });

  SeriesCacheState copyWith({
    String? providerId,
    Map<String, int>? categoryCounts,
    List<String>? sortedGroups,
    int? allCount,
    int? favCount,
    String? selectedCategory,
    List<db.Channel>? series,
    bool? isLoaded,
  }) {
    return SeriesCacheState(
      providerId: providerId ?? this.providerId,
      categoryCounts: categoryCounts ?? this.categoryCounts,
      sortedGroups: sortedGroups ?? this.sortedGroups,
      allCount: allCount ?? this.allCount,
      favCount: favCount ?? this.favCount,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      series: series ?? this.series,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

final vodCacheProvider = StateProvider<VodCacheState>((ref) => const VodCacheState());
final seriesCacheProvider = StateProvider<SeriesCacheState>((ref) => const SeriesCacheState());

