import 'package:uuid/uuid.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../data/models/transaction_model.dart';
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
  LedgerPaymentMethod? _paymentMethod;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isClean {
    if (widget.entryToEdit != null) {
      final entry = widget.entryToEdit!;
      final initialAmt = _amountInputFromCents(entry.amountInCents);
      final initialNote = LedgerPaymentMethod.strip(entry.note) ?? '';
      return _amountString == initialAmt &&
          _noteController.text.trim() == initialNote.trim() &&
          _selectedDate == entry.date &&
          _entryType == entry.type &&
          _paymentMethod == LedgerPaymentMethod.read(entry.note) &&
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
      _amountString = _amountInputFromCents(entry.amountInCents);
      _paymentMethod = LedgerPaymentMethod.read(entry.note);
      _noteController.text = LedgerPaymentMethod.strip(entry.note) ?? '';
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
      _amountString = _amountInputFromCents(_amountInCents + amount * 100);
    });
  }

  void _pickDate() async {
    HapticFeedback.lightImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);
    final minDate = DateTime(2020);
    final maxDate = DateTime.now().add(const Duration(days: 365));
    final localDate = _selectedDate.toLocal();

    if (isIos) {
      DateTime tempPicked = localDate;
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
                  const Text(
                    'Select Date & Time',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  CupertinoButton(
                    child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _selectedDate = tempPicked);
                      Navigator.of(ctx).pop();
                    },
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.dateAndTime,
                  initialDateTime: localDate,
                  minimumDate: minDate,
                  maximumDate: maxDate,
                  onDateTimeChanged: (d) => tempPicked = d.toLocal(),
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final picked = await showDatePicker(
        context: context,
        initialDate: localDate,
        firstDate: minDate,
        lastDate: maxDate,
      );
      if (picked != null) {
        final defaultHour = localDate.hour;
        final defaultMinute = localDate.minute;
        final defaultSecond = localDate.second;

        TimeOfDay? pickedTime;
        if (mounted) {
          pickedTime = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: defaultHour, minute: defaultMinute),
          );
        }

        final finalDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          pickedTime?.hour ?? defaultHour,
          pickedTime?.minute ?? defaultMinute,
          pickedTime != null ? 0 : defaultSecond,
        );
        setState(() {
          _selectedDate = finalDateTime;
        });
      }
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

  int get _amountInCents {
    final parts = _amountString.split('.');
    final whole = int.tryParse(parts.first) ?? 0;
    final fraction = parts.length == 1 ? 0 : int.parse(parts.last.padRight(2, '0'));
    return whole * 100 + fraction;
  }

  static String _amountInputFromCents(int cents) {
    final whole = cents ~/ 100;
    final fraction = cents % 100;
    return fraction == 0 ? '$whole' : '$whole.${fraction.toString().padLeft(2, '0')}';
  }

  final _saveRequestId = const Uuid().v4();

  void _saveEntry() async {
    if (_isSubmitting) return;
    final amountCents = _amountInCents;
    if (amountCents <= 0) {
      setState(() => _errorMessage = 'Please enter an amount greater than ₹0');
      return;
    }

    setState(() {
      _errorMessage = null;
      _isSubmitting = true;
    });

    final party = ref.read(partyDetailProvider(widget.partyId)).value;
    final payment = party != null && isLedgerPayment(party.type, _entryType) &&
        !(widget.entryToEdit?.id.startsWith('entry_init_') ?? false);
    final text = _noteController.text.trim();
    final note = payment && _paymentMethod != null
        ? _paymentMethod!.encode(text)
        : text.isEmpty ? null : text;

    try {
      if (widget.entryToEdit != null) {
        final updated = widget.entryToEdit!.copyWith(
          amountInCents: amountCents,
          type: _entryType,
          date: _selectedDate,
          note: note,
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
              requestId: _saveRequestId,
              amountInCents: amountCents,
              type: _entryType,
              date: _selectedDate,
              note: note,
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
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error.toString();
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final party = ref.watch(partyDetailProvider(widget.partyId)).value;
    final opening = widget.entryToEdit?.id.startsWith('entry_init_') ?? false;
    final payment = party != null && isLedgerPayment(party.type, _entryType) && !opening;
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

                      if (party != null)
                        Text(
                          opening ? 'Opening balance' : payment
                              ? 'Payment movement' : 'Credit entry',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      if (payment)
                        DropdownButton<LedgerPaymentMethod>(
                          value: _paymentMethod,
                          hint: const Text('Payment method (optional)'),
                          menuMaxHeight: 280,
                          items: [
                            const DropdownMenuItem<LedgerPaymentMethod>(
                              child: Text('Unspecified'),
                            ),
                            for (final method in LedgerPaymentMethod.values)
                              DropdownMenuItem(value: method, child: Text(method.label)),
                          ],
                          onChanged: _isSubmitting ? null : (value) => setState(() => _paymentMethod = value),
                        ),

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
