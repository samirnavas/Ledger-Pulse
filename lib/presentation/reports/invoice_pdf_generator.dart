import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../data/models/company_model.dart';
import '../../data/models/gst_models.dart';
import '../../data/models/party_model.dart';
import '../../data/models/voucher_model.dart';

/// Dynamic Invoice PDF Document Generator supporting 4 unique templates,
/// logo & signature embedding, and full statutory GST reporting.
class InvoicePdfGenerator {
  static Future<Uint8List> generateInvoicePdf({
    required VoucherModel voucher,
    required Company company,
    required Party party,
    required InvoiceTemplateType templateType,
    InvoiceCustomization? customization,
  }) async {
    final pdf = pw.Document();

    pw.Font? regularFont;
    pw.Font? boldFont;
    try {
      regularFont = await PdfGoogleFonts.interRegular().timeout(const Duration(milliseconds: 250));
      boldFont = await PdfGoogleFonts.interBold().timeout(const Duration(milliseconds: 250));
    } catch (_) {
      // Fallback in offline or test environments
    }

    final theme = (regularFont != null && boldFont != null)
        ? pw.ThemeData.withFont(base: regularFont, bold: boldFont)
        : pw.ThemeData.base();

    final config = customization ?? const InvoiceCustomization();

    switch (templateType) {
      case InvoiceTemplateType.modernExpressive:
        pdf.addPage(_buildModernExpressivePage(voucher, company, party, config, theme));
        break;
      case InvoiceTemplateType.classicCorporate:
        pdf.addPage(_buildClassicCorporatePage(voucher, company, party, config, theme));
        break;
      case InvoiceTemplateType.gstStatutory:
        pdf.addPage(_buildGstStatutoryPage(voucher, company, party, config, theme));
        break;
      case InvoiceTemplateType.compactPos:
        pdf.addPage(_buildCompactPosPage(voucher, company, party, config, theme));
        break;
    }

    return await pdf.save();
  }

  // ==========================================
  // 1. MODERN EXPRESSIVE TEMPLATE
  // ==========================================
  static pw.Page _buildModernExpressivePage(
    VoucherModel voucher,
    Company company,
    Party party,
    InvoiceCustomization config,
    pw.ThemeData theme,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: theme,
      build: (context) {
        final primaryColor = PdfColor.fromHex('#4F46E5'); // Indigo
        final surfaceColor = PdfColor.fromHex('#EEF2FF');

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Top Modern Header
            pw.Container(
              padding: const pw.EdgeInsets.all(18),
              decoration: pw.BoxDecoration(
                color: surfaceColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(12)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _buildLogoWidget(config, company, primaryColor),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        company.legalName,
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                      if (company.gstin != null)
                        pw.Text(
                          'GSTIN: ${company.gstin}',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                      if (company.address != null)
                        pw.Text(
                          company.address!,
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: primaryColor,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.Text(
                          voucher.type.displayName.toUpperCase(),
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        '#${voucher.voucherNumber}',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'Date: ${DateFormatter.formatShortDate(voucher.date)}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      ),
                      if (voucher.dueDate != null)
                        pw.Text(
                          'Due: ${DateFormatter.formatShortDate(voucher.dueDate!)}',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.red700),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Party & Supply Info Card
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'BILLED TO',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          party.name,
                          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'Phone: ${party.phoneNumber}',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                        if (party.gstin != null && party.gstin!.isNotEmpty)
                          pw.Text(
                            'GSTIN: ${party.gstin}',
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                        if (party.address != null && party.address!.isNotEmpty)
                          pw.Text(
                            party.address!,
                            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                          ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'SUPPLY DETAILS',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Place of Supply: State Code ${voucher.placeOfSupplyStateCode ?? '29'}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          'Payment Mode: ${voucher.paymentMode.displayName}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        if (voucher.irn != null)
                          pw.Text(
                            'IRN: ${voucher.irn!.substring(0, 16)}...',
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                          ),
                        if (voucher.eWayBillNumber != null)
                          pw.Text(
                            'e-Way Bill: ${voucher.eWayBillNumber}',
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Line Items Table
            _buildItemsTable(voucher, primaryColor),
            pw.SizedBox(height: 16),

            // Summary & Signature
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: _buildBankAndNotesBox(config, voucher),
                ),
                pw.SizedBox(width: 24),
                pw.Expanded(
                  flex: 2,
                  child: _buildTaxSummaryCard(voucher, primaryColor),
                ),
              ],
            ),
            pw.Spacer(),

            // Authorized Signature Footer
            _buildSignatureFooter(config, company),
          ],
        );
      },
    );
  }

  // ==========================================
  // 2. CLASSIC CORPORATE TEMPLATE
  // ==========================================
  static pw.Page _buildClassicCorporatePage(
    VoucherModel voucher,
    Company company,
    Party party,
    InvoiceCustomization config,
    pw.ThemeData theme,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      theme: theme,
      build: (context) {
        final darkNavy = PdfColor.fromHex('#1E293B');

        return pw.Container(
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: darkNavy, width: 1.5),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Corporate Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        company.legalName.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: darkNavy,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        company.address ?? 'Registered Business Address',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                      ),
                      pw.Text(
                        'GSTIN: ${company.gstin ?? "N/A"} • Email: ${company.email ?? ""}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey800),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'TAX INVOICE',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: darkNavy,
                        ),
                      ),
                      pw.Text(
                        'Invoice No: ${voucher.voucherNumber}',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        'Date: ${DateFormatter.formatShortDate(voucher.date)}',
                        style: const pw.TextStyle(fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1, color: darkNavy),
              pw.SizedBox(height: 6),

              // Two column details: Bill-To & Ship-To
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Buyer / Billed To:',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(party.name, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Phone: ${party.phoneNumber}', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('GSTIN: ${party.gstin ?? "URP"}', style: const pw.TextStyle(fontSize: 9)),
                        if (party.address != null)
                          pw.Text(party.address!, style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Consignee / Shipped To:',
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          voucher.isBillToShipToDifferent
                              ? (voucher.shipToAddress ?? party.name)
                              : party.name,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.Text(
                          'Ship-To GSTIN: ${voucher.isBillToShipToDifferent ? (voucher.shipToGstin ?? "URP") : (party.gstin ?? "URP")}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.Text('Place of Supply: State ${voucher.placeOfSupplyStateCode ?? "29"}', style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),

              // Items Table
              _buildItemsTable(voucher, darkNavy),
              pw.SizedBox(height: 12),

              // Financial Breakdown & Banking
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: _buildBankAndNotesBox(config, voucher),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    flex: 2,
                    child: _buildTaxSummaryCard(voucher, darkNavy),
                  ),
                ],
              ),
              pw.Spacer(),

              // Signatory
              _buildSignatureFooter(config, company),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // 3. GST STATUTORY TAX INVOICE (With HSN, CGST, SGST, IGST, IRN & QR)
  // ==========================================
  static pw.Page _buildGstStatutoryPage(
    VoucherModel voucher,
    Company company,
    Party party,
    InvoiceCustomization config,
    pw.ThemeData theme,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: theme,
      build: (context) {
        final darkColor = PdfColors.blueGrey900;

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Statutory Top Banner with IRN & QR
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'GST TAX INVOICE',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: darkColor,
                      ),
                    ),
                    pw.Text(
                      '(Issued under Section 31 of Central Goods and Services Tax Act, 2017)',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      company.legalName,
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text('GSTIN: ${company.gstin ?? "29ABCDE1234F1ZH"} • State: Karnataka (29)', style: const pw.TextStyle(fontSize: 9)),
                    if (company.address != null)
                      pw.Text(company.address!, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
                // QR Code Widget
                pw.Container(
                  width: 75,
                  height: 75,
                  padding: const pw.EdgeInsets.all(4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  ),
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: voucher.signedQrCode ?? 'GSTN:IRN:${voucher.irn ?? "SAMPLE_IRN"}:DOC:${voucher.voucherNumber}',
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),

            // IRN & e-Way Bill Strip
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: PdfColors.grey200,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'IRN: ${voucher.irn ?? "64-character statutory hash registered with IRP"}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  if (voucher.eWayBillNumber != null)
                    pw.Text(
                      'e-Way Bill No: ${voucher.eWayBillNumber}',
                      style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // Bill-To & Ship-To (with URP enforcement display)
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Details of Receiver / Billed to:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        pw.Text(party.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        pw.Text('GSTIN / UIN: ${party.gstin ?? "URP (Unregistered)"}', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('State & Code: Karnataka (29)', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text('Phone: ${party.phoneNumber}', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                ),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey400),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Details of Consignee / Shipped to:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        pw.Text(voucher.isBillToShipToDifferent ? (voucher.shipToAddress ?? party.name) : party.name, style: const pw.TextStyle(fontSize: 9)),
                        pw.Text(
                          'Ship-To GSTIN: ${voucher.isBillToShipToDifferent ? (voucher.shipToGstin ?? "URP") : (party.gstin ?? "URP")}',
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                        pw.Text('Invoice #: ${voucher.voucherNumber} • Date: ${DateFormatter.formatShortDate(voucher.date)}', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text('Place of Supply: State ${voucher.placeOfSupplyStateCode ?? "29"}', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),

            // Statutory Multi-column GST Table (Item, HSN, Qty, Rate, Taxable, CGST, SGST, IGST, Total)
            _buildStatutoryGstTable(voucher),
            pw.SizedBox(height: 10),

            // Summary Card
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: _buildBankAndNotesBox(config, voucher),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  flex: 2,
                  child: _buildTaxSummaryCard(voucher, darkColor),
                ),
              ],
            ),
            pw.Spacer(),

            // Declaration & Authorized Signatory
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  flex: 3,
                  child: pw.Text(
                    'Declaration: We declare that this invoice shows the actual price of the goods or services described and that all particulars are true and correct.',
                    style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  flex: 2,
                  child: _buildSignatureFooter(config, company),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  // ==========================================
  // 4. COMPACT / POS RECEIPT SLIP
  // ==========================================
  static pw.Page _buildCompactPosPage(
    VoucherModel voucher,
    Company company,
    Party party,
    InvoiceCustomization config,
    pw.ThemeData theme,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      theme: theme,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              company.legalName,
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            if (company.gstin != null)
              pw.Text(
                'GSTIN: ${company.gstin}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            pw.Text(
              '${voucher.type.displayName.toUpperCase()} #${voucher.voucherNumber}',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              'Date: ${DateFormatter.formatShortDate(voucher.date)}',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text('Party: ${party.name}', style: const pw.TextStyle(fontSize: 8)),
            pw.Divider(thickness: 0.5),

            // Mini items list
            pw.ListView.builder(
              itemCount: voucher.items.length,
              itemBuilder: (context, index) {
                final item = voucher.items[index];
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 2),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          '${item.itemName} (${item.quantity.toStringAsFixed(0)} ${item.unit})',
                          style: const pw.TextStyle(fontSize: 8),
                        ),
                      ),
                      pw.Text(
                        CurrencyFormatter.format(item.totalInCents),
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                );
              },
            ),
            pw.Divider(thickness: 0.5),

            // Mini Totals
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Tax Amount:', style: const pw.TextStyle(fontSize: 8)),
                pw.Text(CurrencyFormatter.format(voucher.taxInCents), style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('GRAND TOTAL:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  CurrencyFormatter.format(voucher.totalAmountInCents),
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Text('Thank You for Your Business!', style: const pw.TextStyle(fontSize: 7)),
          ],
        );
      },
    );
  }

  // ==========================================
  // SHARED SUB-WIDGETS
  // ==========================================

  static pw.Widget _buildLogoWidget(InvoiceCustomization config, Company company, PdfColor primaryColor) {
    if (config.logoBytes != null && config.logoBytes!.isNotEmpty) {
      return pw.Image(
        pw.MemoryImage(Uint8List.fromList(config.logoBytes!)),
        height: 38,
      );
    }
    // Stylish text fallback badge
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: pw.BoxDecoration(
        color: primaryColor,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Text(
        company.name.isNotEmpty ? company.name[0].toUpperCase() : 'LP',
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
      ),
    );
  }

  static pw.Widget _buildItemsTable(VoucherModel voucher, PdfColor headerBg) {
    return pw.TableHelper.fromTextArray(
      headers: ['#', 'Item / Description', 'HSN', 'Qty', 'Unit Rate', 'Tax %', 'Amount'],
      data: List<List<dynamic>>.generate(
        voucher.items.length,
        (i) {
          final item = voucher.items[i];
          return [
            '${i + 1}',
            item.itemName,
            item.hsnCode.isNotEmpty ? item.hsnCode : '9983',
            '${item.quantity.toStringAsFixed(0)} ${item.unit}',
            CurrencyFormatter.format(item.unitPriceInCents),
            '${item.taxRatePercent.toStringAsFixed(0)}%',
            CurrencyFormatter.format(item.totalInCents),
          ];
        },
      ),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 9,
      ),
      headerDecoration: pw.BoxDecoration(color: headerBg),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        0: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.center,
        6: pw.Alignment.centerRight,
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    );
  }

  static pw.Widget _buildStatutoryGstTable(VoucherModel voucher) {
    return pw.TableHelper.fromTextArray(
      headers: ['#', 'Item', 'HSN', 'Qty', 'Taxable', 'CGST', 'SGST', 'IGST', 'Total'],
      data: List<List<dynamic>>.generate(
        voucher.items.length,
        (i) {
          final item = voucher.items[i];
          return [
            '${i + 1}',
            item.itemName,
            item.hsnCode.isNotEmpty ? item.hsnCode : '9983',
            '${item.quantity.toStringAsFixed(0)} ${item.unit}',
            CurrencyFormatter.format((item.unitPriceInCents * item.quantity).round()),
            item.cgstInCents > 0 ? CurrencyFormatter.format(item.cgstInCents) : '-',
            item.sgstInCents > 0 ? CurrencyFormatter.format(item.sgstInCents) : '-',
            item.igstInCents > 0 ? CurrencyFormatter.format(item.igstInCents) : '-',
            CurrencyFormatter.format(item.totalInCents),
          ];
        },
      ),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 8,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      cellStyle: const pw.TextStyle(fontSize: 7.5),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        0: pw.Alignment.center,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
        6: pw.Alignment.centerRight,
        7: pw.Alignment.centerRight,
        8: pw.Alignment.centerRight,
      },
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    );
  }

  static pw.Widget _buildTaxSummaryCard(VoucherModel voucher, PdfColor accentColor) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        children: [
          _buildSummaryRow('Subtotal:', CurrencyFormatter.format(voucher.subtotalInCents)),
          if (voucher.cgstInCents > 0)
            _buildSummaryRow('CGST:', CurrencyFormatter.format(voucher.cgstInCents)),
          if (voucher.sgstInCents > 0)
            _buildSummaryRow('SGST:', CurrencyFormatter.format(voucher.sgstInCents)),
          if (voucher.igstInCents > 0)
            _buildSummaryRow('IGST:', CurrencyFormatter.format(voucher.igstInCents)),
          if (voucher.cgstInCents == 0 && voucher.sgstInCents == 0 && voucher.igstInCents == 0 && voucher.taxInCents > 0)
            _buildSummaryRow('GST Total:', CurrencyFormatter.format(voucher.taxInCents)),
          if (voucher.discountInCents > 0)
            _buildSummaryRow('Discount:', '-${CurrencyFormatter.format(voucher.discountInCents)}'),
          pw.Divider(thickness: 1),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Amount:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                CurrencyFormatter.format(voucher.totalAmountInCents),
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: accentColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSummaryRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static pw.Widget _buildBankAndNotesBox(InvoiceCustomization config, VoucherModel voucher) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('BANK & PAYMENT DETAILS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text('Bank: ${config.bankName} • A/C: ${config.bankAccountNumber}', style: const pw.TextStyle(fontSize: 8)),
        pw.Text('IFSC: ${config.bankIfsc} • UPI: ${config.upiId}', style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 6),
        pw.Text('TERMS & CONDITIONS', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text(config.termsAndConditions, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      ],
    );
  }

  static pw.Widget _buildSignatureFooter(InvoiceCustomization config, Company company) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text('For ${company.legalName}', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 8),
        if (config.signatureBytes != null && config.signatureBytes!.isNotEmpty)
          pw.Image(
            pw.MemoryImage(Uint8List.fromList(config.signatureBytes!)),
            height: 30,
          )
        else
          pw.Container(height: 20),
        pw.Container(width: 140, height: 1, color: PdfColors.grey400),
        pw.SizedBox(height: 2),
        pw.Text(config.authorizedSignatoryName, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
        pw.Text(config.authorizedSignatoryDesignation, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      ],
    );
  }
}
