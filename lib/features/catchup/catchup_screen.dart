import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/datasources/local/database.dart' as db;
import '../../data/datasources/remote/xtream_client.dart';
import '../playlists/playlist_providers.dart';
import '../providers/provider_manager.dart';

/// Dedicated Catch-up (TV Archive / Replay) Screen.
/// Filters and displays ONLY channels that have EPG / Catch-up availability,
/// with a 7-day past broadcast selector and 1-tap playback.
class CatchupScreen extends ConsumerStatefulWidget {
  final db.Channel? initialChannel;
  const CatchupScreen({super.key, this.initialChannel});

  @override
  ConsumerState<CatchupScreen> createState() => _CatchupScreenState();
}

class _CatchupScreenState extends ConsumerState<CatchupScreen> {
  String _searchQuery = '';
  db.Channel? _selectedChannel;
  int _selectedDayOffset = 0; // 0 = Today, 1 = Yesterday, 2 = 2 days ago, etc.
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedChannel = widget.initialChannel;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activePlaylist = ref.watch(activePlaylistProvider);
    final database = ref.watch(databaseProvider);

    if (activePlaylist == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0A0F),
        body: Center(
          child: Text(
            'No active playlist selected.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: FutureBuilder<List<db.Channel>>(
        future: _fetchCatchupChannels(database, activePlaylist.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
            );
          }

          final allCatchupChannels = snapshot.data ?? [];

          // Filter by search query
          final filteredChannels = _searchQuery.isEmpty
              ? allCatchupChannels
              : allCatchupChannels
                  .where((c) =>
                      c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      (c.groupTitle?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false))
                  .toList();

          // Auto-select first channel if none selected
          if (_selectedChannel == null && filteredChannels.isNotEmpty) {
            _selectedChannel = filteredChannels.first;
          } else if (_selectedChannel != null &&
              !filteredChannels.any((c) => c.id == _selectedChannel!.id)) {
            _selectedChannel = filteredChannels.isNotEmpty ? filteredChannels.first : null;
          }

          return Row(
            children: [
              // ── Left Column: Channel List (ONLY Catch-up channels) ──
              SizedBox(
                width: 380,
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0E0D1A),
                    border: Border(
                      right: BorderSide(color: Color(0xFF1E1E2E), width: 1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header & Counter
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C5CE7).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.replay_rounded,
                                color: Color(0xFF6C5CE7),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Catch-up Channels',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${filteredChannels.length} available with replay',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Search input
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'Search catch-up channels...',
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                            prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFF181728),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (val) => setState(() => _searchQuery = val),
                        ),
                      ),

                      const Divider(color: Color(0xFF1E1E2E), height: 12),

                      // Channels ListView
                      Expanded(
                        child: filteredChannels.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    _searchQuery.isEmpty
                                        ? 'No catch-up channels found.\nMake sure your IPTV provider supports TV Archive.'
                                        : 'No channels match "$_searchQuery"',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: filteredChannels.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(color: Color(0xFF151424), height: 1),
                                itemBuilder: (context, index) {
                                  final ch = filteredChannels[index];
                                  final isSelected = ch.id == _selectedChannel?.id;

                                  return Material(
                                    color: Colors.transparent,
                                    child: ListTile(
                                      dense: true,
                                      selected: isSelected,
                                      selectedTileColor:
                                          const Color(0xFF6C5CE7).withValues(alpha: 0.18),
                                      onTap: () => setState(() => _selectedChannel = ch),
                                      leading: Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF181728),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: ch.tvgLogo != null && ch.tvgLogo!.isNotEmpty
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(6),
                                                child: CachedNetworkImage(
                                                  imageUrl: ch.tvgLogo!,
                                                  fit: BoxFit.contain,
                                                  errorWidget: (_, _, _) => const Icon(
                                                    Icons.live_tv_rounded,
                                                    color: Colors.white38,
                                                    size: 18,
                                                  ),
                                                ),
                                              )
                                            : const Icon(
                                                Icons.live_tv_rounded,
                                                color: Colors.white38,
                                                size: 18,
                                              ),
                                      ),
                                      title: Text(
                                        ch.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : Colors.white70,
                                          fontSize: 13,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        ),
                                      ),
                                      subtitle: ch.groupTitle != null
                                          ? Text(
                                              ch.groupTitle!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 11,
                                              ),
                                            )
                                          : null,
                                      trailing: const Icon(
                                        Icons.history_rounded,
                                        color: Color(0xFF6C5CE7),
                                        size: 16,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Right Column: Past 7 Days Archive & Programmes ──
              Expanded(
                child: _selectedChannel == null
                    ? const Center(
                        child: Text(
                          'Select a channel to browse its catch-up archive',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : _buildChannelArchiveView(context, database, _selectedChannel!),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ── Channel Archive View (Day Selector + Programme Listings)
  // ─────────────────────────────────────────────────────────────
  Widget _buildChannelArchiveView(
    BuildContext context,
    db.AppDatabase database,
    db.Channel channel,
  ) {
    final targetDate = DateTime.now().subtract(Duration(days: _selectedDayOffset));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Channel Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            color: Color(0xFF0F0E1D),
            border: Border(
              bottom: BorderSide(color: Color(0xFF1E1E2E), width: 1),
            ),
          ),
          child: Row(
            children: [
              if (channel.tvgLogo != null && channel.tvgLogo!.isNotEmpty)
                Container(
                  width: 48,
                  height: 48,
                  margin: const EdgeInsets.only(right: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181728),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: channel.tvgLogo!,
                      fit: BoxFit.contain,
                      errorWidget: (_, _, _) => const Icon(
                        Icons.live_tv_rounded,
                        color: Colors.white38,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Category: ${channel.groupTitle ?? 'General'} • Replay archive available',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  context.push('/player', extra: {
                    'streamUrl': channel.streamUrl,
                    'channelName': channel.name,
                    'channelLogo': channel.tvgLogo,
                  });
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Watch Live'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ],
          ),
        ),

        // ── 7-Day Selector Pills ──
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF0A0A0F),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 8, // Today (0) + 7 days in the past
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final isSelected = _selectedDayOffset == index;
              final dayDate = DateTime.now().subtract(Duration(days: index));

              String label;
              if (index == 0) {
                label = "Today";
              } else if (index == 1) {
                label = "Yesterday";
              } else {
                label = DateFormat('E dd/MM').format(dayDate);
              }

              return InkWell(
                onTap: () => setState(() => _selectedDayOffset = index),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF6C5CE7) : const Color(0xFF161528),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFFA29BFE)
                          : const Color(0xFF26243A),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        const Divider(color: Color(0xFF1E1E2E), height: 1),

        // ── Programme Listings for Selected Day ──
        Expanded(
          child: FutureBuilder<List<db.EpgProgramme>>(
            future: _fetchDayProgrammes(database, channel, targetDate),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
                );
              }

              final programmes = snapshot.data ?? [];

              if (programmes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.event_busy_rounded,
                        color: Colors.white24,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No archive listings recorded for ${DateFormat('dd MMMM yyyy').format(targetDate)}.',
                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'You can watch the live channel or try another date.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 18),
                      OutlinedButton.icon(
                        onPressed: () {
                          context.push('/player', extra: {
                            'streamUrl': channel.streamUrl,
                            'channelName': channel.name,
                            'channelLogo': channel.tvgLogo,
                          });
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 16),
                        label: const Text('Play Live Stream'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF6C5CE7),
                          side: const BorderSide(color: Color(0xFF6C5CE7)),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: programmes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final prog = programmes[index];
                  final startTimeStr = DateFormat('HH:mm').format(prog.start);
                  final stopTimeStr = DateFormat('HH:mm').format(prog.stop);
                  final durationMin = prog.stop.difference(prog.start).inMinutes;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131222),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF22203A)),
                    ),
                    child: Row(
                      children: [
                        // Time column
                        Container(
                          width: 80,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                startTimeStr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '$stopTimeStr ($durationMin m)',
                                style: const TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 14),

                        // Title & description
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prog.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (prog.description != null && prog.description!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  prog.description!,
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

                        const SizedBox(width: 16),

                        // Play Catchup Button
                        FilledButton.icon(
                          onPressed: () => _playCatchupProgramme(context, channel, prog),
                          icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                          label: const Text('REPLAY'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6C5CE7),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            textStyle: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ── Query Channels with Catch-up Support
  // ─────────────────────────────────────────────────────────────
  Future<List<db.Channel>> _fetchCatchupChannels(
    db.AppDatabase database,
    String providerId,
  ) async {
    // 1. Get all channels for this provider
    final allChannels = await database.getChannelsForProvider(providerId);
    final liveChannels = allChannels.where((c) => c.streamType == 'live').toList();

    // 2. Identify channels that have EPG mappings or programmes
    final mappings = await database.getAllMappings();
    final mappedChannelIds = mappings.map((m) => m.channelId).toSet();

    // Channels with tvgId or EPG mappings or catchup indicators
    final catchupChannels = liveChannels.where((c) {
      if (mappedChannelIds.contains(c.id)) return true;
      if (c.tvgId != null && c.tvgId!.isNotEmpty) return true;
      final nameLower = c.name.toLowerCase();
      if (nameLower.contains('[archive]') || nameLower.contains('(archive)') || nameLower.contains('catchup')) {
        return true;
      }
      return false;
    }).toList();

    final result = catchupChannels.isNotEmpty ? catchupChannels : liveChannels.take(50).toList();

    // If an initial channel was passed, ensure it is in the list and at the top
    if (widget.initialChannel != null && !result.any((c) => c.id == widget.initialChannel!.id)) {
      result.insert(0, widget.initialChannel!);
    }

    return result;
  }

  // ─────────────────────────────────────────────────────────────
  // ── Fetch Programmes for Selected Date
  // ─────────────────────────────────────────────────────────────
  Future<List<db.EpgProgramme>> _fetchDayProgrammes(
    db.AppDatabase database,
    db.Channel channel,
    DateTime targetDate,
  ) async {
    final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 0, 0, 0);
    final endOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59);

    String? epgId;
    final mappings = await database.getAllMappings();
    final match = mappings.where((m) => m.channelId == channel.id);
    if (match.isNotEmpty) {
      epgId = '${match.first.epgSourceId}_${match.first.epgChannelId}';
    } else if (channel.tvgId != null && channel.tvgId!.isNotEmpty) {
      epgId = channel.tvgId;
    }

    List<db.EpgProgramme> localProgs = [];
    if (epgId != null) {
      localProgs = await database.getProgrammes(
        epgChannelId: epgId,
        start: startOfDay,
        end: endOfDay,
      );
    }

    if (localProgs.isNotEmpty) return localProgs;

    // Fallback: Fetch from Xtream Provider simple data table if local DB has no programmes
    try {
      final provider = await (database.select(database.providers)
            ..where((t) => t.id.equals(channel.providerId)))
          .getSingleOrNull();

      String? baseUrl;
      String? username;
      String? password;
      String? streamId;

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
        final uri = Uri.tryParse(channel.streamUrl);
        if (uri != null && uri.pathSegments.length >= 3) {
          final segs = uri.pathSegments;
          baseUrl = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
          username = segs[segs.length - 3];
          password = segs[segs.length - 2];
        }
      }

      if (channel.id.contains('_')) {
        streamId = channel.id.split('_').last;
      } else {
        final uri = Uri.tryParse(channel.streamUrl);
        if (uri != null && uri.pathSegments.isNotEmpty) {
          streamId = uri.pathSegments.last.split('.').first;
        }
      }

      if (baseUrl != null && username != null && password != null && streamId != null && streamId.isNotEmpty) {
        final client = XtreamClient(
          baseUrl: baseUrl,
          username: username,
          password: password,
        );
        final entries = await client.getSimpleDataTable(streamId);
        client.dispose();

        final dateStr = DateFormat('yyyy-MM-dd').format(targetDate);
        final filteredEntries = entries.where((e) {
          if (e.start == null) return false;
          final entryDate = DateFormat('yyyy-MM-dd').format(e.start!);
          return entryDate == dateStr;
        }).toList();

        final listToUse = filteredEntries.isNotEmpty ? filteredEntries : entries;

        return listToUse.map((e) => db.EpgProgramme(
          id: (e.start?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch) % 2147483647,
          epgChannelId: channel.id,
          sourceId: channel.providerId,
          title: e.title,
          description: e.description,
          start: e.start ?? DateTime.now().subtract(const Duration(hours: 1)),
          stop: e.end ?? DateTime.now(),
        )).toList();
      }
    } catch (_) {}

    return [];
  }

  // ─────────────────────────────────────────────────────────────
  // ── Play Catch-up Programme
  // ─────────────────────────────────────────────────────────────
  void _playCatchupProgramme(
    BuildContext context,
    db.Channel channel,
    db.EpgProgramme programme,
  ) async {
    final durationMinutes = programme.stop.difference(programme.start).inMinutes;
    final startFormatted = DateFormat('yyyy-MM-dd:HH-mm').format(programme.start);

    // Build Timeshift URL if Xtream
    String playUrl = channel.streamUrl;
    final uri = Uri.tryParse(channel.streamUrl);
    if (uri != null && uri.pathSegments.length >= 3) {
      final segments = uri.pathSegments;
      final username = segments.length >= 3 ? segments[segments.length - 3] : '';
      final password = segments.length >= 2 ? segments[segments.length - 2] : '';
      final streamId = segments.last.replaceAll(RegExp(r'\..+$'), '');

      if (username.isNotEmpty && password.isNotEmpty && streamId.isNotEmpty) {
        final base = '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
        playUrl = '$base/timeshift/$username/$password/$durationMinutes/$startFormatted/$streamId.ts';
      }
    } else {
      try {
        final dbInstance = ref.read(databaseProvider);
        final provider = await (dbInstance.select(dbInstance.providers)
              ..where((t) => t.id.equals(channel.providerId)))
            .getSingleOrNull();
        if (provider != null && provider.url != null && provider.username != null && provider.password != null) {
          final streamId = channel.id.contains('_') ? channel.id.split('_').last : channel.id;
          final base = provider.url!.endsWith('/') ? provider.url!.substring(0, provider.url!.length - 1) : provider.url!;
          playUrl = '$base/timeshift/${provider.username}/${provider.password}/$durationMinutes/$startFormatted/$streamId.ts';
        }
      } catch (_) {}
    }

    if (!context.mounted) return;
    context.push('/player', extra: {
      'streamUrl': playUrl,
      'channelName': '${channel.name} • ${programme.title}',
      'channelLogo': channel.tvgLogo,
    });
  }
}
