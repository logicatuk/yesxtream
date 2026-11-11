import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/platform_info.dart';
import '../../data/services/app_settings.dart';
import '../player/player_service.dart';
import '../playlists/playlist_providers.dart';
import '../providers/add_provider_dialog.dart';

/// Top bar shell matching IBO Player Pro style.
/// Replaces the left sidebar menu with top bar navigation tabs (Home, Live, Movies, Series),
/// giving content 100% full width with no redundant sidebars.
class YesShell extends ConsumerStatefulWidget {
  final Widget child;

  const YesShell({super.key, required this.child});

  @override
  ConsumerState<YesShell> createState() => _YesShellState();
}

class _YesShellState extends ConsumerState<YesShell> {
  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final playlistsAsync = ref.watch(allPlaylistsProvider);
    final activePlaylist = ref.watch(activePlaylistProvider);
    final settings = ref.watch(appSettingsProvider);

    // Fullscreen for Home launcher dashboard
    final isHome = location == '/' || location == '/home';
    if (isHome) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Column(
        children: [
          // ── Top Bar with Logo, 4 Tabs, and Right Clock Timer ──
          _buildTopBar(context, location, settings),

          // ── Full-Width Page Content (No left navigation rail) ──
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    String location,
    AppSettings settings,
  ) {
    final isTV = PlatformInfo.isTV || PlatformInfo.isAndroid;
    final scale = PlatformInfo.tvScaleFactor(context);
    final barHeight = isTV ? (58 * scale).clamp(58.0, 110.0) : 58.0;
    final logoSize = (32 * scale).clamp(32.0, 56.0);
    final titleFontSize = (16 * scale).clamp(16.0, 28.0);
    final tabFontSize = (14 * scale).clamp(14.0, 24.0);
    final clockFontSize = (13 * scale).clamp(13.0, 22.0);

    return Container(
      height: barHeight,
      padding: EdgeInsets.symmetric(horizontal: isTV ? 24 : 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D18),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E1E2E), width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 960 || PlatformInfo.isMobile;
          final isVeryCompact = constraints.maxWidth < 500;

          return Row(
            children: [
              // ── 1. Left: Brand Logo & Name ──
              InkWell(
                onTap: () {
                  try {
                    ref.read(playerServiceProvider).stop();
                  } catch (_) {}
                  context.go('/home');
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/icon/yestream.png',
                          width: logoSize,
                          height: logoSize,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (!isVeryCompact) ...[
                        const SizedBox(width: 8),
                        Text(
                          'YESXTREAM',
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),
              Container(height: 18, width: 1, color: const Color(0xFF26243A)),
              const SizedBox(width: 6),

              // ── 2. Navigation Tabs (Home | Live | Movies | Series) ──
              _buildTopTab(
                context: context,
                title: settings.tr('nav_home'),
                route: '/home',
                isSelected: location == '/' || location == '/home',
                fontSize: tabFontSize,
              ),
              _buildTabDivider(),
              _buildTopTab(
                context: context,
                title: settings.tr('nav_live'),
                route: '/live',
                isSelected: location.startsWith('/live'),
                fontSize: tabFontSize,
              ),
              _buildTabDivider(),
              _buildTopTab(
                context: context,
                title: settings.tr('nav_movies'),
                route: '/movies',
                isSelected: location.startsWith('/movies'),
                fontSize: tabFontSize,
              ),
              _buildTabDivider(),
              _buildTopTab(
                context: context,
                title: settings.tr('nav_series'),
                route: '/series',
                isSelected: location.startsWith('/series'),
                fontSize: tabFontSize,
              ),

              // ── 3. Desktop Search & Timer (Hidden on mobile/compact) ──
              if (!isCompact) ...[
                const SizedBox(width: 14),
                InkWell(
                  onTap: () {
                    try {
                      ref.read(playerServiceProvider).stop();
                    } catch (_) {}
                    context.go('/search');
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: constraints.maxWidth < 900 ? 180 : 280,
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161528),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF2A2840)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.search_rounded, size: 16, color: Colors.white54),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Search channels, movies, series...',
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                _ShellClockTimer(fontSize: clockFontSize),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopTab({
    required BuildContext context,
    required String title,
    required String route,
    required bool isSelected,
    double fontSize = 14,
  }) {
    return Focus(
      canRequestFocus: false,
      child: Builder(
        builder: (ctx) {
          final hasFocus = Focus.of(ctx).hasFocus;
          return InkWell(
            onTap: () {
              if (!isSelected) {
                if (route != '/live') {
                  try {
                    ref.read(playerServiceProvider).stop();
                  } catch (_) {}
                }
                context.go(route);
              }
            },
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: hasFocus
                    ? const Color(0xFF6C5CE7).withValues(alpha: 0.28)
                    : Colors.transparent,
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: hasFocus ? 2.0 : 1.5,
                ),
              ),
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFFFFD32A)
                      : (hasFocus ? Colors.white : Colors.white70),
                  fontSize: fontSize,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  shadows: isSelected
                      ? [
                          Shadow(
                            color: const Color(0xFFFFD32A).withValues(alpha: 0.5),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabDivider() {
    return Container(
      height: 14,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.white24,
    );
  }
}

/// Real-time clock timer in HH:mm format for the top bar
class _ShellClockTimer extends StatefulWidget {
  final double fontSize;
  const _ShellClockTimer({this.fontSize = 13});

  @override
  State<_ShellClockTimer> createState() => _ShellClockTimerState();
}

class _ShellClockTimerState extends State<_ShellClockTimer> {
  late Timer _timer;
  String _time = '';

  @override
  void initState() {
    super.initState();
    _update();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _update());
  }

  void _update() {
    if (!mounted) return;
    setState(() {
      _time = DateFormat('HH:mm').format(DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF161528),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF26243A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.access_time_rounded, size: widget.fontSize + 1, color: const Color(0xFF6C5CE7)),
          const SizedBox(width: 6),
          Text(
            _time,
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.fontSize,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
