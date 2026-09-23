import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants/colors.dart';
import '../../core/constants/typography.dart';
import '../../core/theme/adaptive_theme.dart';
import '../../core/utils/adaptive_page_route.dart';
import '../../core/widgets/liquid_glass_card.dart';
import '../../data/models/user_profile_model.dart';
import '../auth/phone_input_screen.dart';
import '../home/company_switcher_sheet.dart';
import '../home/sync_settings_sheet.dart';
import '../providers/auth_providers.dart';
import '../providers/profile_provider.dart';
import '../inventory/inventory_screen.dart';
import '../reports/audit_log_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

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
  late TextEditingController _gstinController;
  late TextEditingController _businessTypeController;
  late TextEditingController _bankNameController;
  late TextEditingController _bankAccountController;
  late TextEditingController _bankIfscController;
  late TextEditingController _upiIdController;

  bool _isEditing = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(userProfileProvider);
    _nameController = TextEditingController(text: profile.name);
    _businessNameController = TextEditingController(text: profile.businessName);
    _phoneController = TextEditingController(text: profile.phoneNumber);
    _emailController = TextEditingController(text: profile.email);
    _addressController = TextEditingController(text: profile.address);
    _gstinController = TextEditingController(text: profile.gstin);
    _businessTypeController = TextEditingController(text: profile.businessType);
    _bankNameController = TextEditingController(text: profile.bankName ?? '');
    _bankAccountController = TextEditingController(text: profile.bankAccountNumber ?? '');
    _bankIfscController = TextEditingController(text: profile.bankIfsc ?? '');
    _upiIdController = TextEditingController(text: profile.upiId ?? '');

    _nameController.addListener(_onFieldChanged);
    _businessNameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _emailController.addListener(_onFieldChanged);
    _addressController.addListener(_onFieldChanged);
    _gstinController.addListener(_onFieldChanged);
    _businessTypeController.addListener(_onFieldChanged);
    _bankNameController.addListener(_onFieldChanged);
    _bankAccountController.addListener(_onFieldChanged);
    _bankIfscController.addListener(_onFieldChanged);
    _upiIdController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    final current = ref.read(userProfileProvider);
    final changed = _nameController.text != current.name ||
        _businessNameController.text != current.businessName ||
        _phoneController.text != current.phoneNumber ||
        _emailController.text != current.email ||
        _addressController.text != current.address ||
        _gstinController.text != current.gstin ||
        _businessTypeController.text != current.businessType ||
        _bankNameController.text != (current.bankName ?? '') ||
        _bankAccountController.text != (current.bankAccountNumber ?? '') ||
        _bankIfscController.text != (current.bankIfsc ?? '') ||
        _upiIdController.text != (current.upiId ?? '');

    if (changed != _hasChanges) {
      setState(() {
        _hasChanges = changed;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _businessNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _gstinController.dispose();
    _businessTypeController.dispose();
    _bankNameController.dispose();
    _bankAccountController.dispose();
    _bankIfscController.dispose();
    _upiIdController.dispose();
    super.dispose();
  }

  void _saveProfile() {
    if (_formKey.currentState?.validate() ?? false) {
      HapticFeedback.mediumImpact();
      final current = ref.read(userProfileProvider);
      final updatedProfile = current.copyWith(
        name: _nameController.text.trim(),
        businessName: _businessNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
        gstin: _gstinController.text.trim(),
        businessType: _businessTypeController.text.trim(),
        bankName: _bankNameController.text.trim(),
        bankAccountNumber: _bankAccountController.text.trim(),
        bankIfsc: _bankIfscController.text.trim().toUpperCase(),
        upiId: _upiIdController.text.trim(),
      );

      ref.read(userProfileProvider.notifier).updateProfile(updatedProfile);

      setState(() {
        _isEditing = false;
        _hasChanges = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Profile and banking details updated successfully'),
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
          title: const Row(
            children: [
              Icon(Icons.logout_rounded, color: AppColors.payableRed),
              SizedBox(width: 10),
              Text('Logout'),
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
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        createAdaptivePageRoute(
          builder: (context) => const PhoneInputScreen(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Form(
      key: _formKey,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Action Row for Edit/Save
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('My Profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  if (_isEditing)
                    TextButton.icon(
                      onPressed: _hasChanges ? _saveProfile : () {
                        HapticFeedback.lightImpact();
                        setState(() => _isEditing = false);
                      },
                      icon: Icon(Icons.check_circle_outline, color: _hasChanges ? Theme.of(context).colorScheme.primary : Colors.grey),
                      label: Text(
                        _hasChanges ? 'Save' : 'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _hasChanges
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          _isEditing = true;
                        });
                      },
                      icon: Icon(isIos ? CupertinoIcons.pencil : Icons.edit_outlined, size: 16),
                      label: const Text('Edit Profile'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // 1. Header Card with Avatar
              _buildHeaderCard(context, profile, isIos, isDark),

              const SizedBox(height: 24),

              // 1.5 ERP Foundation, Companies & Statutory Security
              _buildSectionHeader(context, 'Enterprise & Security', Icons.admin_panel_settings_outlined, isIos),
              const SizedBox(height: 12),
              _buildActionTile(
                context,
                title: 'Active Company',
                subtitle: profile.activeCompany.name,
                icon: isIos ? CupertinoIcons.building_2_fill : Icons.business_rounded,
                isIos: isIos,
                trailing: Chip(
                  label: Text(
                    profile.role.displayName,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onTap: () => CompanySwitcherSheet.show(context),
              ),
              const SizedBox(height: 10),
              _buildActionTile(
                context,
                title: 'Sync & Backup Center',
                subtitle: profile.activeCompany.isCloudSyncEnabled
                    ? 'Supabase Cloud (PostgreSQL)'
                    : (profile.activeCompany.isDropboxSyncEnabled ? 'Dropbox Storage Backup' : 'Local Only'),
                icon: isIos ? CupertinoIcons.cloud_upload_fill : Icons.sync_rounded,
                isIos: isIos,
                onTap: () => SyncSettingsSheet.show(context),
              ),
              const SizedBox(height: 10),
              _buildActionTile(
                context,
                title: 'Item Master & Inventory',
                subtitle: 'SKU tracking, stock valuation & alerts',
                icon: isIos ? CupertinoIcons.cube_box_fill : Icons.inventory_2_rounded,
                isIos: isIos,
                onTap: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (context) => const InventoryScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              _buildActionTile(
                context,
                title: 'Statutory Audit Trail',
                subtitle: 'Tamper-evident SHA-256 mutation log',
                icon: isIos ? CupertinoIcons.shield_lefthalf_fill : Icons.verified_user_rounded,
                isIos: isIos,
                onTap: () {
                  Navigator.of(context).push(
                    createAdaptivePageRoute(
                      builder: (context) => const AuditLogScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // 2. Personal Information Section
              _buildSectionHeader(context, 'Personal Information', Icons.person_outline_rounded, isIos),
              const SizedBox(height: 12),
              if (_isEditing) ...[
                _buildInputField(
                  context,
                  controller: _nameController,
                  label: 'Full Name',
                  icon: isIos ? CupertinoIcons.person : Icons.person_outline,
                  enabled: _isEditing,
                  validator: (val) => val == null || val.trim().isEmpty ? 'Name cannot be empty' : null,
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  context,
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: isIos ? CupertinoIcons.phone : Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  enabled: _isEditing,
                  validator: (val) => val == null || val.trim().isEmpty ? 'Phone number cannot be empty' : null,
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  context,
                  controller: _emailController,
                  label: 'Email Address',
                  icon: isIos ? CupertinoIcons.mail : Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  enabled: _isEditing,
                ),
              ] else
                _buildReadOnlyCard(context, isIos, [
                  _buildReadOnlyRow(context, 'Full Name', profile.name, isIos ? CupertinoIcons.person : Icons.person_outline),
                  const SizedBox(height: 16),
                  _buildReadOnlyRow(context, 'Phone Number', profile.phoneNumber, isIos ? CupertinoIcons.phone : Icons.phone_outlined),
                  const SizedBox(height: 16),
                  _buildReadOnlyRow(context, 'Email Address', profile.email, isIos ? CupertinoIcons.mail : Icons.email_outlined),
                ]),

              const SizedBox(height: 24),

              // 3. Business Information Section
              _buildSectionHeader(context, 'Business Details', Icons.business_outlined, isIos),
              const SizedBox(height: 12),
              if (_isEditing) ...[
                _buildInputField(
                  context,
                  controller: _businessNameController,
                  label: 'Business Name',
                  icon: isIos ? CupertinoIcons.briefcase : Icons.storefront_outlined,
                  enabled: _isEditing,
                  validator: (val) => val == null || val.trim().isEmpty ? 'Business name cannot be empty' : null,
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  context,
                  controller: _businessTypeController,
                  label: 'Business Type',
                  icon: isIos ? CupertinoIcons.tag : Icons.category_outlined,
                  enabled: _isEditing,
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  context,
                  controller: _gstinController,
                  label: 'GSTIN / Tax ID',
                  icon: isIos ? CupertinoIcons.doc_text : Icons.badge_outlined,
                  enabled: _isEditing,
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  context,
                  controller: _addressController,
                  label: 'Business Address',
                  icon: isIos ? CupertinoIcons.location : Icons.location_on_outlined,
                  maxLines: 2,
                  enabled: _isEditing,
                ),
              ] else
                _buildReadOnlyCard(context, isIos, [
                  _buildReadOnlyRow(context, 'Business Name', profile.businessName, isIos ? CupertinoIcons.briefcase : Icons.storefront_outlined),
                  const SizedBox(height: 16),
                  _buildReadOnlyRow(context, 'Business Type', profile.businessType, isIos ? CupertinoIcons.tag : Icons.category_outlined),
                  const SizedBox(height: 16),
                  _buildReadOnlyRow(context, 'GSTIN / Tax ID', profile.gstin, isIos ? CupertinoIcons.doc_text : Icons.badge_outlined),
                  const SizedBox(height: 16),
                  _buildReadOnlyRow(context, 'Business Address', profile.address, isIos ? CupertinoIcons.location : Icons.location_on_outlined),
                ]),

              const SizedBox(height: 24),

              // Banking & UPI Remittance Details Section (FR-VCH-09)
              _buildSectionHeader(
                context,
                'Banking & Remittance (Invoice Payment)',
                isIos ? CupertinoIcons.building_2_fill : Icons.account_balance_outlined,
                isIos,
              ),
              const SizedBox(height: 12),
              if (_isEditing) ...[
                _buildInputField(
                  context,
                  controller: _bankNameController,
                  label: 'Bank Name',
                  icon: isIos ? CupertinoIcons.building_2_fill : Icons.account_balance_rounded,
                  enabled: _isEditing,
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  context,
                  controller: _bankAccountController,
                  label: 'Account Number',
                  icon: isIos ? CupertinoIcons.number : Icons.credit_card_rounded,
                  keyboardType: TextInputType.number,
                  enabled: _isEditing,
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  context,
                  controller: _bankIfscController,
                  label: 'IFSC Code',
                  icon: isIos ? CupertinoIcons.barcode : Icons.qr_code_2_rounded,
                  enabled: _isEditing,
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  context,
                  controller: _upiIdController,
                  label: 'UPI ID / VPA (e.g. business@okhdfcbank)',
                  icon: isIos ? CupertinoIcons.money_dollar_circle : Icons.payment_rounded,
                  enabled: _isEditing,
                ),
              ] else
                _buildReadOnlyCard(context, isIos, [
                  _buildReadOnlyRow(context, 'Bank Name', profile.bankName ?? '', isIos ? CupertinoIcons.building_2_fill : Icons.account_balance_rounded),
                  const SizedBox(height: 16),
                  _buildReadOnlyRow(context, 'Account Number', profile.bankAccountNumber ?? '', isIos ? CupertinoIcons.number : Icons.credit_card_rounded),
                  const SizedBox(height: 16),
                  _buildReadOnlyRow(context, 'IFSC Code', profile.bankIfsc ?? '', isIos ? CupertinoIcons.barcode : Icons.qr_code_2_rounded),
                  const SizedBox(height: 16),
                  _buildReadOnlyRow(context, 'UPI ID / VPA', profile.upiId ?? '', isIos ? CupertinoIcons.money_dollar_circle : Icons.payment_rounded),
                ]),

              const SizedBox(height: 24),

              // 4. Save Changes Button (if editing)
              if (_isEditing) ...[
                ElevatedButton.icon(
                  onPressed: _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text(
                    'Save Changes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
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
    );
  }

  Widget _buildHeaderCard(
    BuildContext context,
    UserProfile profile,
    bool isIos,
    bool isDark,
  ) {
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
                    child: const Icon(
                      Icons.camera_alt,
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
                  profile.name,
                  style: AppTypography.titleMedium.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  profile.businessName,
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
                    profile.phoneNumber,
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
        Text(
          title,
          style: AppTypography.titleSmall.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
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
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(
        fontSize: 14,
        color: enabled
            ? Theme.of(context).colorScheme.onSurface
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: enabled
            ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
