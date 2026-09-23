import 'dart:convert';
import '../models/company_model.dart';
import '../models/party_model.dart';
import '../models/voucher_model.dart';

/// Engine to aggregate transactions and generate statutory GSTR JSON payloads
/// matching the exact schemas prescribed by the Indian Goods and Services Tax Network (GSTN).
class GstrJsonEngine {
  /// Generates official GSTR-1 Outward Supplies JSON for upload to gst.gov.in
  static Map<String, dynamic> generateGstr1Json({
    required Company company,
    required List<VoucherModel> salesVouchers,
    required List<Party> parties,
    required String returnPeriod, // e.g. "092026"
    double previousYearGrossTurnover = 15000000.0,
  }) {
    final partyMap = {for (var p in parties) p.id: p};
    final companyGstin = company.gstin ?? '29ABCDE1234F1ZH';
    final supplierState = company.stateCode ?? companyGstin.substring(0, 2);

    final List<Map<String, dynamic>> b2bList = [];
    final List<Map<String, dynamic>> b2clList = [];
    final Map<String, Map<String, dynamic>> b2csGroups = {};
    final Map<String, Map<String, dynamic>> hsnGroups = {};

    int minDocNum = 999999999;
    int maxDocNum = 0;
    int totalDocs = 0;
    int cancelledDocs = 0;
    int currentTurnoverCents = 0;

    // Filter only sales vouchers that are posted
    final relevantSales = salesVouchers.where((v) =>
        v.type == VoucherType.sales && v.status != VoucherStatus.voided).toList();

    for (final voucher in relevantSales) {
      currentTurnoverCents += voucher.totalAmountInCents;
      totalDocs++;

      final docNum = int.tryParse(voucher.voucherNumber.replaceAll(RegExp(r'[^0-9]'), '')) ?? totalDocs;
      if (docNum < minDocNum) minDocNum = docNum;
      if (docNum > maxDocNum) maxDocNum = docNum;

      final party = voucher.partyId != null ? partyMap[voucher.partyId] : null;
      final partyGstin = party?.gstin ?? voucher.shipToGstin;
      final pos = voucher.placeOfSupplyStateCode ?? supplierState;
      final isInterState = pos != supplierState;
      final voucherVal = voucher.totalAmountInCents / 100.0;

      // Group items for tax details
      final List<Map<String, dynamic>> itmsList = [];
      for (int i = 0; i < voucher.items.length; i++) {
        final item = voucher.items[i];
        final grossCents = (item.unitPriceInCents * item.quantity).round();
        final txvalCents = grossCents > item.discountInCents ? grossCents - item.discountInCents : 0;
        final txval = txvalCents / 100.0;
        final rate = item.taxRatePercent;

        double iamt = 0;
        double camt = 0;
        double samt = 0;

        if (isInterState) {
          iamt = (txval * rate) / 100.0;
        } else {
          camt = (txval * (rate / 2.0)) / 100.0;
          samt = (txval * (rate / 2.0)) / 100.0;
        }

        itmsList.add({
          'num': i + 1,
          'itm_det': {
            'rt': rate,
            'txval': double.parse(txval.toStringAsFixed(2)),
            'iamt': double.parse(iamt.toStringAsFixed(2)),
            'camt': double.parse(camt.toStringAsFixed(2)),
            'samt': double.parse(samt.toStringAsFixed(2)),
            'csamt': 0.0,
          },
        });

        // Accumulate HSN Table
        final hsnCode = item.hsnCode.isNotEmpty ? item.hsnCode : '9983';
        if (!hsnGroups.containsKey(hsnCode)) {
          hsnGroups[hsnCode] = {
            'hsn_sc': hsnCode,
            'desc': item.itemName,
            'uqc': item.unit.toUpperCase(),
            'qty': 0.0,
            'val': 0.0,
            'txval': 0.0,
            'iamt': 0.0,
            'camt': 0.0,
            'samt': 0.0,
            'csamt': 0.0,
          };
        }
        final hEntry = hsnGroups[hsnCode]!;
        hEntry['qty'] = (hEntry['qty'] as double) + item.quantity;
        hEntry['val'] = (hEntry['val'] as double) + (item.totalInCents / 100.0);
        hEntry['txval'] = (hEntry['txval'] as double) + txval;
        hEntry['iamt'] = (hEntry['iamt'] as double) + iamt;
        hEntry['camt'] = (hEntry['camt'] as double) + camt;
        hEntry['samt'] = (hEntry['samt'] as double) + samt;
      }

      final dateStr =
          '${voucher.date.day.toString().padLeft(2, '0')}-${voucher.date.month.toString().padLeft(2, '0')}-${voucher.date.year}';

      // Route to B2B, B2CL, or B2CS
      if (partyGstin != null && partyGstin.trim().length == 15 && partyGstin != 'URP') {
        // B2B: Registered Customer
        final ctin = partyGstin.trim().toUpperCase();
        var ctinGroup = b2bList.firstWhere(
          (element) => element['ctin'] == ctin,
          orElse: () {
            final newGroup = {'ctin': ctin, 'inv': <Map<String, dynamic>>[]};
            b2bList.add(newGroup);
            return newGroup;
          },
        );

        (ctinGroup['inv'] as List<Map<String, dynamic>>).add({
          'inum': voucher.voucherNumber,
          'idt': dateStr,
          'val': double.parse(voucherVal.toStringAsFixed(2)),
          'pos': pos,
          'rchrg': 'N',
          'inv_typ': 'R',
          'itms': itmsList,
        });
      } else if (isInterState && voucherVal > 250000.0) {
        // B2CL: Inter-state Unregistered > ₹2.5 Lakhs
        b2clList.add({
          'pos': pos,
          'inv': [
            {
              'inum': voucher.voucherNumber,
              'idt': dateStr,
              'val': double.parse(voucherVal.toStringAsFixed(2)),
              'itms': itmsList,
            }
          ],
        });
      } else {
        // B2CS: Intra-state or Inter-state <= ₹2.5 Lakhs
        for (final itm in itmsList) {
          final itmDet = itm['itm_det'] as Map<String, dynamic>;
          final rate = itmDet['rt'] as double;
          final key = '${pos}_$rate';

          if (!b2csGroups.containsKey(key)) {
            b2csGroups[key] = {
              'sply_ty': isInterState ? 'INTER' : 'INTRA',
              'pos': pos,
              'rt': rate,
              'txval': 0.0,
              'iamt': 0.0,
              'camt': 0.0,
              'samt': 0.0,
              'csamt': 0.0,
            };
          }
          final bEntry = b2csGroups[key]!;
          bEntry['txval'] = (bEntry['txval'] as double) + (itmDet['txval'] as double);
          bEntry['iamt'] = (bEntry['iamt'] as double) + (itmDet['iamt'] as double);
          bEntry['camt'] = (bEntry['camt'] as double) + (itmDet['camt'] as double);
          bEntry['samt'] = (bEntry['samt'] as double) + (itmDet['samt'] as double);
        }
      }
    }

    // Format HSN list with sequence numbers
    final List<Map<String, dynamic>> formattedHsnList = [];
    int hsnIndex = 1;
    for (final hsn in hsnGroups.values) {
      formattedHsnList.add({
        'num': hsnIndex++,
        'hsn_sc': hsn['hsn_sc'],
        'desc': hsn['desc'],
        'uqc': hsn['uqc'],
        'qty': double.parse((hsn['qty'] as double).toStringAsFixed(2)),
        'val': double.parse((hsn['val'] as double).toStringAsFixed(2)),
        'txval': double.parse((hsn['txval'] as double).toStringAsFixed(2)),
        'iamt': double.parse((hsn['iamt'] as double).toStringAsFixed(2)),
        'camt': double.parse((hsn['camt'] as double).toStringAsFixed(2)),
        'samt': double.parse((hsn['samt'] as double).toStringAsFixed(2)),
        'csamt': 0.0,
      });
    }

    // Document Issued Table
    final docIssueList = [
      {
        'doc_typ': 'Invoices for outward supply',
        'doc_det': [
          {
            'doc_num': 1,
            'from': minDocNum < 999999999 ? minDocNum.toString() : '1',
            'to': maxDocNum > 0 ? maxDocNum.toString() : '$totalDocs',
            'totnum': totalDocs,
            'canc': cancelledDocs,
            'net_issue': totalDocs - cancelledDocs,
          }
        ],
      }
    ];

    final b2csList = b2csGroups.values
        .map((e) => {
              'sply_ty': e['sply_ty'],
              'pos': e['pos'],
              'rt': e['rt'],
              'txval': double.parse((e['txval'] as double).toStringAsFixed(2)),
              'iamt': double.parse((e['iamt'] as double).toStringAsFixed(2)),
              'camt': double.parse((e['camt'] as double).toStringAsFixed(2)),
              'samt': double.parse((e['samt'] as double).toStringAsFixed(2)),
              'csamt': 0.0,
            })
        .toList();

    return {
      'gstin': companyGstin,
      'fp': returnPeriod,
      'gt': previousYearGrossTurnover,
      'cur_gt': double.parse((currentTurnoverCents / 100.0).toStringAsFixed(2)),
      'b2b': b2bList,
      'b2cl': b2clList,
      'b2cs': b2csList,
      'hsn': {'data': formattedHsnList},
      'doc_issue': {'doc_det': docIssueList},
      'nil': {
        'inv': [
          {'nil_amt': 0.0, 'expt_amt': 0.0, 'ngsup_amt': 0.0, 'sply_ty': 'INTRAB2B'}
        ]
      },
    };
  }

  /// Generates GSTR-2 Inward Supplies (Purchases) JSON
  static Map<String, dynamic> generateGstr2Json({
    required Company company,
    required List<VoucherModel> purchaseVouchers,
    required List<Party> parties,
    required String returnPeriod,
  }) {
    final partyMap = {for (var p in parties) p.id: p};
    final companyGstin = company.gstin ?? '29ABCDE1234F1ZH';

    final List<Map<String, dynamic>> b2bList = [];

    for (final voucher in purchaseVouchers) {
      if (voucher.type != VoucherType.purchase || voucher.status == VoucherStatus.voided) continue;
      final party = voucher.partyId != null ? partyMap[voucher.partyId] : null;
      final supplierGstin = party?.gstin ?? '29SUPPLIER9999Z1';

      final dateStr =
          '${voucher.date.day.toString().padLeft(2, '0')}-${voucher.date.month.toString().padLeft(2, '0')}-${voucher.date.year}';

      final List<Map<String, dynamic>> itmsList = [];
      for (int i = 0; i < voucher.items.length; i++) {
        final item = voucher.items[i];
        final gross = (item.unitPriceInCents * item.quantity).round();
        final txval = (gross - item.discountInCents) / 100.0;
        final tax = (txval * item.taxRatePercent) / 100.0;

        itmsList.add({
          'num': i + 1,
          'itm_det': {
            'rt': item.taxRatePercent,
            'txval': double.parse(txval.toStringAsFixed(2)),
            'iamt': voucher.igstInCents > 0 ? double.parse(tax.toStringAsFixed(2)) : 0.0,
            'camt': voucher.cgstInCents > 0 ? double.parse((tax / 2.0).toStringAsFixed(2)) : 0.0,
            'samt': voucher.sgstInCents > 0 ? double.parse((tax / 2.0).toStringAsFixed(2)) : 0.0,
          },
          'itc': {
            'elg': 'ip', // Inputs
            'tx_i': voucher.igstInCents > 0 ? double.parse(tax.toStringAsFixed(2)) : 0.0,
            'tx_c': voucher.cgstInCents > 0 ? double.parse((tax / 2.0).toStringAsFixed(2)) : 0.0,
            'tx_s': voucher.sgstInCents > 0 ? double.parse((tax / 2.0).toStringAsFixed(2)) : 0.0,
          },
        });
      }

      var ctinGroup = b2bList.firstWhere(
        (e) => e['ctin'] == supplierGstin,
        orElse: () {
          final newGroup = {'ctin': supplierGstin, 'inv': <Map<String, dynamic>>[]};
          b2bList.add(newGroup);
          return newGroup;
        },
      );

      (ctinGroup['inv'] as List<Map<String, dynamic>>).add({
        'inum': voucher.voucherNumber,
        'idt': dateStr,
        'val': double.parse((voucher.totalAmountInCents / 100.0).toStringAsFixed(2)),
        'pos': voucher.placeOfSupplyStateCode ?? '29',
        'rchrg': 'N',
        'itms': itmsList,
      });
    }

    return {
      'gstin': companyGstin,
      'fp': returnPeriod,
      'b2b': b2bList,
    };
  }

  /// Generates GSTR-2A Inward Supplies Reconciliation JSON matching portal feed
  static Map<String, dynamic> generateGstr2aReconciliationJson({
    required List<VoucherModel> booksPurchases,
    required List<Map<String, dynamic>> portal2aFeed,
  }) {
    final List<Map<String, dynamic>> matched = [];
    final List<Map<String, dynamic>> mismatched = [];
    final List<Map<String, dynamic>> missingInBooks = [];
    final List<Map<String, dynamic>> missingInPortal = [];

    final booksByInv = {for (var v in booksPurchases) v.voucherNumber.trim().toUpperCase(): v};
    final portalByInv = <String, Map<String, dynamic>>{};

    for (final pItem in portal2aFeed) {
      final invNum = (pItem['inum'] as String?)?.trim().toUpperCase() ?? '';
      portalByInv[invNum] = pItem;
    }

    // Compare Books vs Portal
    for (final entry in booksByInv.entries) {
      final inum = entry.key;
      final voucher = entry.value;

      if (portalByInv.containsKey(inum)) {
        final pItem = portalByInv[inum]!;
        final portalVal = ((pItem['val'] as num?)?.toDouble() ?? 0.0);
        final booksVal = voucher.totalAmountInCents / 100.0;

        if ((portalVal - booksVal).abs() < 1.0) {
          matched.add({
            'inum': inum,
            'supplier': voucher.partyName ?? 'Supplier',
            'amount': booksVal,
            'status': 'MATCHED',
          });
        } else {
          mismatched.add({
            'inum': inum,
            'supplier': voucher.partyName ?? 'Supplier',
            'booksAmount': booksVal,
            'portalAmount': portalVal,
            'difference': double.parse((portalVal - booksVal).toStringAsFixed(2)),
            'status': 'MISMATCHED_VALUE',
          });
        }
      } else {
        missingInPortal.add({
          'inum': inum,
          'supplier': voucher.partyName ?? 'Supplier',
          'amount': voucher.totalAmountInCents / 100.0,
          'status': 'MISSING_IN_PORTAL_2A',
        });
      }
    }

    // Portal items not in books
    for (final entry in portalByInv.entries) {
      if (!booksByInv.containsKey(entry.key)) {
        missingInBooks.add({
          'inum': entry.key,
          'supplier': entry.value['supplierGstin'] ?? 'Unknown Supplier',
          'amount': (entry.value['val'] as num?)?.toDouble() ?? 0.0,
          'status': 'MISSING_IN_BOOKS',
        });
      }
    }

    return {
      'reconciliationDate': DateTime.now().toIso8601String(),
      'summary': {
        'totalMatched': matched.length,
        'totalMismatched': mismatched.length,
        'totalMissingInBooks': missingInBooks.length,
        'totalMissingInPortal': missingInPortal.length,
      },
      'matched': matched,
      'mismatched': mismatched,
      'missingInBooks': missingInBooks,
      'missingInPortal': missingInPortal,
    };
  }

  /// Generates GSTR-3B Monthly Statutory Tax Summary JSON
  static Map<String, dynamic> generateGstr3bJson({
    required Company company,
    required List<VoucherModel> salesVouchers,
    required List<VoucherModel> purchaseVouchers,
    required String returnPeriod,
  }) {
    final companyGstin = company.gstin ?? '29ABCDE1234F1ZH';

    // 1. Table 3.1: Details of Outward Supplies and inward supplies liable to reverse charge
    double osupTaxable = 0.0;
    double osupIamt = 0.0;
    double osupCamt = 0.0;
    double osupSamt = 0.0;

    for (final v in salesVouchers) {
      if (v.status == VoucherStatus.voided) continue;
      osupTaxable += (v.subtotalInCents / 100.0);
      osupIamt += (v.igstInCents / 100.0);
      osupCamt += (v.cgstInCents / 100.0);
      osupSamt += (v.sgstInCents / 100.0);
    }

    // 2. Table 4: Eligible ITC from Purchases
    double itcIamt = 0.0;
    double itcCamt = 0.0;
    double itcSamt = 0.0;

    for (final v in purchaseVouchers) {
      if (v.status == VoucherStatus.voided) continue;
      itcIamt += (v.igstInCents / 100.0);
      itcCamt += (v.cgstInCents / 100.0);
      itcSamt += (v.sgstInCents / 100.0);
    }

    return {
      'gstin': companyGstin,
      'ret_period': returnPeriod,
      'sup_details': {
        'osup_det': {
          'txval': double.parse(osupTaxable.toStringAsFixed(2)),
          'iamt': double.parse(osupIamt.toStringAsFixed(2)),
          'camt': double.parse(osupCamt.toStringAsFixed(2)),
          'samt': double.parse(osupSamt.toStringAsFixed(2)),
          'csamt': 0.0,
        },
        'osup_zero': {'txval': 0.0, 'iamt': 0.0, 'csamt': 0.0},
        'osup_nil_exmp': {'txval': 0.0},
        'isup_rev': {'txval': 0.0, 'iamt': 0.0, 'camt': 0.0, 'samt': 0.0, 'csamt': 0.0},
        'osup_nongst': {'txval': 0.0},
      },
      'inter_sup': {
        'unreg_details': [],
        'comp_details': [],
        'uin_details': [],
      },
      'itc_elg': {
        'itc_avl': [
          {
            'ty': 'OTH',
            'iamt': double.parse(itcIamt.toStringAsFixed(2)),
            'camt': double.parse(itcCamt.toStringAsFixed(2)),
            'samt': double.parse(itcSamt.toStringAsFixed(2)),
            'csamt': 0.0,
          }
        ],
        'itc_rev': [],
        'itc_net': {
          'iamt': double.parse(itcIamt.toStringAsFixed(2)),
          'camt': double.parse(itcCamt.toStringAsFixed(2)),
          'samt': double.parse(itcSamt.toStringAsFixed(2)),
          'csamt': 0.0,
        },
        'itc_inelg': [],
      },
      'inward_sup': {
        'isup_details': [
          {'ty': 'GST', 'inter': 0.0, 'intra': 0.0}
        ]
      },
      'intr_ltfee': {
        'intr_details': {'iamt': 0.0, 'camt': 0.0, 'samt': 0.0, 'csamt': 0.0},
        'ltfee_details': {'camt': 0.0, 'samt': 0.0}
      },
    };
  }

  /// Generates GSTR-4 Composition Dealer Return JSON
  static Map<String, dynamic> generateGstr4Json({
    required Company company,
    required List<VoucherModel> vouchers,
    required String financialYear, // e.g. "2026-27"
  }) {
    final companyGstin = company.gstin ?? '27AACCS9005K1Z1';

    double totalTurnover = 0.0;
    for (final v in vouchers) {
      if (v.type == VoucherType.sales && v.status != VoucherStatus.voided) {
        totalTurnover += (v.totalAmountInCents / 100.0);
      }
    }

    // Composition tax rate is 1% (0.5% CGST + 0.5% SGST) for traders/manufacturers
    final taxRate = 1.0;
    final totalTax = (totalTurnover * taxRate) / 100.0;

    return {
      'gstin': companyGstin,
      'fy': financialYear,
      'aggregate_turnover_prior': 4500000.0,
      'turnover_details': {
        'total_turnover': double.parse(totalTurnover.toStringAsFixed(2)),
        'rate': taxRate,
        'cgst': double.parse((totalTax / 2.0).toStringAsFixed(2)),
        'sgst': double.parse((totalTax / 2.0).toStringAsFixed(2)),
        'total_tax_payable': double.parse(totalTax.toStringAsFixed(2)),
      },
      'inward_rcm': {'txval': 0.0, 'iamt': 0.0, 'camt': 0.0, 'samt': 0.0},
    };
  }

  /// Generates GSTR-9 Annual Return Summary JSON
  static Map<String, dynamic> generateGstr9Json({
    required Company company,
    required List<VoucherModel> salesVouchers,
    required List<VoucherModel> purchaseVouchers,
    required String financialYear,
  }) {
    final companyGstin = company.gstin ?? '29ABCDE1234F1ZH';

    double totalOutwardTaxable = 0.0;
    double totalCgst = 0.0;
    double totalSgst = 0.0;
    double totalIgst = 0.0;

    for (final v in salesVouchers) {
      if (v.status == VoucherStatus.voided) continue;
      totalOutwardTaxable += (v.subtotalInCents / 100.0);
      totalCgst += (v.cgstInCents / 100.0);
      totalSgst += (v.sgstInCents / 100.0);
      totalIgst += (v.igstInCents / 100.0);
    }

    double totalItc = 0.0;
    for (final v in purchaseVouchers) {
      if (v.status == VoucherStatus.voided) continue;
      final tax = v.taxInCents > 0 ? v.taxInCents : (v.cgstInCents + v.sgstInCents + v.igstInCents);
      totalItc += (tax / 100.0);
    }

    return {
      'gstin': companyGstin,
      'fp': financialYear,
      'part2_outward_supplies': {
        'b2b': double.parse(totalOutwardTaxable.toStringAsFixed(2)),
        'b2c': 0.0,
        'zero_rated': 0.0,
        'cgst': double.parse(totalCgst.toStringAsFixed(2)),
        'sgst': double.parse(totalSgst.toStringAsFixed(2)),
        'igst': double.parse(totalIgst.toStringAsFixed(2)),
        'total_turnover': double.parse(totalOutwardTaxable.toStringAsFixed(2)),
      },
      'part3_itc_details': {
        'itc_availed': double.parse(totalItc.toStringAsFixed(2)),
        'itc_reversed': 0.0,
        'net_itc_available': double.parse(totalItc.toStringAsFixed(2)),
      },
      'part4_tax_paid': {
        'tax_payable': double.parse((totalCgst + totalSgst + totalIgst).toStringAsFixed(2)),
        'tax_paid_cash': double.parse((totalCgst + totalSgst + totalIgst).toStringAsFixed(2)),
      },
    };
  }

  /// Formats any of the statutory reports into an indented JSON string
  static String formatJson(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(data);
  }
}
