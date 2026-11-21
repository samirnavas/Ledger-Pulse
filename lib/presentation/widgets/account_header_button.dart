import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme/adaptive_theme.dart';

class AccountHeaderButton extends StatelessWidget {
  const AccountHeaderButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final colors = Theme.of(context).colorScheme;
    final avatar = CircleAvatar(
      radius: 17,
      backgroundColor: colors.secondaryContainer,
      foregroundColor: colors.onSecondaryContainer,
      child: Icon(
        isIos ? CupertinoIcons.person_fill : Icons.person_rounded,
        size: 20,
      ),
    );
    if (isIos) {
      return Tooltip(
        message: 'My Account',
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          onPressed: onPressed,
          child: avatar,
        ),
      );
    }
    return IconButton(
      icon: avatar,
      tooltip: 'My Account',
      onPressed: onPressed,
    );
  }
}
