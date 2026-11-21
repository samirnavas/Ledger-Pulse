import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/core/utils/currency_formatter.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/local/drift_ledger_repository.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/party_model.dart';
import 'package:ledger_pulse/data/models/transaction_model.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/ledger/ledger_workspace_views.dart';
import 'package:ledger_pulse/presentation/providers/ledger_providers.dart';
import 'package:ledger_pulse/presentation/providers/reporting_providers.dart';

void main() {
  test(
    'ledger reports include both party types and stay within the active profile',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final repo = DriftLedgerRepository(db: db, autoSync: false);
      final now = DateTime(2026, 10, 20);
      final company = Company(
        id: 'ledger-reports',
        name: 'Reports',
        legalName: 'Reports',
        currencyCode: 'USD',
        createdAt: now,
        updatedAt: now,
      );
      final other = company.copyWith(id: 'other-ledger');
      final container = ProviderContainer(
        overrides: [
          activeCompanyProvider.overrideWithValue(company),
          appDatabaseProvider.overrideWithValue(db),
          ledgerUpdatesStreamProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
          partyListProvider.overrideWith(
            (ref) => throw StateError('Dashboard filter used'),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        repo.dispose();
        await db.close();
      });
      await repo.createCompany(company);
      await repo.createCompany(other);

      Future<void> seedParty(
        String id,
        String companyId,
        PartyType type,
        int balance, {
        bool deleted = false,
      }) async {
        await db
            .into(db.parties)
            .insert(
              PartiesCompanion.insert(
                id: id,
                companyId: Value(companyId),
                name: id,
                phoneNumber: '',
                type: type,
                netBalanceInCents: Value(balance),
                lastUpdated: now,
                isDeleted: Value(deleted),
              ),
            );
        await db
            .into(db.ledgerEntries)
            .insert(
              LedgerEntriesCompanion.insert(
                id: 'entry-$id',
                companyId: Value(companyId),
                partyId: id,
                amountInCents: balance.abs(),
                type: balance > 0 ? EntryType.gave : EntryType.got,
                date: now,
              ),
            );
      }

      await seedParty('Customer', company.id, PartyType.customer, 12345);
      await seedParty('Supplier', company.id, PartyType.supplier, -5000);
      await seedParty(
        'Deleted',
        company.id,
        PartyType.customer,
        100,
        deleted: true,
      );
      await seedParty('Other', other.id, PartyType.customer, 90000);

      final balances = await container.read(
        dynamicReportDataProvider('rpt_party_balances').future,
      );
      expect(balances.rows.map((row) => row.get('party')), [
        'Customer',
        'Supplier',
      ]);
      expect(
        balances.rows.first.get('receive'),
        CurrencyFormatter.format(12345, currencyCode: 'USD'),
      );
      expect(
        balances.rows.last.get('pay'),
        CurrencyFormatter.format(5000, currencyCode: 'USD'),
      );

      final register = await container.read(
        dynamicReportDataProvider('rpt_day_book').future,
      );
      expect(
        register.rows.map((row) => row.get('party')),
        unorderedEquals(['Customer', 'Supplier', 'Deleted']),
      );
      repo.setContext(companyId: company.id);
      await repo.addEntry(
        LedgerEntry(
          id: 'credit-sale',
          partyId: 'Customer',
          amountInCents: 2000,
          type: EntryType.gave,
          date: now,
        ),
      );
      await repo.addEntry(
        LedgerEntry(
          id: 'payment-bank',
          partyId: 'Customer',
          amountInCents: 600,
          type: EntryType.got,
          date: now,
          note: LedgerPaymentMethod.bank.encode('Paid online'),
        ),
      );
      final paymentReport = await container.read(
        dynamicReportDataProvider('rpt_payments').future,
      );
      expect(paymentReport.rows.single.get('method'), 'Bank transfer');
      expect(paymentReport.rows.single.get('type'), 'Payment received');
      expect(
        paymentReport.summary['Received'],
        CurrencyFormatter.format(600, currencyCode: 'USD'),
      );
      final bank = await repo.getAccountById(
        '${company.id}_${DefaultAccounts.bankId}',
      );
      expect(bank.currentBalanceInCents, 600);

      final activitySubscription = container.listen(
        ledgerActivityProvider,
        (_, _) {},
      );
      addTearDown(activitySubscription.close);
      final activity = await container.read(ledgerActivityProvider.future);
      expect(activity.map((row) => row.party.name), isNot(contains('Other')));
      expect(
        activity.singleWhere((row) => row.party.name == 'Deleted').archived,
        isTrue,
      );
      final bankEntry = activity.singleWhere(
        (row) => row.entry.id == 'payment-bank',
      );
      expect(bankEntry.entry.runningBalanceInCents, 13745);
      await expectLater(
        container.read(dynamicReportDataProvider('rpt_gstr1').future),
        throwsArgumentError,
      );
    },
  );
}
