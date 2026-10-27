import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/colors.dart';
import '../../../core/constants/strings.dart';
import '../../../core/constants/typography.dart';
import '../../../core/theme/adaptive_theme.dart';
import '../../../core/widgets/amount_text.dart';
import '../../../data/models/party_model.dart';

/// Top sticky header for PartyLedgerScreen displaying initials/avatar, phone, call button, and net balance.
class PartyLedgerHeroHeader extends StatelessWidget {
  final Party party;
  final VoidCallback onCall;

  const PartyLedgerHeroHeader({
    super.key,
    required this.party,
    required this.onCall,
  });

  String _getInitials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'P';
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: isIos
            ? (isDark
                ? const Color(0xFF141414).withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.8))
            : (isDark
                ? Colors.black
                : Theme.of(context).colorScheme.surfaceContainerLow),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: isDark ? 0.35 : 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (!isIos) ...[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _getInitials(party.name),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              // Phone & Quick Call Action
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: onCall,
                    child: Text(
                      party.phoneNumber,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: onCall,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isIos ? CupertinoIcons.phone_fill : Icons.call_rounded,
                            size: 13,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            AppStrings.callParty,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Net Balance in Bold Typography
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                party.netBalanceInCents > 0
                    ? "YOU'LL GET"
                    : party.netBalanceInCents < 0
                        ? "YOU'LL GIVE"
                        : 'SETTLED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: party.netBalanceInCents > 0
                      ? (isDark
                          ? const Color(0xFF4ADE80)
                          : AppColors.receivableGreenDark)
                      : party.netBalanceInCents < 0
                          ? (isDark
                              ? const Color(0xFFF87171)
                              : AppColors.payableRedDark)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              AmountText(
                amountInCents: party.netBalanceInCents,
                variant: AmountVariant.large,
                absolute: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
