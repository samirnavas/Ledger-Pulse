import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/colors.dart';
import '../../core/modules/module_catalog.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_confirm_dialog.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/account_model.dart';
import '../../data/models/company_model.dart';
import '../../domain/exceptions/ledger_exceptions.dart';
import '../providers/company_providers.dart';

/// Multi-step company creation flow (adaptive Cupertino / Material 3).
/// Used during first-run onboarding (when no companies exist) and from CompanySwitcherSheet.
class CreateCompanyFlow extends ConsumerStatefulWidget {
  final bool isOnboarding;
  final VoidCallback? onCompanyCreated;

  const CreateCompanyFlow({
    super.key,
    this.isOnboarding = false,
    this.onCompanyCreated,
  });

  static Future<Company?> navigate(BuildContext context) {
    return Navigator.of(context).push<Company>(
      createAdaptivePageRoute(builder: (_) => const CreateCompanyFlow()),
    );
  }

  @override
  ConsumerState<CreateCompanyFlow> createState() => _CreateCompanyFlowState();
}

class _CreateCompanyFlowState extends ConsumerState<CreateCompanyFlow> {
  int _currentStep = 0;
  bool _isSubmitting = false;

  // Step (a) controllers: Name, Legal Name, Currency
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _legalNameCtrl = TextEditingController();
  String _currencyCode = 'INR';

  // Step (b): Mode picker
  CompanyMode _selectedMode = CompanyMode.ledger;

  // Step (c): Presets & Custom Modules for Ledger
  String _selectedPreset = 'Billing & GST';
  late Set<AppModule> _selectedModules;
  bool _isCustomModulesExpanded = false;

  // Step (d): GST Setup (for Ledger with GST enabled)
  final TextEditingController _gstinCtrl = TextEditingController();
  final TextEditingController _stateCodeCtrl = TextEditingController();

  // Wallets opening balances (for Expense Tracker mode)
  final TextEditingController _cashOpeningCtrl = TextEditingController();
  final TextEditingController _bankOpeningCtrl = TextEditingController();

  final List<String> _commonCurrencies = const [
    'INR',
    'USD',
    'EUR',
    'GBP',
    'AED',
    'SGD',
    'CAD',
    'AUD',
  ];

  @override
  void initState() {
    super.initState();
    _selectedModules = ModuleCatalog.defaultsFor(
      CompanyMode.ledger,
      preset: _selectedPreset,
    );

    _gstinCtrl.addListener(() {
      final text = _gstinCtrl.text.trim();
      if (text.length >= 2) {
        final prefix = text.substring(0, 2);
        if (int.tryParse(prefix) != null && _stateCodeCtrl.text.isEmpty) {
          _stateCodeCtrl.text = prefix;
        }
      }
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _legalNameCtrl.dispose();
    _gstinCtrl.dispose();
    _stateCodeCtrl.dispose();
    _cashOpeningCtrl.dispose();
    _bankOpeningCtrl.dispose();
    super.dispose();
  }

  int get _totalSteps {
    if (_selectedMode == CompanyMode.expenseTracker) {
      // Step 0: Name/Legal/Currency, Step 1: Mode, Step 2: Wallets Opening Balances
      return 3;
    }
    // Ledger mode:
    // Step 0: Name/Legal/Currency, Step 1: Mode, Step 2: Presets/Modules,
    // Step 3 (if GST enabled): GST details
    return _selectedModules.contains(AppModule.gst) ? 4 : 3;
  }

  void _onModeChanged(CompanyMode newMode) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedMode = newMode;
      if (newMode == CompanyMode.expenseTracker) {
        _selectedModules = ModuleCatalog.defaultsFor(CompanyMode.expenseTracker);
      } else {
        _selectedModules = ModuleCatalog.defaultsFor(
          CompanyMode.ledger,
          preset: _selectedPreset,
        );
      }
    });
  }

  void _onPresetChanged(String preset) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedPreset = preset;
      _selectedModules = ModuleCatalog.defaultsFor(
        CompanyMode.ledger,
        preset: preset,
      );
    });
  }

  void _toggleModule(AppModule module, bool enable) {
    HapticFeedback.lightImpact();
    setState(() {
      if (enable) {
        _selectedModules = {..._selectedModules, module};
        // Auto-enable missing dependencies
        final missing = ModuleCatalog.missingDependencies(module, _selectedModules);
        if (missing.isNotEmpty) {
          _selectedModules = {..._selectedModules, ...missing};
        }
      } else {
        _selectedModules = _selectedModules.where((m) => m != module).toSet();
        // Auto-disable dependents
        final dependents = ModuleCatalog.dependentsOf(module);
        _selectedModules = _selectedModules.difference(dependents);
      }
    });
  }

  bool _validateCurrentStep() {
    if (_currentStep == 0) {
      if (_nameCtrl.text.trim().isEmpty) {
        _showToast('Company name is required');
        return false;
      }
    }
    return true;
  }

  void _nextStep() {
    HapticFeedback.lightImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_validateCurrentStep()) return;

    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      _submitCompany();
    }
  }

  void _previousStep() {
    HapticFeedback.lightImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  Future<void> _submitCompany() async {
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      final companyId = 'cmp_${DateTime.now().millisecondsSinceEpoch}';
      final hasGst = _selectedMode == CompanyMode.ledger && _selectedModules.contains(AppModule.gst);

      final newCompany = Company(
        id: companyId,
        name: _nameCtrl.text.trim(),
        legalName: _legalNameCtrl.text.trim().isNotEmpty
            ? _legalNameCtrl.text.trim()
            : _nameCtrl.text.trim(),
        currencyCode: _currencyCode,
        mode: _selectedMode,
        enabledModules: _selectedModules,
        gstin: hasGst && _gstinCtrl.text.trim().isNotEmpty
            ? _gstinCtrl.text.trim().toUpperCase()
            : null,
        stateCode: hasGst && _stateCodeCtrl.text.trim().isNotEmpty
            ? _stateCodeCtrl.text.trim()
            : null,
        dealerType: _selectedMode == CompanyMode.ledger ? 'regular' : '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Handle wallet opening balances for Expense Tracker mode
      Map<String, int>? initialWalletBalancesInCents;
      if (_selectedMode == CompanyMode.expenseTracker) {
        final cashParsed = double.tryParse(_cashOpeningCtrl.text.trim()) ?? 0.0;
        final bankParsed = double.tryParse(_bankOpeningCtrl.text.trim()) ?? 0.0;
        final cashCents = (cashParsed * 100).round();
        final bankCents = (bankParsed * 100).round();

        if (cashCents != 0 || bankCents != 0) {
          initialWalletBalancesInCents = {
            ExpenseTrackerDefaults.walletCashId: cashCents,
            ExpenseTrackerDefaults.walletBankId: bankCents,
          };
        }
      }

      await ref.read(companyControllerProvider.notifier).addCompany(
            newCompany,
            initialWalletBalancesInCents: initialWalletBalancesInCents,
          );

      widget.onCompanyCreated?.call();

      if (mounted) {
        if (!widget.isOnboarding && Navigator.canPop(context)) {
          Navigator.of(context).pop(newCompany);
        }
      }
    } catch (e) {
      if (mounted) {
        _showToast('Failed to create company: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    final isIos = AdaptiveThemeHelper.isIos(context);
    if (isIos) {
      showAdaptiveInfoDialog(
        context: context,
        title: 'Ledger Pulse',
        message: message,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    return AdaptiveScaffold(
      title: widget.isOnboarding ? 'Create your first company' : 'New Company',
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              children: [
                _buildProgressHeader(isIos, isDark),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    child: _buildCurrentStep(isIos, isDark),
                  ),
                ),
                _buildBottomActionBar(isIos, isDark),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressHeader(bool isIos, bool isDark) {
    final stepPercentage = (_currentStep + 1) / _totalSteps;
    final primaryColor = isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'STEP ${_currentStep + 1} OF $_totalSteps',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: primaryColor,
                ),
              ),
              Text(
                _stepTitle,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isIos
                      ? CupertinoColors.secondaryLabel
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: stepPercentage,
              minHeight: 6,
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  String get _stepTitle {
    switch (_currentStep) {
      case 0:
        return 'Company Profile';
      case 1:
        return 'Business Type';
      case 2:
        return _selectedMode == CompanyMode.ledger ? 'Module Preset' : 'Wallet Balances';
      case 3:
        return 'Tax & GST Setup';
      default:
        return '';
    }
  }

  Widget _buildCurrentStep(bool isIos, bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildStepCompanyProfile(isIos, isDark);
      case 1:
        return _buildStepCompanyMode(isIos, isDark);
      case 2:
        return _selectedMode == CompanyMode.ledger
            ? _buildStepLedgerPresetsAndModules(isIos, isDark)
            : _buildStepExpenseTrackerWallets(isIos, isDark);
      case 3:
        return _buildStepGstSetup(isIos, isDark);
      default:
        return const SizedBox.shrink();
    }
  }

  // STEP (a): Name, Legal Name, Currency
  Widget _buildStepCompanyProfile(bool isIos, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Let\'s set up your entity',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Enter the basic identifying information for this entity.',
          style: TextStyle(
            fontSize: 14,
            color: isIos
                ? CupertinoColors.secondaryLabel
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Company Name Field
        if (isIos) ...[
          const Text('Company Name *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: _nameCtrl,
            placeholder: 'e.g. Skyline Logistics Pvt Ltd',
            padding: const EdgeInsets.all(12),
          ),
          const SizedBox(height: 16),
          const Text('Legal / Trade Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: _legalNameCtrl,
            placeholder: 'Optional registered legal name',
            padding: const EdgeInsets.all(12),
          ),
        ] else ...[
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Company Name *',
              hintText: 'e.g. Skyline Logistics Pvt Ltd',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.business_rounded),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _legalNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Legal / Trade Name (Optional)',
              hintText: 'Registered business name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
          ),
        ],

        const SizedBox(height: 24),
        const Text('Operating Currency', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _commonCurrencies.map((curr) {
            final isSelected = _currencyCode == curr;
            return ChoiceChip(
              label: Text(curr, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
              selected: isSelected,
              onSelected: (val) {
                if (val) {
                  HapticFeedback.selectionClick();
                  setState(() => _currencyCode = curr);
                }
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // STEP (b): Mode Type Picker (Business Ledger vs Expense Tracker)
  Widget _buildStepCompanyMode(bool isIos, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose your organization mode',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Select the operating system that fits how you handle money.',
          style: TextStyle(
            fontSize: 14,
            color: isIos
                ? CupertinoColors.secondaryLabel
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Card 1: Business Ledger
        _buildModeCard(
          isIos: isIos,
          isDark: isDark,
          mode: CompanyMode.ledger,
          title: 'Business Ledger',
          subtitle: 'Double-entry bookkeeping, GST compliance, vouchers, inventory, manufacturing, payroll, and audit trails.',
          badge: 'Standard ERP',
          icon: isIos ? CupertinoIcons.chart_bar_alt_fill : Icons.account_balance_rounded,
        ),

        const SizedBox(height: 16),

        // Card 2: Expense Tracker
        _buildModeCard(
          isIos: isIos,
          isDark: isDark,
          mode: CompanyMode.expenseTracker,
          title: 'Expense Tracker',
          subtitle: 'Personal cashflow & small business wallets, budget tracking, recurring bills, and streamlined categorization.',
          badge: 'Lightweight',
          icon: isIos ? CupertinoIcons.creditcard_fill : Icons.wallet_rounded,
        ),
      ],
    );
  }

  Widget _buildModeCard({
    required bool isIos,
    required bool isDark,
    required CompanyMode mode,
    required String title,
    required String subtitle,
    required String badge,
    required IconData icon,
  }) {
    final isSelected = _selectedMode == mode;
    final primaryColor = isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: () => _onModeChanged(mode),
      child: LiquidGlassCard(
        borderRadius: 16,
        borderColor: isSelected ? primaryColor : (isDark ? Colors.white12 : Colors.black12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isSelected ? Border.all(color: primaryColor, width: 2) : null,
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? primaryColor.withValues(alpha: 0.15) : (isDark ? Colors.white10 : Colors.black12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: isSelected ? primaryColor : (isDark ? Colors.white70 : Colors.black54),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? primaryColor : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? primaryColor : (isDark ? Colors.white24 : Colors.black12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: isIos
                            ? CupertinoColors.secondaryLabel
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? primaryColor : (isDark ? Colors.white24 : Colors.black26),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // STEP (c) for Ledger: Presets & Expandable Module Checklist
  Widget _buildStepLedgerPresetsAndModules(bool isIos, bool isDark) {
    final presets = ['Simple Khata', 'Billing & GST', 'Full ERP'];
    final ledgerModules = ModuleCatalog.ledgerModules;
    final primaryColor = isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Choose your workflow preset',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Start with an optimized preset or customize the exact modules needed.',
          style: TextStyle(
            fontSize: 14,
            color: isIos
                ? CupertinoColors.secondaryLabel
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),

        // Preset Selector Chips
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: presets.map((preset) {
            final isSelected = _selectedPreset == preset;
            return ChoiceChip(
              label: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  preset,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                ),
              ),
              selected: isSelected,
              onSelected: (val) {
                if (val) _onPresetChanged(preset);
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 24),

        // Expandable Custom Module Checklist
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: _isCustomModulesExpanded,
              onExpansionChanged: (val) => setState(() => _isCustomModulesExpanded = val),
              title: Text(
                'Customize Modules (${_selectedModules.length} enabled)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              subtitle: Text(
                'Configure individual ERP capabilities',
                style: TextStyle(
                  fontSize: 12,
                  color: isIos
                      ? CupertinoColors.secondaryLabel
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              children: [
                const Divider(height: 1),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ledgerModules.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final module = ledgerModules[idx];
                    final isEnabled = _selectedModules.contains(module);
                    final missing = ModuleCatalog.missingDependencies(module, _selectedModules);

                    return SwitchListTile.adaptive(
                      value: isEnabled,
                      activeTrackColor: primaryColor,
                      title: Row(
                        children: [
                          Icon(ModuleCatalog.iconFor(module), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            ModuleCatalog.labelFor(module),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(
                            ModuleCatalog.descriptionFor(module),
                            style: TextStyle(
                              fontSize: 12,
                              color: isIos
                                  ? CupertinoColors.secondaryLabel
                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (missing.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Requires: ${missing.map(ModuleCatalog.labelFor).join(', ')}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.payableRed,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      onChanged: (val) => _toggleModule(module, val),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // STEP (c) for Expense Tracker: Initial Wallet Balances
  Widget _buildStepExpenseTrackerWallets(bool isIos, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Wallet Setup & Opening Balances',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Expense Tracker includes Cash and Bank wallets with default budget categories. Optionally set initial opening balances.',
          style: TextStyle(
            fontSize: 14,
            color: isIos
                ? CupertinoColors.secondaryLabel
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        // Cash Wallet Opening Balance
        if (isIos) ...[
          const Text('Cash in Wallet Opening Balance', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: _cashOpeningCtrl,
            placeholder: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(_currencyCode, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            padding: const EdgeInsets.all(12),
          ),
          const SizedBox(height: 16),
          const Text('Bank Account Opening Balance', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: _bankOpeningCtrl,
            placeholder: '0.00',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(_currencyCode, style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            padding: const EdgeInsets.all(12),
          ),
        ] else ...[
          TextField(
            controller: _cashOpeningCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Cash in Wallet Opening Balance',
              hintText: '0.00',
              prefixText: '$_currencyCode ',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bankOpeningCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Bank Account Opening Balance',
              hintText: '0.00',
              prefixText: '$_currencyCode ',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.account_balance_outlined),
            ),
          ),
        ],

        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (isIos ? CupertinoColors.activeBlue : Theme.of(context).colorScheme.primary).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '11 expense categories (Food, Groceries, Transport, etc.) and 2 income categories (Salary, Other) will be initialized automatically.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isIos
                        ? CupertinoColors.label
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // STEP (d): GST Setup (only for Ledger mode with GST module enabled)
  Widget _buildStepGstSetup(bool isIos, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GST & State Tax Details',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          'Since the GST module is enabled, provide your 15-character GSTIN. State code will auto-populate.',
          style: TextStyle(
            fontSize: 14,
            color: isIos
                ? CupertinoColors.secondaryLabel
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),

        if (isIos) ...[
          const Text('GSTIN (Optional)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: _gstinCtrl,
            placeholder: '29ABCDE1234F1ZH',
            textCapitalization: TextCapitalization.characters,
            padding: const EdgeInsets.all(12),
          ),
          const SizedBox(height: 16),
          const Text('2-Digit State Code', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          CupertinoTextField(
            controller: _stateCodeCtrl,
            placeholder: 'e.g. 29',
            keyboardType: TextInputType.number,
            padding: const EdgeInsets.all(12),
          ),
        ] else ...[
          TextField(
            controller: _gstinCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'GSTIN (Optional)',
              hintText: '29ABCDE1234F1ZH',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.receipt_long_outlined),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _stateCodeCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'State Code',
              hintText: 'e.g. 29',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.map_outlined),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomActionBar(bool isIos, bool isDark) {
    final isLastStep = _currentStep == _totalSteps - 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white,
        border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              flex: 1,
              child: AdaptiveButton(
                type: AdaptiveButtonType.secondary,
                onPressed: _isSubmitting ? null : _previousStep,
                child: const Text('Back'),
              ),
            )
          else if (!widget.isOnboarding && Navigator.canPop(context))
            Expanded(
              flex: 1,
              child: AdaptiveButton(
                type: AdaptiveButtonType.secondary,
                onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
          if (_currentStep > 0 || (!widget.isOnboarding && Navigator.canPop(context)))
            const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: AdaptiveButton(
              type: AdaptiveButtonType.primary,
              isLoading: _isSubmitting,
              onPressed: _isSubmitting ? null : _nextStep,
              child: Text(isLastStep ? 'Create Company' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }
}
