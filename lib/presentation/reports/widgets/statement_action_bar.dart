import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/strings.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/widgets/adaptive_button.dart';

/// Persistent bottom action bar for sharing on WhatsApp and exporting PDF statements.
class StatementActionBar extends StatelessWidget {
  final bool isExporting;
  final VoidCallback onShareWhatsApp;
  final VoidCallback onExportPdf;

  const StatementActionBar({
    super.key,
    required this.isExporting,
    required this.onShareWhatsApp,
    required this.onExportPdf,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: isIos
            ? CupertinoColors.systemBackground
            : Theme.of(context).colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.35
                      : 0.5,
                ),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Share on WhatsApp
          Expanded(
            child: AdaptiveButton(
              onPressed: onShareWhatsApp,
              type: AdaptiveButtonType.secondary,
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isIos ? CupertinoIcons.chat_bubble_fill : Icons.chat_rounded,
                    size: 18,
                    color: const Color(0xFF25D366),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'WhatsApp',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Export PDF
          Expanded(
            child: AdaptiveButton(
              onPressed: isExporting ? () {} : onExportPdf,
              type: AdaptiveButtonType.primary,
              height: 48,
              child: isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isIos
                              ? CupertinoIcons.doc_text_fill
                              : Icons.picture_as_pdf_rounded,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          AppStrings.exportPdf,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
