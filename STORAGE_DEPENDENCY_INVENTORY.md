# Storage Dependency Inventory

Date: 2026-11-21
Project: Northstar Business OS (read-only production inspection)

## Scope and safety

This document records metadata-only SELECT inspection of Supabase Storage buckets, object counts, and `storage.objects` RLS policies. No bucket, object, policy, or application setting was changed. Supabase Storage metadata is treated as read-only; file operations must use the Storage API.

## Current production facts

| Bucket name (exact) | Public | Object count | Max size | Allowed MIME types |
|---|---:|---:|---:|---|
| `product images` | No | 0 | 10 MiB | image/jpeg, image/png, image/webp |
| `User Uplads` | No | 2 | 10 MiB | image/jpeg, image/png, image/webp |

The application upload code calls `supabaseClient.storage.from('User Uploads')`. That exact bucket name does not appear in the bucket inventory. The existing `User Uplads` bucket contains two objects, so it must not be renamed, deleted, recreated, or migrated casually.

## Storage policy inventory

Policies observed on `storage.objects`:

- `product images`: authenticated INSERT, SELECT, UPDATE, and DELETE policies scoped to the first folder segment matching `auth.uid()`.
- `User Uploads`: authenticated INSERT, SELECT, UPDATE, and DELETE policies scoped to the first folder segment matching `auth.uid()`.
- No policy in the inspected set targets the exact existing bucket name `User Uplads`.

This means the frontend bucket identifier and the existing typo bucket are different, while the current policy set targets a third spelling (`User Uploads`) that is absent from the bucket list. The current frontend upload is therefore expected to fail with a missing-bucket response. The two objects in `User Uplads` are not covered by the inspected user-folder policies; access must not be assumed.

## Application dependencies

- `index.html` upload action calls `storage.from('User Uploads').upload(...)`.
- The object path is currently `<auth-user-uuid>/<timestamp>_<sanitized-filename>`.
- The UI's owner/admin tile also labels the bucket `User Uploads`.
- Upload code sets `upsert:false`; it does not need UPDATE/SELECT for an overwrite today, but list/download/delete features still require deliberate matching policies if introduced.

## Safe resolution plan — not executed

1. Inventory the two existing `User Uplads` objects through the Storage API (metadata only first), confirm their purpose and whether the app references them, and preserve a recoverable backup/export before any migration.
2. Decide one canonical bucket name. Do not infer that the misspelled bucket is disposable.
3. Align the frontend bucket ID and all Storage policies with the chosen canonical name as one reviewed change.
4. Confirm the exact allowed operations. For new uploads, an authenticated INSERT policy is required; add SELECT/UPDATE only for explicit read/list or upsert workflows, and DELETE only if the product exposes deletion.
5. Test upload, list, download, and delete using a synthetic test account and disposable file in a free local/test environment before rollout.
6. Verify that one user cannot access another user's folder and that unauthenticated users cannot upload or read private objects.

Supabase documentation confirms that Storage access is enforced by RLS on `storage.objects`; private bucket operations are subject to policies, and Storage metadata should be treated as read-only while object operations go through the Storage API:
- https://supabase.com/docs/guides/storage/security/access-control
- https://supabase.com/docs/guides/storage/buckets/fundamentals
- https://supabase.com/docs/guides/storage/schema/design

## Test status

- Read-only bucket inventory: completed.
- Read-only object counts: completed (2 objects in `User Uplads`; no object paths or customer content reproduced here).
- Read-only Storage RLS policy inventory: completed.
- Actual upload/download/list/delete test: NOT RUN.
- Bucket rename, object migration, policy change, and production deployment: NOT PERFORMED.
