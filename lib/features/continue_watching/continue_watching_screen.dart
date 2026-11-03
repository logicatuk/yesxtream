import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/services/playback_history_service.dart';

class ContinueWatchingScreen extends ConsumerWidget {
  const ContinueWatchingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(watchHistoryProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D14),
        elevation: 0,
        title: const Text(
          'Continue Watching',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          if (history.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                _confirmClearHistory(context, ref);
              },
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white54, size: 18),
              label: const Text('Clear All', style: TextStyle(color: Colors.white54)),
            ),
        ],
      ),
      body: history.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_rounded, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text('No watch history yet',
                      style: TextStyle(color: Colors.white38, fontSize: 16)),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                childAspectRatio: 0.7,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final item = history[index];
                return _buildHistoryCard(context, ref, item);
              },
            ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, WidgetRef ref, WatchHistoryItem item) {
    final progress = item.progressFraction;

    return Card(
      color: const Color(0xFF161524),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
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
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster / Backdrop with Progress Bar
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.posterUrl != null || item.backdropUrl != null
                      ? Image.network(
                          item.posterUrl ?? item.backdropUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFF222035),
                            child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 40),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF222035),
                          child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 40),
                        ),

                  // Gradient for contrast
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

                  // Remove button
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                      tooltip: 'Remove from history',
                      onPressed: () {
                        ref.read(watchHistoryProvider.notifier).removeHistory(item.id);
                      },
                    ),
                  ),

                  // Progress Bar at bottom of poster
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

            // Information
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
  }

  void _confirmClearHistory(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A192A),
        title: const Text('Clear Watch History?'),
        content: const Text(
          'This will remove all continue watching progress from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(watchHistoryProvider.notifier).clearAll();
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
