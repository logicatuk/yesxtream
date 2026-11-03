import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/datasources/remote/tmdb_client.dart';
import '../../data/datasources/remote/xtream_client.dart';
import '../../data/services/playback_history_service.dart';
import '../providers/provider_manager.dart';

class MovieDetailScreen extends ConsumerStatefulWidget {
  final db.Channel movie;

  const MovieDetailScreen({super.key, required this.movie});

  @override
  ConsumerState<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends ConsumerState<MovieDetailScreen> {
  TmdbShowDetail? _tmdbDetail;
  Map<String, dynamic>? _xtreamInfo;
  bool _loading = true;
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.movie.favorite;
    _fetchDetails();
    _checkDbFavorite();
  }

  Future<void> _checkDbFavorite() async {
    try {
      final dbInstance = ref.read(databaseProvider);
      final ch = await (dbInstance.select(dbInstance.channels)
            ..where((t) => t.id.equals(widget.movie.id)))
          .getSingleOrNull();
      if (ch != null && mounted) {
        setState(() => _isFavorite = ch.favorite);
      }
    } catch (_) {}
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

  Future<void> _fetchDetails() async {
    Map<String, dynamic>? xtreamInfo;
    String? tmdbId;

    // 1. Fetch from Xtream Provider get_vod_info if available
    try {
      final dbInstance = ref.read(databaseProvider);
      final provider = await (dbInstance.select(dbInstance.providers)
            ..where((t) => t.id.equals(widget.movie.providerId)))
          .getSingleOrNull();

      String? baseUrl;
      String? username;
      String? password;
      String? vodId;

      if (provider != null && provider.type == 'xtream' && provider.url != null) {
        baseUrl = provider.url;
        username = provider.username;
        password = provider.password;
      } else if (provider?.url != null) {
        final parsed = parseXtreamFromM3uUrl(provider!.url!);
        if (parsed != null) {
          baseUrl = parsed.baseUrl;
          username = parsed.username;
          password = parsed.password;
        }
      }

      if (baseUrl == null) {
        final uri = Uri.tryParse(widget.movie.streamUrl);
        if (uri != null && uri.pathSegments.length >= 3) {
          final segs = uri.pathSegments;
          baseUrl = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
          username = segs[segs.length - 3];
          password = segs[segs.length - 2];
        }
      }

      if (widget.movie.id.contains('_vod_')) {
        vodId = widget.movie.id.split('_vod_').last;
      } else {
        final uri = Uri.tryParse(widget.movie.streamUrl);
        if (uri != null && uri.pathSegments.isNotEmpty) {
          vodId = uri.pathSegments.last.split('.').first;
        } else if (widget.movie.id.contains('_')) {
          vodId = widget.movie.id.split('_').last;
        } else {
          vodId = widget.movie.id;
        }
      }

      if (baseUrl != null && username != null && password != null && vodId != null && vodId.isNotEmpty) {
        final client = XtreamClient(
          baseUrl: baseUrl,
          username: username,
          password: password,
        );
        final res = await client.getVodInfo(vodId);
        client.dispose();
        if (res['info'] is Map<String, dynamic>) {
          xtreamInfo = res['info'] as Map<String, dynamic>;
          tmdbId = xtreamInfo['tmdb_id']?.toString();
        }
      }
    } catch (_) {}

    // 2. Fetch TMDB details
    TmdbShowDetail? tmdbDetail;
    try {
      if (tmdbId != null && tmdbId.isNotEmpty && tmdbId != '0') {
        final tid = int.tryParse(tmdbId);
        if (tid != null && tid > 0) {
          tmdbDetail = await TmdbClient.defaultClient.getMovieDetails(tid);
        }
      }
      if (tmdbDetail == null) {
        // Strip IPTV prefix like AMZ - , GR - , 4K-AR - , NETFLIX |
        var cleanName = widget.movie.name
            .replaceAll(RegExp(r'^(AMZ|GR|4K|UHD|HD|FHD|AR|EN|FR|NETFLIX|DISNEY|OSN|APPLE|HBO|WARNER)[\s\-_|:]+', caseSensitive: false), '')
            .replaceAll(RegExp(r'^[A-Z0-9\s]{2,8}[\s\-_|:]+', caseSensitive: false), '')
            .replaceAll(RegExp(r'\.(mp4|mkv|avi|mov)$', caseSensitive: false), '')
            .replaceAll(RegExp(r'\[.*?\]'), '')
            .trim();

        int? year;
        final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(cleanName);
        if (yearMatch != null) {
          year = int.tryParse(yearMatch.group(1)!);
          cleanName = cleanName.replaceAll(yearMatch.group(0)!, '').trim();
        }

        tmdbDetail = await TmdbClient.defaultClient.searchAndGetMovie(
          cleanName,
          year: year,
        );
        if (tmdbDetail == null && year != null) {
          tmdbDetail = await TmdbClient.defaultClient.searchAndGetMovie(cleanName);
        }
        if (tmdbDetail == null && cleanName.contains('+')) {
          tmdbDetail = await TmdbClient.defaultClient.searchAndGetMovie(cleanName.replaceAll('+', ' '));
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _xtreamInfo = xtreamInfo;
        _tmdbDetail = tmdbDetail;
        _loading = false;
      });
    }
  }

  String _formatDuration(int? minutes) {
    if (minutes == null || minutes <= 0) return '';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatTimeMs(int ms) {
    final dur = Duration(milliseconds: ms);
    final hours = dur.inHours;
    final minutes = dur.inMinutes.remainder(60);
    final seconds = dur.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _play({bool startOver = false}) {
    final history = ref.read(watchHistoryProvider);
    final item = history.where((h) => h.id == widget.movie.id).firstOrNull;
    final pos = startOver ? 0 : (item?.positionMs ?? 0);

    final poster = _tmdbDetail?.posterUrl ??
        _xtreamInfo?['movie_image'] as String? ??
        _xtreamInfo?['cover_big'] as String? ??
        widget.movie.tvgLogo;
    final backdrop = _tmdbDetail?.backdropUrl ??
        (_xtreamInfo?['backdrop_path'] is List && (_xtreamInfo!['backdrop_path'] as List).isNotEmpty
            ? (_xtreamInfo!['backdrop_path'] as List).first as String?
            : null);

    context.push('/vod-player', extra: {
      'id': widget.movie.id,
      'streamUrl': widget.movie.streamUrl,
      'streamType': 'vod',
      'title': widget.movie.name,
      'posterUrl': poster,
      'backdropUrl': backdrop,
      'initialPositionMs': pos,
    });
  }

  void _launchTrailer(String key) async {
    final url = key.startsWith('http') ? key : 'https://www.youtube.com/watch?v=$key';
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(watchHistoryProvider);
    final historyItem = history.where((h) => h.id == widget.movie.id).firstOrNull;
    final hasProgress = historyItem != null && historyItem.positionMs > 10000;

    final backdropUrl = _tmdbDetail?.backdropUrl ??
        (_xtreamInfo?['backdrop_path'] is List && (_xtreamInfo!['backdrop_path'] as List).isNotEmpty
            ? (_xtreamInfo!['backdrop_path'] as List).first as String?
            : null);

    final posterUrl = _tmdbDetail?.posterUrl.isNotEmpty == true
        ? _tmdbDetail!.posterUrl
        : (_xtreamInfo?['movie_image'] as String? ??
            _xtreamInfo?['cover_big'] as String? ??
            widget.movie.tvgLogo);

    // Overview / Synopsis
    final String synopsis = (_tmdbDetail?.overview != null && _tmdbDetail!.overview!.isNotEmpty)
        ? _tmdbDetail!.overview!
        : (_xtreamInfo?['plot'] as String? ??
            _xtreamInfo?['description'] as String? ??
            'No synopsis available.');

    // User Score / Rating
    String? userScore;
    if (_tmdbDetail?.voteAverage != null && _tmdbDetail!.voteAverage! > 0) {
      userScore = '${_tmdbDetail!.voteAverage!.toStringAsFixed(1)} / 10';
    } else if (_xtreamInfo?['rating'] != null && '${_xtreamInfo!['rating']}'.isNotEmpty) {
      userScore = '${_xtreamInfo!['rating']}';
    }

    // Release Date
    final releaseDate = _tmdbDetail?.releaseDate ??
        _xtreamInfo?['releasedate'] as String? ??
        _xtreamInfo?['release_date'] as String? ??
        (_tmdbDetail?.year != null ? '${_tmdbDetail!.year}' : null);

    // Duration
    final durationStr = _tmdbDetail?.runtime != null && _tmdbDetail!.runtime! > 0
        ? _formatDuration(_tmdbDetail?.runtime)
        : (_xtreamInfo?['duration'] as String? ?? '');

    // Genres
    final genres = _tmdbDetail?.genres.isNotEmpty == true
        ? _tmdbDetail!.genres
        : (_xtreamInfo?['genre'] as String? ?? '')
            .split(',')
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .toList();

    // Director
    final director = _tmdbDetail?.director ?? _xtreamInfo?['director'] as String?;

    // Cast list
    final castList = <String>[];
    if (_tmdbDetail?.cast.isNotEmpty == true) {
      castList.addAll(_tmdbDetail!.cast.take(8));
    } else {
      final rawCast = _xtreamInfo?['cast'] as String? ?? _xtreamInfo?['actors'] as String? ?? '';
      if (rawCast.isNotEmpty) {
        castList.addAll(rawCast
            .split(RegExp(r'[,;]|\s{2,}'))
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .take(8));
      }
    }

    // Trailer Key
    final trailerKey = _xtreamInfo?['youtube_trailer'] as String? ?? _tmdbDetail?.trailerKey;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // ── Backdrop Artwork ──
          if (backdropUrl != null && backdropUrl.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 480,
              child: ShaderMask(
                shaderCallback: (rect) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black, Colors.transparent],
                  ).createShader(Rect.fromLTRB(0, 0, rect.width, rect.height));
                },
                blendMode: BlendMode.dstIn,
                child: CachedNetworkImage(
                  imageUrl: backdropUrl,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),

          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0xFF0A0A0F),
                  ],
                  stops: [0.15, 0.65],
                ),
              ),
            ),
          ),

          // ── Content ──
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Poster Card
                        Container(
                          width: 220,
                          height: 330,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: posterUrl != null && posterUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: posterUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    color: const Color(0xFF1E1E2E),
                                    child: const Icon(Icons.movie, size: 64, color: Colors.white24),
                                  ),
                                )
                              : Container(
                                  color: const Color(0xFF1E1E2E),
                                  child: const Icon(Icons.movie, size: 64, color: Colors.white24),
                                ),
                        ),
                        const SizedBox(width: 36),

                        // Movie Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.movie.name,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Badges: User Score, Year, Duration, Genres
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (userScore != null && userScore.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF39C12).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFF39C12), width: 1),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star_rounded, size: 16, color: Color(0xFFF39C12)),
                                          const SizedBox(width: 4),
                                          Text(
                                            userScore,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFF39C12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (releaseDate != null && releaseDate.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: Text(
                                        releaseDate,
                                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                                      ),
                                    ),
                                  if (durationStr.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: Text(
                                        durationStr,
                                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                                      ),
                                    ),
                                  for (final g in genres.take(3))
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF6C5CE7).withValues(alpha: 0.5)),
                                      ),
                                      child: Text(
                                        g,
                                        style: const TextStyle(fontSize: 12, color: Color(0xFFA29BFE)),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 20),

                              // Overview / Synopsis
                              const Text(
                                'Overview',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                synopsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.5,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Director
                              if (director != null && director.isNotEmpty) ...[
                                Row(
                                  children: [
                                    const Text('Director: ',
                                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 13)),
                                    Text(director, style: const TextStyle(color: Colors.white, fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                              ],

                              // Cast section
                              if (castList.isNotEmpty) ...[
                                const Text(
                                  'Cast',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    for (final actor in castList)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF161528),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF26243A)),
                                        ),
                                        child: Text(
                                          actor,
                                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                              ],

                              // Progress bar if saved progress exists
                              if (hasProgress) ...[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: historyItem.progressFraction,
                                        backgroundColor: Colors.white12,
                                        valueColor: const AlwaysStoppedAnimation(Color(0xFF6C5CE7)),
                                        minHeight: 6,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Resume at ${_formatTimeMs(historyItem.positionMs)} / ${_formatTimeMs(historyItem.durationMs)}',
                                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                              ],

                              // Action Buttons: Play / Resume, Trailer, Favorite
                              Wrap(
                                spacing: 14,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () => _play(),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF6C5CE7),
                                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                                    label: Text(
                                      hasProgress ? 'Resume' : 'Play',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                    ),
                                  ),

                                  if (trailerKey != null && trailerKey.isNotEmpty)
                                    OutlinedButton.icon(
                                      onPressed: () => _launchTrailer(trailerKey!),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Color(0xFFE74C3C)),
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      icon: const Icon(Icons.play_circle_outline_rounded, color: Color(0xFFE74C3C), size: 20),
                                      label: const Text(
                                        'Trailer',
                                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                      ),
                                    ),

                                  OutlinedButton.icon(
                                    onPressed: _toggleFavorite,
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: _isFavorite
                                            ? const Color(0xFFFFD32A).withValues(alpha: 0.8)
                                            : const Color(0xFF2E2C42),
                                      ),
                                      backgroundColor: _isFavorite
                                          ? const Color(0xFFFFD32A).withValues(alpha: 0.12)
                                          : Colors.transparent,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: Icon(
                                      _isFavorite
                                          ? Icons.star_rounded
                                          : Icons.star_outline_rounded,
                                      color: _isFavorite
                                          ? const Color(0xFFFFD32A)
                                          : Colors.white70,
                                    ),
                                    label: Text(
                                      _isFavorite ? 'Favorited' : 'Favorite',
                                      style: TextStyle(
                                        color: _isFavorite ? const Color(0xFFFFD32A) : Colors.white,
                                        fontSize: 14,
                                        fontWeight: _isFavorite ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
