import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform_info.dart';
import '../../core/tv_back_handler.dart';
import '../../data/services/playback_history_service.dart';

class ContinueWatchingScreen extends ConsumerWidget {
  const ContinueWatchingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(watchHistoryProvider);
    final isTV = PlatformInfo.isTV;

    return TvBackHandler(
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(isTV ? 28 : 16, isTV ? 20 : 12, 12, 8),
              child: Row(
                children: [
                  Text(
                    'Continue Watching',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: isTV ? 24 : 20,
                    ),
                  ),
                  const Spacer(),
                  if (history.isNotEmpty)
                    FocusableActionDetector(
                      actions: {
                        ActivateIntent: CallbackAction<ActivateIntent>(
                          onInvoke: (_) {
                            _confirmClearHistory(context, ref);
                            return null;
                          },
                        ),
                      },
                      child: Builder(
                        builder: (ctx) {
                          final focused = Focus.of(ctx).hasFocus;
                          return InkWell(
                            onTap: () => _confirmClearHistory(context, ref),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: focused ? Colors.white : Colors.white24,
                                  width: focused ? 2 : 1,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.delete_sweep_rounded, color: Colors.white54, size: 18),
                                  SizedBox(width: 6),
                                  Text('Clear All', style: TextStyle(color: Colors.white54)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: history.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_rounded, size: 64, color: Colors.white24),
                          SizedBox(height: 16),
                          Text(
                            'No watch history yet',
                            style: TextStyle(color: Colors.white38, fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: isTV ? 240 : 220,
                        childAspectRatio: 0.7,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        return _HistoryCard(
                          item: history[index],
                          autofocus: isTV && index == 0,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmClearHistory(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A192A),
        title: const Text('Clear watch history?'),
        content: const Text('This removes all Continue Watching items.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            autofocus: true,
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
            onPressed: () {
              ref.read(watchHistoryProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends ConsumerWidget {
  final WatchHistoryItem item;
  final bool autofocus;

  const _HistoryCard({required this.item, this.autofocus = false});

  void _open(BuildContext context) {
    if (item.streamType == 'live') {
      context.push('/player', extra: {
        'streamUrl': item.streamUrl,
        'channelName': item.title,
      });
    } else {
      context.push('/vod-player', extra: {
        'id': item.id,
        'title': item.title,
        'streamUrl': item.streamUrl,
        'streamType': item.streamType,
        'seriesName': item.seriesName,
        'seasonNumber': item.seasonNumber,
        'episodeNumber': item.episodeNumber,
        'posterUrl': item.posterUrl,
        'backdropUrl': item.backdropUrl,
        'initialPositionMs': item.positionMs,
      });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = item.progressFraction;

    return FocusableActionDetector(
      autofocus: autofocus,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _open(context);
            return null;
          },
        ),
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return InkWell(
            onTap: () => _open(context),
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
                        item.posterUrl != null || item.backdropUrl != null
                            ? Image.network(
                                item.posterUrl ?? item.backdropUrl!,
                                fit: BoxFit.cover,
                                cacheWidth: 320,
                                errorBuilder: (_, __, ___) => Container(
                                  color: const Color(0xFF222035),
                                  child: const Icon(
                                    Icons.movie_rounded,
                                    color: Colors.white24,
                                    size: 40,
                                  ),
                                ),
                              )
                            : Container(
                                color: const Color(0xFF222035),
                                child: const Icon(
                                  Icons.movie_rounded,
                                  color: Colors.white24,
                                  size: 40,
                                ),
                              ),
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87],
                                stops: [0.6, 1.0],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: IconButton(
                            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                            onPressed: () {
                              ref.read(watchHistoryProvider.notifier).removeHistory(item.id);
                            },
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white24,
                            color: const Color(0xFF6C5CE7),
                            minHeight: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.seriesName ?? item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (item.seasonNumber != null && item.episodeNumber != null)
                              Text(
                                'S${item.seasonNumber} • E${item.episodeNumber}',
                                style: const TextStyle(color: Color(0xFFA29BFE), fontSize: 11),
                              )
                            else
                              Text(
                                item.streamType.toUpperCase(),
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            Text(
                              '${(progress * 100).toInt()}%',
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
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
}
