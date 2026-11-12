import 'package:flutter/material.dart';
import '../providers/add_provider_dialog.dart';

enum PlaylistImportType { iptv, m3u, phone }

/// Opens the unified responsive Add Provider / Playlist dialog.
Future<void> showChoosePlaylistTypeDialog(BuildContext context) {
  return showAddProviderDialog(context);
}
