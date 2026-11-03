import 'dart:io' show Platform;

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

  static bool get isMobile {
    if (kIsWeb) return false;
    return (Platform.isAndroid || Platform.isIOS) && !isTV;
  }

  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isLinux || Platform.isWindows;
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

    if (Platform.isAndroid) {
      _detectedAsTV = hasDirectionalNav || (isTvScreen && data.devicePixelRatio < 2.0);
    }
  }
}
