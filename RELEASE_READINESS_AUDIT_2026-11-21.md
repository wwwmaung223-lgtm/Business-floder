# Release Readiness Audit — 2026-11-21

## Scope and safety
This is a read-only review of the current branch and live Supabase metadata. No production database writes, Storage mutations, billing changes, merges, or deployments were performed.

## Verified current application behavior

### Authentication and data loading
- The browser uses the Supabase publishable key and Supabase Auth; no service-role key was found in the inspected client initialization.
- On sign-in, the app loads products, customers, orders, finance records, and OCR notes.
- Main records are queried per authenticated user through the shared cloud-select helper (verify its exact implementation before changing query semantics).
- OCR note reads use `ocr_notes.select('*').order('created_at', descending)`; writes include the signed-in user's `user_id`.
- OCR note errors fall back to browser local storage. This fallback can make notes appear saved locally while cloud sync is unavailable; the UI should distinguish local-only from cloud-saved records.

### OCR and image upload
- OCR runs in the browser with Tesseract.js and asks the user to review extracted text before saving.
- Image validation allows JPEG, PNG, and WebP; rejects empty files and files over 10 MiB.
- Upload targets the private bucket ID `User Uploads` and stores objects under `<auth.uid()>/<timestamp>_<sanitized filename>`.
- The live Storage metadata audit found no bucket named `User Uploads`; the existing misspelled bucket `User Uplads` contains two objects. The expected bucket is therefore a release blocker for upload. Preserve the legacy bucket and its objects; do not silently rename, delete, or repoint uploads.
- Client-side MIME/size checks are usability controls, not security controls. Enforce the same restrictions at the bucket and retain owner-folder RLS policies.

### Orders and inventory
- The current order form inserts one row into `orders` with `user_id`, optional matched `customer_id`, `total_amount`, and status.
- It does not create `order_items`, does not call the existing POS sale RPC, does not deduct stock, and does not write an order-linked stock movement or audit event.
- The selected product is currently represented in the UI only; the saved order does not persist the selected product or quantity.
- Treat the order UI as a basic order register, not a complete POS/inventory transaction. Do not advertise stock deduction or itemized receipts until an atomic server-side workflow is implemented and tested.
- Do not connect the existing POS RPC without first validating its authorization, price-trust, pending-order stock deduction, and idempotency behavior.

### RLS metadata spot-check
All inspected tables below have RLS enabled in the schema inventory.
- `ocr_notes`: authenticated users have separate SELECT/INSERT/DELETE policies scoped to `auth.uid() = user_id`; no UPDATE policy was present in the returned policy set.
- `business_memberships`: owner SELECT policy only; no member-side read policy or invitation/role-management workflow was present in the returned policy set.
- `audit_logs`: user SELECT policy scoped to `user_id = auth.uid()`; no client INSERT/UPDATE/DELETE policy appeared in the returned policy set.
- `subscription_requests`: users can INSERT their own pending requests and SELECT their own requests. An owner/admin ALL policy relies on server-assigned `app_metadata.role`.
- `subscriptions`: users can SELECT their own subscription; owner/admin ALL policy relies on `app_metadata.role`.
- Policies are permissive by default and combine with OR. Any future policy hardening must account for existing permissive policies rather than assuming a new restrictive-looking policy overrides them.

## Release blockers and recommended order

### P0 — Must resolve before public launch
1. Create the exact private Storage bucket ID `User Uploads` using Supabase Storage UI/API (not direct SQL writes to `storage.buckets` or `storage.objects`).
   - Private: ON
   - File size limit: 10 MiB
   - Allowed MIME types: `image/jpeg`, `image/png`, `image/webp`
   - Keep owner-folder INSERT/SELECT/UPDATE/DELETE policies limited to the first path segment matching `auth.uid()`.
   - Test authenticated owner upload/read/delete, cross-user denial, and anonymous denial using disposable accounts and synthetic images.
   - Keep `User Uplads` and its two existing objects untouched until they are independently reviewed and backed up.
2. Run browser E2E tests with two disposable accounts: sign-up/sign-in/sign-out, data isolation, product/customer/order/expense CRUD, OCR extraction/save/reload, upload validation, and owner/admin access denial.
3. Review every table's RLS policy set and all SECURITY DEFINER functions with a least-privilege matrix. Do not remove policies or revoke function grants without disposable-account regression tests.
4. Configure Auth redirect URLs, email confirmation/reset flow, rate limits, and abuse protections for the actual production domain.

### P1 — Core business correctness
1. Implement an atomic, server-side order workflow that persists order items and calculates totals from trusted product prices.
2. Define inventory semantics explicitly: reserve/deduct only at the correct confirmed status; prevent negative stock; lock product rows; make retries idempotent.
3. Add order detail/receipt views and accurate customer linkage; do not infer customer identity from a display string.
4. Add server-side validation for numeric amounts, positive quantities, currency, and allowed state transitions.
5. Make cloud/local data status explicit and provide a safe retry path; avoid silent local-only fallback for records users believe are in the cloud.

### P1 — Billing and payment safety
1. Keep all payment requests pending until trusted recipient-side confirmation is available. OCR and AI anomaly detection are not proof of payment.
2. Use immutable server-created payment intents with amount/currency/plan snapshots, expiry, unique references, duplicate detection, and idempotent activation.
3. Never store a private QR image or payment secrets in the public repository or client bundle.
4. Confirm gateway/API availability, merchant eligibility, fees, and sandbox access directly with the payment provider before promising automation.

### P2 — Reliability, accessibility, and operations
- Add automated browser tests and API/RLS isolation tests.
- Add structured error reporting that excludes secrets, receipts, and sensitive customer data.
- Add backup/restore rehearsal and data export/import validation.
- Add accessibility checks (keyboard focus, labels, contrast, reduced motion) and test mobile widths.
- Add dependency pinning/SBOM and a lightweight dependency vulnerability scan.
- Add bilingual Burmese/English coverage checks; current language toggle should be audited for all visible labels, errors, and dialogs.
- Add privacy/retention notice for OCR documents and customer records.

## Test status
- Latest known frontend static GitHub Actions run passed at commit `7224e07aaaf730cdd4d9eb9a543c1825de4620ee`.
- This audit did not run browser E2E, real Storage upload, two-user isolation, payment reconciliation, or POS transaction tests.
- Passing static checks must not be described as full production readiness.

## Deployment gate
Keep PR #1 in draft until P0 checks and review are complete. Do not merge or deploy this branch as a claim that upload, POS inventory, or payment automation is complete.
