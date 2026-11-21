# Frontend Security and Data-Integrity Review
Date: 2026-11-21
Repository: wwwmaung223-lgtm/Business-floder
Reviewed ref: security/rls-permissions-hardening
Reviewed file: index.html (single-page V1.4 Glass application)

## Scope and safety
This is a source review only. No production database writes, storage writes, deployment, or live-user tests were performed. Findings below are based on the checked-in source and the previously recorded read-only production audit. Do not treat this document as proof that an exploit has been reproduced.

## Confirmed source findings

### F-01 — Storage bucket identifier mismatch (High functional impact; security posture needs policy confirmation)
- Frontend upload calls `supabaseClient.storage.from('User Uploads')`.
- The read-only Storage audit found the actual private bucket names `product images` and `User Uplads` (misspelled).
- The requested bucket name therefore does not match either observed bucket. Upload is expected to fail with a missing-bucket error unless a third bucket exists outside the inspected listing.
- Do not rename, delete, or recreate a bucket until object counts, references, and backup/restore options are checked.
- Safe resolution: decide on one canonical bucket name; inspect all existing objects and policies; then update the frontend or perform a carefully planned bucket/object migration. Test upload, list, download, and delete using a non-production fixture before release.

### F-02 — Owner-area role gate exists only in browser code (High)
- `showPage('owner')` checks `currentUser.app_metadata.role` for `owner` or `admin`.
- The hidden five-tap logo gesture is only obscurity; it is not authorization.
- The source itself correctly notes that the server-assigned app_metadata role is required, but browser navigation checks can be bypassed by calling client APIs directly.
- Database tables, RPCs, and any privileged actions must enforce authorization independently through RLS/function checks. Do not rely on hidden navigation, disabled buttons, or frontend role checks.

### F-03 — Current UI cannot safely represent team access yet (High for planned multi-role operation)
- The frontend sets `user_id: currentUser.id` on product, customer, order, and finance inserts.
- Reads use `select('*')` and rely on RLS to filter rows.
- This is compatible with an individual-user ownership model, but it does not implement a business-membership tenant model for staff working on an owner's records.
- The existing database audit found membership rows empty, current helper functions fall back to the signed-in user's own ID, and POS/stock RPCs assume `auth.uid()` ownership.
- Do not enable staff access or change the frontend to submit an owner ID until the tenant model, membership lifecycle, role matrix, and database enforcement are implemented and tested together.

### F-04 — Dynamic HTML is mostly text-escaped, but inline event construction remains fragile (Medium)
- `render()` assigns database-derived names, dates, descriptions, statuses, and OCR text through `innerHTML`; most text positions pass through `esc()`.
- The product delete button embeds `p.id` inside an inline `onclick` attribute using only single-quote removal. This is not a context-safe attribute/JavaScript encoding strategy.
- Current IDs are expected to be UUIDs, which reduces the practical attack surface, but database values should not be interpolated into executable attributes.
- Safe resolution: render a button with a non-executable data attribute and use one delegated event listener; validate the ID format before the delete call. Keep text escaping for text nodes.

### F-05 — OCR cloud persistence silently falls back to device-local notes (Medium data-integrity / user-expectation issue)
- OCR note reads catch cloud errors and load notes from localStorage.
- The auth note says OCR notes are kept on this device in this version, while the save function attempts a Supabase insert and reports a setup SQL instruction on failure.
- Users can therefore see local notes alongside cloud-backed records without a clear per-note storage status.
- Safe resolution: label local-only notes clearly, show cloud sync failures explicitly, and avoid implying that local notes are backed up in Supabase. Provide a deliberate export/import path if migration is needed.

### F-06 — Local browser storage and backup contain business data (Medium privacy consideration)
- `saveLocalOnly()` writes the full in-memory `db` object to localStorage under a per-auth-user key.
- `exportData()` downloads the currently loaded records as JSON.
- This is not a server-side secret leak, but shared/unlocked devices and downloaded backup files may expose customer, order, finance, and OCR-note content.
- Safe resolution: minimize local persistence, explain device-local storage, provide a clear sign-out/device-data cleanup option, and remind users to protect exported backups. Do not put service-role or secret keys in this browser application.

### F-07 — Order/customer display loses relational context (Medium data correctness)
- Orders are loaded with `select('*')` and mapped to display `customer_id` rather than a customer name; the order form matches customers by name in the local array.
- The order insert stores `customer_id`, amount, and status but does not persist the selected product/item or create `order_items`.
- This means the visible order history cannot reliably show line items and may show an ID in place of the customer name.
- Safe resolution: use a validated customer ID selection and a tenant-consistent relational query; persist order items through a transaction/RPC with stock movement and audit records. Do not retrofit this as separate uncoordinated browser writes.

### F-08 — Revenue figures are derived from current browser-loaded orders (Medium reporting correctness)
- Dashboard revenue sums orders whose UI status is exactly `Paid`; expense totals sum finance rows filtered to `record_type === 'expense'`.
- There is no reconciliation against refunds, partial payments, voids, tax, or line-item totals in this source.
- Treat this as a simple recorded-order summary, not an accounting ledger or verified profit figure.

## Remediation staged on the security branch

### F-04 — Product delete event handling
- Updated `index.html` on `security/rls-permissions-hardening` to remove the database-derived product ID from an inline JavaScript event handler.
- Product rows now render a button with an escaped `data-product-id` attribute and use one delegated click listener.
- The listener validates the ID against the expected UUID shape before calling the existing delete function.
- The delete query still scopes by both product ID and `currentUser.id`; no authorization boundary was weakened.
- Static checks on the fetched branch source: inline script syntax parse PASSED; delegated handler present; inline delete handler absent; UUID guard present; escaped data attribute present; owner-scoped delete filter preserved.
- Browser interaction/E2E tests remain NOT RUN. This change is staged in the draft PR branch and has not been deployed.

## Positive controls observed
- The browser client uses a Supabase publishable key, not a service-role key. A publishable key is intended for public clients; safety depends on correctly configured RLS and grants.
- Product, customer, order, and finance inserts set the signed-in user's ID.
- Product deletion filters by both product ID and signed-in user ID.
- Text displayed in most generated table/list cells is passed through `esc()`.
- OCR is performed in the browser with Tesseract.js; the inspected code does not upload the image as part of the OCR call. A separate explicit upload action exists.

## Required implementation order (do not skip)
1. Resolve and test the Storage bucket name/policies without moving or deleting existing objects.
2. Design one authoritative tenant model for owner + memberships, including how multiple businesses and removed/suspended memberships behave.
3. Replace the entire relevant permissive-policy set together; permissive policies OR-combine, so adding a narrow policy alone may not close a broad existing policy.
4. Review every SECURITY DEFINER function for fixed search_path, explicit authentication/authorization, ownership scope, and least-privilege EXECUTE grants. Test auth triggers and signup before changing trigger-function ACLs.
5. Update POS/stock/order RPCs to use the chosen tenant model and atomically write orders, order items, stock movements, and audit events.
6. Replace inline event handlers and clarify cloud-vs-local OCR persistence.
7. Run automated tests with synthetic users/fixtures for owner, manager, cashier, stock staff, accountant, unrelated user, suspended member, removed member, and unauthenticated role.
8. Re-run Supabase Security and Performance Advisors and verify the app using a free local/staging-compatible environment before any production rollout.

## Test status
- Static source inspection: completed for the sections referenced above.
- Production database inspection: read-only audit only; no writes.
- Local PostgreSQL/Supabase integration tests: NOT RUN.
- Browser end-to-end tests: NOT RUN.
- Storage upload test: NOT RUN.
- Production deployment: NOT PERFORMED.
- This review does not authorize applying SQL to production.

## Supabase documentation consulted
- Storage Access Control: https://supabase.com/docs/guides/storage/security/access-control
- Storage Helper Functions: https://supabase.com/docs/guides/storage/schema/helper-functions
- Supabase guidance confirms Storage authorization is enforced by RLS on `storage.objects`; user-folder constraints should be tied to the authenticated identity, and upsert requires the relevant INSERT/SELECT/UPDATE permissions.
