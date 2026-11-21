# Ledger Pulse

Ledger Pulse is an offline-first Flutter app with two profile types. Switch profiles from the top bar or drawer. Profile type is fixed at creation.

- **Business ledger** has Home, Parties, Transactions, and Reports. Record customer and supplier credit, payments, opening balances, corrections, and voids. Archive settled parties while retaining their history. Reports include outstanding balances, the transaction register, statements, and posted cash or bank movements. Statements can be shared as PDF or CSV. Party CSV import validates and previews pasted rows.
- **Expense tracker** provides wallets, expense and income transactions, transfers, categories, budgets, recurring rules, and reports.

Drift stores records locally. The sync outbox sends profile-scoped changes to Supabase. Ledger postings use integer minor units, internal double-entry journals, and an audit trail. Legacy accounting code and tables preserve historical compatibility. ERP screens, modes, and licensing are outside the release scope.

## Local checks

```sh
flutter pub get
flutter analyze
flutter test
```

Flutter tests use local Drift or simulated remotes for most workflows. Verify live authentication delivery, authenticated Supabase policy enforcement, native receipt and share behavior, and device layouts in staging before release. Receipt references currently point to device files. Receipt images are not synchronized.

## Android release builds

Use an ignored `android/key.properties` file with `storeFile`, `storePassword`, `keyAlias`, and `keyPassword` to sign a production build. Resolve relative keystore paths from the Android project directory. Keep the signing file and private key outside version control. A checkout without that file can compile an unsigned release artifact.

```sh
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

APKs are written to `build/app/outputs/flutter-apk/`. Verify the signing certificate on the distribution artifact. Build and sign the iOS release on macOS with Xcode and the intended provisioning profile.

## Release gate

Run the [read-only ledger reconciliation](scripts/reconcile_ledger_postings.sql) on an approved snapshot before preparing or applying a data repair. Verify profile-mode enforcement, stale-write protection, and the role matrix on staging. The [architecture specification](docs/architecture/target-architecture.md) distinguishes the release implementation from future infrastructure work.
