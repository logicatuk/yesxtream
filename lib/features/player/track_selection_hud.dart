import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../data/services/app_settings.dart';
import '../../data/services/pip_service.dart';

/// Advanced HUD bottom sheet / dialog for:
/// 1. Audio track switching
/// 2. Subtitle track selection
/// 3. Buffering presets (Low Latency / Live Sports vs Standard vs Ultra 4K VOD)
/// 4. Picture-in-Picture (PiP) trigger
/// 5. Aspect Ratio adjustment
/// Fully D-Pad navigable for Android TV with 10-foot neon purple focus highlights.
class TrackSelectionHud extends ConsumerStatefulWidget {
  final Player player;
  final VoidCallback? onPipRequested;
  final Function(String ratio)? onAspectRatioChanged;
  final String currentAspectRatio;

  const TrackSelectionHud({
    super.key,
    required this.player,
    this.onPipRequested,
    this.onAspectRatioChanged,
    this.currentAspectRatio = 'Auto',
  });

  static Future<void> show(
    BuildContext context, {
    required Player player,
    VoidCallback? onPipRequested,
    Function(String ratio)? onAspectRatioChanged,
    String currentAspectRatio = 'Auto',
  }) {
    final isTv = MediaQuery.of(context).size.width > 900;
    if (isTv) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620, maxHeight: 600),
            child: TrackSelectionHud(
              player: player,
              onPipRequested: onPipRequested,
              onAspectRatioChanged: onAspectRatioChanged,
              currentAspectRatio: currentAspectRatio,
            ),
          ),
        ),
      );
    } else {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: TrackSelectionHud(
            player: player,
            onPipRequested: onPipRequested,
            onAspectRatioChanged: onAspectRatioChanged,
            currentAspectRatio: currentAspectRatio,
          ),
        ),
      );
    }
  }

  @override
  ConsumerState<TrackSelectionHud> createState() => _TrackSelectionHudState();
}

class _TrackSelectionHudState extends ConsumerState<TrackSelectionHud>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Tracks _tracks;
  late Track _currentTrack;
  bool _pipSupported = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tracks = widget.player.state.tracks;
    _currentTrack = widget.player.state.track;
    _checkPipSupport();
  }

  Future<void> _checkPipSupport() async {
    final supported = await ref.read(pipServiceProvider).isPipSupported();
    if (mounted) {
      setState(() => _pipSupported = supported);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _applyBufferPreset(String mode) async {
    await ref.read(appSettingsProvider.notifier).update(
          (s) => s.copyWith(bufferMode: mode),
        );

    if (!kIsWeb) {
      try {
        final np = widget.player.platform as dynamic;
        switch (mode) {
          case 'low_latency':
            await np.setProperty('demuxer-readahead-secs', '2');
            await np.setProperty('cache-secs', '5');
            await np.setProperty('demuxer-max-bytes', '64M');
            await np.setProperty('demuxer-max-back-bytes', '16M');
            await np.setProperty('cache-pause', 'no');
            await np.setProperty('cache-pause-initial', 'no');
            await np.setProperty('cache-pause-wait', '0');
            break;
          case 'ultra':
            await np.setProperty('demuxer-readahead-secs', '180');
            await np.setProperty('cache-secs', '600');
            await np.setProperty('demuxer-max-bytes', '1500M');
            await np.setProperty('demuxer-max-back-bytes', '300M');
            await np.setProperty('cache-pause', 'no');
            break;
          case 'standard':
          default:
            await np.setProperty('demuxer-readahead-secs', '60');
            await np.setProperty('cache-secs', '180');
            await np.setProperty('demuxer-max-bytes', '400M');
            await np.setProperty('demuxer-max-back-bytes', '100M');
            await np.setProperty('cache-pause', 'no');
            break;
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final audioList = _tracks.audio.where((a) => a.id != 'auto' && a.id != 'no').toList();
    final subtitleList = _tracks.subtitle.where((s) => s.id != 'auto' && s.id != 'no').toList();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0E17).withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: const Color(0xFF26243A), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 28,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Grabber & Title Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
                    ),
                    child: const Icon(Icons.tune_rounded, color: Color(0xFFA78BFA), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      settings.tr('player_settings'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  if (_pipSupported)
                    _NeonFocusButton(
                      autofocus: false,
                      onPressed: () {
                        Navigator.of(context).pop();
                        if (widget.onPipRequested != null) {
                          widget.onPipRequested!();
                        } else {
                          ref.read(pipServiceProvider).enterPip();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF8B5CF6)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.picture_in_picture_alt_rounded,
                                color: Color(0xFFA78BFA), size: 16),
                            const SizedBox(width: 6),
                            Text(
                              settings.tr('enter_pip'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF161524),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF242238)),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: const Color(0xFF8B5CF6),
                  boxShadow: const [
                    BoxShadow(color: Color(0x668B5CF6), blurRadius: 10, spreadRadius: 1),
                  ],
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                tabs: [
                  Tab(
                    icon: const Icon(Icons.audiotrack_rounded, size: 18),
                    text: '${settings.tr('audio_tracks')} (${audioList.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.subtitles_rounded, size: 18),
                    text: '${settings.tr('subtitle_tracks')} (${subtitleList.length})',
                  ),
                  Tab(
                    icon: const Icon(Icons.speed_rounded, size: 18),
                    text: settings.tr('buffer_mode'),
                  ),
                ],
              ),
            ),

            // Tab Contents
            Flexible(
              child: SizedBox(
                height: 340,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Audio Tracks
                    _buildAudioTab(audioList, settings),

                    // Tab 2: Subtitles
                    _buildSubtitlesTab(subtitleList, settings),

                    // Tab 3: Buffering & Streaming Profiles
                    _buildBufferTab(settings),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioTab(List<AudioTrack> tracks, AppSettings settings) {
    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.audiotrack_outlined, size: 40, color: Colors.white24),
            const SizedBox(height: 8),
            Text(
              'No additional audio tracks found',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
          ],
        ),
      );
    }

    final activeId = _currentTrack.audio.id;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: tracks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final t = tracks[index];
        final isActive = t.id == activeId;
        final title = t.title != null && t.title!.isNotEmpty
            ? t.title!
            : (t.language != null && t.language!.isNotEmpty
                ? t.language!.toUpperCase()
                : 'Track ${index + 1}');

        final details = [
          if (t.language != null && t.language!.isNotEmpty) t.language!.toUpperCase(),
          if (t.channels != null) '${t.channels} ch',
          if (t.bitrate != null && t.bitrate! > 0) '${(t.bitrate! / 1000).round()} kbps',
        ].join(' • ');

        return _NeonFocusButton(
          autofocus: index == 0,
          onPressed: () {
            widget.player.setAudioTrack(t);
            setState(() {
              _currentTrack = widget.player.state.track;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.18)
                  : const Color(0xFF141322),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? const Color(0xFF8B5CF6) : const Color(0xFF22203A),
                width: isActive ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.audiotrack_rounded,
                  color: isActive ? const Color(0xFFA78BFA) : Colors.white54,
                  size: 20,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          details,
                          style: TextStyle(
                            color: isActive ? const Color(0xFFA78BFA) : Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isActive)
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSubtitlesTab(List<SubtitleTrack> tracks, AppSettings settings) {
    final activeId = _currentTrack.subtitle.id;
    final isOff = activeId == 'no' || activeId == 'auto';

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        // 'Off' Tile
        _NeonFocusButton(
          autofocus: isOff,
          onPressed: () {
            widget.player.setSubtitleTrack(SubtitleTrack.no());
            setState(() {
              _currentTrack = widget.player.state.track;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: isOff
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.18)
                  : const Color(0xFF141322),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isOff ? const Color(0xFF8B5CF6) : const Color(0xFF22203A),
                width: isOff ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.subtitles_off_rounded,
                    color: isOff ? const Color(0xFFA78BFA) : Colors.white54, size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    settings.tr('subtitles_off'),
                    style: TextStyle(
                      color: isOff ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: isOff ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (isOff)
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
              ],
            ),
          ),
        ),

        // Subtitle entries
        ...List.generate(tracks.length, (index) {
          final t = tracks[index];
          final isActive = t.id == activeId;
          final title = t.title != null && t.title!.isNotEmpty
              ? t.title!
              : (t.language != null && t.language!.isNotEmpty
                  ? t.language!.toUpperCase()
                  : 'Subtitle ${index + 1}');

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: _NeonFocusButton(
              onPressed: () {
                widget.player.setSubtitleTrack(t);
                setState(() {
                  _currentTrack = widget.player.state.track;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.18)
                      : const Color(0xFF141322),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isActive ? const Color(0xFF8B5CF6) : const Color(0xFF22203A),
                    width: isActive ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.subtitles_rounded,
                      color: isActive ? const Color(0xFFA78BFA) : Colors.white54,
                      size: 20,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: isActive ? Colors.white : Colors.white70,
                          fontSize: 14,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isActive)
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBufferTab(AppSettings settings) {
    final currentMode = settings.bufferMode;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        // 1. Low Latency Preset (Live Sports)
        _buildBufferTile(
          id: 'low_latency',
          title: settings.tr('buffer_low_latency'),
          description: settings.tr('buffer_low_latency_desc'),
          icon: Icons.bolt_rounded,
          accentColor: const Color(0xFFF59E0B),
          isSelected: currentMode == 'low_latency',
          onTap: () => _applyBufferPreset('low_latency'),
        ),
        const SizedBox(height: 10),

        // 2. Standard Balanced Preset
        _buildBufferTile(
          id: 'standard',
          title: settings.tr('buffer_standard'),
          description: settings.tr('buffer_standard_desc'),
          icon: Icons.balance_rounded,
          accentColor: const Color(0xFF3B82F6),
          isSelected: currentMode == 'standard',
          onTap: () => _applyBufferPreset('standard'),
        ),
        const SizedBox(height: 10),

        // 3. Ultra Stable Preset (4K VOD)
        _buildBufferTile(
          id: 'ultra',
          title: settings.tr('buffer_ultra'),
          description: settings.tr('buffer_ultra_desc'),
          icon: Icons.rocket_launch_rounded,
          accentColor: const Color(0xFF10B981),
          isSelected: currentMode == 'ultra',
          onTap: () => _applyBufferPreset('ultra'),
        ),

        // Aspect Ratio Selector
        if (widget.onAspectRatioChanged != null) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              settings.tr('aspect_ratio'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: ['Auto', '16:9', '4:3', 'Fit', 'Fill'].map((ratio) {
              final isCurrent = widget.currentAspectRatio == ratio;
              return _NeonFocusButton(
                onPressed: () {
                  widget.onAspectRatioChanged!(ratio);
                  setState(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? const Color(0xFF8B5CF6)
                        : const Color(0xFF181728),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrent ? const Color(0xFFA78BFA) : const Color(0xFF26243A),
                    ),
                  ),
                  child: Text(
                    ratio,
                    style: TextStyle(
                      color: isCurrent ? Colors.white : Colors.white70,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildBufferTile({
    required String id,
    required String title,
    required String description,
    required IconData icon,
    required Color accentColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return _NeonFocusButton(
      autofocus: isSelected,
      onPressed: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.15)
              : const Color(0xFF141322),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accentColor : const Color(0xFF22203A),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: accentColor, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Helper button widget providing high-contrast purple neon focus rings for Android TV remote D-Pad navigation.
class _NeonFocusButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onPressed;
  final bool autofocus;

  const _NeonFocusButton({
    required this.child,
    required this.onPressed,
    this.autofocus = false,
  });

  @override
  State<_NeonFocusButton> createState() => _NeonFocusButtonState();
}

class _NeonFocusButtonState extends State<_NeonFocusButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (focus) => setState(() => _isFocused = focus),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: _isFocused
                ? const [
                    BoxShadow(
                      color: Color(0xCC8B5CF6),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
