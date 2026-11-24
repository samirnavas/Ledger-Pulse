# Paypr internal identity

## Identifiers

- Flutter package changed from `ledger_pulse` to `paypr`. The Flutter application class is `PayprApp`.
- Android application ID and Kotlin namespace changed from `com.ledgerpulse.ledger_pulse` to `com.paypr.app`. The signing configuration and predictive-back flags are unchanged.
- iOS Runner changed from `com.ledger.pulse` to `com.paypr.app` in Debug, Profile, and Release. RunnerTests changed to `com.paypr.app.RunnerTests`. Codemagic requests signing files for the new Runner App ID.
- The dashboard link is `paypr://dashboard`. Widget payloads, action links, and native registrations use the new scheme. Android widget component names and the native method channels moved to the new identity. The iOS app group declared in the entitlement files is `group.com.paypr.app`.
- Supabase still uses `awzxwsmfyrbnnuqkxuxu` and its existing API URL and client credentials. The Supabase project lookup returned the display name Paypr and status `ACTIVE_HEALTHY` for that same reference. No hosted settings were edited from this checkout.

## Availability and external configuration

- No `com.paypr.app` collision was present in the checkout or on the connected emulator before install. A public exact-identifier search yielded no confirmed match. The direct public Play listing could not be verified from this environment. These checks do not reserve the identifier or detect unpublished reservations.
- Confirm `com.paypr.app` in Google Play Console when setting up the first release. Use the existing production signing configuration and the appropriate upload key once available.
- In Apple Developer Certificates, Identifiers & Profiles, verify availability and register `com.paypr.app` as an explicit App ID. Create provisioning profiles for that ID and use the matching team in the release workflow. The checked-in Xcode configurations currently disable signing. Prepare a signed Archive in the release environment. If shipping the widget, register `group.com.paypr.app` and assign it to the app and extension identifiers. The checked-in project does not contain a WidgetKit target or reference the entitlement files from its build settings. The Phase 2 source changes do not add a new extension target. [Apple App ID registration](https://developer.apple.com/help/account/identifiers/register-an-app-id/)
- The Supabase display name is already Paypr. Review Authentication → URL Configuration and replace legacy mobile callbacks only where an enabled flow actually uses them. `paypr://dashboard` is a widget and navigation link. The checked-in phone OTP and password sign-in flows do not supply a `redirectTo` URL. Keep the hosted site URL and any working callbacks needed by the legacy development app while it is still in use. Review enabled SMS and email templates for old display text without changing their code or token variables. [Supabase redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls) · [Supabase email templates](https://supabase.com/docs/guides/auth/auth-email-templates)
- The checkout has no Google OAuth client, Firebase configuration, push notification sender or registration, custom Keychain access groups, or verified HTTPS App Links/Universal Links. No service identifiers were created for those features. GitHub Actions invokes Flutter with project-relative paths and required no identity change.

## Local data and rollout

- Android and iOS treat the new IDs as separate installations. The old sandbox, local files, and app preferences remain under the old ID. The new app uses the same Drift schema version 15 and the same `ledger_pulse_<sanitizedUid>.sqlite` naming convention inside its own sandbox. No local or remote schema migrations are required.
- The old development build can stay installed while Paypr is verified. Before retiring it, open each legacy workspace, reconnect and complete sync, and compare the records in a fresh Paypr sign-in. Guest data, transactions and edits still in a local outbox, local settings, cached session data, and local attachments do not automatically follow the bundle or package ID. Widgets must be placed again for the new installation.
- If sync cannot be confirmed, retain the old installation and back up its application documents before uninstalling it. For an Android debug build, stop the old app first and archive its `app_flutter` directory using `adb exec-out run-as com.ledgerpulse.ledger_pulse tar -cf - app_flutter`, redirecting the binary output with a binary-safe shell such as `cmd.exe` to a private file outside the repository. Include any SQLite `-wal` and `-shm` files present. For an iOS development build, use Xcode Devices and Simulators to download the old app's container. Keep backups private and verify they open before relying on them. Sign in again with the same Supabase account on Paypr. Do not import the old credentials or copy a legacy database over a database already in use.

## Retained legacy references

- `ledger_pulse_*.sqlite`, the web SQLite namespace, `LEDGERPULSE_DEV_DB_NAMESPACE`, and the recovery lookup names identify existing files and tools. `ledgerpulse:` strings used in deterministic IDs still tie recurring occurrences, initial wallets and categories, and onboarding operations to existing records.
- Supabase `ledgerpulse_*` RPC names, private schema and bucket names, local Supabase stack identity, and historical SQL are server-side contracts. The project reference and all database objects remain in place.
- Existing UPI addresses, license validation constants, and copyright ownership strings are integration and legal data. Test company and mock contact values are fixtures. Desktop executable and bundle identities were left in place to preserve their separate installation and persistence contracts.
- The previous rebrand report, original SRS, architecture audits, and repair tooling record the prior identity and recovery procedures. The original Android package and iOS ID also appear in this report for rollout and backup use.

## Modified files

- `pubspec.yaml`, application and test Dart package URIs under `lib/`, `test/`, and `tool/`, `lib/main.dart`, `lib/core/services/widget_entry_service.dart`, `lib/core/services/widget_sync_service.dart`, and `lib/presentation/settings/about_screen.dart`. Method-channel, startup class, and deep-link assertions changed in `test/expense_shell_test.dart`, `test/expense_reports_export_test.dart`, `test/widget_sync_service_test.dart`, and `test/widget_test.dart`.
- `android/app/build.gradle.kts`, `android/app/src/main/AndroidManifest.xml`, and `android/app/src/main/kotlin/com/paypr/app/{MainActivity,PayprGlanceReceiver,PayprGlanceWidget,PayprWidgetProvider,WidgetEntry}.kt`, moved from the old Kotlin package directory. The widget resources moved to `android/app/src/main/res/layout/widget_paypr_{small,medium}.xml` and `android/app/src/main/res/xml/paypr_widget_{info,medium_info}.xml`.
- `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner/{AppDelegate.swift,Info.plist,Runner.entitlements}`, `ios/PayprWidget/{Info.plist,PayprWidgetBundle.swift,PayprWidgetView.swift,PayprWidgetExtension.entitlements}` moved from `ios/LedgerPulseWidget/`, and `codemagic.yaml`.
- `server/package.json`, `README.md`, `docs/paypr-rebrand.md`, and this report. `flutter pub get` refreshed ignored package metadata. Visual assets from Phase 1 remain intact.

<details>
<summary>All Dart files with updated package paths</summary>

```text
test/accounts_budgets_recurring_ui6_test.dart
test/adaptive_primitives_test.dart
test/api_ledger_repository_test.dart
test/app_pull_to_refresh_test.dart
test/architecture/database_architecture_test.dart
test/audit_trail_test.dart
test/auth/auth_flow_and_identity_test.dart
test/auth/first_use_setup_test.dart
test/auth/profile_lifecycle_test.dart
test/auth/session_initialization_test.dart
test/auto_sync_on_open_test.dart
test/benchmark_performance_test.dart
test/budgets_and_recurring_test.dart
test/company_and_profile_sync_test.dart
test/company_creation_and_mode_seeding_test.dart
test/company_handling_trust_test.dart
test/company_mode_and_modules_test.dart
test/company_model_test.dart
test/company_switcher_edit_delete_test.dart
test/complete_business_cycle_test.dart
test/contact_call_and_statement_export_test.dart
test/contacts_and_receipt_picker_test.dart
test/cts2010_cheque_printing_test.dart
test/currency_formatter_test.dart
test/custom_sql_report_engine_test.dart
test/data_import_service_test.dart
test/database/reactive_database_selection_test.dart
test/database_migration_test.dart
test/default_color_theme_test.dart
test/device_auth_persistence_test.dart
test/document_workflow_test.dart
test/double_entry_accounting_test.dart
test/drift_ledger_repository_test.dart
test/dynamic_invoice_templates_test.dart
test/ecommerce_sync_test.dart
test/einvoice_ewaybill_compliance_test.dart
test/expense/expense_domain_test.dart
test/expense_posting_test.dart
test/expense_reports_and_csv_import_ui7_test.dart
test/expense_reports_export_test.dart
test/expense_repository_test.dart
test/expense_shell_test.dart
test/expense_tracker_screens_test.dart
test/expense_transactions_tab_test.dart
test/financial_statement_engine_test.dart
test/gst_tax_engine_test.dart
test/gst_validation_service_test.dart
test/gstr_json_engine_test.dart
test/helpers/golden_helper.dart
test/helpers/legacy_module_test_company.dart
test/home_shell_test.dart
test/inventory_reporting_test.dart
test/inventory_stock_ledger_test.dart
test/invoice_drafting_payment_test.dart
test/ledger_entry_edit_and_delete_test.dart
test/ledger_release_reports_test.dart
test/local_ledger_repository_test.dart
test/manufacturing_bom_test.dart
test/mock_ledger_repository_test.dart
test/module_catalog_and_providers_test.dart
test/module_gating_and_guards_test.dart
test/multi_company_test.dart
test/order_to_invoice_conversion_test.dart
test/party_edit_and_delete_test.dart
test/payment_gateway_test.dart
test/payroll_engine_test.dart
test/platform_and_theme_test.dart
test/predictive_back_and_draggable_modals_test.dart
test/predictive_back_navigation_test.dart
test/previews/profile_onboarding_preview_test.dart
test/profile/end_to_end_verification_test.dart
test/profile/profile_creation_and_supabase_persistence_test.dart
test/profile/profile_onboarding_and_routing_test.dart
test/profile/profile_type_serialization_and_parsing_test.dart
test/profile/workspace_lifecycle_and_immutability_test.dart
test/quick_add_transaction_sheet_ui5_test.dart
test/rbac_access_control_test.dart
test/receivables_payables_test.dart
test/search_sort_and_running_balance_test.dart
test/splitting_profile_fab_test.dart
test/subscription_licensing_test.dart
test/subscription_persistence_test.dart
test/supabase_outbox_sync_test.dart
test/sync/delete_not_resurrected_test.dart
test/sync/misplaced_ledger_repair_test.dart
test/sync/outbox_valid_json_test.dart
test/sync/phase1_unit_tests.dart
test/sync/phase2_unit_tests.dart
test/sync/phase3_unit_tests.dart
test/sync/phase4_unit_tests.dart
test/sync/phase6_unit_tests.dart
test/sync/profile_bootstrap_recovery_test.dart
test/sync/profile_sync_regression_test.dart
test/sync/shared_sync_contract_test.dart
test/sync/support/fake_remote_gateway.dart
test/sync/support/strict_fake_remote.dart
test/sync/sync_engine_hardening_test.dart
test/sync/time_roundtrip_test.dart
test/sync/timestamp_regression_test.dart
test/sync/wallet_sync_test.dart
test/sync/workspace_command_sync_test.dart
test/sync_modes_and_vouchers_test.dart
test/theme_preference_test.dart
test/ui/account_profile_ui_test.dart
test/upgrade_to_ledger_test.dart
test/voucher_posting_engine_test.dart
test/widget_entry_service_test.dart
test/widget_sync_service_test.dart
test/widget_test.dart
```

</details>

## Verification and remaining release gates

- `flutter pub get` passed and generated a package configuration rooted at `paypr`. Dart formatting ran on the edited integration files. The Drift `build_runner` generation completed with no tracked generated output or schema changes. `git diff --check` passed.
- `flutter analyze --no-pub --no-fatal-infos` passed with 17 existing informational lints and zero warnings or errors. All 153 selected tests passed, covering startup, authentication, workspace state, database isolation and architecture, expense navigation and reports, offline sync, and widget data and entry.
- The Android x86-64 debug build installed as a separate `com.paypr.app` app. Both packages remained installed and all five original SQLite filenames remained present. Android resolved `paypr://dashboard` to Paypr and `ledgerpulse://dashboard` to the legacy installation.
- After the user signed in on the new installation, its workspace picker showed the existing cloud workspace. Selecting it loaded the same ₹40 expense previously visible in the legacy app. The existing hosted project also reported healthy under the Paypr name. This verifies the tested account and transaction. The sync or backup status of other legacy local-only data remains unconfirmed.
- The Android ARM64 release APK built successfully. It is unsigned because this checkout has no production signing properties. Store identifier availability, release signing, and a signed iOS archive and device check remain before release. iOS XML and target settings passed static checks. Xcode is unavailable on this Windows host.

