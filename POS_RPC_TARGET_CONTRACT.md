# POS RPC Target Contract and Direct-Write Boundary Audit

**Date:** 2026-11-22  
**Scope:** Read-only Production catalog/RPC inspection and hardening-branch frontend source inspection  
**Status:** DESIGN ONLY — no SQL migration, frontend edit, or deployment  
**Production changes:** None

## Executive decision

Do not wire the current Order form directly to the existing `northstar_create_pos_sale(...)` RPC. The function is transactional, but it trusts a browser-supplied unit price, decrements stock for both `pending` and `completed` orders, has no idempotency key, and scopes all records to `auth.uid()` rather than a business tenant and active staff membership.

The current browser Order form is also incomplete: it inserts only an `orders` header. It does not persist an `order_items` row, decrement stock, write a `stock_movements` row, or write a POS audit event. The selected product is only used in local display state.

The safe near-term target is a single-owner POS v2 boundary. Staff POS must remain disabled until the tenant/business model and server-side membership permissions are implemented together.

## 1. Verified frontend write paths

Source inspected: `index.html` on `security/rls-permissions-hardening`.

| Flow | Current cloud write | Important limitation |
|---|---|---|
| Product create | Direct insert into `products` with `stock: 0` | Does not set `stock_quantity`; database default is zero. No receiving workflow is exposed here. |
| Customer create | Direct insert into `customers` | Owner-scoped RLS currently protects the row. |
| Order create | Direct insert into `orders` with user, optional customer, total and status | Selected product is not persisted as an order item; no stock movement or POS audit event. |
| Expense create | Direct insert into `finance_records` | Direct client write is currently allowed by owner-scoped RLS; accounting controls/period close are not part of this form. |

The frontend source contains no direct calls to `order_items` or `stock_movements` in the inspected order workflow.

## 2. Verified Production schema and RLS boundary

Read-only catalog inspection found:

- `products` has both legacy `stock` and operational `stock_quantity`; `stock_quantity` is NOT NULL with default 0.
- `orders` has `customer_id`, `customer_name`, `total_amount`, `status`, and `payment_method`.
- `order_items` stores `order_id`, `product_id`, product name snapshot, quantity, unit price, and line total.
- `stock_movements` stores product, quantity delta, reason, and `created_by`.
- `audit_logs` stores tenant/owner `user_id`, `actor_id`, action, entity, entity ID, details, and timestamp.

Current Production policies on the inspected tables:

- `products`, `customers`, `orders`, and `finance_records` each have a broad owner-scoped authenticated `ALL` policy plus command-specific owner policies. This is redundant because permissive policies are OR-combined. A staged deduplication migration exists in the PR branch but has not been applied to Production.
- `order_items`, `stock_movements`, and `audit_logs` expose owner-scoped SELECT policies only in the inspected policy set. No direct authenticated INSERT policy was returned for these tables.
- This explains why the current direct Order header insert can succeed while a complete multi-table POS write should be performed through a carefully guarded server RPC.

## 3. Existing Production RPC behavior

### `northstar_create_pos_sale(uuid,integer,numeric,uuid,text,text,text)`

Verified function behavior:

1. Requires `auth.uid()`.
2. Accepts quantity, unit price, customer, customer name, payment method, and status from the caller.
3. Allows `pending` and `completed`.
4. Locks the product row with `FOR UPDATE`, scoped to `products.user_id = auth.uid()`.
5. Checks stock and customer ownership.
6. Inserts order and order item.
7. Decrements `stock_quantity` for both pending and completed statuses.
8. Inserts stock movement and audit log.
9. Returns order ID, new stock, total, and status.

The transaction is atomic, and the product row lock helps prevent concurrent overselling. However:
- `p_unit_price` is caller-controlled and is not compared with the authoritative product price.
- A pending order immediately consumes stock.
- There is no request/idempotency key, so network retries can create duplicate orders and deductions.
- It is owner-user scoped, not business/membership scoped.
- It does not check trial/subscription entitlement or the active device guard.

### `northstar_adjust_stock(uuid,integer,text)`

The function locks the product, rejects zero delta and missing reason, prevents negative stock, and writes movement/audit rows. It is also owner-user scoped and does not enforce staff permissions, subscription entitlement, or active device status.

The current Production ACL snapshot indicates authenticated execution is revoked for these two POS/stock RPCs. Do not grant them back as-is.

## 4. Recommended POS v2 contract — design only

### Security boundary

For the legacy single-owner release:
- Resolve actor only from `auth.uid()`; never accept `actor_id` or `user_id` as trusted client arguments.
- Resolve the product and customer only within the authenticated owner's records.
- Check `get_account_entitlements()` server-side and require `pos_allowed = true`.
- Require `current_account_device_is_active()` server-side.
- Until tenant migration is complete, do not allow staff accounts to use the owner-scoped POS function.
- Use `SECURITY DEFINER` only where necessary, with `SET search_path = ''`, schema-qualified object references, strict input validation, and EXECUTE grants only to `authenticated`.

### Proposed create-sale input

- `p_product_id uuid`
- `p_quantity integer`
- `p_customer_id uuid default null`
- `p_customer_name text default 'Walk-in customer'`
- `p_payment_method text`
- `p_status text` (initially `pending` or `completed`)
- `p_request_key uuid` (required; generated once by the client per intended sale and reused on retry)

Do not accept `p_unit_price` in the default contract. Derive the price from the locked, owner-scoped product row. Any future price override must be a separate role-checked capability with a required reason and audit metadata.

### Idempotency

Create a dedicated request ledger with:
- `user_id`
- `request_key`
- normalized request hash
- `order_id`
- canonical response JSON
- created timestamp

Enforce UNIQUE(`user_id`, `request_key`). Serialize duplicate attempts for the same owner/request key. If the key is replayed with the same request hash, return the original canonical result without repeating stock or audit writes. If the same key is reused with different sale inputs, reject it.

The request record, order, order item, stock movement, and audit event must commit or roll back together.

### Stock and order-state semantics

Recommended default:
- `completed`: lock product, verify available stock, create order and item, decrement stock, insert stock movement, insert audit event — all in one transaction.
- `pending`: create order and item but do not decrement stock. Pending orders must not silently reserve inventory.
- Pending-to-completed transition: use a separate server RPC that locks the order and product, verifies the order is still pending, checks current stock, decrements stock exactly once, creates one stock movement and one audit event, and updates status atomically. Repeated completion requests must return the already-completed result without a second deduction.
- If the business later requires reservation, add an explicit reservation model and expiry/release workflow rather than treating pending as a hidden deduction.

This is a proposed policy for review, not a user-confirmed business rule.

### Stock receiving and adjustment

Use a separate RPC for stock receiving/adjustment. It must:
- check authenticated owner, entitlement, and active device;
- lock the owner-scoped product row;
- validate a nonzero delta and a meaningful reason;
- reject negative resulting stock;
- update `stock_quantity`, insert `stock_movements`, and insert `audit_logs` in one transaction;
- derive `created_by` and `actor_id` from `auth.uid()`.

Do not use ordinary product form updates to modify stock.

## 5. Tenant/staff boundary

This contract is explicitly single-owner. The existing operational tables use `user_id`; memberships use `business_owner_id` and `member_user_id`; no shared `business_id` tenant key was observed on the inspected operational tables.

Do not add a browser role check and then grant staff access to these owner-scoped RPCs. A future staff-capable POS must:
- accept explicit `business_id`;
- verify active membership for that exact business and permission inside the RPC;
- ensure product, customer, order, item, stock movement, and audit rows all belong to that business;
- preserve authenticated staff `actor_id` separately from business owner/tenant identity;
- deny suspended/removed membership immediately;
- include composite tenant-aware constraints and RLS policies.

## 6. Required acceptance tests before UI integration

Use synthetic accounts/data only:

1. Unauthenticated and anonymous callers are denied.
2. Expired trial, inactive subscription, and revoked device are denied by the RPC.
3. Active owner with valid entitlement/device can create a sale.
4. Another owner's product/customer IDs are rejected.
5. Browser-supplied user/actor/price values cannot change authoritative ownership or price.
6. Completed sale creates exactly one order, item, stock decrement, movement, and audit event.
7. Pending sale creates order/item but does not decrement stock.
8. Pending-to-completed transition decrements stock once; replay does not decrement twice.
9. Duplicate request key + same payload returns original result.
10. Duplicate request key + different payload is rejected.
11. Insufficient stock leaves no partial order/item/movement/audit writes.
12. Two concurrent completed sales cannot oversell.
13. Failure at each write stage rolls back the entire transaction.
14. Stock adjustment requires a reason, cannot produce negative stock, and records actor identity.
15. Existing owner-only RLS read access and unrelated workflows continue to work.

Only after disposable PostgreSQL/Supabase tests pass should the frontend form be changed to call the RPC. Browser E2E must then verify the form, returned order ID, totals, stock, and audit history.

## 7. Release gates

- [x] Read-only source inspection of browser product/customer/order/expense writes.
- [x] Read-only Production schema and RLS policy inspection for POS-related tables.
- [x] Read-only inspection of existing Production POS and stock RPC definitions.
- [x] Documented target contract and acceptance tests.
- [ ] Business approval of pending-order stock semantics.
- [ ] Disposable PostgreSQL/Supabase integration and concurrency tests.
- [ ] Implement staged RPC migration and rollback plan.
- [ ] Frontend integration without changing the established visual baseline.
- [ ] Browser E2E and database verification.
- [ ] Explicit owner approval before Production rollout.

**No Production SQL, data, ACL, migration ledger, or deployment was changed during this review.**
