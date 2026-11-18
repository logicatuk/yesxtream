import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../data/datasources/local/database.dart' as db;
import '../../data/services/device_identity_service.dart';
import '../../data/services/device_sync_service.dart';
import '../providers/add_provider_dialog.dart';
import '../providers/provider_manager.dart';
import 'playlist_providers.dart';

class PlaylistManagerScreen extends ConsumerWidget {
  const PlaylistManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(allPlaylistsProvider);
    final activePlaylist = ref.watch(activePlaylistProvider);
    final identityAsync = ref.watch(deviceIdentityProvider);
    final entitlement = ref.watch(deviceEntitlementProvider);
    final identity = identityAsync.value;
    final isRegistered = identity?.serverRegistered == true && identity?.deviceKey != null;
    final macAddress = identity?.macAddress ?? 'Loading…';
    final deviceKey = identity?.deviceKey;
    final portalUrl = identity?.portalLoginUrl ?? entitlement.portalLoginUrl;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        title: const Text(
          'Playlists',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Sync Cloud Playlists',
            icon: entitlement.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync_rounded),
            onPressed: entitlement.isSyncing
                ? null
                : () async {
                    await ref.read(deviceEntitlementProvider.notifier).sync();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cloud playlists synchronized')),
                      );
                    }
                  },
          ),
          FilledButton.icon(
            onPressed: () => showAddProviderDialog(context),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Playlist'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: playlistsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF6C5CE7)),
        ),
        error: (err, _) => Center(
          child: Text('Error: $err', style: const TextStyle(color: Colors.red)),
        ),
        data: (playlists) {
          if (playlists.isEmpty) {
            final hasValidKey = isRegistered && deviceKey != null && portalUrl != null && portalUrl.isNotEmpty;

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF13111C),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasValidKey ? const Color(0xFF26243A) : const Color(0xFFE17055).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasValidKey) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SizedBox(
                              width: 140,
                              height: 140,
                              child: CustomPaint(
                                painter: QrPainter(
                                  data: portalUrl,
                                  version: QrVersions.auto,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Color(0xFF000000),
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Color(0xFF000000),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'No Playlists Found',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Scan the QR code with your phone to upload an M3U or Xtream playlist through the customer portal, or add one locally below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 14, color: Colors.white60, height: 1.4),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1B1829),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFF2E2B44)),
                            ),
                            child: Wrap(
                              spacing: 16,
                              runSpacing: 6,
                              alignment: WrapAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('MAC: $macAddress',
                                        style: const TextStyle(
                                            color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: macAddress));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('MAC copied: $macAddress')),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.copy_rounded, size: 15, color: Colors.white60),
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('KEY: $deviceKey',
                                        style: const TextStyle(
                                            color: Color(0xFFA29BFE),
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: deviceKey!));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Device key copied: $deviceKey')),
                                        );
                                      },
                                      borderRadius: BorderRadius.circular(6),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.copy_rounded, size: 15, color: Color(0xFFA29BFE)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: () => ref.read(deviceEntitlementProvider.notifier).sync(),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF6C5CE7),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                                icon: const Icon(Icons.sync_rounded, size: 18),
                                label: const Text('Sync Cloud Playlists'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => showAddProviderDialog(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Color(0xFF38354D)),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add Local Playlist'),
                              ),
                            ],
                          ),
                        ] else ...[
                          const Icon(Icons.cloud_off_rounded, size: 52, color: Color(0xFFFFA07A)),
                          const SizedBox(height: 14),
                          const Text(
                            'Not Synced with Server Yet',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Connecting to Yestream server to verify device and generate your verified key.\nMAC: $macAddress',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, color: Colors.white60, height: 1.4),
                          ),
                          const SizedBox(height: 22),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: () async {
                                  ref.invalidate(deviceIdentityProvider);
                                  await ref.read(deviceEntitlementProvider.notifier).sync();
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF6C5CE7),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Retry Connection'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => showAddProviderDialog(context),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Color(0xFF38354D)),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                ),
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('Add Local Playlist'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: playlists.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              if (index == 0) {
                // Cloud Sync header banner
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13111C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF26243A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_done_rounded, color: Color(0xFF6C5CE7), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Device: $macAddress',
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              entitlement.formattedStatusBadge,
                              style: TextStyle(
                                color: entitlement.isActive
                                    ? Colors.greenAccent
                                    : (entitlement.isExpired ? Colors.redAccent : Colors.amberAccent),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: entitlement.isSyncing
                            ? null
                            : () => ref.read(deviceEntitlementProvider.notifier).sync(),
                        icon: entitlement.isSyncing
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.sync_rounded, size: 16),
                        label: Text(entitlement.isSyncing ? 'Syncing' : 'Sync'),
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFFA29BFE)),
                      ),
                    ],
                  ),
                );
              }

              final playlist = playlists[index - 1];
              final isActive = activePlaylist?.id == playlist.id;

              return _PlaylistCard(
                playlist: playlist,
                isActive: isActive,
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaylistCard extends ConsumerStatefulWidget {
  final db.Provider playlist;
  final bool isActive;

  const _PlaylistCard({
    required this.playlist,
    required this.isActive,
  });

  @override
  ConsumerState<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends ConsumerState<_PlaylistCard> {
  bool _isRefreshing = false;

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      final manager = ref.read(providerManagerProvider);
      final count = await manager.refreshProvider(widget.playlist.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated "${widget.playlist.name}": $count channels loaded'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refresh failed: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _openPlaylist() {
    ref.read(activePlaylistIdProvider.notifier).selectPlaylist(widget.playlist.id);
    context.go('/live');
  }

  void _showManageDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ManagePlaylistDialog(playlist: widget.playlist),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6C5CE7);
    final p = widget.playlist;

    final dateStr = p.lastRefresh != null
        ? DateFormat('MMM d, yyyy • HH:mm').format(p.lastRefresh!)
        : 'Never';

    final isXtream = p.type == 'xtream';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF141322),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isActive ? accent : const Color(0xFF26243A),
          width: widget.isActive ? 1.8 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isXtream ? Icons.live_tv_rounded : Icons.playlist_play_rounded,
              color: accent,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      p.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isXtream ? const Color(0xFF00B894) : const Color(0xFF0984E3))
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isXtream ? 'IPTV login' : 'M3U',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isXtream ? const Color(0xFF00B894) : const Color(0xFF74B9FF),
                        ),
                      ),
                    ),
                    if (widget.isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFA29BFE),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Last updated: $dateStr',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
          ),
          // Actions: Open, Refresh, Manage
          OutlinedButton.icon(
            onPressed: _openPlaylist,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFF6C5CE7)),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Open'),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                  )
                : const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Refresh Channels',
            onPressed: _isRefreshing ? null : _refresh,
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white70),
            tooltip: 'Manage Playlist',
            onPressed: _showManageDialog,
          ),
        ],
      ),
    );
  }
}

class _ManagePlaylistDialog extends ConsumerStatefulWidget {
  final db.Provider playlist;
  const _ManagePlaylistDialog({required this.playlist});

  @override
  ConsumerState<_ManagePlaylistDialog> createState() => _ManagePlaylistDialogState();
}

class _ManagePlaylistDialogState extends ConsumerState<_ManagePlaylistDialog> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.playlist.name);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    final newName = _nameCtrl.text.trim();
    if (newName.isEmpty) return;

    final dbInstance = ref.read(databaseProvider);
    await (dbInstance.update(dbInstance.providers)
          ..where((t) => t.id.equals(widget.playlist.id)))
        .write(db.ProvidersCompanion(name: Value(newName)));

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Playlist renamed')),
    );
  }

  void _editConnection() {
    Navigator.of(context).pop();
    showAddProviderDialog(
      context,
      existingId: widget.playlist.id,
      initialName: widget.playlist.name,
      initialUrl: widget.playlist.url,
      initialUsername: widget.playlist.username,
      initialPassword: widget.playlist.password,
      isXtream: widget.playlist.type == 'xtream',
    );
  }

  Future<void> _setAsStartup() async {
    await ref.read(activePlaylistIdProvider.notifier).selectPlaylist(widget.playlist.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"${widget.playlist.name}" set as active playlist')),
    );
  }

  Future<void> _confirmRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1B1A2C),
        title: const Text('Remove Playlist?'),
        content: Text(
          'Are you sure you want to remove "${widget.playlist.name}"? '
          'All imported channels from this playlist will be removed from your library. '
          'Your player license remains active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final manager = ref.read(providerManagerProvider);
        await manager.deleteProvider(widget.playlist.id);
        ref.read(deviceEntitlementProvider.notifier).pushLocalPlaylistsToCloud().catchError((_) {});
        await ref.read(activePlaylistIdProvider.notifier).clearIfDeleted(widget.playlist.id);
        ref.invalidate(allPlaylistsProvider);
        ref.invalidate(activePlaylistStatsProvider);
        ref.invalidate(activePlaylistAccountInfoProvider);
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Playlist removed')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Failed to remove playlist: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141322),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Manage Playlist',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white38),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Rename field
              TextFormField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'Rename Playlist',
                  filled: true,
                  fillColor: const Color(0xFF1B1A2C),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.check, color: Color(0xFF6C5CE7)),
                    onPressed: _rename,
                  ),
                ),
              ),

              const SizedBox(height: 18),
              const Divider(color: Color(0xFF26243A)),
              const SizedBox(height: 8),

              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.white70),
                title: const Text('Edit Connection'),
                subtitle: const Text('Update server URL or credentials', style: TextStyle(fontSize: 12)),
                onTap: _editConnection,
              ),

              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: Colors.white70),
                title: const Text('Set as Active Playlist'),
                subtitle: const Text('Use as current library', style: TextStyle(fontSize: 12)),
                onTap: _setAsStartup,
              ),

              ListTile(
                leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                title: const Text('Remove Playlist', style: TextStyle(color: Colors.redAccent)),
                subtitle: const Text('Delete channels (license unaffected)', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                onTap: _confirmRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
