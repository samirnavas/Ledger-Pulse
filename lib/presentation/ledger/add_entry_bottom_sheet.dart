import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../data/models/transaction_model.dart';
import '../payments/cts2010_cheque_preview_screen.dart';
import '../providers/ledger_providers.dart';


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
  bool _showNoteField = false;

  bool get _isClean {
    if (widget.entryToEdit != null) {
      final initialAmt = (widget.entryToEdit!.amountInCents ~/ 100).toString();
      final initialNote = widget.entryToEdit!.note ?? '';
      return _amountString == initialAmt &&
          _noteController.text.trim() == initialNote.trim() &&
          _selectedDate == widget.entryToEdit!.date &&
          _entryType == widget.entryToEdit!.type &&
          _receiptUrl == widget.entryToEdit!.receiptPhotoUrl;
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
      _amountString = (entry.amountInCents ~/ 100).toString();
      _noteController.text = entry.note ?? '';
      _selectedDate = entry.date;
      _receiptUrl = entry.receiptPhotoUrl;
      _showNoteField = entry.note != null && entry.note!.trim().isNotEmpty;
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

  Future<void> _handlePopAction() async {
    if (_isClean) {
      Navigator.of(context).pop();
      return;
    }
    final shouldDiscard = await showDiscardChangesDialog(context);
    if (shouldDiscard && mounted) {
      Navigator.of(context).pop();
    }
  }

  void _onKeypadTap(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      _errorMessage = null;
      if (key == 'backspace') {
        if (_amountString.length > 1) {
          _amountString = _amountString.substring(0, _amountString.length - 1);
        } else {
          _amountString = '0';
        }
      } else if (key == '00') {
        if (_amountString != '0' && _amountString.length <= 7) {
          _amountString += '00';
        }
      } else if (key == '0') {
        if (_amountString != '0' && _amountString.length <= 8) {
          _amountString += '0';
        }
      } else {
        // Digits 1-9
        if (_amountString == '0') {
          _amountString = key;
        } else if (_amountString.length <= 8) {
          _amountString += key;
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
    setState(() {
      _errorMessage = null;
      final current = int.tryParse(_amountString) ?? 0;
      final updated = current + amount;
      _amountString = updated.toString();
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

  Future<void> _pickImage(ImageSource source) async {
    HapticFeedback.lightImpact();
    try {
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (photo != null) {
        setState(() {
          _receiptUrl = photo.path;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Receipt attached successfully!'),
              backgroundColor: AppColors.primaryBlue,
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to attach image: $e'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    }
  }

  void _showAttachmentOptions() {
    HapticFeedback.lightImpact();
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      showCupertinoModalPopup(
        context: context,
        builder: (context) => CupertinoActionSheet(
          title: const Text('Attach Bill / Receipt'),
          message:
              const Text('Select an image source for this transaction receipt'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.camera);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.camera, size: 20),
                  SizedBox(width: 8),
                  Text('Take Photo'),
                ],
              ),
            ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.of(context).pop();
                _pickImage(ImageSource.gallery);
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.photo, size: 20),
                  SizedBox(width: 8),
                  Text('Choose from Gallery'),
                ],
              ),
            ),
            if (_receiptUrl != null)
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() => _receiptUrl = null);
                },
                child: const Text('Remove Receipt'),
              ),
          ],
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
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Attach Bill / Receipt',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded,
                      color: AppColors.primaryBlue),
                  title: const Text('Take Photo',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded,
                      color: AppColors.primaryBlue),
                  title: const Text('Choose from Gallery',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.of(context).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                if (_receiptUrl != null)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.payableRed),
                    title: const Text(
                      'Remove Receipt',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.payableRed,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() => _receiptUrl = null);
                    },
                  ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _saveEntry() async {
    final amountInt = int.tryParse(_amountString) ?? 0;
    if (amountInt <= 0) {
      setState(() => _errorMessage = 'Please enter an amount greater than ₹0');
      return;
    }

    // Convert rupees to integer cents
    final amountCents = amountInt * 100;

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

  Widget _buildKeypadButton({
    required String label,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    IconData? icon,
    bool isAction = false,
  }) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          height: 52,
          child: Material(
            color: isAction
                ? CupertinoColors.systemGrey5
                : (Theme.of(context).brightness == Brightness.dark
                    ? CupertinoColors.systemGrey6
                    : CupertinoColors.white),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              borderRadius: BorderRadius.circular(14),
              child: Center(
                child: icon != null
                    ? Icon(icon,
                        size: 24,
                        color: Theme.of(context).colorScheme.onSurface)
                    : Text(
                        label,
                        style: TextStyle(
                          fontSize: label == '00' ? 20 : 24,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: SizedBox(
          height: 52,
          child: FilledButton.tonal(
            onPressed: () {
              HapticFeedback.lightImpact();
              onTap();
            },
            onLongPress: onLongPress != null
                ? () {
                    HapticFeedback.mediumImpact();
                    onLongPress();
                  }
                : null,
            style: ButtonStyle(
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 8),
              ),
            ),
            child: icon != null
                ? Icon(icon, size: 24)
                : Text(
                    label,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: label == '00' ? 20 : null,
                        ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickPresetChip(int amount) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      return Expanded(
        child: GestureDetector(
          onTap: () => _addQuickPreset(amount),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.2
                      : 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Center(
              child: Text(
                '+₹$amount',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ActionChip(
          onPressed: () => _addQuickPreset(amount),
          label: Center(
            child: Text(
              '+₹$amount',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final isGave = _entryType == EntryType.gave;
    final themeColor =
        isGave ? AppColors.payableRed : AppColors.receivableGreen;
    final rawAmountInt = int.tryParse(_amountString) ?? 0;
    final formattedDisplay = CurrencyFormatter.format(rawAmountInt * 100);

    final containerColor = isIos
        ? (isDark
            ? CupertinoColors.systemGroupedBackground.darkColor
            : CupertinoColors.systemGroupedBackground)
        : Theme.of(context).colorScheme.surfaceContainerHighest;

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
                      // Top Drag Handle
                      const ModalDragHandle(
                        margin: EdgeInsets.only(bottom: 8.0),
                      ),

                  // Top Header: Type Indicator & Party Name & Close Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
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
                                    widget.entryToEdit != null
                                        ? Icons.edit_outlined
                                        : (isGave
                                            ? Icons.arrow_upward_rounded
                                            : Icons.arrow_downward_rounded),
                                    size: 15,
                                    color: themeColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.entryToEdit != null
                                        ? 'EDIT ENTRY'
                                        : (isGave ? 'YOU GAVE' : 'YOU GOT'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: themeColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.partyName,
                                style: AppTypography.titleMedium
                                    .copyWith(fontSize: 15),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _handlePopAction();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Type Switcher: You Gave vs You Got
                  Container(
                    decoration: BoxDecoration(
                      color: isIos
                          ? CupertinoColors.systemGrey5
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() => _entryType = EntryType.gave);
                            },
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: isGave
                                    ? AppColors.payableRed
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: isGave
                                    ? [
                                        BoxShadow(
                                          color: AppColors.payableRed
                                              .withValues(alpha: 0.3),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  '- You Gave',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: isGave
                                        ? Colors.white
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() => _entryType = EntryType.got);
                            },
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 9),
                              decoration: BoxDecoration(
                                color: !isGave
                                    ? AppColors.receivableGreen
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: !isGave
                                    ? [
                                        BoxShadow(
                                          color: AppColors.receivableGreen
                                              .withValues(alpha: 0.3),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  '+ You Got',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: !isGave
                                        ? Colors.white
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Giant Typographic Amount Display (No system keyboard popup)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isIos
                          ? (Theme.of(context).brightness == Brightness.dark
                              ? CupertinoColors.systemBackground.darkColor
                              : CupertinoColors.white)
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainer,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _errorMessage != null
                            ? AppColors.payableRed
                            : themeColor.withValues(
                                alpha: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? 0.4
                                    : 0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
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
                            Flexible(
                              child: Text(
                                _amountString,
                                style: TextStyle(
                                  fontSize:
                                      _amountString.length > 6 ? 34 : 42,
                                  fontWeight: FontWeight.w900,
                                  color: themeColor,
                                  letterSpacing: 0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (rawAmountInt > 0)
                          Text(
                            formattedDisplay,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMutedLight,
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppColors.payableRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Quick Preset Chips (+₹100, +₹500, +₹1000, +₹5000)
                  Row(
                    children: [
                      _buildQuickPresetChip(100),
                      _buildQuickPresetChip(500),
                      _buildQuickPresetChip(1000),
                      _buildQuickPresetChip(5000),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Date & Optional Note & Attach Receipt row
                  Row(
                    children: [
                      // Date Chip
                      OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_today_rounded,
                            size: 14),
                        label: Text(
                          DateFormatter.formatRelative(_selectedDate),
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 34),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Note Toggle Button
                      OutlinedButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          setState(
                              () => _showNoteField = !_showNoteField);
                        },
                        icon: Icon(
                          _showNoteField || _noteController.text.isNotEmpty
                              ? Icons.edit_note_rounded
                              : Icons.note_add_outlined,
                          size: 16,
                        ),
                        label: Text(
                          _noteController.text.isNotEmpty
                              ? 'Note Added'
                              : 'Add Note',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          minimumSize: const Size(0, 34),
                          foregroundColor:
                              _noteController.text.isNotEmpty
                                  ? AppColors.primaryBlue
                                  : AppColors.textSecondaryLight,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Attach Bill Button
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showAttachmentOptions,
                          icon: Icon(
                            _receiptUrl != null
                                ? Icons.check_circle_rounded
                                : Icons.camera_alt_outlined,
                            size: 14,
                            color: _receiptUrl != null
                                ? AppColors.primaryBlue
                                : AppColors.textSecondaryLight,
                          ),
                          label: Text(
                            _receiptUrl != null
                                ? 'Bill Attached'
                                : 'Attach Bill',
                            style: TextStyle(
                              fontSize: 12,
                              color: _receiptUrl != null
                                  ? AppColors.primaryBlue
                                  : AppColors.textSecondaryLight,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            minimumSize: const Size(0, 34),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Expandable Note input
                  if (_showNoteField) ...[
                    const SizedBox(height: 8),
                    Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: isIos
                            ? (Theme.of(context).brightness ==
                                    Brightness.dark
                                ? CupertinoColors.systemBackground.darkColor
                                : CupertinoColors.white)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(
                                  alpha:
                                      Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? 0.35
                                          : 0.5),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: _noteController,
                        autofocus: true,
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Enter optional note (e.g. Bill #104)...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 10),

                  // Custom Oversized On-Screen Numeric Keypad (0-9, 00, ⌫)
                  Column(
                    children: [
                      Row(
                        children: [
                          _buildKeypadButton(
                              label: '1', onTap: () => _onKeypadTap('1')),
                          _buildKeypadButton(
                              label: '2', onTap: () => _onKeypadTap('2')),
                          _buildKeypadButton(
                              label: '3', onTap: () => _onKeypadTap('3')),
                        ],
                      ),
                      Row(
                        children: [
                          _buildKeypadButton(
                              label: '4', onTap: () => _onKeypadTap('4')),
                          _buildKeypadButton(
                              label: '5', onTap: () => _onKeypadTap('5')),
                          _buildKeypadButton(
                              label: '6', onTap: () => _onKeypadTap('6')),
                        ],
                      ),
                      Row(
                        children: [
                          _buildKeypadButton(
                              label: '7', onTap: () => _onKeypadTap('7')),
                          _buildKeypadButton(
                              label: '8', onTap: () => _onKeypadTap('8')),
                          _buildKeypadButton(
                              label: '9', onTap: () => _onKeypadTap('9')),
                        ],
                      ),
                      Row(
                        children: [
                          _buildKeypadButton(
                            label: '00',
                            onTap: () => _onKeypadTap('00'),
                            isAction: true,
                          ),
                          _buildKeypadButton(
                              label: '0', onTap: () => _onKeypadTap('0')),
                          _buildKeypadButton(
                            label: '',
                            icon: Icons.backspace_outlined,
                            onTap: () => _onKeypadTap('backspace'),
                            onLongPress: _onKeypadLongPressBackspace,
                            isAction: true,
                          ),
                        ],
                      ),
                    ],
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
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
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
