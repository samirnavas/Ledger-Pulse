import 'dart:typed_data';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum IndianBankChequeProfile {
  sbi,
  hdfc,
  icici,
  axis,
  pnb,
  canara,
  bankOfBaroda,
  standardCts2010;

  String get displayName {
    switch (this) {
      case IndianBankChequeProfile.sbi:
        return 'State Bank of India (SBI)';
      case IndianBankChequeProfile.hdfc:
        return 'HDFC Bank';
      case IndianBankChequeProfile.icici:
        return 'ICICI Bank';
      case IndianBankChequeProfile.axis:
        return 'Axis Bank';
      case IndianBankChequeProfile.pnb:
        return 'Punjab National Bank (PNB)';
      case IndianBankChequeProfile.canara:
        return 'Canara Bank';
      case IndianBankChequeProfile.bankOfBaroda:
        return 'Bank of Baroda';
      case IndianBankChequeProfile.standardCts2010:
        return 'Standard Indian CTS-2010';
    }
  }

  // Coordinates in mm from top-left
  double get dateBoxLeftMm => 152.0;
  double get dateBoxTopMm => 9.5;
  double get dateCharPitchMm => 6.1;

  double get payeeLineLeftMm => 20.0;
  double get payeeLineTopMm => 23.0;

  double get amountWordsLine1LeftMm => 28.0;
  double get amountWordsLine1TopMm => 32.5;

  double get amountWordsLine2LeftMm => 16.0;
  double get amountWordsLine2TopMm => 40.5;

  double get amountFiguresLeftMm => 152.0;
  double get amountFiguresTopMm => 39.0;

  double get signatoryLeftMm => 135.0;
  double get signatoryTopMm => 66.0;
}

class Cts2010ChequeConfig {
  final IndianBankChequeProfile bankProfile;
  final bool isAcPayeeOnly;
  final bool isBearerCrossed;
  final double offsetXmm;
  final double offsetYmm;

  const Cts2010ChequeConfig({
    this.bankProfile = IndianBankChequeProfile.standardCts2010,
    this.isAcPayeeOnly = true,
    this.isBearerCrossed = true,
    this.offsetXmm = 0.0,
    this.offsetYmm = 0.0,
  });

  Cts2010ChequeConfig copyWith({
    IndianBankChequeProfile? bankProfile,
    bool? isAcPayeeOnly,
    bool? isBearerCrossed,
    double? offsetXmm,
    double? offsetYmm,
  }) {
    return Cts2010ChequeConfig(
      bankProfile: bankProfile ?? this.bankProfile,
      isAcPayeeOnly: isAcPayeeOnly ?? this.isAcPayeeOnly,
      isBearerCrossed: isBearerCrossed ?? this.isBearerCrossed,
      offsetXmm: offsetXmm ?? this.offsetXmm,
      offsetYmm: offsetYmm ?? this.offsetYmm,
    );
  }
}

class Cts2010ChequePrinterService {
  // Standard CTS-2010 Cheque Dimensions: 203mm width x 95mm height (approx 8.0" x 3.74")
  static const double chequeWidthMm = 203.0;
  static const double chequeHeightMm = 95.0;
  static const double micrBandHeightMm = 19.0; // 19mm bottom reserved zone

  /// Converts Millimeters to PDF Points (1 mm = 2.834645669291339 pt)
  static double mmToPt(double mm) => mm * 2.834645669291339;

  /// Converts an amount in cents to Indian Words (Lakhs & Crores)
  static String numberToIndianWords(int amountInCents) {
    if (amountInCents <= 0) return 'Zero Rupees Only';

    final int wholeRupees = amountInCents ~/ 100;
    final int paisa = amountInCents % 100;

    String words = _convertToWords(wholeRupees).trim();
    if (words.isEmpty) words = 'Zero';
    words = '$words Rupees';

    if (paisa > 0) {
      words = '$words and ${_convertToWords(paisa).trim()} Paisa';
    }

    return '$words Only';
  }

  static String _convertToWords(int n) {
    if (n == 0) return '';

    const units = [
      '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
      'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
      'Seventeen', 'Eighteen', 'Nineteen'
    ];

    const tens = [
      '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
    ];

    if (n < 20) return units[n];
    if (n < 100) return '${tens[n ~/ 10]} ${units[n % 10]}';
    if (n < 1000) return '${units[n ~/ 100]} Hundred ${_convertToWords(n % 100)}';
    if (n < 100000) return '${_convertToWords(n ~/ 1000)} Thousand ${_convertToWords(n % 1000)}';
    if (n < 10000000) return '${_convertToWords(n ~/ 100000)} Lakh ${_convertToWords(n % 100000)}';
    return '${_convertToWords(n ~/ 10000000)} Crore ${_convertToWords(n % 10000000)}';
  }

  /// Generates print-ready CTS-2010 Cheque PDF
  static Future<Uint8List> generateChequePdf({
    required String payeeName,
    required int amountInCents,
    required DateTime chequeDate,
    required String companyName,
    Cts2010ChequeConfig config = const Cts2010ChequeConfig(),
    bool showChequeGuidelines = false,
  }) async {
    final doc = pw.Document();
    final profile = config.bankProfile;

    final widthPt = mmToPt(chequeWidthMm);
    final heightPt = mmToPt(chequeHeightMm);

    // Format Date string: DDMMYYYY
    final dateStr = DateFormat('ddMMyyyy').format(chequeDate);

    // Format Amount in Words
    final rawWords = numberToIndianWords(amountInCents);
    final boundedWords = '*** $rawWords ***';

    // Split words across 2 lines if long
    String wordsLine1 = boundedWords;
    String wordsLine2 = '';
    if (boundedWords.length > 48) {
      final splitIdx = boundedWords.lastIndexOf(' ', 48);
      if (splitIdx != -1) {
        wordsLine1 = boundedWords.substring(0, splitIdx);
        wordsLine2 = boundedWords.substring(splitIdx).trim();
      }
    }

    // Format Amount in Figures (e.g. *** 1,50,000.00 /- ***)
    final numFormat = NumberFormat('#,##,##0.00', 'en_IN');
    final amountFiguresStr = '*** ${numFormat.format(amountInCents / 100.0)} /- ***';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(widthPt, heightPt, marginAll: 0),
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              // Optional calibration guidelines for testing
              if (showChequeGuidelines)
                pw.Positioned.fill(
                  child: pw.Container(
                    decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
                  ),
                ),

              // A/C PAYEE ONLY Crossing Lines (Top-Left)
              if (config.isAcPayeeOnly)
                pw.Positioned(
                  left: mmToPt(12.0 + config.offsetXmm),
                  top: mmToPt(6.0 + config.offsetYmm),
                  child: pw.Transform.rotate(
                    angle: -0.5,
                    child: pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Container(width: 80, height: 1, color: PdfColors.black),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'A/C PAYEE ONLY',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Container(width: 80, height: 1, color: PdfColors.black),
                      ],
                    ),
                  ),
                ),

              // Date Box Digits (D D M M Y Y Y Y)
              ...List.generate(dateStr.length, (index) {
                final digit = dateStr[index];
                final posX = profile.dateBoxLeftMm + (index * profile.dateCharPitchMm) + config.offsetXmm;
                final posY = profile.dateBoxTopMm + config.offsetYmm;
                return pw.Positioned(
                  left: mmToPt(posX),
                  top: mmToPt(posY),
                  child: pw.Text(
                    digit,
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      font: pw.Font.courierBold(),
                    ),
                  ),
                );
              }),

              // Payee Line
              pw.Positioned(
                left: mmToPt(profile.payeeLineLeftMm + config.offsetXmm),
                top: mmToPt(profile.payeeLineTopMm + config.offsetYmm),
                child: pw.Text(
                  '*** $payeeName ***',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ),

              // Amount in Words - Line 1
              pw.Positioned(
                left: mmToPt(profile.amountWordsLine1LeftMm + config.offsetXmm),
                top: mmToPt(profile.amountWordsLine1TopMm + config.offsetYmm),
                child: pw.Text(
                  wordsLine1,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
              ),

              // Amount in Words - Line 2
              if (wordsLine2.isNotEmpty)
                pw.Positioned(
                  left: mmToPt(profile.amountWordsLine2LeftMm + config.offsetXmm),
                  top: mmToPt(profile.amountWordsLine2TopMm + config.offsetYmm),
                  child: pw.Text(
                    wordsLine2,
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ),

              // Amount in Figures Box (with safety sandwiching)
              pw.Positioned(
                left: mmToPt(profile.amountFiguresLeftMm + config.offsetXmm),
                top: mmToPt(profile.amountFiguresTopMm + config.offsetYmm),
                child: pw.Text(
                  amountFiguresStr,
                  style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              ),

              // Signatory / Company Header
              pw.Positioned(
                left: mmToPt(profile.signatoryLeftMm + config.offsetXmm),
                top: mmToPt(profile.signatoryTopMm + config.offsetYmm),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('For $companyName', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 12),
                    pw.Text('Authorised Signatory', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
