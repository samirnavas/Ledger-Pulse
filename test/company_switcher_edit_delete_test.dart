import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';
import 'package:ledger_pulse/presentation/home/edit_profile_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_pulse/data/local/database.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/data/models/user_profile_model.dart';
import 'package:ledger_pulse/presentation/home/company_switcher_sheet.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/database_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('Expense profile loads with missing or stale company details', () async {
    final now = DateTime.now();
    final header = WorkspaceProfileHeader(
      id: 'expense_profile',
      name: 'Expenses',
      legalName: 'Expenses',
      type: ProfileType.expense,
      role: ProfileRole.owner,
      updatedAt: now,
    );
    final staleCompany = Company(
      id: header.id,
      name: 'Stale company',
      legalName: 'Stale company',
      address: 'Saved address',
      createdAt: now,
      updatedAt: now,
    );
    final container = ProviderContainer(
      overrides: [
        companiesProvider.overrideWith((ref) async => [staleCompany]),
        userProfileProvider.overrideWith(
          () => _TestUserProfileNotifier(
            UserProfile(
              id: 'usr_test',
              name: 'Account holder',
              phoneNumber: '',
              email: '',
              companies: const [],
              activeCompanyId: header.id,
            ),
          ),
        ),
        profileSessionProvider.overrideWith(
          () => _TestSession(
            ActiveProfileReadySessionState(
              userId: 'usr_test',
              activeProfile: header,
              availableProfiles: [header],
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(activeCompanyProvider).mode,
      CompanyMode.expenseTracker,
    );
    await container.read(companiesProvider.future);
    final company = container.read(activeCompanyProvider);
    expect(company.mode, CompanyMode.expenseTracker);
    expect(company.name, header.name);
    expect(company.address, staleCompany.address);
  });

  test(
    'Canonical profile names win over stale companies and remain synchronized after edit',
    () async {
      final now = DateTime.now();
      final company = Company(
        id: 'canonical_profile',
        name: 'Stale company name',
        legalName: 'Stale company name',
        mode: CompanyMode.expenseTracker,
        createdAt: now,
        updatedAt: now,
      );
      await db
          .into(db.profiles)
          .insert(
            ProfilesCompanion.insert(
              id: company.id,
              name: 'Current profile name',
              profileType: const Value('expense'),
            ),
          );
      await db
          .into(db.companies)
          .insert(
            CompaniesCompanion.insert(
              id: company.id,
              profileId: Value(company.id),
              name: company.name,
              legalName: company.legalName,
              mode: const Value('expense'),
            ),
          );
      final header = WorkspaceProfileHeader(
        id: company.id,
        name: 'Current profile name',
        legalName: 'Current profile name',
        type: ProfileType.expense,
        role: ProfileRole.owner,
        updatedAt: now,
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          companiesProvider.overrideWith((ref) async => [company]),
          userProfileProvider.overrideWith(
            () => _TestUserProfileNotifier(
              UserProfile(
                id: 'usr_test',
                name: 'Account holder',
                phoneNumber: '',
                email: '',
                companies: [company],
                activeCompanyId: company.id,
              ),
            ),
          ),
          profileSessionProvider.overrideWith(
            () => _TestSession(
              ActiveProfileReadySessionState(
                userId: 'usr_test',
                activeProfile: header,
                availableProfiles: [header],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(userCompaniesProvider).single.name,
        'Current profile name',
      );
      final updated = container
          .read(activeCompanyProvider)
          .copyWith(name: 'Renamed profile', currencyCode: 'USD');
      await container
          .read(companyControllerProvider.notifier)
          .updateCompany(updated);
      expect(container.read(activeCompanyProvider).name, 'Renamed profile');
      expect(
        (container.read(profileSessionProvider)
                as ActiveProfileReadySessionState)
            .activeProfile
            .name,
        'Renamed profile',
      );
      final persisted = await (db.select(
        db.profiles,
      )..where((p) => p.id.equals(company.id))).getSingle();
      expect(persisted.name, 'Renamed profile');
      expect(persisted.currencyCode, 'USD');
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final mode in [CompanyMode.ledger, CompanyMode.expenseTracker]) {
      testWidgets(
        'Edit Profile adapts fields and fits a narrow keyboard viewport ($platform, $mode)',
        (tester) async {
          tester.view.physicalSize = const Size(320, 600);
          tester.view.devicePixelRatio = 1;
          tester.view.viewInsets = const FakeViewPadding(bottom: 180);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final company = Company(
            id: 'small_profile',
            name: 'My profile',
            legalName: 'My business',
            mode: mode,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: ThemeData(platform: platform),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.4)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showEditProfileSheet(context, company),
                      child: const Text('Edit'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
          expect(find.text('Edit Profile'), findsOneWidget);
          expect(find.byKey(const Key('profile_name_field')), findsOneWidget);
          expect(
            find.byKey(const Key('profile_currency_field')),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('profile_gstin_field')),
            mode == CompanyMode.ledger ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(const Key('profile_legal_name_field')),
            mode == CompanyMode.ledger ? findsOneWidget : findsNothing,
          );
          await tester.ensureVisible(
            find.byKey(const Key('save_profile_button')),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(const Key('save_profile_button')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  group('CompanyController Unit Tests', () {
    test('updateCompany modifies existing company in user profile', () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          userProfileProvider.overrideWith(
            () => _TestUserProfileNotifier(
              UserProfile(
                id: 'usr_test',
                name: 'Test User',
                phoneNumber: '+91 99999 88888',
                email: 'test@example.com',
                companies: [
                  Company(
                    id: 'cmp_1',
                    name: 'Original Name',
                    legalName: 'Original Legal',
                    gstin: '29ABCDE1234F1Z1',
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
                ],
                activeCompanyId: 'cmp_1',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(companyControllerProvider.notifier);
      final initialCompany = container.read(activeCompanyProvider);
      expect(initialCompany.name, equals('Original Name'));

      final updated = initialCompany.copyWith(name: 'Updated Enterprise Ltd');
      await controller.updateCompany(updated);

      final current = container.read(activeCompanyProvider);
      expect(current.name, equals('Updated Enterprise Ltd'));
      expect(
        container.read(userCompaniesProvider).first.name,
        equals('Updated Enterprise Ltd'),
      );
    });

    test(
      'deleteCompany deletes company and reassigns activeCompanyId when active is deleted',
      () async {
        final cmp1 = Company(
          id: 'cmp_1',
          name: 'Company 1',
          legalName: 'Company 1 Ltd',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final cmp2 = Company(
          id: 'cmp_2',
          name: 'Company 2',
          legalName: 'Company 2 Ltd',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            userProfileProvider.overrideWith(
              () => _TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Test User',
                  phoneNumber: '+91 99999 88888',
                  email: 'test@example.com',
                  companies: [cmp1, cmp2],
                  activeCompanyId: 'cmp_1',
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(companyControllerProvider.notifier);
        expect(container.read(userCompaniesProvider).length, equals(2));
        expect(container.read(activeCompanyProvider).id, equals('cmp_1'));

        final result = await controller.deleteCompany('cmp_1');
        expect(result, isTrue);

        final remaining = container.read(userCompaniesProvider);
        expect(remaining.length, equals(1));
        expect(remaining.first.id, equals('cmp_2'));
        expect(container.read(activeCompanyProvider).id, equals('cmp_2'));
      },
    );

    test(
      'deleteCompany returns false when trying to delete the only company',
      () async {
        final cmp1 = Company(
          id: 'cmp_single',
          name: 'Sole Company',
          legalName: 'Sole Company Ltd',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final container = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            userProfileProvider.overrideWith(
              () => _TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Test User',
                  phoneNumber: '+91 99999 88888',
                  email: 'test@example.com',
                  companies: [cmp1],
                  activeCompanyId: 'cmp_single',
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(companyControllerProvider.notifier);
        final result = await controller.deleteCompany('cmp_single');
        expect(result, isFalse);
        expect(container.read(userCompaniesProvider).length, equals(1));
      },
    );
  });

  group('CompanySwitcherSheet Widget Tests', () {
    testWidgets('Three dot menu button and tap-and-hold display options menu', (
      tester,
    ) async {
      final cmp1 = Company(
        id: 'cmp_1',
        name: 'Alpha Traders',
        legalName: 'Alpha Traders Pvt Ltd',
        gstin: '29ABCDE1234F1Z1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final cmp2 = Company(
        id: 'cmp_2',
        name: 'Beta Logistics',
        legalName: 'Beta Logistics Pvt Ltd',
        gstin: '29ABCDE1234F1Z2',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          userProfileProvider.overrideWith(
            () => _TestUserProfileNotifier(
              UserProfile(
                id: 'usr_test',
                name: 'Samir Navas',
                phoneNumber: '+91 98765 43210',
                email: 'samir@example.com',
                companies: [cmp1, cmp2],
                activeCompanyId: 'cmp_1',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: CompanySwitcherSheet(scrollController: ScrollController()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify both companies rendered
      expect(find.text('Alpha Traders'), findsOneWidget);
      expect(find.text('Beta Logistics'), findsOneWidget);

      // Verify 3-dot menu button is rendered
      final moreButtons = find.byIcon(Icons.more_vert_rounded);
      expect(moreButtons, findsNWidgets(2));

      // 1. Test clicking the 3-dot button on Beta Logistics
      await tester.tap(moreButtons.at(1));
      await tester.pumpAndSettle();

      // Verify bottom sheet menu appeared
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Delete Profile'), findsOneWidget);
      expect(find.text('Switch to this Profile'), findsOneWidget);

      // Dismiss menu
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // 2. Test tap and hold (long press) on Alpha Traders
      await tester.longPress(find.text('Alpha Traders'));
      await tester.pumpAndSettle();

      // Verify bottom sheet menu appeared from long press
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Delete Profile'), findsOneWidget);

      // Tap Edit Profile
      await tester.tap(find.text('Edit Profile'));
      await tester.pumpAndSettle();

      // Verify Edit Profile Dialog is displayed
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);

      // Change company name
      final nameField = find.widgetWithText(TextField, 'Alpha Traders');
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Alpha Global Enterprises');
      await tester.ensureVisible(find.byKey(const Key('save_profile_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save_profile_button')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 2));

      // Verify updated name in list
      expect(find.text('Alpha Global Enterprises'), findsOneWidget);
      expect(find.byKey(const Key('profile_name_field')), findsNothing);
      expect(
        container.read(userCompaniesProvider).first.name,
        'Alpha Global Enterprises',
      );
    });
  });
}

class _TestUserProfileNotifier extends UserProfileNotifier {
  final UserProfile _initial;
  _TestUserProfileNotifier(this._initial);

  @override
  UserProfile build() => _initial;

  @override
  void updateProfile(UserProfile updated) {
    state = updated;
  }
}

class _TestSession extends ProfileSessionController {
  _TestSession(this.initial);
  final ProfileSessionState initial;
  @override
  ProfileSessionState build() => initial;
}
