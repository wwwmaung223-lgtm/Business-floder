# Read-only RLS and Function ACL Snapshot
Date: 2026-11-21
Project: esoekjjwsbtuyjkrbnam
Environment: production metadata read only; no database changes made.

## Policy snapshot: observed permissive policy duplication

The following policy definitions were read from `pg_policies`. All listed policies are PERMISSIVE and target `authenticated`.

### products
- `Users manage own products`: ALL; USING and WITH CHECK compare `(select auth.uid())` to `user_id`.
- `products_select_own_v1`: SELECT; USING `auth.uid() = user_id`.
- `products_insert_own_v1`: INSERT; WITH CHECK `auth.uid() = user_id`.
- `products_update_own_v1`: UPDATE; USING and WITH CHECK `auth.uid() = user_id`.
- `products_delete_own_v1`: DELETE; USING `auth.uid() = user_id`.

### customers
- `Users manage own customers`: ALL; USING and WITH CHECK compare `(select auth.uid())` to `user_id`.
- Separate SELECT, INSERT, UPDATE, DELETE `customers_*_own_v1` policies repeat the same ownership rule using `auth.uid()`.

### orders
- `Users manage own orders`: ALL; USING and WITH CHECK compare `(select auth.uid())` to `user_id`.
- Separate SELECT, INSERT, UPDATE, DELETE `orders_*_own_v1` policies repeat the same ownership rule using `auth.uid()`.

### finance_records
- `Users manage own finance`: ALL; USING and WITH CHECK compare `(select auth.uid())` to `user_id`.
- Separate SELECT, INSERT, UPDATE, DELETE `finance_*_own` policies repeat the same ownership rule using `auth.uid()`.

### Other observed policies
- `ocr_notes`: separate own-row SELECT, INSERT, DELETE policies.
- `business_memberships`: `Owners read their team` SELECT policy checks `business_owner_id = auth.uid()`.
- `stock_movements`: `Users read own stock movements` SELECT policy checks `user_id = auth.uid()`.
- `order_items`: `Users read own order items` SELECT policy checks `user_id = auth.uid()`.
- `audit_logs`: `Users read own audit logs` SELECT policy checks `user_id = auth.uid()`.

## Security implication
PostgreSQL combines permissive policies with OR. The duplicate policies observed here do not currently broaden access beyond the same `user_id = auth.uid()` rule, but they create policy sprawl and make future changes dangerous. If a future tenant/role policy is added without removing or replacing the broad `ALL` policy, the old permissive policy may continue to authorize the operation. Replace the complete policy set for each affected table as one reviewed migration; do not merely append a new role policy.

## Function metadata snapshot

The following `public.northstar_*` functions were read from `pg_proc`:

| Function | SECURITY DEFINER | search_path | ACL snapshot |
|---|---:|---|---|
| northstar_accept_team_invites() | yes | public | postgres, authenticated |
| northstar_add_team_member(text,text) | yes | public | postgres, authenticated |
| northstar_adjust_stock(uuid,integer,text) | yes | public | postgres, authenticated |
| northstar_assign_free_plan() | yes | public | default ACL |
| northstar_create_pos_sale(uuid,integer,numeric,uuid,text,text,text) | yes | public | postgres, authenticated |
| northstar_current_business_owner_id() | yes | public | postgres, authenticated |
| northstar_current_team_role() | yes | public | postgres, authenticated |
| northstar_has_permission(text,text) | yes | public | postgres, authenticated |
| northstar_remove_team_member(uuid) | yes | public | postgres, authenticated |
| northstar_review_subscription_request(uuid,text,text) | yes | public | postgres, authenticated |

This metadata query does not prove each function body is safe. Each SECURITY DEFINER body still needs review for explicit `auth.uid()` checks, tenant scoping, authorization, input validation, safe object qualification, and intended execution grants. The `northstar_assign_free_plan()` function showed default ACL metadata and needs specific ACL inspection. The previously observed `handle_new_user()` trigger function also requires trigger/ACL review. Do not revoke function execution blindly: triggers and signup flows must be tested first.

## Implementation decisions
1. Do not add tenant-aware RLS yet. Current membership model and RPC assumptions are not sufficient for staff access.
2. Before role policies, settle the canonical business ownership model and multi-membership semantics.
3. Replace old and new policies atomically for each table, after writing an explicit role/action matrix.
4. Review every SECURITY DEFINER body and effective grants (including PUBLIC inheritance) before changing ACLs.
5. Test signup, invite acceptance, role changes, suspension/removal, POS sale, stock adjustment, and cross-tenant denial with synthetic users in a free local-compatible environment.
6. No production DDL until the migration has passed those tests and the owner explicitly approves rollout.

## Verification status
- Metadata query against production: completed, read-only.
- Policy/function definitions changed: no.
- Database integration tests: NOT RUN.
- Production deployment: NOT PERFORMED.
