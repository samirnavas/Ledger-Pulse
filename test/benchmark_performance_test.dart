// ignore_for_file: avoid_print

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/accounting/voucher_posting_engine.dart';
import 'package:ledger_pulse/data/local/audit_service.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/voucher_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuditService auditService;
  late VoucherPostingEngine postingEngine;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    auditService = AuditService(db);
    postingEngine = VoucherPostingEngine(db, auditService);

    await db.into(db.companies).insert(
      CompaniesCompanion.insert(
        id: 'cmp_perf_test',
        name: 'Performance Benchmarking Corp',
        legalName: 'Performance Benchmarking Corp Pvt Ltd',
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Performance & Sizing Benchmarks (SRS Section 5.1, 6.2)', () {
    test('Silver Plan Sizing Benchmark (~100 vouchers/day, 5,000 items/accounts)', () async {
      final swTotal = Stopwatch()..start();

      // 1. Seed 5,000 items & parties in a single batch
      final swSeed = Stopwatch()..start();
      await db.batch((batch) {
        for (int i = 1; i <= 2500; i++) {
          batch.insert(
            db.inventoryItems,
            InventoryItemsCompanion.insert(
              id: 'itm_silver_$i',
              companyId: Value('cmp_perf_test'),
              sku: 'SKU-SILVER-$i',
              name: 'Silver Hardware Unit #$i',
              sellingPriceInCents: Value(10000 + (i * 10)),
              purchasePriceInCents: Value(8000 + (i * 10)),
              currentStockQuantity: Value(100.0),
              minimumStockAlert: Value(20.0),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
        for (int i = 1; i <= 2500; i++) {
          batch.insert(
            db.parties,
            PartiesCompanion.insert(
              id: 'pty_silver_$i',
              companyId: Value('cmp_perf_test'),
              name: 'Silver Customer #$i',
              phoneNumber: '+91 90000 ${i.toString().padLeft(5, '0')}',
              type: PartyType.customer,
              lastUpdated: DateTime.now(),
            ),
          );
        }
      });
      swSeed.stop();
      print('[Silver] 5,000 entities seeded in: ${swSeed.elapsedMilliseconds} ms');

      // 2. Post 100 vouchers (Silver daily volume)
      final swVouchers = Stopwatch()..start();
      for (int i = 1; i <= 100; i++) {
        final voucher = VoucherModel(
          id: 'vch_silver_$i',
          companyId: 'cmp_perf_test',
          voucherNumber: 'VCH-SILV-$i',
          type: VoucherType.sales,
          date: DateTime.now(),
          partyId: 'pty_silver_$i',
          partyName: 'Silver Customer #$i',
          status: VoucherStatus.posted,
          items: [
            VoucherItemModel(
              itemId: 'itm_silver_$i',
              itemName: 'Silver Hardware Unit #$i',
              sku: 'SKU-SILVER-$i',
              quantity: 2,
              unitPriceInCents: 10000,
              taxRatePercent: 18,
              totalInCents: 23600,
            ),
          ],
          subtotalInCents: 20000,
          taxInCents: 3600,
          totalAmountInCents: 23600,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await postingEngine.postVoucher(voucher: voucher, userId: 'usr_bench');
      }
      swVouchers.stop();
      final avgVoucherMs = swVouchers.elapsedMilliseconds / 100;
      print('[Silver] 100 double-entry vouchers posted in: ${swVouchers.elapsedMilliseconds} ms (avg: ${avgVoucherMs.toStringAsFixed(2)} ms/voucher)');
      expect(avgVoucherMs, lessThan(200.0), reason: 'Average voucher posting must be under 200ms (no noticeable UI lag per SRS 5.1)');

      // 3. Search query benchmark (indexed lookups)
      final swSearch = Stopwatch()..start();
      for (int i = 1; i <= 20; i++) {
        final targetSku = 'SKU-SILVER-${(i * 100)}';
        final res = await (db.select(db.inventoryItems)..where((t) => t.sku.equals(targetSku))).get();
        expect(res.isNotEmpty, isTrue);
      }
      swSearch.stop();
      final avgSearchMs = swSearch.elapsedMilliseconds / 20;
      print('[Silver] 20 indexed SKU searches took: ${swSearch.elapsedMilliseconds} ms (avg: ${avgSearchMs.toStringAsFixed(2)} ms/query)');
      expect(avgSearchMs, lessThan(10.0), reason: 'Search must be under 10ms');

      // 4. Financial aggregate (Trial Balance calculation across 100 vouchers)
      final swAgg = Stopwatch()..start();
      final totalReceivables = await db.customSelect(
        'SELECT SUM(amount_in_cents) as total FROM ledger_entries WHERE company_id = ?;',
        variables: [Variable.withString('cmp_perf_test')],
      ).getSingle();
      swAgg.stop();
      print('[Silver] Aggregate calculation completed in: ${swAgg.elapsedMilliseconds} ms, total: ${totalReceivables.data['total']} cents');
      expect(swAgg.elapsedMilliseconds, lessThan(50), reason: 'Ledger aggregate must be under 50ms');

      swTotal.stop();
      print('[Silver] Full benchmark passed in ${swTotal.elapsedMilliseconds} ms');
    });

    test('Diamond Plan Sizing Benchmark (~500 vouchers/day, 10,000 items/accounts)', () async {
      final swTotal = Stopwatch()..start();

      // 1. Seed 10,000 items & parties in a batch
      final swSeed = Stopwatch()..start();
      await db.batch((batch) {
        for (int i = 1; i <= 5000; i++) {
          batch.insert(
            db.inventoryItems,
            InventoryItemsCompanion.insert(
              id: 'itm_dia_$i',
              companyId: Value('cmp_perf_test'),
              sku: 'SKU-DIA-$i',
              name: 'Diamond Industrial Component #$i',
              sellingPriceInCents: Value(50000 + (i * 50)),
              purchasePriceInCents: Value(40000 + (i * 50)),
              currentStockQuantity: Value(500.0),
              minimumStockAlert: Value(50.0),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
        for (int i = 1; i <= 5000; i++) {
          batch.insert(
            db.parties,
            PartiesCompanion.insert(
              id: 'pty_dia_$i',
              companyId: Value('cmp_perf_test'),
              name: 'Diamond Enterprise Client #$i',
              phoneNumber: '+91 80000 ${i.toString().padLeft(5, '0')}',
              type: PartyType.customer,
              lastUpdated: DateTime.now(),
            ),
          );
        }
      });
      swSeed.stop();
      print('[Diamond] 10,000 entities seeded in: ${swSeed.elapsedMilliseconds} ms');

      // 2. Post 500 vouchers (Diamond daily volume)
      final swVouchers = Stopwatch()..start();
      for (int i = 1; i <= 500; i++) {
        final voucher = VoucherModel(
          id: 'vch_dia_$i',
          companyId: 'cmp_perf_test',
          voucherNumber: 'VCH-DIA-$i',
          type: VoucherType.sales,
          date: DateTime.now(),
          partyId: 'pty_dia_$i',
          partyName: 'Diamond Enterprise Client #$i',
          status: VoucherStatus.posted,
          items: [
            VoucherItemModel(
              itemId: 'itm_dia_$i',
              itemName: 'Diamond Industrial Component #$i',
              sku: 'SKU-DIA-$i',
              quantity: 5,
              unitPriceInCents: 50000,
              taxRatePercent: 18,
              totalInCents: 295000,
            ),
          ],
          subtotalInCents: 250000,
          taxInCents: 45000,
          totalAmountInCents: 295000,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        await postingEngine.postVoucher(voucher: voucher, userId: 'usr_bench');
      }
      swVouchers.stop();
      final avgVoucherMs = swVouchers.elapsedMilliseconds / 500;
      print('[Diamond] 500 double-entry vouchers posted in: ${swVouchers.elapsedMilliseconds} ms (avg: ${avgVoucherMs.toStringAsFixed(2)} ms/voucher)');
      expect(avgVoucherMs, lessThan(200.0), reason: 'Average voucher posting must be under 200ms (no noticeable UI lag per SRS 5.1)');

      // 3. Search query benchmark (indexed lookups across 10,000 items)
      final swSearch = Stopwatch()..start();
      for (int i = 1; i <= 50; i++) {
        final targetSku = 'SKU-DIA-${(i * 100)}';
        final res = await (db.select(db.inventoryItems)..where((t) => t.sku.equals(targetSku))).get();
        expect(res.isNotEmpty, isTrue);
      }
      swSearch.stop();
      final avgSearchMs = swSearch.elapsedMilliseconds / 50;
      print('[Diamond] 50 indexed searches across 10,000 items: ${swSearch.elapsedMilliseconds} ms (avg: ${avgSearchMs.toStringAsFixed(2)} ms/query)');
      expect(avgSearchMs, lessThan(10.0), reason: 'Search must be under 10ms');

      // 4. Financial statement aggregate over 500 posted vouchers (1,000 ledger lines)
      final swAgg = Stopwatch()..start();
      final entriesCount = await db.customSelect(
        'SELECT COUNT(*) as count, SUM(amount_in_cents) as total FROM ledger_entries WHERE company_id = ?;',
        variables: [Variable.withString('cmp_perf_test')],
      ).getSingle();
      swAgg.stop();
      print('[Diamond] Aggregate over ${entriesCount.data['count']} entries in: ${swAgg.elapsedMilliseconds} ms, total: ${entriesCount.data['total']} cents');
      expect(swAgg.elapsedMilliseconds, lessThan(50), reason: 'Ledger aggregate must be under 50ms');

      swTotal.stop();
      print('[Diamond] Full benchmark passed in ${swTotal.elapsedMilliseconds} ms');
    });
  });
}
