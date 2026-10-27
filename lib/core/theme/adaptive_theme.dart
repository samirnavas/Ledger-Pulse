import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AdaptiveThemeHelper {
  /// Automatically checks whether iOS Cupertino style should be rendered based on host device OS.
  static bool isIos(BuildContext context) {
    try {
      final platform = Theme.of(context).platform;
      if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
        return true;
      }
    } catch (_) {
      // Fallback to defaultTargetPlatform if context lacks Theme widget (e.g. unmounted in unit tests)
    }
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }
}

