# Trial and Device Entitlement Review

**Review type:** Read-only staged migration and frontend source review  
**Branch:** `security/rls-permissions-hardening`  
**Migration:** `20261122120000_add_trial_device_entitlement_foundation.sql`  
**Production changes:** None  
**Status:** Design/foundation only; do not apply until isolated PostgreSQL tests and enforcement wiring are complete.

## Executive finding

The staged migration creates a 15-day per-user trial, device registrations tied to Supabase Auth `session_id`, manual extra-device add-ons, and SECURITY DEFINER RPCs. The frontend calls the trial/device registration RPCs after sign-in and displays entitlement/device status.

This is **not yet an enforced POS entitlement or device-access boundary**. The entitlement RPC reports a `pos_allowed` boolean based on admin, paid subscription, or trial. It does not include the current-device-active predicate. The current browser order handler still writes an order header directly and does not check either entitlement or device status. The device guard helper has no current call site in the inspected browser source, and no protected POS/stock RPC currently consumes it.

## Verified frontend behavior on the branch

- `activateUser()` loads cloud data, then calls `initializeAccountSecurity()`.
- `initializeAccountSecurity()` calls `ensure_account_pos_trial()`, then `register_account_device(...)`, then refreshes account status.
- The device key is generated with `crypto.randomUUID()` and stored in browser `localStorage`.
- Device type and label are inferred from the browser user-agent.
- The account screen reads the user's own device/add-on rows and can request device revocation.
- `refreshAccountSecurity()` displays `ent.pos_allowed`, but this is presentation only. No POS or stock mutation is conditionally blocked by that value in the inspected order handler.
- The current `orderSubmit()` still inserts directly into `public.orders`; it does not call the transactional POS RPC, check device state, or create order items/stock movements.

## Security and correctness observations

1. **No enforcement integration:** `current_account_device_is_active()` is defined and granted to authenticated, but no current POS/stock RPC calls it. Until every protected server mutation checks it, revoking a device only changes registration state; it does not revoke business-data access or block the existing order-header insert.
2. **Entitlement is advisory:** `get_account_entitlements()` returns `pos_allowed`, but the value is not a database authorization control. Do not describe the UI label “POS access enabled/locked” as enforced access.
3. **Client device key is not hardware attestation:** The key is browser-local and can be reset/copied by the client. The Auth `session_id` binding proves the registration belongs to an Auth session, not that the request comes from a unique physical device. Describe this as session-bound device registration, not immutable hardware identity.
4. **Device-session lifecycle needs tests:** On a new Auth session, the same local device key is re-registered against the new session. Verify behavior for concurrent sessions, duplicate device keys, stale sessions, refresh, sign-out, revoked sessions, and re-login.
5. **Trial start semantics:** The trial is created by the first call to `ensure_account_pos_trial()` or `get_account_entitlements()`. Confirm all account activation paths call this intentionally and that no unauthenticated path can create a row for another user.
6. **Add-on approval:** The review RPC checks platform-admin membership and requires a payment reference for approval. Test concurrent reviews, duplicate requests, rejection, audit insertion, and whether add-on expiry/revocation is reflected immediately.
7. **RLS and grants:** Tables expose SELECT only to authenticated users with owner-row policies; writes are intended to occur through SECURITY DEFINER RPCs. Verify effective function ACLs, owner privileges, fixed search paths, and two-user isolation in PostgreSQL.
8. **Admin behavior:** Device registration bypasses slot limits for platform admins. Verify that this exception is intentional and that it does not leak into ordinary business-owner entitlements.

## Required implementation sequence

1. Treat this migration as a schema/RPC foundation only; do not claim POS enforcement.
2. Define exactly which server operations are protected: POS sale, stock adjustment/receiving, refunds/voids, and any other inventory mutation.
3. Add a single server-side authorization contract that checks authenticated user, account entitlement, active device/session, explicit business context, active membership, and permission. Keep owner-only single-tenant behavior until the business tenant model is implemented.
4. Resolve the current POS architecture blockers separately: authoritative product price, pending-order stock semantics, idempotency, row locking, transaction rollback, and audit actor identity.
5. In a disposable PostgreSQL environment, test trial start/expiry, concurrent device registration, device revoke, new session, session revoke, add-on approve/reject, and unauthorized access.
6. Update the frontend to display server results but never rely on client-side checks as the security boundary.
7. Only after full test coverage and explicit rollout approval should the migration be considered for Production.

## Acceptance tests

- User A cannot read User B's trial, device, or add-on rows.
- An authenticated user cannot create or approve an add-on for another user.
- A non-admin cannot approve an add-on, including with a forged client role.
- Concurrent registration cannot exceed the account's device limits.
- Revoking a device causes every protected server-side operation from that session to fail.
- A newly issued Auth session must follow the defined re-registration policy.
- Expired trials and subscriptions deny protected POS/stock mutations.
- Active paid subscription does not bypass device enforcement if the product policy requires device registration.
- All failed POS operations leave orders, items, stock, movements, and audit logs unchanged.
- Duplicate idempotency requests do not duplicate a sale.

## Release gate

No Production DDL or frontend deployment is authorized by this review. The staged migration remains un-applied. The current environment still lacks an isolated PostgreSQL runtime, so PostgreSQL/RLS integration tests remain a wait gate.
