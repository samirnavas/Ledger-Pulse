import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_button.dart';
import '../../core/widgets/adaptive_controls.dart';
import '../../core/widgets/adaptive_picker.dart';
import '../../core/widgets/adaptive_scaffold.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../domain/models/workspace_profile_header.dart';
import '../providers/auth_providers.dart';
import '../providers/profile_session_controller.dart';
import 'app_root_gate.dart';

class ProfileOnboardingScreen extends ConsumerStatefulWidget {
  final String userId;

  const ProfileOnboardingScreen({super.key, required this.userId});

  @override
  ConsumerState<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState
    extends ConsumerState<ProfileOnboardingScreen> {
  ProfileType _selectedType = ProfileType.expense;
  String _selectedCurrency = 'INR';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _legalNameController = TextEditingController();
  final TextEditingController _gstinController = TextEditingController();

  bool _isCreating = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _legalNameController.dispose();
    _gstinController.dispose();
    super.dispose();
  }

  void _handleCreate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorMessage = _selectedType == ProfileType.expense
            ? 'Please enter your profile name'
            : 'Please enter your business or firm name';
      });
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _errorMessage = null;
      _isCreating = true;
    });

    try {
      final repo = ref.read(profileRepositoryProvider);
      final created = await repo.createProfile(
        name: name,
        type: _selectedType,
        currencyCode: _selectedCurrency,
        legalName: _selectedType == ProfileType.ledger &&
                _legalNameController.text.trim().isNotEmpty
            ? _legalNameController.text.trim()
            : null,
        gstin: _selectedType == ProfileType.ledger &&
                _gstinController.text.trim().isNotEmpty
            ? _gstinController.text.trim().toUpperCase()
            : null,
        accountId: widget.userId,
      );

      // Save preference for newly created profile so it immediately becomes active
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs?.setString('last_active_profile_${widget.userId}', created.id);

      // Reload profile session so state machine transitions to active profile
      await ref
          .read(profileSessionProvider.notifier)
          .loadProfilesForUser(widget.userId);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          createAdaptivePageRoute(
            builder: (_) => const AppRootGate(),
            transitionType: SharedAxisTransitionType.scaled,
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final isDark = Theme.of(context).brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;

    final primaryText =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryText =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return AdaptiveScaffold(
      title: 'Setup Your Workspace',
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Select Workspace Type',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose how you want to manage your records. Workspace type is permanent and immutable.',
                style: AppTypography.bodySmall.copyWith(color: secondaryText),
              ),
              const SizedBox(height: 20),

              // Mode Selection Cards (Side-by-side or stacked on narrow)
              Row(
                children: [
                  Expanded(
                    child: _buildTypeCard(
                      type: ProfileType.expense,
                      title: 'Personal & Expense',
                      subtitle:
                          'Track cash wallets, personal income, categories & budgets.',
                      icon: isIos
                          ? CupertinoIcons.money_dollar_circle
                          : Icons.account_balance_wallet_outlined,
                      isSelected: _selectedType == ProfileType.expense,
                      accentColor: AppColors.primaryGreen,
                      isDark: isDark,
                      isIos: isIos,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _buildTypeCard(
                      type: ProfileType.ledger,
                      title: 'Business Ledger',
                      subtitle:
                          'Full double-entry bookkeeping, GST invoicing, parties & inventory.',
                      icon: isIos
                          ? CupertinoIcons.building_2_fill
                          : Icons.business_outlined,
                      isSelected: _selectedType == ProfileType.ledger,
                      accentColor: AppColors.primaryBlue,
                      isDark: isDark,
                      isIos: isIos,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Immutability Notice Banner
              _buildImmutabilityBanner(isDark, isIos),
              const SizedBox(height: 28),

              // Form Section Title
              Text(
                _selectedType == ProfileType.expense
                    ? 'Expense Profile Setup'
                    : 'Business Details & Compliance',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: primaryText,
                ),
              ),
              const SizedBox(height: 16),

              // Fields
              if (_selectedType == ProfileType.expense) ...[
                _buildAdaptiveInputField(
                  controller: _nameController,
                  label: 'Profile Name',
                  hint: 'e.g. Samir Personal, Household Budget',
                  icon: isIos
                      ? CupertinoIcons.person_crop_circle
                      : Icons.person_outline,
                  isDark: isDark,
                  isIos: isIos,
                ),
                const SizedBox(height: 16),
                AdaptiveDropdownField<String>(
                  label: 'Currency',
                  value: _selectedCurrency,
                  items: const [
                    AdaptivePickerItem(label: 'INR - Indian Rupee (₹)', value: 'INR'),
                    AdaptivePickerItem(label: 'USD - US Dollar (\$)', value: 'USD'),
                    AdaptivePickerItem(label: 'EUR - Euro (€)', value: 'EUR'),
                    AdaptivePickerItem(label: 'GBP - British Pound (£)', value: 'GBP'),
                    AdaptivePickerItem(label: 'AED - UAE Dirham (د.إ)', value: 'AED'),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCurrency = val);
                  },
                ),
              ] else ...[
                _buildAdaptiveInputField(
                  controller: _nameController,
                  label: 'Business / Company Name *',
                  hint: 'e.g. Apex Traders Ltd.',
                  icon: isIos
                      ? CupertinoIcons.building_2_fill
                      : Icons.business_outlined,
                  isDark: isDark,
                  isIos: isIos,
                ),
                const SizedBox(height: 16),
                _buildAdaptiveInputField(
                  controller: _legalNameController,
                  label: 'Legal Registered Name (Optional)',
                  hint: 'e.g. Apex Traders Private Limited',
                  icon: isIos
                      ? CupertinoIcons.doc_plaintext
                      : Icons.description_outlined,
                  isDark: isDark,
                  isIos: isIos,
                ),
                const SizedBox(height: 16),
                _buildAdaptiveInputField(
                  controller: _gstinController,
                  label: 'GSTIN (Optional)',
                  hint: '15-digit GST identification number',
                  icon: isIos
                      ? CupertinoIcons.number_circle
                      : Icons.confirmation_number_outlined,
                  isDark: isDark,
                  isIos: isIos,
                ),
                const SizedBox(height: 16),
                AdaptiveDropdownField<String>(
                  label: 'Primary Currency',
                  value: _selectedCurrency,
                  items: const [
                    AdaptivePickerItem(label: 'INR - Indian Rupee (₹)', value: 'INR'),
                    AdaptivePickerItem(label: 'USD - US Dollar (\$)', value: 'USD'),
                    AdaptivePickerItem(label: 'EUR - Euro (€)', value: 'EUR'),
                    AdaptivePickerItem(label: 'GBP - British Pound (£)', value: 'GBP'),
                    AdaptivePickerItem(label: 'AED - UAE Dirham (د.إ)', value: 'AED'),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCurrency = val);
                  },
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 36),

              AdaptiveButton(
                onPressed: _isCreating ? null : _handleCreate,
                isFullWidth: true,
                isLoading: _isCreating,
                child: Text(
                  _isCreating
                      ? 'Creating Workspace...'
                      : 'Complete & Open Workspace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImmutabilityBanner(bool isDark, bool isIos) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: isDark ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primaryBlue.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isIos ? CupertinoIcons.info_circle : Icons.info_outline,
            color: AppColors.primaryBlue,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Domain Rule: A workspace type cannot be altered after creation. Personal Expense and Business Ledger maintain separate database records and synchronization guarantees.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeCard({
    required ProfileType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required Color accentColor,
    required bool isDark,
    required bool isIos,
  }) {
    final borderCol = isSelected
        ? accentColor
        : (isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.1));

    final cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.15)
                : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 24,
            color: isSelected ? accentColor : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          style: AppTypography.titleSmall.copyWith(
            fontWeight: FontWeight.bold,
            color: isSelected ? accentColor : (isDark ? Colors.white : Colors.black87),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: AppTypography.bodySmall.copyWith(
            fontSize: 11,
            color: isDark ? Colors.white54 : Colors.black54,
            height: 1.35,
          ),
        ),
      ],
    );

    if (isIos) {
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedType = type);
        },
        child: LiquidGlassCard(
          borderRadius: 18,
          borderColor: borderCol,
          padding: const EdgeInsets.all(16),
          child: cardContent,
        ),
      );
    }

    return Card(
      elevation: isSelected ? 2 : 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: borderCol,
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      color: isSelected
          ? accentColor.withValues(alpha: 0.08)
          : (isDark
              ? Theme.of(context).colorScheme.surfaceContainerLow
              : AppColors.surfaceWhite),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedType = type);
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: cardContent,
        ),
      ),
    );
  }

  Widget _buildAdaptiveInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    required bool isIos,
  }) {
    if (isIos) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 6.0),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          CupertinoTextField(
            controller: controller,
            placeholder: hint,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Icon(
                icon,
                size: 20,
                color: isDark ? CupertinoColors.systemGrey : CupertinoColors.systemGrey2,
              ),
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceCardDark : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.12),
              ),
            ),
          ),
        ],
      );
    }

    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
    );
  }
}
