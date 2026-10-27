import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../../core/modules/module_catalog.dart';
import '../../data/models/company_model.dart';
import '../../data/models/rbac_model.dart';
import '../../data/models/sync_model.dart';
import '../../data/models/user_profile_model.dart';
import '../models/audit_log_model.dart';
import '../security/access_control_service.dart';
import 'database.dart';
import 'drift_ledger_base.dart';

/// Mixin handling Companies and User Profile operations for DriftLedgerRepository.
mixin DriftCompaniesProfileMixin on DriftLedgerRepositoryBase {
  Future<void> seedAccountsFor(
    Company company, {
    Map<String, int>? initialWalletBalancesInCents,
  }) =>
      postingEngine.seedAccountsFor(
        company,
        initialWalletBalancesInCents: initialWalletBalancesInCents,
      );

  Future<void> _importCompaniesFromJsonIfEmpty() async {
    final profileRows = await (db.select(db.userProfiles)..where((t) => t.isDeleted.equals(false))).get();
    for (final profileRow in profileRows) {
      final jsonStr = profileRow.companiesJson;
      if (jsonStr != null && jsonStr.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(jsonStr);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is Map<String, dynamic>) {
                final comp = Company.fromMap(item);
                await _insertCompanyDirectly(comp);
              }
            }
          }
        } catch (e) {
          debugPrint('Failed to decode companiesJson for profile ${profileRow.id}: $e');
        }
      }
    }
  }

  Future<void> _insertCompanyDirectly(Company comp) async {
    await db.transaction(() async {
      await db.into(db.companies).insertOnConflictUpdate(
            CompaniesCompanion.insert(
              id: comp.id,
              name: comp.name,
              legalName: comp.legalName,
              gstin: Value(comp.gstin),
              stateCode: Value(comp.stateCode),
              dealerType: Value(comp.dealerType),
              currencyCode: Value(comp.currencyCode),
              address: Value(comp.address),
              email: Value(comp.email),
              phoneNumber: Value(comp.phoneNumber),
              logoUrl: Value(comp.logoUrl),
              signatureUrl: Value(comp.signatureUrl),
              signatoryName: Value(comp.signatoryName),
              bankName: Value(comp.bankName),
              bankAccountNumber: Value(comp.bankAccountNumber),
              bankIfsc: Value(comp.bankIfsc),
              upiId: Value(comp.upiId),
              isCloudSyncEnabled: Value(comp.isCloudSyncEnabled),
              isDropboxSyncEnabled: Value(comp.isDropboxSyncEnabled),
              isActive: Value(comp.isActive),
              isDeleted: const Value(false),
              createdAt: Value(comp.createdAt),
              updatedAt: Value(comp.updatedAt),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );
      await postingEngine.seedAccountsFor(comp);
    });
  }

  @override
  Future<List<Company>> getCompanies() async {
    await ensureInitialized();
    var rows = await (db.select(db.companies)..where((t) => t.isDeleted.equals(false))).get();

    // One-time compatibility: if the table has no companies but companiesJson has data, import it.
    if (rows.isEmpty) {
      await _importCompaniesFromJsonIfEmpty();
      rows = await (db.select(db.companies)..where((t) => t.isDeleted.equals(false))).get();
    }

    return rows.map((r) => Company(
      id: r.id,
      name: r.name,
      legalName: r.legalName,
      gstin: r.gstin,
      stateCode: r.stateCode,
      dealerType: r.dealerType,
      currencyCode: r.currencyCode,
      address: r.address,
      email: r.email,
      phoneNumber: r.phoneNumber,
      logoUrl: r.logoUrl,
      signatureUrl: r.signatureUrl,
      signatoryName: r.signatoryName,
      bankName: r.bankName,
      bankAccountNumber: r.bankAccountNumber,
      bankIfsc: r.bankIfsc,
      upiId: r.upiId,
      isCloudSyncEnabled: r.isCloudSyncEnabled,
      isDropboxSyncEnabled: r.isDropboxSyncEnabled,
      isActive: r.isActive,
      mode: CompanyMode.fromName(r.mode),
      enabledModules: r.enabledModulesJson != null
          ? AppModule.parseSet(r.enabledModulesJson)
          : AppModule.allModules,
      createdAt: r.createdAt,
      updatedAt: r.updatedAt,
    )).toList();
  }

  Future<Company> createCompany(
    Company company, {
    Map<String, int>? initialWalletBalancesInCents,
  }) async {
    await ensureInitialized();
    AccessControlService.verifyPermission(currentRole, UserAction.createCompany);

    await db.transaction(() async {
      await db.into(db.companies).insertOnConflictUpdate(
            CompaniesCompanion.insert(
              id: company.id,
              name: company.name,
              legalName: company.legalName,
              gstin: Value(company.gstin),
              stateCode: Value(company.stateCode),
              dealerType: Value(company.dealerType),
              currencyCode: Value(company.currencyCode),
              address: Value(company.address),
              email: Value(company.email),
              phoneNumber: Value(company.phoneNumber),
              logoUrl: Value(company.logoUrl),
              signatureUrl: Value(company.signatureUrl),
              signatoryName: Value(company.signatoryName),
              bankName: Value(company.bankName),
              bankAccountNumber: Value(company.bankAccountNumber),
              bankIfsc: Value(company.bankIfsc),
              upiId: Value(company.upiId),
              isCloudSyncEnabled: Value(company.isCloudSyncEnabled),
              isDropboxSyncEnabled: Value(company.isDropboxSyncEnabled),
              isActive: Value(company.isActive),
              mode: Value(company.mode.name),
              enabledModulesJson: Value(jsonEncode(company.enabledModules.map((m) => m.name).toList())),
              isDeleted: const Value(false),
              createdAt: Value(company.createdAt),
              updatedAt: Value(company.updatedAt),
              syncStatus: const Value(SyncRecordStatus.pending),
            ),
          );

      // Seed chart of accounts inside the same transaction as the company insert
      await postingEngine.seedAccountsFor(
        company,
        initialWalletBalancesInCents: initialWalletBalancesInCents,
      );

      await recordOutboxEntry(
        targetTable: 'companies',
        recordId: company.id,
        mutationType: 'UPSERT',
        payload: {
          ...company.toMap(),
          'companyId': company.id,
        },
        companyId: company.id,
      );

      await recordAuditLog(
        entityType: 'company',
        entityId: company.id,
        action: AuditAction.insert,
        newState: company.toMap(),
        companyId: company.id,
      );
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
    return company;
  }

  /// Upgrades an expense tracker company to a business ledger in a single transaction.
  Future<Company> upgradeToLedger(
    String companyId, {
    String preset = ModulePresets.billingAndGst,
    Set<AppModule>? modules,
  }) async {
    await ensureInitialized();
    AccessControlService.verifyPermission(currentRole, UserAction.createCompany);

    final existing = await (db.select(db.companies)..where((t) => t.id.equals(companyId))).getSingleOrNull();
    if (existing == null) {
      throw Exception('Company not found: $companyId');
    }

    final targetModules = modules ?? ModuleCatalog.defaultsFor(CompanyMode.ledger, preset: preset);
    final now = DateTime.now();

    final oldMap = {
      'id': existing.id,
      'name': existing.name,
      'legalName': existing.legalName,
      'mode': existing.mode,
      'enabledModules': existing.enabledModulesJson,
    };

    late Company updatedCompany;

    await db.transaction(() async {
      // 1. Update company record: set mode = ledger, apply preset modules
      await (db.update(db.companies)..where((t) => t.id.equals(companyId))).write(
        CompaniesCompanion(
          mode: Value(CompanyMode.ledger.name),
          enabledModulesJson: Value(jsonEncode(targetModules.map((m) => m.name).toList())),
          updatedAt: Value(now),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      // 2. Seed only the missing ledger accounts (AR, AP, GST, etc.)
      await postingEngine.seedMissingLedgerAccountsFor(companyId);

      // Build updated company model
      final row = await (db.select(db.companies)..where((t) => t.id.equals(companyId))).getSingle();
      updatedCompany = Company(
        id: row.id,
        name: row.name,
        legalName: row.legalName,
        gstin: row.gstin,
        stateCode: row.stateCode,
        dealerType: row.dealerType,
        currencyCode: row.currencyCode,
        address: row.address,
        email: row.email,
        phoneNumber: row.phoneNumber,
        logoUrl: row.logoUrl,
        signatureUrl: row.signatureUrl,
        signatoryName: row.signatoryName,
        bankName: row.bankName,
        bankAccountNumber: row.bankAccountNumber,
        bankIfsc: row.bankIfsc,
        upiId: row.upiId,
        isCloudSyncEnabled: row.isCloudSyncEnabled,
        isDropboxSyncEnabled: row.isDropboxSyncEnabled,
        isActive: row.isActive,
        mode: CompanyMode.fromName(row.mode),
        enabledModules: AppModule.parseSet(row.enabledModulesJson),
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

      // 3. Write sync outbox entry
      await recordOutboxEntry(
        targetTable: 'companies',
        recordId: companyId,
        mutationType: 'UPSERT',
        payload: {
          ...updatedCompany.toMap(),
          'companyId': companyId,
          'action': 'upgrade_to_ledger',
        },
        companyId: companyId,
      );

      // 4. Record audit log
      await recordAuditLog(
        entityType: 'company',
        entityId: companyId,
        action: AuditAction.update,
        oldState: oldMap,
        newState: updatedCompany.toMap(),
        companyId: companyId,
      );
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
    return updatedCompany;
  }

  Future<Company> updateCompany(Company company) async {
    await ensureInitialized();
    AccessControlService.verifyPermission(currentRole, UserAction.createCompany);

    final existing = await (db.select(db.companies)..where((t) => t.id.equals(company.id))).getSingleOrNull();
    final oldMap = existing != null ? {
      'id': existing.id,
      'name': existing.name,
      'legalName': existing.legalName,
      'gstin': existing.gstin,
    } : null;

    final updated = company.copyWith(updatedAt: DateTime.now());

    await db.transaction(() async {
      await (db.update(db.companies)..where((t) => t.id.equals(updated.id))).write(
        CompaniesCompanion(
          name: Value(updated.name),
          legalName: Value(updated.legalName),
          gstin: Value(updated.gstin),
          stateCode: Value(updated.stateCode),
          dealerType: Value(updated.dealerType),
          currencyCode: Value(updated.currencyCode),
          address: Value(updated.address),
          email: Value(updated.email),
          phoneNumber: Value(updated.phoneNumber),
          logoUrl: Value(updated.logoUrl),
          signatureUrl: Value(updated.signatureUrl),
          signatoryName: Value(updated.signatoryName),
          bankName: Value(updated.bankName),
          bankAccountNumber: Value(updated.bankAccountNumber),
          bankIfsc: Value(updated.bankIfsc),
          upiId: Value(updated.upiId),
          isCloudSyncEnabled: Value(updated.isCloudSyncEnabled),
          isDropboxSyncEnabled: Value(updated.isDropboxSyncEnabled),
          isActive: Value(updated.isActive),
          mode: Value(updated.mode.name),
          enabledModulesJson: Value(jsonEncode(updated.enabledModules.map((m) => m.name).toList())),
          updatedAt: Value(updated.updatedAt),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await recordOutboxEntry(
        targetTable: 'companies',
        recordId: updated.id,
        mutationType: 'UPSERT',
        payload: {
          ...updated.toMap(),
          'companyId': updated.id,
        },
        companyId: updated.id,
      );

      await recordAuditLog(
        entityType: 'company',
        entityId: updated.id,
        action: AuditAction.update,
        oldState: oldMap,
        newState: updated.toMap(),
        companyId: updated.id,
      );
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
    return updated;
  }

  Future<void> deleteCompany(String companyId) async {
    await ensureInitialized();
    AccessControlService.verifyPermission(currentRole, UserAction.createCompany);

    await db.transaction(() async {
      await (db.update(db.companies)..where((t) => t.id.equals(companyId))).write(
        CompaniesCompanion(
          isDeleted: const Value(true),
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
          syncStatus: const Value(SyncRecordStatus.pending),
        ),
      );

      await recordOutboxEntry(
        targetTable: 'companies',
        recordId: companyId,
        mutationType: 'DELETE',
        payload: {
          'id': companyId,
          'isDeleted': true,
          'companyId': companyId,
        },
        companyId: companyId,
      );
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
  }

  // --- User Profile Management ---

  Future<UserProfile?> getUserProfile([String? userId]) async {
    await ensureInitialized();
    final targetId = userId ?? currentUserId;

    final profileRow = await (db.select(db.userProfiles)
          ..where((t) => t.id.equals(targetId) & t.isDeleted.equals(false)))
        .getSingleOrNull();

    final companies = await getCompanies();

    if (profileRow == null) {
      if (companies.isNotEmpty) {
        return UserProfile(
          id: targetId,
          name: 'User',
          phoneNumber: companies.first.phoneNumber ?? '',
          email: companies.first.email ?? '',
          companies: companies,
          activeCompanyId: companies.first.id,
        );
      }
      return null;
    }

    Role userRole = Role.admin;
    try {
      userRole = Role.values.byName(profileRow.role);
    } catch (e) {
      debugPrint('Unknown user role "${profileRow.role}", defaulting to admin: $e');
    }

    return UserProfile(
      id: profileRow.id,
      name: profileRow.name,
      phoneNumber: profileRow.phoneNumber,
      email: profileRow.email,
      businessName: profileRow.businessName,
      address: profileRow.address,
      gstin: profileRow.gstin,
      businessType: profileRow.businessType,
      bankName: profileRow.bankName,
      bankAccountNumber: profileRow.bankAccountNumber,
      bankIfsc: profileRow.bankIfsc,
      upiId: profileRow.upiId,
      activeCompanyId: profileRow.activeCompanyId,
      role: userRole,
      companies: companies,
    );
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    await ensureInitialized();

    final profileCompanion = UserProfilesCompanion.insert(
      id: profile.id,
      name: profile.name,
      phoneNumber: profile.phoneNumber,
      email: profile.email,
      businessName: Value(profile.businessName),
      address: Value(profile.address),
      gstin: Value(profile.gstin),
      businessType: Value(profile.businessType),
      bankName: Value(profile.bankName),
      bankAccountNumber: Value(profile.bankAccountNumber),
      bankIfsc: Value(profile.bankIfsc),
      upiId: Value(profile.upiId),
      activeCompanyId: Value(profile.activeCompanyId),
      role: Value(profile.role.name),
      companiesJson: const Value.absent(),
      isDeleted: const Value(false),
      updatedAt: Value(DateTime.now()),
      syncStatus: const Value(SyncRecordStatus.pending),
    );

    await db.transaction(() async {
      await db.into(db.userProfiles).insertOnConflictUpdate(profileCompanion);

      // Persist any companies directly into the Companies table (single source of truth)
      for (final comp in profile.companies) {
        await db.into(db.companies).insertOnConflictUpdate(
              CompaniesCompanion.insert(
                id: comp.id,
                name: comp.name,
                legalName: comp.legalName,
                gstin: Value(comp.gstin),
                stateCode: Value(comp.stateCode),
                dealerType: Value(comp.dealerType),
                currencyCode: Value(comp.currencyCode),
                address: Value(comp.address),
                email: Value(comp.email),
                phoneNumber: Value(comp.phoneNumber),
                logoUrl: Value(comp.logoUrl),
                signatureUrl: Value(comp.signatureUrl),
                signatoryName: Value(comp.signatoryName),
                bankName: Value(comp.bankName),
                bankAccountNumber: Value(comp.bankAccountNumber),
                bankIfsc: Value(comp.bankIfsc),
                upiId: Value(comp.upiId),
                isCloudSyncEnabled: Value(comp.isCloudSyncEnabled),
                isDropboxSyncEnabled: Value(comp.isDropboxSyncEnabled),
                isActive: Value(comp.isActive),
                mode: Value(comp.mode.name),
                enabledModulesJson: Value(jsonEncode(comp.enabledModules.map((m) => m.name).toList())),
                isDeleted: const Value(false),
                createdAt: Value(comp.createdAt),
                updatedAt: Value(comp.updatedAt),
                syncStatus: const Value(SyncRecordStatus.pending),
              ),
            );
        await postingEngine.seedAccountsFor(comp);

        await recordOutboxEntry(
          targetTable: 'companies',
          recordId: comp.id,
          mutationType: 'UPSERT',
          payload: {
            ...comp.toMap(),
            'companyId': comp.id,
          },
          companyId: comp.id,
        );
      }

      await recordOutboxEntry(
        targetTable: 'user_profiles',
        recordId: profile.id,
        mutationType: 'UPSERT',
        payload: {
          ...profile.toMap(),
          'companyId': profile.activeCompanyId,
        },
        companyId: profile.activeCompanyId,
      );

      await recordAuditLog(
        entityType: 'user_profile',
        entityId: profile.id,
        action: AuditAction.update,
        newState: profile.toMap(),
        companyId: profile.activeCompanyId,
        userId: profile.id,
      );
    });

    updateStreamController.add(null);
    triggerBackgroundSync();
  }
}
