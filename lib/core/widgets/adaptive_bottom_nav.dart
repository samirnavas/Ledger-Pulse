import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import '../theme/adaptive_theme.dart';

/// An adaptive bottom navigation bar implementing Material 3 NavigationBar on Android
/// and frosted RealLiquidGlass CupertinoTabBar on iOS.
class AdaptiveBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isPartiesEnabled;
  final List<BottomNavigationBarItem>? iosItems;
  final List<NavigationDestination>? destinations;

  const AdaptiveBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.isPartiesEnabled = true,
    this.iosItems,
    this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      if (!isPartiesEnabled && iosItems == null) {
        return const SizedBox.shrink();
      }

      final items = iosItems ??
          const [
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.person_2),
              activeIcon: Icon(CupertinoIcons.person_2_fill),
              label: 'Customers',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.archivebox),
              activeIcon: Icon(CupertinoIcons.archivebox_fill),
              label: 'Suppliers',
            ),
            BottomNavigationBarItem(
              icon: Icon(CupertinoIcons.person_crop_circle),
              activeIcon: Icon(CupertinoIcons.person_crop_circle_fill),
              label: 'Profile',
            ),
          ];

      if (items.length < 2) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: RealLiquidGlass(
          borderRadius: 28,
          blur: 24,
          child: CupertinoTabBar(
            backgroundColor: Colors.transparent,
            currentIndex: currentIndex.clamp(0, items.length - 1),
            onTap: onTap,
            items: items,
          ),
        ),
      );
    }

    if (!isPartiesEnabled && destinations == null) {
      return const SizedBox.shrink();
    }

    final effectiveDestinations = destinations ??
        const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Suppliers',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Profile',
          ),
        ];

    // Material 3 NavigationBar requires at least 2 destinations
    if (effectiveDestinations.length < 2) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Android Material 3 Expressive NavigationBar
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black : null,
        border: isDark
            ? Border(
                top: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.3),
                  width: 1,
                ),
              )
            : null,
      ),
      child: NavigationBar(
        backgroundColor: isDark
            ? Colors.black
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        selectedIndex: currentIndex.clamp(0, effectiveDestinations.length - 1),
        onDestinationSelected: onTap,
        destinations: effectiveDestinations,
      ),
    );
  }
}
