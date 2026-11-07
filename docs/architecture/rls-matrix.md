# Cloud Security & Row Level Security (RLS) Authorization Matrix

**Contract Version:** `v1.0.0-PROD-CONTRACT-20261106`  
**Status:** Approved Architectural Target (Read-Only Specification)  
**Security Standard:** Zero-Trust Multi-Tenant Isolation with Role-Based Access Control (RBAC)  
**Target Migration:** Emergency Migration `0010_emergency_security_hardening.sql` followed by `0011_target_architecture_rls.sql`  

---

## 1. Vulnerability Root Cause & Emergency Remediation

### 1.1 Critical Vulnerabilities Addressed
1. **Wide-Open Public Read-Write Policies (`RSK-01` from Migration 0008):**
   - In `0008_modes_modules.sql`, six policies granted `USING (true) WITH CHECK (true)` for `anon` and `authenticated` on `accounts`, `vouchers`, `journals`, `journal_lines`, `budgets`, and `recurring_rules`.
   - Migration `0009` failed to drop them. Because PostgreSQL evaluates permissive policies with `OR`, any anonymous user with the anon key can view and alter all tenant books.
2. **`owner_id IS NULL` Data Leak (`RSK-02` from Migration 0009):**
   - In `0009_identity_sync_hardening.sql`, policy `owner_isolation_companies` included `OR owner_id IS NULL`, granting any authenticated user visibility over all legacy un-owned companies.
3. **Missing Policies on Enabled Tables:**
   - `inventory_items`, `stock_ledger`, and `audit_logs` had RLS enabled in migration 0009 without policies, resulting in broken client access or arbitrary state.

### 1.2 Emergency Security Migration Script (`0010_emergency_security_hardening.sql`)

This script must be executed in Supabase immediately prior to any schema restructuring:

```sql
-- ====================================================================
-- MIGRATION 0010: EMERGENCY SECURITY HARDENING & LEAK REMEDIATION
-- ====================================================================

-- Step 1: DROP ALL 6 PERMISSIVE PUBLIC POLICIES FROM MIGRATION 0008
DROP POLICY IF EXISTS "Allow public read-write on accounts" ON public.accounts;
DROP POLICY IF EXISTS "Allow public read-write on vouchers" ON public.vouchers;
DROP POLICY IF EXISTS "Allow public read-write on journals" ON public.journals;
DROP POLICY IF EXISTS "Allow public read-write on journal_lines" ON public.journal_lines;
DROP POLICY IF EXISTS "Allow public read-write on budgets" ON public.budgets;
DROP POLICY IF EXISTS "Allow public read-write on recurring_rules" ON public.recurring_rules;

-- Step 2: DROP PERMISSIVE NULL CLAUSE ON COMPANIES FROM MIGRATION 0009
DROP POLICY IF EXISTS "owner_isolation_companies" ON public.companies;
CREATE POLICY "owner_isolation_companies" ON public.companies
    FOR ALL TO authenticated
    USING (owner_id = auth.uid())
    WITH CHECK (owner_id = auth.uid());

-- Step 3: IMMEDIATE INTERIM LOCKDOWN ON VOUCHERS & JOURNALS (OWNER RESTRICTED)
CREATE POLICY "owner_isolation_vouchers" ON public.vouchers
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

CREATE POLICY "owner_isolation_journals" ON public.journals
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

CREATE POLICY "owner_isolation_journal_lines" ON public.journal_lines
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

CREATE POLICY "owner_isolation_accounts" ON public.accounts
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

CREATE POLICY "owner_isolation_inventory_items" ON public.inventory_items
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

CREATE POLICY "owner_isolation_stock_ledger" ON public.stock_ledger
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));

CREATE POLICY "owner_isolation_audit_logs" ON public.audit_logs
    FOR ALL TO authenticated
    USING (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()))
    WITH CHECK (company_id IN (SELECT id FROM public.companies WHERE owner_id = auth.uid()));
```

---

## 2. High-Performance RLS Helper Functions

To avoid recursive policy evaluations and multi-table joins on every queried row, Supabase PostgreSQL utilizes optimized `SECURITY DEFINER` helper functions marked with `STABLE`:

```sql
-- Checks if current user is an active member of profile with one of the allowed roles
CREATE OR REPLACE FUNCTION public.has_profile_role(p_profile_id TEXT, p_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        -- 1. Direct owner match
        SELECT 1 FROM public.companies
        WHERE id = p_profile_id AND owner_id = auth.uid()
        UNION ALL
        -- 2. Explicit membership role match
        SELECT 1 FROM public.shared_memberships
        WHERE profile_id = p_profile_id
          AND account_id = auth.uid()
          AND role = ANY(p_roles)
    );
$$;

-- Returns profile type ('expense' or 'ledger')
CREATE OR REPLACE FUNCTION public.get_profile_type(p_profile_id TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT mode FROM public.companies WHERE id = p_profile_id;
$$;
```

---

## 3. Comprehensive Target RLS Authorization Matrix

| Table Name | Operation | Target Role | Permitted If (USING / WITH CHECK) | Policy Rule Description |
| :--- | :--- | :--- | :--- | :--- |
| **`shared_profiles`** (`companies`) | `SELECT` | Authenticated | `has_profile_role(id, ARRAY['owner','admin','accountant','manager','data_entry','viewer'])` | Members can view the workspaces they belong to. |
| | `INSERT` | Authenticated | `owner_id = auth.uid()` | Any authenticated user can create a new profile with themselves as owner. |
| | `UPDATE` | Authenticated | `has_profile_role(id, ARRAY['owner','admin'])` | Only Owners and Admins can update profile settings. |
| | `DELETE` | Authenticated | `owner_id = auth.uid()` | Only the Owner can delete/soft-delete a profile. |
| **`shared_memberships`** | `SELECT` | Authenticated | `account_id = auth.uid() OR has_profile_role(profile_id, ARRAY['owner','admin'])` | Users view their own memberships; Admins view all workspace members. |
| | `INSERT` | Authenticated | `has_profile_role(profile_id, ARRAY['owner','admin'])` | Owners and Admins can invite new members. |
| | `UPDATE` | Authenticated | `has_profile_role(profile_id, ARRAY['owner','admin'])` | Owners and Admins can modify member roles. |
| | `DELETE` | Authenticated | `has_profile_role(profile_id, ARRAY['owner']) OR account_id = auth.uid()` | Owners can remove members; members can leave. |
| **`exp_wallets`** | `SELECT` | Authenticated | `has_profile_role(profile_id, ARRAY['owner','admin','viewer'])` | Any workspace member can view wallets in Expense profile. |
| | `INSERT`/`UPDATE` | Authenticated | `has_profile_role(profile_id, ARRAY['owner','admin'])` | Owners and Admins manage wallet accounts. |
| | `DELETE` | Authenticated | `has_profile_role(profile_id, ARRAY['owner','admin'])` | Soft-delete only. |
| **`exp_categories`** | `SELECT` | Authenticated | `has_profile_role(profile_id, ARRAY['owner','admin','viewer'])` | Workspace members can view categories. |
| | `INSERT`/`UPDATE` | Authenticated | `has_profile_role(profile_id, ARRAY['owner','admin'])` | Category configuration restricted to Owners and Admins. |
| **`exp_transactions`** | `SELECT` | Authenticated | `has_profile_role(profile_id, ARRAY['owner','admin','viewer'])` | Members view expense transactions. |
| | `INSERT`/`UPDATE` | Authenticated | `has_profile_role(profile_id, ARRAY['owner','admin'])` | Members create and edit transactions. |
| | `DELETE` | Authenticated | `has_profile_role(profile_id, ARRAY['owner','admin'])` | Soft-delete only. |
| **`led_vouchers`** | `SELECT` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','accountant','manager','data_entry','viewer'])` | All members view vouchers in Ledger profile. |
| | `INSERT` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','accountant','manager','data_entry'])` | Permitted roles create vouchers. |
| | `UPDATE` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','accountant','manager'])` | Data entry roles cannot modify posted vouchers. |
| | `DELETE` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin'])` | Voiding / soft-deleting vouchers requires elevated permissions. |
| **`led_journals`** | `SELECT` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','accountant','manager','viewer'])` | Data entry roles restricted from viewing general journals. |
| | `INSERT`/`UPDATE` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','accountant'])` | Posted double-entry journals generated strictly by authorized roles. |
| | `DELETE` | Authenticated | `has_profile_role(company_id, ARRAY['owner'])` | Journal deletion forbidden; must be voided. |
| **`led_journal_lines`** | `SELECT` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','accountant','manager','viewer'])` | Read journal line items. |
| | `INSERT`/`UPDATE` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','accountant'])` | Debit/credit line posting restricted. |
| **`led_inventory_items`** | `SELECT` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','accountant','manager','data_entry','viewer'])` | View item master. |
| | `INSERT`/`UPDATE` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','manager'])` | Stock item creation and price adjustments. |
| **`led_audit_logs`** | `SELECT` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','accountant'])` | Statutory audit trail viewing restricted to Owner/Admin/Accountant. |
| | `INSERT` | Authenticated | `has_profile_role(company_id, ARRAY['owner','admin','accountant','manager','data_entry'])` | System appends audit trail on every voucher mutation. |
| | `UPDATE`/`DELETE` | Authenticated | `FALSE` | **Strictly Forbidden:** Audit trail is immutable by statute. |

---

## 4. Storage Bucket Authorization Matrix (`ledgerpulse_storage`)

Supabase Storage policies on `storage.objects` mirror workspace isolation:

```sql
-- 1. SELECT (Download/Read): User must have active membership in the profile path
CREATE POLICY "tenant_storage_read" ON storage.objects
FOR SELECT TO authenticated
USING (
    bucket_id = 'ledgerpulse_storage'
    AND (
        -- User's personal avatar folder
        (storage.foldername(name))[1] = 'users' AND (storage.foldername(name))[2] = auth.uid()::text
        OR
        -- Profile folder matching membership
        (storage.foldername(name))[1] = 'profiles' AND public.has_profile_role((storage.foldername(name))[2], ARRAY['owner','admin','accountant','manager','data_entry','viewer'])
    )
);

-- 2. INSERT (Upload): User must have editing role in target profile
CREATE POLICY "tenant_storage_upload" ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
    bucket_id = 'ledgerpulse_storage'
    AND (
        (storage.foldername(name))[1] = 'users' AND (storage.foldername(name))[2] = auth.uid()::text
        OR
        (storage.foldername(name))[1] = 'profiles' AND public.has_profile_role((storage.foldername(name))[2], ARRAY['owner','admin','accountant','manager','data_entry'])
    )
);

-- 3. DELETE (Purge): Restricted to Owner and Admin
CREATE POLICY "tenant_storage_delete" ON storage.objects
FOR DELETE TO authenticated
USING (
    bucket_id = 'ledgerpulse_storage'
    AND (
        (storage.foldername(name))[1] = 'users' AND (storage.foldername(name))[2] = auth.uid()::text
        OR
        (storage.foldername(name))[1] = 'profiles' AND public.has_profile_role((storage.foldername(name))[2], ARRAY['owner','admin'])
    )
);
```

---
*End of Cloud Security & RLS Matrix Specification (`docs/architecture/rls-matrix.md`)*

