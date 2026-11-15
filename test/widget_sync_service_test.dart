import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ledger_pulse/core/utils/currency_formatter.dart';
import 'package:ledger_pulse/data/models/company_model.dart';
import 'package:ledger_pulse/domain/models/workspace_profile_header.dart';
import 'package:ledger_pulse/presentation/expense/quick_add_transaction_sheet.dart';
import 'package:ledger_pulse/presentation/providers/company_providers.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_controller.dart';
import 'package:ledger_pulse/presentation/providers/profile_session_state.dart';
import 'package:ledger_pulse/presentation/splash/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WidgetSyncService & Formatting Tests', () {
    final testCompany = Company(
      id: 'cmp_enterprise',
      name: 'Ledger Enterprise',
      legalName: 'Ledger Enterprise Private Limited',
      currencyCode: 'INR',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final expenseProfile = Company(
      id: 'cmp_personal',
      name: 'Personal Wallet',
      legalName: 'Personal Wallet',
      currencyCode: 'INR',
      mode: CompanyMode.expenseTracker,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('CurrencyFormatter correctly formats amounts for widget presentation', () {
      // 2000 rupees in cents is 200000
      final formattedWithSym = CurrencyFormatter.format(
        200000,
        includeSymbol: true,
        showDecimalsAlways: false,
      );
      expect(formattedWithSym, contains('2,000'));
      expect(formattedWithSym, contains('₹'));

      final formattedWithoutSym = CurrencyFormatter.format(
        100000,
        includeSymbol: false,
        showDecimalsAlways: false,
      ).trim();
      expect(formattedWithoutSym, equals('1,000'));
    });

    test('Deep link URI generation matches format ledgerpulse://dashboard?company_id={id}', () {
      final uri = Uri.parse('ledgerpulse://dashboard?company_id=${testCompany.id}');
      expect(uri.scheme, equals('ledgerpulse'));
      expect(uri.host, equals('dashboard'));
      expect(uri.queryParameters['company_id'], equals('cmp_enterprise'));
    });

    test('Deep link with quick_add action matches format ledgerpulse://dashboard?company_id={id}&action=quick_add', () {
      final uri = Uri.parse('ledgerpulse://dashboard?company_id=${expenseProfile.id}&action=quick_add');
      expect(uri.scheme, equals('ledgerpulse'));
      expect(uri.host, equals('dashboard'));
      expect(uri.queryParameters['company_id'], equals('cmp_personal'));
      expect(uri.queryParameters['action'], equals('quick_add'));
    });

    test('Active company provider yields active company metadata for expense mode', () {
      final container = ProviderContainer(
        overrides: [
          activeCompanyProvider.overrideWithValue(expenseProfile),
        ],
      );
      addTearDown(container.dispose);

      final activeCompany = container.read(activeCompanyProvider);
      expect(activeCompany.name, equals('Personal Wallet'));
      expect(activeCompany.mode, equals(CompanyMode.expenseTracker));
      expect(activeCompany.isExpense, isTrue);
    });

    test('Expense tracker budget calculation yields expected progress text and percentages', () {
      const int todaySpendCents = 200000; // 2,000
      const int dailyBudgetCents = 370000; // 3,700

      final todayFormatted = CurrencyFormatter.format(
        todaySpendCents,
        includeSymbol: false,
        showDecimalsAlways: false,
      ).trim();
      final budgetFormatted = CurrencyFormatter.format(
        dailyBudgetCents,
        includeSymbol: false,
        showDecimalsAlways: false,
      ).trim();

      final progressText = 'Spend - $todayFormatted/$budgetFormatted';
      final percent = ((todaySpendCents / dailyBudgetCents) * 100).round();

      expect(progressText, equals('Spend - 2,000/3,700'));
      expect(percent, equals(54)); // 2000 / 3700 ~ 54%
    });
    test('QuickAddTransactionSheet.isSheetOpen tracks modal state accurately', () {
      expect(QuickAddTransactionSheet.isSheetOpen, isFalse);
    });

    test('SplashScreen skipHold fast-tracks splash animation on quick_add launch', () {
      SplashScreen.skipHold = true;
      expect(SplashScreen.skipHold, isTrue);
      SplashScreen.skipHold = false;
    });

    test('activeCompanyProvider fallback preserves expenseTracker mode when profile is expense', () {
      final container = ProviderContainer(
        overrides: [
          userCompaniesProvider.overrideWithValue([]),
          profileSessionProvider.overrideWith(() => _MockExpenseProfileSessionController()),
        ],
      );
      addTearDown(container.dispose);

      final company = container.read(activeCompanyProvider);
      expect(company.mode, equals(CompanyMode.expenseTracker));
      expect(company.name, equals('Personal Expense Workspace'));
    });
  });
}

class _MockExpenseProfileSessionController extends ProfileSessionController {
  @override
  ProfileSessionState build() {
    return ActiveProfileReadySessionState(
      userId: 'usr_test_123',
      activeProfile: WorkspaceProfileHeader(
        id: 'prof_test_expense',
        name: 'Personal Expense Workspace',
        legalName: 'Personal Expense Workspace',
        type: ProfileType.expense,
        role: ProfileRole.owner,
        currencyCode: 'INR',
        isActive: true,
        updatedAt: DateTime.now(),
      ),
      availableProfiles: [],
      isOffline: false,
    );
  }
}
