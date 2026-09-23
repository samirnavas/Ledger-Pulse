import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/colors.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/draggable_modal_sheet.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/company_model.dart';
import '../../data/models/gst_models.dart';
import '../../data/models/party_model.dart';
import '../../data/models/voucher_model.dart';
import '../../data/services/payment_gateway_service.dart';
import 'invoice_pdf_generator.dart';

class PdfExportModal extends StatefulWidget {
  final Uint8List pdfBytes;
  final File file;
  final String fileName;
  final String partyName;
  final String periodLabel;
  final String? partyPhone;
  final VoucherModel? voucher;
  final Company? company;
  final Party? party;

  const PdfExportModal({
    super.key,
    required this.pdfBytes,
    required this.file,
    required this.fileName,
    required this.partyName,
    required this.periodLabel,
    this.partyPhone,
    this.voucher,
    this.company,
    this.party,
  });

  static Future<void> show({
    required BuildContext context,
    required Uint8List pdfBytes,
    required File file,
    required String fileName,
    required String partyName,
    required String periodLabel,
    String? partyPhone,
    VoucherModel? voucher,
    Company? company,
    Party? party,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context) => PdfExportModal(
        pdfBytes: pdfBytes,
        file: file,
        fileName: fileName,
        partyName: partyName,
        periodLabel: periodLabel,
        partyPhone: partyPhone,
        voucher: voucher,
        company: company,
        party: party,
      ),
    );
  }

  @override
  State<PdfExportModal> createState() => _PdfExportModalState();
}

class _PdfExportModalState extends State<PdfExportModal> {
  late Uint8List _currentPdfBytes;
  late File _currentFile;
  InvoiceTemplateType _selectedTemplate = InvoiceTemplateType.gstStatutory;
  InvoiceCustomization _customization = const InvoiceCustomization();
  bool _isRegenerating = false;

  @override
  void initState() {
    super.initState();
    _currentPdfBytes = widget.pdfBytes;
    _currentFile = widget.file;
  }

  bool get _isInvoiceMode => widget.voucher != null && widget.company != null && widget.party != null;

  Future<void> _changeTemplate(InvoiceTemplateType template) async {
    if (!_isInvoiceMode || _selectedTemplate == template) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selectedTemplate = template;
      _isRegenerating = true;
    });

    try {
      final newBytes = await InvoicePdfGenerator.generateInvoicePdf(
        voucher: widget.voucher!,
        company: widget.company!,
        party: widget.party!,
        templateType: template,
        customization: _customization,
      );

      final tempDir = await getTemporaryDirectory();
      final updatedFile = File('${tempDir.path}/${widget.fileName}');
      await updatedFile.writeAsBytes(newBytes);

      if (mounted) {
        setState(() {
          _currentPdfBytes = newBytes;
          _currentFile = updatedFile;
          _isRegenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegenerating = false);
      }
    }
  }

  Future<void> _sharePdf() async {
    HapticFeedback.lightImpact();
    final xFile = XFile(_currentFile.path, mimeType: 'application/pdf', name: widget.fileName);
    final subject = _isInvoiceMode
        ? 'Invoice #${widget.voucher?.voucherNumber} from ${widget.company?.name}'
        : 'Statement - ${widget.partyName}';
    final shareText = _isInvoiceMode
        ? 'Dear ${widget.partyName}, please find attached your Invoice #${widget.voucher?.voucherNumber} for ₹${(widget.voucher!.totalAmountInCents / 100.0).toStringAsFixed(2)}. Thank you for your business!'
        : 'Ledger Statement for ${widget.partyName} (${widget.periodLabel})';

    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [xFile],
      text: shareText,
      subject: subject,
    );
  }

  Future<void> _shareViaWhatsApp() async {
    HapticFeedback.lightImpact();
    final cleanPhone = (widget.partyPhone ?? widget.party?.phoneNumber ?? '')
        .replaceAll(RegExp(r'[^0-9]'), '');
    final invoiceNo = widget.voucher?.voucherNumber ?? 'N/A';
    final amountStr = widget.voucher != null
        ? '₹${(widget.voucher!.totalAmountInCents / 100.0).toStringAsFixed(2)}'
        : '';
    final message = _isInvoiceMode
        ? 'Hello ${widget.partyName},\nYour invoice #$invoiceNo for $amountStr from ${widget.company?.name ?? "Ludgerpulse"} has been generated. Please find the attached copy.'
        : 'Hello ${widget.partyName},\nPlease review your ledger statement for ${widget.periodLabel} attached.';

    try {
      final phonePrefix = cleanPhone.length == 10 ? '91$cleanPhone' : cleanPhone;
      final uri = Uri.parse('whatsapp://send?phone=$phonePrefix&text=${Uri.encodeComponent(message)}');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback to web link or native share
        final webUri = Uri.parse('https://wa.me/$phonePrefix?text=${Uri.encodeComponent(message)}');
        if (await canLaunchUrl(webUri)) {
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        } else {
          await _sharePdf();
        }
      }
    } catch (_) {
      await _sharePdf();
    }
  }

  Future<void> _shareViaSms() async {
    HapticFeedback.lightImpact();
    final cleanPhone = (widget.partyPhone ?? widget.party?.phoneNumber ?? '')
        .replaceAll(RegExp(r'[^0-9]'), '');
    final invoiceNo = widget.voucher?.voucherNumber ?? 'N/A';
    final amountStr = widget.voucher != null
        ? '₹${(widget.voucher!.totalAmountInCents / 100.0).toStringAsFixed(2)}'
        : '';
    final message = _isInvoiceMode
        ? 'Invoice #$invoiceNo for $amountStr has been generated for ${widget.partyName} by ${widget.company?.name ?? "Ludgerpulse"}.'
        : 'Statement for ${widget.partyName} (${widget.periodLabel}) is generated by ${widget.company?.name ?? "Ludgerpulse"}.';

    final uri = Uri.parse('sms:$cleanPhone?body=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await _sharePdf();
      }
    } catch (_) {
      await _sharePdf();
    }
  }

  void _showPaymentGatewayModal(BuildContext context) {
    if (!_isInvoiceMode) return;
    HapticFeedback.lightImpact();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => _PaymentGatewayDropInSheet(
        voucher: widget.voucher!,
        company: widget.company!,
        party: widget.party!,
      ),
    );
  }

  Future<void> _sharePaymentLink() async {
    _showPaymentGatewayModal(context);
  }

  Future<void> _downloadPdf(BuildContext context) async {
    HapticFeedback.mediumImpact();
    try {
      Directory? targetDir;

      if (Platform.isAndroid) {
        targetDir = Directory('/storage/emulated/0/Download');
        if (!await targetDir.exists()) {
          targetDir = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        targetDir = await getApplicationDocumentsDirectory();
      } else {
        targetDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      }

      final savePath = '${targetDir?.path ?? (await getTemporaryDirectory()).path}/${widget.fileName}';
      final savedFile = File(savePath);
      await savedFile.writeAsBytes(_currentPdfBytes);

      if (context.mounted) {
        final isDownloads = targetDir?.path.toLowerCase().contains('download') ?? false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Saved to ${isDownloads ? 'Downloads' : 'Documents'}: ${widget.fileName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.receivableGreen,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save file: $e'),
            backgroundColor: AppColors.payableRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showBrandingConfigModal() {
    final nameController = TextEditingController(text: _customization.authorizedSignatoryName);
    final titleController = TextEditingController(text: _customization.authorizedSignatoryDesignation);
    final bankController = TextEditingController(text: _customization.bankName);
    final acctController = TextEditingController(text: _customization.bankAccountNumber);
    final ifscController = TextEditingController(text: _customization.bankIfsc);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (ctx, scroll) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scroll,
            children: [
              const ModalDragHandle(margin: EdgeInsets.only(bottom: 12)),
              Text(
                'Customize Logo & Authorized Signature',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Signatory Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'Signatory Designation',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bankController,
                decoration: const InputDecoration(
                  labelText: 'Bank Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: acctController,
                decoration: const InputDecoration(
                  labelText: 'Bank Account Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ifscController,
                decoration: const InputDecoration(
                  labelText: 'Bank IFSC',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              AdaptiveButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  setState(() {
                    _customization = _customization.copyWith(
                      authorizedSignatoryName: nameController.text.trim(),
                      authorizedSignatoryDesignation: titleController.text.trim(),
                      bankName: bankController.text.trim(),
                      bankAccountNumber: acctController.text.trim(),
                      bankIfsc: ifscController.text.trim(),
                    );
                  });
                  _changeTemplate(_selectedTemplate);
                },
                child: const Text('Save & Apply to PDF'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      snap: true,
      snapSizes: const [0.5, 0.85, 0.95],
      snapAnimationDuration: const Duration(milliseconds: 250),
      shouldCloseOnMinExtent: true,
      expand: false,
      builder: (context, scrollController) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              decoration: BoxDecoration(
                color: isIos
                    ? (isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.25),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const ModalDragHandle(
                    margin: EdgeInsets.only(top: 10, bottom: 4),
                  ),

                  // Header Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 12, 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.picture_as_pdf_rounded,
                            color: Theme.of(context).colorScheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isInvoiceMode ? 'Tax Invoice Document' : 'Account Statement PDF',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.partyName} • ${widget.periodLabel}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (_isInvoiceMode)
                          IconButton(
                            tooltip: 'Customize Logo & Signature',
                            icon: Icon(
                              isIos ? CupertinoIcons.paintbrush : Icons.tune_rounded,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            onPressed: _showBrandingConfigModal,
                          ),
                        IconButton(
                          icon: Icon(
                            isIos ? CupertinoIcons.xmark_circle_fill : Icons.close_rounded,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),

                  // Template Selector Bar (for invoices)
                  if (_isInvoiceMode)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: isDark ? const Color(0xFF262626) : const Color(0xFFF3F4F6),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: InvoiceTemplateType.values.map((template) {
                            final isSelected = _selectedTemplate == template;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: isIos
                                  ? GestureDetector(
                                      onTap: () => _changeTemplate(template),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isSelected ? CupertinoColors.activeBlue : Colors.transparent,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isSelected ? CupertinoColors.activeBlue : CupertinoColors.systemGrey3,
                                          ),
                                        ),
                                        child: Text(
                                          template.displayName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                            color: isSelected ? Colors.white : CupertinoColors.label,
                                          ),
                                        ),
                                      ),
                                    )
                                  : ChoiceChip(
                                      label: Text(template.displayName),
                                      selected: isSelected,
                                      onSelected: (_) => _changeTemplate(template),
                                    ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                  const Divider(height: 1, thickness: 1),

                  // PDF Preview Area
                  Expanded(
                    child: _isRegenerating
                        ? const Center(child: CupertinoActivityIndicator(radius: 16))
                        : ClipRRect(
                            child: Container(
                              color: isDark ? const Color(0xFF121212) : const Color(0xFFF3F4F6),
                              child: PdfPreview(
                                build: (format) async => _currentPdfBytes,
                                allowPrinting: false,
                                allowSharing: false,
                                canChangePageFormat: false,
                                canChangeOrientation: false,
                                canDebug: false,
                                maxPageWidth: 580,
                                loadingWidget: const Center(
                                  child: CupertinoActivityIndicator(radius: 14),
                                ),
                              ),
                            ),
                          ),
                  ),

                  const Divider(height: 1, thickness: 1),

                  // Action Buttons: WhatsApp, SMS, Share, Download
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // WhatsApp
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF25D366),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: _shareViaWhatsApp,
                                icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                                label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // SMS
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: _shareViaSms,
                                icon: const Icon(Icons.sms_rounded, size: 18),
                                label: const Text('SMS', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Native Share Sheet
                            Expanded(
                              child: AdaptiveButton(
                                onPressed: _sharePdf,
                                type: AdaptiveButtonType.secondary,
                                height: 46,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isIos ? CupertinoIcons.share : Icons.share_rounded,
                                      size: 18,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Native Share',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Download / Save File
                            Expanded(
                              child: AdaptiveButton(
                                onPressed: () => _downloadPdf(context),
                                type: AdaptiveButtonType.primary,
                                height: 46,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      isIos ? CupertinoIcons.arrow_down_to_line : Icons.download_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Save File',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_isInvoiceMode) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              onPressed: () => _showPaymentGatewayModal(context),
                              icon: const Icon(Icons.payment_rounded, size: 20),
                              label: const Text('Online Payment Gateways (Razorpay, Paytm, Cashfree, UPI, Stripe)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PaymentGatewayDropInSheet extends StatefulWidget {
  final VoucherModel voucher;
  final Company company;
  final Party party;

  const _PaymentGatewayDropInSheet({
    required this.voucher,
    required this.company,
    required this.party,
  });

  @override
  State<_PaymentGatewayDropInSheet> createState() => _PaymentGatewayDropInSheetState();
}

class _PaymentGatewayDropInSheetState extends State<_PaymentGatewayDropInSheet> {
  PaymentGatewayProvider _selectedProvider = PaymentGatewayProvider.bharatUpi;

  PaymentLinkPayload get _linkPayload => PaymentGatewayService.createInvoicePaymentLink(
        voucher: widget.voucher,
        company: widget.company,
        party: widget.party,
        provider: _selectedProvider,
      );

  String get _formattedMessage =>
      'Dear ${widget.party.name}, please pay ₹${(widget.voucher.totalAmountInCents / 100.0).toStringAsFixed(2)} for Invoice #${widget.voucher.voucherNumber} online via ${_selectedProvider.displayName}: ${_linkPayload.paymentUrl}';

  Future<void> _shareWhatsApp() async {
    HapticFeedback.lightImpact();
    final cleanPhone = widget.party.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$cleanPhone?text=${Uri.encodeComponent(_formattedMessage)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // ignore: deprecated_member_use
      await Share.share(_formattedMessage);
    }
  }

  Future<void> _shareSms() async {
    HapticFeedback.lightImpact();
    final cleanPhone = widget.party.phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('sms:$cleanPhone?body=${Uri.encodeComponent(_formattedMessage)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // ignore: deprecated_member_use
      await Share.share(_formattedMessage);
    }
  }

  Future<void> _shareNative() async {
    HapticFeedback.lightImpact();
    // ignore: deprecated_member_use
    await Share.share(
      _formattedMessage,
      subject: 'Payment Link for Invoice #${widget.voucher.voucherNumber}',
    );
  }

  void _copyToClipboard() {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: _linkPayload.paymentUrl));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Payment link copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _simulatePaymentCallback() {
    HapticFeedback.mediumImpact();
    final txnId = 'pay_sim_${DateTime.now().millisecondsSinceEpoch}';
    final callback = PaymentGatewayService.handlePaymentSuccessCallback(
      company: widget.company,
      invoiceVoucher: widget.voucher,
      gatewayTransactionId: txnId,
      paymentMode: _selectedProvider.displayName,
    );

    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Payment Verified (${callback.transactionId}) • Auto-created Receipt #${callback.generatedReceiptVoucher?.voucherNumber}',
        ),
        backgroundColor: AppColors.receivableGreen,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final payload = _linkPayload;
    final amountRupees = (widget.voucher.totalAmountInCents / 100.0).toStringAsFixed(2);

    final content = Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Online Payment Drop-in',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Invoice #${widget.voucher.voucherNumber} • ₹$amountRupees',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Provider Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: PaymentGatewayProvider.values.map((p) {
                final isSelected = p == _selectedProvider;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(p.displayName),
                    onSelected: (_) {
                      HapticFeedback.selectionClick();
                      setState(() => _selectedProvider = p);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),

          // Link Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.blueGrey.shade800 : Colors.blueGrey.shade200,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Direct Payment URL (${_selectedProvider.name.toUpperCase()})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        payload.paymentUrl,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Copy Link',
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  onPressed: _copyToClipboard,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Sharing actions: WhatsApp, SMS, Native Share
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _shareWhatsApp,
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  label: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _shareSms,
                  icon: const Icon(Icons.sms_rounded, size: 18),
                  label: const Text('SMS', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Native Share',
                icon: Icon(isIos ? CupertinoIcons.share : Icons.share_rounded),
                onPressed: _shareNative,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Simulate payment callback button
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: _simulatePaymentCallback,
            icon: const Icon(Icons.verified_rounded, color: AppColors.receivableGreen, size: 18),
            label: const Text(
              'Simulate Payment Webhook Confirmation',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.receivableGreen),
            ),
          ),
        ],
      ),
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 24,
        padding: EdgeInsets.zero,
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(child: content),
    );
  }
}
