import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/localization/app_translations.dart';

class AppSettings {
  final bool autoPreview;
  final bool autoplayNextEpisode;
  final String preferredAudioLanguage;
  final String fallbackAudioLanguage;
  final String subtitleMode; // 'Off', 'On', 'Auto'
  final String preferredSubtitleLanguage;
  final String clockFormat; // '12-hour', '24-hour'
  final String startupPage; // 'Home', 'Live TV'
  final String textSize; // 'Small', 'Normal', 'Large'
  final String language; // 'English', 'Français', etc.
  final bool parentalControlsEnabled;
  final String parentalPin;
  final List<String> lockedCategories;

  // Pro IPTV Player Settings
  final String streamFormat; // 'ts' (MPEG-TS) or 'm3u8' (HLS)
  final int epgTimeShiftHours; // -12 to +12 hours offset
  final bool hardwareAcceleration; // Hardware GPU decoding vs software
  final bool autoRefreshOnStartup; // Automatically refresh channels & EPG on launch
  final String defaultAspectRatio; // 'Fit (Auto)', '16:9', '4:3', 'Fill / Stretch', 'Zoom'
  final String bufferMode; // 'standard', 'low_latency', 'ultra'

  const AppSettings({
    this.autoPreview = true,
    this.autoplayNextEpisode = true,
    this.preferredAudioLanguage = 'English',
    this.fallbackAudioLanguage = 'English',
    this.subtitleMode = 'Off',
    this.preferredSubtitleLanguage = 'English',
    this.clockFormat = '24-hour',
    this.startupPage = 'Home',
    this.textSize = 'Normal',
    this.language = 'English',
    this.parentalControlsEnabled = false,
    this.parentalPin = '',
    this.lockedCategories = const [],
    this.streamFormat = 'ts',
    this.epgTimeShiftHours = 0,
    this.hardwareAcceleration = true,
    this.autoRefreshOnStartup = false,
    this.defaultAspectRatio = 'Fit (Auto)',
    this.bufferMode = 'standard',
  });

  /// Localized string lookup for current settings language
  String tr(String key) => AppTranslations.tr(key, language);

  /// RTL layout detection (Arabic)
  bool get isRtl => AppTranslations.isRtl(language);

  AppSettings copyWith({
    bool? autoPreview,
    bool? autoplayNextEpisode,
    String? preferredAudioLanguage,
    String? fallbackAudioLanguage,
    String? subtitleMode,
    String? preferredSubtitleLanguage,
    String? clockFormat,
    String? startupPage,
    String? textSize,
    String? language,
    bool? parentalControlsEnabled,
    String? parentalPin,
    List<String>? lockedCategories,
    String? streamFormat,
    int? epgTimeShiftHours,
    bool? hardwareAcceleration,
    bool? autoRefreshOnStartup,
    String? defaultAspectRatio,
    String? bufferMode,
  }) {
    return AppSettings(
      autoPreview: autoPreview ?? this.autoPreview,
      autoplayNextEpisode: autoplayNextEpisode ?? this.autoplayNextEpisode,
      preferredAudioLanguage: preferredAudioLanguage ?? this.preferredAudioLanguage,
      fallbackAudioLanguage: fallbackAudioLanguage ?? this.fallbackAudioLanguage,
      subtitleMode: subtitleMode ?? this.subtitleMode,
      preferredSubtitleLanguage: preferredSubtitleLanguage ?? this.preferredSubtitleLanguage,
      clockFormat: clockFormat ?? this.clockFormat,
      startupPage: startupPage ?? this.startupPage,
      textSize: textSize ?? this.textSize,
      language: language ?? this.language,
      parentalControlsEnabled: parentalControlsEnabled ?? this.parentalControlsEnabled,
      parentalPin: parentalPin ?? this.parentalPin,
      lockedCategories: lockedCategories ?? this.lockedCategories,
      streamFormat: streamFormat ?? this.streamFormat,
      epgTimeShiftHours: epgTimeShiftHours ?? this.epgTimeShiftHours,
      hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
      autoRefreshOnStartup: autoRefreshOnStartup ?? this.autoRefreshOnStartup,
      defaultAspectRatio: defaultAspectRatio ?? this.defaultAspectRatio,
      bufferMode: bufferMode ?? this.bufferMode,
    );
  }

  /// Formats a live stream URL according to the chosen stream format ('ts' or 'm3u8').
  /// Specifically transforms Xtream live streams between .ts and .m3u8.
  String formatLiveStreamUrl(String url) {
    if (url.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;

    final path = uri.path;

    // Never transform VOD or Series or timeshift
    if (path.contains('/movie/') || path.contains('/series/') || path.contains('/timeshift/')) {
      return url;
    }

    final isLiveStream = path.contains('/live/') || path.endsWith('.ts') || path.endsWith('.m3u8');
    if (!isLiveStream) return url;

    if (kIsWeb || streamFormat == 'm3u8') {
      if (path.endsWith('.ts')) {
        final newPath = '${path.substring(0, path.length - 3)}.m3u8';
        return uri.replace(path: newPath).toString();
      }
    } else if (streamFormat == 'ts') {
      if (path.endsWith('.m3u8')) {
        final newPath = '${path.substring(0, path.length - 5)}.ts';
        return uri.replace(path: newPath).toString();
      }
    }
    return url;
  }
}

class AppSettingsNotifier extends StateNotifier<AppSettings> {
  AppSettingsNotifier() : super(const AppSettings()) {
    _load();
  }

  static const _kAutoPreview = 'setting_auto_preview';
  static const _kAutoplayNext = 'setting_autoplay_next';
  static const _kPrefAudio = 'setting_pref_audio';
  static const _kFallbackAudio = 'setting_fallback_audio';
  static const _kSubtitleMode = 'setting_sub_mode';
  static const _kPrefSubtitle = 'setting_pref_sub';
  static const _kClockFormat = 'setting_clock_format';
  static const _kStartupPage = 'setting_startup_page';
  static const _kTextSize = 'setting_text_size';
  static const _kLanguage = 'setting_language';
  static const _kParentalEnabled = 'setting_parental_enabled';
  static const _kParentalPin = 'setting_parental_pin';
  static const _kLockedCategories = 'setting_locked_cats';
  static const _kStreamFormat = 'setting_stream_format';
  static const _kEpgTimeShift = 'setting_epg_time_shift';
  static const _kHwAcc = 'setting_hardware_acc';
  static const _kAutoRefreshStartup = 'setting_auto_refresh_startup';
  static const _kAspectRatio = 'setting_aspect_ratio';
  static const _kBufferMode = 'setting_buffer_mode';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = AppSettings(
      autoPreview: prefs.getBool(_kAutoPreview) ?? true,
      autoplayNextEpisode: prefs.getBool(_kAutoplayNext) ?? true,
      preferredAudioLanguage: prefs.getString(_kPrefAudio) ?? 'English',
      fallbackAudioLanguage: prefs.getString(_kFallbackAudio) ?? 'English',
      subtitleMode: prefs.getString(_kSubtitleMode) ?? 'Off',
      preferredSubtitleLanguage: prefs.getString(_kPrefSubtitle) ?? 'English',
      clockFormat: prefs.getString(_kClockFormat) ?? '24-hour',
      startupPage: prefs.getString(_kStartupPage) ?? 'Home',
      textSize: prefs.getString(_kTextSize) ?? 'Normal',
      language: prefs.getString(_kLanguage) ?? 'English',
      parentalControlsEnabled: prefs.getBool(_kParentalEnabled) ?? false,
      parentalPin: prefs.getString(_kParentalPin) ?? '',
      lockedCategories: prefs.getStringList(_kLockedCategories) ?? const [],
      streamFormat: prefs.getString(_kStreamFormat) ?? (kIsWeb ? 'm3u8' : 'ts'),
      epgTimeShiftHours: prefs.getInt(_kEpgTimeShift) ?? 0,
      hardwareAcceleration: prefs.getBool(_kHwAcc) ?? true,
      autoRefreshOnStartup: prefs.getBool(_kAutoRefreshStartup) ?? false,
      defaultAspectRatio: prefs.getString(_kAspectRatio) ?? 'Fit (Auto)',
      bufferMode: prefs.getString(_kBufferMode) ?? 'standard',
    );
  }

  Future<void> update(AppSettings Function(AppSettings current) updater) async {
    final updated = updater(state);
    state = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoPreview, updated.autoPreview);
    await prefs.setBool(_kAutoplayNext, updated.autoplayNextEpisode);
    await prefs.setString(_kPrefAudio, updated.preferredAudioLanguage);
    await prefs.setString(_kFallbackAudio, updated.fallbackAudioLanguage);
    await prefs.setString(_kSubtitleMode, updated.subtitleMode);
    await prefs.setString(_kPrefSubtitle, updated.preferredSubtitleLanguage);
    await prefs.setString(_kClockFormat, updated.clockFormat);
    await prefs.setString(_kStartupPage, updated.startupPage);
    await prefs.setString(_kTextSize, updated.textSize);
    await prefs.setString(_kLanguage, updated.language);
    await prefs.setBool(_kParentalEnabled, updated.parentalControlsEnabled);
    await prefs.setString(_kParentalPin, updated.parentalPin);
    await prefs.setStringList(_kLockedCategories, updated.lockedCategories);
    await prefs.setString(_kStreamFormat, updated.streamFormat);
    await prefs.setInt(_kEpgTimeShift, updated.epgTimeShiftHours);
    await prefs.setBool(_kHwAcc, updated.hardwareAcceleration);
    await prefs.setBool(_kAutoRefreshStartup, updated.autoRefreshOnStartup);
    await prefs.setString(_kAspectRatio, updated.defaultAspectRatio);
    await prefs.setString(_kBufferMode, updated.bufferMode);
  }
}

final appSettingsProvider =
    StateNotifierProvider<AppSettingsNotifier, AppSettings>((ref) {
  return AppSettingsNotifier();
});
