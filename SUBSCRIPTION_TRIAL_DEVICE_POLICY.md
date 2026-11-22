# NORTHSTAR BUSINESS OS — Subscription, Trial & Device Policy
**Status:** Proposed product specification for owner review; not applied to Production.
**Target:** Myanmar small businesses; MMK pricing; $0 implementation budget.
**Source of truth inspected:** Production `plans` and `plan_features` catalog (read-only), current revenue model, tenant architecture, and POS review on 2026-11-22.

## 1. Commercial rules

- Keep the currently published monthly list prices unchanged during the first validation period: Free 0 MMK, Starter 9,900 MMK, Growth 29,900 MMK, Business 79,900 MMK.
- New customer accounts receive one 15-day POS trial, beginning at the first successful account activation (not on repeated logins).
- Trial grants the POS-capable Business feature set for 15 calendar days, subject to the same device policy and safe operational limits. Trial cannot be restarted by deleting/recreating a profile; eligibility must be tied to the authenticated account and recorded server-side.
- When the 15 days expire without a paid subscription, block new POS sales, stock mutations and other paid-only actions server-side. Keep sign-in, plan comparison, upgrade/payment request, support, and export of the customer's own data available. Do not delete customer data.
- A paid subscription becomes active only after a trusted platform admin verifies the payment against the merchant transaction record and approves it server-side. A screenshot alone is not proof of payment.
- If a paid subscription expires, move to an expired/read-only state for paid-only actions; retain data and allow upgrade/export. Grace-period behavior must be explicitly configured, not inferred by the browser.
- Platform administrators are a separate platform-level role, not a business plan. Their accounts bypass plan, trial, device-count, usage and branch limits for internal QA and support. Every admin bypass/action must be audit-logged. Admin status must come from trusted `app_metadata` or a server-managed allowlist, never user-editable metadata.

## 2. Plan matrix

All prices below are MMK per month. Staff seats exclude the business owner.

| Feature / limit | Free (after trial) | Starter | Growth | Business |
|---|---:|---:|---:|---:|
| Monthly price | 0 | 9,900 | 29,900 | 79,900 |
| POS & sales | Trial only; locked after day 15 | Included | Included | Included |
| Products | 50 | 500 | Unlimited | Unlimited |
| Customers | 100 | 1,000 | Unlimited | Unlimited |
| Sales history | 30 days | Unlimited | Unlimited | Unlimited |
| Staff accounts | 0 | 2 | 5 | Unlimited |
| Inventory | Basic | Full | Advanced | Advanced |
| Reports | No advanced reports | Basic | Advanced | Advanced |
| OCR documents | Not included | Not included | 100 / month* | Unlimited* |
| AI assistant | Not included | Not included | 100 / month* | Unlimited* |
| Workflow automation | Not included | Not included | Included* | Advanced* |
| Data export | Not included | Not included | Included | Included |
| Multi-branch | Not included | Not included | Not included | Included |
| Standard devices | 1 phone + 1 laptop | 1 phone + 1 laptop | 1 phone + 1 laptop | 1 phone + 1 laptop |
| Extra device | Add-on subject to separate price rule | Same | Same | Same |

`Unlimited` means no plan cap, not infinite infrastructure or abusive usage. Apply fair-use and technical safety limits where needed.

*The existing database catalog stores Growth OCR=100 and AI=100, and Business unlimited; it stores automation enabled for Growth and Business. Before advertising these as monthly quotas, confirm the counting period and ensure atomic server-side usage enforcement. The current UI and schema have not yet been verified to enforce all these entitlements.

### Plan positioning
- **Free:** Learn the workspace, maintain a small catalog and customers, review basic non-POS records. POS is available only during the initial 15-day trial.
- **Starter:** One small shop with everyday POS, inventory, customer management and a small staff team.
- **Growth:** A growing shop needing advanced reports, OCR, AI, exports and automation.
- **Business:** Larger operations needing unlimited plan quotas, multi-branch support and larger staff teams.

## 3. Device policy

### Included devices
Each standard account has exactly two active device slots:
1. One phone slot (Android or iPhone).
2. One laptop/desktop slot.

A phone plus a laptop can be active at the same time. A second phone or second computer is a new device and cannot silently replace an existing registered device.

### New-device sign-in
- Register a device after successful authentication and an explicit confirmation step.
- If the phone slot or computer slot is already occupied, show the device name/type and last-active time.
- The account owner can either:
  1. Sign out/revoke the old device, then register the new one; or
  2. Purchase an additional-device add-on, if eligible.
- Revocation must invalidate the old device's server-side session/authorization promptly; hiding a session in the UI is insufficient.
- Notify the account owner about new device registration and revocation where a verified notification channel exists.
- Device identity must use a server-issued device registration ID and session records. Browser fingerprinting alone is not reliable proof of a physical device and must not be the only control.
- Apply rate limits and audit events to device enrollment, replacement and revocation. Provide a recovery flow for lost/broken devices.

### Additional-device add-on
The owner proposed **11,000 MMK** to expand the device allowance. The billing period is not yet specified and must be confirmed before implementation or advertising. The add-on should increase the relevant device slot count by one; it must not silently grant staff seats, extra businesses, branches or plan features.

## 4. Trial lifecycle

1. On first verified account activation, create one server-side trial record with `trial_started_at`, `trial_ends_at = trial_started_at + 15 days`, and `trial_status='active'`.
2. Enforce trial eligibility once per auth user ID. Repeated sign-in, browser reset, device change or password reset must not restart the trial.
3. During trial, display remaining time and the exact expiry date/time in the user's local timezone.
4. Send reminders only if an email/notification channel is configured and verified; suggested timing: 3 days and 1 day before expiry.
5. At expiry, server-side authorization denies POS sale creation, stock mutation, premium OCR/AI/automation and other paid entitlements until a paid plan is activated. Keep account access, billing, support and data export available.
6. On verified payment approval, activate the selected paid plan and set the period from the approved billing period. Prevent duplicate approvals and duplicate subscription rows.

## 5. Platform admin / QA access

- Platform admin bypasses all commercial entitlements, device caps, trial expiry, staff-seat caps, branch caps and usage quotas.
- Admin must not be a normal customer plan with a hidden Business subscription.
- Keep a separate admin control panel and audit trail. Admin data access should be explicit and logged; unlimited access does not mean actions are invisible.
- Support impersonation, if ever added, must be read-only by default, time-limited, visibly bannered and audited.

## 6. Enforcement architecture — required before launch

- Entitlements must be checked by trusted server-side functions/RPCs and RLS where relevant. Frontend feature hiding is only presentation.
- A single entitlement resolver should return plan, subscription status, trial status, limits, current usage, device slots and admin bypass for the authenticated user.
- Use atomic usage increments/limits to prevent concurrent requests exceeding quotas.
- Device registry should record user_id, device_id, device_type, friendly_name, created_at, last_seen_at, revoked_at, and session identifier/hash as appropriate. Never store raw refresh tokens in a device table.
- Session revocation must be tied to actual Supabase Auth sessions/token lifecycle. A custom device row alone cannot guarantee immediate sign-out of a stolen session.
- Add audit events for trial start/expiry, plan activation/expiry, payment approval/rejection, device registration/replacement/revocation, limit denials and admin bypass.
- The existing operational schema is user-owned, not yet a complete business-tenant model. Do not enable staff access by only increasing a plan's staff count; tenant-aware business_id, membership, permission checks and POS RPC must be implemented together.
- Do not connect the browser POS form to the current POS RPC until price integrity, pending-order stock semantics, idempotency and tenant authorization are fixed and tested.

## 7. Launch acceptance tests

- Trial starts once, expires exactly after 15 days, cannot be reset by login/device/profile edits, and blocks POS server-side after expiry.
- Paid approval grants only the selected plan and correct period; rejection does not require a payment reference; duplicate approval is rejected.
- A standard account can use one phone and one computer concurrently.
- A second phone cannot evict the registered phone without explicit revoke or add-on; same for a second computer.
- Revoked device cannot continue protected actions with an old session.
- Add-on increases device allowance only by the purchased quantity and for the approved billing term.
- Admin is unlimited even after trial expiry, but every privileged action is audited.
- Every plan limit is enforced server-side under concurrent requests.
- Cross-user and cross-business access tests pass for all tables, RPCs and storage.
- POS creates order, order items, stock movement, stock update and audit record atomically; failures roll back; retries do not duplicate sales.

## 8. Decisions still needed

1. **11,000 MMK add-on billing:** one-time purchase, monthly recurring, or per-year? Do not implement until confirmed.
2. **Device slot transfer:** default proposal is account owner self-service revoke + register, with admin-assisted recovery only for lost-device cases.
3. **Trial coverage:** this spec proposes the full paid POS feature set for 15 days, then POS and other paid-only features lock. Confirm if trial should include all Business-level features or only POS + core inventory.
4. **Annual plans:** not included in this first specification; existing catalog is monthly. Add annual discounts only after the monthly flow works.

## 9. Change control

This document is a product specification only. It does not modify Production prices, plan features, subscriptions, Auth settings, device sessions, POS behavior or deployments. Implement in stages on the security branch, test with synthetic users, then request explicit approval before any Production rollout.
