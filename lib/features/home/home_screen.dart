import 'dart:io' as io show exit;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/platform_info.dart';
import '../../core/tv_exit_helper.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/services/app_settings.dart';
import '../../data/services/app_update_service.dart';
import '../../data/services/device_identity_service.dart';
import '../../data/services/device_sync_service.dart';
import '../playlists/playlist_providers.dart';
import '../providers/add_provider_dialog.dart';
import '../providers/provider_manager.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isReloading = false;
  static bool _hasAutoRefreshedOnStartup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoRefreshOnStartup();
    });
  }

  Future<void> _checkAutoRefreshOnStartup() async {
    if (_hasAutoRefreshedOnStartup) return;
    final settings = ref.read(appSettingsProvider);
    if (!settings.autoRefreshOnStartup) return;

    final activePlaylist = ref.read(activePlaylistProvider);
    if (activePlaylist != null) {
      _hasAutoRefreshedOnStartup = true;
      try {
        final manager = ref.read(providerManagerProvider);
        await manager.refreshProvider(activePlaylist.id);
        ref.invalidate(activePlaylistStatsProvider);
        ref.invalidate(activePlaylistAccountInfoProvider);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePlaylist = ref.watch(activePlaylistProvider);
    final playlistsAsync = ref.watch(allPlaylistsProvider);
    final accountInfoAsync = ref.watch(activePlaylistAccountInfoProvider);
    final statsAsync = ref.watch(activePlaylistStatsProvider);
    final settings = ref.watch(appSettingsProvider);

    void handleHomeBack() {
      if (ModalRoute.of(context)?.isCurrent != true) return;
      _showExitDialog(context, settings);
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) handleHomeBack();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): handleHomeBack,
          const SingleActivator(LogicalKeyboardKey.goBack): handleHomeBack,
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF070712),
      body: playlistsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
        ),
        error: (err, _) => Center(
          child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
        ),
        data: (playlists) {
          if (playlists.isEmpty) {
            return _buildEmptyState(context, settings);
          }

          final accountInfo = accountInfoAsync.value;
          final stats = statsAsync.value ?? const PlaylistStats();

          return Stack(
            children: [
              // ── Background Gradient & Vignette (App Signature Palette) ──
              Positioned.fill(
                child: RepaintBoundary(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF070716), // Deep midnight navy
                                Color(0xFF0F0E26), // Dark royal purple
                                Color(0xFF141232), // Rich indigo
                                Color(0xFF080712), // Dark bottom
                              ],
                              stops: [0.0, 0.4, 0.75, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Soft ambient purple radial glow in the center
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0.0, 0.1),
                              radius: 0.85,
                              colors: [
                                const Color(0xFF6C5CE7).withValues(alpha: 0.14),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Main Layout ──
              SafeArea(
                left: false,
                right: false,
                top: false,
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isLandscape = constraints.maxWidth > constraints.maxHeight;

                    if (!isLandscape) {
                      return _buildCompactLayout(
                        context,
                        activePlaylist,
                        accountInfo,
                        stats,
                        settings,
                      );
                    }

                    final isShortHeight = constraints.maxHeight < 480;
                    final maxW = (constraints.maxWidth * 0.86).clamp(320.0, 1650.0);
                    final maxH = (constraints.maxHeight * 0.64).clamp(180.0, 580.0);
                    final dashScale = math.min(maxW / 940.0, maxH / 255.0);

                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: constraints.maxWidth < 800 ? 16 : 32,
                        vertical: isShortHeight ? 6 : 16,
                      ),
                      child: Column(
                        children: [
                          // ── Top Header (Logo center, Expiry right) ──
                          _buildHeader(activePlaylist, accountInfo, settings, isShort: isShortHeight),

                          // ── Center Main Dashboard (Auto-scaled to fit any screen size) ──
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                width: 940.0 * dashScale,
                                height: 255.0 * dashScale,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  alignment: Alignment.center,
                                  child: MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                      textScaler: TextScaler.noScaling,
                                    ),
                                    child: SizedBox(
                                      width: 940,
                                      height: 255,
                                      child: _buildLandscapeDashboard(
                                        context,
                                        activePlaylist,
                                        accountInfo,
                                        stats,
                                        settings,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // ── Bottom Version Tag ──
                          _buildFooter(),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ── Header (Logo centered, Expiry info on top right)
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(
    db.Provider? playlist,
    AccountInfo? accountInfo,
    AppSettings settings, {
    bool isShort = false,
  }) {
    String expiryText;
    if (accountInfo?.expDate != null) {
      final dateStr = DateFormat('dd/MM/yyyy').format(accountInfo!.expDate!);
      expiryText = '${settings.tr('account_expires')} $dateStr';
    } else if (playlist != null) {
      expiryText = '${settings.tr('playlists_count')}: ${playlist.name}';
    } else {
      expiryText = '';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        if (isNarrow) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _BrandLogo(),
                  if (expiryText.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        expiryText,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return SizedBox(
          height: isShort ? 42 : 60,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Center(child: _BrandLogo()),
              if (expiryText.isNotEmpty)
                Positioned(
                  right: 0,
                  child: Text(
                    expiryText,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ── Landscape Dashboard (Hero TV + 5 Grid Tiles + 3 Actions)
  // ─────────────────────────────────────────────────────────────
  Widget _buildLandscapeDashboard(
    BuildContext context,
    db.Provider? activePlaylist,
    AccountInfo? accountInfo,
    PlaylistStats stats,
    AppSettings settings,
  ) {
    const totalHeight = 255.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // ── 1. Big Hero Tile: "Live TV" ──
        SizedBox(
          width: 250,
          height: totalHeight,
          child: _TvHeroTile(
            title: settings.tr('live_tv'),
            onTap: () => context.go('/live'),
          ),
        ),

        const SizedBox(width: 16),

        // ── 2. Center Grid: 5 Action Tiles in Purple App Theme ──
        SizedBox(
          width: 440,
          height: totalHeight,
          child: Column(
            children: [
              // Row 1: [ Films ] [ Séries ] [ Catch-up ]
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _TvGridTile(
                        title: settings.tr('movies'),
                        icon: Icons.play_circle_outline_rounded,
                        onTap: () => context.go('/movies'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _TvGridTile(
                        title: settings.tr('series'),
                        icon: Icons.movie_creation_outlined,
                        onTap: () => context.go('/series'),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _TvGridTile(
                        title: settings.tr('catchup_tv'),
                        icon: Icons.replay_rounded,
                        badgeText: 'REPLAY',
                        onTap: () => context.go('/catchup'),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Row 2: [ Compte ] [ Changer la liste de lecture ]
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: _TvGridTile(
                        title: settings.tr('account_details'),
                        icon: Icons.people_alt_outlined,
                        onTap: () => _showAccountDialog(
                          context,
                          activePlaylist,
                          accountInfo,
                          stats,
                          settings,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 1,
                      child: _TvGridTile(
                        title: settings.tr('switch_playlist'),
                        icon: Icons.switch_account_outlined,
                        onTap: () => _showPlaylistSwitcher(context, settings),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 16),

        // ── 3. Right Action Buttons: Paramètres, Recharger, QUITTER ──
        SizedBox(
          width: 215,
          height: totalHeight,
          child: Column(
            children: [
              Expanded(
                child: _TvActionButton(
                  title: settings.tr('settings'),
                  icon: Icons.settings_outlined,
                  onTap: () => context.go('/settings'),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _TvActionButton(
                  title: settings.tr('refresh_playlist'),
                  icon: Icons.refresh_rounded,
                  isLoading: _isReloading,
                  onTap: () => _handleReload(activePlaylist, settings),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _TvActionButton(
                  title: settings.tr('exit_dialog_confirm'),
                  icon: Icons.logout_rounded,
                  isExit: true,
                  onTap: () => _showExitDialog(context, settings),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ── Compact / Mobile Layout
  // ─────────────────────────────────────────────────────────────
  Widget _buildCompactLayout(
    BuildContext context,
    db.Provider? activePlaylist,
    AccountInfo? accountInfo,
    PlaylistStats stats,
    AppSettings settings,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        final hPad = availableWidth < 380 ? 12.0 : 16.0;

        // Adaptive spacing based on screen height
        final isVeryTall = availableHeight > 800;
        final isShort = availableHeight < 640;
        final gap = isVeryTall ? 12.0 : (isShort ? 7.0 : 10.0);
        final topPad = isShort ? 12.0 : (isVeryTall ? 26.0 : 18.0);
        final bottomPad = isShort ? 8.0 : 14.0;

        return Padding(
          padding: EdgeInsets.fromLTRB(hPad, topPad, hPad, bottomPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header: Logo + expiry pill, horizontally centered with comfortable top room ──
              _buildHeader(activePlaylist, accountInfo, settings),
              SizedBox(height: gap),

              // ── 1. Hero: Live TV ──
              Expanded(
                flex: 13,
                child: _TvHeroTile(
                  title: settings.tr('live_tv'),
                  isCompact: isShort,
                  onTap: () => context.go('/live'),
                ),
              ),
              SizedBox(height: gap),

              // ── 2. Row 1: Movies & Series ──
              Expanded(
                flex: 9,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _TvGridTile(
                        title: settings.tr('movies'),
                        icon: Icons.play_circle_outline_rounded,
                        onTap: () => context.go('/movies'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TvGridTile(
                        title: settings.tr('series'),
                        icon: Icons.movie_creation_outlined,
                        onTap: () => context.go('/series'),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: gap),

              // ── 3. Row 2: Catchup TV & Account Details ──
              Expanded(
                flex: 9,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _TvGridTile(
                        title: settings.tr('catchup_tv'),
                        icon: Icons.replay_rounded,
                        badgeText: 'REPLAY',
                        onTap: () => context.go('/catchup'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TvGridTile(
                        title: settings.tr('account_details'),
                        icon: Icons.people_alt_outlined,
                        onTap: () => _showAccountDialog(
                          context,
                          activePlaylist,
                          accountInfo,
                          stats,
                          settings,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: gap),

              // ── 4. Switch Playlist: horizontal layout (icon left, text right) ──
              Expanded(
                flex: 5,
                child: _TvGridTileHorizontal(
                  title: settings.tr('switch_playlist'),
                  icon: Icons.switch_account_outlined,
                  onTap: () => _showPlaylistSwitcher(context, settings),
                ),
              ),
              SizedBox(height: gap),

              // ── 5. Action Buttons Row: Settings, Refresh, Exit ──
              Expanded(
                flex: 4,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _TvActionButton(
                        title: settings.tr('settings'),
                        icon: Icons.settings_outlined,
                        onTap: () => context.go('/settings'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TvActionButton(
                        title: settings.tr('refresh_playlist'),
                        icon: Icons.refresh_rounded,
                        isLoading: _isReloading,
                        onTap: () => _handleReload(activePlaylist, settings),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TvActionButton(
                        title: settings.tr('exit_dialog_confirm'),
                        icon: Icons.logout_rounded,
                        isExit: true,
                        onTap: () => _showExitDialog(context, settings),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isVeryTall ? 6.0 : 4.0),

              // ── Footer version tag ──
              _buildFooter(),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ── Footer
  // ─────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Align(
      alignment: Alignment.bottomRight,
      child: Text(
        'v${AppUpdateService.currentVersion}',
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────
  // ── Empty State
  // ─────────────────────────────────────────────────────────────
  Widget _buildEmptyState(BuildContext context, AppSettings settings) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _BrandLogo(),
            const SizedBox(height: 36),
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
                ),
              ),
              child: const Icon(
                Icons.tv_rounded,
                size: 42,
                color: Color(0xFF6C5CE7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              settings.tr('add_playlist'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              settings.tr('onboarding_hint'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.white60),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              autofocus: true,
              onPressed: () => showAddProviderDialog(context),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                padding:
                    const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ).copyWith(
                side: WidgetStateProperty.resolveWith(
                  (states) => states.contains(WidgetState.focused)
                      ? const BorderSide(color: Colors.white, width: 3)
                      : null,
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(
                settings.tr('add_playlist'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ── Reload Handler
  // ─────────────────────────────────────────────────────────────
  Future<void> _handleReload(db.Provider? playlist, AppSettings settings) async {
    if (playlist == null || _isReloading) return;

    setState(() => _isReloading = true);

    try {
      final manager = ref.read(providerManagerProvider);
      final count = await manager.refreshProvider(playlist.id);
      ref.invalidate(activePlaylistStatsProvider);
      ref.invalidate(activePlaylistAccountInfoProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF161528),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF00B894)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${settings.tr('refresh_playlist')} ($count)',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFF26243A)),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            content: Text('Erreur: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isReloading = false);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // ── Account Dialog ("Compte")
  // ─────────────────────────────────────────────────────────────
  void _showAccountDialog(
    BuildContext context,
    db.Provider? playlist,
    AccountInfo? info,
    PlaylistStats stats,
    AppSettings settings,
  ) {
    if (playlist == null) return;

    final expiryFormatted = info?.expDate != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(info!.expDate!)
        : 'Unlimited';

    final identity = ref.read(deviceIdentityProvider).value;
    final entitlement = ref.read(deviceEntitlementProvider);
    final isRegistered = identity?.serverRegistered == true && identity?.deviceKey != null;
    final mac = identity?.macAddress ?? '—';
    final key = isRegistered ? identity!.deviceKey! : 'Not synced';
    final licenseStatus = isRegistered ? entitlement.formattedStatusBadge : 'Not synced with server';
    final licenseExpiry = entitlement.expiresAt != null
        ? DateFormat('dd/MM/yyyy').format(entitlement.expiresAt!)
        : (entitlement.trialEndsAt != null
            ? DateFormat('dd/MM/yyyy').format(entitlement.trialEndsAt!)
            : 'Unlimited');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 440,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF121124),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF6C5CE7).withValues(alpha: 0.5),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C5CE7).withValues(alpha: 0.25),
                blurRadius: 30,
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C5CE7).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.account_circle_outlined,
                        color: Color(0xFF6C5CE7),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        settings.tr('account_details'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const Divider(color: Color(0xFF22203A), height: 28),

                _buildInfoRow(
                  'Profile',
                  playlist.name,
                ),
                _buildInfoRow(
                  'Type',
                  playlist.type.toUpperCase(),
                ),
                if (playlist.username != null && playlist.username!.isNotEmpty)
                  _buildInfoRow(
                    'Username',
                    playlist.username!,
                  ),
                _buildInfoRow(
                  settings.tr('account_status'),
                  info?.status ?? settings.tr('account_active'),
                  valueColor: const Color(0xFF00B894),
                ),
                _buildInfoRow(
                  settings.tr('account_expires'),
                  expiryFormatted,
                  valueColor: const Color(0xFFA29BFE),
                ),
                if (info?.maxConnections != null)
                  _buildInfoRow(
                    'Max Connections',
                    '${info!.maxConnections}',
                  ),

                const Divider(color: Color(0xFF22203A), height: 24),

                // Device & App License
                Row(
                  children: const [
                    Icon(Icons.devices_rounded, size: 16, color: Color(0xFFA29BFE)),
                    SizedBox(width: 8),
                    Text(
                      'Device & App License',
                      style: TextStyle(
                        color: Color(0xFFA29BFE),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildInfoRow('Device MAC', mac),
                _buildInfoRow('Device Key', key),
                _buildInfoRow(
                  'License Status',
                  licenseStatus,
                  valueColor: entitlement.isActive
                      ? const Color(0xFF00B894)
                      : (entitlement.isExpired ? Colors.redAccent : Colors.amberAccent),
                ),
                _buildInfoRow(
                  'License Expiry',
                  licenseExpiry,
                  valueColor: entitlement.isActive ? const Color(0xFF00B894) : Colors.amberAccent,
                ),

                const Divider(color: Color(0xFF22203A), height: 24),

                // Content stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatPill(settings.tr('live_tv'), '${stats.liveCount}'),
                    _buildStatPill(settings.tr('movies'), '${stats.moviesCount}'),
                    _buildStatPill(settings.tr('series'), '${stats.seriesCount}'),
                  ],
                ),

                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    autofocus: true,
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ).copyWith(
                      side: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.focused)
                            ? const BorderSide(color: Colors.white, width: 2.5)
                            : null,
                      ),
                    ),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String count) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ── Playlist Switcher Dialog ("Changer la liste de lecture")
  // ─────────────────────────────────────────────────────────────
  void _showPlaylistSwitcher(BuildContext context, AppSettings settings) {
    showDialog(
      context: context,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final playlistsAsync = ref.watch(allPlaylistsProvider);
          final activePlaylist = ref.watch(activePlaylistProvider);

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 480,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFF121124),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C5CE7).withValues(alpha: 0.25),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.playlist_play_rounded,
                        color: Color(0xFF6C5CE7),
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          settings.tr('switch_playlist'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white60),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(color: Color(0xFF22203A), height: 20),

                  playlistsAsync.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF6C5CE7)),
                    ),
                    error: (err, _) => Text('Error: $err',
                        style: const TextStyle(color: Colors.red)),
                    data: (playlists) {
                      return ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: playlists.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final p = playlists[index];
                            final isCurrent = p.id == activePlaylist?.id;

                            return Focus(
                              canRequestFocus: false,
                              child: Builder(
                                builder: (rowCtx) {
                                  final hasFocus = Focus.of(rowCtx).hasFocus;
                                  return InkWell(
                                    autofocus: isCurrent || index == 0,
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      ref
                                          .read(activePlaylistIdProvider.notifier)
                                          .selectPlaylist(p.id);
                                    },
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: hasFocus
                                            ? const Color(0xFF6C5CE7).withValues(alpha: 0.35)
                                            : isCurrent
                                                ? const Color(0xFF6C5CE7)
                                                    .withValues(alpha: 0.2)
                                                : const Color(0xFF181728),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: hasFocus
                                              ? Colors.white
                                              : isCurrent
                                                  ? const Color(0xFF6C5CE7)
                                                  : const Color(0xFF26243A),
                                          width: hasFocus ? 2.5 : (isCurrent ? 1.5 : 1),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            p.type == 'xtream'
                                                ? Icons.bolt_rounded
                                                : Icons.link_rounded,
                                            color: isCurrent
                                                ? const Color(0xFFA29BFE)
                                                : Colors.white60,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  p.name,
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: isCurrent
                                                        ? FontWeight.bold
                                                        : FontWeight.w500,
                                                  ),
                                                ),
                                                Text(
                                                  p.type.toUpperCase(),
                                                  style: const TextStyle(
                                                    color: Colors.white54,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (isCurrent)
                                            const Icon(
                                              Icons.check_circle_rounded,
                                              color: Color(0xFF00B894),
                                              size: 20,
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (context.mounted) {
                                context.go('/playlists');
                              }
                            });
                          },
                          icon: const Icon(Icons.settings_suggest_rounded,
                              size: 16),
                          label: Text(
                            settings.tr('playlists_count'),
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Color(0xFF26243A)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (context.mounted) {
                                showAddProviderDialog(context);
                              }
                            });
                          },
                          icon: const Icon(Icons.add_rounded, size: 16),
                          label: const Text(
                            '+ Playlist',
                            style: TextStyle(fontSize: 13),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF6C5CE7),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // ── Exit Dialog ("QUITTER")
  // ─────────────────────────────────────────────────────────────
  void _showExitDialog(BuildContext context, AppSettings settings) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 380,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF121124),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF6C5CE7).withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.power_settings_new_rounded,
                color: Color(0xFF6C5CE7),
                size: 42,
              ),
              const SizedBox(height: 16),
              Text(
                settings.tr('exit_dialog_title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                settings.tr('exit_dialog_message'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      autofocus: true,
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Color(0xFF26243A)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ).copyWith(
                        side: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.focused)
                              ? const BorderSide(color: Colors.white, width: 2.5)
                              : const BorderSide(color: Color(0xFF26243A)),
                        ),
                      ),
                      child: Text(settings.tr('exit_dialog_cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        if (kIsWeb) {
                          exitSmartTvApp();
                        } else if (PlatformInfo.isAndroid || PlatformInfo.isIOS) {
                          SystemNavigator.pop();
                        } else {
                          io.exit(0);
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6C5CE7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ).copyWith(
                        side: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.focused)
                              ? const BorderSide(color: Colors.white, width: 2.5)
                              : null,
                        ),
                      ),
                      child: Text(settings.tr('exit_dialog_confirm')),
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

// ─────────────────────────────────────────────────────────────
// ── App Brand Logo (Top Center)
// ─────────────────────────────────────────────────────────────
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/icon/yestream_logo.png',
            width: 34,
            height: 34,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 10),

        // Brand name: "yes" in white, "stream" in white with PRO badge
        RichText(
          text: const TextSpan(
            children: [
              TextSpan(
                text: 'yes',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: 'stream',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),

        // Small purple "PRO" tag
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF6C5CE7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'PRO',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ── Left Hero Tile: "En direct" (Live TV)
// ─────────────────────────────────────────────────────────────
class _TvHeroTile extends StatefulWidget {
  final String title;
  final VoidCallback onTap;
  final bool isCompact;

  const _TvHeroTile({
    required this.title,
    required this.onTap,
    this.isCompact = false,
  });

  @override
  State<_TvHeroTile> createState() => _TvHeroTileState();
}

class _TvHeroTileState extends State<_TvHeroTile> {
  bool _isFocused = false;
  bool _isHovered = false;

  bool get _highlight => _isFocused || _isHovered;

  @override
  Widget build(BuildContext context) {
    final isTV = PlatformInfo.isTV;
    final animDur = isTV ? Duration.zero : const Duration(milliseconds: 180);
    return FocusableActionDetector(
      autofocus: true,
      onFocusChange: (f) => setState(() => _isFocused = f),
      onShowHoverHighlight: isTV ? null : (h) => setState(() => _isHovered = h),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: (!isTV && _highlight) ? 1.04 : 1.0,
          duration: animDur,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: animDur,
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _highlight
                    ? const [Color(0xFF7D6DF8), Color(0xFF5A4AE3)]
                    : const [Color(0xFF6C5CE7), Color(0xFF4834D4)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _highlight
                    ? Colors.white
                    : const Color(0xFFA29BFE).withValues(alpha: 0.5),
                width: _highlight ? (isTV ? 3.5 : 2.4) : 1.4,
              ),
              boxShadow: isTV
                  ? null
                  : [
                      BoxShadow(
                        color: _highlight
                            ? const Color(0xFF6C5CE7).withValues(alpha: 0.6)
                            : const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                        blurRadius: _highlight ? 24 : 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Stylized TV icon with play triangle inside
                      _TvWithPlayIcon(size: widget.isCompact ? 56 : 72),
                      SizedBox(height: widget.isCompact ? 10 : 14),
                      Text(
                        widget.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: widget.isCompact ? 20 : 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ── Stylized TV Icon with Play Arrow inside
// ─────────────────────────────────────────────────────────────
class _TvWithPlayIcon extends StatelessWidget {
  final double size;
  const _TvWithPlayIcon({this.size = 80});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 0.82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Antennas / TV Outline
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // TV Antennas
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.rotate(
                    angle: -0.4,
                    child: Container(
                      width: 3,
                      height: size * 0.18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(width: size * 0.16),
                  Transform.rotate(
                    angle: 0.4,
                    child: Container(
                      width: 3,
                      height: size * 0.18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 1),

              // Main TV Monitor Frame
              Container(
                width: size * 0.9,
                height: size * 0.58,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.14),
                  border: Border.all(color: Colors.white, width: 3.5),
                ),
                child: Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: size * 0.36,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ── Center Grid Action Tile (Films, Séries, Catch-up, etc.)
// ─────────────────────────────────────────────────────────────
class _TvGridTile extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final String? badgeText;

  const _TvGridTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.badgeText,
  });

  @override
  State<_TvGridTile> createState() => _TvGridTileState();
}

class _TvGridTileState extends State<_TvGridTile> {
  bool _isFocused = false;
  bool _isHovered = false;

  bool get _highlight => _isFocused || _isHovered;

  @override
  Widget build(BuildContext context) {
    final isTV = PlatformInfo.isTV;
    final animDur = isTV ? Duration.zero : const Duration(milliseconds: 180);
    return FocusableActionDetector(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onShowHoverHighlight: isTV ? null : (h) => setState(() => _isHovered = h),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: (!isTV && _highlight) ? 1.04 : 1.0,
          duration: animDur,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: animDur,
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _highlight
                    ? const [Color(0xFF5A4AE3), Color(0xFF3B2E9C)]
                    : const [Color(0xFF382E88), Color(0xFF1E1752)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _highlight
                    ? Colors.white
                    : const Color(0xFF6C5CE7).withValues(alpha: 0.45),
                width: _highlight ? (isTV ? 3.2 : 2.0) : 1.2,
              ),
              boxShadow: isTV
                  ? null
                  : [
                      BoxShadow(
                        color: _highlight
                            ? const Color(0xFF6C5CE7).withValues(alpha: 0.5)
                            : const Color(0xFF4834D4).withValues(alpha: 0.25),
                        blurRadius: _highlight ? 18 : 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Stack(
              children: [
                // Mini Badge (e.g. for Catch-up)
                if (widget.badgeText != null)
                  Positioned(
                    top: 2,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C5CE7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.badgeText!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(widget.icon, size: 36, color: Colors.white),
                          const SizedBox(height: 6),
                          Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ── Full-Width Horizontal Tile (Switch Playlist)
// ─────────────────────────────────────────────────────────────
class _TvGridTileHorizontal extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final String? badgeText;

  const _TvGridTileHorizontal({
    required this.title,
    required this.icon,
    required this.onTap,
    this.badgeText,
  });

  @override
  State<_TvGridTileHorizontal> createState() => _TvGridTileHorizontalState();
}

class _TvGridTileHorizontalState extends State<_TvGridTileHorizontal> {
  bool _isFocused = false;
  bool _isHovered = false;

  bool get _highlight => _isFocused || _isHovered;

  @override
  Widget build(BuildContext context) {
    final isTV = PlatformInfo.isTV;
    final animDur = isTV ? Duration.zero : const Duration(milliseconds: 180);
    return FocusableActionDetector(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onShowHoverHighlight: isTV ? null : (h) => setState(() => _isHovered = h),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: (!isTV && _highlight) ? 1.04 : 1.0,
          duration: animDur,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: animDur,
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _highlight
                    ? const [Color(0xFF5A4AE3), Color(0xFF3B2E9C)]
                    : const [Color(0xFF382E88), Color(0xFF1E1752)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _highlight
                    ? Colors.white
                    : const Color(0xFF6C5CE7).withValues(alpha: 0.45),
                width: _highlight ? (isTV ? 3.2 : 2.0) : 1.2,
              ),
              boxShadow: isTV
                  ? null
                  : [
                      BoxShadow(
                        color: _highlight
                            ? const Color(0xFF6C5CE7).withValues(alpha: 0.5)
                            : const Color(0xFF4834D4).withValues(alpha: 0.25),
                        blurRadius: _highlight ? 18 : 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, size: 26, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ── Right Column Action Button (Paramètres, Recharger, QUITTER)
// ─────────────────────────────────────────────────────────────
class _TvActionButton extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLoading;
  final bool isExit;

  const _TvActionButton({
    required this.title,
    required this.icon,
    required this.onTap,
    this.isLoading = false,
    this.isExit = false,
  });

  @override
  State<_TvActionButton> createState() => _TvActionButtonState();
}

class _TvActionButtonState extends State<_TvActionButton> {
  bool _isFocused = false;
  bool _isHovered = false;

  bool get _highlight => _isFocused || _isHovered;

  @override
  Widget build(BuildContext context) {
    final isTV = PlatformInfo.isTV;
    final animDur = isTV ? Duration.zero : const Duration(milliseconds: 180);
    return FocusableActionDetector(
      onFocusChange: (f) => setState(() => _isFocused = f),
      onShowHoverHighlight: isTV ? null : (h) => setState(() => _isHovered = h),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => widget.onTap(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: (!isTV && _highlight) ? 1.03 : 1.0,
          duration: animDur,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: animDur,
            width: double.infinity,
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: _highlight
                  ? const Color(0xFF6C5CE7).withValues(alpha: 0.35)
                  : const Color(0xFF141328).withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _highlight
                    ? Colors.white
                    : const Color(0xFF6C5CE7).withValues(alpha: 0.35),
                width: _highlight ? (isTV ? 3.0 : 1.8) : 1.2,
              ),
              boxShadow: isTV
                  ? null
                  : [
                      BoxShadow(
                        color: _highlight
                            ? const Color(0xFF6C5CE7).withValues(alpha: 0.4)
                            : Colors.black26,
                        blurRadius: _highlight ? 14 : 6,
                      ),
                    ],
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.isLoading)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    else
                      Icon(
                        widget.icon,
                        size: 24,
                        color: Colors.white,
                      ),
                    const SizedBox(width: 10),
                    Text(
                      widget.title,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight:
                            widget.isExit ? FontWeight.w800 : FontWeight.w700,
                        letterSpacing: widget.isExit ? 0.4 : 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
