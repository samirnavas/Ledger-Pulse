import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_chip.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_controls.dart';
import '../../core/widgets/adaptive_date_field.dart';
import '../../core/widgets/adaptive_picker.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/recurring_rule_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/services/recurring_service.dart';
import '../ledger/widgets/entry_amount_display.dart';
import '../ledger/widgets/entry_attachment_picker_sheet.dart';
import '../ledger/widgets/entry_note_and_details.dart';
import '../ledger/widgets/entry_numeric_keypad.dart';
import '../ledger/widgets/entry_quick_presets_row.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import '../providers/recurring_providers.dart';
import 'widgets/transaction_type_switcher.dart';

/// Modal bottom sheet for rapid transaction entry (Expense, Income, Transfer).
/// Built on [DraggableModalSheet] with ledger keypad, amount display, presets,
/// and adaptive chips.
class QuickAddTransactionSheet extends ConsumerStatefulWidget {
  final VoucherModel? initialVoucher;

  const QuickAddTransactionSheet({
    super.key,
    this.initialVoucher,
  });

  static Future<bool?> show(
    BuildContext context, {
    VoucherModel? initialVoucher,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: false,
      elevation: 0,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => QuickAddTransactionSheet(
        initialVoucher: initialVoucher,
      ),
    );
  }

  @override
  ConsumerState<QuickAddTransactionSheet> createState() =>
      _QuickAddTransactionSheetState();
}

class _QuickAddTransactionSheetState
    extends ConsumerState<QuickAddTransactionSheet> {
  late VoucherType _selectedType;
  String _amountString = '0';
  late final TextEditingController _hiddenAmountController;
  late final TextEditingController _noteController;
  late final TextEditingController _refController;

  String? _selectedCategoryId;
  String? _selectedWalletId;
  String? _selectedToWalletId;
  late DateTime _selectedDate;
  DateTime? _endDate;
  String? _receiptPhotoUrl;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isRepeating = false;
  RecurringIntervalType _recurringInterval = RecurringIntervalType.monthly;

  bool get _isClean {
    if (widget.initialVoucher != null) {
      final v = widget.initialVoucher!;
      final amt = (v.totalAmountInCents % 100 == 0)
          ? (v.totalAmountInCents ~/ 100).toString()
          : (v.totalAmountInCents / 100.0).toStringAsFixed(2);
      final note = v.narration ?? '';
      final refNum = v.referenceNumber ?? '';
      return _amountString == amt &&
          _noteController.text.trim() == note.trim() &&
          _refController.text.trim() == refNum.trim() &&
          _selectedType == v.type &&
          _selectedCategoryId == v.categoryAccountId &&
          _selectedWalletId == v.walletAccountId &&
          _selectedToWalletId == v.toWalletAccountId &&
          _selectedDate == v.date &&
          _receiptPhotoUrl == v.receiptPhotoUrl;
    }
    return (_amountString == '0' || _amountString.isEmpty) &&
        _noteController.text.trim().isEmpty &&
        _refController.text.trim().isEmpty &&
        _receiptPhotoUrl == null &&
        !_isRepeating;
  }

  @override
  void initState() {
    super.initState();
    final v = widget.initialVoucher;
    if (v != null) {
      _selectedType = v.type;
      final double amt = v.totalAmountInCents / 100.0;
      _amountString =
          amt % 1 == 0 ? amt.toInt().toString() : amt.toStringAsFixed(2);
      _hiddenAmountController = TextEditingController();
      _noteController = TextEditingController(text: v.narration ?? '');
      _refController = TextEditingController(text: v.referenceNumber ?? '');
      _selectedCategoryId = v.categoryAccountId;
      _selectedWalletId = v.walletAccountId;
      _selectedToWalletId = v.toWalletAccountId;
      _selectedDate = v.date;
      _receiptPhotoUrl = v.receiptPhotoUrl;
    } else {
      _selectedType = VoucherType.expense;
      _amountString = '0';
      _hiddenAmountController = TextEditingController();
      _noteController = TextEditingController();
      _refController = TextEditingController();
      _selectedDate = DateTime.now();
    }

    _noteController.addListener(_onFieldChanged);
    _refController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _noteController.removeListener(_onFieldChanged);
    _refController.removeListener(_onFieldChanged);
    _hiddenAmountController.dispose();
    _noteController.dispose();
    _refController.dispose();
    super.dispose();
  }

  void _onKeypadTap(String key) {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    setState(() {
      _errorMessage = null;
      if (key == 'backspace') {
        if (_amountString.length > 1) {
          _amountString = _amountString.substring(0, _amountString.length - 1);
        } else {
          _amountString = '0';
        }
      } else if (key == '.') {
        if (!_amountString.contains('.')) {
          _amountString += '.';
        }
      } else if (key == '0') {
        if (_amountString != '0') {
          final parts = _amountString.split('.');
          if (parts.length <= 1 || parts[1].length < 2) {
            if (_amountString.length <= 9) {
              _amountString += '0';
            }
          }
        }
      } else {
        // Digits 1-9
        if (_amountString == '0') {
          _amountString = key;
        } else {
          final parts = _amountString.split('.');
          if (parts.length <= 1 || parts[1].length < 2) {
            if (_amountString.length <= 9) {
              _amountString += key;
            }
          }
        }
      }
    });
  }

  void _onKeypadLongPressBackspace() {
    HapticFeedback.mediumImpact();
    setState(() {
      _amountString = '0';
      _errorMessage = null;
    });
  }

  void _addQuickPreset(int amount) {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    setState(() {
      _errorMessage = null;
      final current = double.tryParse(_amountString) ?? 0.0;
      final updated = current + amount;
      if (updated == updated.roundToDouble()) {
        _amountString = updated.toInt().toString();
      } else {
        _amountString = updated.toStringAsFixed(2);
      }
    });
  }

  Future<void> _pickDate() async {
    HapticFeedback.lightImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);
    final now = DateTime.now();

    if (isIos) {
      DateTime tempDate = _selectedDate;
      await showCupertinoModalPopup<void>(
        context: context,
        builder: (ctx) => Container(
          height: 280,
          color: CupertinoTheme.of(ctx).scaffoldBackgroundColor,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: const Text('Cancel'),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                  CupertinoButton(
                    child: const Text('Done',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      setState(() => _selectedDate = tempDate);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _selectedDate,
                  maximumDate: now.add(const Duration(days: 365)),
                  minimumYear: 2020,
                  onDateTimeChanged: (val) => tempDate = val,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: now.add(const Duration(days: 365)),
      );
      if (picked != null) {
        setState(() => _selectedDate = picked);
      }
    }
  }

  void _openAttachmentPicker() {
    showEntryAttachmentPicker(
      context: context,
      currentReceiptUrl: _receiptPhotoUrl,
      onReceiptChanged: (newUrl) {
        setState(() => _receiptPhotoUrl = newUrl);
      },
    );
  }

  Future<void> _saveTransaction(Company company) async {
    final amountCents = CurrencyFormatter.parseToCents(_amountString);

    if (amountCents <= 0) {
      setState(() => _errorMessage = 'Please enter an amount greater than 0.');
      return;
    }

    if (_selectedWalletId == null) {
      setState(() => _errorMessage = 'Please select a payment wallet.');
      return;
    }

    if (_selectedType == VoucherType.transfer) {
      if (_selectedToWalletId == null) {
        setState(() => _errorMessage = 'Please select a destination wallet.');
        return;
      }
      if (_selectedWalletId == _selectedToWalletId) {
        setState(() =>
            _errorMessage = 'Destination wallet must differ from source wallet.');
        return;
      }
    } else {
      if (_selectedCategoryId == null) {
        setState(() => _errorMessage = 'Please choose a category.');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(expenseRepositoryProvider);
      final note = _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim();
      final refNum = _refController.text.trim().isEmpty
          ? null
          : _refController.text.trim();

      if (widget.initialVoucher != null) {
        // Edit existing transaction
        final updated = widget.initialVoucher!.copyWith(
          type: _selectedType,
          totalAmountInCents: amountCents,
          categoryAccountId: _selectedType == VoucherType.transfer
              ? null
              : _selectedCategoryId,
          walletAccountId: _selectedWalletId,
          toWalletAccountId: _selectedType == VoucherType.transfer
              ? _selectedToWalletId
              : null,
          date: _selectedDate,
          narration: note,
          referenceNumber: refNum,
          receiptPhotoUrl: _receiptPhotoUrl,
          updatedAt: DateTime.now(),
        );
        await repo.updateTransaction(updated);
      } else {
        // Create new transaction
        if (_selectedType == VoucherType.expense) {
          await repo.addExpense(
            categoryAccountId: _selectedCategoryId!,
            walletAccountId: _selectedWalletId!,
            amountInCents: amountCents,
            date: _selectedDate,
            narration: note,
            referenceNumber: refNum,
            receiptPhotoUrl: _receiptPhotoUrl,
          );
        } else if (_selectedType == VoucherType.income) {
          await repo.addIncome(
            categoryAccountId: _selectedCategoryId!,
            walletAccountId: _selectedWalletId!,
            amountInCents: amountCents,
            date: _selectedDate,
            narration: note,
            referenceNumber: refNum,
            receiptPhotoUrl: _receiptPhotoUrl,
          );
        } else {
          await repo.addTransfer(
            walletAccountId: _selectedWalletId!,
            toWalletAccountId: _selectedToWalletId!,
            amountInCents: amountCents,
            date: _selectedDate,
            narration: note,
            referenceNumber: refNum,
          );
        }

        // If repeat option is enabled, register a recurring rule starting on the next interval date
        if (_isRepeating && company.isModuleEnabled(AppModule.recurring)) {
          final nextDate = RecurringService.advanceDate(
            _selectedDate,
            _recurringInterval,
          );
          final template = RecurringTemplate(
            type: _selectedType,
            amountInCents: amountCents,
            walletAccountId: _selectedWalletId!,
            categoryAccountId: _selectedType == VoucherType.transfer
                ? null
                : _selectedCategoryId,
            toWalletAccountId: _selectedType == VoucherType.transfer
                ? _selectedToWalletId
                : null,
            notes: note,
          );
          await ref.read(recurringServiceProvider).createRule(
                template: template,
                interval: _recurringInterval,
                nextRunDate: nextDate,
                endDate: _endDate,
              );
        }
      }

      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Color _getTypeColor(BuildContext context, VoucherType type) {
    switch (type) {
      case VoucherType.expense:
        return AppColors.expense(context);
      case VoucherType.income:
        return AppColors.income(context);
      case VoucherType.transfer:
        return Theme.of(context).colorScheme.primary;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  IconData _getCategoryIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('food') ||
        lower.contains('dining') ||
        lower.contains('restaurant')) {
      return Icons.restaurant_rounded;
    } else if (lower.contains('salary') ||
        lower.contains('income') ||
        lower.contains('wage')) {
      return Icons.payments_rounded;
    } else if (lower.contains('transport') ||
        lower.contains('travel') ||
        lower.contains('fuel')) {
      return Icons.directions_car_rounded;
    } else if (lower.contains('bill') ||
        lower.contains('utility') ||
        lower.contains('electric')) {
      return Icons.receipt_long_rounded;
    } else if (lower.contains('shopping') || lower.contains('grocer')) {
      return Icons.shopping_bag_rounded;
    } else if (lower.contains('invest') || lower.contains('dividend')) {
      return Icons.trending_up_rounded;
    } else if (lower.contains('rent') || lower.contains('home')) {
      return Icons.home_rounded;
    } else if (lower.contains('health') || lower.contains('medical')) {
      return Icons.medical_services_rounded;
    }
    return Icons.category_rounded;
  }

  Future<void> _openCategoryPicker(
    BuildContext context,
    List<AccountModel> categories,
  ) async {
    HapticFeedback.lightImpact();
    final picked = await showAdaptivePicker<String>(
      context: context,
      title: 'Select Category',
      selectedValue: _selectedCategoryId,
      items: categories.map((cat) {
        return AdaptivePickerItem<String>(
          value: cat.id,
          label: cat.name,
          subtitle: cat.description ?? cat.type.name,
          icon: Icon(_getCategoryIcon(cat.name), size: 18),
        );
      }).toList(),
    );
    if (picked != null) {
      setState(() {
        _selectedCategoryId = picked;
        _errorMessage = null;
      });
    }
  }

  Widget _buildCategorySelector(
    BuildContext context,
    List<AccountModel> allCategories,
    Color themeColor,
  ) {
    final targetType = _selectedType == VoucherType.expense
        ? AccountType.expense
        : AccountType.income;
    final filtered = allCategories.where((c) => c.type == targetType).toList();

    if (filtered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No categories found.'),
      );
    }

    const maxDirectChips = 4;
    final List<AccountModel> displayed = [];
    final selectedCat =
        filtered.where((c) => c.id == _selectedCategoryId).firstOrNull;

    for (int i = 0; i < filtered.length; i++) {
      if (i < maxDirectChips) {
        displayed.add(filtered[i]);
      }
    }

    if (selectedCat != null && !displayed.contains(selectedCat)) {
      if (displayed.isNotEmpty) {
        displayed.removeLast();
      }
      displayed.add(selectedCat);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ...displayed.map((cat) {
                final isSelected = _selectedCategoryId == cat.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AdaptiveChip(
                    key: Key('cat_chip_${cat.id}'),
                    label: cat.name,
                    isSelected: isSelected,
                    selectedColor: themeColor,
                    icon: Icon(_getCategoryIcon(cat.name), size: 16),
                    onSelected: (selected) {
                      if (selected) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedCategoryId = cat.id;
                          _errorMessage = null;
                        });
                      }
                    },
                  ),
                );
              }),
              if (filtered.length > maxDirectChips)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AdaptiveChip(
                    key: const Key('cat_chip_more'),
                    label: 'More',
                    isSelected: false,
                    icon: const Icon(Icons.more_horiz, size: 16),
                    onSelected: (_) => _openCategoryPicker(context, filtered),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openWalletPicker({
    required BuildContext context,
    required String title,
    required List<AccountModel> wallets,
    required String? selectedId,
    required ValueChanged<String> onSelected,
    required String currencyCode,
  }) async {
    HapticFeedback.lightImpact();
    final picked = await showAdaptivePicker<String>(
      context: context,
      title: title,
      selectedValue: selectedId,
      items: wallets.map((w) {
        final isLiability = w.type == AccountType.liability;
        final icon = isLiability
            ? Icons.credit_card_rounded
            : (w.name.toLowerCase().contains('bank')
                ? Icons.account_balance_rounded
                : Icons.account_balance_wallet_rounded);
        final balanceFormatted = CurrencyFormatter.format(
          w.currentBalanceInCents,
          currencyCode: currencyCode,
        );
        return AdaptivePickerItem<String>(
          value: w.id,
          label: w.name,
          subtitle: 'Balance: $balanceFormatted',
          icon: Icon(icon, size: 20),
        );
      }).toList(),
    );
    if (picked != null) {
      onSelected(picked);
    }
  }

  Widget _buildWalletSelector({
    required BuildContext context,
    required String title,
    required List<AccountModel> wallets,
    required String? selectedId,
    required ValueChanged<String> onSelected,
    required Color themeColor,
    required String currencyCode,
    String keyPrefix = 'wallet_chip_',
  }) {
    if (wallets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Text('No wallets configured.'),
      );
    }

    const maxDirectChips = 3;
    final List<AccountModel> displayed = [];
    final selectedWallet = wallets.where((w) => w.id == selectedId).firstOrNull;

    for (int i = 0; i < wallets.length; i++) {
      if (i < maxDirectChips) {
        displayed.add(wallets[i]);
      }
    }

    if (selectedWallet != null && !displayed.contains(selectedWallet)) {
      if (displayed.isNotEmpty) {
        displayed.removeLast();
      }
      displayed.add(selectedWallet);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ...displayed.map((wallet) {
                final isSelected = selectedId == wallet.id;
                final isLiability = wallet.type == AccountType.liability;
                final icon = isLiability
                    ? Icons.credit_card_rounded
                    : (wallet.name.toLowerCase().contains('bank')
                        ? Icons.account_balance_rounded
                        : Icons.account_balance_wallet_rounded);

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AdaptiveChip(
                    key: Key('$keyPrefix${wallet.id}'),
                    label: wallet.name,
                    isSelected: isSelected,
                    selectedColor: themeColor,
                    icon: Icon(icon, size: 16),
                    onSelected: (selected) {
                      if (selected) {
                        HapticFeedback.selectionClick();
                        onSelected(wallet.id);
                      }
                    },
                  ),
                );
              }),
              if (wallets.length > maxDirectChips)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AdaptiveChip(
                    key: Key('${keyPrefix}more'),
                    label: 'More',
                    isSelected: false,
                    icon: const Icon(Icons.more_horiz, size: 16),
                    onSelected: (_) => _openWalletPicker(
                      context: context,
                      title: title,
                      wallets: wallets,
                      selectedId: selectedId,
                      onSelected: onSelected,
                      currencyCode: currencyCode,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final company = ref.watch(activeCompanyProvider);
    final walletsAsync = ref.watch(walletsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final themeColor = _getTypeColor(context, _selectedType);
    final currencySymbol = CurrencyFormatter.getSymbol(company.currencyCode);

    final containerColor = isIos
        ? (isDark
            ? CupertinoColors.systemGroupedBackground.darkColor
            : CupertinoColors.systemGroupedBackground)
        : (isDark
            ? AppColors.surfaceCardDark
            : Theme.of(context).colorScheme.surfaceContainerHighest);

    walletsAsync.whenData((wallets) {
      if (_selectedWalletId == null && wallets.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _selectedWalletId == null) {
            setState(() => _selectedWalletId = wallets.first.id);
          }
        });
      }
    });

    return PopScope(
      canPop: _isClean,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldDiscard = await showAdaptiveConfirmDialog(
          context: context,
          title: 'Discard unsaved changes?',
          message: 'You have unsaved changes that will be lost if you leave.',
          confirmLabel: 'Discard',
          cancelLabel: 'Keep Editing',
          isDestructive: true,
        );
        if (shouldDiscard && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: DraggableModalSheet(
        initialChildSize: 0.95,
        minChildSize: 0.35,
        maxChildSize: 0.98,
        snapSizes: const [0.95, 0.98],
        showHandle: true,
        backgroundColor: containerColor,
        builder: (sheetContext, scrollController) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 0,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header: Title & Close Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.initialVoucher != null
                                ? (isIos
                                    ? CupertinoIcons.pencil
                                    : Icons.edit_outlined)
                                : (_selectedType == VoucherType.expense
                                    ? (isIos
                                        ? CupertinoIcons.arrow_up
                                        : Icons.arrow_upward_rounded)
                                    : (_selectedType == VoucherType.income
                                        ? (isIos
                                            ? CupertinoIcons.arrow_down
                                            : Icons.arrow_downward_rounded)
                                        : (isIos
                                            ? CupertinoIcons
                                                .arrow_right_arrow_left
                                            : Icons.swap_horiz_rounded))),
                            size: 15,
                            color: themeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.initialVoucher != null
                                ? 'EDIT TRANSACTION'
                                : (_selectedType == VoucherType.expense
                                    ? 'NEW EXPENSE'
                                    : (_selectedType == VoucherType.income
                                        ? 'NEW INCOME'
                                        : 'NEW TRANSFER')),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: themeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        Navigator.of(context).maybePop();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Scrollable Form Body
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Type Switcher (Expense, Income, Transfer)
                        TransactionTypeSwitcher(
                          selectedType: _selectedType,
                          onTypeChanged: (type) {
                            setState(() {
                              _selectedType = type;
                              _selectedCategoryId = null;
                              _errorMessage = null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Amount Display
                        EntryAmountDisplay(
                          amountString: _amountString,
                          themeColor: themeColor,
                          errorMessage: _errorMessage,
                          currencyCode: company.currencyCode,
                        ),
                        const SizedBox(height: 10),

                        // Hidden TextField for test automation backwards compatibility
                        SizedBox(
                          width: 0,
                          height: 0,
                          child: Opacity(
                            opacity: 0,
                            child: TextField(
                              key: const Key('quick_add_amount_field'),
                              controller: _hiddenAmountController,
                              onChanged: (val) {
                                setState(() {
                                  _amountString = val.isEmpty ? '0' : val;
                                  _errorMessage = null;
                                });
                              },
                            ),
                          ),
                        ),

                        // Quick Presets Row (+100, +500, +1000)
                        EntryQuickPresetsRow(
                          themeColor: themeColor,
                          currencySymbol: currencySymbol,
                          presets: const [100, 500, 1000],
                          onAddPreset: _addQuickPreset,
                        ),
                        const SizedBox(height: 12),

                        // Category Selector (Expense & Income)
                        if (_selectedType != VoucherType.transfer) ...[
                          categoriesAsync.when(
                            data: (cats) => _buildCategorySelector(
                              sheetContext,
                              cats,
                              themeColor,
                            ),
                            loading: () => const Center(
                              child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CupertinoActivityIndicator(),
                              ),
                            ),
                            error: (e, _) =>
                                Text('Error loading categories: $e'),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Wallet Selector (Source Wallet)
                        walletsAsync.when(
                          data: (wallets) => _buildWalletSelector(
                            context: sheetContext,
                            title: _selectedType == VoucherType.transfer
                                ? 'From Wallet'
                                : 'Paid With / To',
                            wallets: wallets,
                            selectedId: _selectedWalletId,
                            onSelected: (id) {
                              setState(() {
                                _selectedWalletId = id;
                                _errorMessage = null;
                              });
                            },
                            themeColor: themeColor,
                            currencyCode: company.currencyCode,
                            keyPrefix: 'wallet_chip_',
                          ),
                          loading: () => const Center(
                            child: Padding(
                              padding: EdgeInsets.all(8.0),
                              child: CupertinoActivityIndicator(),
                            ),
                          ),
                          error: (e, _) => Text('Error loading wallets: $e'),
                        ),
                        const SizedBox(height: 12),

                        // Destination Wallet (Transfer only)
                        if (_selectedType == VoucherType.transfer) ...[
                          walletsAsync.when(
                            data: (wallets) {
                              final availableToWallets = wallets
                                  .where((w) => w.id != _selectedWalletId)
                                  .toList();
                              return _buildWalletSelector(
                                context: sheetContext,
                                title: 'To Wallet',
                                wallets: availableToWallets,
                                selectedId: _selectedToWalletId,
                                onSelected: (id) {
                                  setState(() {
                                    _selectedToWalletId = id;
                                    _errorMessage = null;
                                  });
                                },
                                themeColor: themeColor,
                                currencyCode: company.currencyCode,
                                keyPrefix: 'to_wallet_chip_',
                              );
                            },
                            loading: () => const Center(
                              child: Padding(
                                padding: EdgeInsets.all(8.0),
                                child: CupertinoActivityIndicator(),
                              ),
                            ),
                            error: (e, _) => Text('Error loading wallets: $e'),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Note, Date and Receipt
                        EntryNoteAndDetails(
                          noteController: _noteController,
                          selectedDate: _selectedDate,
                          receiptUrl: _receiptPhotoUrl,
                          themeColor: themeColor,
                          onPickDate: _pickDate,
                          onOpenAttachmentPicker: _openAttachmentPicker,
                          labelText: 'Note (Optional)',
                          hintText: 'e.g. Dinner with team, Bill, Shopping...',
                          noteFieldKey: const Key('quick_add_note_field'),
                        ),
                        const SizedBox(height: 8),

                        // Reference Number Input
                        TextFormField(
                          controller: _refController,
                          textCapitalization: TextCapitalization.characters,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color:
                                Theme.of(sheetContext).colorScheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Reference # (Optional)',
                            labelStyle: TextStyle(
                              fontSize: 12,
                              color: Theme.of(sheetContext)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                            hintText: 'e.g. INV-1002, TXN-5481',
                            prefixIcon: Icon(
                              Icons.numbers_rounded,
                              size: 18,
                              color: themeColor,
                            ),
                            filled: true,
                            fillColor: isDark
                                ? AppColors.surfaceCardDark
                                : Theme.of(sheetContext)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.4),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: isDark
                                    ? AppColors.borderDark
                                    : Theme.of(sheetContext)
                                        .colorScheme
                                        .outlineVariant,
                              ),
                            ),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Repeat Option
                        if (company.isModuleEnabled(AppModule.recurring) &&
                            widget.initialVoucher == null) ...[
                          AdaptiveSwitch(
                            key: const Key('quick_add_repeat_switch'),
                            value: _isRepeating,
                            label: 'Repeat Transaction',
                            subtitle:
                                'Automatically generate recurring vouchers',
                            onChanged: (val) {
                              setState(() => _isRepeating = val);
                            },
                          ),
                          if (_isRepeating) ...[
                            const SizedBox(height: 8),
                            AdaptiveDropdownField<RecurringIntervalType>(
                              key: const Key('quick_add_repeat_interval'),
                              label: 'Repeat Frequency',
                              value: _recurringInterval,
                              items: const [
                                AdaptivePickerItem(
                                  value: RecurringIntervalType.daily,
                                  label: 'Daily',
                                ),
                                AdaptivePickerItem(
                                  value: RecurringIntervalType.weekly,
                                  label: 'Weekly',
                                ),
                                AdaptivePickerItem(
                                  value: RecurringIntervalType.monthly,
                                  label: 'Monthly',
                                ),
                                AdaptivePickerItem(
                                  value: RecurringIntervalType.yearly,
                                  label: 'Yearly',
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _recurringInterval = val);
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: AdaptiveDateField(
                                    label: 'Start Date',
                                    selectedDate: _selectedDate,
                                    onDateSelected: (d) =>
                                        setState(() => _selectedDate = d),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AdaptiveDateField(
                                    label: 'End Date (Optional)',
                                    selectedDate: _endDate ??
                                        _selectedDate
                                            .add(const Duration(days: 365)),
                                    onDateSelected: (d) =>
                                        setState(() => _endDate = d),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 8),
                        ],

                        // Keypad
                        EntryNumericKeypad(
                          themeColor: themeColor,
                          onKeyTap: _onKeypadTap,
                          onLongPressBackspace: _onKeypadLongPressBackspace,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),

                // Submit Button
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AdaptiveButton(
                      key: const Key('quick_add_submit_button'),
                      isFullWidth: true,
                      height: 52,
                      isLoading: _isSubmitting,
                      type: _selectedType == VoucherType.expense
                          ? AdaptiveButtonType.destructive
                          : (_selectedType == VoucherType.income
                              ? AdaptiveButtonType.success
                              : AdaptiveButtonType.primary),
                      onPressed: _isSubmitting
                          ? null
                          : () => _saveTransaction(company),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.initialVoucher != null
                                ? (isIos
                                    ? CupertinoIcons.check_mark
                                    : Icons.check_rounded)
                                : (_selectedType == VoucherType.expense
                                    ? (isIos
                                        ? CupertinoIcons.arrow_up
                                        : Icons.arrow_upward_rounded)
                                    : (_selectedType == VoucherType.income
                                        ? (isIos
                                            ? CupertinoIcons.arrow_down
                                            : Icons.arrow_downward_rounded)
                                        : (isIos
                                            ? CupertinoIcons
                                                .arrow_right_arrow_left
                                            : Icons.swap_horiz_rounded))),
                            size: 20,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.initialVoucher != null
                                ? 'Update Transaction'
                                : (_selectedType == VoucherType.expense
                                    ? 'Save Expense'
                                    : (_selectedType == VoucherType.income
                                        ? 'Save Income'
                                        : 'Save Transfer')),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
