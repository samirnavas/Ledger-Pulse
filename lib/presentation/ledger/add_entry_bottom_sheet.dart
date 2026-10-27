import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../data/models/transaction_model.dart';
import '../payments/cts2010_cheque_preview_screen.dart';
import '../providers/ledger_providers.dart';
import 'widgets/entry_amount_display.dart';
import 'widgets/entry_attachment_picker_sheet.dart';
import 'widgets/entry_header.dart';
import 'widgets/entry_note_and_details.dart';
import 'widgets/entry_numeric_keypad.dart';
import 'widgets/entry_quick_presets_row.dart';
import 'widgets/entry_type_switcher.dart';

class AddEntryBottomSheet extends ConsumerStatefulWidget {
  final String partyId;
  final String partyName;
  final EntryType initialType;
  final LedgerEntry? entryToEdit;

  const AddEntryBottomSheet({
    super.key,
    required this.partyId,
    required this.partyName,
    required this.initialType,
    this.entryToEdit,
  });

  @override
  ConsumerState<AddEntryBottomSheet> createState() =>
      _AddEntryBottomSheetState();
}

class _AddEntryBottomSheetState extends ConsumerState<AddEntryBottomSheet> {
  String _amountString = '0';
  final TextEditingController _noteController = TextEditingController();
  late EntryType _entryType;
  DateTime _selectedDate = DateTime.now();
  String? _receiptUrl;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isClean {
    if (widget.entryToEdit != null) {
      final entry = widget.entryToEdit!;
      final initialAmt = (entry.amountInCents % 100 == 0)
          ? (entry.amountInCents ~/ 100).toString()
          : (entry.amountInCents / 100.0).toStringAsFixed(2);
      final initialNote = entry.note ?? '';
      return _amountString == initialAmt &&
          _noteController.text.trim() == initialNote.trim() &&
          _selectedDate == entry.date &&
          _entryType == entry.type &&
          _receiptUrl == entry.receiptPhotoUrl;
    }
    return (_amountString == '0' || _amountString.isEmpty) &&
        _noteController.text.trim().isEmpty &&
        _receiptUrl == null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.entryToEdit != null) {
      final entry = widget.entryToEdit!;
      _entryType = entry.type;
      if (entry.amountInCents % 100 == 0) {
        _amountString = (entry.amountInCents ~/ 100).toString();
      } else {
        _amountString = (entry.amountInCents / 100.0).toStringAsFixed(2);
      }
      _noteController.text = entry.note ?? '';
      _selectedDate = entry.date;
      _receiptUrl = entry.receiptPhotoUrl;
    } else {
      _entryType = widget.initialType;
    }
    _noteController.addListener(_onNoteChanged);
  }

  void _onNoteChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _noteController.removeListener(_onNoteChanged);
    _noteController.dispose();
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

  void _pickDate() async {
    HapticFeedback.lightImpact();
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

  void _openAttachmentPicker() {
    showEntryAttachmentPicker(
      context: context,
      currentReceiptUrl: _receiptUrl,
      onReceiptChanged: (newUrl) {
        setState(() => _receiptUrl = newUrl);
      },
    );
  }

  void _saveEntry() async {
    final amountDouble = double.tryParse(_amountString) ?? 0.0;
    final amountCents = (amountDouble * 100).round();
    if (amountCents <= 0) {
      setState(() => _errorMessage = 'Please enter an amount greater than ₹0');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    if (widget.entryToEdit != null) {
      final updated = widget.entryToEdit!.copyWith(
        amountInCents: amountCents,
        type: _entryType,
        date: _selectedDate,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        receiptPhotoUrl: _receiptUrl,
      );
      await ref.read(ledgerActionControllerProvider).updateEntry(updated);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Updated ${_entryType == EntryType.gave ? "You Gave" : "You Got"} ${CurrencyFormatter.format(amountCents)}',
            ),
            backgroundColor: _entryType == EntryType.gave
                ? AppColors.payableRed
                : AppColors.receivableGreen,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      await ref.read(ledgerActionControllerProvider).addEntry(
            partyId: widget.partyId,
            amountInCents: amountCents,
            type: _entryType,
            date: _selectedDate,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
            receiptPhotoUrl: _receiptUrl,
          );

      if (mounted) {
        Navigator.of(context).pop();

        final isWindows = !kIsWeb && Platform.isWindows;
        if (isWindows && _entryType == EntryType.gave) {
          // Automatic trigger for Windows desktop CTS-2010 Cheque Printing
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Saved You Gave ${CurrencyFormatter.format(amountCents)} • Opening Cheque Print Preview...',
              ),
              backgroundColor: AppColors.payableRed,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'PRINT CHEQUE',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (_) => Cts2010ChequePreviewScreen(
                        initialPayeeName: widget.partyName,
                        initialAmountInCents: amountCents,
                      ),
                    ),
                  );
                },
              ),
            ),
          );
          Navigator.of(context).push(
            createAdaptivePageRoute(
              builder: (_) => Cts2010ChequePreviewScreen(
                initialPayeeName: widget.partyName,
                initialAmountInCents: amountCents,
              ),
            ),
          );
        } else {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final isGave = _entryType == EntryType.gave;
    final themeColor =
        isGave ? AppColors.payableRed : AppColors.receivableGreen;

    final containerColor = isIos
        ? (isDark
            ? CupertinoColors.systemGroupedBackground.darkColor
            : CupertinoColors.systemGroupedBackground)
        : (isDark
            ? const Color(0xFF141414)
            : Theme.of(context).colorScheme.surfaceContainerHighest);

    return PopScope(
      canPop: _isClean,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldDiscard = await showDiscardChangesDialog(context);
        if (shouldDiscard && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: DraggableScrollableSheet(
            initialChildSize: 0.95,
            minChildSize: 0.35,
            maxChildSize: 0.98,
            snap: true,
            snapSizes: const [0.95, 0.98],
            snapAnimationDuration: const Duration(milliseconds: 250),
            shouldCloseOnMinExtent: true,
            expand: false,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: containerColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28.0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                      blurRadius: 18,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top Drag Handle (centered on card)
                      const ModalDragHandle(
                        margin: EdgeInsets.only(bottom: 12.0),
                      ),

                      // Top Header: Type Indicator & Party Name
                      EntryHeader(
                        partyName: widget.partyName,
                        isEdit: widget.entryToEdit != null,
                        entryType: _entryType,
                        themeColor: themeColor,
                      ),
                      const SizedBox(height: 10),

                      // Type Switcher: You Gave vs You Got
                      EntryTypeSwitcher(
                        entryType: _entryType,
                        onTypeChanged: (newType) {
                          setState(() => _entryType = newType);
                        },
                      ),
                      const SizedBox(height: 12),

                      // Giant Typographic Amount Display (No system keyboard popup)
                      EntryAmountDisplay(
                        amountString: _amountString,
                        themeColor: themeColor,
                        errorMessage: _errorMessage,
                      ),
                      const SizedBox(height: 10),

                      // Quick Preset Chips (+₹100, +₹500, +₹1000, +₹5000)
                      EntryQuickPresetsRow(
                        entryType: _entryType,
                        onAddPreset: _addQuickPreset,
                      ),

                      // Entry name text box and date/attachments
                      const SizedBox(height: 10),
                      EntryNoteAndDetails(
                        noteController: _noteController,
                        selectedDate: _selectedDate,
                        receiptUrl: _receiptUrl,
                        themeColor: themeColor,
                        onPickDate: _pickDate,
                        onOpenAttachmentPicker: _openAttachmentPicker,
                      ),

                      const SizedBox(height: 10),

                      // Custom Oversized On-Screen Numeric Keypad (0-9, ., ⌫)
                      EntryNumericKeypad(
                        themeColor: themeColor,
                        onKeyTap: _onKeypadTap,
                        onLongPressBackspace: _onKeypadLongPressBackspace,
                      ),

                      const SizedBox(height: 12),

                      // Instant Submission Button
                      AdaptiveButton(
                        onPressed: _saveEntry,
                        isFullWidth: true,
                        height: 52,
                        type: isGave
                            ? AdaptiveButtonType.destructive
                            : AdaptiveButtonType.success,
                        isLoading: _isSubmitting,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isGave
                                  ? (isIos ? CupertinoIcons.arrow_up : Icons.arrow_upward_rounded)
                                  : (isIos ? CupertinoIcons.arrow_down : Icons.arrow_downward_rounded),
                              size: 20,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.entryToEdit != null
                                  ? 'Update ${_entryType == EntryType.gave ? "You Gave" : "You Got"} Entry'
                                  : 'Save ${_entryType == EntryType.gave ? "You Gave" : "You Got"} Entry',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
