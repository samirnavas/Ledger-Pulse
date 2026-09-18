import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../theme/adaptive_theme.dart';

/// Displays a platform-adaptive confirmation dialog asking the user whether
/// they want to discard unsaved changes.
///
/// Returns `true` if the user chooses to discard, and `false` or `null` otherwise.
Future<bool> showDiscardChangesDialog(BuildContext context) async {
  final isIos = AdaptiveThemeHelper.isIos(context);

  if (isIos) {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
          'You have unsaved changes that will be lost if you leave.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep Editing'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return result ?? false;
  } else {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        title: const Text(
          'Discard unsaved changes?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19),
        ),
        content: Text(
          'You have unsaved changes that will be lost if you leave.',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Keep Editing',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.payableRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Discard',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
