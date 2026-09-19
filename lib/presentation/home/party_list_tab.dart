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
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/amount_text.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/skeleton_list_tile.dart';
import '../../data/models/party_model.dart';
import '../ledger/party_ledger_screen.dart';
import '../providers/ledger_providers.dart';
import 'add_party_dialog.dart';

class PartyListTab extends ConsumerStatefulWidget {
  const PartyListTab({super.key});

  @override
  ConsumerState<PartyListTab> createState() => _PartyListTabState();
}

class _PartyListTabState extends ConsumerState<PartyListTab> {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(
      text: ref.read(partySearchQueryProvider),
    );
    _searchFocusNode = FocusNode();
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  void _onSearchFocusChanged() {
    final isActive =
        _searchFocusNode.hasFocus || _searchController.text.isNotEmpty;
    ref.read(isPartySearchActiveProvider.notifier).setActive(isActive);
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _clearSearch() {
    HapticFeedback.lightImpact();
    _searchController.clear();
    _searchFocusNode.unfocus();
    ref.read(partySearchQueryProvider.notifier).setQuery('');
    ref.read(isPartySearchActiveProvider.notifier).setActive(false);
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
        showDragHandle: true,
        enableDrag: true,
        isScrollControlled: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Sort Parties By',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...PartySortOption.values.map((option) {
                  final isSelected = option == currentSort;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: Icon(
                        option == PartySortOption.alphabetical
                            ? Icons.sort_by_alpha_rounded
                            : option == PartySortOption.highestReceivable
                                ? Icons.trending_up_rounded
                                : Icons.schedule_rounded,
                        color: isSelected
                            ? Theme.of(context).colorScheme.onPrimaryContainer
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        option.label,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w500,
                          color: isSelected
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle_rounded,
                              color: Theme.of(context).colorScheme.primary)
                          : null,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ref.read(partySortOptionProvider.notifier).setSort(option);
                        Navigator.of(context).pop();
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _openEditParty(Party party) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddPartyDialog(
        initialType: party.type,
        partyToEdit: party,
      ),
    );
  }

  Future<void> _handleDeleteParty(Party party) async {
    // 1. Safety Check: Verify if party.netBalanceInCents != 0
    if (party.netBalanceInCents != 0) {
      final formattedBalance = CurrencyFormatter.format(
        party.netBalanceInCents,
        absolute: true,
      );
      await showAdaptiveInfoDialog(
        context: context,
        title: 'Cannot Delete Party',
        message:
            'Cannot delete a party with an outstanding balance of $formattedBalance. Settle the dues first.',
        buttonLabel: 'OK',
      );
      return;
    }

    // 2. Open Adaptive Confirmation Dialog for 0-balance party
    final shouldDelete = await showAdaptiveConfirmDialog(
      context: context,
      title: 'Delete Party?',
      message:
          'Are you sure you want to delete ${party.name}? All transaction records for this party will be archived.',
      confirmLabel: 'Delete',
      cancelLabel: 'Cancel',
      isDestructive: true,
    );

    if (shouldDelete && mounted) {
      try {
        await ref.read(ledgerActionControllerProvider).deleteParty(party.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${party.name} deleted and archived.'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Theme.of(context).colorScheme.inverseSurface,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete party: $e'),
              backgroundColor: AppColors.payableRed,
            ),
          );
        }
      }
    }
  }

  void _showPartyContextMenu(BuildContext context, Party party) {
    HapticFeedback.mediumImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      showCupertinoModalPopup(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: Text(party.name),
          message: Text(party.phoneNumber),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(ctx).pop();
                _openEditParty(party);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.pencil, size: 20),
                  SizedBox(width: 8),
                  Text('Edit Details'),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.of(ctx).pop();
                _handleDeleteParty(party);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.trash, size: 20),
                  SizedBox(width: 8),
                  Text('Delete Party'),
                ],
              ),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ),
      );
    } else {
      final colorScheme = Theme.of(context).colorScheme;
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        backgroundColor: colorScheme.surfaceContainerHighest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        party.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        party.phoneNumber,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.edit_outlined),
                        title: const Text(
                          'Edit Details',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _openEditParty(party);
                        },
                      ),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        indent: 56,
                        endIndent: 16,
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.4),
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.delete_outline,
                          color: colorScheme.error,
                        ),
                        title: Text(
                          'Delete Party',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.error,
                          ),
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(16)),
                        ),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _handleDeleteParty(party);
                        },
                      ),
                    ],
                  ),
                ),
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
                        border: 1.2,
                        borderColor: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white.withValues(alpha: 0.22)
                            : Colors.black.withValues(alpha: 0.15),
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
                                focusNode: _searchFocusNode,
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
                                onTap: _clearSearch,
                                child: const Icon(
                                  CupertinoIcons.clear_circled_solid,
                                  size: 16,
                                  color: AppColors.textMutedLight,
                                ),
                              ),
                          ],
                        ),
                      )
                    : SearchBar(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        elevation: const WidgetStatePropertyAll(0),
                        backgroundColor: WidgetStatePropertyAll(
                          Theme.of(context).colorScheme.surfaceContainerHigh,
                        ),
                        side: WidgetStatePropertyAll(
                          BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withValues(alpha: 0.6),
                            width: 1.0,
                          ),
                        ),
                        shape: WidgetStatePropertyAll(
                          RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant
                                  .withValues(alpha: 0.6),
                              width: 1.0,
                            ),
                          ),
                        ),
                        leading: const Icon(Icons.search),
                        hintText: AppStrings.searchHint,
                        hintStyle: WidgetStatePropertyAll(
                          TextStyle(
                            fontSize: 14,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        trailing: [
                          if (currentQuery.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearSearch,
                            ),
                        ],
                        onChanged: (val) {
                          ref
                              .read(partySearchQueryProvider.notifier)
                              .setQuery(val);
                        },
                        onTapOutside: (event) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        constraints: const BoxConstraints(
                          minHeight: 48,
                          maxHeight: 48,
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
                        height: 48,
                        width: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHigh,
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

        // 2. Party List View (smooth list-only animated transition)
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey<PartyType?>(ref.watch(selectedPartyTypeFilterProvider)),
              child: partiesAsync.when(
                loading: () => ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: 6,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 76,
                    endIndent: 16,
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.2
                            : 0.35),
                  ),
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
                    );
                  }

                  final isDark = Theme.of(context).brightness == Brightness.dark;

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: parties.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 76,
                      endIndent: 16,
                      color: Theme.of(context).colorScheme.outlineVariant.withValues(
                          alpha: isDark ? 0.2 : 0.35),
                    ),
                itemBuilder: (context, index) {
                  final party = parties[index];
                  final avatarBg = _getAvatarColor(party.name);
                  final initials = _getInitials(party.name);

                  final Widget rowContent = Row(
                    children: [
                      // Avatar
                      isIos
                          ? CircleAvatar(
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
                            )
                          : Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                initials,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      fontWeight: FontWeight.bold,
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

                      // Net Balance
                      AmountText(
                        amountInCents: party.netBalanceInCents,
                        variant: AmountVariant.medium,
                        absolute: true,
                      ),

                      const SizedBox(width: 4),

                      // 3-dot Context Menu Button
                      IconButton(
                        icon: Icon(
                          isIos
                              ? CupertinoIcons.ellipsis_circle
                              : Icons.more_vert_rounded,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 32, minHeight: 32),
                        splashRadius: 20,
                        tooltip: 'Party Options',
                        onPressed: () =>
                            _showPartyContextMenu(context, party),
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

                  return InkWell(
                    onTap: openLedger,
                    onLongPress: () =>
                        _showPartyContextMenu(context, party),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: rowContent,
                    ),
                  );
                },
              );
            },
          ),
          ),
          ),
        ),
      ],
    );
  }
}
