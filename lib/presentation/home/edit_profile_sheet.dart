import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../core/theme/adaptive_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/adaptive_controls.dart';
import '../../core/widgets/adaptive_picker.dart';
import '../../data/models/company_model.dart';
import '../providers/company_providers.dart';
import '../widgets/workspace_details_fields.dart';

Future<void> showEditProfileSheet(BuildContext context, Company profile) async {
  final key = GlobalKey<_EditProfileFormState>();
  Widget panel(BuildContext sheetContext) => LayoutBuilder(
    builder: (context, constraints) {
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final height = ((constraints.maxHeight - keyboard) * 0.92).clamp(
        0.0,
        700.0,
      );
      return Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SizedBox(
              height: height,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Cancel',
                              onPressed: () => Navigator.of(sheetContext).pop(),
                              icon: const Icon(Icons.close),
                            ),
                            Expanded(
                              child: Text(
                                'Edit Workspace',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            TextButton(
                              key: const Key('save_profile_button'),
                              onPressed: () => key.currentState?.save(),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _EditProfileForm(key: key, profile: profile),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  if (AdaptiveThemeHelper.isIos(context)) {
    await showCupertinoModalPopup<void>(context: context, builder: panel);
  } else {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: panel,
    );
  }
}

class _EditProfileForm extends ConsumerStatefulWidget {
  const _EditProfileForm({super.key, required this.profile});
  final Company profile;

  @override
  ConsumerState<_EditProfileForm> createState() => _EditProfileFormState();
}

class _EditProfileFormState extends ConsumerState<_EditProfileForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _legal;
  late final WorkspaceDetailsControllers _details;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late String _currency;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _name = TextEditingController(text: p.name);
    _legal = TextEditingController(text: p.legalName);
    _details = WorkspaceDetailsControllers(p);
    _phone = TextEditingController(text: p.phoneNumber);
    _email = TextEditingController(text: p.email);
    _currency = p.currencyCode;
  }

  @override
  void dispose() {
    for (final controller in [_name, _legal, _phone, _email]) {
      controller.dispose();
    }
    _details.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final p = widget.profile;
    final updated = p.copyWith(
      name: _name.text.trim(),
      legalName: p.isExpense || _legal.text.trim().isEmpty
          ? _name.text.trim()
          : _legal.text.trim(),
      currencyCode: _currency,
      address: p.isExpense ? p.address : _details.address.text.trim(),
      gstin: p.isExpense ? p.gstin : _details.gstin.text.trim().toUpperCase(),
      bankName: p.isExpense ? p.bankName : _details.bankName.text.trim(),
      bankAccountNumber: p.isExpense
          ? p.bankAccountNumber
          : _details.bankAccountNumber.text.trim(),
      bankIfsc: p.isExpense
          ? p.bankIfsc
          : _details.bankIfsc.text.trim().toUpperCase(),
      upiId: p.isExpense ? p.upiId : _details.upiId.text.trim(),
      phoneNumber: p.isExpense ? p.phoneNumber : _phone.text.trim(),
      email: p.isExpense ? p.email : _email.text.trim(),
      updatedAt: DateTime.now(),
    );
    try {
      await ref.read(companyControllerProvider.notifier).updateCompany(updated);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save workspace: $error';
        });
      }
    }
  }

  Widget _field(
    String id,
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    int maxLines = 1,
    bool required = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: Key(id),
      controller: controller,
      enabled: !_saving,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textInputAction: maxLines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) => required && (value?.trim().isEmpty ?? true)
          ? 'Enter a workspace name'
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final currencies = {_currency, 'INR', 'USD', 'EUR', 'GBP', 'AED'};
    return Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    p.isExpense ? 'Expense Tracker' : 'Business Ledger',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text('Workspace type cannot be changed.'),
                  const SizedBox(height: 20),
                  _field(
                    'profile_name_field',
                    'Workspace name',
                    _name,
                    required: true,
                  ),
                  AdaptiveDropdownField<String>(
                    key: const Key('profile_currency_field'),
                    label: 'Currency',
                    value: _currency,
                    items: currencies
                        .map((c) => AdaptivePickerItem(value: c, label: c))
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _currency = value);
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                  if (!p.isExpense) ...[
                    _field(
                      'profile_legal_name_field',
                      'Legal / trade name',
                      _legal,
                    ),
                    _field(
                      'profile_phone_field',
                      'Phone (optional)',
                      _phone,
                      keyboardType: TextInputType.phone,
                    ),
                    _field(
                      'profile_email_field',
                      'Email (optional)',
                      _email,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    WorkspaceDetailsFields(
                      details: _details,
                      enabled: !_saving,
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  if (_saving) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
