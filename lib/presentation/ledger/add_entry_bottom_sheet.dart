import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/strings.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../data/models/transaction_model.dart';
import '../providers/ledger_providers.dart';

class AddEntryBottomSheet extends ConsumerStatefulWidget {
  final String partyId;
  final String partyName;
  final EntryType initialType;

  const AddEntryBottomSheet({
    super.key,
    required this.partyId,
    required this.partyName,
    required this.initialType,
  });

  @override
  ConsumerState<AddEntryBottomSheet> createState() =>
      _AddEntryBottomSheetState();
}

class _AddEntryBottomSheetState extends ConsumerState<AddEntryBottomSheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  late EntryType _entryType;
  DateTime _selectedDate = DateTime.now();
  String? _receiptUrl;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _entryType = widget.initialType;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDate.hour,
          _selectedDate.minute,
        );
      });
    }
  }

  void _toggleMockReceipt() {
    setState(() {
      if (_receiptUrl == null) {
        _receiptUrl =
            'https://images.unsplash.com/photo-1554224155-8d04cb21cd6c?w=400';
      } else {
        _receiptUrl = null;
      }
    });
  }

  void _saveEntry() async {
    final amountCents = CurrencyFormatter.parseToCents(_amountController.text);
    if (amountCents <= 0) {
      setState(() => _errorMessage = 'Please enter a valid amount');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    await ref.read(ledgerActionControllerProvider).addEntry(
          partyId: widget.partyId,
          amountInCents: amountCents,
          type: _entryType,
          date: _selectedDate,
          note: _noteController.text,
          receiptPhotoUrl: _receiptUrl,
        );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved ${_entryType == EntryType.gave ? "You Gave" : "You Got"} ${CurrencyFormatter.format(amountCents)}',
          ),
          backgroundColor: _entryType == EntryType.gave
              ? AppColors.payableRed
              : AppColors.receivableGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isGave = _entryType == EntryType.gave;
    final themeColor =
        isGave ? AppColors.payableRed : AppColors.receivableGreen;

    return Container(
      decoration: BoxDecoration(
        color: isIos ? CupertinoColors.systemBackground : AppColors.surfaceWhite,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Top Header: Type selector & Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isGave
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 16,
                            color: themeColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isGave ? 'YOU GAVE' : 'YOU GOT',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: themeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'to ${widget.partyName}',
                      style: AppTypography.titleMedium.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Type Switcher
            Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceCardM3,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _entryType = EntryType.gave),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isGave ? AppColors.payableRed : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '- You Gave',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isGave
                                  ? Colors.white
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _entryType = EntryType.got),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !isGave
                              ? AppColors.receivableGreen
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            '+ You Got',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: !isGave
                                  ? Colors.white
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Large Inline Numeric Input Field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isIos
                    ? CupertinoColors.white
                    : AppColors.surfaceCardM3.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _errorMessage != null
                      ? AppColors.payableRed
                      : AppColors.borderLight,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '₹',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: themeColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      autofocus: true,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: themeColor,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0.00',
                        hintStyle: TextStyle(
                          color: AppColors.textMutedLight,
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        fillColor: Colors.transparent,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(
                  color: AppColors.payableRed,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Date Selector + Quick Date Chips
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_rounded, size: 16),
                  label: Text(DateFormatter.formatRelative(_selectedDate)),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() => _selectedDate = DateTime.now());
                  },
                  child: const Text('Today'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() => _selectedDate =
                        DateTime.now().subtract(const Duration(days: 1)));
                  },
                  child: const Text('Yesterday'),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Note Input
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                hintText: AppStrings.enterNoteOptional,
                prefixIcon: Icon(Icons.edit_note_rounded, size: 20),
              ),
            ),

            const SizedBox(height: 14),

            // Mock Camera / Attach Bill
            InkWell(
              onTap: _toggleMockReceipt,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _receiptUrl != null
                      ? AppColors.primaryBlueLight.withValues(alpha: 0.3)
                      : AppColors.surfaceCardM3,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _receiptUrl != null
                        ? AppColors.primaryBlue
                        : AppColors.borderLight,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _receiptUrl != null
                          ? Icons.receipt_long_rounded
                          : Icons.camera_alt_outlined,
                      size: 20,
                      color: _receiptUrl != null
                          ? AppColors.primaryBlue
                          : AppColors.textSecondaryLight,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _receiptUrl != null
                          ? 'Bill attached (receipt_preview.jpg)'
                          : AppStrings.attachBill,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: _receiptUrl != null
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: _receiptUrl != null
                              ? AppColors.primaryBlueDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ),
                    if (_receiptUrl != null)
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: AppColors.primaryBlue,
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Instant Submission Button
            AdaptiveButton(
              onPressed: _saveEntry,
              isFullWidth: true,
              height: 52,
              type: isGave
                  ? AdaptiveButtonType.destructive
                  : AdaptiveButtonType.success,
              isLoading: _isSubmitting,
              child: Text(
                'Save ${_entryType == EntryType.gave ? "You Gave" : "You Got"} Entry',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
