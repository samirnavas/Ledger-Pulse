import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../data/models/party_model.dart';
import '../providers/ledger_providers.dart';


class AddPartyDialog extends ConsumerStatefulWidget {
  final PartyType initialType;
  final Party? partyToEdit;

  const AddPartyDialog({
    super.key,
    required this.initialType,
    this.partyToEdit,
  });

  @override
  ConsumerState<AddPartyDialog> createState() => _AddPartyDialogState();
}

class _AddPartyDialogState extends ConsumerState<AddPartyDialog> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  late PartyType _type;
  String? _error;
  bool _isSubmitting = false;

  bool get _isClean {
    if (widget.partyToEdit != null) {
      final rawPhone = widget.partyToEdit!.phoneNumber
          .replaceFirst('+91 ', '')
          .replaceFirst('+91', '')
          .trim();
      return _nameController.text.trim() == widget.partyToEdit!.name.trim() &&
          _phoneController.text.trim() == rawPhone &&
          _type == widget.partyToEdit!.type;
    }
    return _nameController.text.trim().isEmpty &&
        _phoneController.text.trim().isEmpty;
  }

  @override
  void initState() {
    super.initState();
    if (widget.partyToEdit != null) {
      _nameController.text = widget.partyToEdit!.name;
      _phoneController.text = widget.partyToEdit!.phoneNumber
          .replaceFirst('+91 ', '')
          .replaceFirst('+91', '')
          .trim();
      _type = widget.partyToEdit!.type;
    } else {
      _type = widget.initialType;
    }
    _nameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFieldChanged);
    _phoneController.removeListener(_onFieldChanged);
    _nameController.dispose();
    _phoneController.dispose();
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

    try {
      if (widget.partyToEdit != null) {
        final updatedParty = widget.partyToEdit!.copyWith(
          name: name,
          phoneNumber: phone.startsWith('+') ? phone : '+91 $phone',
          type: _type,
          lastUpdated: DateTime.now(),
        );
        await ref.read(ledgerActionControllerProvider).updateParty(updatedParty);
      } else {
        await ref.read(ledgerActionControllerProvider).addParty(
              name: name,
              phoneNumber: phone.startsWith('+') ? phone : '+91 $phone',
              type: _type,
              initialBalanceInCents: 0,
            );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final containerColor = isIos
        ? (isDark
            ? CupertinoColors.systemBackground.darkColor
            : CupertinoColors.systemBackground)
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
      child: DraggableScrollableSheet(
        initialChildSize: 0.42,
        minChildSize: 0.25,
        maxChildSize: 0.88,
        snap: true,
        snapSizes: const [0.42, 0.88],
        snapAnimationDuration: const Duration(milliseconds: 250),
        shouldCloseOnMinExtent: true,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28.0)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 8,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Drag Handle
                  const ModalDragHandle(
                    margin: EdgeInsets.only(bottom: 12.0),
                  ),

                  // Header Title
                  Text(
                    widget.partyToEdit != null
                        ? 'Edit ${_type.displayName}'
                        : 'Add New ${_type.displayName}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: Theme.of(context).colorScheme.onSurface,
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
                      if (widget.partyToEdit != null &&
                          widget.partyToEdit!.netBalanceInCents != 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Cannot change type for a party with an active balance.',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                      setState(() {
                        _type = val;
                      });
                    },
                  ),

                  const SizedBox(height: 16),

                  // Name with inline Import from Contacts button
                  TextField(
                    controller: _nameController,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Contact / Business Name',
                      prefixIcon: const Icon(Icons.person_outline, size: 20),
                      suffixIcon: IconButton(
                        tooltip: 'Import from Contacts',
                        icon: Icon(
                          isIos
                              ? CupertinoIcons.person_crop_circle_badge_plus
                              : Icons.contacts_rounded,
                          size: 22,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: _importFromContacts,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerLowest,
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
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                      hintText: '9876543210',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerLowest,
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
                    child: Text(
                      widget.partyToEdit != null
                          ? 'Save Changes'
                          : 'Save & Open Ledger',
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
