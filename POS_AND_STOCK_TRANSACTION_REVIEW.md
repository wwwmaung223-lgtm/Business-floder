# POS and Stock Transaction Review

**Review type:** Read-only source and database-function inspection  
**Environment:** Existing Supabase production project and GitHub hardening branch  
**Production changes:** None  
**Status:** Findings and remediation design only; no database migration or deployment

## Executive finding

The database contains a transactional POS function, `public.northstar_create_pos_sale(...)`, but the current browser application does not call it. The current Order form inserts directly into `public.orders`. That path does not create an `order_items` row, deduct product stock, write a stock movement, or write the POS audit event. The UI therefore currently records an order header, not a complete inventory-aware POS sale.

The transactional RPC is closer to the required workflow, but it is not yet safe for staff/tenant use because it scopes product and customer lookup to `auth.uid()`, rather than an explicit business and active membership. It also accepts a caller-supplied unit price and deducts stock for both `completed` and `pending` statuses.

## Verified source findings

### 1. Browser Order form

The inspected `index.html` on `security/rls-permissions-hardening` shows that `orderSubmit()`:
- builds a payload with `user_id: currentUser.id`, optional `customer_id`, `total_amount`, and `status`;
- calls `supabaseClient.from('orders').insert(payload).select().single()`;
- does not call `northstar_create_pos_sale` or `northstar_adjust_stock`;
- does not insert into `order_items` or `stock_movements`.

The selected product is used for the local display value, not persisted as an order item. This is a source inspection finding, not a live browser test.

### 2. `northstar_create_pos_sale`

The inspected PostgreSQL function:
- requires an authenticated user;
- validates quantity is at least one, unit price is nonnegative, payment status is `completed` or `pending`, and payment method is in an allowlist;
- selects a product by `id` and `user_id = auth.uid()` using `FOR UPDATE`;
- checks available stock and, if supplied, checks customer ownership using `user_id = auth.uid()`;
- creates an order header and order item;
- deducts stock, writes a stock movement, and writes an audit log before returning.

These writes occur within the function invocation's PostgreSQL transaction, so an error in the function rolls back its database writes. However, the function has no explicit idempotency key, trusts the supplied unit price rather than loading an authoritative price, and deducts stock even when `p_status = 'pending'`. Whether pending orders should reserve stock is a business rule that must be decided explicitly.

### 3. `northstar_adjust_stock`

The inspected function:
- requires authentication, a nonzero delta, and a reason of at least two trimmed characters;
- locks the product row with `FOR UPDATE`;
- scopes the product by `user_id = auth.uid()`;
- prevents negative stock;
- updates stock and inserts stock movement and audit records.

The row lock and negative-stock check are useful concurrency protections. However, the current function does not check an active team membership or role, so its ownership model is not yet compatible with staff operating on a business owner's inventory.

### 4. Team invitations and authorization boundary

The inspected invitation functions use `auth.uid()` and `business_owner_id` membership ownership, but operational POS and stock functions still use `user_id = auth.uid()`. A staff member therefore cannot simply be enabled for POS by assigning a membership role: the data access and RPC ownership model must be changed coherently. Role checks in the browser are not a substitute for server-side authorization.

## Risks and required design decisions

1. **Order completeness:** Choose one canonical POS write path. A completed sale should not be represented by an order header alone.
2. **Price integrity:** The server should derive the sale price from an authorized product/pricing record or validate an explicitly permitted override with role checks and an audit reason.
3. **Pending-sale semantics:** Decide whether pending orders reserve stock, deduct stock, or leave stock unchanged until payment/fulfilment. Encode the decision in one server-side transaction.
4. **Idempotency:** Add a client-generated unique sale/request key with a database uniqueness constraint so network retries cannot create duplicate orders or deduct stock twice.
5. **Tenant authorization:** Resolve a specific business context and verify the caller has an active membership and the required permission inside the RPC. Do not use the first membership implicitly.
6. **Atomicity:** In one transaction, validate business membership, product/customer tenant ownership, price, quantity and status; lock inventory rows; create order and items; apply the stock policy; create movement and audit records; record idempotency key.
7. **Stock adjustment:** Require an explicit stock-adjust permission, active business membership, reason, tenant-scoped product lock, and audit actor identity.
8. **Audit identity:** Record the authenticated staff actor separately from the business owner/tenant. Do not write the owner's identity as the actor for staff actions.

## Safe implementation sequence

1. Decide pending-order stock semantics and price-override policy.
2. Design the business-aware RPC signatures and permission checks without changing production.
3. Add synthetic test cases for owner, manager, cashier, stock staff, accountant, suspended/removed membership, unrelated business, dual-business user, insufficient stock, invalid price, duplicate idempotency key, and concurrent sale attempts.
4. Test all writes and rollback behavior in a disposable PostgreSQL/Supabase test environment. The current free execution environment has no local PostgreSQL runtime, so this review did not execute those integration tests.
5. Update the browser Order/POS form to call the canonical RPC and display the returned order id, total, and stock result only after success.
6. Run browser E2E tests and verify the database records, then request explicit approval before production rollout.

## Follow-up production metadata verification — 2026-11-21

A later read-only inspection confirmed the current production schema contains the following additional facts:

- `products` includes both legacy `stock` and `stock_quantity`; the POS function reads and updates `stock_quantity`. The UI product form currently inserts `stock: 0` and does not expose an initial `stock_quantity` field. This means new products may have no practical stock entry workflow in the current browser UI.
- `orders` contains `customer_name` and `payment_method`; the browser order form currently does not persist either field.
- `order_items` includes product snapshot, quantity, unit price, and line total. The current browser order form does not persist these fields.
- The deployed POS function is granted EXECUTE to `authenticated` and `postgres`. This confirms it is callable by signed-in clients, so its validation must be treated as a security boundary.
- The function definition confirms it trusts `p_unit_price`, accepts `pending` and `completed`, and decrements `stock_quantity` in both cases. It does not accept an idempotency key.
- The current POS RPC is owner-user scoped (`user_id = auth.uid()`), not tenant/membership scoped. Team roles cannot safely be enabled by merely calling this function as a staff user.
- The Storage bucket `User Uploads` is now present in production metadata as private, 10 MiB, JPEG/PNG/WebP. Existing `User Uplads` remains private and was not modified. Bucket metadata and policy presence have been checked read-only; real Storage API upload/download and cross-user denial tests remain NOT RUN.
- The production Vercel alias still points to `main` commit `f815dc1d3789b645113b5fd00587ba9623254b0a`; the hardening branch is not live.

### POS implementation gate

Do not connect the current browser form directly to the existing RPC. Before integration, implement and test all of the following in a disposable database:
1. Derive authoritative unit price from the tenant-owned product record (or implement a role-checked, audited override).
2. Decide pending stock semantics. A safe default candidate is no stock deduction until the order transitions to a confirmed/completed sale; if stock reservation is needed, model reservations explicitly.
3. Add an idempotency request key with a unique constraint and a replay-safe response.
4. Add explicit business context and server-side active-membership/permission checks, or formally scope the product to single-owner mode and keep staff operations disabled.
5. Validate quantity, currency precision, price bounds, customer tenant, product tenant, status transitions, and payment method on the server.
6. Test concurrent sale attempts, insufficient stock, duplicate retries, transaction rollback, pending-to-completed transitions, and unauthorized callers.
7. Only then connect the UI to the RPC and expose inventory fields.

## Test status

- PostgreSQL integration tests: **NOT RUN**
- Concurrent transaction tests: **NOT RUN**
- Browser E2E tests: **NOT RUN**
- Static source inspection: **COMPLETED**
- Production database writes/schema changes: **NONE**
- Deployment: **NONE**
