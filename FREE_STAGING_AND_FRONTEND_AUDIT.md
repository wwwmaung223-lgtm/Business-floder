# Zero-Cost Staging Strategy and Frontend Audit

## Cost constraint

The owner selected a strict $0 budget. Do not create a Supabase paid development branch or a second Supabase project without explicit new approval. The Supabase branch quote returned during planning was $0.01344/hour (about $9.81 for 730 hours), so it is outside the approved budget.

## Safe $0 workflow

1. Keep the existing production Supabase project untouched.
2. Prepare and review SQL migrations as files in this GitHub branch only. Do not execute them against production.
3. Use a local PostgreSQL/Supabase-compatible environment only if it can be installed and run without paid services; document setup and resource requirements first.
4. Prefer schema-only fixtures and synthetic test accounts/data. Never copy real customer or business personal data into an untrusted environment.
5. If a local database/runtime is not available to the owner, keep this stage as static SQL review and automated source-level tests; label database integration tests as NOT RUN.
6. Keep all work on the security branch and use the existing draft PR. Do not merge or deploy until staging tests and rollback are complete.

## Frontend source audit (index.html)

Source inspected from branch at commit `a866b74ee88d3c16249dc9f6170b474dccc3d9d8`.

### Confirmed implementation details

- Single-file HTML app titled `Northstar Business OS · V1.4 Glass`.
- Supabase JS client is used for authentication and data operations.
- Product, customer, order, and finance writes include `user_id: currentUser.id`; product deletion additionally filters by both product ID and current user ID.
- Cloud load reads products, customers, orders, and finance records. OCR notes are read from `ocr_notes` with localStorage fallback.
- OCR uses Tesseract.js in the browser; language comes from the OCR language selector.
- OCR note saving inserts into `ocr_notes` with `user_id: currentUser.id`.
- Image upload targets Storage bucket ID `User Uploads`, path prefixed with current user's auth UUID.
- The actual bucket inventory found only `product images` and `User Uplads`; neither is `User Uploads`. Existing upload flow is therefore expected to fail unless an unobserved bucket is created or bucket ID is corrected.
- UI owner-area navigation checks `currentUser.app_metadata.role`; this is UI gating only and must not be treated as database authorization.
- POS/stock/team management functionality is not visibly wired in the inspected single-file frontend excerpt; database RPCs exist but require a separate complete cross-reference before changes.

### Security review requirements before code edits

- Audit every dynamic `innerHTML` path and confirm untrusted values pass through a context-appropriate encoder. HTML text escaping alone is not sufficient for JavaScript, URL, CSS, or attribute contexts.
- Keep authorization in RLS/RPCs, not in hidden navigation or client-side role checks.
- Confirm all fetches and writes are tenant-scoped after the owner/business model is defined.
- Validate uploaded MIME type and size on both client and Storage policy; never rely on client checks alone.
- Keep publishable Supabase key only in browser code; never put service-role or secret keys in the frontend.
- Preserve current layout, navigation, responsive behavior, and transitions during security work.

## Status

- No code changes to `index.html` in this commit.
- No production database changes.
- No deployment.
- Database integration tests have NOT been run.
