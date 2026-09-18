import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:real_liquid_glass/real_liquid_glass.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/party_model.dart';
import '../ledger/party_ledger_screen.dart';
import '../providers/ledger_providers.dart';

class PartyListTab extends ConsumerStatefulWidget {
  const PartyListTab({super.key});

  @override
  ConsumerState<PartyListTab> createState() => _PartyListTabState();
}

class _PartyListTabState extends ConsumerState<PartyListTab> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(partySearchQueryProvider),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  void _showSortOptions(BuildContext context, PartySortOption currentSort) {
    HapticFeedback.lightImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      showCupertinoModalPopup(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: const Text('Sort Parties By'),
          actions: PartySortOption.values.map((option) {
            final isSelected = option == currentSort;
            return CupertinoActionSheetAction(
              onPressed: () {
                HapticFeedback.lightImpact();
                ref.read(partySortOptionProvider.notifier).setSort(option);
                Navigator.of(context).pop();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isSelected) ...[
                    const Icon(CupertinoIcons.checkmark_alt, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    option.label,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Sort Parties By',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...PartySortOption.values.map((option) {
                  final isSelected = option == currentSort;
                  return ListTile(
                    leading: Icon(
                      option == PartySortOption.alphabetical
                          ? Icons.sort_by_alpha_rounded
                          : option == PartySortOption.highestReceivable
                              ? Icons.trending_up_rounded
                              : Icons.schedule_rounded,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      option.label,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded,
                            color: Theme.of(context).colorScheme.primary)
                        : null,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.read(partySortOptionProvider.notifier).setSort(option);
                      Navigator.of(context).pop();
                    },
                  );
                }),
              ],
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final partiesAsync = ref.watch(partyListProvider);
    final currentSort = ref.watch(partySortOptionProvider);
    final currentQuery = ref.watch(partySearchQueryProvider);
    final isIos = AdaptiveThemeHelper.isIos(context);

    // Keep controller in sync if query changed from elsewhere
    if (_searchController.text != currentQuery) {
      _searchController.value = TextEditingValue(
        text: currentQuery,
        selection: TextSelection.collapsed(offset: currentQuery.length),
      );
    }

    return Column(
      children: [
        // 1. Sticky Search Bar & Sort Action Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Search Input Field
              Expanded(
                child: isIos
                    ? LiquidGlassContainer(
                        height: 44,
                        borderRadius: 14,
                        blur: 20,
                        border: 1.0,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            const Icon(
                              CupertinoIcons.search,
                              size: 18,
                              color: AppColors.textMutedLight,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onTapOutside: (event) => FocusManager.instance.primaryFocus?.unfocus(),
                                onChanged: (val) {
                                  ref
                                      .read(partySearchQueryProvider.notifier)
                                      .setQuery(val);
                                },
                                decoration: const InputDecoration(
                                  hintText: AppStrings.searchHint,
                                  hintStyle: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textMutedLight,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                              ),
                            ),
                            if (currentQuery.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  ref
                                      .read(partySearchQueryProvider.notifier)
                                      .setQuery('');
                                },
                                child: const Icon(
                                  CupertinoIcons.clear_circled_solid,
                                  size: 16,
                                  color: AppColors.textMutedLight,
                                ),
                              ),
                          ],
                        ),
                      )
                    : Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(
                                    alpha: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.35
                                        : 0.5),
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onTapOutside: (event) =>
                                    FocusManager.instance.primaryFocus?.unfocus(),
                                onChanged: (val) {
                                  ref
                                      .read(partySearchQueryProvider.notifier)
                                      .setQuery(val);
                                },
                                decoration: InputDecoration(
                                  hintText: AppStrings.searchHint,
                                  hintStyle: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                  isDense: true,
                                ),
                              ),
                            ),
                            if (currentQuery.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  ref
                                      .read(partySearchQueryProvider.notifier)
                                      .setQuery('');
                                },
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),

              const SizedBox(width: 10),

              // Sort Action Button
              InkWell(
                onTap: () => _showSortOptions(context, currentSort),
                borderRadius: BorderRadius.circular(isIos ? 14 : 24),
                child: isIos
                    ? LiquidGlassContainer(
                        height: 44,
                        width: 44,
                        borderRadius: 14,
                        blur: 20,
                        border: 1.0,
                        child: Icon(
                          CupertinoIcons.sort_down,
                          size: 20,
                          color: currentSort != PartySortOption.mostRecent
                              ? AppColors.primaryBlue
                              : (Theme.of(context).brightness == Brightness.dark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight),
                        ),
                      )
                    : Container(
                        height: 46,
                        width: 46,
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(
                                    alpha: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? 0.35
                                        : 0.5),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.sort_rounded,
                          size: 22,
                          color: currentSort != PartySortOption.mostRecent
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
              ),
            ],
          ),
        ),

        // 2. Party List View
        Expanded(
          child: partiesAsync.when(
            loading: () => ListView.separated(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 6),
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => const SkeletonListTile(),
            ),
            error: (err, stack) => Center(
              child: Text('Error loading parties: $err'),
            ),
            data: (parties) {
              if (parties.isEmpty) {
                final filter = ref.watch(selectedPartyTypeFilterProvider);
                final tabName = filter == PartyType.supplier ? 'Suppliers' : 'Customers';

                return EmptyStateView(
                  lottieAsset: 'assets/animations/empty_ledger.json',
                  fallbackIcon: currentQuery.isNotEmpty
                      ? Icons.search_off_rounded
                      : (filter == PartyType.supplier
                          ? Icons.local_shipping_outlined
                          : Icons.people_outline_rounded),
                  title: currentQuery.isNotEmpty
                      ? 'No matches for "$currentQuery"'
                      : 'No $tabName Found',
                  subtitle: currentQuery.isNotEmpty
                      ? 'Try searching by a different name or phone number.'
                      : 'Add a new ${filter == PartyType.supplier ? 'supplier' : 'customer'} to start tracking transactions.',
                  actionButton: currentQuery.isNotEmpty
                      ? TextButton(
                          onPressed: () {
                            _searchController.clear();
                            ref
                                .read(partySearchQueryProvider.notifier)
                                .setQuery('');
                          },
                          child: const Text('Clear Search'),
                        )
                      : null,
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                itemCount: parties.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final party = parties[index];
                  final avatarBg = _getAvatarColor(party.name);
                  final initials = _getInitials(party.name);

                  final Widget rowContent = Row(
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
                              style: AppTypography.labelSmall.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
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
                                  ? (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? AppColors.receivableGreen
                                          .withValues(alpha: 0.2)
                                      : AppColors.receivableGreenLight)
                                  : party.netBalanceInCents < 0
                                      ? (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? AppColors.payableRed
                                              .withValues(alpha: 0.2)
                                          : AppColors.payableRedLight)
                                      : (Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                          : AppColors.borderLight
                                              .withValues(alpha: 0.5)),
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
                                    ? (Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFF4ADE80)
                                        : AppColors.receivableGreenDark)
                                    : party.netBalanceInCents < 0
                                        ? (Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? const Color(0xFFF87171)
                                            : AppColors.payableRedDark)
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
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
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                    ],
                  );

                  void openLedger() {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).push(
                      createAdaptivePageRoute(
                        builder: (context) =>
                            PartyLedgerScreen(partyId: party.id),
                        transitionType: SharedAxisTransitionType.horizontal,
                      ),
                    );
                  }

                  if (isIos) {
                    return LiquidGlassContainer(
                      borderRadius: 16,
                      blur: 20,
                      padding: const EdgeInsets.all(14),
                      onTap: openLedger,
                      child: rowContent,
                    );
                  }

                  return InkWell(
                    onTap: openLedger,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(
                                  alpha: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? 0.35
                                      : 0.5),
                          width: 1,
                        ),
                      ),
                      child: rowContent,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
