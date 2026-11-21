# Northstar Business OS — Verified Security Audit Findings

Audit date: 2026-11-21 (UTC)
Environment: production database, read-only inspection only
Branch: security/rls-permissions-hardening

## No changes made

No production DDL, data writes, storage changes, website deployment, or main-branch changes were performed during this audit.

## 1. Authentication and SECURITY DEFINER functions

The following two trigger functions are reported by Supabase Security Advisor as executable by anon and authenticated because they retain default function ACLs:

- `public.handle_new_user()` — SECURITY DEFINER, owner postgres, empty search_path, trigger `on_auth_user_created` on `auth.users`.
- `public.northstar_assign_free_plan()` — SECURITY DEFINER, owner postgres, search_path public, trigger `northstar_new_user_free_plan` on `auth.users`.

Both are trigger-returning functions and should not be exposed as callable RPC endpoints. A proposed migration should revoke EXECUTE from PUBLIC, anon, and authenticated while preserving trigger invocation; verify with a test signup on staging.

Other SECURITY DEFINER functions have explicit ACLs granting authenticated (and postgres), not anon:
- `northstar_accept_team_invites()`
- `northstar_add_team_member(text,text)`
- `northstar_adjust_stock(uuid,integer,text)`
- `northstar_create_pos_sale(uuid,integer,numeric,uuid,text,text,text)`
- `northstar_current_business_owner_id()`
- `northstar_current_team_role()`
- `northstar_has_permission(text,text)`
- `northstar_remove_team_member(uuid)`
- `northstar_review_subscription_request(uuid,text,text)`

These functions need a per-function review, not blanket revocation. The subscription review RPC checks `auth.jwt()->'app_metadata'->>'role'` for owner/admin. The POS and stock RPCs check authentication and current user ownership but still assume the caller owns the records.

## 2. Team authorization gap

- `northstar_has_permission(feature, action)` defines role permissions but no current public RLS policy calls it.
- Main business tables use `user_id` ownership.
- `northstar_current_business_owner_id()` picks the earliest active membership and falls back to `auth.uid()`; multiple active memberships can make the selected business ambiguous.
- A user with only removed/suspended memberships may fall back to their own user ID in the owner helper. This needs explicit semantics before it is used in RLS.
- The current POS and stock adjustment RPCs query products with `user_id = auth.uid()`, so staff cannot safely operate on owner-owned products through these RPCs.
- Membership table currently has zero rows, so no existing staff membership data was found at audit time.

## 3. RLS policy design risk

The `products`, `customers`, `orders`, and `finance_records` tables have broad permissive ALL policies alongside command-specific policies. PostgreSQL permissive policies are OR-combined. Adding new role-aware policies without removing/replacing the old broad policies would not enforce the intended restrictions.

The migration must replace the complete policy set on affected tables as a coordinated change and include explicit USING and WITH CHECK predicates for UPDATE.

## 4. Storage bucket mismatch

Actual private buckets:
- `product images`
- `User Uplads` (exact ID/name, spelling as stored)

Frontend upload code targets `User Uploads`.
Storage object policies also target `User Uploads`, which does not match the existing bucket ID `User Uplads`.

All buckets inspected are private with a 10 MiB limit and image/jpeg, image/png, image/webp MIME types. Do not rename/delete buckets or objects until object counts, references, and backup/rollback behavior are verified. A safe fix may be to create the correctly named bucket and preserve the old one until migration is verified, or consistently update code/policies to the existing ID.

## 5. Constraints and data integrity

Existing constraints include:
- orders.customer_id + user_id composite FK to customers(id,user_id), which prevents cross-user customer references.
- order_items.order_id and product_id foreign keys are currently single-column relationships; tenant consistency should be enforced when staff/owner shared business scope is introduced.
- business_memberships role check permits manager, cashier, stock_staff, accountant; status check permits invited, active, suspended, removed.
- subscriptions has a unique user_id constraint.
- order_items quantity must be positive and unit_price/line_total nonnegative.

Before tenant migration, inspect every dependent FK and preserve existing rows.

## 6. Existing production data observed

Read-only counts at audit time:
- products: 1
- customers: 1
- orders: 2
- business_memberships: 0
- finance_records: 0

Counts are point-in-time observations, not guarantees about later data.

## 7. Required staging test matrix

1. Anonymous users cannot call private SECURITY DEFINER RPCs or read/write private tables.
2. Owner can CRUD their own business data.
3. Owner A cannot read or modify Owner B's data.
4. Cashier can create sales but cannot view finance or adjust stock outside allowed policy.
5. Stock Staff can view/adjust stock but cannot access finance or customer data beyond explicitly allowed scope.
6. Accountant can access finance/reports and permitted order data, but cannot modify products/stock.
7. Manager permissions match the agreed role matrix.
8. Suspended/removed memberships lose access immediately; ambiguous multi-business membership is handled explicitly.
9. POS transaction updates order, order_items, stock, stock_movements, and audit_logs atomically.
10. Cross-tenant order_items cannot reference another tenant's order/product.
11. Signup still creates profile and free subscription after trigger ACL hardening.
12. Upload works only in the intended private bucket and user folder; existing uploaded files remain accessible.
13. Rollback restores prior policies/functions without losing records.

## 8. Recommended next sequence

1. Create/confirm a staging Supabase project and clone schema/data safely (sanitize personal data).
2. Agree and document multi-business membership selection behavior.
3. Design a stable business-owner/tenant key across all business tables and dependent RPCs.
4. Draft a single coordinated RLS/function/storage migration; do not apply it to production yet.
5. Execute staging tests and advisor checks.
6. Open a draft PR for review; merge and production rollout only after explicit approval and backup/rollback readiness.
