import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchHistoryItem {
  final String id;
  final String title;
  final String? posterUrl;
  final String? backdropUrl;
  final String streamUrl;
  final String streamType; // 'live', 'vod', 'series'
  final int positionMs;
  final int durationMs;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final DateTime lastWatched;

  const WatchHistoryItem({
    required this.id,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    required this.streamUrl,
    required this.streamType,
    required this.positionMs,
    required this.durationMs,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    required this.lastWatched,
  });

  double get progressFraction {
    if (durationMs <= 0) return 0.0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'posterUrl': posterUrl,
        'backdropUrl': backdropUrl,
        'streamUrl': streamUrl,
        'streamType': streamType,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'seriesName': seriesName,
        'seasonNumber': seasonNumber,
        'episodeNumber': episodeNumber,
        'lastWatched': lastWatched.toIso8601String(),
      };

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) =>
      WatchHistoryItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        posterUrl: json['posterUrl'] as String?,
        backdropUrl: json['backdropUrl'] as String?,
        streamUrl: json['streamUrl'] as String? ?? '',
        streamType: json['streamType'] as String? ?? 'vod',
        positionMs: json['positionMs'] as int? ?? 0,
        durationMs: json['durationMs'] as int? ?? 0,
        seriesName: json['seriesName'] as String?,
        seasonNumber: json['seasonNumber'] as int?,
        episodeNumber: json['episodeNumber'] as int?,
        lastWatched: DateTime.tryParse(json['lastWatched'] as String? ?? '') ??
            DateTime.now(),
      );
}

class WatchHistoryNotifier extends StateNotifier<List<WatchHistoryItem>> {
  WatchHistoryNotifier() : super(const []) {
    _load();
  }

  static const _kHistoryKey = 'watch_history_items_v1';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistoryKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      state = list
          .map((e) => WatchHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => b.lastWatched.compareTo(a.lastWatched));
    } catch (_) {}
  }

  Future<void> saveProgress({
    required String id,
    required String title,
    String? posterUrl,
    String? backdropUrl,
    required String streamUrl,
    required String streamType,
    required int positionMs,
    required int durationMs,
    String? seriesName,
    int? seasonNumber,
    int? episodeNumber,
  }) async {
    final item = WatchHistoryItem(
      id: id,
      title: title,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      streamUrl: streamUrl,
      streamType: streamType,
      positionMs: positionMs,
      durationMs: durationMs,
      seriesName: seriesName,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      lastWatched: DateTime.now(),
    );

    final filtered = state.where((e) => e.id != id).toList();
    // Keep up to 50 items
    state = [item, ...filtered].take(50).toList();
    await _persist();
  }

  Future<void> removeItem(String id) async {
    state = state.where((e) => e.id != id).toList();
    await _persist();
  }

  Future<void> removeHistory(String id) => removeItem(id);

  Future<void> clearAll() async {
    state = const [];
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = state.map((e) => e.toJson()).toList();
    await prefs.setString(_kHistoryKey, jsonEncode(jsonList));
  }
}

final watchHistoryProvider =
    StateNotifierProvider<WatchHistoryNotifier, List<WatchHistoryItem>>((ref) {
  return WatchHistoryNotifier();
});
