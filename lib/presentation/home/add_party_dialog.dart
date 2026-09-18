import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
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

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isIos ? CupertinoColors.systemBackground : AppColors.surfaceWhite,
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
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add New ${_type.displayName}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryLight,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Party Type Toggle
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Customer')),
                    selected: _type == PartyType.customer,
                    selectedColor: AppColors.primaryBlueLight,
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _type = PartyType.customer;
                          _isReceivable = true;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Supplier')),
                    selected: _type == PartyType.supplier,
                    selectedColor: AppColors.primaryBlueLight,
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _type = PartyType.supplier;
                          _isReceivable = false;
                        });
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Name
            TextField(
              controller: _nameController,
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
              decoration: InputDecoration(
                labelText: 'Opening Balance (₹) Optional',
                prefixIcon: const Icon(Icons.currency_rupee, size: 20),
                hintText: '0.00',
                suffixIcon: DropdownButtonHideUnderline(
                  child: DropdownButton<bool>(
                    value: _isReceivable,
                    items: const [
                      DropdownMenuItem(value: true, child: Text("You'll Get (+)")),
                      DropdownMenuItem(value: false, child: Text("You'll Give (-)")),
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
