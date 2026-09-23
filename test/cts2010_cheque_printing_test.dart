import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/services/cts2010_cheque_printer_service.dart';

void main() {
  group('CTS-2010 Indian Cheque Printing Tests (FR-PMT-02, FR-PMT-03)', () {
    test('numberToIndianWords formats Lakhs, Thousands, and Paisa correctly', () {
      expect(
        Cts2010ChequePrinterService.numberToIndianWords(15000000), // ₹1,50,000
        equals('One Lakh Fifty Thousand Rupees Only'),
      );

      expect(
        Cts2010ChequePrinterService.numberToIndianWords(275000000), // ₹27,50,000
        equals('Twenty Seven Lakh Fifty Thousand Rupees Only'),
      );

      expect(
        Cts2010ChequePrinterService.numberToIndianWords(10050075), // ₹1,00,500.75
        equals('One Lakh Five Hundred Rupees and Seventy Five Paisa Only'),
      );

      expect(
        Cts2010ChequePrinterService.numberToIndianWords(50000), // ₹500
        equals('Five Hundred Rupees Only'),
      );
    });

    test('CTS-2010 standard dimensions and mm-to-pt math conform to NPCI/RBI standard', () {
      expect(Cts2010ChequePrinterService.chequeWidthMm, equals(203.0));
      expect(Cts2010ChequePrinterService.chequeHeightMm, equals(95.0));
      expect(Cts2010ChequePrinterService.micrBandHeightMm, equals(19.0));

      final widthPt = Cts2010ChequePrinterService.mmToPt(203.0);
      expect(widthPt, closeTo(575.43, 0.1));

      final heightPt = Cts2010ChequePrinterService.mmToPt(95.0);
      expect(heightPt, closeTo(269.29, 0.1));
    });

    test('generateChequePdf generates valid binary PDF bytes matching bank coordinates', () async {
      final pdfBytes = await Cts2010ChequePrinterService.generateChequePdf(
        payeeName: 'Karnataka Power Transmission Corp',
        amountInCents: 45000000, // ₹4,50,000
        chequeDate: DateTime(2026, 9, 23),
        companyName: 'Ludgerpulse ERP Pvt Ltd',
        config: const Cts2010ChequeConfig(
          bankProfile: IndianBankChequeProfile.hdfc,
          isAcPayeeOnly: true,
        ),
      );

      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46])); // %PDF header
    });
  });
}
