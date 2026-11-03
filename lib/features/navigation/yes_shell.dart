import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
          _buildTopBar(context, location),

          // ── Full-Width Page Content (No left navigation rail) ──
          Expanded(child: widget.child),
        ],
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    String location,
  ) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D18),
        border: Border(
          bottom: BorderSide(color: Color(0xFF1E1E2E), width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 700;
          final isVeryCompact = constraints.maxWidth < 500;

          return Row(
            children: [
              // ── 1. Left: Brand Logo & Name ──
              InkWell(
                onTap: () => context.go('/home'),
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
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (!isVeryCompact) ...[
                        const SizedBox(width: 8),
                        const Text(
                          'YESXTREAM',
                          style: TextStyle(
                            fontSize: 16,
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
                title: 'Home',
                route: '/home',
                isSelected: location == '/' || location == '/home',
              ),
              _buildTabDivider(),
              _buildTopTab(
                context: context,
                title: 'Live',
                route: '/live',
                isSelected: location.startsWith('/live'),
              ),
              _buildTabDivider(),
              _buildTopTab(
                context: context,
                title: 'Movies',
                route: '/movies',
                isSelected: location.startsWith('/movies'),
              ),
              _buildTabDivider(),
              _buildTopTab(
                context: context,
                title: 'Series',
                route: '/series',
                isSelected: location.startsWith('/series'),
              ),

              // ── 3. Search Bar (Adaptive) ──
              if (isCompact) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search_rounded, size: 20, color: Colors.white70),
                  onPressed: () => context.go('/search'),
                ),
              ] else ...[
                const SizedBox(width: 14),
                InkWell(
                  onTap: () => context.go('/search'),
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
              ],

              const Spacer(),

              // Clock Timer (HH:mm)
              const _ShellClockTimer(),
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
  }) {
    return InkWell(
      onTap: () => context.go(route),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFD32A) : Colors.white70,
            fontSize: 14,
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
  const _ShellClockTimer();

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
          const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF6C5CE7)),
          const SizedBox(width: 6),
          Text(
            _time,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
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
