# Paypr rebranding report

This records Phase 1. The [Phase 2 identity report](paypr-identity.md) records the subsequent package and bundle changes.

## A. Changes completed

- Flutter now uses Paypr for the app title, welcome and setup screens, settings, drawer footers, and report and share branding. Expense Tracker and Business Ledger remain the workspace types. The supplied `Final.svg` was rendered to a transparent PNG at its original 340 × 453 viewport. A dark surface keeps the white and green mark legible in both themes.
- The supplied 252 × 336 Lottie composition plays inside the existing Flutter splash on the existing startup timeline. Deep links and reduced-motion settings use the static mark. The authentication gate also uses the static mark while it loads workspaces.
- Android uses the supplied IconKitchen export at all five launcher densities, with adaptive foreground and background layers. The themed icon uses an alpha mask of the supplied foreground, including the green accent's silhouette. The 108 dp adaptive canvas keeps the mark inside the central safe zone. The system splash uses the adaptive icon on Android 12+ and a centered Paypr mark on earlier versions. The installed widget keeps its component name and displays Paypr in the picker.
- iOS uses the supplied app icon at every size declared by the Runner catalog, including the opaque 1024 × 1024 marketing icon. Native launch uses a centered Paypr mark and a system appearance background. The WidgetKit source and permission prompts use Paypr. The supplied icon is the default for every iOS appearance.
- Web manifest and browser metadata, Windows product and window metadata, Linux window title, macOS display and menu metadata, and the local API description use Paypr. Web, Windows, and macOS use the new icon.
- Removed the superseded Flutter icon and the unused iOS `Icon-App-*` placeholders after checking the catalog and references. The existing Material 3 and Cupertino components still own layout, navigation, and theme behavior.

## B. Files modified

- Flutter metadata and shared UI. `pubspec.yaml`, `lib/core/constants/{mode_strings,strings}.dart`, `lib/core/widgets/paypr_logo.dart`.
- Flutter screens. `lib/presentation/auth/{app_root_gate,first_use_setup_screen,phone_input_screen}.dart`, `lib/presentation/expense/widgets/expense_sidebar_drawer.dart`, `lib/presentation/home/{create_company_flow,dashboard_sidebar_drawer}.dart`, `lib/presentation/profile/profile_screen.dart`, `lib/presentation/settings/{about_screen,settings_screen}.dart`, `lib/presentation/splash/splash_screen.dart`.
- Flutter report and copy changes. `lib/data/api/api_ledger_repository.dart`, `lib/data/local/connection/connection.dart`, `lib/data/models/gst_models.dart`, `lib/data/reporting/report_export_service.dart`, `lib/data/services/gst_validation_service.dart`, `lib/presentation/reports/{pdf_export_modal,statement_preview_screen}.dart`, `lib/presentation/reports/widgets/statement_pdf_generator.dart`. The built-in GST sample uses a neutral example business name.
- Android. `android/app/src/main/AndroidManifest.xml`, `android/app/src/main/kotlin/com/ledgerpulse/ledger_pulse/WidgetEntry.kt`, `res/values/strings.xml`, `res/values*/colors.xml`, `res/values*/paypr_launch_*.xml`, `res/drawable*/launch_background.xml`, `res/drawable-xxhdpi/paypr_launch_mark.png`, and `res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher*.png`, all under `android/app/src/main/`.
- iOS. `ios/Runner/Info.plist`, `ios/Runner/Base.lproj/LaunchScreen.storyboard`, `ios/Runner/Assets.xcassets/{AppIcon.appiconset,LaunchImage.imageset}` PNGs, `ios/LedgerPulseWidget/{Info.plist,LedgerPulseWidgetView.swift}`.
- Flutter assets. Added `assets/icons/paypr_logo.png` and `assets/animations/paypr_splash.json`, which embeds the image from the supplied animation. Removed `assets/icons/app_icon.png`.
- Web and desktop. `web/{index.html,manifest.json,apple-touch-icon.png,favicon.png,favicon.ico}`, `web/icons/*.png`, `linux/runner/my_application.cc`, `macos/Runner/{Info.plist,Base.lproj/MainMenu.xib,Assets.xcassets/AppIcon.appiconset/*.png}`, `windows/runner/{main.cpp,Runner.rc,resources/app_icon.ico}`.
- API, documentation, and tests. `server/{package.json,server.js}`, `README.md`, `docs/expense_ui_qa.md`, this report, `windows/runner/{cheque_printing_readme,reports_readme}.md`, `test/{expense_reports_export_test,gst_validation_service_test,widget_entry_service_test,widget_test}.dart`.

## C. Identity and compatibility

- Android application ID and Kotlin namespace before and after are `com.ledgerpulse.ledger_pulse`. Retaining the application ID lets an APK signed with the existing key update the installed app.
- iOS Runner bundle identifier before and after is `com.ledger.pulse`. RunnerTests remains `com.ledger.pulse.RunnerTests`. The app group is `group.com.ledgerpulse.app`.
- Flutter package name before and after is `ledger_pulse`.
- Drift native database before and after is `ledger_pulse_<sanitizedUid>.sqlite`, including `ledger_pulse_usr_default.sqlite` for the guest scope. Legacy lookup and development namespace filenames, web storage names, and the `LEDGERPULSE_DEV_DB_NAMESPACE` flag are preserved.
- The rebrand required zero migrations. Drift schema version, local preferences, secure storage and session handling, Supabase project identity, remote schemas, RPCs, buckets, migrations, and sync metadata were preserved.

## D. Retained old-brand references

- **Flutter and tooling identity.** `name: ledger_pulse`, `package:ledger_pulse/…` imports, and the `LedgerPulseApp` implementation and test references still refer to the existing package. `ledger_pulse.iml`, generated package configuration and build metadata reflect that identity. Android namespaces and native class paths, Linux and Windows targets and binary names, macOS `PRODUCT_NAME` and internal bundle and test names, and the local `ledger-pulse-server` npm package name remain internal identifiers. The Android application ID and iOS signing identifiers also remain in associated native and build configuration.
- **Widgets and links.** `LedgerPulseWidgetProvider`, `LedgerPulseGlanceReceiver`, `LedgerPulseGlanceWidget`, `LedgerPulseWidget` and companion Kotlin and Swift symbols, the `ios/LedgerPulseWidget` source directory, `widget_ledger_pulse_*` and `ledger_pulse_widget_*` resources, and native log tags are retained. Existing placements, WidgetKit kind, app group, `ledger_pulse/widget_entry`, `com.ledgerpulse.ledger_pulse/app_info`, URL names and schemes `ledgerpulse`, `ledgerpulse-widget`, and `com.ledgerpulse.ledgerpulse` still use the existing protocol. Associated tests cover the original payloads and URLs.
- **Storage, sync, and deterministic IDs.** The local database names in C, Supabase `ledgerpulse_*` RPCs and `ledgerpulse_internal` schema, storage bucket keys `ledgerpulse_storage` and `ledgerpulse-private`, `ledgerpulse-fresh-start` project, migration and contract-test filenames, and `ledgerpulse:` prefixes used to derive recurring occurrence, first-use, default-wallet, and default-category IDs were preserved. Changing them could leave existing data unreachable or generate duplicates.
- **Payment, licensing, and ownership.** The existing UPI defaults in `gst_models.dart` and `payment_gateway_service.dart`, license verification salt, and desktop copyright holder string are retained. They identify payment routes, existing license contracts, or the recorded owner. Mock authentication emails and test company details are fixture values. Stored business names, old receipts, and previously exported files retain their original content.
- **Historical material.** The original SRS and its text copy, earlier architecture reports under `docs/architecture/`, Drift snapshots, SQL migration history, one-off repair tool, and earlier screenshots and build outputs record prior state or support recovery. The application rebuild generates new release output. The widget extension directory is present as source, but the checked-in Xcode project has no WidgetKit extension target to build.

To enumerate exact tracked file and line matches, run the following from the repository root. These matches include imports, fixtures, and compatibility contracts.

```powershell
git grep -inE 'ledger[ _.\-]?pulse|ludger[ _-]?pulse|expense[ _-]?pulse|LPWeb' -- ':!docs/paypr-rebrand.md'
git ls-files | Select-String 'ledger[ _.\-]?pulse|ludger[ _-]?pulse|expense[ _-]?pulse|LPWeb'
```

## E. External release actions

- **Google Play.** Update the existing app's localized name, description, store icon, and screenshots under Grow users → Store presence → Main store listing. Use `android/play_store_512.png` from the supplied IconKitchen export. Publish on the existing listing with its current signing setup and a version code greater than the latest published one. [Play Console store listing help](https://support.google.com/googleplay/android-developer/answer/9859152)
- **App Store Connect.** In the existing app record, edit General → App Information and set the localized name to Paypr. Update the version metadata and screenshots, then submit a signed build from the same bundle identifier with an eligible build number. The 1024 px icon is in the Runner asset catalog. [App Store Connect app information](https://developer.apple.com/help/app-store-connect/create-an-app-record/view-and-edit-app-information/)
- **Supabase Auth.** In the existing project, review Authentication → Providers → Phone → SMS Message and change old brand text to Paypr while keeping `{{ .Code }}`. Review Authentication → Email Templates for any enabled verification, recovery, or account emails that mention the old name. Update the subjects, body copy, and configured sender display name as applicable. Preserve template variables, redirect settings, SMTP details, and SMS provider credentials. No hosted settings were edited. [Phone sign-in templates](https://supabase.com/docs/guides/auth/phone-login) · [Email templates](https://supabase.com/docs/guides/auth/auth-email-templates)
- Update the wording on the existing store-linked privacy and support pages if they show the prior name. Retain the current URLs. The repository has no Firebase integration or Google OAuth client to update. The app has no notification-channel or push sender implementation. The existing notification permission declaration was preserved.

## F. Verification

- `flutter pub get` passed without changing the dependency lockfile. The Dart formatter ran on the edited files. Unrelated formatting changes were excluded from the diff. `git diff --check` passed.
- `flutter analyze --no-pub --no-fatal-infos` exited successfully with 17 pre-existing informational style lints and zero errors or warnings. The default analyzer run treated informational lints as fatal.
- The serial Flutter regression run passed 151 tests covering startup and onboarding, authentication and session restoration, home and navigation, reports, database selection, offline sync, and widget data and entry. The three startup tests also passed a focused rerun that decoded the bundled Lottie composition and its embedded image. Startup assertions reflect the current welcome and first-use routes. A widget test now expects the workspace wording already returned by the service.
- An Android x86-64 debug APK built and installed in place on the Android 17 emulator. The launcher showed Paypr with the themed icon, and the native splash showed the Paypr mark in light and dark mode. The installation timestamp, all five existing SQLite filenames, the active workspace, and the existing expense matched the pre-update state. The `ledgerpulse://dashboard` link resolved to the existing app and the placed widget remained visible.
- An Android ARM64 release APK built successfully. Production signing and a Play-delivered upgrade were outside this local check because the production signing properties were unavailable.
- Static checks passed for all Android icon resources, all 21 referenced opaque RGB iOS icons, the native XML files, and the web icon paths. This Windows environment has no Xcode. iOS build, install, WidgetKit, and system appearance behavior remain unverified. Samsung and Vivo launcher behavior, desktop runtime, real hosted Auth delivery, and a signed production update were outside the verified runs.
