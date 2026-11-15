import 'package:flutter/material.dart';

import '../../data/datasources/remote/xtream_client.dart';

/// User-facing title + message for playlist / provider add failures.
class PlaylistErrorInfo {
  final String title;
  final String message;
  final IconData icon;
  final Color color;

  const PlaylistErrorInfo({
    required this.title,
    required this.message,
    this.icon = Icons.error_outline_rounded,
    this.color = const Color(0xFFFF6B81),
  });
}

/// Turns raw Xtream / M3U / Dio / web errors into short TV-friendly copy.
PlaylistErrorInfo formatPlaylistError(Object error) {
  if (error is XtreamAuthException) {
    return _formatAuth(error.message);
  }

  if (error is XtreamServerException) {
    return _formatServer(error.message);
  }

  if (error is XtreamException) {
    final t = error.message.toLowerCase();
    if (t.contains('no channels') || t.contains('no streams')) {
      return const PlaylistErrorInfo(
        title: 'Empty Playlist',
        message:
            'Login worked, but no channels or streams were found on this account.',
        icon: Icons.playlist_remove_rounded,
        color: Color(0xFFFFB142),
      );
    }
    return PlaylistErrorInfo(
      title: 'Playlist Error',
      message: _sanitize(error.message),
    );
  }

  final raw = error.toString();
  final text = raw
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^Failed to add provider:\s*', caseSensitive: false), '')
      .trim();

  if (_looksLikeWrongPassword(text)) {
    return const PlaylistErrorInfo(
      title: 'Wrong Username or Password',
      message:
          'The server rejected these login details.\n\n'
          'Check the username and password, then try again.',
      icon: Icons.lock_outline_rounded,
      color: Color(0xFFFF6B81),
    );
  }

  if (_looksLikeExpired(text)) {
    return PlaylistErrorInfo(
      title: 'Playlist Expired',
      message: _expiredMessage(text),
      icon: Icons.event_busy_rounded,
      color: const Color(0xFFFFB142),
    );
  }

  if (_looksLikeM3u(text)) {
    return PlaylistErrorInfo(
      title: 'M3U Playlist Error',
      message: _m3uMessage(text),
      icon: Icons.playlist_add_check_rounded,
      color: const Color(0xFFFF6B81),
    );
  }

  if (_looksLikeNetwork(text)) {
    return const PlaylistErrorInfo(
      title: 'Cannot Reach Server',
      message:
          'The app could not connect to this playlist URL.\n\n'
          'Check the server address, your internet connection, and that the link still works.',
      icon: Icons.wifi_off_rounded,
      color: Color(0xFFFF6B81),
    );
  }

  if (text.toLowerCase().contains('no channels') ||
      text.toLowerCase().contains('no playable') ||
      text.toLowerCase().contains('no streams')) {
    return const PlaylistErrorInfo(
      title: 'Empty Playlist',
      message:
          'No channels or streams were found in this playlist.',
      icon: Icons.playlist_remove_rounded,
      color: Color(0xFFFFB142),
    );
  }

  return PlaylistErrorInfo(
    title: 'Could Not Add Playlist',
    message: _sanitize(text),
  );
}

PlaylistErrorInfo _formatAuth(String message) {
  if (_looksLikeExpired(message)) {
    return PlaylistErrorInfo(
      title: 'Playlist Expired',
      message: _expiredMessage(message),
      icon: Icons.event_busy_rounded,
      color: const Color(0xFFFFB142),
    );
  }
  if (message.toLowerCase().contains('not active') ||
      message.toLowerCase().contains('disabled') ||
      message.toLowerCase().contains('banned')) {
    return PlaylistErrorInfo(
      title: 'Account Not Active',
      message:
          'This IPTV account is not active.\n\n'
          '${_sanitize(message)}\n\n'
          'Contact your provider if this is unexpected.',
      icon: Icons.person_off_outlined,
      color: const Color(0xFFFFB142),
    );
  }
  return const PlaylistErrorInfo(
    title: 'Wrong Username or Password',
    message:
        'The server rejected these login details.\n\n'
        'Check the username and password, then try again.',
    icon: Icons.lock_outline_rounded,
    color: Color(0xFFFF6B81),
  );
}

PlaylistErrorInfo _formatServer(String message) {
  if (_looksLikeNetwork(message)) {
    return const PlaylistErrorInfo(
      title: 'Cannot Reach Server',
      message:
          'The app could not connect to this server.\n\n'
          'Check the server URL and your internet connection.',
      icon: Icons.wifi_off_rounded,
    );
  }
  if (message.contains('404') || message.toLowerCase().contains('not found')) {
    return const PlaylistErrorInfo(
      title: 'Invalid Server URL',
      message:
          'No Xtream Codes API was found at this address.\n\n'
          'Check the server URL (example: http://example.com:8080).',
      icon: Icons.link_off_rounded,
    );
  }
  if (message.toLowerCase().contains('not a valid xtream') ||
      message.toLowerCase().contains('invalid response') ||
      message.toLowerCase().contains('missing "user_info"')) {
    return const PlaylistErrorInfo(
      title: 'Not an Xtream Server',
      message:
          'This URL does not look like a valid Xtream Codes panel.\n\n'
          'Use the panel URL from your provider, not an M3U file link.',
      icon: Icons.dns_outlined,
    );
  }
  return PlaylistErrorInfo(
    title: 'Server Error',
    message: _sanitize(message),
  );
}

bool _looksLikeWrongPassword(String text) {
  final t = text.toLowerCase();
  return t.contains('invalid username') ||
      t.contains('wrong password') ||
      t.contains('wrong username') ||
      t.contains('login failed') ||
      t.contains('authentication failed') ||
      t.contains('auth failed') ||
      t.contains('http 401') ||
      t.contains('http 403') ||
      (t.contains('password') &&
          (t.contains('invalid') || t.contains('incorrect')));
}

bool _looksLikeExpired(String text) {
  final t = text.toLowerCase();
  return t.contains('expired') ||
      t.contains('subscription ended') ||
      t.contains('trial ended');
}

bool _looksLikeM3u(String text) {
  final t = text.toLowerCase();
  return t.contains('m3u') ||
      t.contains('playlist is empty') ||
      t.contains('no valid channels') ||
      t.contains('web page or invalid') ||
      t.contains('instead of an m3u') ||
      t.contains('0 bytes');
}

bool _looksLikeNetwork(String text) {
  final t = text.toLowerCase();
  return t.contains('xmlhttprequest') ||
      t.contains('connection failed') ||
      t.contains('connection errored') ||
      t.contains('connection error') ||
      t.contains('network layer') ||
      t.contains('socketexception') ||
      t.contains('failed host lookup') ||
      t.contains('connection refused') ||
      t.contains('connection timed out') ||
      t.contains('timed out') ||
      t.contains('timeout') ||
      t.contains('network is unreachable') ||
      t.contains('could not reach') ||
      t.contains('dioexception');
}

String _expiredMessage(String text) {
  final dateMatch = RegExp(r'on (\d{4}-\d{2}-\d{2})').firstMatch(text);
  if (dateMatch != null) {
    return 'This playlist subscription expired on ${dateMatch.group(1)}.\n\n'
        'Renew with your IPTV provider, then add the playlist again.';
  }
  return 'This playlist or account subscription has expired.\n\n'
      'Renew with your IPTV provider, then try again.';
}

String _m3uMessage(String text) {
  final t = text.toLowerCase();
  if (t.contains('404') || t.contains('not found')) {
    return 'The M3U link was not found (404).\n\n'
        'Check the URL or ask your provider for a new link.';
  }
  if (t.contains('empty') || t.contains('0 bytes')) {
    return 'The M3U file is empty.\n\n'
        'Ask your provider for a working playlist URL.';
  }
  if (t.contains('web page') ||
      t.contains('invalid document') ||
      t.contains('html')) {
    return 'This URL returned a web page instead of an M3U playlist.\n\n'
        'Paste the direct .m3u / .m3u8 link from your provider.';
  }
  if (t.contains('no valid') || t.contains('no playable')) {
    return 'No playable channels were found in this M3U playlist.\n\n'
        'The file may be broken or the link may have expired.';
  }
  return '${_sanitize(text)}\n\nCheck that the M3U URL is correct and still active.';
}

String _sanitize(String text) {
  var t = text;
  t = t.replaceAll(
    RegExp(r'The XMLHttpRequest onError callback was called\.?', caseSensitive: false),
    '',
  );
  t = t.replaceAll(
    RegExp(
      r'This typically indicates an error on the network layer\.?',
      caseSensitive: false,
    ),
    '',
  );
  t = t.replaceAll(
    RegExp(
      r'This indicates an error which most likely cannot be solved by the library\.?',
      caseSensitive: false,
    ),
    '',
  );
  t = t.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  if (t.isEmpty) {
    return 'Something went wrong while adding this playlist. Please try again.';
  }
  if (t.length > 280) {
    return '${t.substring(0, 277)}...';
  }
  return t;
}
