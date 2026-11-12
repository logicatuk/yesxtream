import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Detects the current platform type for UI adaptation.
///
/// On Android TV / Fire TV, we query the native Android hardware/UI mode
/// (LEANBACK / TELEVISION / amazon.hardware.fire_tv / no touchscreen) and fall
/// back to MediaQuery heuristics on Web TVs (LG webOS, Samsung Tizen).
class PlatformInfo {
  PlatformInfo._();

  static const _platformChannel =
      MethodChannel('io.github.clubanderson.clubtivi/platform');

  static bool? _isTvOverride;
  static bool _nativeTvDetected = false;
  static bool _nativeChecked = false;

  /// Force TV mode (useful for testing on desktop with keyboard).
  static void setTvOverride(bool value) => _isTvOverride = value;

  /// Query native platform once before runApp() to reliably identify
  /// Fire TV Stick, Android TV, and leanback/non-touch Android devices.
  static Future<void> init() async {
    if (_nativeChecked || !isAndroid) return;
    _nativeChecked = true;
    try {
      final result = await _platformChannel.invokeMethod<bool>('isTvDevice');
      if (result == true) {
        _nativeTvDetected = true;
        _detectedAsTV = true;
      }
    } catch (_) {
      // Tests / headless runs where native plugin channel isn't mounted.
    }
  }

  /// True when running on a TV (Android TV, Fire TV, Samsung Tizen, LG webOS).
  static bool get isTV {
    if (_isTvOverride != null) return _isTvOverride!;
    return _nativeTvDetected || _detectedAsTV;
  }

  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  static bool get isMacOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  static bool get isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool get isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool get isMobile {
    return (isAndroid || isIOS) && !isTV;
  }

  static bool get isDesktop {
    return isMacOS || isLinux || isWindows;
  }

  /// Cached TV detection result (set after first MediaQuery access or native init).
  static bool _detectedAsTV = false;

  /// Call this once from a widget that has access to [MediaQuery].
  /// Detects TV by native Android flags, screen size, shortest side, and
  /// directional navigation mode.
  static void detectFromContext(BuildContext context) {
    if (_isTvOverride != null) return;
    if (_nativeTvDetected) {
      _detectedAsTV = true;
      return;
    }

    final data = MediaQuery.of(context);
    final size = data.size;
    final shortest = size.shortestSide;
    final hasDirectionalNav = data.navigationMode == NavigationMode.directional;
    final isTvScreen = shortest >= 480 && size.width > size.height;

    if (kIsWeb) {
      _detectedAsTV = hasDirectionalNav || (isTvScreen && data.devicePixelRatio <= 2.0);
      return;
    }

    if (isAndroid) {
      _detectedAsTV = hasDirectionalNav || (isTvScreen && data.devicePixelRatio <= 2.0);
    }
  }

  /// Returns a UI scale factor for TV screens (LG webOS, Samsung Tizen, Android TV).
  ///
  /// Keeps text and theme targets comfortably legible from 10 feet while
  /// avoiding overflow inside fixed-height lists and bars. Full-dashboard views
  /// (like Home) scale proportionally via responsive layout constraints.
  static double tvScaleFactor(BuildContext context) {
    if (!isTV) return 1.0;
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 1600) return 1.3;
    if (w >= 1200) return 1.2;
    if (w >= 800) return 1.1;
    return 1.0;
  }
}
