import 'package:flutter_test/flutter_test.dart';
import 'package:yesxtream/features/providers/provider_manager.dart';

void main() {
  group('parseXtreamFromM3uUrl', () {
    test('extracts credentials and baseUrl from standard Xtream M3U link', () {
      const url =
          'http://aspnet42279.wd.business-cdn-8k.com/get.php?username=916cc9abb08c&password=82niom7dse&type=m3u_plus&output=ts';
      final parsed = parseXtreamFromM3uUrl(url);

      expect(parsed, isNotNull);
      expect(parsed!.baseUrl, 'http://aspnet42279.wd.business-cdn-8k.com');
      expect(parsed.username, '916cc9abb08c');
      expect(parsed.password, '82niom7dse');
    });

    test('extracts credentials when port is present in host', () {
      const url =
          'http://iptv.server.net:8080/get.php?username=myuser&password=mypass&type=m3u';
      final parsed = parseXtreamFromM3uUrl(url);

      expect(parsed, isNotNull);
      expect(parsed!.baseUrl, 'http://iptv.server.net:8080');
      expect(parsed.username, 'myuser');
      expect(parsed.password, 'mypass');
    });

    test('returns null for plain M3U URL without credentials', () {
      const url = 'https://example.com/playlist.m3u8';
      final parsed = parseXtreamFromM3uUrl(url);

      expect(parsed, isNull);
    });
  });
}
