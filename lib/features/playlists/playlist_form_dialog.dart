import 'package:flutter/material.dart';
import '../providers/add_provider_dialog.dart';
import 'choose_playlist_type_dialog.dart';

/// Opens the unified responsive Add Provider / Playlist dialog.
Future<void> showPlaylistFormDialog(
  BuildContext context, {
  required PlaylistImportType type,
  String? existingId,
  String? initialName,
  String? initialUrl,
  String? initialUsername,
  String? initialPassword,
}) {
  return showAddProviderDialog(
    context,
    existingId: existingId,
    initialName: initialName,
    initialUrl: initialUrl,
    initialUsername: initialUsername,
    initialPassword: initialPassword,
    isXtream: type == PlaylistImportType.iptv,
  );
}
