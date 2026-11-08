import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// Central registry of all active [Player] instances.
///
/// On desktop platforms (especially macOS), if the Flutter engine shuts down
/// while native mpv background threads are still running, mpv can fire FFI
/// property change callbacks into a terminating or destroyed Dart isolate,
/// triggering `dart::Assert::Fail` and `SIGABRT` (crash on exit).
///
/// This registry tracks every instantiated [Player] so they can all be
/// cleanly stopped and disposed during the app exit lifecycle.
class ActivePlayerRegistry {
  ActivePlayerRegistry._();

  static final Set<Player> _players = <Player>{};

  /// Register a player instance upon creation.
  static void register(Player player) {
    _players.add(player);
  }

  /// Unregister a player instance upon disposal.
  static void unregister(Player player) {
    _players.remove(player);
  }

  /// Stop and dispose all registered players asynchronously.
  static Future<void> disposeAll({Duration timeout = const Duration(milliseconds: 1000)}) async {
    if (_players.isEmpty) return;

    final list = _players.toList();
    _players.clear();

    debugPrint('[ActivePlayerRegistry] Stopping and disposing ${list.length} active player(s)...');

    final futures = list.map((player) async {
      try {
        await player.stop();
      } catch (e) {
        debugPrint('[ActivePlayerRegistry] Error stopping player: $e');
      }
      try {
        await player.dispose();
      } catch (e) {
        debugPrint('[ActivePlayerRegistry] Error disposing player: $e');
      }
    });

    try {
      await Future.wait(futures).timeout(timeout);
    } catch (e) {
      debugPrint('[ActivePlayerRegistry] Timeout waiting for player disposal: $e');
    }
  }

  /// Best-effort synchronous cleanup for detached lifecycle events.
  static void disposeAllSync() {
    if (_players.isEmpty) return;
    final list = _players.toList();
    _players.clear();
    for (final player in list) {
      try {
        player.stop();
        player.dispose();
      } catch (_) {}
    }
  }
}

