import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../data/datasources/local/database.dart' as db;
import '../providers/provider_manager.dart';
import 'choose_playlist_type_dialog.dart';
import 'playlist_form_dialog.dart';
import 'playlist_providers.dart';

class PlaylistManagerScreen extends ConsumerWidget {
  const PlaylistManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(allPlaylistsProvider);
    final activePlaylist = ref.watch(activePlaylistProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        title: const Text(
          'Playlists',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          FilledButton.icon(
            onPressed: () => showChoosePlaylistTypeDialog(context),
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
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.playlist_remove_rounded,
                      size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  const Text(
                    'No playlists found',
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add an IPTV login or M3U playlist to start watching',
                    style: TextStyle(fontSize: 14, color: Colors.white38),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => showChoosePlaylistTypeDialog(context),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Playlist'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: playlists.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
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
    showPlaylistFormDialog(
      context,
      type: widget.playlist.type == 'xtream'
          ? PlaylistImportType.iptv
          : PlaylistImportType.m3u,
      existingId: widget.playlist.id,
      initialName: widget.playlist.name,
      initialUrl: widget.playlist.url,
      initialUsername: widget.playlist.username,
      initialPassword: widget.playlist.password,
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
      final manager = ref.read(providerManagerProvider);
      await manager.deleteProvider(widget.playlist.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Playlist removed')),
      );
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
