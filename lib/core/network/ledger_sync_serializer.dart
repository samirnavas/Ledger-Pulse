import '../../data/models/party_model.dart';
import '../../data/models/voucher_model.dart';
import 'sync_codec.dart';
import 'sync_contract.dart';

class LedgerSyncSerializer {
  static Map<String, dynamic> serializeParty(Party party, String profileId) {
    return {
      'id': party.id,
      'company_id': profileId,
      'name': party.name,
      'phone_number': party.phoneNumber,
      'type': party.type.name,
      'net_balance_in_cents': party.netBalanceInCents,
      'last_updated': encodeTime(party.lastUpdated),
    };
  }

  static Map<String, dynamic> serializeVoucher(
    VoucherModel voucher, {
    bool isDeleted = false,
    int revision = 0,
  }) {
    return {
      'id': voucher.id,
      'company_id': voucher.companyId,
      'voucher_number': voucher.voucherNumber,
      'type': voucher.type.name,
      'party_id': voucher.partyId,
      'party_name': voucher.partyName,
      'date': encodeTime(voucher.date),
      'status': voucher.status.name,
      'payment_mode': voucher.paymentMode.name,
      'subtotal_in_cents': voucher.subtotalInCents,
      'tax_in_cents': voucher.taxInCents,
      'discount_in_cents': voucher.discountInCents,
      'total_amount_in_cents': voucher.totalAmountInCents,
      'narration': voucher.narration,
      'reference_number': voucher.referenceNumber,
      'source_voucher_id': voucher.sourceVoucherId,
      'receipt_photo_url': voucher.receiptPhotoUrl,
      'category_account_id': voucher.categoryAccountId,
      'wallet_account_id': voucher.walletAccountId,
      'to_wallet_account_id': voucher.toWalletAccountId,
      'created_at': encodeTime(voucher.createdAt),
      'updated_at': encodeTime(voucher.updatedAt),
      'is_deleted': isDeleted,
      'revision': revision,
    };
  }

  static SyncMutationEnvelope wrapVoucher({
    required VoucherModel voucher,
    required SyncOperation operation,
    int revision = 0,
    bool isDeleted = false,
  }) {
    return SyncMutationEnvelope(
      id: 'mut_vch_${voucher.id}_$revision',
      profileId: voucher.companyId,
      domain: SyncDomain.ledger,
      entityType: SyncEntityType.voucher,
      entityId: voucher.id,
      operation: operation,
      payload: serializeVoucher(voucher, isDeleted: isDeleted, revision: revision),
      revision: revision,
      idempotencyKey: 'idem_vch_${voucher.id}_$revision',
      createdAt: DateTime.now(),
    );
  }
}
