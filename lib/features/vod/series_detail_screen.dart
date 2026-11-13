import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/tv_back_handler.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/datasources/remote/tmdb_client.dart';
import '../../data/datasources/remote/xtream_client.dart';
import '../../data/services/app_settings.dart';
import '../../data/services/playback_history_service.dart';
import '../player/player_service.dart';
import '../providers/provider_manager.dart';

class SeriesDetailScreen extends ConsumerStatefulWidget {
  final db.Channel series;

  const SeriesDetailScreen({super.key, required this.series});

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  TmdbShowDetail? _tmdbDetail;
  Map<String, dynamic>? _xtreamSeriesInfo;
  Map<int, List<TmdbEpisode>> _xtreamFallbackEpisodes = {};
  int _selectedSeason = 1;
  TmdbSeasonDetail? _seasonDetail;
  bool _loading = true;

  // Selected episode for compact panel
  TmdbEpisode? _selectedEpisode;
  final Map<String, String> _episodeStreamUrls = {};
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    try {
      ref.read(playerServiceProvider).stop();
    } catch (_) {}
    _isFavorite = widget.series.favorite;
    _fetchDetails();
    _checkDbFavorite();
  }

  Future<void> _checkDbFavorite() async {
    try {
      final dbInstance = ref.read(databaseProvider);
      final ch = await (dbInstance.select(dbInstance.channels)
            ..where((t) => t.id.equals(widget.series.id)))
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
            ..where((t) => t.id.equals(widget.series.id)))
          .write(db.ChannelsCompanion(
        favorite: Value(next),
      ));
    } catch (_) {}
  }

  Future<void> _fetchDetails() async {
    Map<String, dynamic>? xtreamInfo;
    final Map<int, List<TmdbEpisode>> fallbackEpisodes = {};
    String? tmdbId;

    // 1. Resolve episode stream URLs from Xtream Codes provider if applicable
    try {
      final dbInstance = ref.read(databaseProvider);
      final provider = await (dbInstance.select(dbInstance.providers)
            ..where((t) => t.id.equals(widget.series.providerId)))
          .getSingleOrNull();

      String? baseUrl;
      String? username;
      String? password;
      String? seriesId;

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
        final uri = Uri.tryParse(widget.series.streamUrl);
        if (uri != null && uri.pathSegments.length >= 3) {
          final segs = uri.pathSegments;
          baseUrl = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
          username = segs[segs.length - 3];
          password = segs[segs.length - 2];
        }
      }

      if (widget.series.id.contains('_series_')) {
        seriesId = widget.series.id.split('_series_').last;
      } else {
        final uri = Uri.tryParse(widget.series.streamUrl);
        if (uri != null && uri.pathSegments.isNotEmpty) {
          seriesId = uri.pathSegments.last.split('.').first;
        } else if (widget.series.id.contains('_')) {
          seriesId = widget.series.id.split('_').last;
        } else {
          seriesId = widget.series.id;
        }
      }

      if (baseUrl != null && username != null && password != null && seriesId.isNotEmpty) {
        final client = XtreamClient(
          baseUrl: baseUrl,
          username: username,
          password: password,
        );
        final info = await client.getSeriesInfo(seriesId);
        client.dispose();

        if (info['info'] is Map<String, dynamic>) {
          xtreamInfo = info['info'] as Map<String, dynamic>;
          tmdbId = xtreamInfo['tmdb_id']?.toString();
        }

        final episodesMap = info['episodes'];
        if (episodesMap is Map) {
          final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
          episodesMap.forEach((seasonKey, epList) {
            final sNum = int.tryParse('$seasonKey') ?? 1;
            final seasonEps = <TmdbEpisode>[];
            if (epList is List) {
              for (int idx = 0; idx < epList.length; idx++) {
                final ep = epList[idx];
                if (ep is Map) {
                  final eNum = ep['episode_num'] is int
                      ? ep['episode_num'] as int
                      : int.tryParse('${ep['episode_num']}') ?? (idx + 1);
                  final epId = ep['id'];
                  final ext = ep['container_extension'] as String? ?? 'mp4';
                  final title = ep['title'] as String? ?? 'Episode $eNum';
                  final streamUrl = '$cleanBase/series/$username/$password/$epId.$ext';
                  _episodeStreamUrls['${sNum}_$eNum'] = streamUrl;
                  _episodeStreamUrls['${sNum}_${idx + 1}'] = streamUrl;
                  if (sNum == 1) {
                    _episodeStreamUrls['$eNum'] = streamUrl;
                    _episodeStreamUrls['${idx + 1}'] = streamUrl;
                  }
                  if (epId != null) {
                    _episodeStreamUrls['id_$epId'] = streamUrl;
                  }

                  final epInfo = ep['info'] is Map ? ep['info'] as Map : null;
                  final epImage = (epInfo?['movie_image'] as String?) ??
                      (ep['movie_image'] as String?) ??
                      (epInfo?['still_path'] as String?) ??
                      (epInfo?['cover_big'] as String?) ??
                      (ep['cover'] as String?);

                  seasonEps.add(TmdbEpisode(
                    id: int.tryParse('$epId'),
                    episodeNumber: eNum,
                    seasonNumber: sNum,
                    name: title,
                    overview: epInfo != null ? epInfo['plot'] as String? : null,
                    stillPath: (epImage != null && epImage.isNotEmpty) ? epImage : null,
                  ));
                }
              }
            }
            if (seasonEps.isNotEmpty) {
              fallbackEpisodes[sNum] = seasonEps;
            }
          });
        }
      }
    } catch (_) {}

    // 2. Fetch TMDB show & season details for artwork, overview, and cast
    TmdbShowDetail? tmdbDetail;
    TmdbSeasonDetail? seasonDetail;

    try {
      if (tmdbId != null && tmdbId.isNotEmpty && tmdbId != '0') {
        final tid = int.tryParse(tmdbId);
        if (tid != null && tid > 0) {
          tmdbDetail = await TmdbClient.defaultClient.getTvShow(tid);
        }
      }

      if (tmdbDetail == null) {
        var cleanName = widget.series.name
            .replaceAll(RegExp(r'^(AMZ|GR|4K|UHD|HD|FHD|AR|EN|FR|NETFLIX|DISNEY|OSN|APPLE|HBO|WARNER)[\s\-_|:]+', caseSensitive: false), '')
            .replaceAll(RegExp(r'^[A-Z0-9\s]{2,8}[\s\-_|:]+', caseSensitive: false), '')
            .replaceAll(RegExp(r'\[.*?\]'), '')
            .replaceAll(RegExp(r'\(.*?\)'), '')
            .trim();

        tmdbDetail = await TmdbClient.defaultClient.searchAndGetTv(cleanName);
        if (tmdbDetail == null && cleanName.contains('+')) {
          tmdbDetail = await TmdbClient.defaultClient.searchAndGetTv(cleanName.replaceAll('+', ' '));
        }
      }

      if (tmdbDetail != null) {
        seasonDetail = await TmdbClient.defaultClient.getCachedTvSeason(
          tmdbDetail.id,
          _selectedSeason,
        );
      }
    } catch (_) {}

    // 3. Fallback season detail from Xtream if TMDB had none
    if (seasonDetail == null && fallbackEpisodes.containsKey(_selectedSeason)) {
      seasonDetail = TmdbSeasonDetail(
        id: _selectedSeason,
        seasonNumber: _selectedSeason,
        name: 'Season $_selectedSeason',
        episodes: fallbackEpisodes[_selectedSeason] ?? [],
      );
    }

    if (mounted) {
      setState(() {
        _xtreamSeriesInfo = xtreamInfo;
        _xtreamFallbackEpisodes = fallbackEpisodes;
        _tmdbDetail = tmdbDetail;
        _seasonDetail = seasonDetail;
        _loading = false;
      });
    }
  }

  Future<void> _changeSeason(int seasonNum) async {
    setState(() {
      _selectedSeason = seasonNum;
      _selectedEpisode = null;
    });

    TmdbSeasonDetail? season;
    if (_tmdbDetail != null) {
      season = await TmdbClient.defaultClient.getCachedTvSeason(
        _tmdbDetail!.id,
        seasonNum,
      );
    }
    if ((season == null || season.episodes.isEmpty) && _xtreamFallbackEpisodes.containsKey(seasonNum)) {
      season = TmdbSeasonDetail(
        id: seasonNum,
        seasonNumber: seasonNum,
        name: 'Season $seasonNum',
        episodes: _xtreamFallbackEpisodes[seasonNum] ?? [],
      );
    }
    if (mounted) {
      setState(() => _seasonDetail = season);
    }
  }

  void _playEpisode(TmdbEpisode ep, {bool startOver = false}) {
    final epId = '${widget.series.id}_s${ep.seasonNumber}_e${ep.episodeNumber}';
    final history = ref.read(watchHistoryProvider);
    final historyItem = history.where((h) => h.id == epId).firstOrNull;
    final pos = startOver ? 0 : (historyItem?.positionMs ?? 0);

    // Look up by season_episode, then by ep.id, then fallback to first available
    String? xtreamUrl = _episodeStreamUrls['${ep.seasonNumber}_${ep.episodeNumber}'];
    if (xtreamUrl == null && ep.id != null) {
      xtreamUrl = _episodeStreamUrls['id_${ep.id}'];
    }
    if (xtreamUrl == null) {
      xtreamUrl = _episodeStreamUrls['${ep.episodeNumber}'];
    }

    final url = (xtreamUrl != null && xtreamUrl.isNotEmpty)
        ? xtreamUrl
        : (widget.series.streamUrl.isNotEmpty
            ? widget.series.streamUrl
            : (_episodeStreamUrls.isNotEmpty ? _episodeStreamUrls.values.first : ''));

    // Prepare next episode if available in current season
    Map<String, dynamic>? nextEpData;
    if (_seasonDetail != null && _seasonDetail!.episodes.isNotEmpty) {
      final curIdx = _seasonDetail!.episodes.indexWhere(
        (e) => e.seasonNumber == ep.seasonNumber && e.episodeNumber == ep.episodeNumber,
      );
      if (curIdx >= 0 && curIdx < _seasonDetail!.episodes.length - 1) {
        final nextEp = _seasonDetail!.episodes[curIdx + 1];
        String? nextUrl = _episodeStreamUrls['${nextEp.seasonNumber}_${nextEp.episodeNumber}'];
        if (nextUrl == null && nextEp.id != null) {
          nextUrl = _episodeStreamUrls['id_${nextEp.id}'];
        }
        if (nextUrl == null) {
          nextUrl = _episodeStreamUrls['${nextEp.episodeNumber}'];
        }
        if (nextUrl != null && nextUrl.isNotEmpty) {
          nextEpData = {
            'id': '${widget.series.id}_s${nextEp.seasonNumber}_e${nextEp.episodeNumber}',
            'streamUrl': nextUrl,
            'title': '${widget.series.name} • S${nextEp.seasonNumber}E${nextEp.episodeNumber} - ${nextEp.name}',
            'posterUrl': nextEp.stillUrl.isNotEmpty ? nextEp.stillUrl : widget.series.tvgLogo,
            'backdropUrl': _tmdbDetail?.backdropUrl,
            'seriesName': widget.series.name,
            'seasonNumber': nextEp.seasonNumber,
            'episodeNumber': nextEp.episodeNumber,
            'episodeTitle': nextEp.name,
          };
        }
      }
    }

    context.push('/vod-player', extra: {
      'id': epId,
      'streamUrl': url,
      'streamType': 'series',
      'title': '${widget.series.name} • S${ep.seasonNumber}E${ep.episodeNumber} - ${ep.name}',
      'posterUrl': ep.stillUrl.isNotEmpty ? ep.stillUrl : widget.series.tvgLogo,
      'backdropUrl': _tmdbDetail?.backdropUrl,
      'initialPositionMs': pos,
      'seriesName': widget.series.name,
      'seasonNumber': ep.seasonNumber,
      'episodeNumber': ep.episodeNumber,
      'episodeTitle': ep.name,
      'nextEpisode': nextEpData,
    });
  }

  void _launchTrailer(String key) async {
    final cleanKey = key.trim();
    if (cleanKey.isEmpty) return;
    final url = cleanKey.startsWith('http') ? cleanKey : 'https://www.youtube.com/watch?v=$cleanKey';
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      try {
        await launchUrl(uri);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open trailer: $url')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0F),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7))),
      );
    }

    final backdropUrl = _tmdbDetail?.backdropUrl ??
        (_xtreamSeriesInfo?['backdrop_path'] is List && (_xtreamSeriesInfo!['backdrop_path'] as List).isNotEmpty
            ? (_xtreamSeriesInfo!['backdrop_path'] as List).first as String?
            : null);

    final posterUrl = _tmdbDetail?.posterUrl.isNotEmpty == true
        ? _tmdbDetail!.posterUrl
        : (_xtreamSeriesInfo?['cover'] as String? ?? widget.series.tvgLogo);

    final description = _tmdbDetail?.overview ??
        _xtreamSeriesInfo?['plot'] as String? ??
        'No synopsis available.';

    // User score / Rating
    String? userScore;
    if (_tmdbDetail?.voteAverage != null && _tmdbDetail!.voteAverage! > 0) {
      userScore = '${_tmdbDetail!.voteAverage!.toStringAsFixed(1)} / 10';
    } else if (_xtreamSeriesInfo?['rating'] != null && '${_xtreamSeriesInfo!['rating']}'.isNotEmpty) {
      userScore = '${_xtreamSeriesInfo!['rating']}';
    }

    // Release Date
    final releaseDate = _tmdbDetail?.releaseDate ??
        _xtreamSeriesInfo?['releaseDate'] as String? ??
        _xtreamSeriesInfo?['releasedate'] as String? ??
        (_tmdbDetail?.year != null ? '${_tmdbDetail!.year}' : null);

    // Director
    final director = _tmdbDetail?.director ?? _xtreamSeriesInfo?['director'] as String?;

    // Cast
    final castList = <String>[];
    if (_tmdbDetail?.cast.isNotEmpty == true) {
      castList.addAll(_tmdbDetail!.cast.take(8));
    } else {
      final rawCast = _xtreamSeriesInfo?['cast'] as String? ?? '';
      if (rawCast.isNotEmpty) {
        castList.addAll(rawCast
            .split(RegExp(r'[,;]|\s{2,}'))
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .take(8));
      }
    }

    // Trailer Key
    final trailerKey = _xtreamSeriesInfo?['youtube_trailer'] as String? ?? _tmdbDetail?.trailerKey;

    final availableSeasonsSet = <int>{};
    if (_tmdbDetail?.numberOfSeasons != null && _tmdbDetail!.numberOfSeasons! > 0) {
      availableSeasonsSet.addAll(List.generate(_tmdbDetail!.numberOfSeasons!, (i) => i + 1));
    }
    availableSeasonsSet.addAll(_xtreamFallbackEpisodes.keys);
    if (availableSeasonsSet.isEmpty) availableSeasonsSet.add(1);
    final sortedSeasons = availableSeasonsSet.toList()..sort();
    if (!sortedSeasons.contains(_selectedSeason)) {
      _selectedSeason = sortedSeasons.first;
    }
    final settings = ref.watch(appSettingsProvider);

    return TvBackHandler(
      fallbackRoute: '/series',
      child: Scaffold(
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
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),

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

          SafeArea(
            left: false,
            right: false,
            top: false,
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/series');
                      }
                    },
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;

                      Widget buildEpisodeCard(TmdbEpisode ep) {
                        final isSelected = ep.episodeNumber == _selectedEpisode?.episodeNumber;
                        final epStill = ep.stillUrl.isNotEmpty ? ep.stillUrl : null;
                        final thumbUrl = epStill ??
                            backdropUrl ??
                            posterUrl ??
                            (widget.series.tvgLogo != null && widget.series.tvgLogo!.isNotEmpty ? widget.series.tvgLogo : null);

                        return FocusableActionDetector(
                          actions: {
                            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
                              setState(() => _selectedEpisode = ep);
                              _playEpisode(ep);
                              return null;
                            }),
                            ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) {
                              setState(() => _selectedEpisode = ep);
                              _playEpisode(ep);
                              return null;
                            }),
                          },
                          child: Builder(
                            builder: (epCtx) {
                              final hasFocus = Focus.of(epCtx).hasFocus;
                              return InkWell(
                                onTap: () {
                                  setState(() => _selectedEpisode = ep);
                                  _playEpisode(ep);
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: hasFocus
                                        ? const Color(0xFF6C5CE7).withValues(alpha: 0.35)
                                        : (isSelected
                                            ? const Color(0xFF6C5CE7).withValues(alpha: 0.15)
                                            : const Color(0xFF141322)),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: hasFocus
                                          ? Colors.white
                                          : (isSelected
                                              ? const Color(0xFF6C5CE7)
                                              : const Color(0xFF22203A)),
                                      width: hasFocus ? 2.5 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      // Thumbnail with fallback
                                      Container(
                                        width: 86,
                                        height: 54,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(8),
                                          color: const Color(0xFF1E1E2E),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                  child: thumbUrl != null && thumbUrl.isNotEmpty
                                      ? Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            CachedNetworkImage(
                                              imageUrl: thumbUrl,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, _, _) => const Center(
                                                child: Icon(Icons.play_circle_outline,
                                                    color: Colors.white24, size: 24),
                                              ),
                                            ),
                                            Container(
                                              color: Colors.black.withValues(alpha: 0.25),
                                            ),
                                            const Center(
                                              child: Icon(Icons.play_circle_fill_rounded,
                                                  color: Colors.white70, size: 24),
                                            ),
                                          ],
                                        )
                                      : const Center(
                                          child: Icon(Icons.play_circle_outline,
                                              color: Colors.white24, size: 24),
                                        ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'E${ep.episodeNumber} • ${ep.name ?? "Episode ${ep.episodeNumber}"}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (ep.overview != null && ep.overview!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          ep.overview!,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton(
                                  icon: const Icon(Icons.play_circle_filled_rounded,
                                      size: 30, color: Color(0xFF6C5CE7)),
                                  onPressed: () => _playEpisode(ep),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  );
                }

                      Widget buildSeasonSelector() {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Text(
                                '${settings.tr('season')}: ',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E2E),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF2E2C42)),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: _selectedSeason,
                                    dropdownColor: const Color(0xFF1E1E2E),
                                    style: const TextStyle(color: Colors.white, fontSize: 14),
                                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
                                    items: sortedSeasons.map((s) {
                                      return DropdownMenuItem<int>(
                                        value: s,
                                        child: Text('${settings.tr('season')} $s'),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) _changeSeason(val);
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      Widget buildEpisodesList() {
                        if (_seasonDetail == null || _seasonDetail!.episodes.isEmpty) {
                          return Center(
                            child: Text(
                              settings.tr('no_episodes'),
                              style: const TextStyle(color: Colors.white38),
                            ),
                          );
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          itemCount: _seasonDetail!.episodes.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final ep = _seasonDetail!.episodes[index];
                            return buildEpisodeCard(ep);
                          },
                        );
                      }

                      Widget buildOverviewDetails({bool includePoster = false, bool isCompact = false}) {
                        return SingleChildScrollView(
                          padding: EdgeInsets.all(isCompact ? 12 : 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (includePoster) ...[
                                Container(
                                  width: isCompact ? 105 : 160,
                                  height: isCompact ? 150 : 235,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: posterUrl != null && posterUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: posterUrl,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, _, _) =>
                                              const Icon(Icons.tv, size: 60, color: Colors.white24),
                                        )
                                      : const Icon(Icons.tv, size: 60, color: Colors.white24),
                                ),
                                SizedBox(height: isCompact ? 10 : 16),
                                Text(
                                  widget.series.name,
                                  style: TextStyle(
                                    fontSize: isCompact ? 18 : 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],

                              // Badges
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (userScore != null && userScore.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF39C12).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFF39C12)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF39C12)),
                                          const SizedBox(width: 4),
                                          Text(
                                            userScore,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFF39C12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (releaseDate != null && releaseDate.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: Text(
                                        releaseDate,
                                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              Text(
                                description,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 14),

                              if (director != null && director.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Text('${settings.tr('director')}: ',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 12)),
                                    Expanded(
                                      child: Text(director, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                              ],

                              if (castList.isNotEmpty) ...[
                                Text(
                                  settings.tr('cast'),
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    for (final a in castList)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF161528),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFF26243A)),
                                        ),
                                        child: Text(a, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],

                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    autofocus: true,
                                    onPressed: () {
                                      if (_seasonDetail != null && _seasonDetail!.episodes.isNotEmpty) {
                                        _playEpisode(_seasonDetail!.episodes.first);
                                      }
                                    },
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF6C5CE7),
                                    ).copyWith(
                                      side: WidgetStateProperty.resolveWith(
                                        (states) => states.contains(WidgetState.focused)
                                            ? const BorderSide(color: Colors.white, width: 2.5)
                                            : null,
                                      ),
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                                    label: Text(settings.tr('play_episode')),
                                  ),
                                  if (trailerKey != null && trailerKey.isNotEmpty)
                                    OutlinedButton.icon(
                                      onPressed: () => _launchTrailer(trailerKey),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Color(0xFFE74C3C)),
                                      ),
                                      icon: const Icon(Icons.play_circle_outline_rounded, color: Color(0xFFE74C3C), size: 18),
                                      label: Text(settings.tr('trailer'), style: const TextStyle(color: Colors.white, fontSize: 13)),
                                    ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: _isFavorite
                                          ? const Color(0xFFFFD32A).withValues(alpha: 0.15)
                                          : const Color(0xFF1E1E2E),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _isFavorite ? const Color(0xFFFFD32A) : Colors.white24,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: IconButton(
                                      tooltip: _isFavorite ? settings.tr('remove_favorites') : settings.tr('add_favorites'),
                                      icon: Icon(
                                        _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                                        color: _isFavorite ? const Color(0xFFFFD32A) : Colors.white,
                                        size: 22,
                                      ),
                                      onPressed: _toggleFavorite,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }

                      // ── Portrait Mobile / Foldable Responsive Layout ──
                      if (isPortrait) {
                        final epCount = _seasonDetail?.episodes.length ?? 0;

                        return DefaultTabController(
                          length: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Compact Series Header Banner
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 72,
                                      height: 104,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.5),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: posterUrl != null && posterUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: posterUrl,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, _, _) =>
                                                  const Icon(Icons.tv, size: 32, color: Colors.white24),
                                            )
                                          : const Icon(Icons.tv, size: 32, color: Colors.white24),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.series.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            children: [
                                              if (userScore != null && userScore.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFF39C12).withValues(alpha: 0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: const Color(0xFFF39C12)),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF39C12)),
                                                      const SizedBox(width: 3),
                                                      Text(userScore, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF39C12))),
                                                    ],
                                                  ),
                                                ),
                                              if (releaseDate != null && releaseDate.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withValues(alpha: 0.08),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.white24),
                                                  ),
                                                  child: Text(releaseDate, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              FilledButton.icon(
                                                autofocus: true,
                                                onPressed: () {
                                                  if (_seasonDetail != null && _seasonDetail!.episodes.isNotEmpty) {
                                                    _playEpisode(_seasonDetail!.episodes.first);
                                                  }
                                                },
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: const Color(0xFF6C5CE7),
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ).copyWith(
                                                  side: WidgetStateProperty.resolveWith(
                                                    (states) => states.contains(WidgetState.focused)
                                                        ? const BorderSide(color: Colors.white, width: 2.5)
                                                        : null,
                                                  ),
                                                ),
                                                icon: const Icon(Icons.play_arrow_rounded, size: 16),
                                                label: Text(settings.tr('play_episode'), style: const TextStyle(fontSize: 12)),
                                              ),
                                              if (trailerKey != null && trailerKey.isNotEmpty) ...[
                                                const SizedBox(width: 8),
                                                OutlinedButton.icon(
                                                  onPressed: () => _launchTrailer(trailerKey),
                                                  style: OutlinedButton.styleFrom(
                                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                    minimumSize: Size.zero,
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ).copyWith(
                                                    side: WidgetStateProperty.resolveWith(
                                                      (states) => states.contains(WidgetState.focused)
                                                          ? const BorderSide(color: Colors.white, width: 2.5)
                                                          : const BorderSide(color: Color(0xFFE74C3C)),
                                                    ),
                                                  ),
                                                  icon: const Icon(Icons.play_circle_outline_rounded, color: Color(0xFFE74C3C), size: 16),
                                                  label: Text(settings.tr('trailer'), style: const TextStyle(color: Colors.white, fontSize: 12)),
                                                ),
                                              ],
                                              const SizedBox(width: 8),
                                              OutlinedButton.icon(
                                                onPressed: _toggleFavorite,
                                                style: OutlinedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ).copyWith(
                                                  side: WidgetStateProperty.resolveWith(
                                                    (states) => states.contains(WidgetState.focused)
                                                        ? const BorderSide(color: Colors.white, width: 2.5)
                                                        : BorderSide(
                                                            color: _isFavorite
                                                                ? const Color(0xFFFFD32A).withValues(alpha: 0.8)
                                                                : const Color(0xFF2E2C42),
                                                          ),
                                                  ),
                                                ),
                                                icon: Icon(
                                                  _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                                                  color: _isFavorite ? const Color(0xFFFFD32A) : Colors.white70,
                                                  size: 16,
                                                ),
                                                label: Text(
                                                  _isFavorite ? 'Favorited' : 'Favorite',
                                                  style: TextStyle(
                                                    color: _isFavorite ? const Color(0xFFFFD32A) : Colors.white,
                                                    fontSize: 12,
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
                              const SizedBox(height: 8),

                              // Tabs: Episodes vs Details
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: Color(0xFF26243A), width: 1),
                                  ),
                                ),
                                child: TabBar(
                                  indicatorColor: const Color(0xFF6C5CE7),
                                  indicatorWeight: 3,
                                  labelColor: Colors.white,
                                  unselectedLabelColor: Colors.white54,
                                  labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  tabs: [
                                    Tab(text: 'Episodes ($epCount)'),
                                    const Tab(text: 'Details & Cast'),
                                  ],
                                ),
                              ),

                              Expanded(
                                child: TabBarView(
                                  children: [
                                    // Tab 1: Episodes (Full width)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        buildSeasonSelector(),
                                        Expanded(child: buildEpisodesList()),
                                      ],
                                    ),
                                    // Tab 2: Overview & Cast (Full width)
                                    buildOverviewDetails(includePoster: false),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      // ── Landscape Layout (Side-by-Side: Phones, Tablets, Desktop TV) ──
                      // Left: Overview with Poster (width scaled nicely)
                      // Right: Full-height Season Selector & Episodes with 100% scrollable freedom!
                      final isShortLandscape = constraints.maxHeight < 520;
                      final leftWidth = isShortLandscape
                          ? (constraints.maxWidth < 750 ? 240.0 : 280.0)
                          : (constraints.maxWidth < 950 ? 300.0 : 360.0);

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Overview
                          SizedBox(
                            width: leftWidth,
                            child: buildOverviewDetails(includePoster: true, isCompact: isShortLandscape),
                          ),
                          // Right Episodes (Fully scrollable)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                buildSeasonSelector(),
                                Expanded(child: buildEpisodesList()),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
}
