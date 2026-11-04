import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yesxtream/data/datasources/local/database.dart';
import 'package:yesxtream/data/datasources/remote/xtream_client.dart';
import 'package:yesxtream/features/providers/provider_manager.dart';

void main() {
  group('XtreamClient Authentication Verification', () {
    test('authenticates successfully when auth=1 and status=Active', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final response = Response(
              requestOptions: options,
              statusCode: 200,
              data: jsonEncode({
                'user_info': {
                  'username': 'valid_user',
                  'auth': 1,
                  'status': 'Active',
                  'exp_date': '${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + 86400}',
                },
                'server_info': {
                  'url': 'http://iptv.server.com',
                  'port': '8080',
                },
              }),
            );
            return handler.resolve(response);
          },
        ),
      );

      final client = XtreamClient(
        baseUrl: 'http://iptv.server.com:8080',
        username: 'valid_user',
        password: 'valid_password',
        dio: dio,
      );

      final info = await client.authenticate();
      expect(info.isActive, isTrue);
      expect(info.auth, 1);
      expect(info.status, 'Active');
    });

    test('rejects fake credentials when auth=0 (standard Xtream Codes rejection)', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final response = Response(
              requestOptions: options,
              statusCode: 200,
              data: jsonEncode({
                'user_info': {
                  'username': 'fake_user',
                  'auth': 0,
                  'status': 'Disabled',
                  'message': 'We could not find a matching account.',
                },
              }),
            );
            return handler.resolve(response);
          },
        ),
      );

      final client = XtreamClient(
        baseUrl: 'http://iptv.server.com:8080',
        username: 'fake_user',
        password: 'fake_password',
        dio: dio,
      );

      expect(
        () => client.authenticate(),
        throwsA(isA<XtreamAuthException>().having(
          (e) => e.message,
          'message',
          contains('We could not find a matching account'),
        )),
      );
    });

    test('rejects when status is not Active (e.g. Expired)', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final response = Response(
              requestOptions: options,
              statusCode: 200,
              data: jsonEncode({
                'user_info': {
                  'username': 'expired_user',
                  'auth': 1,
                  'status': 'Expired',
                  'message': 'Subscription has ended',
                },
              }),
            );
            return handler.resolve(response);
          },
        ),
      );

      final client = XtreamClient(
        baseUrl: 'http://iptv.server.com:8080',
        username: 'expired_user',
        password: 'password',
        dio: dio,
      );

      expect(
        () => client.authenticate(),
        throwsA(isA<XtreamAuthException>().having(
          (e) => e.message,
          'message',
          contains('Account is not active'),
        )),
      );
    });

    test('rejects fake server returning HTML webpage instead of JSON', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final response = Response(
              requestOptions: options,
              statusCode: 200,
              data: '<!DOCTYPE html><html><body>Welcome to My Blog</body></html>',
            );
            return handler.resolve(response);
          },
        ),
      );

      final client = XtreamClient(
        baseUrl: 'http://fake-blog.com',
        username: 'user',
        password: 'password',
        dio: dio,
      );

      expect(
        () => client.authenticate(),
        throwsA(isA<XtreamServerException>().having(
          (e) => e.message,
          'message',
          contains('not a valid Xtream Codes server'),
        )),
      );
    });

    test('rejects server returning HTTP 404', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 404),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final client = XtreamClient(
        baseUrl: 'http://fake-iptv.com',
        username: 'user',
        password: 'password',
        dio: dio,
      );

      expect(
        () => client.authenticate(),
        throwsA(isA<XtreamServerException>().having(
          (e) => e.message,
          'message',
          contains('404'),
        )),
      );
    });
  });

  group('ProviderManager playlist verification & DB integrity', () {
    late AppDatabase db;
    late ProviderManager manager;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      manager = ProviderManager(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('refuses to add fake M3U URL that does not resolve or returns HTML', () async {
      expect(
        () => manager.addM3uProvider(
          id: 'test_fake_m3u',
          name: 'Fake M3U',
          url: 'http://127.0.0.1:59999/nonexistent.m3u',
        ),
        throwsA(isA<Exception>()),
      );

      // Verify that provider was NOT saved to SQLite database
      final providers = await db.getAllProviders();
      expect(providers, isEmpty);
    });
  });
}
