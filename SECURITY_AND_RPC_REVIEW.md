# Security and RPC Review — 2026-11-21

Project: Northstar Business OS
Branch: security/rls-permissions-hardening
Scope: read-only production review; no SQL, Storage, Auth, or deployment changes made.

## Executive summary

The current schema has RLS enabled on the application tables reviewed, and most customer-owned records are scoped to `auth.uid()`. This is a useful baseline, but the current role/membership model is not yet a complete multi-user tenant authorization system. The highest-priority gaps are RPC authorization consistency, broad/overlapping RLS policies, incomplete lifecycle controls for OCR notes and team memberships, and subscription approval semantics.

## Freshly verified findings

### 1. RLS policy coverage and overlaps

- `products`, `customers`, `orders`, and `finance_records` each have a broad authenticated `FOR ALL` owner policy plus command-specific owner policies. PostgreSQL permissive policies combine with OR semantics, so the broad policy makes the narrower duplicates redundant. This is not by itself a cross-user leak because the predicates remain owner-scoped, but it complicates future hardening and policy review.
- `ocr_notes` has owner-scoped INSERT, SELECT, DELETE policies, but no UPDATE policy. If users need to correct saved OCR text, that action currently has no matching RLS policy.
- `business_memberships` has only an owner SELECT policy in the current policy inventory. Team membership writes are routed through SECURITY DEFINER functions; this needs a deliberate function-only write model and tests.
- `order_items` and `stock_movements` expose owner-scoped SELECT policies only. Writes are intended to occur through server-side functions, which should be confirmed against the frontend flow.
- `audit_logs` has owner-scoped SELECT only, consistent with append-only intent.
- `subscription_requests` and `subscriptions` each have a broad platform owner/admin ALL policy based on `app_metadata.role`, plus customer-specific INSERT/SELECT rules where applicable. Keep platform-admin privileges server-controlled; never let user-editable metadata grant this role.

### 2. SECURITY DEFINER function review

Fresh function-definition inspection found these behaviors:

- `northstar_create_pos_sale` is transactional and creates an order, order item, stock deduction, stock movement, and audit log. It checks the caller owns the product/customer and validates quantity, price non-negativity, payment method, and status. However:
  - caller-supplied `p_unit_price` is trusted instead of reading the product's authoritative selling price;
  - pending sales still deduct stock;
  - there is no idempotency key to prevent duplicate sales on retry;
  - no explicit role/permission check is made through `northstar_has_permission`.
- `northstar_adjust_stock` locks the product and records stock movement/audit data, but only checks ownership and authentication; it does not call the role permission helper.
- `northstar_add_team_member` checks authentication, email format, role allowlist, subscription staff limit, and inserts under the caller's owner ID. Validate duplicate invite behavior, concurrent limit races, and whether an already removed member can be reactivated safely.
- `northstar_accept_team_invites` activates every pending invitation matching the authenticated user's email. Test case-insensitive matching, multiple invitations from different owners, and email-change behavior.
- `northstar_remove_team_member` scopes removal to `business_owner_id = auth.uid()`.
- `northstar_has_permission` is a role matrix helper, but the reviewed POS and stock RPC definitions do not call it. Therefore the helper does not itself enforce permissions on those RPC entry points.
- `northstar_review_subscription_request` requires a payment reference for both approve and reject, stores that reference in the generic `note` field, and always sets subscription end to one month. It does not use a stored amount/currency/billing-period snapshot. Do not use this as an automatic payment confirmation mechanism.

### 3. Function execution ACLs

The read-only ACL inventory shows authenticated EXECUTE grants for the `northstar_*` team, stock, POS, and subscription-review functions. The two auth-trigger functions `handle_new_user` and `northstar_assign_free_plan` show default ACLs. Before changing any function grants, identify which are trigger-only, inspect trigger bindings, and test signup/plan assignment in an isolated disposable environment. Do not blindly revoke or alter production function privileges.

### 4. Subscription/payment model is not ready for automated activation

The existing `subscription_requests` table does not contain immutable amount, currency, billing period, payment method, transaction reference, receipt object key, or verification status fields. A generic note field is not an auditable payment ledger. Until a trusted recipient-side KPay confirmation source is available, receipt OCR and AI fraud scoring must only create a review signal; they must not activate a paid subscription.

## Recommended implementation order (not yet applied)

1. Build disposable-user authorization tests for owner A, owner B, invited member, active member in each role, suspended member, and anonymous caller.
2. Add explicit permission checks inside each privileged RPC, including owner-vs-team-member resolution, before allowing any data mutation. Keep tenant identity anchored to the business owner, not the member's own `auth.uid()`.
3. Define one canonical RLS policy per operation. Remove broad duplicates only in a reviewed migration after confirming all application paths and service roles.
4. Decide whether OCR notes are immutable. If editable, add a narrowly scoped owner UPDATE policy; if immutable, keep no UPDATE and expose an explicit delete/recreate correction flow.
5. Make POS sale price authoritative from the product record or a server-validated price override with an audit reason; add idempotency; decide whether pending orders reserve stock or deduct only on completion.
6. Replace subscription approval's generic note-based reference with a payment-intent/ledger model containing immutable plan, amount, currency, billing period, unique transaction reference, receipt object key, review trail, and idempotent activation.
7. Restrict trigger-only function execution only after trigger dependencies and signup regression tests are verified.
8. Add Storage API bucket remediation from `STORAGE_BUCKET_REMEDIATION_PLAN.md`; preserve the existing misspelled bucket and its two objects until migration is separately tested.

## Required acceptance tests

- Anonymous callers cannot read or mutate private business data or execute privileged mutations.
- User A cannot read or mutate User B's rows, including through every RPC.
- A team member can only act within their owner tenant and only for explicitly allowed role/action pairs.
- Suspended/removed members lose access immediately.
- Duplicate POS submission with the same idempotency key creates exactly one order and one stock movement.
- Pending-vs-completed stock behavior is consistent and documented.
- Subscription approval is idempotent, uses the selected plan's exact billing period, and cannot be triggered by OCR/AI output alone.
- OCR data is only visible to its owner; correction/deletion behavior is explicitly tested.

## Change boundary

This file records findings and a safe remediation plan only. It does not authorize production SQL, RLS, function, Storage, billing, or deployment changes.
