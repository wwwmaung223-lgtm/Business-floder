# Storage Bucket Remediation Plan

Date: 2026-11-21
Project: Northstar Business OS
Status: design-only; no production Storage changes made

## Verified current state

A fresh read-only query of `storage.buckets` joined to `storage.objects` returned:

| Bucket ID | Public | Objects | Max size | Allowed MIME types |
|---|---:|---:|---:|---|
| `product images` | No | 0 | 10 MiB | JPEG, PNG, WebP |
| `User Uplads` | No | 2 | 10 MiB | JPEG, PNG, WebP |

A fresh read-only query of `pg_policies` for `storage.objects` returned eight authenticated policies:
- INSERT / SELECT / UPDATE / DELETE scoped to first path segment = `auth.uid()` for `product images`.
- INSERT / SELECT / UPDATE / DELETE scoped to first path segment = `auth.uid()` for `User Uploads`.

No policy in this inventory targets the existing bucket ID `User Uplads`.

The frontend's `uploadImage()` function calls `supabaseClient.storage.from('User Uploads').upload(...)`. Therefore, the frontend and policy name agree with each other, but the actual bucket with that exact ID is absent. The existing `User Uplads` bucket is a different ID and contains two objects.

## Impact

- Uploads to `User Uploads` are expected to fail until a bucket with that exact ID exists.
- Do not assume the two files in `User Uplads` are disposable or unused.
- Do not change `storage.objects` or `storage.buckets` rows directly with SQL. Supabase documents Storage metadata as read-only; object and bucket operations must use the Storage API.
- Keep user receipts, OCR uploads, and other potentially sensitive files in private buckets. A public bucket makes file retrieval available to anyone with the asset URL; private bucket downloads remain subject to RLS or signed URLs.

## Candidate resolution

Preferred low-risk candidate, subject to owner approval and a tested Storage API operation:
1. Preserve the existing `User Uplads` bucket and its two objects unchanged.
2. Create a new **private** bucket with the exact ID `User Uploads`, matching the existing frontend and its four user-folder policies.
3. Set the same 10 MiB limit and JPEG/PNG/WebP allowlist as the existing upload bucket unless the product requirement is intentionally changed.
4. Test with a synthetic authenticated user: upload one disposable image to `<auth.uid()>/<random-name>`; confirm that same user can access only their own object; confirm a second user and anonymous client cannot read or overwrite it.
5. Test list/download/delete separately only if the UI needs those operations. Current upload uses `upsert:false`; the Storage docs state that a basic upload needs INSERT, while upsert additionally needs SELECT and UPDATE.
6. Only after the new bucket passes tests, consider a separate cleanup decision for the old misspelled bucket. No automatic migration or deletion.

Alternative: change the frontend and policy identifiers to `User Uplads`. This is not preferred because it preserves a typo in the public-facing implementation and still requires validating the existing two objects' purpose and policy coverage.

## Additional frontend guardrails

Before calling Storage upload, the client should reject:
- Files with a MIME type outside JPEG, PNG, or WebP.
- Files larger than 10 MiB.
- Empty or missing files.

These checks improve the user experience but are not a security boundary. Bucket restrictions and RLS remain authoritative.

## Acceptance tests

- [ ] Canonical bucket ID exists and is private.
- [ ] Bucket size and MIME restrictions match the intended policy.
- [ ] Authenticated user A can upload to A's folder.
- [ ] User A cannot read, list, overwrite, or delete user B's files.
- [ ] User B cannot read, list, overwrite, or delete user A's files.
- [ ] Anonymous upload and private download are denied.
- [ ] Unsupported MIME and oversized files are rejected by both UI and Storage.
- [ ] Existing two objects in `User Uplads` remain unchanged.
- [ ] No service-role key is present in browser code.
- [ ] Browser E2E tests pass on mobile and desktop.

## Official documentation checked

- Storage Access Control: https://supabase.com/docs/guides/storage/security/access-control
- Storage Buckets: https://supabase.com/docs/guides/storage/buckets/fundamentals
- Storage Schema: https://supabase.com/docs/guides/storage/schema/design

Supabase's current docs say private bucket operations are subject to RLS; upload requires an INSERT policy; upsert requires SELECT and UPDATE; and Storage schema records should be treated as read-only while operations go through the Storage API.

## Not performed

No bucket was created, renamed, made public, or deleted. No objects or policies were changed. No production SQL writes, Storage API operations, or deployments were performed. Upload/download/list/delete tests remain NOT RUN.
