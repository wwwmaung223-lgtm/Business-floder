-- Remove redundant command-specific policies that duplicate each table's
-- existing owner-scoped ALL policy. PostgreSQL permissive policies are ORed;
-- these policies add no access beyond the ALL policy and cause repeated policy
-- evaluation (Supabase Advisor multiple_permissive_policies/auth_rls_initplan).
--
-- Verified before drafting:
--   products: "Users manage own products" has matching owner USING/WITH CHECK.
--   customers: "Users manage own customers" has matching owner USING/WITH CHECK.
--   orders: "Users manage own orders" has matching owner USING/WITH CHECK.
--   finance_records: "Users manage own finance" has matching owner USING/WITH CHECK.
--
-- Keep the ALL policies intact. This does not introduce staff/tenant access;
-- the current user_id = auth.uid() ownership boundary remains unchanged.

DROP POLICY IF EXISTS products_delete_own_v1 ON public.products;
DROP POLICY IF EXISTS products_insert_own_v1 ON public.products;
DROP POLICY IF EXISTS products_select_own_v1 ON public.products;
DROP POLICY IF EXISTS products_update_own_v1 ON public.products;

DROP POLICY IF EXISTS customers_delete_own_v1 ON public.customers;
DROP POLICY IF EXISTS customers_insert_own_v1 ON public.customers;
DROP POLICY IF EXISTS customers_select_own_v1 ON public.customers;
DROP POLICY IF EXISTS customers_update_own_v1 ON public.customers;

DROP POLICY IF EXISTS orders_delete_own_v1 ON public.orders;
DROP POLICY IF EXISTS orders_insert_own_v1 ON public.orders;
DROP POLICY IF EXISTS orders_select_own_v1 ON public.orders;
DROP POLICY IF EXISTS orders_update_own_v1 ON public.orders;

DROP POLICY IF EXISTS finance_delete_own ON public.finance_records;
DROP POLICY IF EXISTS finance_insert_own ON public.finance_records;
DROP POLICY IF EXISTS finance_select_own ON public.finance_records;
DROP POLICY IF EXISTS finance_update_own ON public.finance_records;
