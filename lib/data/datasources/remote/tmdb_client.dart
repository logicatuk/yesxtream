import 'package:dio/dio.dart';

/// Direct TMDB API key (internal only - never exposed to user)
const String tmdbApiKey = '23829a23ce35d4698331b31d4c662bd9';

/// Client for The Movie Database (TMDB) API v3
/// Docs: https://developer.themoviedb.org/docs
class TmdbClient {
  final Dio _dio;
  final String apiKey;

  static const _baseUrl = 'https://api.themoviedb.org/3';
  static const _imageBase = 'https://image.tmdb.org/t/p';

  static final TmdbClient defaultClient = TmdbClient(apiKey: tmdbApiKey);

  // In-memory response cache for fast repeats
  static final Map<String, TmdbShowDetail> _detailCache = {};
  static final Map<String, List<TmdbSearchResult>> _searchCache = {};
  static final Map<String, TmdbSeasonDetail> _seasonCache = {};

  TmdbClient({
    this.apiKey = tmdbApiKey,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    // Detect if user provided a v4 Bearer token (long JWT) vs v3 API key (short hex)
    final isBearerToken = apiKey.length > 40 || apiKey.startsWith('eyJ');

    _dio.options
      ..baseUrl = _baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 15);
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (isBearerToken) {
          options.headers['Authorization'] = 'Bearer $apiKey';
        } else {
          options.queryParameters['api_key'] = apiKey;
        }
        handler.next(options);
      },
    ));
  }

  /// Build a full image URL from a TMDB file path
  static String imageUrl(String? path, {String size = 'w500'}) {
    if (path == null || path.isEmpty) return '';
    return '$_imageBase/$size$path';
  }

  /// Get poster URL (w500)
  static String posterUrl(String? path) => imageUrl(path, size: 'w500');

  /// Get backdrop URL (w1280)
  static String backdropUrl(String? path) => imageUrl(path, size: 'w1280');

  /// Get still/screenshot URL (w300)
  static String stillUrl(String? path) => imageUrl(path, size: 'w300');

  /// Get TV show details including images and external IDs
  Future<TmdbShowDetail> getTvShow(int tmdbId) async {
    final response = await _dio.get('/tv/$tmdbId',
        queryParameters: {'append_to_response': 'external_ids,credits,videos'});
    return TmdbShowDetail.fromJson(response.data as Map<String, dynamic>);
  }

  /// Get movie details including images and external IDs
  Future<TmdbShowDetail> getMovie(int tmdbId) async {
    final response = await _dio.get('/movie/$tmdbId',
        queryParameters: {'append_to_response': 'external_ids,credits,videos'});
    return TmdbShowDetail.fromJson(response.data as Map<String, dynamic>);
  }

  /// Alias for getMovie
  Future<TmdbShowDetail> getMovieDetails(int tmdbId) => getMovie(tmdbId);

  /// Get TV season details with episode list
  Future<TmdbSeasonDetail> getTvSeason(int tmdbId, int seasonNumber) async {
    final response = await _dio.get('/tv/$tmdbId/season/$seasonNumber');
    return TmdbSeasonDetail.fromJson(response.data as Map<String, dynamic>);
  }

  /// Search for TV shows
  Future<List<TmdbSearchResult>> searchTv(String query) async {
    final response = await _dio.get(
      '/search/tv',
      queryParameters: {'query': query},
    );
    final results = response.data['results'] as List;
    return results
        .map((e) => TmdbSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Search for movies
  Future<List<TmdbSearchResult>> searchMovie(String query) async {
    final response = await _dio.get(
      '/search/movie',
      queryParameters: {'query': query},
    );
    final results = response.data['results'] as List;
    return results
        .map((e) => TmdbSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Alias for searchMovie
  Future<List<TmdbSearchResult>> searchMovies(String query) => searchMovie(query);

  /// Get trending TV shows (day or week)
  Future<List<TmdbSearchResult>> getTrendingTv({String window = 'day', int page = 1}) async {
    final response = await _dio.get(
      '/trending/tv/$window',
      queryParameters: {'page': page},
    );
    final results = response.data['results'] as List;
    return results
        .map((e) => TmdbSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get trending movies (day or week)
  Future<List<TmdbSearchResult>> getTrendingMovie({String window = 'day', int page = 1}) async {
    final response = await _dio.get(
      '/trending/movie/$window',
      queryParameters: {'page': page},
    );
    final results = response.data['results'] as List;
    return results
        .map((e) => TmdbSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get popular TV shows
  Future<List<TmdbSearchResult>> getPopularTv({int page = 1}) async {
    final response = await _dio.get(
      '/tv/popular',
      queryParameters: {'page': page},
    );
    final results = response.data['results'] as List;
    return results
        .map((e) => TmdbSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get popular movies
  Future<List<TmdbSearchResult>> getPopularMovie({int page = 1}) async {
    final response = await _dio.get(
      '/movie/popular',
      queryParameters: {'page': page},
    );
    final results = response.data['results'] as List;
    return results
        .map((e) => TmdbSearchResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Find by external ID (e.g., IMDB ID)
  Future<TmdbShowDetail?> findByImdbId(String imdbId, {bool isMovie = false}) async {
    final response = await _dio.get(
      '/find/$imdbId',
      queryParameters: {'external_source': 'imdb_id'},
    );
    final key = isMovie ? 'movie_results' : 'tv_results';
    final results = response.data[key] as List;
    if (results.isEmpty) return null;
    return TmdbShowDetail.fromJson(results.first as Map<String, dynamic>);
  }

  /// Search and get movie details with local cache
  Future<TmdbShowDetail?> searchAndGetMovie(String title, {int? year}) async {
    final cacheKey = 'm_${title.toLowerCase().trim()}_$year';
    if (_detailCache.containsKey(cacheKey)) return _detailCache[cacheKey];

    try {
      final results = await searchMovie(title);
      if (results.isEmpty) return null;
      TmdbSearchResult best = results.first;
      if (year != null) {
        for (final r in results) {
          if (r.year == year) {
            best = r;
            break;
          }
        }
      }
      final detail = await getMovie(best.id);
      _detailCache[cacheKey] = detail;
      return detail;
    } catch (_) {
      return null;
    }
  }

  /// Search and get TV show details with local cache
  Future<TmdbShowDetail?> searchAndGetTv(String title, {int? year}) async {
    final cacheKey = 't_${title.toLowerCase().trim()}_$year';
    if (_detailCache.containsKey(cacheKey)) return _detailCache[cacheKey];

    try {
      final results = await searchTv(title);
      if (results.isEmpty) return null;
      TmdbSearchResult best = results.first;
      if (year != null) {
        for (final r in results) {
          if (r.year == year) {
            best = r;
            break;
          }
        }
      }
      final detail = await getTvShow(best.id);
      _detailCache[cacheKey] = detail;
      return detail;
    } catch (_) {
      return null;
    }
  }

  /// Get TV season with local cache
  Future<TmdbSeasonDetail?> getCachedTvSeason(int tmdbId, int seasonNumber) async {
    final cacheKey = 's_${tmdbId}_$seasonNumber';
    if (_seasonCache.containsKey(cacheKey)) return _seasonCache[cacheKey];

    try {
      final detail = await getTvSeason(tmdbId, seasonNumber);
      _seasonCache[cacheKey] = detail;
      return detail;
    } catch (_) {
      return null;
    }
  }
}

/// TMDB show/movie detail with image paths
class TmdbShowDetail {
  final int id;
  final String title;
  final String? imdbId;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final double? voteAverage;
  final int? voteCount;
  final List<String> genres;
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final int? year;
  final int? runtime;
  final String? releaseDate;
  final String? director;
  final List<String> cast;
  final String? trailerKey;

  const TmdbShowDetail({
    required this.id,
    this.title = '',
    this.imdbId,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.voteAverage,
    this.voteCount,
    this.genres = const [],
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.year,
    this.runtime,
    this.releaseDate,
    this.director,
    this.cast = const [],
    this.trailerKey,
  });

  String get posterUrl => TmdbClient.posterUrl(posterPath);
  String get backdropUrl => TmdbClient.backdropUrl(backdropPath);

  factory TmdbShowDetail.fromJson(Map<String, dynamic> json) {
    final relDate = json['release_date'] as String? ?? json['first_air_date'] as String? ?? '';
    final externalIds = json['external_ids'] as Map<String, dynamic>?;
    final imdbId = json['imdb_id'] as String? ?? externalIds?['imdb_id'] as String?;

    // Credits
    final credits = json['credits'] as Map<String, dynamic>?;
    final crewList = credits?['crew'] as List?;
    String? director;
    if (crewList != null) {
      for (final c in crewList) {
        if (c is Map && c['job'] == 'Director') {
          director = c['name'] as String?;
          break;
        }
      }
    }
    final castList = (credits?['cast'] as List?)
            ?.take(10)
            .map((c) => (c is Map ? c['name'] as String? : null) ?? '')
            .where((n) => n.isNotEmpty)
            .toList() ??
        [];

    // Videos
    final videos = json['videos'] as Map<String, dynamic>?;
    final videoList = videos?['results'] as List?;
    String? trailerKey;
    if (videoList != null) {
      for (final v in videoList) {
        if (v is Map && v['type'] == 'Trailer' && v['site'] == 'YouTube') {
          trailerKey = v['key'] as String?;
          break;
        }
      }
    }

    return TmdbShowDetail(
      id: json['id'] as int,
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      imdbId: imdbId,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      overview: json['overview'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      voteCount: json['vote_count'] as int?,
      genres: (json['genres'] as List?)
              ?.map((g) => (g as Map<String, dynamic>)['name'] as String)
              .toList() ??
          [],
      numberOfSeasons: json['number_of_seasons'] as int?,
      numberOfEpisodes: json['number_of_episodes'] as int?,
      year: relDate.length >= 4 ? int.tryParse(relDate.substring(0, 4)) : null,
      runtime: json['runtime'] as int?,
      releaseDate: relDate.isNotEmpty ? relDate : null,
      director: director,
      cast: castList,
      trailerKey: trailerKey,
    );
  }
}

/// TMDB season detail with episodes
class TmdbSeasonDetail {
  final int? id;
  final int seasonNumber;
  final String? name;
  final String? posterPath;
  final String? overview;
  final List<TmdbEpisode> episodes;

  const TmdbSeasonDetail({
    this.id,
    required this.seasonNumber,
    this.name,
    this.posterPath,
    this.overview,
    this.episodes = const [],
  });

  factory TmdbSeasonDetail.fromJson(Map<String, dynamic> json) {
    return TmdbSeasonDetail(
      id: json['id'] as int?,
      seasonNumber: json['season_number'] as int,
      name: json['name'] as String?,
      posterPath: json['poster_path'] as String?,
      overview: json['overview'] as String?,
      episodes: (json['episodes'] as List?)
              ?.map((e) => TmdbEpisode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// A single TMDB episode
class TmdbEpisode {
  final int episodeNumber;
  final int seasonNumber;
  final String? name;
  final String? overview;
  final String? stillPath;
  final double? voteAverage;
  final String? airDate;

  const TmdbEpisode({
    required this.episodeNumber,
    required this.seasonNumber,
    this.name,
    this.overview,
    this.stillPath,
    this.voteAverage,
    this.airDate,
  });

  String get stillUrl => TmdbClient.stillUrl(stillPath);

  factory TmdbEpisode.fromJson(Map<String, dynamic> json) {
    return TmdbEpisode(
      episodeNumber: json['episode_number'] as int,
      seasonNumber: json['season_number'] as int,
      name: json['name'] as String?,
      overview: json['overview'] as String?,
      stillPath: json['still_path'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      airDate: json['air_date'] as String?,
    );
  }
}

/// TMDB search result
class TmdbSearchResult {
  final int id;
  final String? name;
  final String? title;
  final String? posterPath;
  final String? backdropPath;
  final String? overview;
  final double? voteAverage;
  final String? firstAirDate;
  final String? releaseDate;

  const TmdbSearchResult({
    required this.id,
    this.name,
    this.title,
    this.posterPath,
    this.backdropPath,
    this.overview,
    this.voteAverage,
    this.firstAirDate,
    this.releaseDate,
  });

  String get displayName => name ?? title ?? 'Unknown';
  String get posterUrl => TmdbClient.posterUrl(posterPath);
  String get backdropUrl => TmdbClient.backdropUrl(backdropPath);

  int? get year {
    final date = firstAirDate ?? releaseDate;
    if (date == null || date.length < 4) return null;
    return int.tryParse(date.substring(0, 4));
  }

  factory TmdbSearchResult.fromJson(Map<String, dynamic> json) {
    return TmdbSearchResult(
      id: json['id'] as int,
      name: json['name'] as String?,
      title: json['title'] as String?,
      posterPath: json['poster_path'] as String?,
      backdropPath: json['backdrop_path'] as String?,
      overview: json['overview'] as String?,
      voteAverage: (json['vote_average'] as num?)?.toDouble(),
      firstAirDate: json['first_air_date'] as String?,
      releaseDate: json['release_date'] as String?,
    );
  }
}
