# SECURITY DEFINER RPC Body Review
Date: 2026-11-21
Source: read-only `pg_get_functiondef` inspection of production functions in `public`.
No database changes were made.

## Key findings

### RPC-01 — Membership selection is ambiguous for users in multiple businesses (High)
Functions:
- `northstar_current_business_owner_id()`
- `northstar_current_team_role()`
- `northstar_has_permission(text,text)`

Observed behavior:
- Current owner helper selects the earliest-created active membership for the signed-in member and returns only one owner ID.
- Current role helper similarly selects one role by earliest `created_at`.
- Permission helper delegates to that single selected role.
- If one user belongs to multiple businesses, these helpers do not accept a business identifier and may apply the wrong business's role to a request.
- If no membership is found, owner helper falls back to `auth.uid()`.

Impact:
- A future tenant-aware RLS policy or RPC built on these helpers could accidentally scope access to the wrong business or produce inconsistent permissions. Current memberships were previously observed empty, so this is a design blocker rather than a reproduced cross-tenant exploit.

Required fix:
- Make business context explicit and validate that the signed-in user has an active membership for that exact business on every request.
- Avoid arbitrary `ORDER BY created_at LIMIT 1` as a tenant selector.
- Define behavior for zero, one, and multiple active memberships, including suspended/removed memberships.
- Test with a synthetic user who is an active member of two separate businesses with different roles.

### RPC-02 — POS and stock adjustment RPCs are owner-user scoped, not tenant scoped (High for staff support)
Functions:
- `northstar_create_pos_sale(...)`
- `northstar_adjust_stock(uuid,integer,text)`

Observed behavior:
- Both require `auth.uid()`.
- POS selects the product and optional customer only where `user_id = auth.uid()`.
- POS writes order, order item, stock movement, and audit log with `user_id = auth.uid()` and `created_by = auth.uid()`.
- Stock adjustment selects/updates product where `user_id = auth.uid()` and writes stock/audit rows under the signed-in user's ID.

Impact:
- Staff members cannot safely operate on the owner's records using the current RPC implementation. Simply relaxing frontend checks or adding broad RLS policies would not solve this.

Required fix:
- After choosing the tenant model, take an explicit business ID (or resolve it through a single unambiguous validated context) and authorize the member's role for the operation.
- Derive business ownership server-side; never trust a client-supplied owner ID by itself.
- Record the authenticated staff user as actor/creator while associating records with the business tenant.
- Keep POS order + line item + stock deduction + stock movement + audit event atomic.

### RPC-03 — Team invitation lifecycle requires edge-case tests (Medium/High)
Functions:
- `northstar_add_team_member(text,text)`
- `northstar_accept_team_invites()`
- `northstar_remove_team_member(uuid)`

Observed behavior:
- Add-member checks authentication, email shape, allowed role values, self-invite, active subscription/plan staff limit, and inserts/updates a membership keyed by owner + member email.
- For an email already present in `auth.users`, the function sets the membership to active immediately and sets `member_user_id`; otherwise it creates an invited membership.
- Accept-invites updates every invited membership whose normalized email matches the authenticated user's email.
- Remove-member marks a membership removed only when its `business_owner_id` equals the caller.

Review items:
- Confirm whether immediate activation for an already registered email is intentional and how the member is notified/consents.
- Verify duplicate invites, case-insensitive email uniqueness, owner re-invites after removal, role changes, multiple-business invitations, and concurrent invite acceptance.
- Ensure membership reads/writes are constrained to the intended business and actor.
- Verify removed or suspended users lose access immediately, including through still-valid JWTs and already-open sessions.

### RPC-04 — Subscription review RPC has a server-side platform-role check (Positive control; still needs tests)
Function: `northstar_review_subscription_request(uuid,text,text)`

Observed behavior:
- Checks `auth.jwt()->'app_metadata'->>'role'` for `owner` or `admin`.
- Restricts decision to approve/reject and requires a payment reference.
- Locks a pending request row before updating it and, on approval, creates/updates a subscription.

Review items:
- Test unauthenticated and ordinary authenticated callers are rejected.
- Confirm only intended platform operators receive app_metadata role.
- Review whether payment reference should be stored as a note or in a dedicated field with audit history.

## SECURITY DEFINER and search_path
All inspected `northstar_*` functions are SECURITY DEFINER and set `search_path = public`. Object references in the inspected bodies are mostly schema-qualified as `public.*`; auth references use `auth.*`. This is a positive baseline, not a complete hardening guarantee. Review every function body for authorization, ownership/tenant scoping, input validation, and EXECUTE privileges. Do not blanket-revoke EXECUTE: some functions are called by authenticated users and auth triggers may require execution under trigger semantics.

The metadata snapshot showed `northstar_assign_free_plan()` with default ACL metadata. A separate earlier audit also found `handle_new_user()` with default ACL metadata. Inspect effective ACLs, including inherited PUBLIC grants, and test signup/trigger behavior before changing privileges.

## Required tests before any rollout
- Unauthenticated call to every RPC.
- Ordinary authenticated user calling owner/admin-only operations.
- Owner performing operations within own business.
- Staff performing only role-permitted operations in the correct business.
- Same staff user belonging to two businesses with different roles.
- Staff trying to access a third unrelated business.
- Suspended and removed member using a previously issued session.
- Duplicate and concurrent invitation acceptance.
- POS sale with valid/invalid customer, insufficient stock, and invalid quantity/price/status/payment method.
- Stock adjustment with zero/negative/oversized deltas and missing reason.
- Verify every successful POS transaction creates consistent order, order item, stock movement, and audit log records; verify failures roll back all changes.

## Verification status
- Function source inspection: completed for the listed RPCs.
- Function code changed: no.
- Database integration tests: NOT RUN.
- Production DDL/deployment: NOT PERFORMED.
