import 'package:drift/drift.dart' as drift;
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
import '../../core/widgets/adaptive_section_header.dart';
import '../../core/widgets/adaptive_segmented_control.dart';
import '../../data/local/database.dart';
import '../../data/local/outbox_helper.dart';
import '../../domain/models/workspace_profile_header.dart';
import '../providers/auth_providers.dart';
import '../providers/database_providers.dart';
import '../providers/profile_provider.dart';
import '../providers/profile_session_controller.dart';
import '../widgets/workspace_details_fields.dart';
import 'app_root_gate.dart';

class ProfileOnboardingScreen extends ConsumerStatefulWidget {
  final String userId;
  final String? initialName;

  const ProfileOnboardingScreen({
    super.key,
    required this.userId,
    this.initialName,
  });

  @override
  ConsumerState<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState
    extends ConsumerState<ProfileOnboardingScreen> {
  ProfileType _selectedType = ProfileType.expense;
  String _selectedCurrency = 'INR';

  final TextEditingController _nameController = TextEditingController();
  final _legalNameController = TextEditingController();
  final _details = WorkspaceDetailsControllers();

  bool _isCreating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null && widget.initialName!.trim().isNotEmpty) {
      _nameController.text = widget.initialName!.trim();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _legalNameController.dispose();
    _details.dispose();
    super.dispose();
  }

  void _handleLogout() async {
    HapticFeedback.mediumImpact();
    await ref.read(authControllerProvider.notifier).logout();
    ref.read(profileSessionProvider.notifier).logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        createAdaptivePageRoute(
          builder: (_) => const AppRootGate(),
          transitionType: SharedAxisTransitionType.scaled,
        ),
        (route) => false,
      );
    }
  }

  void _handleCreate() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorMessage = _selectedType == ProfileType.expense
            ? 'Please enter your workspace name'
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
      String? optional(TextEditingController controller) {
        final value = controller.text.trim();
        return _selectedType == ProfileType.ledger && value.isNotEmpty ? value : null;
      }
      final created = await repo.createProfile(
        name: name,
        type: _selectedType,
        currencyCode: _selectedCurrency,
        legalName: optional(_legalNameController),
        address: optional(_details.address),
        gstin: optional(_details.gstin)?.toUpperCase(),
        bankName: optional(_details.bankName),
        bankAccountNumber: optional(_details.bankAccountNumber),
        bankIfsc: optional(_details.bankIfsc)?.toUpperCase(),
        upiId: optional(_details.upiId),
        accountId: widget.userId,
      );

      // Save preference for newly created profile so it immediately becomes active
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs?.setString(activeWorkspacePreferenceKey(widget.userId), created.id);

      // Populate user_profiles in local database with details given during signup & onboarding
      final authState = ref.read(authControllerProvider);
      final accountName = (widget.initialName != null && widget.initialName!.trim().isNotEmpty)
          ? widget.initialName!.trim()
          : (authState.userName?.isNotEmpty == true ? authState.userName! : name);
      final accountEmail = authState.email ?? '';
      final accountPhone = authState.phoneNumber ?? '';

      final db = ref.read(appDatabaseProvider);
      final now = DateTime.now();

      await db.into(db.userProfiles).insertOnConflictUpdate(
        UserProfilesCompanion.insert(
          id: widget.userId,
          name: accountName,
          phoneNumber: accountPhone,
          email: accountEmail,
          role: const drift.Value('admin'),
          updatedAt: drift.Value(now),
          syncStatus: const drift.Value(SyncRecordStatus.pending),
        ),
      );

      try {
        await enqueueMutation(
          db: db,
          table: 'user_profiles',
          recordId: widget.userId,
          type: 'UPSERT',
          fullRowMap: {
            'id': widget.userId,
            'name': accountName,
            'phone_number': accountPhone,
            'phoneNumber': accountPhone,
            'email': accountEmail,
            'role': 'admin',
            'is_deleted': false,
            'isDeleted': false,
            'updated_at': now.toIso8601String(),
            'updatedAt': now,
          },
        );
      } catch (_) {}

      // Reload profile session and user profile so state machine transitions to active profile
      await ref
          .read(profileSessionProvider.notifier)
          .loadProfilesForUser(widget.userId);
      await ref.read(userProfileProvider.notifier).reloadFromDatabase();

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark ||
        CupertinoTheme.of(context).brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final secondaryText =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final canPop = ModalRoute.of(context)?.canPop ?? false;

    return AdaptiveScaffold(
      title: 'Set Up Your Workspace',
      actions: [
        if (!canPop)
          if (isIos)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: _handleLogout,
              child: Icon(
                CupertinoIcons.square_arrow_right,
                size: 22,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Sign Out',
              onPressed: _handleLogout,
            ),
      ],
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

              // Material 3 / Cupertino Adaptive Segmented Control
              AdaptiveSegmentedControl<ProfileType>(
                groupValue: _selectedType,
                children: const {
                  ProfileType.expense: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Personal & Expense',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  ProfileType.ledger: Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'Ledger · Coming Soon',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                },
                onValueChanged: (val) {
                  if (val == ProfileType.ledger) return;
                  HapticFeedback.lightImpact();
                  setState(() {
                    _selectedType = val;
                    _errorMessage = null;
                  });
                },
              ),
              const SizedBox(height: 12),

              // Selected Mode Minimal Description
              Text(
                _selectedType == ProfileType.expense
                    ? 'Track cash wallets, personal income, categories, and budgets.'
                    : 'Track customer and supplier transactions, balances, and statements.',
                style: AppTypography.bodySmall.copyWith(
                  color: secondaryText,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 1),
                child: Text(
                  'Workspace type cannot be changed after creation.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark
                        ? AppColors.textMutedDark
                        : AppColors.textMutedLight,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Form Section Header
              AdaptiveSectionHeader(
                title: _selectedType == ProfileType.expense
                    ? 'Expense Workspace Setup'
                    : 'Business Details & Compliance',
                padding: const EdgeInsets.only(bottom: 12),
              ),

              // Fields
              if (_selectedType == ProfileType.expense) ...[
                _buildAdaptiveInputField(
                  controller: _nameController,
                  label: 'Workspace Name',
                  hint: 'e.g. Samir Personal, Household Budget',
                  icon: isIos
                      ? CupertinoIcons.person
                      : Icons.person_outline_rounded,
                  isDark: isDark,
                  isIos: isIos,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _handleCreate(),
                ),
                const SizedBox(height: 14),
                AdaptiveDropdownField<String>(
                  label: 'Currency',
                  value: _selectedCurrency,
                  prefixIcon: Icon(
                    isIos
                        ? CupertinoIcons.money_dollar
                        : Icons.currency_exchange_rounded,
                    size: 20,
                    color: isDark
                        ? colorScheme.onSurfaceVariant
                        : AppColors.textSecondaryLight,
                  ),
                  items: const [
                    AdaptivePickerItem(label: 'INR - Indian Rupee (₹)', value: 'INR'),
                    AdaptivePickerItem(label: 'USD - US Dollar (\$)', value: 'USD'),
                    AdaptivePickerItem(label: 'EUR - Euro (€)', value: 'EUR'),
                    AdaptivePickerItem(label: 'GBP - British Pound (£)', value: 'GBP'),
                    AdaptivePickerItem(label: 'AED - UAE Dirham (د.إ)', value: 'AED'),
                    AdaptivePickerItem(label: 'SGD - Singapore Dollar (S\$)', value: 'SGD'),
                    AdaptivePickerItem(label: 'CAD - Canadian Dollar (C\$)', value: 'CAD'),
                    AdaptivePickerItem(label: 'AUD - Australian Dollar (A\$)', value: 'AUD'),
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
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                AdaptiveDropdownField<String>(
                  label: 'Primary Currency',
                  value: _selectedCurrency,
                  prefixIcon: Icon(
                    isIos
                        ? CupertinoIcons.money_dollar
                        : Icons.currency_exchange_rounded,
                    size: 20,
                    color: isDark
                        ? colorScheme.onSurfaceVariant
                        : AppColors.textSecondaryLight,
                  ),
                  items: const [
                    AdaptivePickerItem(label: 'INR - Indian Rupee (₹)', value: 'INR'),
                    AdaptivePickerItem(label: 'USD - US Dollar (\$)', value: 'USD'),
                    AdaptivePickerItem(label: 'EUR - Euro (€)', value: 'EUR'),
                    AdaptivePickerItem(label: 'GBP - British Pound (£)', value: 'GBP'),
                    AdaptivePickerItem(label: 'AED - UAE Dirham (د.إ)', value: 'AED'),
                    AdaptivePickerItem(label: 'SGD - Singapore Dollar (S\$)', value: 'SGD'),
                    AdaptivePickerItem(label: 'CAD - Canadian Dollar (C\$)', value: 'CAD'),
                    AdaptivePickerItem(label: 'AUD - Australian Dollar (A\$)', value: 'AUD'),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCurrency = val);
                  },
                ),
                const SizedBox(height: 14),
                _buildAdaptiveInputField(
                  controller: _legalNameController,
                  label: 'Legal / trade name (optional)',
                  hint: 'Registered business name',
                  icon: isIos ? CupertinoIcons.building_2_fill : Icons.business_outlined,
                  isDark: isDark,
                  isIos: isIos,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 14),
                WorkspaceDetailsFields(details: _details, enabled: !_isCreating),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      isIos
                          ? CupertinoIcons.exclamationmark_circle
                          : Icons.error_outline_rounded,
                      color: isIos
                          ? CupertinoColors.destructiveRed
                          : colorScheme.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: isIos
                              ? CupertinoColors.destructiveRed
                              : colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ],

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    width: 0.5,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: AdaptiveButton(
                  onPressed: _isCreating ? null : _handleCreate,
                  isFullWidth: true,
                  isLoading: _isCreating,
                  child: const Text('Complete & Open Workspace'),
                ),
              ),
            ),
          ],
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
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onSubmitted,
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
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ),
          CupertinoTextField(
            controller: controller,
            placeholder: hint,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            textCapitalization: textCapitalization,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            style: TextStyle(
              fontSize: 15,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
            placeholderStyle: TextStyle(
              fontSize: 15,
              color: isDark
                  ? AppColors.textMutedDark
                  : AppColors.textMutedLight,
            ),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 12.0),
              child: Icon(
                icon,
                size: 20,
                color: isDark
                    ? CupertinoColors.systemGrey
                    : CupertinoColors.systemGrey2,
              ),
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceCardDark
                  : AppColors.surfaceWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? const Color(0xFF27272A)
                    : AppColors.borderLight,
                width: 1,
              ),
            ),
          ),
        ],
      );
    }

    return TextField(
      controller: controller,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}
