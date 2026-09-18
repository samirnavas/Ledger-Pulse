import 'package:flutter/material.dart';

class AdaptiveThemeHelper {
  /// Automatically checks whether iOS Cupertino style should be rendered based on host device OS.
  static bool isIos(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  }
}
