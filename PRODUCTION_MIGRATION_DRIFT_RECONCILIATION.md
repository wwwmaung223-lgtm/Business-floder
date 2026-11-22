# Production Migration-History Reconciliation

**Review type:** Read-only migration ledger, repository, and live PostgreSQL catalog comparison  
**Project:** Existing Northstar Production Supabase project  
**Branch:** `security/rls-permissions-hardening`  
**Production changes:** None  
**Status:** Reconciliation evidence only; do not replay or synthesize migrations.

## Executive summary

The Production migration ledger contains five applied version entries whose matching SQL source files are absent from both the checked-out `main` and the current hardening branch. A sixth entry has a version/name timestamp mismatch: Production records version `20261122071644`, while its name and the tracked migration filename begin with `20261122073500`.

This is a migration-history reproducibility problem. The live schema is the current operational truth; the ledger is evidence of what the migration runner recorded; the repository is not currently a complete source-of-truth archive for every applied migration.

## Ledger-to-repository comparison

| Production version | Ledger name | Repository SQL source | Current assessment |
|---|---|---|---|
| `20261122055410` | `auto_trial_and_student_submission_access` | Missing from main and hardening branch | Recover exact source or reconstruct from reviewed live catalog |
| `20261122071644` | `20261122073500_restrict_unwired_authenticated_rpcs` | Branch file `20261122073500_restrict_unwired_authenticated_rpcs.sql` exists | Version timestamp mismatch; likely corresponding source by exact name, but reconcile ledger metadata and original application record |
| `20261122074501` | `gate_class_students_subscription` | Missing from main and hardening branch | Recover exact source or reconstruct from reviewed live catalog |
| `20261122074634` | `add_teaching_platform_foreign_key_indexes` | Missing from main and hardening branch | Recover exact source or reconstruct from live indexes/constraints |
| `20261122074840` | `gate_homework_submissions_subscription` | Missing from main and hardening branch | Recover exact source or reconstruct from reviewed live catalog |
| `20261122082701` | `grant_kpay_admin_rpcs` | Missing from main and hardening branch | Recover exact source; compare intended grants to current effective ACLs |

The migration list also includes other applied versions whose tracked files are present; they are outside the missing-source set above.

## Exact source and live-state evidence

### 1. The 20261122073500 migration

The branch file `supabase/migrations/20261122073500_restrict_unwired_authenticated_rpcs.sql` exists. It revokes direct EXECUTE for the listed team-management/stock RPCs and `review_kpay_payment(uuid,boolean,text)`. It explicitly says the subscription helper and platform-admin helper remain callable.

Production records the same descriptive name but a different version value (`20261122071644`). Treat this as a ledger/source timestamp discrepancy, not proof that the file was never applied.

### 2. Current Production effective function ACLs

A fresh read-only catalog check returned:

| Function | anon EXECUTE | authenticated EXECUTE | Owner |
|---|---:|---:|---|
| `is_platform_admin()` | No | Yes | postgres |
| `review_kpay_payment(uuid,boolean,text)` | No | Yes | postgres |
| `northstar_accept_team_invites()` | No | No | postgres |
| `northstar_add_team_member(text,text)` | No | No | postgres |
| `northstar_adjust_stock(uuid,integer,text)` | No | No | postgres |
| `northstar_current_business_owner_id()` | No | No | postgres |
| `northstar_current_team_role()` | No | No | postgres |
| `northstar_has_permission(text,text)` | No | No | postgres |
| `northstar_remove_team_member(uuid)` | No | No | postgres |
| `northstar_review_subscription_request(uuid,text,text)` | No | No | postgres |

The explicit ACL for both KPay functions is `{postgres=X/postgres,authenticated=X/postgres}`. The review function's current body calls `public.is_platform_admin()` before selecting and locking the payment request, rejects already-reviewed requests, and writes the payment decision/subscription period in the function transaction.

The Production state is consistent with a later grant of authenticated access to the KPay review workflow after the earlier broad revocation, but the missing `20261122082701_grant_kpay_admin_rpcs.sql` source must be recovered before asserting the exact migration contents or replaying it.

### 3. Trial/device tables remain branch-only

Fresh Production catalog checks confirm `account_pos_trials`, `account_devices`, `subscription_addons`, `current_account_device_is_active()`, and `get_account_entitlements()` are absent in Production. Their branch migration is not applied.

## Safe reconciliation procedure

1. Preserve a read-only export of the complete Production migration ledger and relevant catalog definitions.
2. Search the original migration authoring history, deployment logs, backups, and any available SQL editor history for the exact five missing SQL files.
3. For each missing source, compare its recovered SQL with current Production catalog state, including constraints, indexes, policies, function definitions, and effective ACLs.
4. For version `20261122071644`, verify whether the tracked `20261122073500` SQL is exactly the SQL that was applied. Do not change the ledger or rename files until the migration runner's version semantics and deployment log are confirmed.
5. Recover the exact `grant_kpay_admin_rpcs` SQL and verify its scope against the current ACL table above. Do not infer the full grant list from the filename.
6. Commit canonical historical SQL files or a clearly labeled reconstruction record. Never rewrite historical migration files to make them appear different from what was applied.
7. Only after source reconciliation, prepare a forward-only migration for any desired new state. Test in disposable PostgreSQL first and obtain explicit approval before Production DDL.

## Non-actions and release gate

- No Production SQL, ledger row, schema, ACL, data, or deployment was changed during this review.
- Do not re-run any of the five missing migrations merely because their source files are absent.
- Do not automatically revoke authenticated KPay review execution: the function has an internal platform-admin check and the current workflow depends on an authenticated admin call. Its helper ACL is a separate staged hardening change.
- No isolated PostgreSQL runtime is currently available for migration replay/integration tests. This remains a wait gate.
