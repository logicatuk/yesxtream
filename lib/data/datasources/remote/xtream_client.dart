import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../models/channel.dart';

class XtreamException implements Exception {
  final String message;
  const XtreamException(this.message);
  @override
  String toString() => message;
}

class XtreamAuthException extends XtreamException {
  const XtreamAuthException(super.message);
}

class XtreamServerException extends XtreamException {
  const XtreamServerException(super.message);
}

/// Xtream Codes API client.
///
/// Supports both Xtream Codes and XUI APIs which share the same player_api.php
/// endpoint structure. Handles authentication, category/stream listing,
/// EPG retrieval, and VOD/series catalogs.
class XtreamClient {
  final Dio _dio;
  final String baseUrl;
  final String username;
  final String password;

  XtreamClient({
    required this.baseUrl,
    required this.username,
    required this.password,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 20)
      ..receiveTimeout = const Duration(seconds: 150)
      ..headers = {
        if (!kIsWeb) 'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)',
        'Accept': '*/*',
      };
  }

  String get _cleanBaseUrl {
    var url = baseUrl.trim();
    if (!url.toLowerCase().startsWith('http://') &&
        !url.toLowerCase().startsWith('https://')) {
      url = 'http://$url';
    }
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String get _apiBase => '$_cleanBaseUrl/player_api.php';

  static dynamic _parseJson(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  Map<String, String> get _authParams => {
        'username': username,
        'password': password,
      };

  /// Authenticate and get server info + account status.
  /// Throws [XtreamAuthException] if credentials are wrong, expired, or disabled.
  /// Throws [XtreamServerException] if the server returns HTTP errors or invalid non-Xtream data.
  Future<XtreamServerInfo> authenticate() async {
    final Response<dynamic> response;
    try {
      response = await _dio.get(
        _apiBase,
        queryParameters: _authParams,
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 403) {
        throw const XtreamAuthException('Invalid username or password');
      }
      if (code == 404) {
        throw const XtreamServerException(
          'Xtream Codes API endpoint not found on this server (HTTP 404)',
        );
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw const XtreamServerException(
            'Connection timed out — the server did not respond in time',
          );
        case DioExceptionType.connectionError:
          throw const XtreamServerException(
            'Connection failed — could not reach the server',
          );
        case DioExceptionType.badResponse:
          throw XtreamServerException(
            'Server returned HTTP ${e.response?.statusCode ?? 'error'}',
          );
        default:
          final msg = e.message ?? e.type.name;
          if (msg.toLowerCase().contains('xmlhttprequest') ||
              msg.toLowerCase().contains('network layer')) {
            throw const XtreamServerException(
              'Connection failed — could not reach the server',
            );
          }
          throw XtreamServerException('Connection failed: $msg');
      }
    }

    if (response.statusCode != null && (response.statusCode! < 200 || response.statusCode! >= 300)) {
      throw XtreamServerException('Server returned HTTP ${response.statusCode}');
    }

    final data = _parseJson(response.data);
    if (data is! Map<String, dynamic>) {
      throw const XtreamServerException('Server returned an invalid response (not a valid Xtream Codes server)');
    }

    final userInfo = data['user_info'] as Map<String, dynamic>?;
    if (userInfo == null) {
      throw const XtreamServerException('Invalid Xtream server: response missing "user_info"');
    }

    final rawAuth = userInfo['auth'];
    final int authNum = rawAuth is int ? rawAuth : (int.tryParse('$rawAuth') ?? 0);
    final status = userInfo['status']?.toString().trim();
    final message = userInfo['message']?.toString().trim();

    // Check auth flag: 0 means authentication failed
    if (authNum == 0) {
      final reason = (message != null && message.isNotEmpty)
          ? message
          : (status != null && status.isNotEmpty
              ? 'Account $status'
              : 'Invalid username or password');
      throw XtreamAuthException('Login failed: $reason');
    }

    // Check account status if present
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'active') {
      final reason = (message != null && message.isNotEmpty) ? message : status;
      throw XtreamAuthException('Account is not active ($reason)');
    }

    // Check account expiration if specified
    final exp = userInfo['exp_date'];
    if (exp != null && exp != '' && exp != 'null') {
      final expSec = int.tryParse(exp.toString());
      if (expSec != null && expSec > 0) {
        final expDate = DateTime.fromMillisecondsSinceEpoch(expSec * 1000);
        if (DateTime.now().isAfter(expDate)) {
          final dateStr = expDate.toLocal().toString().split(' ')[0];
          throw XtreamAuthException('Account subscription expired on $dateStr');
        }
      }
    }

    return XtreamServerInfo.fromJson(data);
  }

  /// Get live stream categories.
  Future<List<XtreamCategory>> getLiveCategories() async {
    final response = await _dio.get(
      _apiBase,
      queryParameters: {..._authParams, 'action': 'get_live_categories'},
    );
    final rawList = _parseJson(response.data);
    if (rawList is! List) return [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(XtreamCategory.fromJson)
        .toList();
  }

  /// Get all live streams, optionally filtered by category.
  Future<List<Channel>> getLiveStreams({
    String? categoryId,
    required String providerId,
    Map<String, String>? categoryMap,
  }) async {
    final params = {..._authParams, 'action': 'get_live_streams'};
    if (categoryId != null) params['category_id'] = categoryId;

    final response = await _dio.get(_apiBase, queryParameters: params);
    final rawList = _parseJson(response.data);
    if (rawList is! List) return [];
    final out = <Channel>[];
    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is Map<String, dynamic>) {
        final ch = _channelFromXtream(item, providerId, categoryMap: categoryMap);
        if (ch != null) out.add(ch);
      }
      if (i > 0 && i % 2500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return out;
  }

  /// Get set of stream IDs (as strings) that have server-side archive enabled (tv_archive == 1).
  Future<Set<String>> getArchiveStreamIds() async {
    try {
      final params = {..._authParams, 'action': 'get_live_streams'};
      final response = await _dio.get(_apiBase, queryParameters: params);
      final rawList = _parseJson(response.data);
      if (rawList is! List) return {};
      final ids = <String>{};
      for (final item in rawList) {
        if (item is Map<String, dynamic>) {
          final arch = item['tv_archive'];
          if (arch == 1 || arch == '1' || arch == true) {
            final sid = item['stream_id']?.toString();
            if (sid != null && sid.isNotEmpty) {
              ids.add(sid);
            }
          }
        }
      }
      return ids;
    } catch (_) {
      return {};
    }
  }

  /// Get VOD categories.
  Future<List<XtreamCategory>> getVodCategories() async {
    final response = await _dio.get(
      _apiBase,
      queryParameters: {..._authParams, 'action': 'get_vod_categories'},
    );
    final rawList = _parseJson(response.data);
    if (rawList is! List) return [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(XtreamCategory.fromJson)
        .toList();
  }

  /// Get VOD streams, optionally filtered by category.
  Future<List<Channel>> getVodStreams({
    String? categoryId,
    required String providerId,
    Map<String, String>? categoryMap,
  }) async {
    final params = {..._authParams, 'action': 'get_vod_streams'};
    if (categoryId != null) params['category_id'] = categoryId;

    final response = await _dio.get(_apiBase, queryParameters: params);
    final rawList = _parseJson(response.data);
    if (rawList is! List) return [];
    final out = <Channel>[];
    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is Map<String, dynamic>) {
        final ch = _vodFromXtream(item, providerId, categoryMap: categoryMap);
        if (ch != null) out.add(ch);
      }
      if (i > 0 && i % 2500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return out;
  }

  /// Get series categories.
  Future<List<XtreamCategory>> getSeriesCategories() async {
    final response = await _dio.get(
      _apiBase,
      queryParameters: {..._authParams, 'action': 'get_series_categories'},
    );
    final rawList = _parseJson(response.data);
    if (rawList is! List) return [];
    return rawList
        .whereType<Map<String, dynamic>>()
        .map(XtreamCategory.fromJson)
        .toList();
  }

  /// Get series list.
  Future<List<Channel>> getSeriesStreams({
    String? categoryId,
    required String providerId,
    Map<String, String>? categoryMap,
  }) async {
    final params = {..._authParams, 'action': 'get_series'};
    if (categoryId != null) params['category_id'] = categoryId;

    final response = await _dio.get(_apiBase, queryParameters: params);
    final rawList = _parseJson(response.data);
    if (rawList is! List) return [];
    final out = <Channel>[];
    for (var i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is Map<String, dynamic>) {
        final ch = _seriesFromXtream(item, providerId, categoryMap: categoryMap);
        if (ch != null) out.add(ch);
      }
      if (i > 0 && i % 2500 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return out;
  }

  /// Get short EPG for a specific stream (current + next few programs).
  Future<List<XtreamEpgEntry>> getShortEpg(String streamId) async {
    final response = await _dio.get(
      _apiBase,
      queryParameters: {
        ..._authParams,
        'action': 'get_short_epg',
        'stream_id': streamId,
      },
    );
    final data = response.data as Map<String, dynamic>;
    final listings = data['epg_listings'] as List? ?? [];
    return listings
        .map((e) => XtreamEpgEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Build a live stream URL.
  String buildLiveUrl(int streamId, {String extension = 'ts'}) {
    return '$_cleanBaseUrl/live/$username/$password/$streamId.$extension';
  }

  /// Build a VOD stream URL.
  String buildVodUrl(int streamId, {String extension = 'mp4'}) {
    return '$_cleanBaseUrl/movie/$username/$password/$streamId.$extension';
  }

  /// Build a series episode stream URL.
  String buildSeriesEpisodeUrl(dynamic episodeId, {String extension = 'mp4'}) {
    return '$_cleanBaseUrl/series/$username/$password/$episodeId.$extension';
  }

  /// Get series info including all seasons and episode streams from Xtream Codes.
  Future<Map<String, dynamic>> getSeriesInfo(String seriesId) async {
    try {
      final response = await _dio.get(
        _apiBase,
        queryParameters: {
          ..._authParams,
          'action': 'get_series_info',
          'series_id': seriesId,
        },
      );
      final data = _parseJson(response.data);
      if (data is Map<String, dynamic>) {
        return data;
      }
    } catch (_) {}
    return {};
  }

  /// Get full EPG listings for a live stream with automatic Base64 decoding.
  Future<List<XtreamEpgEntry>> getSimpleDataTable(String streamId) async {
    try {
      final response = await _dio.get(
        _apiBase,
        queryParameters: {
          ..._authParams,
          'action': 'get_simple_data_table',
          'stream_id': streamId,
        },
      );
      final data = _parseJson(response.data);
      if (data is Map<String, dynamic>) {
        final listings = (data['epg_listings'] as List?) ?? [];
        return listings.map((e) => XtreamEpgEntry.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Get VOD info including plot, cast, director, rating, releaseDate, trailer, tmdb_id.
  Future<Map<String, dynamic>> getVodInfo(String vodId) async {
    try {
      final response = await _dio.get(
        _apiBase,
        queryParameters: {
          ..._authParams,
          'action': 'get_vod_info',
          'vod_id': vodId,
        },
      );
      final data = _parseJson(response.data);
      if (data is Map<String, dynamic>) {
        return data;
      }
    } catch (_) {}
    return {};
  }

  Channel? _channelFromXtream(
    Map<String, dynamic> json,
    String providerId, {
    Map<String, String>? categoryMap,
  }) {
    final rawId = json['stream_id'];
    final streamId = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
    if (streamId == null) return null;
    final num = json['num'] is int ? json['num'] as int : int.tryParse('${json['num']}');
    final catId = json['category_id']?.toString();
    final catName = (catId != null && categoryMap != null && categoryMap.containsKey(catId))
        ? categoryMap[catId]
        : (json['category_name']?.toString());

    return Channel(
      id: '${providerId}_$streamId',
      providerId: providerId,
      name: json['name']?.toString() ?? 'Unknown',
      tvgId: json['epg_channel_id']?.toString(),
      tvgName: json['name']?.toString(),
      tvgLogo: json['stream_icon']?.toString(),
      groupTitle: (catName != null && catName.isNotEmpty) ? catName : 'General',
      channelNumber: num,
      streamUrl: buildLiveUrl(streamId),
      streamType: StreamType.live,
    );
  }

  Channel? _vodFromXtream(
    Map<String, dynamic> json,
    String providerId, {
    Map<String, String>? categoryMap,
  }) {
    final rawId = json['stream_id'];
    final streamId = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');
    if (streamId == null) return null;
    final rawExt = json['container_extension']?.toString();
    final ext = (rawExt != null && rawExt.isNotEmpty) ? rawExt : 'mp4';
    final catId = json['category_id']?.toString();
    final catName = (catId != null && categoryMap != null && categoryMap.containsKey(catId))
        ? categoryMap[catId]
        : (json['category_name']?.toString());

    return Channel(
      id: '${providerId}_vod_$streamId',
      providerId: providerId,
      name: json['name']?.toString() ?? 'Unknown',
      tvgLogo: json['stream_icon']?.toString(),
      groupTitle: (catName != null && catName.isNotEmpty) ? catName : 'Movies',
      streamUrl: buildVodUrl(streamId, extension: ext),
      streamType: StreamType.vod,
    );
  }

  Channel? _seriesFromXtream(
    Map<String, dynamic> json,
    String providerId, {
    Map<String, String>? categoryMap,
  }) {
    final seriesId = json['series_id']?.toString();
    if (seriesId == null || seriesId.isEmpty) return null;
    final catId = json['category_id']?.toString();
    final catName = (catId != null && categoryMap != null && categoryMap.containsKey(catId))
        ? categoryMap[catId]
        : (json['category_name']?.toString());

    return Channel(
      id: '${providerId}_series_$seriesId',
      providerId: providerId,
      name: json['name']?.toString() ?? 'Unknown',
      tvgLogo: json['cover']?.toString(),
      groupTitle: (catName != null && catName.isNotEmpty) ? catName : 'Series',
      streamUrl: '', // Series need episode lookup
      streamType: StreamType.series,
    );
  }

  void dispose() {
    _dio.close();
  }
}

/// Server info returned by authentication.
class XtreamServerInfo {
  final String? url;
  final String? port;
  final String? httpsPort;
  final String? serverProtocol;
  final String? status;
  final int? auth;
  final String? message;
  final DateTime? expDate;
  final int? maxConnections;
  final int? activeCons;
  final bool isTrial;

  const XtreamServerInfo({
    this.url,
    this.port,
    this.httpsPort,
    this.serverProtocol,
    this.status,
    this.auth,
    this.message,
    this.expDate,
    this.maxConnections,
    this.activeCons,
    this.isTrial = false,
  });

  bool get isActive => (status == null || status!.toLowerCase() == 'active') && auth != 0;

  factory XtreamServerInfo.fromJson(Map<String, dynamic> json) {
    final userInfo = json['user_info'] as Map<String, dynamic>? ?? {};
    final serverInfo = json['server_info'] as Map<String, dynamic>? ?? {};

    DateTime? expDate;
    final exp = userInfo['exp_date'];
    if (exp != null && exp != '' && exp != 'null') {
      final expSec = int.tryParse(exp.toString());
      if (expSec != null && expSec > 0) {
        expDate = DateTime.fromMillisecondsSinceEpoch(expSec * 1000);
      }
    }

    final rawAuth = userInfo['auth'];
    final int? auth = rawAuth is int ? rawAuth : int.tryParse('$rawAuth');

    return XtreamServerInfo(
      url: serverInfo['url'] as String?,
      port: serverInfo['port']?.toString(),
      httpsPort: serverInfo['https_port']?.toString(),
      serverProtocol: serverInfo['server_protocol'] as String?,
      status: userInfo['status'] as String?,
      auth: auth,
      message: userInfo['message']?.toString(),
      expDate: expDate,
      maxConnections: int.tryParse('${userInfo['max_connections']}'),
      activeCons: int.tryParse('${userInfo['active_cons']}'),
      isTrial: userInfo['is_trial'] == '1',
    );
  }
}

/// Xtream category (live, VOD, or series).
class XtreamCategory {
  final String id;
  final String name;
  final int? parentId;

  const XtreamCategory({
    required this.id,
    required this.name,
    this.parentId,
  });

  factory XtreamCategory.fromJson(Map<String, dynamic> json) {
    return XtreamCategory(
      id: json['category_id']?.toString() ?? '',
      name: json['category_name'] as String? ?? '',
      parentId: int.tryParse('${json['parent_id']}'),
    );
  }
}

/// Single EPG entry from Xtream short EPG / simple data table.
class XtreamEpgEntry {
  final String title;
  final String description;
  final DateTime? start;
  final DateTime? end;
  final bool hasArchive;

  const XtreamEpgEntry({
    required this.title,
    this.description = '',
    this.start,
    this.end,
    this.hasArchive = false,
  });

  static String _decodeBase64IfNeeded(String input) {
    if (input.isEmpty) return '';
    try {
      final trimmed = input.trim();
      if (trimmed.length % 4 == 0 && RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(trimmed)) {
        final decodedBytes = base64.decode(trimmed);
        final decoded = utf8.decode(decodedBytes);
        if (decoded.isNotEmpty) return decoded;
      }
    } catch (_) {}
    return input;
  }

  factory XtreamEpgEntry.fromJson(Map<String, dynamic> json) {
    final rawTitle = json['title'] as String? ?? '';
    final rawDesc = json['description'] as String? ?? '';
    final hasArch = json['has_archive'] == 1 || json['has_archive'] == '1';

    return XtreamEpgEntry(
      title: _decodeBase64IfNeeded(rawTitle),
      description: _decodeBase64IfNeeded(rawDesc),
      start: DateTime.tryParse(json['start'] as String? ?? ''),
      end: DateTime.tryParse(json['end'] as String? ?? ''),
      hasArchive: hasArch,
    );
  }
}
