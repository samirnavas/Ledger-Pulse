import 'package:ledger_pulse/data/models/company_model.dart';

/// Supplies the pre-release module policy to tests of retained ERP internals.
/// Release access is covered using real [Company] instances in the guard tests.
class LegacyModuleTestCompany extends Company {
  LegacyModuleTestCompany({
    required super.id,
    super.name = 'Legacy workspace',
    super.legalName = 'Legacy workspace',
    super.gstin,
    super.stateCode,
    super.address,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : super(
         createdAt: createdAt ?? DateTime(2026),
         updatedAt: updatedAt ?? DateTime(2026),
       );

  @override
  bool isModuleEnabled(AppModule module) => enabledModules.contains(module);
}
