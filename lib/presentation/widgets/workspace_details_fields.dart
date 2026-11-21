import 'package:flutter/material.dart';

import '../../data/models/company_model.dart';

class WorkspaceDetailsControllers {
  WorkspaceDetailsControllers([Company? company])
    : address = TextEditingController(text: company?.address),
      gstin = TextEditingController(text: company?.gstin),
      bankName = TextEditingController(text: company?.bankName),
      bankAccountNumber = TextEditingController(
        text: company?.bankAccountNumber,
      ),
      bankIfsc = TextEditingController(text: company?.bankIfsc),
      upiId = TextEditingController(text: company?.upiId);

  final TextEditingController address;
  final TextEditingController gstin;
  final TextEditingController bankName;
  final TextEditingController bankAccountNumber;
  final TextEditingController bankIfsc;
  final TextEditingController upiId;

  void dispose() {
    for (final controller in [
      address,
      gstin,
      bankName,
      bankAccountNumber,
      bankIfsc,
      upiId,
    ]) {
      controller.dispose();
    }
  }
}

class WorkspaceDetailsFields extends StatelessWidget {
  const WorkspaceDetailsFields({
    super.key,
    required this.details,
    required this.enabled,
  });

  final WorkspaceDetailsControllers details;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field('Business address (optional)', details.address, maxLines: 2),
        _field('GSTIN (optional)', details.gstin),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Bank details',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        _field('Bank name (optional)', details.bankName),
        _field(
          'Account number (optional)',
          details.bankAccountNumber,
          keyboardType: TextInputType.number,
        ),
        _field('IFSC code (optional)', details.bankIfsc),
        _field('UPI ID (optional)', details.upiId),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textInputAction: maxLines == 1
          ? TextInputAction.next
          : TextInputAction.newline,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
