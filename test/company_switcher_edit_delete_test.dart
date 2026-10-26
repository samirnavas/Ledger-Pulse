import 'package:drift/native.dart';
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

  group('CompanyController Unit Tests', () {
    test('updateCompany modifies existing company in user profile', () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(
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
              )),
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
      expect(container.read(userCompaniesProvider).first.name, equals('Updated Enterprise Ltd'));
    });

    test('deleteCompany deletes company and reassigns activeCompanyId when active is deleted', () async {
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
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Test User',
                  phoneNumber: '+91 99999 88888',
                  email: 'test@example.com',
                  companies: [cmp1, cmp2],
                  activeCompanyId: 'cmp_1',
                ),
              )),
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
    });

    test('deleteCompany returns false when trying to delete the only company', () async {
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
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Test User',
                  phoneNumber: '+91 99999 88888',
                  email: 'test@example.com',
                  companies: [cmp1],
                  activeCompanyId: 'cmp_single',
                ),
              )),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(companyControllerProvider.notifier);
      final result = await controller.deleteCompany('cmp_single');
      expect(result, isFalse);
      expect(container.read(userCompaniesProvider).length, equals(1));
    });
  });

  group('CompanySwitcherSheet Widget Tests', () {
    testWidgets('Three dot menu button and tap-and-hold display options menu', (tester) async {
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
          userProfileProvider.overrideWith(() => _TestUserProfileNotifier(
                UserProfile(
                  id: 'usr_test',
                  name: 'Samir Navas',
                  phoneNumber: '+91 98765 43210',
                  email: 'samir@example.com',
                  companies: [cmp1, cmp2],
                  activeCompanyId: 'cmp_1',
                ),
              )),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: CompanySwitcherSheet(
                scrollController: ScrollController(),
              ),
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
      expect(find.text('Edit Company Details'), findsOneWidget);
      expect(find.text('Delete Company'), findsOneWidget);
      expect(find.text('Switch to this Company'), findsOneWidget);

      // Dismiss menu
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      // 2. Test tap and hold (long press) on Alpha Traders
      await tester.longPress(find.text('Alpha Traders'));
      await tester.pumpAndSettle();

      // Verify bottom sheet menu appeared from long press
      expect(find.text('Edit Company Details'), findsOneWidget);
      expect(find.text('Delete Company'), findsOneWidget);

      // Tap Edit Company Details
      await tester.tap(find.text('Edit Company Details'));
      await tester.pumpAndSettle();

      // Verify Edit Company Dialog is displayed
      expect(find.text('Edit Company'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);

      // Change company name
      final nameField = find.widgetWithText(TextField, 'Alpha Traders');
      expect(nameField, findsOneWidget);
      await tester.enterText(nameField, 'Alpha Global Enterprises');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Verify updated name in list
      expect(find.text('Alpha Global Enterprises'), findsOneWidget);
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
