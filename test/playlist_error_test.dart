import 'package:flutter_test/flutter_test.dart';
import 'package:yesxtream/data/datasources/remote/xtream_client.dart';
import 'package:yesxtream/features/providers/playlist_error.dart';

void main() {
  test('wrong password shows clear auth title', () {
    final info = formatPlaylistError(
      const XtreamAuthException('Login failed: Invalid username or password'),
    );
    expect(info.title, 'Wrong Username or Password');
    expect(info.message.toLowerCase(), contains('username'));
    expect(info.message.toLowerCase(), isNot(contains('xmlhttprequest')));
  });

  test('expired account shows playlist expired', () {
    final info = formatPlaylistError(
      const XtreamAuthException('Account subscription expired on 2024-01-15'),
    );
    expect(info.title, 'Playlist Expired');
    expect(info.message, contains('2024-01-15'));
  });

  test('M3U empty / invalid messages', () {
    final empty = formatPlaylistError(
      Exception('M3U playlist is empty (0 bytes received)'),
    );
    expect(empty.title, 'M3U Playlist Error');
    expect(empty.message.toLowerCase(), contains('empty'));

    final html = formatPlaylistError(
      Exception('URL returned a web page or invalid document instead of an M3U playlist'),
    );
    expect(html.title, 'M3U Playlist Error');
    expect(html.message.toLowerCase(), contains('web page'));
  });

  test('XMLHttpRequest noise becomes cannot reach server', () {
    final info = formatPlaylistError(
      Exception(
        'Connection failed: The connection errored: The XMLHttpRequest onError callback was called. '
        'This typically indicates an error on the network layer. '
        'This indicates an error which most likely cannot be solved by the library.',
      ),
    );
    expect(info.title, 'Cannot Reach Server');
    expect(info.message.toLowerCase(), isNot(contains('xmlhttprequest')));
    expect(info.message.toLowerCase(), isNot(contains('library')));
  });

  test('Xtream connection failed maps to cannot reach server', () {
    final info = formatPlaylistError(
      const XtreamServerException('Connection failed — could not reach the server'),
    );
    expect(info.title, 'Cannot Reach Server');
  });
}
