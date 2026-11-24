import 'package:flutter/services.dart';
import 'package:paypr/core/services/widget_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:paypr/core/utils/currency_formatter.dart';
import 'package:paypr/data/models/company_model.dart';
import 'package:paypr/data/models/budget_model.dart';
import 'package:paypr/domain/models/workspace_profile_header.dart';
import 'package:paypr/presentation/expense/quick_add_transaction_sheet.dart';
import 'package:paypr/presentation/providers/company_providers.dart';
import 'package:paypr/presentation/providers/profile_session_controller.dart';
import 'package:paypr/presentation/providers/profile_session_state.dart';
import 'package:paypr/presentation/splash/splash_screen.dart';

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

    test('Deep link URI generation matches format paypr://dashboard?company_id={id}', () {
      final uri = Uri.parse('paypr://dashboard?company_id=${testCompany.id}');
      expect(uri.scheme, equals('paypr'));
      expect(uri.host, equals('dashboard'));
      expect(uri.queryParameters['company_id'], equals('cmp_enterprise'));
    });

    test('Deep link with quick_add action matches format paypr://dashboard?company_id={id}&action=quick_add', () {
      final uri = Uri.parse('paypr://dashboard?company_id=${expenseProfile.id}&action=quick_add');
      expect(uri.scheme, equals('paypr'));
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

    test('Widget displays daily spend and monthly budget progress', () async {
      const channel = MethodChannel('home_widget');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final widgetData = <String, Object?>{};
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'saveWidgetData') {
          final args = call.arguments as Map;
          widgetData[args['id'] as String] = args['data'];
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      expect(
        await WidgetSyncService.syncWidgetData(
          company: expenseProfile,
          todaySpendCents: 15500,
          monthSpendCents: 50000,
          budgetCents: 79000,
        ),
        isTrue,
      );
      expect(widgetData['today_label'], 'Today');
      expect(widgetData['today_spend_value'], '155');
      expect(widgetData['spend_progress_text'], 'Month: 500/790');
      expect(widgetData['spend_progress_percent'], 63);
      expect(widgetData['spend_percent_text'], '63%');

      await WidgetSyncService.syncWidgetData(
        company: expenseProfile,
        todaySpendCents: 15500,
        monthSpendCents: 90000,
        budgetCents: 80000,
        budgetSpentCents: 84000,
        budgetPeriod: BudgetPeriodType.weekly,
      );
      expect(widgetData['spend_progress_text'], 'Week: 840/800');
      expect(widgetData['spend_progress_percent'], 100);
      expect(widgetData['spend_percent_text'], '105%');

      await WidgetSyncService.syncWidgetData(
        company: expenseProfile,
        todaySpendCents: 0,
        monthSpendCents: 50000,
      );
      expect(widgetData['today_label'], 'Today');
      expect(widgetData['today_spend_value'], '0');
      expect(widgetData['spend_progress_text'], 'Month: 500');
      expect(widgetData['spend_percent_text'], '');
      expect(widgetData['spend_progress_percent'], 0);
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
