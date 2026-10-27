import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../data/models/recurring_rule_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/services/recurring_service.dart';
import '../providers/company_providers.dart';
import '../providers/expense_providers.dart';
import '../providers/recurring_providers.dart';

/// Modal bottom sheet for rapid transaction entry (Expense, Income, Transfer).
/// Designed so that entering a typical expense takes at most 3 taps after typing the amount.
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
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late final TextEditingController _refController;

  String? _selectedCategoryId;
  String? _selectedWalletId;
  String? _selectedToWalletId;
  late DateTime _selectedDate;
  String? _receiptPhotoUrl;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _isRepeating = false;
  RecurringIntervalType _recurringInterval = RecurringIntervalType.monthly;

  @override
  void initState() {
    super.initState();
    final v = widget.initialVoucher;
    if (v != null) {
      _selectedType = v.type;
      final double amt = v.totalAmountInCents / 100.0;
      _amountController = TextEditingController(
        text: amt % 1 == 0 ? amt.toInt().toString() : amt.toStringAsFixed(2),
      );
      _noteController = TextEditingController(text: v.narration ?? '');
      _refController = TextEditingController(text: v.referenceNumber ?? '');
      _selectedCategoryId = v.categoryAccountId;
      _selectedWalletId = v.walletAccountId;
      _selectedToWalletId = v.toWalletAccountId;
      _selectedDate = v.date;
      _receiptPhotoUrl = v.receiptPhotoUrl;
    } else {
      _selectedType = VoucherType.expense;
      _amountController = TextEditingController();
      _noteController = TextEditingController();
      _refController = TextEditingController();
      _selectedDate = DateTime.now();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _pickReceiptImage() async {
    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (photo != null) {
        setState(() {
          _receiptPhotoUrl = photo.path;
        });
      }
    } catch (e) {
      debugPrint('Failed to pick image: $e');
    }
  }

  Future<void> _pickDate() async {
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
                    child: const Text('Done'),
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

  Future<void> _saveTransaction(Company company) async {
    final amountCents = CurrencyFormatter.parseToCents(_amountController.text);

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final company = ref.watch(activeCompanyProvider);
    final walletsAsync = ref.watch(walletsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final currencySymbol = CurrencyFormatter.getSymbol(company.currencyCode);

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.initialVoucher != null
                      ? 'Edit Transaction'
                      : 'New Transaction',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Scrollable Form Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                // Type Segmented Control
                AdaptiveSegmentedControl<VoucherType>(
                  groupValue: _selectedType,
                  children: const {
                    VoucherType.expense: Text('Expense'),
                    VoucherType.income: Text('Income'),
                    VoucherType.transfer: Text('Transfer'),
                  },
                  onValueChanged: (type) {
                    setState(() {
                      _selectedType = type;
                      _selectedCategoryId = null;
                      _errorMessage = null;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Amount Input Card
                LiquidGlassCard(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Text(
                        currencySymbol,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getTypeColor(_selectedType),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          key: const Key('quick_add_amount_field'),
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          autofocus: widget.initialVoucher == null,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}')),
                          ],
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: const InputDecoration(
                            hintText: '0.00',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Error Banner
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: theme.colorScheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Category Chips (Only for Expense or Income)
                if (_selectedType != VoucherType.transfer) ...[
                  Text(
                    'Category',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  categoriesAsync.when(
                    data: (categories) {
                      final targetType = _selectedType == VoucherType.expense
                          ? AccountType.expense
                          : AccountType.income;
                      final filtered = categories
                          .where((c) => c.type == targetType)
                          .toList();

                      if (filtered.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No categories found.'),
                        );
                      }

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: filtered.map((cat) {
                          final isSelected = _selectedCategoryId == cat.id;
                          return ChoiceChip(
                            key: Key('cat_chip_${cat.id}'),
                            label: Text(cat.name),
                            selected: isSelected,
                            selectedColor: theme.colorScheme.primaryContainer,
                            onSelected: (selected) {
                              if (selected) {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _selectedCategoryId = cat.id;
                                  _errorMessage = null;
                                });
                              }
                            },
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Error loading categories: $e'),
                  ),
                  const SizedBox(height: 16),
                ],

                // Wallet Selector (Source Wallet)
                Text(
                  _selectedType == VoucherType.transfer
                      ? 'Source Wallet'
                      : 'Paid With / To',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                walletsAsync.when(
                  data: (wallets) {
                    if (wallets.isEmpty) {
                      return const Text('No wallets configured.');
                    }

                    // Auto-select first wallet if none selected
                    if (_selectedWalletId == null && wallets.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _selectedWalletId == null) {
                          setState(() => _selectedWalletId = wallets.first.id);
                        }
                      });
                    }

                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: wallets.map((wallet) {
                        final isSelected = _selectedWalletId == wallet.id;
                        final isLiability =
                            wallet.type == AccountType.liability;
                        return ChoiceChip(
                          key: Key('wallet_chip_${wallet.id}'),
                          avatar: Icon(
                            isLiability
                                ? Icons.credit_card
                                : (wallet.name.toLowerCase().contains('bank')
                                    ? Icons.account_balance
                                    : Icons.wallet),
                            size: 16,
                          ),
                          label: Text(wallet.name),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedWalletId = wallet.id;
                                _errorMessage = null;
                              });
                            }
                          },
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Error loading wallets: $e'),
                ),
                const SizedBox(height: 16),

                // Destination Wallet (Transfer only)
                if (_selectedType == VoucherType.transfer) ...[
                  Text(
                    'Destination Wallet',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  walletsAsync.when(
                    data: (wallets) {
                      final available = wallets
                          .where((w) => w.id != _selectedWalletId)
                          .toList();

                      if (available.isEmpty) {
                        return const Text(
                            'Please configure another wallet to transfer between.');
                      }

                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: available.map((wallet) {
                          final isSelected = _selectedToWalletId == wallet.id;
                          return ChoiceChip(
                            key: Key('to_wallet_chip_${wallet.id}'),
                            avatar: Icon(
                              wallet.type == AccountType.liability
                                  ? Icons.credit_card
                                  : Icons.account_balance_wallet,
                              size: 16,
                            ),
                            label: Text(wallet.name),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _selectedToWalletId = wallet.id;
                                  _errorMessage = null;
                                });
                              }
                            },
                          );
                        }).toList(),
                      );
                    },
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Error: $e'),
                  ),
                  const SizedBox(height: 16),
                ],

                // Date Picker Tile
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          DateFormat('dd MMM yyyy').format(_selectedDate),
                        ),
                        onPressed: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(
                          _receiptPhotoUrl != null
                              ? Icons.check_circle
                              : Icons.camera_alt_outlined,
                          size: 18,
                          color: _receiptPhotoUrl != null
                              ? Colors.green
                              : null,
                        ),
                        label: Text(
                          _receiptPhotoUrl != null
                              ? 'Photo Attached'
                              : 'Add Receipt',
                        ),
                        onPressed: _pickReceiptImage,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Note & Reference Input
                TextField(
                  key: const Key('quick_add_note_field'),
                  controller: _noteController,
                  decoration: InputDecoration(
                    labelText: 'Note (Optional)',
                    hintText: 'e.g. Dinner with colleagues',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.notes, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _refController,
                  decoration: InputDecoration(
                    labelText: 'Reference # (Optional)',
                    hintText: 'e.g. Receipt #1234',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.tag, size: 20),
                  ),
                ),

                // Repeat Option (Guarded by Recurring Module)
                if (company.isModuleEnabled(AppModule.recurring) &&
                    widget.initialVoucher == null) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const Key('quick_add_repeat_switch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Repeat Transaction',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Automatically generate repeating vouchers',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: _isRepeating,
                    onChanged: (val) {
                      setState(() => _isRepeating = val);
                    },
                  ),
                  if (_isRepeating) ...[
                    const SizedBox(height: 6),
                    SegmentedButton<RecurringIntervalType>(
                      key: const Key('quick_add_repeat_interval'),
                      segments: const [
                        ButtonSegment(
                          value: RecurringIntervalType.daily,
                          label: Text('Daily'),
                        ),
                        ButtonSegment(
                          value: RecurringIntervalType.weekly,
                          label: Text('Weekly'),
                        ),
                        ButtonSegment(
                          value: RecurringIntervalType.monthly,
                          label: Text('Monthly'),
                        ),
                        ButtonSegment(
                          value: RecurringIntervalType.yearly,
                          label: Text('Yearly'),
                        ),
                      ],
                      selected: {_recurringInterval},
                      onSelectionChanged: (val) {
                        setState(() => _recurringInterval = val.first);
                      },
                    ),
                  ],
                ],
              ],
            ),
          ),

          // Pinned Bottom Action Button
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: AdaptiveButton(
                key: const Key('quick_add_submit_button'),
                isFullWidth: true,
                onPressed: _isSubmitting
                    ? null
                    : () => _saveTransaction(company),
                type: _selectedType == VoucherType.income
                    ? AdaptiveButtonType.success
                    : AdaptiveButtonType.primary,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.initialVoucher != null
                            ? 'Update Transaction'
                            : 'Save ${_selectedType.name[0].toUpperCase()}${_selectedType.name.substring(1)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(VoucherType type) {
    switch (type) {
      case VoucherType.expense:
        return const Color(0xFFEF4444); // Red
      case VoucherType.income:
        return const Color(0xFF10B981); // Emerald Green
      case VoucherType.transfer:
        return const Color(0xFF3B82F6); // Blue
      default:
        return const Color(0xFF6366F1);
    }
  }
}
