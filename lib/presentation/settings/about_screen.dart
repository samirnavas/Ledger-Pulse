import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/strings.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/adaptive_surface_card.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const _appInfo = MethodChannel(
    'com.ledgerpulse.ledger_pulse/app_info',
  );
  late final _version = _loadVersion();

  Future<String?> _loadVersion() async {
    try {
      return await _appInfo.invokeMethod<String>('getVersion');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdaptiveScaffold(
      title: 'About',
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdaptiveSurfaceCard(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/icons/app_icon.png',
                        width: 64,
                        height: 64,
                        excludeFromSemantics: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(AppStrings.appName, style: theme.textTheme.titleLarge),
                    FutureBuilder<String?>(
                      future: _version,
                      builder: (context, snapshot) {
                        final version = snapshot.data;
                        return version == null
                            ? const SizedBox.shrink()
                            : Text('Version $version');
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Personal expense tracking and business bookkeeping.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AdaptiveSurfaceCard(
                padding: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    title: const Text('Open-source licenses'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final version = await _version;
                      if (!context.mounted) return;
                      Navigator.of(context).push(
                        createAdaptivePageRoute(
                          builder: (_) => LicensePage(
                            applicationName: AppStrings.appName,
                            applicationVersion: version,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
