import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Detects the current platform type for UI adaptation.
///
/// On Android TV, there is no touchscreen and the screen is typically
/// large and landscape. We use these heuristics to decide whether to
/// show the 10-foot TV UI (sidebar nav, large focus rings, D-pad nav)
/// or the standard mobile/desktop UI.
class PlatformInfo {
  PlatformInfo._();

  static bool? _isTvOverride;

  /// Force TV mode (useful for testing on desktop with keyboard).
  static void setTvOverride(bool value) => _isTvOverride = value;

  /// True when running on a TV (Android TV, Fire TV, Samsung Tizen, LG webOS).
  static bool get isTV {
    if (_isTvOverride != null) return _isTvOverride!;
    return _detectedAsTV;
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

  /// Cached TV detection result (set after first MediaQuery access).
  static bool _detectedAsTV = false;

  /// Call this once from a widget that has access to [MediaQuery].
  /// Detects TV by screen size, shortest side, and directional navigation mode.
  static void detectFromContext(BuildContext context) {
    if (_isTvOverride != null) return;

    final data = MediaQuery.of(context);
    final size = data.size;
    final shortest = size.shortestSide;
    final hasDirectionalNav = data.navigationMode == NavigationMode.directional;
    final isTvScreen = shortest >= 540 && size.width > size.height;

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
