-- A null category represents the overall budget covering all expense categories.
-- Category-specific budgets retain their existing foreign-key validation.
ALTER TABLE public.exp_budgets ALTER COLUMN category_id DROP NOT NULL;
