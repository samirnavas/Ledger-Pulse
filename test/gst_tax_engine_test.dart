import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/accounting/gst_tax_engine.dart';
import 'package:ledger_pulse/data/models/gst_models.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';

void main() {
  group('GST Tax Calculation Engine Tests (FR-GST-02)', () {
    test('computes intra-state supply for Regular Dealer (equal CGST + SGST split)', () {
      final items = [
        const VoucherItemModel(
          itemId: 'item_1',
          itemName: 'Software License',
          sku: 'SW-01',
          hsnCode: '998313',
          quantity: 2.0,
          unitPriceInCents: 100000, // ₹1,000.00 each -> ₹2,000.00 total
          taxRatePercent: 18.0, // 18% GST -> 9% CGST (₹180) + 9% SGST (₹180)
          totalInCents: 236000,
        ),
      ];

      final breakdown = GstTaxEngine.calculateTax(
        supplierStateCode: '29', // Karnataka
        supplierDealerType: GstDealerType.regular,
        placeOfSupplyStateCode: '29', // Karnataka (Intra-state)
        items: items,
      );

      expect(breakdown.isIntraState, isTrue);
      expect(breakdown.isComposition, isFalse);
      expect(breakdown.subtotalInCents, equals(200000)); // ₹2,000.00
      expect(breakdown.cgstInCents, equals(18000)); // ₹180.00
      expect(breakdown.sgstInCents, equals(18000)); // ₹180.00
      expect(breakdown.igstInCents, equals(0));
      expect(breakdown.totalTaxInCents, equals(36000)); // ₹360.00
      expect(breakdown.totalAmountInCents, equals(236000)); // ₹2,360.00
    });

    test('computes inter-state supply for Regular Dealer (full IGST)', () {
      final items = [
        const VoucherItemModel(
          itemId: 'item_1',
          itemName: 'Cloud Hosting Server',
          sku: 'SRV-01',
          hsnCode: '998315',
          quantity: 1.0,
          unitPriceInCents: 500000, // ₹5,000.00
          taxRatePercent: 18.0, // 18% IGST -> ₹900.00
          totalInCents: 590000,
        ),
      ];

      final breakdown = GstTaxEngine.calculateTax(
        supplierStateCode: '29', // Karnataka
        supplierDealerType: GstDealerType.regular,
        placeOfSupplyStateCode: '27', // Maharashtra (Inter-state)
        items: items,
      );

      expect(breakdown.isIntraState, isFalse);
      expect(breakdown.isComposition, isFalse);
      expect(breakdown.subtotalInCents, equals(500000));
      expect(breakdown.cgstInCents, equals(0));
      expect(breakdown.sgstInCents, equals(0));
      expect(breakdown.igstInCents, equals(90000)); // ₹900.00
      expect(breakdown.totalTaxInCents, equals(90000));
      expect(breakdown.totalAmountInCents, equals(590000));
    });

    test('enforces Composition Dealer rules (0% tax on Bill of Supply)', () {
      final items = [
        const VoucherItemModel(
          itemId: 'item_1',
          itemName: 'Retail Groceries Bulk',
          sku: 'GROC-01',
          hsnCode: '2106',
          quantity: 10.0,
          unitPriceInCents: 10000, // ₹100.00 each -> ₹1,000.00
          taxRatePercent: 12.0, // Standard rate is 12%, but composition cannot collect tax
          totalInCents: 100000,
        ),
      ];

      final breakdown = GstTaxEngine.calculateTax(
        supplierStateCode: '29',
        supplierDealerType: GstDealerType.composition,
        placeOfSupplyStateCode: '29',
        items: items,
      );

      expect(breakdown.isComposition, isTrue);
      expect(breakdown.subtotalInCents, equals(100000));
      expect(breakdown.cgstInCents, equals(0));
      expect(breakdown.sgstInCents, equals(0));
      expect(breakdown.igstInCents, equals(0));
      expect(breakdown.totalTaxInCents, equals(0)); // 0 tax passed to customer
      expect(breakdown.totalAmountInCents, equals(100000));
    });

    test('handles multi-item mix of rates, discounts, and cent rounding', () {
      final items = [
        const VoucherItemModel(
          itemId: 'item_1',
          itemName: 'Item 5%',
          sku: 'ITM-05',
          hsnCode: '1001',
          quantity: 2.0,
          unitPriceInCents: 10550, // ₹105.50 * 2 = 21100
          taxRatePercent: 5.0,
          discountInCents: 1100, // ₹11.00 discount -> Taxable 20000 (₹200.00)
          totalInCents: 21000,
        ),
        const VoucherItemModel(
          itemId: 'item_2',
          itemName: 'Item 28%',
          sku: 'ITM-28',
          hsnCode: '8708',
          quantity: 1.0,
          unitPriceInCents: 50000, // ₹500.00
          taxRatePercent: 28.0, // 28% tax -> ₹140.00 (14000 cents)
          totalInCents: 64000,
        ),
      ];

      final breakdown = GstTaxEngine.calculateTax(
        supplierStateCode: '29',
        supplierDealerType: GstDealerType.regular,
        placeOfSupplyStateCode: '29',
        items: items,
      );

      // Item 1: taxable 20000 -> 5% = 1000 total tax (500 CGST + 500 SGST)
      // Item 2: taxable 50000 -> 28% = 14000 total tax (7000 CGST + 7000 SGST)
      // Total taxable: 70000, CGST: 7500, SGST: 7500, Total tax: 15000
      expect(breakdown.subtotalInCents, equals(70000));
      expect(breakdown.cgstInCents, equals(7500));
      expect(breakdown.sgstInCents, equals(7500));
      expect(breakdown.totalTaxInCents, equals(15000));
      expect(breakdown.totalAmountInCents, equals(85000));
    });
  });
}
