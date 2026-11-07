-- Rollback for Migration 0014
DROP POLICY IF EXISTS "usr_profile_select" ON public.user_profiles;
DROP POLICY IF EXISTS "usr_profile_insert" ON public.user_profiles;
DROP POLICY IF EXISTS "usr_profile_update" ON public.user_profiles;
DROP POLICY IF EXISTS "led_budgets_select" ON public.budgets;
DROP POLICY IF EXISTS "led_budgets_write" ON public.budgets;
DROP POLICY IF EXISTS "led_recurring_select" ON public.recurring_rules;
DROP POLICY IF EXISTS "led_recurring_write" ON public.recurring_rules;

