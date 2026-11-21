import '../../core/widgets/app_pull_to_refresh.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/adaptive_page_entrance.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../core/widgets/splitting_fab.dart';
import '../../data/models/company_model.dart';
import '../../data/models/user_profile_model.dart';
import '../auth/app_root_gate.dart';
import '../home/edit_profile_sheet.dart';
import '../providers/auth_providers.dart';
import '../providers/company_providers.dart';
import '../providers/profile_provider.dart';
import '../providers/profile_session_controller.dart';
import '../providers/sync_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final bool? isStandalone;

  const ProfileScreen({
    super.key,
    this.isStandalone,
  });

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _businessNameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _addressController;

  bool _isEditing = false;
  bool _hasChanges = false;

  late final ProfileSaveActionNotifier _saveActionNotifier;
  late final ProfileCancelActionNotifier _cancelActionNotifier;
  late final IsProfileEditingNotifier _isEditingNotifier;
  late final HasProfileChangesNotifier _hasChangesNotifier;

  @override
  void initState() {
    super.initState();
    _saveActionNotifier = ref.read(profileSaveActionProvider.notifier);
    _cancelActionNotifier = ref.read(profileCancelActionProvider.notifier);
    _isEditingNotifier = ref.read(isProfileEditingProvider.notifier);
    _hasChangesNotifier = ref.read(hasProfileChangesProvider.notifier);

    final profile = ref.read(userProfileProvider);
    _nameController = TextEditingController(text: profile.name);
    _businessNameController = TextEditingController(text: profile.businessName);
    _phoneController = TextEditingController(text: profile.phoneNumber);
    _emailController = TextEditingController(text: profile.email);
    _addressController = TextEditingController(text: profile.address);

    _nameController.addListener(_onFieldChanged);
    _businessNameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _addressController.addListener(_onFieldChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _saveActionNotifier.setAction(_saveProfile);
        _cancelActionNotifier.setAction(_cancelEditing);
      }
    });
  }

  void _onFieldChanged() {
    final current = ref.read(userProfileProvider);
    final changed = _nameController.text != current.name ||
        _businessNameController.text != current.businessName ||
        _phoneController.text != current.phoneNumber ||
        _emailController.text != current.email ||
        _addressController.text != current.address;

    if (changed != _hasChanges) {
      setState(() {
        _hasChanges = changed;
      });
      _hasChangesNotifier.setHasChanges(changed);
    }
  }

  void _cancelEditing() {
    HapticFeedback.lightImpact();
    final current = ref.read(userProfileProvider);
    _nameController.text = current.name;
    _businessNameController.text = current.businessName;
    _phoneController.text = current.phoneNumber;
    _emailController.text = current.email;
    _addressController.text = current.address;
    setState(() {
      _isEditing = false;
      _hasChanges = false;
    });
    _isEditingNotifier.setEditing(false);
    _hasChangesNotifier.setHasChanges(false);
  }

  @override
  void dispose() {
    try {
      _saveActionNotifier.setAction(null);
      _cancelActionNotifier.setAction(null);
      _isEditingNotifier.setEditing(false);
      _hasChangesNotifier.setHasChanges(false);
    } catch (_) {
      // Notifiers may have already been disposed if widget tree is tearing down
    }
    _nameController.dispose();
    _businessNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    if (_formKey.currentState?.validate() ?? false) {
      HapticFeedback.mediumImpact();
      final current = ref.read(userProfileProvider);
      final isExpense = ref.read(activeCompanyProvider).isExpense;
      final updatedProfile = current.copyWith(
        name: _nameController.text.trim(),
        businessName: isExpense ? _businessNameController.text.trim() : null,
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        address: isExpense ? _addressController.text.trim() : null,
      );

      ref.read(userProfileProvider.notifier).updateProfile(updatedProfile);

      setState(() {
        _isEditing = false;
        _hasChanges = false;
      });
      ref.read(isProfileEditingProvider.notifier).setEditing(false);
      ref.read(hasProfileChangesProvider.notifier).setHasChanges(false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                AdaptiveThemeHelper.isIos(context)
                    ? CupertinoIcons.checkmark_circle_fill
                    : Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Flexible(child: Text('Account details saved')),
            ],
          ),
          backgroundColor: AppColors.receivableGreen,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _confirmLogout(BuildContext context) {
    HapticFeedback.warningNotification();
    final isIos = AdaptiveThemeHelper.isIos(context);

    if (isIos) {
      showCupertinoModalPopup<void>(
        context: context,
        builder: (BuildContext context) => CupertinoActionSheet(
          title: const Text('Logout Confirmation'),
          message: const Text('Are you sure you want to logout from Ledger Pulse?'),
          actions: <CupertinoActionSheetAction>[
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(context);
                _performLogout();
              },
              child: const Text('Logout'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ),
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(
                AdaptiveThemeHelper.isIos(context)
                    ? CupertinoIcons.square_arrow_right
                    : Icons.logout_rounded,
                color: AppColors.payableRed,
              ),
              const SizedBox(width: 10),
              const Text('Logout'),
            ],
          ),
          content: const Text('Are you sure you want to log out from Ledger Pulse?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.payableRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context);
                _performLogout();
              },
              child: const Text('Logout'),
            ),
          ],
        ),
      );
    }
  }

  void _performLogout() async {
    await ref.read(authControllerProvider.notifier).logout();
    ref.read(profileSessionProvider.notifier).logout();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        createAdaptivePageRoute(
          builder: (context) => const AppRootGate(),
          transitionType: SharedAxisTransitionType.scaled,
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final profile = ref.watch(userProfileProvider);
    final activeCompany = ref.watch(activeCompanyProvider);
    final isExpense = activeCompany.mode == CompanyMode.expenseTracker;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen<bool>(isProfileEditingProvider, (previous, next) {
      if (next != _isEditing && mounted) {
        setState(() {
          _isEditing = next;
        });
      }
    });

    ref.listen<UserProfile>(userProfileProvider, (previous, next) {
      if (!_isEditing && !_hasChanges && mounted) {
        _nameController.text = next.name;
        _businessNameController.text = next.businessName;
        _phoneController.text = next.phoneNumber;
        _emailController.text = next.email;
        _addressController.text = next.address;
      }
    });

    ref.listen<Company>(activeCompanyProvider, (previous, next) {
      if (next.isExpense && !_isEditing && !_hasChanges && mounted) {
        if (_businessNameController.text.isEmpty && next.name.isNotEmpty) {
          _businessNameController.text = next.name;
        }
        if (_addressController.text.isEmpty && next.address != null && next.address!.isNotEmpty) {
          _addressController.text = next.address!;
        }
      }
    });

    final route = ModalRoute.of(context);
    final isStandalone = widget.isStandalone ?? (route != null && !route.isFirst);

    final formContent = Form(
      key: _formKey,
      child: SafeArea(
        child: AppPullToRefresh(
          onRefresh: () async {
            await ref.read(userProfileProvider.notifier).syncProfileToDatabase();
            await ref.read(syncControllerProvider.notifier).triggerSync();
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // 1. Header Card with Avatar
              _buildHeaderCard(context, profile, isIos, isDark),

              const SizedBox(height: 24),

              // 2. Personal Information Section
              _buildSectionHeader(context, 'Personal Information', Icons.person_outline_rounded, isIos),
              const SizedBox(height: 12),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 320),
                firstCurve: Curves.easeInOutCubic,
                secondCurve: Curves.easeInOutCubic,
                sizeCurve: Curves.easeInOutCubic,
                crossFadeState: _isEditing ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: _buildReadOnlyCard(context, isIos, [
                  _buildReadOnlyRow(
                    context,
                    'Full Name',
                    profile.name.isNotEmpty
                        ? profile.name
                        : (ref.watch(authControllerProvider).userName ?? ''),
                    isIos ? CupertinoIcons.person : Icons.person_outline,
                  ),
                  const SizedBox(height: 16),
                  _buildReadOnlyRow(
                    context,
                    'Phone Number',
                    profile.phoneNumber.isNotEmpty
                        ? profile.phoneNumber
                        : (ref.watch(authControllerProvider).phoneNumber ?? ''),
                    isIos ? CupertinoIcons.phone : Icons.phone_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildReadOnlyRow(
                    context,
                    'Email Address',
                    profile.email.isNotEmpty
                        ? profile.email
                        : (ref.watch(authControllerProvider).email ?? ''),
                    isIos ? CupertinoIcons.mail : Icons.email_outlined,
                  ),
                ]),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInputField(
                        context,
                        controller: _nameController,
                        label: 'Full Name',
                        icon: isIos ? CupertinoIcons.person : Icons.person_outline,
                        enabled: _isEditing,
                        validator: (val) => val == null || val.trim().isEmpty ? 'Name cannot be empty' : null,
                      ),
                      const SizedBox(height: 14),
                      _buildInputField(
                        context,
                        controller: _phoneController,
                        label: 'Phone Number',
                        icon: isIos ? CupertinoIcons.phone : Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        enabled: _isEditing,
                        validator: (val) => val == null || val.trim().isEmpty ? 'Phone number cannot be empty' : null,
                      ),
                      const SizedBox(height: 14),
                      _buildInputField(
                        context,
                        controller: _emailController,
                        label: 'Email Address',
                        icon: isIos ? CupertinoIcons.mail : Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        enabled: _isEditing,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              if (!isExpense) ...[
                _buildSectionHeader(
                  context,
                  'Workspace details',
                  Icons.business_outlined,
                  isIos,
                ),
                const SizedBox(height: 12),
                _buildActionTile(
                  context,
                  title: 'Edit business and bank details',
                  subtitle: activeCompany.name,
                  icon: isIos
                      ? CupertinoIcons.building_2_fill
                      : Icons.account_balance_outlined,
                  isIos: isIos,
                  onTap: () => showEditProfileSheet(context, activeCompany),
                ),
                const SizedBox(height: 24),
              ] else ...[
                _buildSectionHeader(context, 'Account Details', Icons.person_outline, isIos),
                const SizedBox(height: 12),
                if (_isEditing) ...[
                  _buildInputField(
                    context,
                    controller: _businessNameController,
                    label: 'Account Name',
                    icon: Icons.badge_outlined,
                    enabled: true,
                  ),
                  const SizedBox(height: 14),
                  _buildInputField(
                    context,
                    controller: _addressController,
                    label: 'Billing Address',
                    icon: Icons.location_on_outlined,
                    enabled: true,
                  ),
                ] else
                  _buildReadOnlyCard(context, isIos, [
                    _buildReadOnlyRow(context, 'Account Name', profile.businessName, Icons.badge_outlined),
                    const SizedBox(height: 14),
                    _buildReadOnlyRow(context, 'Billing Address', profile.address, Icons.location_on_outlined),
                  ]),
                const SizedBox(height: 24),
              ],

              // 5. Logout Section Button inside Profile
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: AppColors.payableRed.withValues(alpha: 0.3),
                    width: 1.2,
                  ),
                ),
                child: InkWell(
                  onTap: () => _confirmLogout(context),
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isIos ? CupertinoIcons.square_arrow_right : Icons.logout_rounded,
                          color: AppColors.payableRed,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Logout from Account',
                          style: TextStyle(
                            color: AppColors.payableRed,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    ),
  );

    if (isStandalone) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My Account'),
        ),
        floatingActionButton: SplittingProfileFab(
          isEditing: _isEditing,
          onEdit: () {
            HapticFeedback.lightImpact();
            setState(() => _isEditing = true);
            ref.read(isProfileEditingProvider.notifier).setEditing(true);
          },
          onSave: _saveProfile,
          onCancel: _cancelEditing,
        ),
        body: AdaptivePageEntrance(child: formContent),
      );
    }

    return AdaptivePageEntrance(child: formContent);
  }

  Widget _buildHeaderCard(
    BuildContext context,
    UserProfile profile,
    bool isIos,
    bool isDark,
  ) {
    final activeCompany = ref.watch(activeCompanyProvider);
    final isExpense = activeCompany.mode == CompanyMode.expenseTracker;
    final cardContent = Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  profile.initials,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              if (_isEditing)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isIos ? CupertinoIcons.camera_fill : Icons.camera_alt,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.name.isNotEmpty
                      ? profile.name
                      : (ref.watch(authControllerProvider).userName ?? 'My Account'),
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.businessName.isNotEmpty
                      ? profile.businessName
                      : (activeCompany.name.isNotEmpty
                          ? activeCompany.name
                          : (isExpense ? 'Personal Workspace' : 'Business Workspace')),
                  style: AppTypography.bodySmall.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    profile.phoneNumber.isNotEmpty
                        ? profile.phoneNumber
                        : (ref.watch(authControllerProvider).phoneNumber ?? 'No Phone'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 22,
        child: cardContent,
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: cardContent,
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon, bool isIos) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            style: AppTypography.titleSmall.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    required bool enabled,
    String? Function(String?)? validator,
  }) {
    final isIos = AdaptiveThemeHelper.isIos(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (isIos) {
      // iOS Modern Cupertino Inset Field
      return Container(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1C1C1E)
              : CupertinoColors.secondarySystemGroupedBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? const Color(0xFF38383A)
                : const Color(0xFFE5E5EA),
            width: 1.0,
          ),
        ),
        child: TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: validator,
          cursorColor: CupertinoColors.activeBlue,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: enabled
                ? (isDark ? CupertinoColors.white : CupertinoColors.black)
                : CupertinoColors.secondaryLabel,
          ),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(
              fontSize: 13,
              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
              fontWeight: FontWeight.w500,
            ),
            floatingLabelStyle: const TextStyle(
              fontSize: 12,
              color: CupertinoColors.activeBlue,
              fontWeight: FontWeight.w600,
            ),
            prefixIcon: Icon(
              icon,
              size: 20,
              color: isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70),
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            filled: false,
          ),
        ),
      );
    }

    // Material 3 Expressive Text Field (Android)
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      cursorColor: colorScheme.primary,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: enabled
            ? colorScheme.onSurface
            : colorScheme.onSurface.withValues(alpha: 0.6),
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 14,
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 12,
          color: colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Container(
          margin: const EdgeInsets.only(left: 12, right: 10),
          child: Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 24),
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: colorScheme.primary,
            width: 2.0,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: colorScheme.error,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: colorScheme.error,
            width: 2.0,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isIos,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 16,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: CupertinoColors.activeBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: CupertinoColors.activeBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.secondaryLabel,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              ?trailing,
              const SizedBox(width: 6),
              const Icon(CupertinoIcons.chevron_forward, size: 16, color: CupertinoColors.systemGrey3),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: Icon(icon, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?trailing,
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildReadOnlyCard(BuildContext context, bool isIos, List<Widget> children) {
    if (isIos) {
      return LiquidGlassCard(
        borderRadius: 16,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
    }
    
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildReadOnlyRow(BuildContext context, String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 2),
              Text(
                value.isEmpty ? 'Not provided' : value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
