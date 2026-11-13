import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/fuzzy_match.dart';
import '../../core/tv_back_handler.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/services/app_settings.dart';
import '../playlists/playlist_providers.dart';
import '../providers/provider_manager.dart';

/// EPG program guide — horizontal timeline grid view with category filtering.
class GuideScreen extends ConsumerStatefulWidget {
  const GuideScreen({super.key});

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  DateTime _focusTime = DateTime.now();
  final _scrollController = ScrollController();
  final _scrollOffset = ValueNotifier<double>(0.0);
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  /// Pixels per minute for the timeline.
  static const _pixelsPerMinute = 4.0;

  // Channel & Category state
  bool _loading = true;
  List<db.Channel> _allLiveChannels = [];
  List<String> _categories = ['All'];
  String _selectedCategory = 'All';

  // EPG mapping & index maps
  final Map<String, String> _epgMappings = {};
  final Set<String> _validEpgChannelIds = {};
  final Map<String, String> _rawTvgIdToEpgId = {};
  final Map<String, String> _normNameToEpgId = {};
  bool _mappingsLoaded = false;

  // In-memory programme cache (epgChannelId_day -> List<EpgProgramme>)
  final Map<String, List<db.EpgProgramme>> _programmeCache = {};

  @override
  void initState() {
    super.initState();
    _loadData();

    // Pre-set offset to "now"
    final nowMinutes = _focusTime.hour * 60 + _focusTime.minute;
    final initialOffset = (nowMinutes * _pixelsPerMinute - 100).clamp(0.0, 24 * 60 * _pixelsPerMinute);
    _scrollOffset.value = initialOffset;

    _scrollController.addListener(() {
      _scrollOffset.value = _scrollController.offset;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(initialOffset);
      }
    });
  }

  Future<void> _loadData() async {
    final database = ref.read(databaseProvider);
    final activePlaylist = ref.read(activePlaylistProvider);

    String? targetPid = activePlaylist?.id;
    if (targetPid == null) {
      final providers = await database.getAllProviders();
      if (providers.isNotEmpty) targetPid = providers.first.id;
    }

    if (targetPid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      // 1. Fetch only LIVE channels for the active playlist (avoids loading 300k VOD items)
      final liveChannels = await database.getLiveChannels(providerId: targetPid);
      final groupCounts = await database.getLiveGroupCounts(providerId: targetPid);

      final cats = ['All', ...groupCounts.keys.toList()..sort()];

      // 2. Load EPG sources & build multi-level matching index
      final mappings = await database.getAllMappings();
      final epgSources = await database.getAllEpgSources();
      final currentSourceIds = epgSources.map((s) => s.id).toSet();

      final validIds = <String>{};
      final rawToPrefixed = <String, String>{};
      final normNameToPrefixed = <String, String>{};

      for (final src in epgSources) {
        final chs = await database.getEpgChannelsForSource(src.id);
        for (final ch in chs) {
          validIds.add(ch.id);
          rawToPrefixed[ch.channelId.toLowerCase()] = ch.id;
          final norm = _normalizeForEpgMatch(ch.displayName);
          if (norm.isNotEmpty) normNameToPrefixed[norm] = ch.id;
        }
      }

      final epgMap = <String, String>{};
      for (final m in mappings) {
        if (currentSourceIds.contains(m.epgSourceId)) {
          epgMap[m.channelId] = '${m.epgSourceId}_${m.epgChannelId}';
        } else {
          for (final srcId in currentSourceIds) {
            final candidate = '${srcId}_${m.epgChannelId}';
            if (validIds.contains(candidate)) {
              epgMap[m.channelId] = candidate;
              break;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _allLiveChannels = liveChannels;
          _categories = cats;
          _epgMappings.addAll(epgMap);
          _validEpgChannelIds.addAll(validIds);
          _rawTvgIdToEpgId.addAll(rawToPrefixed);
          _normNameToEpgId.addAll(normNameToPrefixed);
          _mappingsLoaded = true;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[Guide] Error loading data: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Normalize channel / EPG name for fuzzy matching
  static String _normalizeForEpgMatch(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\(.*?\)'), '')
        .replaceAll(RegExp(r'\b(hd|fhd|shd|sd|4k|uhd|us|uk|ca|fr|ar|es)\b'), '')
        .replaceAll(RegExp(r'^[a-z]{2,3}[-_|:]+\s*'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Resolve a channel to its EPG channel ID for programme lookup.
  String? _resolveEpgId(db.Channel channel) {
    // 1. Explicit mapping
    final mapped = _epgMappings[channel.id];
    if (mapped != null && mapped.isNotEmpty) return mapped;

    // 2. Exact match on raw tvgId -> prefixed EPG id
    if (channel.tvgId != null && channel.tvgId!.isNotEmpty) {
      final tvgLower = channel.tvgId!.trim().toLowerCase();
      final direct = _rawTvgIdToEpgId[tvgLower];
      if (direct != null) return direct;
      if (_validEpgChannelIds.contains(channel.tvgId)) return channel.tvgId;
    }

    // 3. Match by normalized channel name
    final normName = _normalizeForEpgMatch(channel.name);
    final byName = _normNameToEpgId[normName];
    if (byName != null) return byName;

    return null;
  }

  List<db.Channel> get _filteredChannels {
    var list = _allLiveChannels;
    if (_selectedCategory != 'All') {
      list = list.where((c) => c.groupTitle == _selectedCategory).toList();
    }
    if (_searchQuery.trim().isNotEmpty) {
      list = list
          .where((c) => fuzzyMatchPasses(_searchQuery, [c.name, c.groupTitle]))
          .toList();
    }
    return list;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _scrollOffset.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        primaryFocus!.unfocus();
      }
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _scrollController.animateTo(
        (_scrollController.offset - 250).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _scrollController.animateTo(
        (_scrollController.offset + 250).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final database = ref.read(databaseProvider);
    final channels = _filteredChannels;

    return TvBackHandler(
      fallbackRoute: '/',
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0F),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F0E1A),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
            ),
            title: const Text('Program Guide', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            actions: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded, size: 16, color: Colors.white70),
                tooltip: 'Previous day',
                onPressed: () {
                  setState(() {
                    _focusTime = _focusTime.subtract(const Duration(days: 1));
                    _programmeCache.clear();
                  });
                },
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _focusTime = DateTime.now();
                    _programmeCache.clear();
                  });
                },
                child: Text(
                  _formatDate(_focusTime),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF6C5CE7)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.white70),
                tooltip: 'Next day',
                onPressed: () {
                  setState(() {
                    _focusTime = _focusTime.add(const Duration(days: 1));
                    _programmeCache.clear();
                  });
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF6C5CE7)))
              : _allLiveChannels.isEmpty
                  ? const _GuideEmptyState()
                  : Column(
                      children: [
                        // ── Search & Category Filter Bar ──
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF0F0E1A),
                            border: Border(bottom: BorderSide(color: Color(0xFF1E1C2E))),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 38,
                                      child: TextField(
                                        controller: _searchController,
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: 'Search channels…',
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
                                          fillColor: const Color(0xFF161528),
                                          contentPadding: EdgeInsets.zero,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                        onChanged: (v) => setState(() => _searchQuery = v),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    height: 38,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF161528),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF26243A)),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: _categories.contains(_selectedCategory) ? _selectedCategory : 'All',
                                        dropdownColor: const Color(0xFF161528),
                                        style: const TextStyle(color: Colors.white, fontSize: 13),
                                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
                                        items: _categories.map((cat) {
                                          return DropdownMenuItem<String>(
                                            value: cat,
                                            child: Text(cat, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() => _selectedCategory = val);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // ── Time Ruler ──
                        Container(
                          height: 32,
                          color: const Color(0xFF0F0E1A),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 140,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'CHANNELS',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: _TimeRuler(
                                  scrollController: _scrollController,
                                  focusDate: _focusTime,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Color(0xFF1E1C2E)),

                        // ── Channel Rows ──
                        Expanded(
                          child: channels.isEmpty
                              ? const Center(
                                  child: Text('No channels match your filter',
                                      style: TextStyle(color: Colors.white38)),
                                )
                              : ListView.builder(
                                  itemCount: channels.length,
                                  itemExtent: 56,
                                  itemBuilder: (context, index) {
                                    final channel = channels[index];
                                    final epgId = _mappingsLoaded ? _resolveEpgId(channel) : null;
                                    return _ChannelGuideRow(
                                      key: ValueKey(channel.id),
                                      channel: channel,
                                      channelName: channel.name,
                                      channelLogo: channel.tvgLogo,
                                      scrollOffset: _scrollOffset,
                                      database: database,
                                      epgChannelId: epgId,
                                      focusDate: _focusTime,
                                      pixelsPerMinute: _pixelsPerMinute,
                                      timeShiftHours: settings.epgTimeShiftHours,
                                      cache: _programmeCache,
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return 'Today';
    }
    return '${dt.month}/${dt.day}';
  }
}

class _TimeRuler extends StatelessWidget {
  final ScrollController scrollController;
  final DateTime focusDate;

  const _TimeRuler({required this.scrollController, required this.focusDate});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(24, (hour) {
          final width = 60 * _GuideScreenState._pixelsPerMinute;
          final h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
          final ampm = hour < 12 ? 'AM' : 'PM';
          return SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                '$h12:00 $ampm',
                style: const TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600),
                overflow: TextOverflow.clip,
                maxLines: 1,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ChannelGuideRow extends StatefulWidget {
  final db.Channel channel;
  final String channelName;
  final String? channelLogo;
  final ValueNotifier<double> scrollOffset;
  final db.AppDatabase database;
  final String? epgChannelId;
  final DateTime focusDate;
  final double pixelsPerMinute;
  final int timeShiftHours;
  final Map<String, List<db.EpgProgramme>> cache;

  const _ChannelGuideRow({
    super.key,
    required this.channel,
    required this.channelName,
    this.channelLogo,
    required this.scrollOffset,
    required this.database,
    this.epgChannelId,
    required this.focusDate,
    required this.pixelsPerMinute,
    this.timeShiftHours = 0,
    required this.cache,
  });

  @override
  State<_ChannelGuideRow> createState() => _ChannelGuideRowState();
}

class _ChannelGuideRowState extends State<_ChannelGuideRow> {
  List<db.EpgProgramme>? _programmes;
  bool _loading = false;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _loadProgrammes();
  }

  @override
  void didUpdateWidget(covariant _ChannelGuideRow old) {
    super.didUpdateWidget(old);
    if (old.epgChannelId != widget.epgChannelId ||
        old.focusDate != widget.focusDate ||
        old.timeShiftHours != widget.timeShiftHours) {
      _loadProgrammes();
    }
  }

  Future<void> _loadProgrammes() async {
    if (widget.epgChannelId == null) {
      if (mounted) setState(() => _programmes = []);
      return;
    }

    final cacheKey = '${widget.epgChannelId}_${widget.focusDate.year}_${widget.focusDate.month}_${widget.focusDate.day}_${widget.timeShiftHours}';
    if (widget.cache.containsKey(cacheKey)) {
      if (mounted) {
        setState(() {
          _programmes = widget.cache[cacheKey];
          _loading = false;
        });
      }
      return;
    }

    setState(() => _loading = true);
    final shift = Duration(hours: widget.timeShiftHours);
    final dayStart = DateTime(widget.focusDate.year, widget.focusDate.month, widget.focusDate.day);
    final dayEnd = dayStart.add(const Duration(hours: 24));

    try {
      final progs = await widget.database.getProgrammes(
        epgChannelId: widget.epgChannelId!,
        start: dayStart.subtract(shift),
        end: dayEnd.subtract(shift),
      );

      final unique = <db.EpgProgramme>[];
      for (final raw in progs) {
        final p = widget.timeShiftHours == 0
            ? raw
            : raw.copyWith(
                start: raw.start.add(shift),
                stop: raw.stop.add(shift),
              );
        final dominated = unique.any((u) {
          final oStart = p.start.isAfter(u.start) ? p.start : u.start;
          final oEnd = p.stop.isBefore(u.stop) ? p.stop : u.stop;
          final overlapMs = oEnd.difference(oStart).inMilliseconds;
          if (overlapMs <= 0) return false;
          final pMs = p.stop.difference(p.start).inMilliseconds;
          return pMs > 0 && overlapMs > pMs * 0.5;
        });
        if (!dominated) unique.add(p);
      }

      widget.cache[cacheKey] = unique;
      if (mounted) setState(() { _programmes = unique; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _programmes = []; _loading = false; });
    }
  }

  void _watchChannel() {
    context.push('/player', extra: {
      'streamUrl': widget.channel.streamUrl,
      'channelName': widget.channel.name,
      'channelLogo': widget.channel.tvgLogo,
      'channels': [
        {
          'id': widget.channel.id,
          'name': widget.channel.name,
          'streamUrl': widget.channel.streamUrl,
          'tvgLogo': widget.channel.tvgLogo,
        }
      ],
      'currentIndex': 0,
    });
  }

  @override
  Widget build(BuildContext context) {
    final ppm = widget.pixelsPerMinute;
    final dayStart = DateTime(widget.focusDate.year, widget.focusDate.month, widget.focusDate.day);
    final now = DateTime.now();

    return FocusableActionDetector(
      onFocusChange: (f) => setState(() => _isFocused = f),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          _watchChannel();
          return null;
        }),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) {
          _watchChannel();
          return null;
        }),
      },
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: _isFocused ? const Color(0xFF6C5CE7).withValues(alpha: 0.15) : Colors.transparent,
          border: Border(
            bottom: const BorderSide(color: Color(0xFF141322)),
            left: _isFocused ? const BorderSide(color: Color(0xFF6C5CE7), width: 3) : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            // ── Channel Label Card ──
            InkWell(
              onTap: _watchChannel,
              child: Container(
                width: 140,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFF1E1C2E))),
                ),
                child: Row(
                  children: [
                    if (widget.channelLogo != null && widget.channelLogo!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.network(
                            widget.channelLogo!,
                            width: 26,
                            height: 26,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 20, color: Colors.white24),
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: Icon(Icons.tv, size: 20, color: Colors.white24),
                      ),
                    Expanded(
                      child: Text(
                        widget.channelName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Programme Timeline ──
            Expanded(
              child: _SyncedScrollRow(
                scrollOffset: widget.scrollOffset,
                child: SizedBox(
                  width: 24 * 60 * ppm,
                  height: 52,
                  child: _loading
                      ? const SizedBox.shrink()
                      : (_programmes == null || _programmes!.isEmpty)
                          ? InkWell(
                              onTap: _watchChannel,
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                ),
                                child: const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(left: 12),
                                    child: Text(
                                      'No guide available • Tap to watch live stream',
                                      style: TextStyle(fontSize: 11, color: Colors.white24),
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Stack(
                              clipBehavior: Clip.hardEdge,
                              children: [
                                for (final prog in _programmes!)
                                  _buildProgrammeBlock(prog, dayStart, now, ppm),
                                // Red "NOW" live indicator
                                if (now.year == dayStart.year &&
                                    now.month == dayStart.month &&
                                    now.day == dayStart.day)
                                  Positioned(
                                    left: now.difference(dayStart).inMinutes * ppm,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(width: 2, color: Colors.redAccent),
                                  ),
                              ],
                            ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProgrammeDetail(db.EpgProgramme? prog) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141322),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        prog?.title ?? widget.channelName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white54),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  prog != null
                      ? '${widget.channelName} • ${_fmtTime(prog.start)} – ${_fmtTime(prog.stop)}'
                      : '${widget.channelName} • Guide unavailable',
                  style: const TextStyle(color: Color(0xFFA29BFE), fontSize: 13),
                ),
                if (prog?.description != null && prog!.description!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    prog.description!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _watchChannel();
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Watch Channel'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C5CE7)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgrammeBlock(db.EpgProgramme prog, DateTime dayStart, DateTime now, double ppm) {
    final startMin = prog.start.difference(dayStart).inMinutes.toDouble().clamp(0, 24 * 60);
    final endMin = prog.stop.difference(dayStart).inMinutes.toDouble().clamp(0, 24 * 60);
    final width = (endMin - startMin) * ppm;
    if (width <= 0) return const SizedBox.shrink();
    final isNow = now.isAfter(prog.start) && now.isBefore(prog.stop);

    return Positioned(
      left: startMin * ppm,
      top: 4,
      bottom: 4,
      width: width,
      child: GestureDetector(
        onTap: () => _showProgrammeDetail(prog),
        child: Container(
          margin: const EdgeInsets.only(right: 2),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: isNow
                ? const Color(0xFF6C5CE7).withValues(alpha: 0.85)
                : const Color(0xFF1E1C2E).withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(4),
            border: isNow ? Border.all(color: Colors.white, width: 1.2) : null,
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                prog.title,
                style: TextStyle(
                  fontSize: 11,
                  color: isNow ? Colors.white : Colors.white70,
                  fontWeight: isNow ? FontWeight.bold : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (width > 80)
                Text(
                  '${_fmtTime(prog.start)} - ${_fmtTime(prog.stop)}',
                  style: const TextStyle(fontSize: 9, color: Colors.white38),
                  maxLines: 1,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }
}

class _GuideEmptyState extends StatelessWidget {
  const _GuideEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.live_tv_rounded, size: 64, color: Colors.white24),
          SizedBox(height: 16),
          Text('No Live Channels Found', style: TextStyle(fontSize: 18, color: Colors.white70, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Connect your IPTV provider or playlist to load the TV guide', style: TextStyle(fontSize: 13, color: Colors.white38)),
        ],
      ),
    );
  }
}

class _SyncedScrollRow extends StatefulWidget {
  final ValueNotifier<double> scrollOffset;
  final Widget child;

  const _SyncedScrollRow({required this.scrollOffset, required this.child});

  @override
  State<_SyncedScrollRow> createState() => _SyncedScrollRowState();
}

class _SyncedScrollRowState extends State<_SyncedScrollRow> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.scrollOffset.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!_controller.hasClients) return;
    final target = widget.scrollOffset.value.clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    if ((_controller.offset - target).abs() > 0.5) {
      _controller.jumpTo(target);
    }
  }

  @override
  void dispose() {
    widget.scrollOffset.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: widget.child,
    );
  }
}
