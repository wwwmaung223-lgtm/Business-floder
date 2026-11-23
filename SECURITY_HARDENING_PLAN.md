# Northstar Business OS — Security Hardening Plan

Status: Read-only audit completed; no production changes applied.

## Verified findings

- All 15 public application tables inspected have Row Level Security enabled.
- The `products`, `customers`, `orders`, and `finance_records` tables have overlapping permissive policies. PostgreSQL permissive policies combine with OR, so the intended role restrictions must be designed together with removal/replacement of broad policies.
- The current permission helper `northstar_has_permission(feature, action)` is not referenced by existing RLS policies.
- The current data model primarily scopes business records by `user_id`; staff memberships are stored separately in `business_memberships`. A tenant/owner-scope migration must account for existing records and all dependent RPCs.
- The POS and stock RPCs currently contain owner-user assumptions and need review before staff can safely operate on an owner's data.
- Supabase Security Advisor reported SECURITY DEFINER execution exposure and disabled leaked-password protection. Each function's intended caller and grants must be reviewed individually.
- Supabase Performance Advisor reported unindexed foreign keys, RLS auth initplan warnings, and multiple permissive policies.
- Storage configuration contains a likely bucket-ID mismatch: the existing private upload bucket is named `User Uplads`, while frontend upload code and storage policies refer to `User Uploads`. Verify actual intended bucket and existing objects before any change.
- The website is a single `index.html` application. Preserve the current UI and navigation while implementing any approved security changes.

## Safety rules

1. Do not apply database DDL or data migrations to production until a staging project, migration review, test plan, and rollback plan are available.
2. Do not remove or rename storage buckets until frontend references, policies, and existing objects have been checked.
3. Do not expose service-role credentials or place secrets in the browser.
4. Keep changes isolated on this branch and use a pull request for review before merging.
5. Do not claim a test passed unless it was actually executed.

## Implementation sequence

1. Complete read-only inventory of table constraints, indexes, policies, function signatures/definitions/grants, and auth triggers.
2. Design owner/tenant scoping and role-aware policies for Owner, Manager, Cashier, Stock Staff, and Accountant. Ensure old broad permissive policies cannot bypass the new policies.
3. Review and harden SECURITY DEFINER functions individually: explicit caller/role checks, fixed search_path, and least-privilege EXECUTE grants.
4. Update POS/stock RPCs and frontend queries consistently with the chosen tenant model.
5. Resolve the upload bucket naming mismatch without losing existing files.
6. Add migration tests for owner isolation, staff role boundaries, unauthenticated access, cross-business access, POS stock updates, audit logging, and rollback.
7. Deploy only after staging verification and explicit production approval.

## Current state

- This branch contains the audit plan only.
- No production database, live website, or main-branch changes have been made.
