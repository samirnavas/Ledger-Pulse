-- ====================================================================
-- SUPABASE MIGRATION 0012: TARGET RPCS, IDEMPOTENT PROVISIONING & SYNC MUTATION V3
-- Target: LedgerPulse Supabase / PostgreSQL
-- Contract Version: v1.0.0-PROD-CONTRACT-20261106
-- ====================================================================

-- --------------------------------------------------------------------
-- 1. TRANSACTIONAL & IDEMPOTENT PROFILE CREATION RPC
-- --------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.create_workspace_profile(
    p_name TEXT,
    p_profile_type TEXT,
    p_currency_code TEXT DEFAULT 'INR',
    p_legal_name TEXT DEFAULT NULL,
    p_gstin TEXT DEFAULT NULL,
    p_custom_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_user_id UUID;
    v_profile_id TEXT;
    v_existing_owner UUID;
    v_profile_type TEXT;
    v_legal_name TEXT;
    v_currency TEXT;
BEGIN
    -- 1. Verify caller authentication strictly server-side
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required: auth.uid() is null.';
    END IF;

    -- 2. Validate Profile Type
    v_profile_type := LOWER(TRIM(p_profile_type));
    IF v_profile_type NOT IN ('expense', 'ledger') THEN
        RAISE EXCEPTION 'Invalid profile_type "%". Must be "expense" or "ledger".', p_profile_type;
    END IF;

    -- 3. Determine profile identifier
    IF p_custom_id IS NOT NULL AND TRIM(p_custom_id) <> '' THEN
        v_profile_id := TRIM(p_custom_id);
    ELSE
        v_profile_id := 'prf_' || replace(gen_random_uuid()::text, '-', '');
    END IF;

    v_legal_name := COALESCE(NULLIF(TRIM(p_legal_name), ''), TRIM(p_name));
    v_currency := UPPER(COALESCE(NULLIF(TRIM(p_currency_code), ''), 'INR'));

    -- 4. Check if profile already exists (Idempotent retry guard)
    SELECT owner_id INTO v_existing_owner
    FROM public.companies
    WHERE id = v_profile_id;

    IF v_existing_owner IS NOT NULL THEN
        IF v_existing_owner = v_user_id OR EXISTS (
            SELECT 1 FROM public.shared_memberships
            WHERE profile_id = v_profile_id AND account_id = v_user_id AND role = 'owner'
        ) THEN
            -- Already exists and belongs to caller: return existing without duplicate creation
            RETURN jsonb_build_object(
                'success', true,
                'action', 'retrieved_existing',
                'profile_id', v_profile_id,
                'profile_type', v_profile_type,
                'name', p_name
            );
        ELSE
            RAISE EXCEPTION 'Profile ID "%" already exists and is owned by another account.', v_profile_id;
        END IF;
    END IF;

    -- 5. Insert Workspace Profile into companies
    INSERT INTO public.companies (
        id, name, legal_name, mode, owner_id, currency_code, gstin,
        is_cloud_sync_enabled, is_active, is_deleted, revision, created_at, updated_at
    ) VALUES (
        v_profile_id, TRIM(p_name), v_legal_name, v_profile_type, v_user_id, v_currency, NULLIF(TRIM(p_gstin), ''),
        true, true, false, 0, NOW(), NOW()
    );

    -- 6. Insert Owner Membership
    INSERT INTO public.shared_memberships (
        profile_id, account_id, role, joined_at, updated_at
    ) VALUES (
        v_profile_id, v_user_id, 'owner', NOW(), NOW()
    )
    ON CONFLICT (profile_id, account_id) DO UPDATE SET role = 'owner';

    -- 7. Provision Domain Defaults Idempotently
    IF v_profile_type = 'expense' THEN
        -- Seed Default Wallets
        INSERT INTO public.exp_wallets (
            id, profile_id, name, wallet_type, currency_code, starting_balance_in_cents, current_balance_in_cents, color_hex, icon_name, is_archived, is_deleted, revision, created_at, updated_at
        ) VALUES
            (v_profile_id || '_wal_cash', v_profile_id, 'Cash in Hand', 'cash', v_currency, 0, 0, '#006C4C', 'payments', false, false, 0, NOW(), NOW()),
            (v_profile_id || '_wal_bank', v_profile_id, 'Bank Account', 'bank', v_currency, 0, 0, '#005AC1', 'account_balance', false, false, 0, NOW(), NOW())
        ON CONFLICT (id) DO NOTHING;

        -- Seed Default Categories
        INSERT INTO public.exp_categories (
            id, profile_id, name, category_type, is_system, is_deleted, revision, created_at, updated_at
        ) VALUES
            (v_profile_id || '_cat_food', v_profile_id, 'Food & Dining', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_groceries', v_profile_id, 'Groceries', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_utilities', v_profile_id, 'Utilities & Bills', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_transport', v_profile_id, 'Transportation', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_rent', v_profile_id, 'Rent & Housing', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_shopping', v_profile_id, 'Shopping', 'expense', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_salary', v_profile_id, 'Salary', 'income', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_freelance', v_profile_id, 'Freelance / Business', 'income', true, false, 0, NOW(), NOW()),
            (v_profile_id || '_cat_investments', v_profile_id, 'Investments', 'income', true, false, 0, NOW(), NOW())
        ON CONFLICT (id) DO NOTHING;

    ELSIF v_profile_type = 'ledger' THEN
        -- Seed Standard Indian Chart of Accounts
        INSERT INTO public.accounts (
            id, company_id, code, name, type, kind, is_system, is_active, current_balance_in_cents, is_deleted, revision, created_at, updated_at
        ) VALUES
            (v_profile_id || '_acc_cash', v_profile_id, '1001', 'Cash in Hand', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_bank', v_profile_id, '1002', 'Bank Account', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_debtors', v_profile_id, '1003', 'Sundry Debtors', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_cgst_in', v_profile_id, '1004', 'Input CGST', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_sgst_in', v_profile_id, '1005', 'Input SGST', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_igst_in', v_profile_id, '1006', 'Input IGST', 'asset', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_creditors', v_profile_id, '2001', 'Sundry Creditors', 'liability', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_cgst_out', v_profile_id, '2002', 'Output CGST', 'liability', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_sgst_out', v_profile_id, '2003', 'Output SGST', 'liability', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_igst_out', v_profile_id, '2004', 'Output IGST', 'liability', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_sales', v_profile_id, '3001', 'Sales Account', 'income', 'system', true, true, 0, false, 0, NOW(), NOW()),
            (v_profile_id || '_acc_purchases', v_profile_id, '4001', 'Purchase Account', 'expense', 'system', true, true, 0, false, 0, NOW(), NOW())
        ON CONFLICT (id) DO NOTHING;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'action', 'created_new',
        'profile_id', v_profile_id,
        'profile_type', v_profile_type,
        'name', p_name
    );
END;
$function$;

-- Revoke default public execution; grant to authenticated users
REVOKE EXECUTE ON FUNCTION public.create_workspace_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_workspace_profile(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- --------------------------------------------------------------------
-- 2. PROFILE MEMBER INVITATION RPC
-- --------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.invite_profile_member(
    p_profile_id TEXT,
    p_email TEXT,
    p_role TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_caller_id UUID;
    v_target_user_id UUID;
    v_role TEXT;
BEGIN
    v_caller_id := auth.uid();
    IF v_caller_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    -- Verify caller has owner or admin role in profile
    IF NOT public.has_profile_role(p_profile_id, ARRAY['owner', 'admin']) THEN
        RAISE EXCEPTION 'Permission denied: Only Owners and Admins can invite members to profile %.', p_profile_id;
    END IF;

    v_role := LOWER(TRIM(p_role));
    IF v_role NOT IN ('owner', 'admin', 'accountant', 'manager', 'data_entry', 'viewer') THEN
        RAISE EXCEPTION 'Invalid role: %', p_role;
    END IF;

    -- Look up target user in auth.users by email
    SELECT id INTO v_target_user_id
    FROM auth.users
    WHERE LOWER(email) = LOWER(TRIM(p_email));

    IF v_target_user_id IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'USER_NOT_FOUND',
            'message', 'No registered account found with that email address.'
        );
    END IF;

    -- Insert or update membership
    INSERT INTO public.shared_memberships (
        profile_id, account_id, role, joined_at, updated_at
    ) VALUES (
        p_profile_id, v_target_user_id, v_role, NOW(), NOW()
    )
    ON CONFLICT (profile_id, account_id) DO UPDATE
    SET role = EXCLUDED.role, updated_at = NOW();

    RETURN jsonb_build_object(
        'success', true,
        'profile_id', p_profile_id,
        'account_id', v_target_user_id,
        'role', v_role
    );
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.invite_profile_member(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.invite_profile_member(TEXT, TEXT, TEXT) TO authenticated;


-- --------------------------------------------------------------------
-- 3. SECURE SYNC MUTATION RPC V3 (ALLOWLISTED, OCC, DOMAIN-AWARE)
-- --------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.sync_mutation_v3(
    p_target_table TEXT,
    p_record_id TEXT,
    p_mutation_type TEXT,
    p_payload JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    v_user_id UUID;
    v_profile_id TEXT;
    v_profile_type TEXT;
    v_table TEXT;
    v_type TEXT;
    v_now TIMESTAMPTZ := NOW();
    v_incoming_rev BIGINT;
    v_remote_rev BIGINT;
    v_remote_status TEXT;
BEGIN
    -- 1. Caller authentication
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    -- 2. Explicit Allowlist Validation (NEVER trust or concatenate arbitrary table names)
    v_table := LOWER(TRIM(p_target_table));
    IF v_table NOT IN (
        'companies', 'user_profiles', 'shared_memberships', 'shared_devices',
        'exp_wallets', 'exp_categories', 'exp_transactions', 'exp_budgets', 'exp_recurring_rules',
        'accounts', 'parties', 'vouchers', 'journals', 'journal_lines', 'ledger_entries',
        'inventory_items', 'stock_ledger', 'audit_logs'
    ) THEN
        RAISE EXCEPTION 'Table "%" is not in the authorized sync allowlist.', p_target_table;
    END IF;

    v_type := UPPER(TRIM(p_mutation_type));
    IF v_type NOT IN ('INSERT', 'UPDATE', 'UPSERT', 'DELETE') THEN
        RAISE EXCEPTION 'Invalid mutation type: %', p_mutation_type;
    END IF;

    -- 3. Extract profile identifier
    v_profile_id := COALESCE(
        p_payload->>'profile_id',
        p_payload->>'profileId',
        p_payload->>'company_id',
        p_payload->>'companyId'
    );

    -- 4. Authorize caller for profile-scoped tables
    IF v_table NOT IN ('user_profiles', 'shared_devices') THEN
        IF v_profile_id IS NULL OR v_profile_id = '' THEN
            RAISE EXCEPTION 'Sync mutation payload for table % must specify profile_id or company_id.', v_table;
        END IF;

        IF NOT public.has_profile_role(v_profile_id, ARRAY['owner', 'admin', 'accountant', 'manager', 'data_entry']) THEN
            RAISE EXCEPTION 'Permission denied: Account % has no mutation authorization in profile %.', v_user_id, v_profile_id;
        END IF;

        v_profile_type := public.get_profile_type(v_profile_id);

        -- Validate Domain Isolation
        IF v_table LIKE 'exp_%' AND v_profile_type NOT IN ('expense', 'expenseTracker') THEN
            RAISE EXCEPTION 'Domain Violation: Table % belongs to Expense domain, but profile % is "%"', v_table, v_profile_id, v_profile_type;
        END IF;

        IF v_table IN ('accounts', 'parties', 'vouchers', 'journals', 'journal_lines', 'ledger_entries', 'inventory_items', 'stock_ledger') AND v_profile_type <> 'ledger' THEN
            RAISE EXCEPTION 'Domain Violation: Table % belongs to Ledger domain, but profile % is "%"', v_table, v_profile_id, v_profile_type;
        END IF;
    END IF;

    -- 5. Optimistic Concurrency Control (OCC) for Ledger Posted Records
    IF v_table IN ('vouchers', 'journals') THEN
        v_incoming_rev := COALESCE((p_payload->>'revision')::BIGINT, 0);

        IF v_table = 'vouchers' THEN
            SELECT revision, status INTO v_remote_rev, v_remote_status FROM public.vouchers WHERE id = p_record_id;
        ELSIF v_table = 'journals' THEN
            SELECT revision, status INTO v_remote_rev, v_remote_status FROM public.journals WHERE id = p_record_id;
        END IF;

        IF v_remote_status = 'posted' AND v_remote_rev IS NOT NULL AND v_remote_rev > v_incoming_rev THEN
            RAISE EXCEPTION 'OCC Conflict: Remote posted % % has higher revision (%) than incoming (%). Silent overwrite rejected.',
                v_table, p_record_id, v_remote_rev, v_incoming_rev;
        END IF;
    END IF;

    -- 6. Execute Mutation safely per allowlisted table
    IF v_type = 'DELETE' THEN
        -- Standard Soft Delete across allowlisted tables
        IF v_table = 'exp_transactions' THEN
            UPDATE public.exp_transactions SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'exp_wallets' THEN
            UPDATE public.exp_wallets SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'exp_categories' THEN
            UPDATE public.exp_categories SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'exp_budgets' THEN
            UPDATE public.exp_budgets SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'exp_recurring_rules' THEN
            UPDATE public.exp_recurring_rules SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'vouchers' THEN
            UPDATE public.vouchers SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'journals' THEN
            UPDATE public.journals SET is_deleted = true, status = 'voided', updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'journal_lines' THEN
            UPDATE public.journal_lines SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'accounts' THEN
            UPDATE public.accounts SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'parties' THEN
            UPDATE public.parties SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'ledger_entries' THEN
            UPDATE public.ledger_entries SET is_deleted = true, is_voided = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'inventory_items' THEN
            UPDATE public.inventory_items SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'stock_ledger' THEN
            UPDATE public.stock_ledger SET is_deleted = true, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        ELSIF v_table = 'companies' THEN
            UPDATE public.companies SET is_deleted = true, is_active = false, updated_at = v_now, revision = revision + 1 WHERE id = p_record_id;
        END IF;

        RETURN jsonb_build_object('success', true, 'record_id', p_record_id, 'action', 'soft_deleted');
    ELSE
        -- Specific Upsert logic for Expense Transactions
        IF v_table = 'exp_transactions' THEN
            INSERT INTO public.exp_transactions (
                id, profile_id, transaction_type, amount_in_cents, wallet_id, to_wallet_id, category_id,
                transaction_date, note, payee_or_payer, reference_number, receipt_photo_url,
                is_cleared, is_deleted, revision, created_at, updated_at
            ) VALUES (
                p_record_id,
                v_profile_id,
                COALESCE(p_payload->>'transaction_type', p_payload->>'transactionType', 'expense'),
                COALESCE((p_payload->>'amount_in_cents')::BIGINT, (p_payload->>'amountInCents')::BIGINT, 0),
                COALESCE(p_payload->>'wallet_id', p_payload->>'walletId'),
                COALESCE(p_payload->>'to_wallet_id', p_payload->>'toWalletId'),
                COALESCE(p_payload->>'category_id', p_payload->>'categoryId'),
                COALESCE((p_payload->>'transaction_date')::TIMESTAMPTZ, (p_payload->>'transactionDate')::TIMESTAMPTZ, v_now),
                p_payload->>'note',
                COALESCE(p_payload->>'payee_or_payer', p_payload->>'payeeOrPayer'),
                COALESCE(p_payload->>'reference_number', p_payload->>'referenceNumber'),
                COALESCE(p_payload->>'receipt_photo_url', p_payload->>'receiptPhotoUrl'),
                COALESCE((p_payload->>'is_cleared')::BOOLEAN, (p_payload->>'isCleared')::BOOLEAN, true),
                COALESCE((p_payload->>'is_deleted')::BOOLEAN, (p_payload->>'isDeleted')::BOOLEAN, false),
                COALESCE((p_payload->>'revision')::BIGINT, 0),
                COALESCE((p_payload->>'created_at')::TIMESTAMPTZ, (p_payload->>'createdAt')::TIMESTAMPTZ, v_now),
                v_now
            )
            ON CONFLICT (id) DO UPDATE SET
                transaction_type = EXCLUDED.transaction_type,
                amount_in_cents = EXCLUDED.amount_in_cents,
                wallet_id = EXCLUDED.wallet_id,
                to_wallet_id = EXCLUDED.to_wallet_id,
                category_id = EXCLUDED.category_id,
                transaction_date = EXCLUDED.transaction_date,
                note = EXCLUDED.note,
                payee_or_payer = EXCLUDED.payee_or_payer,
                reference_number = EXCLUDED.reference_number,
                receipt_photo_url = EXCLUDED.receipt_photo_url,
                is_cleared = EXCLUDED.is_cleared,
                is_deleted = EXCLUDED.is_deleted,
                revision = EXCLUDED.revision,
                updated_at = v_now;

        -- Expense Wallets
        ELSIF v_table = 'exp_wallets' THEN
            INSERT INTO public.exp_wallets (
                id, profile_id, name, wallet_type, currency_code, starting_balance_in_cents, current_balance_in_cents,
                color_hex, icon_name, is_archived, is_deleted, revision, created_at, updated_at
            ) VALUES (
                p_record_id,
                v_profile_id,
                COALESCE(p_payload->>'name', 'Wallet'),
                COALESCE(p_payload->>'wallet_type', p_payload->>'walletType', 'cash'),
                COALESCE(p_payload->>'currency_code', p_payload->>'currencyCode', 'INR'),
                COALESCE((p_payload->>'starting_balance_in_cents')::BIGINT, (p_payload->>'startingBalanceInCents')::BIGINT, 0),
                COALESCE((p_payload->>'current_balance_in_cents')::BIGINT, (p_payload->>'currentBalanceInCents')::BIGINT, 0),
                COALESCE(p_payload->>'color_hex', p_payload->>'colorHex'),
                COALESCE(p_payload->>'icon_name', p_payload->>'iconName'),
                COALESCE((p_payload->>'is_archived')::BOOLEAN, (p_payload->>'isArchived')::BOOLEAN, false),
                COALESCE((p_payload->>'is_deleted')::BOOLEAN, (p_payload->>'isDeleted')::BOOLEAN, false),
                COALESCE((p_payload->>'revision')::BIGINT, 0),
                COALESCE((p_payload->>'created_at')::TIMESTAMPTZ, (p_payload->>'createdAt')::TIMESTAMPTZ, v_now),
                v_now
            )
            ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                wallet_type = EXCLUDED.wallet_type,
                currency_code = EXCLUDED.currency_code,
                starting_balance_in_cents = EXCLUDED.starting_balance_in_cents,
                current_balance_in_cents = EXCLUDED.current_balance_in_cents,
                color_hex = EXCLUDED.color_hex,
                icon_name = EXCLUDED.icon_name,
                is_archived = EXCLUDED.is_archived,
                is_deleted = EXCLUDED.is_deleted,
                revision = EXCLUDED.revision,
                updated_at = v_now;

        -- Expense Categories
        ELSIF v_table = 'exp_categories' THEN
            INSERT INTO public.exp_categories (
                id, profile_id, name, category_type, parent_category_id, icon_name, color_hex,
                is_system, is_deleted, revision, created_at, updated_at
            ) VALUES (
                p_record_id,
                v_profile_id,
                COALESCE(p_payload->>'name', 'Category'),
                COALESCE(p_payload->>'category_type', p_payload->>'categoryType', 'expense'),
                COALESCE(p_payload->>'parent_category_id', p_payload->>'parentCategoryId'),
                COALESCE(p_payload->>'icon_name', p_payload->>'iconName'),
                COALESCE(p_payload->>'color_hex', p_payload->>'colorHex'),
                COALESCE((p_payload->>'is_system')::BOOLEAN, (p_payload->>'isSystem')::BOOLEAN, false),
                COALESCE((p_payload->>'is_deleted')::BOOLEAN, (p_payload->>'isDeleted')::BOOLEAN, false),
                COALESCE((p_payload->>'revision')::BIGINT, 0),
                COALESCE((p_payload->>'created_at')::TIMESTAMPTZ, (p_payload->>'createdAt')::TIMESTAMPTZ, v_now),
                v_now
            )
            ON CONFLICT (id) DO UPDATE SET
                name = EXCLUDED.name,
                category_type = EXCLUDED.category_type,
                parent_category_id = EXCLUDED.parent_category_id,
                icon_name = EXCLUDED.icon_name,
                color_hex = EXCLUDED.color_hex,
                is_deleted = EXCLUDED.is_deleted,
                revision = EXCLUDED.revision,
                updated_at = v_now;

        -- Fallback to standard 0008 handler for legacy tables
        ELSE
            PERFORM public.sync_mutation(v_table, p_record_id, v_type, p_payload);
        END IF;

        RETURN jsonb_build_object('success', true, 'record_id', p_record_id, 'action', 'upserted', 'table', v_table);
    END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.sync_mutation_v3(TEXT, TEXT, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_mutation_v3(TEXT, TEXT, TEXT, JSONB) TO authenticated;

