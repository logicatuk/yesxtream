import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/platform_info.dart';
import '../../core/tv_back_handler.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/datasources/remote/xtream_client.dart';
import '../../data/services/app_settings.dart';
import '../playlists/playlist_providers.dart';
import '../providers/provider_manager.dart';

/// Dedicated Catch-up (TV Archive / Replay) Screen.
/// Filters and displays ONLY channels that actually support Catch-up / TV Archive,
/// with instant day-switching, smooth 60fps scrolling, and 1-tap replay playback.
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

  // Channels state
  bool _isLoadingChannels = true;
  String? _currentLoadedProviderId;
  List<db.Channel> _allCatchupChannels = [];
  List<db.Channel> _filteredChannels = [];

  // Programmes state & in-memory cache
  bool _isLoadingProgrammes = false;
  List<db.EpgProgramme> _currentProgrammes = [];
  final Map<String, List<db.EpgProgramme>> _programmesCache = {};

  // Static cache of archive-supported stream IDs per provider to avoid repeated network calls
  static final Map<String, Set<String>> _providerArchiveStreamIds = {};

  @override
  void initState() {
    super.initState();
    _selectedChannel = widget.initialChannel;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadChannels();
    });
  }

  @override
  void didUpdateWidget(CatchupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialChannel != oldWidget.initialChannel && widget.initialChannel != null) {
      _selectChannel(widget.initialChannel!);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _checkProviderChange(String? activePlaylistId) {
    if (activePlaylistId != null && activePlaylistId != _currentLoadedProviderId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadChannels();
      });
    }
  }

  /// Load ONLY genuine catch-up channels for the active provider.
  Future<void> _loadChannels() async {
    final activePlaylist = ref.read(activePlaylistProvider);
    if (activePlaylist == null) {
      if (mounted) {
        setState(() {
          _isLoadingChannels = false;
          _allCatchupChannels = [];
          _filteredChannels = [];
        });
      }
      return;
    }

    final providerId = activePlaylist.id;
    _currentLoadedProviderId = providerId;

    if (mounted) {
      setState(() => _isLoadingChannels = true);
    }

    final database = ref.read(databaseProvider);
    final liveChannels = await database.getLiveChannels(providerId: providerId);

    // Check provider info
    final provider = await (database.select(database.providers)
          ..where((t) => t.id.equals(providerId)))
        .getSingleOrNull();

    Set<String> archiveStreamIds = {};

    // 1. Resolve Xtream credentials if available
    String? baseUrl;
    String? username;
    String? password;

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

    // 2. If Xtream is available, check / cache real tv_archive stream IDs
    if (baseUrl != null && username != null && password != null) {
      if (_providerArchiveStreamIds.containsKey(providerId)) {
        archiveStreamIds = _providerArchiveStreamIds[providerId]!;
      } else {
        try {
          final client = XtreamClient(
            baseUrl: baseUrl,
            username: username,
            password: password,
          );
          archiveStreamIds = await client.getArchiveStreamIds();
          client.dispose();
          _providerArchiveStreamIds[providerId] = archiveStreamIds;
        } catch (_) {}
      }
    }

    // 3. Filter channels that genuinely support Catch-up
    final catchupChannels = liveChannels.where((c) {
      final streamId = c.id.contains('_') ? c.id.split('_').last : c.id;

      // Exact match with server tv_archive flag
      if (archiveStreamIds.isNotEmpty &&
          (archiveStreamIds.contains(streamId) || archiveStreamIds.contains(c.id))) {
        return true;
      }

      // Check name tags indicating catchup/archive
      final nameLower = c.name.toLowerCase();
      if (nameLower.contains('[archive]') ||
          nameLower.contains('(archive)') ||
          nameLower.contains('[catchup]') ||
          nameLower.contains('(catchup)') ||
          nameLower.contains('[replay]') ||
          nameLower.contains('(replay)') ||
          nameLower.contains(' catchup') ||
          nameLower.contains(' replay')) {
        return true;
      }

      // Check stream URL or group title
      if (c.streamUrl.contains('/timeshift/')) return true;
      final groupLower = c.groupTitle?.toLowerCase() ?? '';
      if (groupLower.contains('catchup') ||
          groupLower.contains('archive') ||
          groupLower.contains('replay')) {
        return true;
      }

      return false;
    }).toList();

    // If an initial channel was passed, ensure it is available in the list
    if (widget.initialChannel != null &&
        !catchupChannels.any((c) => c.id == widget.initialChannel!.id)) {
      catchupChannels.insert(0, widget.initialChannel!);
    }

    if (!mounted) return;

    db.Channel? nextSelected = _selectedChannel;
    if (nextSelected == null || !catchupChannels.any((c) => c.id == nextSelected!.id)) {
      nextSelected = catchupChannels.isNotEmpty ? catchupChannels.first : null;
    }

    setState(() {
      _allCatchupChannels = catchupChannels;
      _applySearchFilter();
      _selectedChannel = nextSelected;
      _isLoadingChannels = false;
    });

    if (nextSelected != null) {
      _loadProgrammesForChannel(nextSelected);
    }
  }

  void _onSearchChanged(String val) {
    setState(() {
      _searchQuery = val;
      _applySearchFilter();
    });
  }

  void _applySearchFilter() {
    if (_searchQuery.trim().isEmpty) {
      _filteredChannels = List.from(_allCatchupChannels);
    } else {
      final q = _searchQuery.toLowerCase().trim();
      _filteredChannels = _allCatchupChannels.where((c) {
        return c.name.toLowerCase().contains(q) ||
            (c.groupTitle?.toLowerCase().contains(q) ?? false);
      }).toList();
    }
  }

  void _selectChannel(db.Channel ch) {
    if (_selectedChannel?.id == ch.id) return;
    setState(() => _selectedChannel = ch);
    _loadProgrammesForChannel(ch);
  }

  void _selectDay(int dayOffset) {
    if (_selectedDayOffset == dayOffset) return;
    setState(() => _selectedDayOffset = dayOffset);
    if (_selectedChannel != null) {
      _loadProgrammesForChannel(_selectedChannel!);
    }
  }

  /// Load programmes for the selected channel and day offset, using in-memory cache when possible.
  Future<void> _loadProgrammesForChannel(db.Channel channel) async {
    final cacheKey = '${channel.id}_$_selectedDayOffset';

    if (_programmesCache.containsKey(cacheKey)) {
      if (mounted) {
        setState(() {
          _currentProgrammes = _programmesCache[cacheKey]!;
          _isLoadingProgrammes = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoadingProgrammes = true);
    }

    final targetDate = DateTime.now().subtract(Duration(days: _selectedDayOffset));
    final database = ref.read(databaseProvider);
    final progs = await _fetchDayProgrammes(database, channel, targetDate);

    _programmesCache[cacheKey] = progs;

    if (mounted && _selectedChannel?.id == channel.id) {
      setState(() {
        _currentProgrammes = progs;
        _isLoadingProgrammes = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePlaylist = ref.watch(activePlaylistProvider);
    final settings = ref.watch(appSettingsProvider);
    _checkProviderChange(activePlaylist?.id);

    if (activePlaylist == null) {
      return TvBackHandler(
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          body: Center(
            child: Text(
              settings.tr('no_active_playlist'),
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    if (_isLoadingChannels) {
      return TvBackHandler(
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFF6C5CE7)),
                const SizedBox(height: 16),
                Text(
                  settings.tr('scanning_catchup'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return TvBackHandler(
      child: Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Row(
        children: [
          // ── Left Column: Channel List (ONLY Genuine Catch-up channels) ──
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
                              Text(
                                settings.tr('catchup_title'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${_filteredChannels.length} ${settings.tr('catchup_available')}',
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
                      // Keep search out of TV D-pad traversal; focus channels first.
                      focusNode: FocusNode(skipTraversal: PlatformInfo.isTV),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: settings.tr('search_catchup'),
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.white38, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
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
                      onChanged: _onSearchChanged,
                    ),
                  ),

                  const Divider(color: Color(0xFF1E1E2E), height: 12),

                  // Channels Virtualized ListView
                  Expanded(
                    child: _filteredChannels.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _searchQuery.isEmpty
                                    ? settings.tr('no_catchup_channels')
                                    : '${settings.tr('no_match')} "$_searchQuery"',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _filteredChannels.length,
                            itemExtent: 58.0, // Fixed height for 60fps virtualization
                            itemBuilder: (context, index) {
                              final ch = _filteredChannels[index];
                              final isSelected = ch.id == _selectedChannel?.id;

                              return FocusableActionDetector(
                                autofocus: PlatformInfo.isTV && index == 0,
                                actions: {
                                  ActivateIntent: CallbackAction<ActivateIntent>(
                                    onInvoke: (_) {
                                      _selectChannel(ch);
                                      return null;
                                    },
                                  ),
                                },
                                child: Builder(
                                  builder: (itemCtx) {
                                    final focused = Focus.of(itemCtx).hasFocus;
                                    return Material(
                                color: isSelected || focused
                                    ? const Color(0xFF6C5CE7).withValues(alpha: focused ? 0.30 : 0.18)
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: () => _selectChannel(ch),
                                  child: Container(
                                    height: 58.0,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: const BorderSide(color: Color(0xFF151424), width: 1),
                                        left: focused
                                            ? const BorderSide(color: Colors.white, width: 3)
                                            : BorderSide.none,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        // Channel Logo with memory caching
                                        Container(
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
                                                    memCacheWidth: 72,
                                                    memCacheHeight: 72,
                                                    maxWidthDiskCache: 120,
                                                    maxHeightDiskCache: 120,
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
                                        const SizedBox(width: 12),

                                        // Name and category
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                ch.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isSelected ? Colors.white : Colors.white70,
                                                  fontSize: 13,
                                                  fontWeight:
                                                      isSelected ? FontWeight.bold : FontWeight.w500,
                                                ),
                                              ),
                                              if (ch.groupTitle != null && ch.groupTitle!.isNotEmpty)
                                                Text(
                                                  ch.groupTitle!,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white38,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),

                                        // Replay indicator badge
                                        const Icon(
                                          Icons.history_rounded,
                                          color: Color(0xFF6C5CE7),
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                    );
                                  },
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
                ? Center(
                    child: Text(
                      settings.tr('select_catchup_channel'),
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                : _buildChannelArchiveView(context, _selectedChannel!, settings),
          ),
        ],
      ),
    ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ── Channel Archive View (Day Selector + Programme Listings)
  // ─────────────────────────────────────────────────────────────
  Widget _buildChannelArchiveView(
    BuildContext context,
    db.Channel channel,
    AppSettings settings,
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
                      memCacheWidth: 96,
                      memCacheHeight: 96,
                      maxWidthDiskCache: 160,
                      maxHeightDiskCache: 160,
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
                    'stopOnExit': true,
                  });
                },
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: Text(settings.tr('watch_live')),
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
                label = settings.tr('today');
              } else if (index == 1) {
                label = settings.tr('yesterday');
              } else {
                label = DateFormat('E dd/MM').format(dayDate);
              }

              return FocusableActionDetector(
                actions: {
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      _selectDay(index);
                      return null;
                    },
                  ),
                },
                child: Builder(
                  builder: (pillCtx) {
                    final focused = Focus.of(pillCtx).hasFocus;
                    return InkWell(
                      onTap: () => _selectDay(index),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF6C5CE7) : const Color(0xFF161528),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: focused
                                ? Colors.white
                                : (isSelected
                                    ? const Color(0xFFA29BFE)
                                    : const Color(0xFF26243A)),
                            width: focused ? 2.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              color: isSelected || focused ? Colors.white : Colors.white70,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),

        const Divider(color: Color(0xFF1E1E2E), height: 1),

        // ── Programme Listings for Selected Day ──
        Expanded(
          child: _isLoadingProgrammes
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
                )
              : _currentProgrammes.isEmpty
                  ? Center(
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
                            '${settings.tr('no_catchup_programs')} (${DateFormat('dd MMMM yyyy').format(targetDate)})',
                            style: const TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                          const SizedBox(height: 18),
                          OutlinedButton.icon(
                            onPressed: () {
                              context.push('/player', extra: {
                                'streamUrl': channel.streamUrl,
                                'channelName': channel.name,
                                'channelLogo': channel.tvgLogo,
                                'stopOnExit': true,
                              });
                            },
                            icon: const Icon(Icons.play_arrow_rounded, size: 16),
                            label: Text(settings.tr('watch_live')),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF6C5CE7),
                              side: const BorderSide(color: Color(0xFF6C5CE7)),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      itemCount: _currentProgrammes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final prog = _currentProgrammes[index];
                        final startTimeStr = DateFormat('HH:mm').format(prog.start);
                        final stopTimeStr = DateFormat('HH:mm').format(prog.stop);
                        final durationMin = prog.stop.difference(prog.start).inMinutes;

                        return FocusableActionDetector(
                          actions: {
                            ActivateIntent: CallbackAction<ActivateIntent>(
                              onInvoke: (_) {
                                _playCatchupProgramme(context, channel, prog);
                                return null;
                              },
                            ),
                          },
                          child: Builder(
                            builder: (progCtx) {
                              final focused = Focus.of(progCtx).hasFocus;
                              return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF131222),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: focused ? Colors.white : const Color(0xFF22203A),
                              width: focused ? 2.5 : 1,
                            ),
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
                                    if (prog.description != null &&
                                        prog.description!.isNotEmpty) ...[
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
                                label: Text(settings.tr('play_catchup')),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF6C5CE7),
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
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

    // Single-row mapping lookup instead of loading all mappings
    final match = await (database.select(database.epgMappings)
          ..where((t) => t.channelId.equals(channel.id)))
        .getSingleOrNull();

    if (match != null) {
      epgId = '${match.epgSourceId}_${match.epgChannelId}';
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

      if (baseUrl != null &&
          username != null &&
          password != null &&
          streamId != null &&
          streamId.isNotEmpty) {
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

        return listToUse
            .map((e) => db.EpgProgramme(
                  id: (e.start?.millisecondsSinceEpoch ??
                          DateTime.now().millisecondsSinceEpoch) %
                      2147483647,
                  epgChannelId: channel.id,
                  sourceId: channel.providerId,
                  title: e.title,
                  description: e.description,
                  start: e.start ?? DateTime.now().subtract(const Duration(hours: 1)),
                  stop: e.end ?? DateTime.now(),
                ))
            .toList();
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
        playUrl =
            '$base/timeshift/$username/$password/$durationMinutes/$startFormatted/$streamId.ts';
      }
    } else {
      try {
        final dbInstance = ref.read(databaseProvider);
        final provider = await (dbInstance.select(dbInstance.providers)
              ..where((t) => t.id.equals(channel.providerId)))
            .getSingleOrNull();
        if (provider != null &&
            provider.url != null &&
            provider.username != null &&
            provider.password != null) {
          final streamId =
              channel.id.contains('_') ? channel.id.split('_').last : channel.id;
          final base = provider.url!.endsWith('/')
              ? provider.url!.substring(0, provider.url!.length - 1)
              : provider.url!;
          playUrl =
              '$base/timeshift/${provider.username}/${provider.password}/$durationMinutes/$startFormatted/$streamId.ts';
        }
      } catch (_) {}
    }

    if (!context.mounted) return;
    context.push('/player', extra: {
      'streamUrl': playUrl,
      'channelName': '${channel.name} • ${programme.title}',
      'channelLogo': channel.tvgLogo,
      'stopOnExit': true,
    });
  }
}
