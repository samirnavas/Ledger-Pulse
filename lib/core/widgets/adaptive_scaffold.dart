import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final Widget? leading;
  final Widget? drawer;

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
    this.leading,
    this.drawer,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    if (isIos) {
      final cupertinoScaffold = CupertinoPageScaffold(
        backgroundColor: backgroundColor ??
            (isDark
                ? const Color(0xFF0F172A)
                : const Color(0xFFF1F5F9)),
        navigationBar: CupertinoNavigationBar(
          backgroundColor: isDark
              ? const Color(0xCC0F172A)
              : AppColors.cupertinoBarBackground,
          border: Border(
            bottom: BorderSide(
              color: isDark
                  ? const Color(0x33475569)
                  : AppColors.borderLight,
              width: 0.5,
            ),
          ),
          leading: leading ?? (drawer != null
              ? Builder(
                  builder: (ctx) => CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                    child: const Icon(CupertinoIcons.bars, size: 24),
                  ),
                )
              : null),
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

      if (drawer != null) {
        return Scaffold(
          drawer: drawer,
          backgroundColor: Colors.transparent,
          body: cupertinoScaffold,
        );
      }
      return cupertinoScaffold;
    } else {
      // Android Material 3 Expressive
      final scheme = Theme.of(context).colorScheme;
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness:
              isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: scheme.surfaceContainerLow,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: backgroundColor ?? scheme.surfaceContainerLow,
          appBar: AppBar(
            leading: leading,
            title: titleWidget ?? (title != null ? Text(title!) : null),
            actions: actions,
            bottom: bottomAppBar,
            backgroundColor: scheme.surfaceContainerLow,
            foregroundColor: scheme.onSurface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              statusBarBrightness:
                  isDark ? Brightness.dark : Brightness.light,
            ),
          ),
          drawer: drawer,
          body: body,
          floatingActionButton: floatingActionButton,
          bottomNavigationBar: bottomNavigationBar,
        ),
      );
    }
  }
}

