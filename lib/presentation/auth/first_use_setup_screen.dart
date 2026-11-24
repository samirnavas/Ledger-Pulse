import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../data/models/account_model.dart';
import '../../data/models/expense/expense_wallet_model.dart';
import '../../domain/models/workspace_profile_header.dart';
import '../expense/quick_add_transaction_sheet.dart';
import '../providers/auth_providers.dart';
import '../providers/company_providers.dart';
import '../providers/database_providers.dart';
import '../providers/expense_providers.dart';
import '../providers/profile_provider.dart';
import '../providers/profile_session_controller.dart';
import 'phone_input_screen.dart';
import 'profile_onboarding_screen.dart';

String _pendingKey(String userId) => 'first_use_workspace_$userId';

final pendingFirstUseWorkspaceProvider = Provider.family<String?, String>((
  ref,
  userId,
) {
  return ref.watch(sharedPreferencesProvider)?.getString(_pendingKey(userId));
});

String _setupRecordId(String workspaceId, String record) => const Uuid().v5(
  Namespace.url.value,
  'ledgerpulse:$workspaceId:first-use:$record',
);

final _firstExpenseSavedProvider = StreamProvider.autoDispose
    .family<bool, String>((ref, workspaceId) {
      final db = ref.watch(appDatabaseProvider);
      final id = _setupRecordId(workspaceId, 'expense');
      final query = db.select(db.expenseTransactions)
        ..where((row) => row.id.equals(id));
      return query.watchSingleOrNull().map(
        (row) => row?.profileId == workspaceId,
      );
    });

const _currencies = {
  'INR': 'Indian rupee',
  'USD': 'US dollar',
  'EUR': 'Euro',
  'GBP': 'British pound',
  'JPY': 'Japanese yen',
  'AED': 'UAE dirham',
  'CAD': 'Canadian dollar',
  'AUD': 'Australian dollar',
  'SGD': 'Singapore dollar',
};

String suggestedSetupCurrency(Locale locale) => switch (locale.countryCode) {
  'US' => 'USD',
  'GB' => 'GBP',
  'JP' => 'JPY',
  'AE' => 'AED',
  'CA' => 'CAD',
  'AU' => 'AUD',
  'SG' => 'SGD',
  'AT' ||
  'BE' ||
  'CY' ||
  'DE' ||
  'EE' ||
  'ES' ||
  'FI' ||
  'FR' ||
  'GR' ||
  'HR' ||
  'IE' ||
  'IT' ||
  'LT' ||
  'LU' ||
  'LV' ||
  'MT' ||
  'NL' ||
  'PT' ||
  'SI' ||
  'SK' ||
  'BG' => 'EUR',
  _ => 'INR',
};

const _walletTypes = {
  ExpenseWalletType.cash: 'Cash',
  ExpenseWalletType.bank: 'Bank account',
  ExpenseWalletType.digitalWallet: 'Digital wallet',
};

class LedgerPulseWelcomeScreen extends StatelessWidget {
  const LedgerPulseWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void authenticate(AuthMode mode) => Navigator.of(context).push(
      createAdaptivePageRoute<void>(
        builder: (_) => PhoneInputScreen(initialMode: mode),
      ),
    );
    return _SetupScaffold(
      title: 'LedgerPulse',
      body: _SetupFields(
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/icons/app_icon.png',
                width: 64,
                height: 64,
                excludeFromSemantics: true,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SetupHeading(
            title: 'Make sense of your money.',
            description:
                'Track expenses, see what’s in your wallets, and understand where your money goes.',
            icon: null,
          ),
          const SizedBox(height: 8),
          AdaptiveButton(
            isFullWidth: true,
            onPressed: () => authenticate(AuthMode.signUp),
            child: const Text('Get started'),
          ),
          AdaptiveButton(
            type: AdaptiveButtonType.text,
            onPressed: () => authenticate(AuthMode.login),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}

class FirstUseSetupScreen extends ConsumerStatefulWidget {
  const FirstUseSetupScreen({super.key, required this.userId, this.workspace});

  final String userId;
  final WorkspaceProfileHeader? workspace;

  @override
  ConsumerState<FirstUseSetupScreen> createState() =>
      _FirstUseSetupScreenState();
}

class _FirstUseSetupScreenState extends ConsumerState<FirstUseSetupScreen> {
  final _workspaceName = TextEditingController(text: 'Personal Expenses');
  final _walletName = TextEditingController(text: 'Cash');
  final _openingBalance = TextEditingController();
  late String _currency = suggestedSetupCurrency(
    WidgetsBinding.instance.platformDispatcher.locale,
  );
  ExpenseWalletType _walletType = ExpenseWalletType.cash;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _workspaceName.dispose();
    _walletName.dispose();
    _openingBalance.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) setState(() => _error = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _createWorkspace() {
    final name = _workspaceName.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a workspace name.');
      return;
    }
    _run(() async {
      final userId = widget.userId;
      final prefs = ref.read(sharedPreferencesProvider)!;
      final repo = ref.read(profileRepositoryProvider);
      final session = ref.read(profileSessionProvider.notifier);
      final userProfile = ref.read(userProfileProvider.notifier);
      final existing = await repo.getAccessibleProfiles(userId);
      if (!mounted || ref.read(activeUserIdProvider) != userId) return;
      if (existing.isEmpty) {
        final workspaceId =
            prefs.getString(_pendingKey(userId)) ?? const Uuid().v4();
        if (!await prefs.setString(_pendingKey(userId), workspaceId)) {
          throw StateError('Setup could not be saved');
        }
        if (!mounted || ref.read(activeUserIdProvider) != userId) return;
        ref.invalidate(pendingFirstUseWorkspaceProvider(userId));
        await ensureWorkspaceAccountIdentity(ref, userId, name);
        if (!mounted || ref.read(activeUserIdProvider) != userId) return;
        await repo.createProfile(
          accountId: userId,
          name: name,
          currencyCode: _currency,
          type: ProfileType.expense,
          seedDefaultWallet: false,
          customId: workspaceId,
        );
        await prefs.setString(
          activeWorkspacePreferenceKey(userId),
          workspaceId,
        );
        await prefs.setBool(
          dashboardSetupPreferenceKey(userId, workspaceId),
          false,
        );
      }
      if (!mounted || ref.read(activeUserIdProvider) != userId) return;
      await userProfile.reloadFromDatabase();
      if (mounted) await session.loadProfilesForUser(userId);
    }, 'Could not open your workspace. Try again.');
  }

  void _createWallet(WorkspaceProfileHeader workspace) {
    final name = _walletName.text.trim();
    final opening = _openingBalance.text.trim();
    if (name.isEmpty ||
        (opening.isNotEmpty &&
            !RegExp(
              r'^(\d{1,9}([.,]\d{0,2})?|[.,]\d{1,2})$',
            ).hasMatch(opening))) {
      setState(
        () => _error = name.isEmpty
            ? 'Enter a wallet name.'
            : 'Enter a balance of zero or more with up to two decimal places.',
      );
      return;
    }
    _run(() async {
      final repo = ref.read(expenseRepositoryProvider);
      if (repo.currentCompanyId != workspace.id) return;
      await repo.createWallet(
        name: name,
        type: AccountType.asset,
        walletType: _walletType.toDbValue(),
        openingBalanceInCents: CurrencyFormatter.parseToCents(
          opening.replaceAll(',', '.'),
        ),
        customId: _setupRecordId(workspace.id, 'wallet'),
      );
      if (mounted) ref.invalidate(walletsProvider);
    }, 'Could not save your wallet. Try again.');
  }

  void _finish() {
    _run(() async {
      final userId = widget.userId;
      final prefs = ref.read(sharedPreferencesProvider)!;
      if (!await prefs.remove(_pendingKey(userId))) {
        throw StateError('Setup could not be closed');
      }
      if (mounted) ref.invalidate(pendingFirstUseWorkspaceProvider(userId));
    }, 'Could not finish setup. Try again.');
  }

  @override
  Widget build(BuildContext context) {
    final workspace = widget.workspace;
    if (workspace == null) {
      return _SetupScaffold(
        title: 'Set up LedgerPulse',
        body: _SetupFields(
          children: [
            const _SetupHeading(
              step: 1,
              title: 'Make it yours.',
              description: 'Create a workspace for your personal finances.',
              icon: (
                Symbols.account_balance_wallet,
                CupertinoIcons.money_dollar_circle,
              ),
            ),
            _SetupTextField(
              label: 'Workspace name',
              controller: _workspaceName,
              enabled: !_busy,
            ),
            _SetupChoice<String>(
              label: 'Currency',
              value: _currency,
              choices: {
                for (final entry in _currencies.entries)
                  entry.key: '${entry.key} · ${entry.value}',
              },
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _currency = value),
            ),
            _inlineError(),
            AdaptiveButton(
              isFullWidth: true,
              isLoading: _busy,
              onPressed: _createWorkspace,
              child: const Text('Create workspace'),
            ),
          ],
        ),
      );
    }
    if (ref.watch(activeCompanyProvider.select((company) => company.id)) !=
        workspace.id) {
      return const _SetupScaffold(
        title: 'Set up LedgerPulse',
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    final wallets = ref.watch(walletsProvider);
    return _SetupScaffold(
      title: 'Set up LedgerPulse',
      body: wallets.when(
        loading: () =>
            const Center(child: CircularProgressIndicator.adaptive()),
        error: (_, _) => _loadError(() => ref.invalidate(walletsProvider)),
        data: (items) => items.isEmpty
            ? _walletForm(workspace)
            : _expenseForm(workspace, items),
      ),
    );
  }

  Widget _walletForm(WorkspaceProfileHeader workspace) => _SetupFields(
    children: [
      const _SetupHeading(
        step: 2,
        title: 'Your first wallet.',
        description: 'Where do you usually keep your money?',
        icon: (Symbols.account_balance_wallet, CupertinoIcons.creditcard),
      ),
      _SetupChoice<ExpenseWalletType>(
        label: 'Wallet type',
        value: _walletType,
        choices: _walletTypes,
        onChanged: _busy
            ? null
            : (value) => setState(() {
                if (_walletName.text.trim().isEmpty ||
                    _walletName.text == _walletTypes[_walletType]) {
                  _walletName.text = _walletTypes[value]!;
                }
                _walletType = value;
              }),
      ),
      _SetupTextField(
        label: 'Wallet name',
        controller: _walletName,
        enabled: !_busy,
      ),
      _SetupTextField(
        label: 'Opening balance (${workspace.currencyCode})',
        controller: _openingBalance,
        enabled: !_busy,
        decimal: true,
        hint: '0',
      ),
      Text(
        'Use money you already have. Opening balances are separate from income.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      Text(
        'Your workspace is saved on this device. Any pending changes sync when you’re online.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      _inlineError(),
      AdaptiveButton(
        isFullWidth: true,
        isLoading: _busy,
        onPressed: () => _createWallet(workspace),
        child: const Text('Create wallet'),
      ),
      AdaptiveButton(
        type: AdaptiveButtonType.text,
        onPressed: _busy ? null : _finish,
        child: const Text('Skip for now'),
      ),
    ],
  );

  Widget _expenseForm(
    WorkspaceProfileHeader workspace,
    List<AccountModel> wallets,
  ) {
    final saved = ref.watch(_firstExpenseSavedProvider(workspace.id));
    return saved.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (_, _) => _loadError(
        () => ref.invalidate(_firstExpenseSavedProvider(workspace.id)),
      ),
      data: (alreadySaved) {
        if (alreadySaved) {
          if (!_busy && _error == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _finish();
            });
          }
          return _error == null
              ? const Center(child: CircularProgressIndicator.adaptive())
              : _loadError(_finish);
        }
        if (_error != null) return _loadError(_finish);
        final wallet =
            wallets
                .where(
                  (item) => item.id == _setupRecordId(workspace.id, 'wallet'),
                )
                .firstOrNull ??
            wallets.first;
        return QuickAddTransactionSheet.firstExpense(
          key: ValueKey(wallet.id),
          walletId: wallet.id,
          transactionId: _setupRecordId(workspace.id, 'expense'),
          header: const _SetupHeading(
            step: 3,
            title: 'Start tracking.',
            description: 'Add an expense you’ve recently made.',
            icon: (Symbols.receipt_long, CupertinoIcons.doc_text),
          ),
          onComplete: _finish,
        );
      },
    );
  }

  Widget _inlineError() => _error == null
      ? const SizedBox.shrink()
      : Semantics(
          liveRegion: true,
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        );

  Widget _loadError(VoidCallback retry) => _SetupFields(
    children: [
      Text(
        _error ?? 'Could not load setup data.',
        semanticsLabel: _error ?? 'Could not load setup data.',
      ),
      AdaptiveButton(onPressed: retry, child: const Text('Try again')),
    ],
  );
}

class _SetupScaffold extends StatelessWidget {
  const _SetupScaffold({required this.title, required this.body});
  final String title;
  final Widget body;

  @override
  Widget build(BuildContext context) => AdaptiveScaffold(
    title: title,
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: body,
  );
}

class _SetupFields extends StatelessWidget {
  const _SetupFields({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: children,
            ),
          ),
        ),
      ],
    ),
  );
}

class _SetupHeading extends StatelessWidget {
  const _SetupHeading({
    this.step,
    required this.title,
    required this.description,
    required this.icon,
  });
  final int? step;
  final String title;
  final String description;
  final (IconData, IconData)? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isIos = AdaptiveThemeHelper.isIos(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (step case final current?) ...[
          Semantics(
            label: 'Setup step $current of 3',
            child: Row(
              spacing: 6,
              children: [
                for (var index = 1; index <= 3; index++)
                  Expanded(
                    child: AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      height: 4,
                      decoration: BoxDecoration(
                        color: index <= current
                            ? colors.primary
                            : colors.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (icon case final pair?) ...[
          Icon(isIos ? pair.$2 : pair.$1, color: colors.primary, size: 28),
          const SizedBox(height: 12),
        ],
        Semantics(
          header: true,
          child: Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SetupTextField extends StatelessWidget {
  const _SetupTextField({
    required this.label,
    required this.controller,
    required this.enabled,
    this.decimal = false,
    this.hint,
  });
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool decimal;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final keyboard = decimal
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text;
    if (AdaptiveThemeHelper.isIos(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(label),
          Semantics(
            label: label,
            child: CupertinoTextField(
              controller: controller,
              enabled: enabled,
              keyboardType: keyboard,
              placeholder: hint,
              padding: const EdgeInsets.all(14),
            ),
          ),
        ],
      );
    }
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _SetupChoice<T> extends StatelessWidget {
  const _SetupChoice({
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
  });
  final String label;
  final T value;
  final Map<T, String> choices;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (AdaptiveThemeHelper.isIos(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 6,
        children: [
          Text(label),
          CupertinoButton(
            color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
            onPressed: onChanged == null
                ? null
                : () async {
                    final picked = await showCupertinoModalPopup<T>(
                      context: context,
                      builder: (popup) => CupertinoActionSheet(
                        title: Text(label),
                        actions: [
                          for (final entry in choices.entries)
                            CupertinoActionSheetAction(
                              onPressed: () =>
                                  Navigator.of(popup).pop(entry.key),
                              child: Text(entry.value),
                            ),
                        ],
                        cancelButton: CupertinoActionSheetAction(
                          onPressed: () => Navigator.of(popup).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                    );
                    if (picked != null && context.mounted) {
                      onChanged?.call(picked);
                    }
                  },
            child: Row(
              children: [
                Expanded(child: Text(choices[value]!)),
                const Icon(CupertinoIcons.chevron_down, size: 16),
              ],
            ),
          ),
        ],
      );
    }
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isDense: true,
          isExpanded: true,
          value: value,
          items: [
            for (final entry in choices.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text(entry.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged == null
              ? null
              : (picked) {
                  if (picked != null) onChanged!(picked);
                },
        ),
      ),
    );
  }
}
