# Northstar Tenant Architecture and Role Permission Blueprint
Date: 2026-11-21
Status: DESIGN ONLY — NOT A MIGRATION
Budget: $0; production unchanged.

## 1. Why the current schema cannot safely support team access
The operational tables inspected in production (products, customers, orders, order_items, finance_records, stock_movements, audit_logs, ocr_notes) use `user_id` as the ownership boundary. The membership table instead stores `business_owner_id` and `member_user_id`. No `business_id` column was observed on the inspected operational tables. Existing POS and stock RPCs also filter data by `auth.uid()`.

Therefore adding a staff role check to the browser or simply changing one RLS policy is not enough. There is no consistent tenant key shared by memberships, business data, RPCs, and audit events.

## 2. Recommended target model
Use an explicit business tenant ID, separate from the identity of the user who performed an action.

### Core entities
- `businesses`: one row per business; stable UUID primary key, owner_user_id, name, status, created_at, updated_at.
- `business_memberships`: business_id, member_user_id, normalized member_email, role, status, invited_at, accepted_at, created_at, updated_at. Unique active membership rules must be defined deliberately; retain an invitation history if auditability is required.
- Tenant-owned business tables: add non-null `business_id` after a safe backfill. Keep `user_id` temporarily as legacy owner/creator only where existing semantics require it; do not silently reinterpret it as actor identity.
- Audit events: business_id = affected tenant; actor_id = authenticated person; actor_role = role at action time (or a referenced membership snapshot); entity/action/details/timestamp.
- POS order items and stock movements must reference rows inside the same business. Enforce this with composite tenant-aware foreign keys or equivalent database constraints, not only client checks.

### Legacy migration strategy (future, staged only)
1. Create one initial business row for each distinct legacy owner/user who owns business data.
2. Backfill each legacy row's business_id from its existing user_id.
3. For owner accounts, create an active owner membership for that business.
4. Validate every existing order/customer/product/order-item/stock/audit relationship remains within one business.
5. Add NOT NULL and tenant-aware constraints only after validation; preserve IDs and existing rows.
6. Keep rollback scripts and a verified backup/export before any production migration.
7. Only after all dependent RPCs, RLS policies, storage policies, and frontend queries are ready should the tenant migration be deployed.

Do not add columns or run this backfill in production as part of this design document.

## 3. Recommended role matrix
This is a proposed least-privilege baseline. Owner retains full business control. Platform administrator is a separate platform-level role and is not a business staff role.

| Capability | Owner | Manager | Cashier | Stock Staff | Accountant |
|---|---|---|---|---|---|
| Business settings / billing | Full | No | No | No | View limited billing info only if required |
| Team invitations / role changes / removal | Full | No by default | No | No | No |
| Products: view | Yes | Yes | Yes (POS catalog) | Yes | No by default |
| Products: create/update/archive | Yes | Yes | No | Stock fields only via controlled action | No |
| Stock: view | Yes | Yes | Availability only | Yes | No |
| Stock adjustments / receiving | Yes | Yes | No | Yes, reason required | No |
| POS: create sale | Yes | Yes | Yes | No | No |
| Orders: view | Yes | Yes | Own shift/necessary scope | No | Yes |
| Orders: void/refund/override | Yes | Limited, audited | No | No | No |
| Customers: view/create | Yes | Yes | Minimum necessary | No | No |
| Customer export/delete | Yes | No by default | No | No | No |
| Finance: view | Yes | Summary only | No | No | Yes |
| Finance: create/update | Yes | No | No | No | Yes |
| Finance: delete/close period | Yes | No | No | No | Restricted, audited |
| Reports: operations | Yes | Yes | Shift summary only | Stock summary | Finance reports |
| Audit log: view | Full | Relevant business events | Own actions only | Own actions only | Finance-relevant events |
| Staff activity / security settings | Full | Limited | No | No | No |

Rules:
- Deny by default. Every unlisted capability is denied.
- Staff role changes and membership removal are owner-only initially.
- A member may belong to multiple businesses. Every request must include/resolve an explicit active business context and verify membership for that exact business.
- Suspended/removed memberships must deny immediately on every server-side operation, regardless of old browser state.
- Role checks must use trusted server-side membership data, never user-editable profile metadata.
- Cashier access should be restricted to operational minimum, with optional own-shift scoping implemented only after a shift/session model exists.
- Platform owner/admin privileges must remain separate from a business owner's role.

## 4. Server authorization design
- Create a single well-reviewed helper that answers whether `auth.uid()` is an active member of a specific `business_id` with a specific permission.
- The helper must reject null auth, missing business context, suspended/removed membership, and ambiguous membership state.
- Use SECURITY INVOKER where possible. If SECURITY DEFINER is required, set a fixed safe search_path, schema-qualify objects, perform explicit authorization, and grant EXECUTE only to intended roles.
- RLS policies must use the business_id boundary and role/permission helper.
- Replace the full existing permissive policy set for each table; do not append a new policy alongside broad `ALL` policies. PostgreSQL permissive policies OR together.
- Ensure SELECT policies exist for rows that UPDATE/DELETE workflows must target.
- Prevent users from changing business_id or owner/actor fields through ordinary table updates.
- RPCs should be the only path for atomic POS, stock, membership, and financial close operations where multi-row consistency matters.
- Record actor_id from `auth.uid()`; never accept actor_id from the browser as trusted input.

## 5. Atomic POS and stock transaction contract
A successful POS sale must atomically:
1. Validate authenticated actor and active business membership.
2. Verify permission for `pos.create`.
3. Lock the product row in the selected business.
4. Validate quantity, price, payment method, product status, and available stock.
5. Validate optional customer belongs to the same business.
6. Create order and order_items.
7. Deduct stock.
8. Insert stock_movements with actor_id and business_id.
9. Insert audit event with actor_id, role, business_id, and affected order.
10. Return canonical order/stock totals.

If any step fails, the entire transaction rolls back. A retry/idempotency key should prevent duplicate sales after network retries.

Stock receiving/adjustment must be a separate controlled RPC with reason, actor, business scope, row lock, nonnegative stock rules, and audit event.

## 6. Storage design
- Choose a canonical bucket name only after inspecting all bucket objects, references, and existing policies.
- Preserve private bucket visibility.
- Use paths that include business ID and uploader ID, e.g. `<business_id>/<auth.uid()>/<object_id>`.
- Storage RLS must verify active membership in the path's business and uploader/role permissions.
- Do not rely on a UUID folder alone if staff share a business.
- Do not rename/delete buckets or objects until object inventory and backup are verified.

## 7. Test acceptance matrix
Use synthetic users only:
- Owner A, Owner B.
- Manager A, Cashier A, Stock Staff A, Accountant A.
- One user active in both Business A and Business B with different roles.
- Suspended member, removed member, pending invite, unrelated authenticated user, anonymous user.

Required assertions:
- No user can read/write another business's data without membership.
- A staff member can access only allowed resources in the explicitly selected business.
- A dual-business user receives the role assigned in the selected business, never the first/oldest membership by accident.
- Suspended/removed membership immediately denies table reads, RPCs, and storage operations.
- Client-supplied business_id, user_id, actor_id, role, and status cannot elevate privileges.
- POS failures roll back order, items, stock, movements, and audit rows.
- Concurrent sales cannot oversell stock.
- Replayed requests do not create duplicate orders.
- Invite, accept, re-invite, role-change, suspend, and remove flows are owner-authorized and audited.
- Audit rows cannot be altered/deleted by ordinary business users.
- Signup and free-plan trigger behavior continues after function ACL hardening.
- Existing legacy owner data remains accessible after tenant backfill.

## 8. $0 test environment assessment
The current execution environment was checked for `docker`, `podman`, `psql`, `postgres`, and the Supabase CLI; none were available. Python packages `psycopg` and `psycopg2` were also unavailable. Playwright is installed, but without a running local database/auth/storage stack it cannot prove RLS or RPC correctness.

Therefore database integration tests cannot honestly be marked complete in this environment. Do not substitute SQLite tests for PostgreSQL RLS tests. A free local Supabase/PostgreSQL setup can be used later on the user's own computer if Docker is available; no paid branch or second Supabase project is required.

## 9. Next implementation gates
Gate A — Complete schema and policy inventory (read-only).
Gate B — Confirm role matrix and tenant model (design review).
Gate C — Write migrations and rollback scripts as files only.
Gate D — Test on free local Supabase/PostgreSQL with synthetic users.
Gate E — Update frontend to send explicit business context and consume server-authorized data.
Gate F — Verify storage and auth triggers.
Gate G — Owner-approved backup + production rollout window.
Gate H — Re-run Security/Performance Advisors and smoke tests.

Until Gates A–F pass, do not merge or deploy as a production security fix.
