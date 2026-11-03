import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/datasources/local/database.dart' as db;
import 'add_provider_dialog.dart';
import 'provider_manager.dart';

/// Watches all providers as a stream for reactive UI updates.
final _providersStreamProvider = StreamProvider<List<db.Provider>>((ref) {
  final database = ref.watch(databaseProvider);
  return database.select(database.providers).watch();
});

class ProvidersScreen extends ConsumerWidget {
  const ProvidersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providersAsync = ref.watch(_providersStreamProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          Future.microtask(() {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          });
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: const Text('IPTV Providers'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, size: 28),
            tooltip: 'Add Provider',
            onPressed: () => showAddProviderDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: providersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (providers) => FocusTraversalGroup(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              if (providers.isNotEmpty) ...[
                const _SectionHeader(title: 'Your Playlists'),
                ...providers.map((p) => _ProviderCard(provider: p)),
              ] else ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.playlist_play_rounded, size: 64, color: Colors.white24),
                        const SizedBox(height: 16),
                        const Text(
                          'No playlists added yet',
                          style: TextStyle(fontSize: 18, color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add an IPTV or M3U playlist to begin watching',
                          style: TextStyle(fontSize: 14, color: Colors.white38),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () => showAddProviderDialog(context),
                          icon: const Icon(Icons.add),
                          label: const Text('Add Playlist'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _ProviderCard extends ConsumerWidget {
  final db.Provider provider;
  const _ProviderCard({required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const accent = Color(0xFF6C5CE7);
    final isXtream = provider.type == 'xtream';

    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          // SELECT on provider card → refresh
          _refreshProvider(context, ref);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: hasFocus
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: accent, width: 2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              isXtream ? Icons.api_rounded : Icons.playlist_play_rounded,
              color: accent,
              size: 36,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isXtream ? 'Xtream' : 'M3U',
                          style: const TextStyle(
                              fontSize: 11, color: accent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '— channels',
                        style: TextStyle(
                            fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'Refresh',
              onPressed: () async {
                final manager = ref.read(providerManagerProvider);
                try {
                  final count = await manager.refreshProvider(provider.id);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Loaded $count channels')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Refresh failed: $e')),
                  );
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 20, color: Colors.redAccent),
              tooltip: 'Delete',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A2E),
                    title: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Text(provider.name),
                      ],
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context, false),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        onPressed: () => Navigator.pop(context, true),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  final manager = ref.read(providerManagerProvider);
                  await manager.deleteProvider(provider.id);
                }
              },
            ),
          ],
        ),
      ),
    );
        },  // Builder builder
      ),  // Builder
    );  // Focus
  }

  void _refreshProvider(BuildContext context, WidgetRef ref) async {
    final manager = ref.read(providerManagerProvider);
    try {
      final count = await manager.refreshProvider(provider.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded $count channels')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refresh failed: $e')),
      );
    }
  }
}

