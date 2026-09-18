import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../data/models/party_model.dart';
import '../providers/ledger_providers.dart';

class AddPartyDialog extends ConsumerStatefulWidget {
  final PartyType initialType;

  const AddPartyDialog({
    super.key,
    required this.initialType,
  });

  @override
  ConsumerState<AddPartyDialog> createState() => _AddPartyDialogState();
}

class _AddPartyDialogState extends ConsumerState<AddPartyDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _balanceController = TextEditingController();
  late PartyType _type;
  bool _isReceivable = true;
  String? _error;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _isReceivable = _type == PartyType.customer;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _importFromContacts() async {
    HapticFeedback.lightImpact();
    try {
      final status =
          await FlutterContacts.permissions.request(PermissionType.read);
      if (status != PermissionStatus.granted &&
          status != PermissionStatus.limited) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Contacts permission denied. Please allow contacts access in Settings.'),
              backgroundColor: AppColors.payableRed,
            ),
          );
        }
        return;
      }

      final contact = await FlutterContacts.native.showPicker(
        properties: {ContactProperty.name, ContactProperty.phone},
      );
      if (contact != null) {
        Contact? fullContact = contact;
        if (contact.phones.isEmpty && contact.id != null) {
          fullContact = await FlutterContacts.get(
            contact.id!,
            properties: {ContactProperty.name, ContactProperty.phone},
          );
        }

        String name = fullContact?.displayName ?? contact.displayName ?? '';
        if (name.isEmpty && fullContact?.name != null) {
          final n = fullContact!.name!;
          name = [n.first, n.middle, n.last]
              .where((s) => s != null && s.isNotEmpty)
              .join(' ');
        }
        String phone = '';
        if (fullContact?.phones.isNotEmpty == true) {
          phone = fullContact!.phones.first.number;
        } else if (contact.phones.isNotEmpty) {
          phone = contact.phones.first.number;
        }

        // Strip non-standard characters while keeping leading plus
        phone = phone.replaceAll(RegExp(r'[^\d+]'), '');

        setState(() {
          if (name.isNotEmpty) {
            _nameController.text = name;
          }
          if (phone.isNotEmpty) {
            _phoneController.text = phone;
          }
          _error = null;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Imported "$name" from contacts!'),
              backgroundColor: AppColors.primaryBlue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import contact: $e'),
            backgroundColor: AppColors.payableRed,
          ),
        );
      }
    }
  }

  void _submit() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'Please enter party name');
      return;
    }
    if (phone.isEmpty) {
      setState(() => _error = 'Please enter phone number');
      return;
    }

    setState(() {
      _error = null;
      _isSubmitting = true;
    });

    final enteredBalanceCents = CurrencyFormatter.parseToCents(_balanceController.text);
    // If party is supplier and balance is owed, balance is negative; or if user chose "I owe"
    final initialBalance = _isReceivable ? enteredBalanceCents : -enteredBalanceCents;

    await ref.read(ledgerActionControllerProvider).addParty(
          name: name,
          phoneNumber: phone.startsWith('+') ? phone : '+91 $phone',
          type: _type,
          initialBalanceInCents: initialBalance,
        );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isIos
            ? (isDark
                ? CupertinoColors.systemBackground.darkColor
                : CupertinoColors.systemBackground)
            : Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add New ${_type.displayName}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
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
            const SizedBox(height: 16),

            // Prominent "Import from Contacts" Action Button
            InkWell(
              onTap: _importFromContacts,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(
                      alpha: isDark ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isIos
                          ? CupertinoIcons.person_crop_circle_badge_plus
                          : Icons.contacts_rounded,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Import from Contacts',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Party Type Toggle / Slider
            AdaptiveSegmentedControl<PartyType>(
              groupValue: _type,
              children: const {
                PartyType.customer: Text(
                  'Customer',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                PartyType.supplier: Text(
                  'Supplier',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              },
              onValueChanged: (val) {
                setState(() {
                  _type = val;
                  _isReceivable = val == PartyType.customer;
                });
              },
            ),

            const SizedBox(height: 16),

            // Name
            TextField(
              controller: _nameController,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                labelText: 'Contact / Business Name',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
            const SizedBox(height: 14),

            // Phone
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone_outlined, size: 20),
                hintText: '9876543210',
              ),
            ),
            const SizedBox(height: 14),

            // Opening Balance (optional)
            TextField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                labelText: 'Opening Balance (₹) Optional',
                prefixIcon: const Icon(Icons.currency_rupee, size: 20),
                hintText: '0.00',
                suffixIcon: DropdownButtonHideUnderline(
                  child: DropdownButton<bool>(
                    value: _isReceivable,
                    dropdownColor: Theme.of(context).colorScheme.surfaceContainerLow,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: true,
                        child: Text(
                          "You'll Get (+)",
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFF4ADE80)
                                : AppColors.receivableGreen,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: false,
                        child: Text(
                          "You'll Give (-)",
                          style: TextStyle(
                            color: isDark
                                ? const Color(0xFFF87171)
                                : AppColors.payableRed,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _isReceivable = val);
                    },
                  ),
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.payableRed,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Save Button
            AdaptiveButton(
              onPressed: _submit,
              isFullWidth: true,
              isLoading: _isSubmitting,
              child: const Text('Save & Open Ledger'),
            ),
          ],
        ),
      ),
    );
  }
}

