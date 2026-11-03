import 'dart:convert';
import 'package:dio/dio.dart';
import '../../models/channel.dart';

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
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 45)
      ..headers = {
        'User-Agent': 'IPTVSmartersPro/1.0.0 (Linux; Android 12)',
        'Accept': '*/*',
      }
      ..validateStatus = (status) => status != null && status < 900;
  }

  String get _apiBase {
    final clean = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$clean/player_api.php';
  }

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
  Future<XtreamServerInfo> authenticate() async {
    final response = await _dio.get(
      _apiBase,
      queryParameters: _authParams,
    );
    final data = _parseJson(response.data);
    if (data is Map<String, dynamic>) {
      return XtreamServerInfo.fromJson(data);
    }
    throw Exception('Invalid server response');
  }

  /// Get live stream categories.
  Future<List<XtreamCategory>> getLiveCategories() async {
    final response = await _dio.get(
      _apiBase,
      queryParameters: {..._authParams, 'action': 'get_live_categories'},
    );
    if (response.data is! List) return [];
    return (response.data as List)
        .map((e) => XtreamCategory.fromJson(e as Map<String, dynamic>))
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
    if (response.data is! List) return [];
    return (response.data as List).map((e) {
      final json = e as Map<String, dynamic>;
      return _channelFromXtream(json, providerId, categoryMap: categoryMap);
    }).toList();
  }

  /// Get VOD categories.
  Future<List<XtreamCategory>> getVodCategories() async {
    final response = await _dio.get(
      _apiBase,
      queryParameters: {..._authParams, 'action': 'get_vod_categories'},
    );
    if (response.data is! List) return [];
    return (response.data as List)
        .map((e) => XtreamCategory.fromJson(e as Map<String, dynamic>))
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
    if (response.data is! List) return [];
    return (response.data as List).map((e) {
      final json = e as Map<String, dynamic>;
      return _vodFromXtream(json, providerId, categoryMap: categoryMap);
    }).toList();
  }

  /// Get series categories.
  Future<List<XtreamCategory>> getSeriesCategories() async {
    final response = await _dio.get(
      _apiBase,
      queryParameters: {..._authParams, 'action': 'get_series_categories'},
    );
    if (response.data is! List) return [];
    return (response.data as List)
        .map((e) => XtreamCategory.fromJson(e as Map<String, dynamic>))
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
    if (response.data is! List) return [];
    return (response.data as List).map((e) {
      final json = e as Map<String, dynamic>;
      return _seriesFromXtream(json, providerId, categoryMap: categoryMap);
    }).toList();
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
    return '$baseUrl/live/$username/$password/$streamId.$extension';
  }

  /// Build a VOD stream URL.
  String buildVodUrl(int streamId, {String extension = 'mp4'}) {
    return '$baseUrl/movie/$username/$password/$streamId.$extension';
  }

  /// Build a series episode stream URL.
  String buildSeriesEpisodeUrl(dynamic episodeId, {String extension = 'mp4'}) {
    return '$baseUrl/series/$username/$password/$episodeId.$extension';
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

  Channel _channelFromXtream(
    Map<String, dynamic> json,
    String providerId, {
    Map<String, String>? categoryMap,
  }) {
    final streamId = json['stream_id'];
    final num = json['num'] is int ? json['num'] as int : int.tryParse('${json['num']}');
    final catId = json['category_id']?.toString();
    final catName = (catId != null && categoryMap != null && categoryMap.containsKey(catId))
        ? categoryMap[catId]
        : (json['category_name'] as String?);

    return Channel(
      id: '${providerId}_$streamId',
      providerId: providerId,
      name: json['name'] as String? ?? 'Unknown',
      tvgId: json['epg_channel_id'] as String?,
      tvgName: json['name'] as String?,
      tvgLogo: json['stream_icon'] as String?,
      groupTitle: (catName != null && catName.isNotEmpty) ? catName : 'General',
      channelNumber: num,
      streamUrl: buildLiveUrl(streamId as int),
      streamType: StreamType.live,
    );
  }

  Channel _vodFromXtream(
    Map<String, dynamic> json,
    String providerId, {
    Map<String, String>? categoryMap,
  }) {
    final streamId = json['stream_id'];
    final ext = json['container_extension'] as String? ?? 'mp4';
    final catId = json['category_id']?.toString();
    final catName = (catId != null && categoryMap != null && categoryMap.containsKey(catId))
        ? categoryMap[catId]
        : (json['category_name'] as String?);

    return Channel(
      id: '${providerId}_vod_$streamId',
      providerId: providerId,
      name: json['name'] as String? ?? 'Unknown',
      tvgLogo: json['stream_icon'] as String?,
      groupTitle: (catName != null && catName.isNotEmpty) ? catName : 'Movies',
      streamUrl: buildVodUrl(streamId as int, extension: ext),
      streamType: StreamType.vod,
    );
  }

  Channel _seriesFromXtream(
    Map<String, dynamic> json,
    String providerId, {
    Map<String, String>? categoryMap,
  }) {
    final seriesId = json['series_id'];
    final catId = json['category_id']?.toString();
    final catName = (catId != null && categoryMap != null && categoryMap.containsKey(catId))
        ? categoryMap[catId]
        : (json['category_name'] as String?);

    return Channel(
      id: '${providerId}_series_$seriesId',
      providerId: providerId,
      name: json['name'] as String? ?? 'Unknown',
      tvgLogo: json['cover'] as String?,
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
    this.expDate,
    this.maxConnections,
    this.activeCons,
    this.isTrial = false,
  });

  bool get isActive => status == 'Active';

  factory XtreamServerInfo.fromJson(Map<String, dynamic> json) {
    final userInfo = json['user_info'] as Map<String, dynamic>? ?? {};
    final serverInfo = json['server_info'] as Map<String, dynamic>? ?? {};

    DateTime? expDate;
    final exp = userInfo['exp_date'];
    if (exp != null && exp != '' && exp != 'null') {
      expDate = DateTime.fromMillisecondsSinceEpoch(
        int.parse(exp.toString()) * 1000,
      );
    }

    return XtreamServerInfo(
      url: serverInfo['url'] as String?,
      port: serverInfo['port']?.toString(),
      httpsPort: serverInfo['https_port']?.toString(),
      serverProtocol: serverInfo['server_protocol'] as String?,
      status: userInfo['status'] as String?,
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
