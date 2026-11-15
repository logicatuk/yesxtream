import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform_info.dart';
import '../../core/tv_back_handler.dart';
import '../../data/datasources/local/database.dart' as db;
import '../providers/provider_manager.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  int _tabIndex = 0;
  List<db.Channel> _live = [];
  List<db.Channel> _movies = [];
  List<db.Channel> _series = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final database = ref.read(databaseProvider);
      final all = await database.getFavoriteChannels();
      if (!mounted) return;
      setState(() {
        _live = all.where((c) => c.streamType == 'live').toList();
        _movies = all.where((c) => c.streamType == 'vod').toList();
        _series = all.where((c) => c.streamType == 'series').toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeFavorite(String channelId) async {
    final database = ref.read(databaseProvider);
    await database.toggleFavorite(channelId);
    await _load();
  }

  void _playLive(db.Channel ch) {
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
          'groupTitle': ch.groupTitle,
        }
      ],
      'currentIndex': 0,
    });
  }

  void _openMovie(db.Channel movie) {
    context.push('/movies/detail', extra: movie);
  }

  void _openSeries(db.Channel series) {
    context.push('/series/detail', extra: series);
  }

  @override
  Widget build(BuildContext context) {
    final isTV = PlatformInfo.isTV;
    final tabs = [
      ('Channels', _live.length, Icons.live_tv_rounded),
      ('Movies', _movies.length, Icons.movie_rounded),
      ('Series', _series.length, Icons.tv_rounded),
    ];

    return TvBackHandler(
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isTV ? 28 : 16, isTV ? 20 : 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 26),
                  const SizedBox(width: 10),
                  Text(
                    'Favorites',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: isTV ? 24 : 20,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: List.generate(tabs.length, (i) {
                  final tab = tabs[i];
                  final selected = _tabIndex == i;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FocusableActionDetector(
                        autofocus: isTV && i == 0,
                        actions: {
                          ActivateIntent: CallbackAction<ActivateIntent>(
                            onInvoke: (_) {
                              setState(() => _tabIndex = i);
                              return null;
                            },
                          ),
                        },
                        child: Builder(
                          builder: (ctx) {
                            final focused = Focus.of(ctx).hasFocus;
                            return InkWell(
                              onTap: () => setState(() => _tabIndex = i),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? const Color(0xFF6C5CE7).withValues(alpha: 0.35)
                                      : const Color(0xFF161528),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: focused
                                        ? Colors.white
                                        : (selected
                                            ? const Color(0xFF6C5CE7)
                                            : const Color(0xFF2A2840)),
                                    width: focused ? 2.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(tab.$3, color: Colors.white70, size: 18),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${tab.$1} (${tab.$2})',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight:
                                            selected ? FontWeight.bold : FontWeight.w500,
                                        fontSize: isTV ? 14 : 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
                    )
                  : switch (_tabIndex) {
                      0 => _buildLiveList(),
                      1 => _buildVodGrid(_movies, isMovie: true),
                      _ => _buildVodGrid(_series, isMovie: false),
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveList() {
    if (_live.isEmpty) {
      return _empty('No favorite channels added yet');
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _live.length,
      itemBuilder: (context, index) {
        final ch = _live[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: FocusableActionDetector(
            autofocus: PlatformInfo.isTV && index == 0,
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _playLive(ch);
                  return null;
                },
              ),
            },
            child: Builder(
              builder: (ctx) {
                final focused = Focus.of(ctx).hasFocus;
                return InkWell(
                  onTap: () => _playLive(ch),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: focused
                          ? const Color(0xFF6C5CE7).withValues(alpha: 0.28)
                          : const Color(0xFF161524),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: focused ? Colors.white : const Color(0xFF2A2840),
                        width: focused ? 2.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: ch.tvgLogo != null && ch.tvgLogo!.isNotEmpty
                              ? Image.network(
                                  ch.tvgLogo!,
                                  fit: BoxFit.contain,
                                  cacheWidth: 88,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.live_tv_rounded,
                                    color: Colors.white38,
                                  ),
                                )
                              : const Icon(Icons.live_tv_rounded, color: Colors.white38),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ch.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (ch.groupTitle != null)
                                Text(
                                  ch.groupTitle!,
                                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.star_rounded, color: Colors.amber),
                          onPressed: () => _removeFavorite(ch.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildVodGrid(List<db.Channel> items, {required bool isMovie}) {
    if (items.isEmpty) {
      return _empty(isMovie ? 'No favorite movies yet' : 'No favorite series yet');
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: PlatformInfo.isTV ? 220 : 180,
        childAspectRatio: 0.65,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return FocusableActionDetector(
          autofocus: PlatformInfo.isTV && index == 0,
          actions: {
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                if (isMovie) {
                  _openMovie(item);
                } else {
                  _openSeries(item);
                }
                return null;
              },
            ),
          },
          child: Builder(
            builder: (ctx) {
              final focused = Focus.of(ctx).hasFocus;
              return InkWell(
                onTap: () => isMovie ? _openMovie(item) : _openSeries(item),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF161524),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: focused ? Colors.white : const Color(0xFF2A2840),
                      width: focused ? 3 : 1,
                    ),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            item.tvgLogo != null && item.tvgLogo!.isNotEmpty
                                ? Image.network(
                                    item.tvgLogo!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 320,
                                    errorBuilder: (_, __, ___) => Center(
                                      child: Icon(
                                        isMovie ? Icons.movie_rounded : Icons.tv_rounded,
                                        color: Colors.white24,
                                        size: 36,
                                      ),
                                    ),
                                  )
                                : Center(
                                    child: Icon(
                                      isMovie ? Icons.movie_rounded : Icons.tv_rounded,
                                      color: Colors.white24,
                                      size: 36,
                                    ),
                                  ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                icon: const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                onPressed: () => _removeFavorite(item.id),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _empty(String message) {
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
