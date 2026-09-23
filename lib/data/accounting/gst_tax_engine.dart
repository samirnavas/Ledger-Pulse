import '../models/gst_models.dart';
import '../models/voucher_model.dart';

class GstTaxEngine {
  /// Computes GST tax breakdown according to Indian statutory rules
  static GstTaxBreakdown calculateTax({
    required String supplierStateCode,
    required GstDealerType supplierDealerType,
    required String placeOfSupplyStateCode,
    required List<VoucherItemModel> items,
    int discountInCents = 0,
  }) {
    final sanitizedSupplierState = supplierStateCode.trim().padLeft(2, '0');
    final sanitizedSupplyState = placeOfSupplyStateCode.trim().padLeft(2, '0');

    final bool isIntraState = sanitizedSupplierState.isNotEmpty &&
        sanitizedSupplyState.isNotEmpty &&
        sanitizedSupplierState == sanitizedSupplyState;

    final bool isComposition = supplierDealerType == GstDealerType.composition;

    int runningSubtotal = 0;
    int runningCgst = 0;
    int runningSgst = 0;
    int runningIgst = 0;

    final List<GstItemTaxLine> calculatedLines = [];

    for (final item in items) {
      final grossItemAmount = (item.unitPriceInCents * item.quantity).round();
      final taxableAmount = grossItemAmount > item.discountInCents
          ? grossItemAmount - item.discountInCents
          : 0;

      runningSubtotal += taxableAmount;

      int itemCgst = 0;
      int itemSgst = 0;
      int itemIgst = 0;

      if (!isComposition && item.taxRatePercent > 0 && taxableAmount > 0) {
        if (isIntraState) {
          // Intra-state: Split equally between CGST and SGST
          final halfRate = item.taxRatePercent / 2.0;
          itemCgst = ((taxableAmount * halfRate) / 100.0).round();
          itemSgst = ((taxableAmount * halfRate) / 100.0).round();
          itemIgst = 0;
        } else {
          // Inter-state: Full IGST
          itemCgst = 0;
          itemSgst = 0;
          itemIgst = ((taxableAmount * item.taxRatePercent) / 100.0).round();
        }
      }

      final itemTotalTax = itemCgst + itemSgst + itemIgst;
      final finalItemTotal = taxableAmount + itemTotalTax;

      runningCgst += itemCgst;
      runningSgst += itemSgst;
      runningIgst += itemIgst;

      calculatedLines.add(
        GstItemTaxLine(
          itemId: item.itemId,
          itemName: item.itemName,
          hsnCode: item.hsnCode.isNotEmpty ? item.hsnCode : '9983',
          quantity: item.quantity,
          unitPriceInCents: item.unitPriceInCents,
          taxableAmountInCents: taxableAmount,
          taxRatePercent: item.taxRatePercent,
          cgstInCents: itemCgst,
          sgstInCents: itemSgst,
          igstInCents: itemIgst,
          totalItemTaxInCents: itemTotalTax,
          finalItemTotalInCents: finalItemTotal,
        ),
      );
    }

    final totalTax = runningCgst + runningSgst + runningIgst;
    final preDiscountTotal = runningSubtotal + totalTax;
    final postDiscountTotal = preDiscountTotal > discountInCents
        ? preDiscountTotal - discountInCents
        : 0;

    // Nearest rupee round off (cents modulo 100)
    final remainder = postDiscountTotal % 100;
    int roundOff = 0;
    if (remainder != 0) {
      if (remainder >= 50) {
        roundOff = 100 - remainder;
      } else {
        roundOff = -remainder;
      }
    }

    final finalTotal = postDiscountTotal + roundOff;

    return GstTaxBreakdown(
      subtotalInCents: runningSubtotal,
      cgstInCents: runningCgst,
      sgstInCents: runningSgst,
      igstInCents: runningIgst,
      totalTaxInCents: totalTax,
      discountInCents: discountInCents,
      roundOffInCents: roundOff,
      totalAmountInCents: finalTotal,
      isIntraState: isIntraState,
      isComposition: isComposition,
      itemLines: calculatedLines,
    );
  }
}
