import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/amount_text.dart';
import '../ledger/party_ledger_screen.dart';
import '../providers/ledger_providers.dart';

class PartyListTab extends ConsumerWidget {
  const PartyListTab({super.key});

  Color _getAvatarColor(String name) {
    final colors = [
      const Color(0xFF3B82F6),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFF06B6D4),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partiesAsync = ref.watch(partyListProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);

    return partiesAsync.when(
      loading: () => Center(
        child: isIos
            ? const CupertinoActivityIndicator()
            : const CircularProgressIndicator(),
      ),
      error: (err, stack) => Center(
        child: Text('Error loading parties: $err'),
      ),
      data: (parties) {
        if (parties.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline_rounded,
                    size: 64,
                    color: AppColors.textMutedLight.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No parties found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add a new customer or supplier to start tracking transactions.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: parties.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final party = parties[index];
            final avatarBg = _getAvatarColor(party.name);
            final initials = _getInitials(party.name);

            return InkWell(
              onTap: () {
                Navigator.of(context).push(
                  isIos
                      ? CupertinoPageRoute(
                          builder: (context) =>
                              PartyLedgerScreen(partyId: party.id),
                        )
                      : MaterialPageRoute(
                          builder: (context) =>
                              PartyLedgerScreen(partyId: party.id),
                        ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isIos
                      ? CupertinoColors.white
                      : AppColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.borderLight,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: avatarBg.withValues(alpha: 0.15),
                      child: Text(
                        initials,
                        style: TextStyle(
                          color: avatarBg,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Party Name & Date
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            party.name,
                            style: AppTypography.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Updated ${DateFormatter.formatRelative(party.lastUpdated)}',
                            style: AppTypography.labelSmall,
                          ),
                        ],
                      ),
                    ),

                    // Net Balance & Status Tag
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AmountText(
                          amountInCents: party.netBalanceInCents,
                          variant: AmountVariant.medium,
                          absolute: true,
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: party.netBalanceInCents > 0
                                ? AppColors.receivableGreenLight
                                : party.netBalanceInCents < 0
                                    ? AppColors.payableRedLight
                                    : AppColors.borderLight.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            party.netBalanceInCents > 0
                                ? "YOU'LL GET"
                                : party.netBalanceInCents < 0
                                    ? "YOU'LL GIVE"
                                    : 'SETTLED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: party.netBalanceInCents > 0
                                  ? AppColors.receivableGreenDark
                                  : party.netBalanceInCents < 0
                                      ? AppColors.payableRedDark
                                      : AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(width: 4),
                    Icon(
                      isIos
                          ? CupertinoIcons.chevron_forward
                          : Icons.chevron_right,
                      size: 18,
                      color: AppColors.textMutedLight,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
