# Trial, Subscription Add-on and Device Implementation Status

Date: 2026-11-22
Branch: `security/rls-permissions-hardening`
Status: Development foundation committed; not deployed or applied to Production.

## Owner-approved behavior

- 15-day POS trial, created once on first authenticated account activation.
- Free plan does not count as a paid subscription after trial expiry.
- Included device allowance: one phone and one computer.
- Additional slots: 11,000 MMK per slot per month, manually verified before activation.
- Account owner may revoke a registered device and register a replacement.
- Platform admins bypass device caps and trial/plan gates.
- Existing plan prices and feature caps remain unchanged.

## Implemented in the development migration

Migration: `20261122120000_add_trial_device_entitlement_foundation.sql`

- `account_pos_trials`: one row per auth user, immutable initial 15-day window.
- `account_devices`: device key + Supabase Auth session ID, phone/computer type, last seen and revocation metadata.
- `subscription_addons`: pending/active/rejected monthly add-on record, fixed 11,000 MMK.
- `ensure_account_pos_trial()`: creates the trial once.
- `register_account_device()`: binds a device to the current Auth session, enforces total and per-type slot caps, supports platform-admin bypass.
- `revoke_account_device()`: owner-only device revocation.
- `request_extra_device_slot()`: creates a pending one-slot monthly add-on request.
- `review_extra_device_slot()`: platform-admin approval/rejection; approval requires a merchant transaction reference and grants one month.
- `current_account_device_is_active()`: session/device guard helper for future use by protected RLS policies and mutation RPCs.
- `get_account_entitlements()`: trial, plan, add-on and device summary.

## Important limitations — not launch-ready

1. This migration is only committed to GitHub. It has not been applied to the connected Supabase Production project or any isolated staging database.
2. The current single-file frontend does not yet register devices, show a device-management screen, submit add-on payment evidence, or display trial countdown.
3. Existing business-data RLS policies and POS/stock mutation RPCs have not yet been changed to call `current_account_device_is_active()` and the trial/plan entitlement resolver. The helper alone does not enforce a device cap across the application.
4. The existing POS flow is incomplete. Trial expiry cannot be considered enforced until every protected POS and stock mutation is guarded server-side.
5. Admin bypass is implemented in the new device registration and entitlement resolver only; every protected operation still needs a consistent admin-aware authorization check.
6. Manual add-on approval must be performed only after checking the actual merchant transaction record. A payment screenshot is not proof of payment.
7. Supabase Auth sign-out/revocation behavior must be tested. Revoking the application device record immediately blocks operations only after all protected operations use the guard; a JWT may otherwise remain valid until expiry.

## Required test matrix before rollout

- First activation creates exactly one trial; repeat login never extends it.
- Trial is active immediately before expiry and inactive at/after expiry.
- Free plan does not bypass expired trial; active paid plan does.
- One phone + one computer succeeds; second phone or second computer is denied.
- One monthly add-on allows exactly one additional slot; two concurrent registration attempts cannot exceed the cap.
- Pending/rejected/expired add-on grants no slot.
- Admin can register more than the standard cap; admin actions remain auditable.
- User A cannot list or revoke User B devices or add-ons.
- Revoked session is denied on every guarded read/write and POS/stock mutation.
- Repeated approval of the same add-on cannot extend or duplicate the term.
- Add-on renewal grants the next verified month only; expiry removes the extra allowance without deleting account data.
- Regression tests cover existing login, data loading, POS, stock, orders, and owner/admin functions.

## Safe next sequence

1. Finish frontend device registration and management UI on the development branch.
2. Wire trial/plan/device entitlement checks into every protected server-side action.
3. Add automated SQL/RPC tests and browser regression tests using synthetic accounts.
4. Obtain an isolated staging project or a deliberate Production migration window with backup and rollback.
5. Apply migration and verify end-to-end before enabling customer-facing plan/device purchases.
6. Production merge and deployment remain separate release steps.
