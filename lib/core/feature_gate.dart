// YesXtream feature tier system.
//
// Free tier includes all core IPTV functionality. Pro tier unlocks
// higher provider limits. The gate is lightweight — check
// [FeatureGate.isPro] / [FeatureGate.maxProviders] before enabling.

enum AppTier { free, pro }

/// Centralized feature gating. All pro checks go through here
/// so changing the logic later (e.g. adding trials, per-feature
/// purchases) only requires editing this one file.
class FeatureGate {
  static AppTier _currentTier = AppTier.pro;

  static AppTier get currentTier => _currentTier;
  static bool get isPro => _currentTier == AppTier.pro;
  static bool get isFree => _currentTier == AppTier.free;

  /// Called once at startup (or after purchase/restore).
  static void setTier(AppTier tier) => _currentTier = tier;

  /// Max providers allowed.
  static int get maxProviders => isPro ? 999 : 2;

  /// Max EPG sources allowed.
  static int get maxEpgSources => isPro ? 20 : 2;
}
