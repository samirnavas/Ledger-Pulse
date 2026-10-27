import 'package:flutter/material.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/typography.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../data/models/party_model.dart';

/// Statement Header Card displaying Party name, type, phone, and total gave/got stats.
class StatementHeaderCard extends StatelessWidget {
  final Party party;
  final int totalGave;
  final int totalGot;

  const StatementHeaderCard({
    super.key,
    required this.party,
    required this.totalGave,
    required this.totalGot,
  });

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      return LiquidGlassContainer(
        padding: const EdgeInsets.all(16),
        borderRadius: 18,
        child: _buildContent(context),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.5,
              ),
          width: 1,
        ),
      ),
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              party.name,
              style: AppTypography.headlineMedium,
            ),
            Text(
              party.type.displayName,
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primaryBlue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(party.phoneNumber, style: AppTypography.bodyMedium),
        const Divider(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Gave',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.payableRed,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  CurrencyFormatter.format(totalGave),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.payableRed,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'Total Got',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.receivableGreen,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  CurrencyFormatter.format(totalGot),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.receivableGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
