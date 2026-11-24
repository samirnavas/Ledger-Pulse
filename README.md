# Paypr

Paypr is an offline-first Flutter app with two profile types. Switch profiles from the top bar or drawer. Profile type is fixed at creation.

- **Business ledger** has Home, Parties, Transactions, and Reports. Record customer and supplier credit, payments, opening balances, corrections, and voids. Archive settled parties and view or restore them from the Parties tab. Reports include outstanding balances, the transaction register, statements, and posted cash or bank movements. Statements can be shared as PDF or CSV. Party CSV import previews pasted rows, checks active and archived party names, and commits each valid batch atomically.
- **Expense tracker** provides wallets, expense and income transactions, transfers, categories, budgets, recurring rules, and reports.

Ledger entries default to the existing credit or payment classification for each direction. Choose **Payment or refund** for cash or bank settlement, or **Credit or adjustment** for a non-cash change to a party balance. Drift stores records locally. The sync outbox sends profile-scoped changes to Supabase. Ledger postings use integer minor units, internal double-entry journals, and an audit trail. Legacy accounting code and tables preserve historical compatibility. ERP screens, modes, and licensing are outside the release scope.

## Local checks

```sh
flutter pub get
flutter analyze
flutter test
```

Flutter tests use local Drift or simulated remotes for most workflows. Verify live authentication delivery, authenticated Supabase policy enforcement, native receipt and share behavior, and device layouts in staging before release. Receipt references currently point to device files. Receipt images are not synchronized.

The GitHub Actions workflow runs Flutter analysis, selected financial and sync tests, and unsigned Android and iOS release builds. Store distribution still requires platform signing.

See the [Paypr identity rollout](docs/paypr-identity.md) for package IDs, signing setup, and how to protect data in legacy development installs.

## Android release builds

Use an ignored `android/key.properties` file with `storeFile`, `storePassword`, `keyAlias`, and `keyPassword` to sign a production build. Resolve relative keystore paths from the Android project directory. Keep the signing file and private key outside version control. A checkout without that file can compile an unsigned release artifact.

```sh
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

APKs are written to `build/app/outputs/flutter-apk/`. Verify the signing certificate on the distribution artifact. Build and sign the iOS release on macOS with Xcode and the intended provisioning profile.

## Ledger schema rollout

The app adds two nullable columns when upgrading a Drift database to version 13. Back up local databases and pending outboxes before a staged rollout. Apply the corresponding additive Supabase migration on staging before testing sync, then obtain approval before applying it to production. Install the server migration before distributing clients that write structured ledger fields. Existing notes and journals are retained. Clients read the legacy payment prefix when the structured method is absent. Older client builds cannot display the structured method or classify refunds and adjustments correctly, so validate mixed-version sync and coordinate the client upgrade. Restore a pre-upgrade backup if an in-place rollback is required.

## Release gate

Run the [read-only ledger reconciliation](scripts/reconcile_ledger_postings.sql) on an approved snapshot before preparing or applying a data repair. Verify profile-mode enforcement, stale-write protection, and the role matrix on staging. The [architecture specification](docs/architecture/target-architecture.md) distinguishes the release implementation from future infrastructure work.
