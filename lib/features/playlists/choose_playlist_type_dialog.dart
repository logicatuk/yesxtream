import 'package:flutter/material.dart';
import 'playlist_form_dialog.dart';

enum PlaylistImportType { iptv, m3u, phone }

/// Screen 04: Choose playlist type dialog
Future<void> showChoosePlaylistTypeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => const _ChoosePlaylistTypeDialog(),
  );
}

class _ChoosePlaylistTypeDialog extends StatelessWidget {
  const _ChoosePlaylistTypeDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF141322),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.playlist_add_rounded,
                      color: Color(0xFF6C5CE7),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Playlist',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Choose how you want to connect your content',
                          style: TextStyle(fontSize: 13, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white38),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Option 1: IPTV login (Xtream Codes)
              _PlaylistTypeTile(
                title: 'IPTV login',
                subtitle: 'Server URL, username, and password (Xtream Codes / XUI)',
                icon: Icons.vpn_key_rounded,
                badge: 'Recommended',
                badgeColor: const Color(0xFF6C5CE7),
                onTap: () {
                  Navigator.of(context).pop();
                  showPlaylistFormDialog(context, type: PlaylistImportType.iptv);
                },
              ),

              const SizedBox(height: 12),

              // Option 2: M3U playlist
              _PlaylistTypeTile(
                title: 'M3U playlist',
                subtitle: 'Direct M3U / M3U+ URL with optional EPG feed',
                icon: Icons.link_rounded,
                onTap: () {
                  Navigator.of(context).pop();
                  showPlaylistFormDialog(context, type: PlaylistImportType.m3u);
                },
              ),

              const SizedBox(height: 12),

              // Option 3: Use phone / browser
              _PlaylistTypeTile(
                title: 'Use phone / web portal',
                subtitle: 'Scan QR code and enter credentials or upload files from your phone',
                icon: Icons.qr_code_scanner_rounded,
                onTap: () {
                  Navigator.of(context).pop();
                  showPlaylistFormDialog(context, type: PlaylistImportType.phone);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistTypeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _PlaylistTypeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.badge,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6C5CE7);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1A2C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2B2A40)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? accent).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: (badgeColor ?? accent).withValues(alpha: 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              badge!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: badgeColor ?? accent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}
