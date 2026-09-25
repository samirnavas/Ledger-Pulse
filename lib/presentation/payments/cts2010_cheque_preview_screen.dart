
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';

import '../../data/models/party_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/services/cts2010_cheque_printer_service.dart';
import '../providers/company_providers.dart';

class Cts2010ChequePreviewScreen extends ConsumerStatefulWidget {
  final Party? party;
  final VoucherModel? paymentVoucher;
  final int initialAmountInCents;
  final String? initialPayeeName;

  const Cts2010ChequePreviewScreen({
    super.key,
    this.party,
    this.paymentVoucher,
    this.initialAmountInCents = 1500000,
    this.initialPayeeName,
  });

  @override
  ConsumerState<Cts2010ChequePreviewScreen> createState() =>
      _Cts2010ChequePreviewScreenState();
}

class _Cts2010ChequePreviewScreenState
    extends ConsumerState<Cts2010ChequePreviewScreen> {
  late IndianBankChequeProfile _selectedBank;
  late TextEditingController _payeeController;
  late TextEditingController _amountController;
  final DateTime _chequeDate = DateTime.now();
  bool _isAcPayeeOnly = true;
  double _offsetXmm = 0.0;
  double _offsetYmm = 0.0;
  Uint8List? _pdfBytes;
  bool _isRendering = false;

  @override
  void initState() {
    super.initState();
    _selectedBank = IndianBankChequeProfile.standardCts2010;
    _payeeController = TextEditingController(
      text: widget.initialPayeeName ?? widget.party?.name ?? 'Apex Infotech Solutions',
    );
    final initialAmt = widget.paymentVoucher?.totalAmountInCents ?? widget.initialAmountInCents;
    _amountController = TextEditingController(text: (initialAmt / 100.0).toStringAsFixed(2));
    _regeneratePdf();
  }

  @override
  void dispose() {
    _payeeController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _regeneratePdf() async {
    setState(() => _isRendering = true);
    final company = ref.read(activeCompanyProvider);
    final amountInRupees = double.tryParse(_amountController.text.trim()) ?? 15000.0;
    final amountInCents = (amountInRupees * 100).round();

    final bytes = await Cts2010ChequePrinterService.generateChequePdf(
      payeeName: _payeeController.text.trim(),
      amountInCents: amountInCents,
      chequeDate: _chequeDate,
      companyName: company.name,
      config: Cts2010ChequeConfig(
        bankProfile: _selectedBank,
        isAcPayeeOnly: _isAcPayeeOnly,
        offsetXmm: _offsetXmm,
        offsetYmm: _offsetYmm,
      ),
      showChequeGuidelines: true,
    );

    if (mounted) {
      setState(() {
        _pdfBytes = bytes;
        _isRendering = false;
      });
    }
  }

  Future<void> _printCheque() async {
    if (_pdfBytes == null) return;
    HapticFeedback.mediumImpact();
    await Printing.layoutPdf(
      onLayout: (format) async => _pdfBytes!,
      name: 'CTS2010_Cheque_${_payeeController.text.trim().replaceAll(" ", "_")}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AdaptiveScaffold(
      title: 'CTS-2010 Cheque Printing (Windows)',
      actions: [
        IconButton(
          tooltip: 'Direct Print Cheque',
          icon: Icon(isIos ? CupertinoIcons.printer : Icons.print_rounded),
          onPressed: _printCheque,
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bank Profile Selector
            DropdownButtonFormField<IndianBankChequeProfile>(
              initialValue: _selectedBank,
              decoration: InputDecoration(
                labelText: 'Select Bank Cheque Format',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                prefixIcon: Icon(
                  isIos ? CupertinoIcons.building_2_fill : Icons.account_balance_rounded,
                ),
                isDense: true,
                filled: true,
                fillColor: isIos
                    ? (isDark
                        ? CupertinoColors.systemGrey6.darkColor
                        : CupertinoColors.systemGrey6)
                    : Theme.of(context).colorScheme.surfaceContainerLowest,
              ),
              items: IndianBankChequeProfile.values.map((b) {
                return DropdownMenuItem(
                  value: b,
                  child: Text(b.displayName, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedBank = val);
                  _regeneratePdf();
                }
              },
            ),
            const SizedBox(height: 12),

            // Payee & Amount Inputs
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _payeeController,
                    decoration: InputDecoration(
                      labelText: 'Payee Name *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      prefixIcon: Icon(
                        isIos ? CupertinoIcons.person : Icons.person_outline,
                      ),
                      filled: true,
                      fillColor: isIos
                          ? (isDark
                              ? CupertinoColors.systemGrey6.darkColor
                              : CupertinoColors.systemGrey6)
                          : Theme.of(context).colorScheme.surfaceContainerLowest,
                    ),
                    onChanged: (_) => _regeneratePdf(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Amount (₹) *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      prefixIcon: Icon(
                        isIos ? CupertinoIcons.money_dollar : Icons.currency_rupee_rounded,
                      ),
                      filled: true,
                      fillColor: isIos
                          ? (isDark
                              ? CupertinoColors.systemGrey6.darkColor
                              : CupertinoColors.systemGrey6)
                          : Theme.of(context).colorScheme.surfaceContainerLowest,
                    ),
                    onChanged: (_) => _regeneratePdf(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Options: A/C Payee Only & Calibration Offsets
            Row(
              children: [
                FilterChip(
                  label: const Text('A/C PAYEE ONLY'),
                  selected: _isAcPayeeOnly,
                  shape: const StadiumBorder(),
                  onSelected: (val) {
                    setState(() => _isAcPayeeOnly = val);
                    _regeneratePdf();
                  },
                ),
                const Spacer(),
                Text('Calibration Offsets: X: ${_offsetXmm.toStringAsFixed(1)}mm, Y: ${_offsetYmm.toStringAsFixed(1)}mm',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 14),

            // Interactive Cheque PDF Preview Box
            if (isIos)
              LiquidGlassCard(
                borderRadius: 24,
                padding: EdgeInsets.zero,
                child: SizedBox(
                  height: 240,
                  child: _isRendering || _pdfBytes == null
                      ? const Center(child: CupertinoActivityIndicator(radius: 14))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: PdfPreview(
                            build: (format) async => _pdfBytes!,
                            useActions: false,
                            canChangeOrientation: false,
                            canChangePageFormat: false,
                            maxPageWidth: 600,
                            loadingWidget: const Center(child: CupertinoActivityIndicator()),
                          ),
                        ),
                ),
              )
            else
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surfaceContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5)),
                ),
                child: SizedBox(
                  height: 240,
                  child: _isRendering || _pdfBytes == null
                      ? const Center(child: CupertinoActivityIndicator(radius: 14))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: PdfPreview(
                            build: (format) async => _pdfBytes!,
                            useActions: false,
                            canChangeOrientation: false,
                            canChangePageFormat: false,
                            maxPageWidth: 600,
                            loadingWidget: const Center(child: CupertinoActivityIndicator()),
                          ),
                        ),
                ),
              ),
            const SizedBox(height: 16),

            // Fine-tuning Calibration Slider
            Row(
              children: [
                const Text('Fine Offset X (mm):', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _offsetXmm,
                    min: -10.0,
                    max: 10.0,
                    divisions: 40,
                    label: '${_offsetXmm.toStringAsFixed(1)} mm',
                    onChanged: (v) {
                      setState(() => _offsetXmm = v);
                      _regeneratePdf();
                    },
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const Text('Fine Offset Y (mm):', style: TextStyle(fontSize: 12)),
                Expanded(
                  child: Slider(
                    value: _offsetYmm,
                    min: -10.0,
                    max: 10.0,
                    divisions: 40,
                    label: '${_offsetYmm.toStringAsFixed(1)} mm',
                    onChanged: (v) {
                      setState(() => _offsetYmm = v);
                      _regeneratePdf();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Print Cheque Button
            SizedBox(
              width: double.infinity,
              child: AdaptiveButton(
                onPressed: _printCheque,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isIos ? CupertinoIcons.printer : Icons.print_rounded,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Print CTS-2010 Cheque (Windows Spooler)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
