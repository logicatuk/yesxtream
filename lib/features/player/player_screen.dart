import 'dart:async';
import 'dart:convert';
import '../../core/platform_info.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/local/database.dart' as db;
import '../../data/services/app_settings.dart';
import '../../data/services/pip_service.dart';
import '../../data/services/stream_alternatives_service.dart';
import '../../features/providers/provider_manager.dart' show databaseProvider;
import '../casting/cast_service.dart';
import '../casting/cast_dialog.dart';
import '../channels/channel_debug_dialog.dart';
import 'player_service.dart';
import 'stream_info_badges.dart';
import 'track_selection_hud.dart';

/// Full-screen video player with overlay controls and keyboard navigation.
class PlayerScreen extends ConsumerStatefulWidget {
  final String streamUrl;
  final String channelName;
  final String? channelLogo;
  final List<String> alternativeUrls;
  final List<Map<String, dynamic>> channels;
  final int currentIndex;
  final bool? stopOnExit;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.channelName,
    this.channelLogo,
    this.alternativeUrls = const [],
    this.channels = const [],
    this.currentIndex = 0,
    this.stopOnExit,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showOverlay = true;
  int _currentUrlIndex = 0;
  bool _showChannelList = false;
  bool _isFavorite = false;
  PlayerService? _playerService;

  bool get _shouldStopOnExit => widget.stopOnExit ?? widget.channels.isEmpty;

  // Channel switching state
  late int _channelIndex;
  late String _currentChannelName;
  late String? _currentChannelLogo;

  // Volume state
  double _volume = 100.0;
  bool _showVolumeOverlay = false;
  Timer? _volumeTimer;

  // Overlay timer
  Timer? _overlayTimer;

  // EPG state
  String? _nowPlayingTitle;
  String? _nowPlayingTime;
  String? _nowDescription;
  String? _nextTitle;
  String? _nextTime;
  String? _groupTitle;
  String? _providerName;

  // Favorite lists
  List<db.FavoriteList> _favoriteLists = [];

  // Track selection state
  bool _subtitlesEnabled = false;
  List<SubtitleTrack> _subtitleTracks = [];
  List<AudioTrack> _audioTracks = [];

  static const _aspectRatios = ['Auto', '16:9', '4:3', 'Fit', 'Fill'];
  int _aspectRatioIndex = 0;

  // TV Remote numerical channel jumping state
  String _numberBuffer = '';
  Timer? _numberTimer;

  @override
  void initState() {
    super.initState();
    _playerService = ref.read(playerServiceProvider);
    _channelIndex = widget.currentIndex;
    _currentChannelName = widget.channelName;
    _currentChannelLogo = widget.channelLogo;
    if (widget.channels.isNotEmpty) {
      final ch = widget.channels[_channelIndex];
      _groupTitle = ch['groupTitle']?.toString();
      _providerName = ref.read(streamAlternativesProvider).providerName(ch['providerId']?.toString() ?? '');
    }

    final settings = ref.read(appSettingsProvider);
    final def = settings.defaultAspectRatio;
    if (def.contains('16:9')) {
      _aspectRatioIndex = _aspectRatios.indexOf('16:9');
    } else if (def.contains('4:3')) {
      _aspectRatioIndex = _aspectRatios.indexOf('4:3');
    } else if (def.contains('Fill')) {
      _aspectRatioIndex = _aspectRatios.indexOf('Fill');
    } else if (def.contains('Fit')) {
      _aspectRatioIndex = _aspectRatios.indexOf('Fit');
    }
    if (_aspectRatioIndex < 0) _aspectRatioIndex = 0;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _startPlayback();
    _autoHideOverlay();
    _loadEpgInfo();
    _loadFavoriteState();
  }

  Future<void> _loadFavoriteState() async {
    if (widget.channels.isEmpty) return;
    final ch = widget.channels[_channelIndex];
    final channelId = ch['id'] as String? ?? '';
    if (channelId.isEmpty) return;
    final database = ref.read(databaseProvider);
    final lists = await database.getAllFavoriteLists();
    final listsForChannel = await database.getListsForChannel(channelId);
    if (mounted) {
      setState(() {
        _favoriteLists = lists;
        _isFavorite = listsForChannel.isNotEmpty;
      });
    }
  }

  Future<void> _loadEpgInfo() async {
    if (widget.channels.isEmpty) return;
    final ch = widget.channels[_channelIndex];
    final epgId = ch['epgId'] as String?;
    if (epgId == null || epgId.isEmpty) {
      if (mounted) {
        setState(() {
          _nowPlayingTitle = null;
          _nowPlayingTime = null;
          _nowDescription = null;
          _nextTitle = null;
          _nextTime = null;
        });
      }
      return;
    }

    final database = ref.read(databaseProvider);
    final now = DateTime.now();
    final programmes = await database.getProgrammes(
      epgChannelId: epgId,
      start: now.subtract(const Duration(hours: 1)),
      end: now.add(const Duration(hours: 6)),
    );

    if (!mounted) return;

    db.EpgProgramme? current;
    db.EpgProgramme? next;
    for (final p in programmes) {
      if (now.isAfter(p.start) && now.isBefore(p.stop)) {
        current = p;
      } else if (current != null && next == null && now.isBefore(p.start)) {
        next = p;
        break;
      }
    }

    setState(() {
      _nowPlayingTitle = current?.title;
      _nowPlayingTime = current != null
          ? '${_fmtTime(current.start)} – ${_fmtTime(current.stop)}'
          : null;
      _nowDescription = current?.description;
      _nextTitle = next?.title;
      _nextTime = next != null
          ? '${_fmtTime(next.start)} – ${_fmtTime(next.stop)}'
          : null;
    });
  }

  String _fmtTime(DateTime t) {
    final tod = TimeOfDay.fromDateTime(t);
    final hour = tod.hourOfPeriod == 0 ? 12 : tod.hourOfPeriod;
    final min = tod.minute.toString().padLeft(2, '0');
    final period = tod.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$min $period';
  }

  void _startPlayback() {
    final playerService = ref.read(playerServiceProvider);
    final urls = [widget.streamUrl, ...widget.alternativeUrls];

    // If channels list is empty, this is a show/VOD stream — always start fresh
    final isShowStream = widget.channels.isEmpty;

    if (isShowStream ||
        !(playerService.player.state.playing ||
            playerService.player.state.buffering)) {
      playerService.play(urls[_currentUrlIndex],
        channelId: widget.channels.isNotEmpty ? widget.channels[_channelIndex]['id'] as String? : null,
        epgChannelId: widget.channels.isNotEmpty ? widget.channels[_channelIndex]['epgChannelId'] as String? : null,
        tvgId: widget.channels.isNotEmpty ? widget.channels[_channelIndex]['tvgId'] as String? : null,
        channelName: _currentChannelName,
        vanityName: widget.channels.isNotEmpty ? widget.channels[_channelIndex]['vanityName'] as String? : null,
        originalName: widget.channels.isNotEmpty ? widget.channels[_channelIndex]['tvgName'] as String? : null,
      );
    }

    // Load track info once tracks become available
    playerService.player.stream.tracks.listen((tracks) {
      if (mounted) _loadTrackInfo();
    });

    playerService.bufferingStream.listen((buffering) {
      playerService.onBufferingChanged(buffering);
      if (playerService.shouldFailover && _hasAlternativeStreams) {
        _switchToNextStream();
      }
    });
  }

  bool get _hasAlternativeStreams {
    final urls = [widget.streamUrl, ...widget.alternativeUrls];
    return _currentUrlIndex < urls.length - 1;
  }

  void _switchToNextStream() {
    setState(() => _currentUrlIndex++);
    final urls = [widget.streamUrl, ...widget.alternativeUrls];
    ref.read(playerServiceProvider).play(urls[_currentUrlIndex],
      channelName: _currentChannelName,
    );
  }

  Future<void> _showCastPicker() async {
    final device = await showCastDialog(context, ref);
    if (device != null && mounted) {
      final castService = ref.read(castServiceProvider);
      final urls = [widget.streamUrl, ...widget.alternativeUrls];
      final success = await castService.castTo(
        device,
        urls[_currentUrlIndex],
        title: widget.channelName,
      );
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Casting to ${device.name}'),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {});
      }
    }
  }

  void _loadTrackInfo() {
    final player = ref.read(playerServiceProvider).player;
    final tracks = player.state.tracks;
    setState(() {
      _subtitleTracks = tracks.subtitle
          .where((t) => t.id != 'auto' && t.id != 'no')
          .toList();
      _audioTracks = tracks.audio
          .where((t) => t.id != 'auto' && t.id != 'no')
          .toList();
      _subtitlesEnabled = player.state.track.subtitle.id != 'no' &&
          player.state.track.subtitle.id != 'auto';
    });
  }

  void _toggleSubtitles() {
    final player = ref.read(playerServiceProvider).player;
    if (_subtitlesEnabled) {
      player.setSubtitleTrack(SubtitleTrack.no());
      setState(() => _subtitlesEnabled = false);
    } else if (_subtitleTracks.isNotEmpty) {
      player.setSubtitleTrack(_subtitleTracks.first);
      setState(() => _subtitlesEnabled = true);
    }
  }

  void _showSubtitlePicker() {
    _loadTrackInfo();
    final player = ref.read(playerServiceProvider).player;
    final currentId = player.state.track.subtitle.id;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.closed_caption, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Subtitles', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                dense: true,
                leading: Icon(Icons.block, color: currentId == 'no' ? Colors.greenAccent : Colors.white54, size: 20),
                title: const Text('Off', style: TextStyle(color: Colors.white70, fontSize: 13)),
                trailing: currentId == 'no' ? const Icon(Icons.check, color: Colors.greenAccent, size: 18) : null,
                onTap: () {
                  player.setSubtitleTrack(SubtitleTrack.no());
                  setState(() => _subtitlesEnabled = false);
                  Navigator.of(ctx).pop();
                },
              ),
              ..._subtitleTracks.map((t) {
                final isActive = t.id == currentId;
                return ListTile(
                  dense: true,
                  title: Text(
                    t.title ?? t.language ?? t.id,
                    style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontSize: 13),
                  ),
                  subtitle: t.language != null
                      ? Text(t.language!, style: const TextStyle(color: Colors.white38, fontSize: 11))
                      : null,
                  trailing: isActive ? const Icon(Icons.check, color: Colors.greenAccent, size: 18) : null,
                  onTap: () {
                    player.setSubtitleTrack(t);
                    setState(() => _subtitlesEnabled = true);
                    Navigator.of(ctx).pop();
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showAudioPicker() {
    _loadTrackInfo();
    final player = ref.read(playerServiceProvider).player;
    final currentId = player.state.track.audio.id;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.audiotrack, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Audio Tracks', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              ..._audioTracks.map((t) {
                final isActive = t.id == currentId;
                return ListTile(
                  dense: true,
                  title: Text(
                    t.title ?? t.language ?? t.id,
                    style: TextStyle(color: isActive ? Colors.white : Colors.white70, fontSize: 13),
                  ),
                  subtitle: t.language != null
                      ? Text(t.language!, style: const TextStyle(color: Colors.white38, fontSize: 11))
                      : null,
                  trailing: isActive ? const Icon(Icons.check, color: Colors.greenAccent, size: 18) : null,
                  onTap: () {
                    player.setAudioTrack(t);
                    Navigator.of(ctx).pop();
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _autoHideOverlay() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  void _toggleOverlay() {
    setState(() => _showOverlay = !_showOverlay);
    if (_showOverlay) _autoHideOverlay();
  }

  // ---- Keyboard controls ----

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isTvInput = PlatformInfo.isTV || PlatformInfo.isAndroid;
    if (_showOverlay) _autoHideOverlay();

    // Numerical channel jumping via remote number keys (e.g. 1 0 5 -> jump to channel 105)
    final digit = _getDigitFromKey(key);
    if (digit != null) {
      _appendChannelNumber(digit);
      return KeyEventResult.handled;
    }

    // Select / Enter: if number is being entered, jump immediately!
    // When overlay & channel list are hidden, toggle overlay.
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      if (_numberBuffer.isNotEmpty) {
        _executeNumberJump();
        return KeyEventResult.handled;
      }
      if (!_showOverlay && !_showChannelList) {
        _toggleOverlay();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Escape / Backspace / Back → close channel list or overlay or cancel number input first, then exit
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.goBack) {
      if (_numberBuffer.isNotEmpty) {
        setState(() => _numberBuffer = '');
        _numberTimer?.cancel();
        return KeyEventResult.handled;
      }
      if (_showChannelList) {
        setState(() => _showChannelList = false);
        return KeyEventResult.handled;
      }
      if (_showOverlay && isTvInput) {
        setState(() => _showOverlay = false);
        return KeyEventResult.handled;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_shouldStopOnExit) {
          _playerService?.stop();
        }
        GoRouter.of(context).canPop()
            ? GoRouter.of(context).pop()
            : GoRouter.of(context).go('/');
      });
      return KeyEventResult.handled;
    }

    // Channel switching: use channelUp/Down always, and Up/Down arrows when UI overlay is hidden
    if (key == LogicalKeyboardKey.channelUp ||
        key == LogicalKeyboardKey.pageUp ||
        ((!isTvInput || (!_showOverlay && !_showChannelList)) &&
            key == LogicalKeyboardKey.arrowUp)) {
      _switchChannel(-1);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.channelDown ||
        key == LogicalKeyboardKey.pageDown ||
        ((!isTvInput || (!_showOverlay && !_showChannelList)) &&
            key == LogicalKeyboardKey.arrowDown)) {
      _switchChannel(1);
      return KeyEventResult.handled;
    }

    // Volume on desktop, or reveal overlay/channel list with Left/Right on TV when hidden
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (!isTvInput) {
        _adjustVolume(-5);
        return KeyEventResult.handled;
      }
      if (!_showOverlay && !_showChannelList && widget.channels.isNotEmpty) {
        setState(() => _showChannelList = true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (!isTvInput) {
        _adjustVolume(5);
        return KeyEventResult.handled;
      }
      if (!_showOverlay && !_showChannelList) {
        _toggleOverlay();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.mediaPlayPause ||
        key == LogicalKeyboardKey.mediaPlay ||
        key == LogicalKeyboardKey.mediaPause) {
      _playerService?.player.playOrPause();
      _toggleOverlay();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  String? _getDigitFromKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) return '0';
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) return '1';
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) return '2';
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) return '3';
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) return '4';
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) return '5';
    if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) return '6';
    if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) return '7';
    if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) return '8';
    if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) return '9';
    return null;
  }

  void _appendChannelNumber(String digit) {
    if (_numberBuffer.length < 5) {
      setState(() => _numberBuffer += digit);
    }
    _numberTimer?.cancel();
    _numberTimer = Timer(const Duration(milliseconds: 1500), _executeNumberJump);
  }

  void _executeNumberJump() {
    _numberTimer?.cancel();
    final target = int.tryParse(_numberBuffer);
    final buffer = _numberBuffer;
    setState(() => _numberBuffer = '');
    if (target == null || widget.channels.isEmpty) return;

    // 1. Try matching channel number or tvgId in list
    int targetIndex = widget.channels.indexWhere((c) {
      final numStr = c['channelNumber']?.toString() ?? c['tvgId']?.toString() ?? '';
      return numStr == buffer;
    });

    // 2. If not matched, try 1-based index (e.g. typing 5 jumps to 5th channel)
    if (targetIndex < 0 && target >= 1 && target <= widget.channels.length) {
      targetIndex = target - 1;
    }

    if (targetIndex >= 0 && targetIndex < widget.channels.length) {
      _switchChannel(targetIndex - _channelIndex);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Channel $buffer not found'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFFE84118),
        ),
      );
    }
  }

  void _switchChannel(int delta) {
    if (widget.channels.isEmpty) return;
    setState(() {
      _channelIndex =
          (_channelIndex + delta) % widget.channels.length;
      if (_channelIndex < 0) _channelIndex += widget.channels.length;
      final ch = widget.channels[_channelIndex];
      _currentChannelName = ch['name'] as String? ?? '';
      _currentChannelLogo = ch['tvgLogo'] as String?;
      _groupTitle = ch['groupTitle']?.toString();
      _providerName = ref.read(streamAlternativesProvider).providerName(ch['providerId']?.toString() ?? '');
      _currentUrlIndex = 0;
      _showOverlay = true;
    });
    final ch = widget.channels[_channelIndex];
    ref.read(playerServiceProvider).play(ch['streamUrl'] as String? ?? '',
      channelId: ch['id'] as String?,
      epgChannelId: ch['epgChannelId'] as String?,
      tvgId: ch['tvgId'] as String?,
      channelName: ch['name'] as String?,
    );
    _autoHideOverlay();
    _loadEpgInfo();
    _loadFavoriteState();
  }

  void _adjustVolume(double delta) {
    setState(() {
      _volume = (_volume + delta).clamp(0.0, 100.0);
      _showVolumeOverlay = true;
    });
    ref.read(playerServiceProvider).setVolume(_volume);
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showVolumeOverlay = false);
    });
  }

  @override
  void deactivate() {
    final inPip = ref.read(pipServiceProvider).isInPip;
    if (!inPip && _shouldStopOnExit) {
      _playerService?.stop();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    if (_shouldStopOnExit) {
      try {
        _playerService?.stop();
      } catch (_) {}
    }
    _overlayTimer?.cancel();
    _volumeTimer?.cancel();
    _numberTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerService = ref.watch(playerServiceProvider);
    final isInPip = ref.watch(pipServiceProvider).isInPip;

    // In Picture-in-Picture mode, render clean video without any overlays
    if (isInPip) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: _buildVideoSurface(playerService),
        ),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _shouldStopOnExit) {
          _playerService?.stop();
        }
      },
      child: Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: MouseRegion(
          onHover: (_) {
            if (!_showOverlay) setState(() => _showOverlay = true);
            _autoHideOverlay();
          },
          child: GestureDetector(
            onTap: _toggleOverlay,
            child: Stack(
              fit: StackFit.expand,
              children: [
              // Video — respects aspect ratio setting
              Center(
                child: _buildVideoSurface(playerService),
              ),

              // ── Live Fullscreen Overlay (Screen 10) ──
              if (_showOverlay) ...[
                // Top bar with back button, clock, and quick badges
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black87, Colors.transparent],
                      ),
                    ),
                    child: SafeArea(
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
                            tooltip: 'Exit fullscreen',
                            onPressed: () {
                              if (_shouldStopOnExit) {
                                _playerService?.stop();
                              }
                              GoRouter.of(context).canPop()
                                  ? GoRouter.of(context).pop()
                                  : GoRouter.of(context).go('/live');
                            },
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _currentChannelName,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          StreamInfoBadges(playerService: ref.read(playerServiceProvider)),
                          const SizedBox(width: 8),
                          // Quick PiP trigger
                          IconButton(
                            icon: const Icon(Icons.picture_in_picture_alt_rounded, color: Colors.white70, size: 22),
                            tooltip: 'Picture in Picture',
                            onPressed: () => ref.read(pipServiceProvider).enterPip(),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            TimeOfDay.now().format(context),
                            style: const TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom floating card overlay
                _buildLiveFullscreenCard(context),
              ],

              // TV Remote Numerical Channel Jumping Overlay (Screen 10)
              if (_numberBuffer.isNotEmpty)
                Positioned(
                  top: 36,
                  right: 36,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10101A).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFA78BFA), width: 2.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0xBB8B5CF6),
                          blurRadius: 22,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.dialpad_rounded, color: Color(0xFFA78BFA), size: 26),
                        const SizedBox(width: 10),
                        Text(
                          'CH $_numberBuffer',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Volume overlay
              if (_showVolumeOverlay)
                Positioned(
                  top: 80,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _volume == 0
                              ? Icons.volume_off
                              : _volume < 50
                                  ? Icons.volume_down
                                  : Icons.volume_up,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_volume.round()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Channel list overlay
              if (_showChannelList && widget.channels.isNotEmpty)
                Positioned(
                  right: 0, top: 0, bottom: 0,
                  width: 320,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.85),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(16, 40, 8, 8),
                          child: Row(
                            children: [
                              const Icon(Icons.list, color: Colors.white70, size: 20),
                              const SizedBox(width: 8),
                              const Text('Channels', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                                onPressed: () => setState(() => _showChannelList = false),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white10),
                        Expanded(
                          child: ListView.builder(
                            itemCount: widget.channels.length,
                            itemBuilder: (ctx, i) {
                              final ch = widget.channels[i];
                              final name = ch['name'] as String? ?? '';
                              final isCurrent = i == _channelIndex;
                              return ListTile(
                                autofocus: isCurrent,
                                dense: true,
                                selected: isCurrent,
                                focusColor: const Color(0xFF6C5CE7).withValues(alpha: 0.45),
                                selectedTileColor: const Color(0xFF6C5CE7).withValues(alpha: 0.3),
                                leading: ch['tvgLogo'] != null
                                    ? Image.network(ch['tvgLogo'] as String, width: 28, height: 28, errorBuilder: (_, __, ___) => const Icon(Icons.tv, size: 28, color: Colors.white30))
                                    : const Icon(Icons.tv, size: 28, color: Colors.white30),
                                title: Text(name, style: TextStyle(
                                  color: isCurrent ? Colors.white : Colors.white70,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 13,
                                ), maxLines: 1, overflow: TextOverflow.ellipsis),
                                onTap: () {
                                  setState(() => _showChannelList = false);
                                  if (i != _channelIndex) {
                                    _switchChannel(i - _channelIndex);
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  // ---- Action handlers ----

  Future<void> _takeScreenshot() async {
    final ps = ref.read(playerServiceProvider);
    try {
      final dir = PlatformInfo.isDesktop
          ? (await getDownloadsDirectory()) ?? await getTemporaryDirectory()
          : await getTemporaryDirectory();
      final path = '${dir.path}/clubtivi_screenshot_${DateTime.now().millisecondsSinceEpoch}.png';
      final result = await ps.takeScreenshot(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result != null ? 'Screenshot saved: $path' : 'Screenshot not available')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Screenshot failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _toggleFavorite() {
    if (widget.channels.isEmpty) return;
    final ch = widget.channels[_channelIndex];
    final channelId = ch['id'] as String? ?? '';
    final channelName = ch['name'] as String? ?? '';
    if (channelId.isEmpty) return;
    _showFavoriteListSheet(channelId, channelName);
  }

  Future<void> _showFavoriteListSheet(String channelId, String channelName) async {
    final database = ref.read(databaseProvider);
    final listsForChannel = await database.getListsForChannel(channelId);
    final checkedIds = listsForChannel.map((l) => l.id).toSet();

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Add "$channelName" to list',
                          style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_favoriteLists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text('No favorite lists yet', style: TextStyle(color: Colors.white38)),
                      ),
                    ),
                  ..._favoriteLists.map((list) {
                    final isInList = checkedIds.contains(list.id);
                    return CheckboxListTile(
                      dense: true,
                      value: isInList,
                      activeColor: const Color(0xFFE17055),
                      title: Text('★ ${list.name}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      onChanged: (val) async {
                        if (val == true) {
                          await database.addChannelToList(list.id, channelId);
                          checkedIds.add(list.id);
                        } else {
                          await database.removeChannelFromList(list.id, channelId);
                          checkedIds.remove(list.id);
                        }
                        setSheetState(() {});
                      },
                    );
                  }),
                  const Divider(color: Colors.white12),
                  TextButton.icon(
                    onPressed: () async {
                      final name = await _showCreateListDialog();
                      if (name != null && name.isNotEmpty) {
                        final newList = await database.createFavoriteList(name);
                        await database.addChannelToList(newList.id, channelId);
                        checkedIds.add(newList.id);
                        final updated = await database.getAllFavoriteLists();
                        setState(() => _favoriteLists = updated);
                        setSheetState(() {});
                      }
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Create new list'),
                    style: TextButton.styleFrom(foregroundColor: Colors.cyanAccent),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
    // Refresh favorite state after sheet closes
    final listsAfter = await database.getListsForChannel(channelId);
    if (mounted) {
      setState(() => _isFavorite = listsAfter.isNotEmpty);
    }
  }

  Future<String?> _showCreateListDialog() async {
    String name = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('New Favorite List', style: TextStyle(color: Colors.white)),
        content: TextField(
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'e.g. Sports, News, Kids',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onChanged: (v) => name = v,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(name.trim()), child: const Text('Create')),
        ],
      ),
    );
  }

  Future<void> _enterPip() async {
    // PiP not yet available on desktop — show a message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Picture-in-Picture — available on mobile'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _renameCurrentChannel() async {
    if (widget.channels.isEmpty) return;
    final ch = widget.channels[_channelIndex];
    final channelId = ch['id'] as String?;
    if (channelId == null) return;

    // Load current vanity names
    final prefs = await SharedPreferences.getInstance();
    final vanityJson = prefs.getString('channel_vanity_names');
    Map<String, String> vanityNames = {};
    if (vanityJson != null) {
      try {
        final decoded = jsonDecode(vanityJson) as Map<String, dynamic>;
        vanityNames = decoded.map((k, v) => MapEntry(k, v as String));
      } catch (_) {}
    }

    final originalName = ch['tvgName']?.toString() ?? ch['originalName']?.toString() ?? ch['name']?.toString() ?? '';
    final currentVanity = vanityNames[channelId];
    final controller = TextEditingController(text: currentVanity ?? ch['name']?.toString() ?? originalName);

    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set Display Name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Original: $originalName',
                style: const TextStyle(fontSize: 12, color: Colors.white54)),
            const SizedBox(height: 12),
            TextFormField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Display Name'),
            ),
          ],
        ),
        actions: [
          if (currentVanity != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '\x00RESET'),
              child: const Text('Reset to Original'),
            ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null) return;

    if (result == '\x00RESET') {
      vanityNames.remove(channelId);
    } else if (result.isNotEmpty && result != originalName) {
      vanityNames[channelId] = result;
    } else {
      return;
    }

    await prefs.setString('channel_vanity_names', jsonEncode(vanityNames));

    // Update in-memory channel map and displayed name
    if (!mounted) return;
    setState(() {
      widget.channels[_channelIndex]['vanityName'] =
          vanityNames[channelId];
      widget.channels[_channelIndex]['name'] =
          vanityNames[channelId] ?? originalName;
      _currentChannelName =
          vanityNames[channelId] ?? originalName;
    });
  }

  void _showInfoDialog() {
    if (widget.channels.isEmpty) return;
    try {
      final ch = widget.channels[_channelIndex];
      final channel = db.Channel(
        id: ch['id']?.toString() ?? '',
        providerId: ch['providerId']?.toString() ?? '',
        name: ch['name']?.toString() ?? '',
        groupTitle: ch['groupTitle']?.toString() ?? '',
        streamUrl: ch['streamUrl']?.toString() ?? '',
        streamType: ch['streamType']?.toString() ?? 'live',
        tvgId: ch['tvgId']?.toString(),
        tvgName: ch['tvgName']?.toString(),
        tvgLogo: ch['tvgLogo']?.toString(),
        favorite: false,
        hidden: false,
        sortOrder: 0,
      );
      final ps = ref.read(playerServiceProvider);
      final epgId = ch['epgId']?.toString();
      final alts = ref.read(streamAlternativesProvider).getAlternativeDetails(
        channelId: ch['id']?.toString() ?? '',
        epgChannelId: epgId,
        tvgId: ch['tvgId']?.toString(),
        channelName: ch['name']?.toString(),
        vanityName: ch['vanityName']?.toString(),
        originalName: ch['tvgName']?.toString(),
        excludeUrl: ch['streamUrl']?.toString() ?? '',
      );
      ChannelDebugDialog.show(context, channel, ps,
          mappedEpgId: epgId,
          originalName: ch['tvgName']?.toString() ?? ch['originalName']?.toString() ?? ch['name']?.toString(),
          currentProviderName: ref.read(streamAlternativesProvider).providerName(ch['providerId']?.toString() ?? ''),
          alternatives: alts);
    } catch (e) {
      debugPrint('Error showing info dialog: $e');
    }
  }

  Widget _buildLiveFullscreenCard(BuildContext context) {
    return Positioned(
      bottom: 24,
      left: 24,
      right: 24,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF10101A).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF26243A)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Channel Name on left, LIVE tag on right
            Row(
              children: [
                if (_currentChannelLogo != null && _currentChannelLogo!.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      _currentChannelLogo!,
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.live_tv_rounded,
                        color: Color(0xFF6C5CE7),
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    _currentChannelName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE84118),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE84118).withValues(alpha: 0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.white, size: 8),
                      SizedBox(width: 6),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Row 2: Now: [program title] (left), 21:00-22:00 (right)
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Text(
                        'Now: ',
                        style: TextStyle(
                          color: Color(0xFFA29BFE),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          _nowPlayingTitle ?? 'Live Broadcast',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_nowPlayingTime != null)
                  Text(
                    _nowPlayingTime!,
                    style: const TextStyle(color: Colors.white60, fontSize: 13),
                  ),
              ],
            ),

            // Row 3: Next: [next program]
            if (_nextTitle != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Text(
                    'Next: ',
                    style: TextStyle(
                      color: Colors.white38,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      '$_nextTitle${_nextTime != null ? '  ($_nextTime)' : ''}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),
            const Divider(color: Color(0xFF26243A), height: 1),
            const SizedBox(height: 14),

            // Row 4: Action Buttons: [Channels] [Guide] [Audio] [Subtitles] [Favorite] [More]
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // [Channels]
                  OutlinedButton.icon(
                    onPressed: () {
                      _autoHideOverlay();
                      setState(() => _showChannelList = !_showChannelList);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF2A2840)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.list_rounded, size: 18),
                    label: const Text('Channels', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),

                  // [Guide]
                  OutlinedButton.icon(
                    onPressed: () {
                      _autoHideOverlay();
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                      context.go('/guide');
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF2A2840)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.calendar_month_rounded, size: 18),
                    label: const Text('Guide', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),

                  // [Audio & Subtitles HUD]
                  OutlinedButton.icon(
                    onPressed: () {
                      _autoHideOverlay();
                      TrackSelectionHud.show(
                        context,
                        player: ref.read(playerServiceProvider).player,
                        onPipRequested: () => ref.read(pipServiceProvider).enterPip(),
                        currentAspectRatio: _aspectRatios[_aspectRatioIndex],
                        onAspectRatioChanged: (r) {
                          final idx = _aspectRatios.indexOf(r);
                          if (idx >= 0) setState(() => _aspectRatioIndex = idx);
                        },
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF8B5CF6)),
                      backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18, color: Color(0xFFA78BFA)),
                    label: const Text('Audio & Subs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),

                  // [Favorite]
                  OutlinedButton.icon(
                    onPressed: () {
                      _autoHideOverlay();
                      _toggleFavorite();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _isFavorite ? Colors.amber : Colors.white,
                      side: BorderSide(color: _isFavorite ? Colors.amber.withValues(alpha: 0.5) : const Color(0xFF2A2840)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: Icon(
                      _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 18,
                      color: _isFavorite ? Colors.amber : Colors.white,
                    ),
                    label: Text(
                      _isFavorite ? 'Favorited' : 'Favorite',
                      style: TextStyle(
                        fontSize: 13,
                        color: _isFavorite ? Colors.amber : Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // [More]
                  OutlinedButton.icon(
                    onPressed: () {
                      _autoHideOverlay();
                      _showMoreOptionsSheet(context);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF2A2840)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.more_horiz_rounded, size: 18),
                    label: const Text('More', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreOptionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF141322),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Playback Options',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Color(0xFF6C5CE7)),
                title: const Text('Playback Information', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _showInfoDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.aspect_ratio_rounded, color: Color(0xFF6C5CE7)),
                title: const Text('Aspect Ratio', style: TextStyle(color: Colors.white)),
                trailing: Text(
                  _aspectRatios[_aspectRatioIndex],
                  style: const TextStyle(color: Color(0xFFA29BFE), fontWeight: FontWeight.bold),
                ),
                onTap: () {
                  setState(() {
                    _aspectRatioIndex = (_aspectRatioIndex + 1) % _aspectRatios.length;
                  });
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Aspect Ratio: ${_aspectRatios[_aspectRatioIndex]}'),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_in_picture_alt, color: Color(0xFF6C5CE7)),
                title: const Text('Picture-in-Picture', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _enterPip();
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_rounded, color: Color(0xFF6C5CE7)),
                title: const Text('Settings', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                  context.go('/settings');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoSurface(PlayerService playerService) {
    final mode = _aspectRatios[_aspectRatioIndex];
    if (mode == 'Fill') {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: playerService.player.state.width?.toDouble() ?? 1920,
            height: playerService.player.state.height?.toDouble() ?? 1080,
            child: Video(controller: playerService.videoController, controls: NoVideoControls),
          ),
        ),
      );
    }

    double? ratio;
    if (mode == '16:9') {
      ratio = 16 / 9;
    } else if (mode == '4:3') {
      ratio = 4 / 3;
    } else if (mode == 'Fit') {
      ratio = MediaQuery.of(context).size.aspectRatio;
    } else {
      // Auto: source stream dimensions or fallback to 16:9
      final w = playerService.player.state.width;
      final h = playerService.player.state.height;
      if (w != null && h != null && h > 0) {
        ratio = w / h;
      } else {
        ratio = 16 / 9;
      }
    }

    return AspectRatio(
      aspectRatio: ratio,
      child: Video(controller: playerService.videoController, controls: NoVideoControls),
    );
  }
}
