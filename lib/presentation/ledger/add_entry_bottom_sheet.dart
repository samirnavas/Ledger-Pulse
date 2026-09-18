import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/constants/colors.dart';
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
  String _amountString = '0';
  final TextEditingController _noteController = TextEditingController();
  late EntryType _entryType;
  DateTime _selectedDate = DateTime.now();
  String? _receiptUrl;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _showNoteField = false;

  @override
  void initState() {
    super.initState();
    _entryType = widget.initialType;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
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

  Widget _buildKeypadButton({
    required String label,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    IconData? icon,
    bool isAction = false,
  }) {
    final isIos = AdaptiveThemeHelper.isIos(context);

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        height: 52,
        child: Material(
          color: isAction
              ? (isIos
                  ? CupertinoColors.systemGrey5
                  : Theme.of(context).colorScheme.surfaceContainerHighest)
              : (isIos
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? CupertinoColors.systemGrey6
                      : CupertinoColors.white)
                  : Theme.of(context).colorScheme.surfaceContainerLow),
          borderRadius: BorderRadius.circular(isIos ? 14 : 20),
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: BorderRadius.circular(isIos ? 14 : 20),
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

  Widget _buildQuickPresetChip(int amount) {
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
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
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

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isGave = _entryType == EntryType.gave;
    final themeColor =
        isGave ? AppColors.payableRed : AppColors.receivableGreen;
    final rawAmountInt = int.tryParse(_amountString) ?? 0;
    final formattedDisplay = CurrencyFormatter.format(rawAmountInt * 100);

    return Container(
      decoration: BoxDecoration(
        color: isIos
            ? CupertinoColors.systemGroupedBackground
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Platform Adaptive Top Handle / Pill Indicator
            Center(
              child: isIos
                  ? Container(
                      width: 38,
                      height: 5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey4,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )
                  : Container(
                      width: 38,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant.withValues(
                            alpha: Theme.of(context).brightness == Brightness.dark
                                ? 0.4
                                : 0.7),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
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
                              isGave
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 15,
                              color: themeColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isGave ? 'YOU GAVE' : 'YOU GOT',
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
                          style: AppTypography.titleMedium.copyWith(fontSize: 15),
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
                    Navigator.of(context).pop();
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
                    : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                        padding: const EdgeInsets.symmetric(vertical: 9),
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
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
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
                        padding: const EdgeInsets.symmetric(vertical: 9),
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
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isIos
                    ? (Theme.of(context).brightness == Brightness.dark
                        ? CupertinoColors.systemBackground.darkColor
                        : CupertinoColors.white)
                    : Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _errorMessage != null
                      ? AppColors.payableRed
                      : themeColor.withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
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
                            fontSize: _amountString.length > 6 ? 34 : 42,
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
                  icon: const Icon(Icons.calendar_today_rounded, size: 14),
                  label: Text(
                    DateFormatter.formatRelative(_selectedDate),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                    setState(() => _showNoteField = !_showNoteField);
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 34),
                    foregroundColor: _noteController.text.isNotEmpty
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
                      _receiptUrl != null ? 'Bill Attached' : 'Attach Bill',
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
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? CupertinoColors.systemBackground.darkColor
                          : CupertinoColors.white)
                      : Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
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
                    hintText: 'Enter optional note (e.g. Bill #104)...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                    'Save ${_entryType == EntryType.gave ? "You Gave" : "You Got"} Entry',
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
      ),
    );
  }
}
