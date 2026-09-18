import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../theme/adaptive_theme.dart';

class AdaptiveScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final PreferredSizeWidget? bottomAppBar;

  const AdaptiveScaffold({
    super.key,
    required this.body,
    this.title,
    this.titleWidget,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.bottomAppBar,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      return CupertinoPageScaffold(
        backgroundColor: backgroundColor ?? AppColors.cupertinoSystemBackground,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: AppColors.cupertinoBarBackground,
          border: const Border(
            bottom: BorderSide(color: AppColors.borderLight, width: 0.5),
          ),
          middle: titleWidget ?? (title != null ? Text(title!) : null),
          trailing: actions == null || actions!.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions!,
                ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              ?bottomAppBar,
              Expanded(child: body),
              ?bottomNavigationBar,
            ],
          ),
        ),
      );
    } else {
      // Android Material 3 Expressive
      return Scaffold(
        backgroundColor: backgroundColor ?? AppColors.surfaceLight,
        appBar: AppBar(
          title: titleWidget ?? (title != null ? Text(title!) : null),
          actions: actions,
          bottom: bottomAppBar,
          backgroundColor: AppColors.surfaceWhite,
          surfaceTintColor: Colors.transparent,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      );
    }
  }
}
