import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../data/services/app_settings.dart';
import '../../data/services/pip_service.dart';
import '../../data/services/playback_history_service.dart';
import '../player/active_player_registry.dart';
import '../player/track_selection_hud.dart';

class VodPlayerScreen extends ConsumerStatefulWidget {
  final String title;
  final String streamUrl;
  final String streamType; // 'vod' or 'series'
  final String id;
  final String? posterUrl;
  final String? backdropUrl;
  final String? seriesName;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeTitle;
  final Map<String, dynamic>? nextEpisode;
  final int initialPositionMs;

  const VodPlayerScreen({
    super.key,
    required this.title,
    required this.streamUrl,
    required this.streamType,
    required this.id,
    this.posterUrl,
    this.backdropUrl,
    this.seriesName,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeTitle,
    this.nextEpisode,
    this.initialPositionMs = 0,
  });

  @override
  ConsumerState<VodPlayerScreen> createState() => _VodPlayerScreenState();
}

class _VodPlayerScreenState extends ConsumerState<VodPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  bool _showOverlay = true;
  Timer? _overlayTimer;
  Timer? _historyTimer;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _isBuffering = true;

  // Track state
  Tracks _tracks = const Tracks();
  Track _selectedTrack = const Track();

  // End of episode state
  bool _showEndPanel = false;
  int _autoplayCountdown = 5;
  Timer? _countdownTimer;

  // Active playing episode details (can transition to nextEpisode)
  late String _currentTitle;
  late String _currentStreamUrl;
  late String _currentId;
  late String? _currentPosterUrl;
  late String? _currentBackdropUrl;
  late String? _currentSeriesName;
  late int? _currentSeasonNumber;
  late int? _currentEpisodeNumber;
  late String? _currentEpisodeTitle;
  late Map<String, dynamic>? _currentNextEpisode;

  // Aspect ratio options
  final List<String> _aspectRatios = ['Auto', '16:9', '4:3', 'Fit'];
  int _aspectRatioIndex = 0;

  final List<StreamSubscription> _subscriptions = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title;
    _currentStreamUrl = widget.streamUrl;
    _currentId = widget.id;
    _currentPosterUrl = widget.posterUrl;
    _currentBackdropUrl = widget.backdropUrl;
    _currentSeriesName = widget.seriesName;
    _currentSeasonNumber = widget.seasonNumber;
    _currentEpisodeNumber = widget.episodeNumber;
    _currentEpisodeTitle = widget.episodeTitle;
    _currentNextEpisode = widget.nextEpisode;

    _player = Player();
    ActivePlayerRegistry.register(_player);
    _videoController = VideoController(_player);

    _initPlayer();
  }

  void _initPlayer() async {
    final settings = ref.read(appSettingsProvider);
    final useHwAcc = settings.hardwareAcceleration;

    final defaultAr = settings.defaultAspectRatio;
    if (defaultAr.contains('16:9')) {
      _aspectRatioIndex = _aspectRatios.indexOf('16:9');
    } else if (defaultAr.contains('4:3')) {
      _aspectRatioIndex = _aspectRatios.indexOf('4:3');
    } else if (defaultAr.contains('Fill') || defaultAr.contains('Fit')) {
      _aspectRatioIndex = _aspectRatios.indexOf('Fit');
    }
    if (_aspectRatioIndex < 0) _aspectRatioIndex = 0;

    final dynamic np = _player.platform;
    if (np != null && !kIsWeb) {
      try {
        await np.setProperty('user-agent', 'IPTVSmartersPro/1.0.0 (Linux; Android 12)');
        await np.setProperty('http-header-fields', 'User-Agent: IPTVSmartersPro/1.0.0 (Linux; Android 12)');
        await np.setProperty('audio-channels', 'stereo');
        await np.setProperty('audio-normalize-downmix', 'yes');
        if (useHwAcc) {
          if (defaultTargetPlatform == TargetPlatform.android) {
            await np.setProperty('hwdec', 'mediacodec-copy');
          } else if (defaultTargetPlatform == TargetPlatform.macOS) {
            await np.setProperty('hwdec', 'auto-safe');
          }
        } else {
          await np.setProperty('hwdec', 'no');
        }
      } catch (_) {}
    }

    _listenStreams();
    _startPlayback(_currentStreamUrl, widget.initialPositionMs);

    // Save progress periodically
    _historyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _saveCurrentProgress();
    });
  }

  void _listenStreams() {
    _subscriptions.add(_player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    }));

    _subscriptions.add(_player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    }));

    _subscriptions.add(_player.stream.playing.listen((playing) {
      if (mounted) setState(() => _isPlaying = playing);
    }));

    _subscriptions.add(_player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    }));

    _subscriptions.add(_player.stream.error.listen((err) {
      if (mounted && err.isNotEmpty) {
        setState(() {
          _isBuffering = false;
          _errorMessage = err;
        });
      }
    }));

    _subscriptions.add(_player.stream.tracks.listen((tracks) {
      if (mounted) {
        setState(() => _tracks = tracks);
        _applyPreferredTracks(tracks);
      }
    }));

    _subscriptions.add(_player.stream.track.listen((track) {
      if (mounted) setState(() => _selectedTrack = track);
    }));

    _subscriptions.add(_player.stream.completed.listen((completed) {
      if (completed && mounted) {
        // Only trigger completion if the video actually loaded and reached near the end.
        // Prevents stale completion events from previous stream/stop() calls from aborting playback.
        if (_duration > const Duration(seconds: 10) &&
            _position >= _duration - const Duration(seconds: 5)) {
          _handleStreamCompleted();
        }
      }
    }));
  }

  void _applyPreferredTracks(Tracks tracks) {
    final settings = ref.read(appSettingsProvider);
    // Subtitles preference
    if (settings.subtitleMode == 'Off') {
      _player.setSubtitleTrack(SubtitleTrack.no());
    } else if (settings.subtitleMode == 'On' || settings.subtitleMode == 'Auto') {
      final preferredLang = settings.preferredSubtitleLanguage.toLowerCase();
      final match = tracks.subtitle.firstWhere(
        (t) => (t.language ?? '').toLowerCase().contains(preferredLang),
        orElse: () => SubtitleTrack.no(),
      );
      if (match.id != 'no' && match.id != 'auto') {
        _player.setSubtitleTrack(match);
      }
    }

    // Audio preference
    final prefAudio = settings.preferredAudioLanguage.toLowerCase();
    final audioMatch = tracks.audio.firstWhere(
      (t) => (t.language ?? '').toLowerCase().contains(prefAudio),
      orElse: () => AudioTrack.auto(),
    );
    if (audioMatch.id != 'auto') {
      _player.setAudioTrack(audioMatch);
    }
  }

  Future<void> _startPlayback(String url, int initialMs) async {
    if (url.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _isBuffering = false;
          _errorMessage = 'Stream URL is not available for this title.';
        });
      }
      return;
    }

    try {
      await _player.setVolume(100.0);
      await _player.open(Media(
        url,
        httpHeaders: const {
          'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)',
        },
      ));
      if (initialMs > 1000) {
        // Wait for media duration to load before seeking to avoid seeking beyond 0 / EOF
        _player.stream.duration.firstWhere((d) => d > Duration.zero).then((dur) async {
          if (mounted && initialMs < dur.inMilliseconds - 2000) {
            await _player.seek(Duration(milliseconds: initialMs));
          }
        }).catchError((_) {});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isBuffering = false;
          _errorMessage = 'Playback error: $e';
        });
      }
    }
    _resetOverlayTimer();
  }

  void _handleStreamCompleted() {
    _saveCurrentProgress();
    if (_currentNextEpisode != null) {
      final autoplay = ref.read(appSettingsProvider).autoplayNextEpisode;
      setState(() {
        _showEndPanel = true;
        _autoplayCountdown = 5;
      });
      if (autoplay) {
        _countdownTimer?.cancel();
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (!mounted) {
            timer.cancel();
            return;
          }
          if (_autoplayCountdown <= 1) {
            timer.cancel();
            _playNextEpisode();
          } else {
            setState(() => _autoplayCountdown--);
          }
        });
      }
    }
  }

  void _playNextEpisode() {
    _countdownTimer?.cancel();
    if (_currentNextEpisode == null) return;

    final next = _currentNextEpisode!;
    setState(() {
      _showEndPanel = false;
      _currentTitle = next['title'] as String? ?? 'Next Episode';
      _currentStreamUrl = next['streamUrl'] as String? ?? '';
      _currentId = next['id'] as String? ?? '${widget.id}_next';
      _currentPosterUrl = next['posterUrl'] as String? ?? _currentPosterUrl;
      _currentBackdropUrl = next['backdropUrl'] as String? ?? _currentBackdropUrl;
      _currentSeasonNumber = next['seasonNumber'] as int? ?? _currentSeasonNumber;
      _currentEpisodeNumber = next['episodeNumber'] as int? ?? (_currentEpisodeNumber != null ? _currentEpisodeNumber! + 1 : 1);
      _currentEpisodeTitle = next['episodeTitle'] as String? ?? next['title'] as String?;
      _currentNextEpisode = next['nextEpisode'] as Map<String, dynamic>?;
    });

    _startPlayback(_currentStreamUrl, 0);
  }

  void _saveCurrentProgress() {
    if (!mounted) return;
    if (_duration.inMilliseconds > 0 && _position.inMilliseconds > 0) {
      try {
        ref.read(watchHistoryProvider.notifier).saveProgress(
              id: _currentId,
              title: _currentTitle,
              posterUrl: _currentPosterUrl,
              backdropUrl: _currentBackdropUrl,
              streamUrl: _currentStreamUrl,
              streamType: widget.streamType,
              positionMs: _position.inMilliseconds,
              durationMs: _duration.inMilliseconds,
              seriesName: _currentSeriesName,
              seasonNumber: _currentSeasonNumber,
              episodeNumber: _currentEpisodeNumber,
            );
      } catch (_) {}
    }
  }

  void _resetOverlayTimer() {
    _overlayTimer?.cancel();
    setState(() => _showOverlay = true);
    _overlayTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _isPlaying && !_showEndPanel) {
        setState(() => _showOverlay = false);
      }
    });
  }

  void _toggleOverlay() {
    if (_showOverlay) {
      _overlayTimer?.cancel();
      setState(() => _showOverlay = false);
    } else {
      _resetOverlayTimer();
    }
  }

  void _seekBy(int seconds) {
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _player.seek(clamped);
    _resetOverlayTimer();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();
    _overlayTimer?.cancel();
    _countdownTimer?.cancel();
    _saveCurrentProgress();
    ActivePlayerRegistry.unregister(_player);
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isInPip = ref.watch(pipServiceProvider).isInPip;

    if (isInPip) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: AspectRatio(
            aspectRatio: _getEffectiveAspectRatio(),
            child: Video(controller: _videoController),
          ),
        ),
      );
    }

    final titleLine = widget.streamType == 'series' && _currentSeriesName != null
        ? '$_currentSeriesName • S${_currentSeasonNumber ?? 1} E${_currentEpisodeNumber ?? 1}${_currentEpisodeTitle != null ? ' - $_currentEpisodeTitle' : ''}'
        : _currentTitle;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_showEndPanel) {
            _countdownTimer?.cancel();
            setState(() => _showEndPanel = false);
          } else {
            Navigator.of(context).maybePop();
          }
        },
        const SingleActivator(LogicalKeyboardKey.space): () {
          _player.playOrPause();
          _resetOverlayTimer();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _seekBy(-10),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _seekBy(10),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: _toggleOverlay,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // ── Video Surface ──
                Center(
                  child: AspectRatio(
                    aspectRatio: _getEffectiveAspectRatio(),
                    child: Video(controller: _videoController),
                  ),
                ),

                // ── Buffering Indicator ──
                if (_isBuffering && !_showEndPanel && _errorMessage == null)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF6C5CE7),
                    ),
                  ),

                // ── Error Message ──
                if (_errorMessage != null)
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      margin: const EdgeInsets.all(24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141322),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                          const SizedBox(height: 12),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                          ),
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF6C5CE7),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.arrow_back, size: 16),
                            label: const Text('Go Back'),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Overlay UI ──
                AnimatedOpacity(
                  opacity: _showOverlay ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_showOverlay,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.8),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.88),
                          ],
                          stops: const [0.0, 0.25, 0.7, 1.0],
                        ),
                      ),
                      child: SafeArea(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // ── Top Header ──
                            _buildTopHeader(titleLine),

                            // ── Bottom Controls ──
                            _buildBottomControls(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Screen 19: End-of-Episode Panel ──
                if (_showEndPanel && _currentNextEpisode != null)
                  _buildEndEpisodePanel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _getEffectiveAspectRatio() {
    switch (_aspectRatios[_aspectRatioIndex]) {
      case '16:9':
        return 16 / 9;
      case '4:3':
        return 4 / 3;
      case 'Fit':
        return MediaQuery.of(context).size.aspectRatio;
      default:
        final w = _player.state.width;
        final h = _player.state.height;
        if (w != null && h != null && h > 0) return w / h;
        return 16 / 9;
    }
  }

  Widget _buildTopHeader(String titleLine) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
            onPressed: () {
              _saveCurrentProgress();
              Navigator.of(context).maybePop();
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titleLine,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.streamType == 'series' && _currentTitle.isNotEmpty)
                  Text(
                    _currentTitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Aspect ratio toggle
          TextButton.icon(
            onPressed: () {
              setState(() {
                _aspectRatioIndex = (_aspectRatioIndex + 1) % _aspectRatios.length;
              });
              _resetOverlayTimer();
            },
            icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white70, size: 18),
            label: Text(
              _aspectRatios[_aspectRatioIndex],
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          // Picture-in-Picture button
          IconButton(
            icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white70, size: 22),
            tooltip: 'Picture in Picture',
            onPressed: () => ref.read(pipServiceProvider).enterPip(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final posMs = _position.inMilliseconds.toDouble();
    final durMs = _duration.inMilliseconds.toDouble();
    final progress = durMs > 0 ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Scrub progress bar ──
          Row(
            children: [
              Text(
                _formatDuration(_position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF6C5CE7),
                    inactiveTrackColor: Colors.white24,
                    thumbColor: const Color(0xFFA29BFE),
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (val) {
                      _resetOverlayTimer();
                      final targetMs = (val * durMs).toInt();
                      _player.seek(Duration(milliseconds: targetMs));
                    },
                  ),
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Playback buttons ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rewind -10s
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 30),
                tooltip: 'Rewind 10s',
                onPressed: () => _seekBy(-10),
              ),
              const SizedBox(width: 16),

              // Play / Pause
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF6C5CE7),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  iconSize: 36,
                  icon: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    _player.playOrPause();
                    _resetOverlayTimer();
                  },
                ),
              ),
              const SizedBox(width: 16),

              // Fast Forward +10s
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 30),
                tooltip: 'Forward 10s',
                onPressed: () => _seekBy(10),
              ),

              const Spacer(),

              // Quick HUD (Audio, Subtitles, Buffering, Presets)
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: Color(0xFFA78BFA)),
                tooltip: 'Audio & Subtitle HUD',
                onPressed: () {
                  TrackSelectionHud.show(
                    context,
                    player: _player,
                    onPipRequested: () => ref.read(pipServiceProvider).enterPip(),
                    currentAspectRatio: _aspectRatios[_aspectRatioIndex],
                    onAspectRatioChanged: (r) {
                      final idx = _aspectRatios.indexOf(r);
                      if (idx >= 0) setState(() => _aspectRatioIndex = idx);
                    },
                  );
                },
              ),

              // Audio Drawer button (Screen 17)
              IconButton(
                icon: const Icon(Icons.audiotrack_rounded, color: Colors.white70),
                tooltip: 'Audio Tracks',
                onPressed: () => _openAudioDrawer(context),
              ),

              // Subtitles Drawer button (Screen 18)
              IconButton(
                icon: const Icon(Icons.subtitles_rounded, color: Colors.white70),
                tooltip: 'Subtitles',
                onPressed: () => _openSubtitlesDrawer(context),
              ),

              // Next Episode button (Series only)
              if (widget.streamType == 'series' && _currentNextEpisode != null)
                IconButton(
                  icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                  tooltip: 'Next Episode',
                  onPressed: _playNextEpisode,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Screen 17: Audio Drawer ──
  void _openAudioDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141322),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final audioTracks = _tracks.audio;
        final currentAudio = _selectedTrack.audio;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Audio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      audioTracks.isEmpty
                          ? 'Detecting audio tracks…'
                          : audioTracks.length == 1
                              ? '1 available track'
                              : '${audioTracks.length} tracks available',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFF26253D), height: 24),
                if (audioTracks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Detecting audio tracks…',
                        style: TextStyle(color: Colors.white60),
                      ),
                    ),
                  )
                else
                  ...audioTracks.map((track) {
                    final label = (track.title?.isNotEmpty == true
                            ? track.title!
                            : (track.language?.isNotEmpty == true
                                ? track.language!
                                : 'Audio track ${audioTracks.indexOf(track) + 1}'))
                        .toUpperCase();

                    final isSelected = currentAudio.id == track.id;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        color: isSelected ? const Color(0xFF6C5CE7) : Colors.white38,
                      ),
                      title: Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: track.channels != null
                          ? Text('${track.channels} channels • ${track.bitrate ?? ''} bps',
                              style: const TextStyle(color: Colors.white38, fontSize: 12))
                          : null,
                      onTap: () {
                        _player.setAudioTrack(track);
                        Navigator.pop(ctx);
                        _resetOverlayTimer();
                      },
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Screen 18: Subtitle Drawer ──
  void _openSubtitlesDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141322),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final subTracks = _tracks.subtitle;
        final currentSub = _selectedTrack.subtitle;
        final isOff = currentSub.id == 'no';

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Subtitles',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(color: Color(0xFF26253D), height: 24),
                // Off option
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    isOff ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: isOff ? const Color(0xFF6C5CE7) : Colors.white38,
                  ),
                  title: Text(
                    'Off',
                    style: TextStyle(
                      color: isOff ? Colors.white : Colors.white70,
                      fontWeight: isOff ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  onTap: () {
                    _player.setSubtitleTrack(SubtitleTrack.no());
                    Navigator.pop(ctx);
                    _resetOverlayTimer();
                  },
                ),
                if (subTracks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No selectable subtitles available.',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  )
                else
                  ...subTracks.map((track) {
                    if (track.id == 'no') return const SizedBox.shrink();
                    final label = (track.title?.isNotEmpty == true
                            ? track.title!
                            : (track.language?.isNotEmpty == true
                                ? track.language!
                                : 'Subtitle track ${subTracks.indexOf(track) + 1}'))
                        .toUpperCase();

                    final isSelected = !isOff && currentSub.id == track.id;

                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        color: isSelected ? const Color(0xFF6C5CE7) : Colors.white38,
                      ),
                      title: Text(
                        label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      onTap: () {
                        _player.setSubtitleTrack(track);
                        Navigator.pop(ctx);
                        _resetOverlayTimer();
                      },
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Screen 19: End-of-Episode Panel ──
  Widget _buildEndEpisodePanel() {
    final next = _currentNextEpisode!;
    final nextTitle = next['title'] as String? ?? 'Episode';
    final seasonNum = next['seasonNumber'] ?? _currentSeasonNumber ?? 1;
    final epNum = next['episodeNumber'] ?? (_currentEpisodeNumber != null ? _currentEpisodeNumber! + 1 : 1);

    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Card(
        color: const Color(0xFF1A192A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF333152), width: 1.5),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Next Episode',
                style: TextStyle(
                  color: Color(0xFFA29BFE),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Season $seasonNum • Episode $epNum: $nextTitle',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (ref.read(appSettingsProvider).autoplayNextEpisode)
                Text(
                  'Autoplay in $_autoplayCountdown s…',
                  style: const TextStyle(color: Colors.white60, fontSize: 14),
                ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      _countdownTimer?.cancel();
                      setState(() => _showEndPanel = false);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: _playNextEpisode,
                    icon: const Icon(Icons.play_arrow_rounded, size: 20),
                    label: const Text('Play Next Episode'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
