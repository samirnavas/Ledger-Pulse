import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/accounting/gst_tax_engine.dart';
import '../../data/models/gst_models.dart';
import '../../data/models/voucher_model.dart';
import '../../data/services/einvoice_ewaybill_service.dart';
import '../../data/services/gst_validation_service.dart';

final gstValidationServiceProvider = Provider<GstValidationService>((ref) {
  return GstValidationService();
});

final einvoiceEwaybillServiceProvider = Provider<EInvoiceEWayBillService>((ref) {
  final gstValidator = ref.watch(gstValidationServiceProvider);
  return EInvoiceEWayBillService(gstValidator: gstValidator);
});

class SubscriptionQuotaNotifier extends Notifier<SubscriptionQuota> {
  @override
  SubscriptionQuota build() {
    final service = ref.watch(einvoiceEwaybillServiceProvider);
    return service.currentQuota;
  }

  void updateQuota(SubscriptionQuota quota) {
    state = quota;
  }
}

final subscriptionQuotaProvider =
    NotifierProvider<SubscriptionQuotaNotifier, SubscriptionQuota>(
  SubscriptionQuotaNotifier.new,
);

/// Computes live tax breakdown for currently configured items and party
final gstTaxCalculationProvider = Provider.family<GstTaxBreakdown, ({
  String supplierStateCode,
  GstDealerType supplierDealerType,
  String placeOfSupplyStateCode,
  List<VoucherItemModel> items,
  int discountInCents,
})>((ref, params) {
  return GstTaxEngine.calculateTax(
    supplierStateCode: params.supplierStateCode,
    supplierDealerType: params.supplierDealerType,
    placeOfSupplyStateCode: params.placeOfSupplyStateCode,
    items: params.items,
    discountInCents: params.discountInCents,
  );
});
