import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import '../theme/adaptive_theme.dart';

/// An adaptive bottom navigation bar implementing Material 3 NavigationBar on Android
/// and frosted RealLiquidGlass CupertinoTabBar on iOS.
class AdaptiveBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AdaptiveBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: RealLiquidGlass(
          borderRadius: 28,
          blur: 24,
          child: CupertinoTabBar(
            backgroundColor: Colors.transparent,
            currentIndex: currentIndex,
            onTap: onTap,
            items: const [
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
            ],
          ),
        ),
      );
    }

    // Android Material 3 Expressive NavigationBar
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onTap,
      destinations: const [
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
      ],
    );
  }
}
