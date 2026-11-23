# SECURITY DEFINER Trigger Function ACL Review

Date: 2026-11-21
Project: Northstar Business OS
Scope: read-only production metadata inspection; proposed remediation only.

## Verified trigger attachment

Two trigger functions in the exposed `public` schema are attached to `auth.users`:

- `public.handle_new_user()` — AFTER INSERT trigger `on_auth_user_created`.
- `public.northstar_assign_free_plan()` — AFTER INSERT trigger `northstar_new_user_free_plan`.

## Verified effective privileges

A read-only privilege check returned the following for both functions:

| Function | SECURITY DEFINER | anon EXECUTE | authenticated EXECUTE | service_role EXECUTE |
|---|---:|---:|---:|---:|
| `handle_new_user()` | Yes | Yes | Yes | Yes |
| `northstar_assign_free_plan()` | Yes | Yes | Yes | Yes |

Both functions have default ACLs (no explicit per-function ACL recorded in `proacl`).

## Function-specific review

### `handle_new_user()`

- SECURITY DEFINER.
- `search_path` is explicitly empty (`search_path=""`).
- Function inserts a profile using the new auth user's ID and supplied full name metadata.
- It is trigger-attached, and does not need to be callable as a direct public RPC endpoint for the observed signup flow.

### `northstar_assign_free_plan()`

- SECURITY DEFINER.
- `search_path` is set to `public`.
- Function inserts the free subscription for the newly created auth user and returns the trigger row.
- The table reference in the inspected function body is schema-qualified as `public.subscriptions`; an empty search path should therefore be considered as an additional hardening option after exact source review and signup regression testing.
- It is trigger-attached, and does not need to be callable as a direct public RPC endpoint for the observed signup flow.

## Proposed narrow ACL remediation — NOT EXECUTED

After confirming that no application or external client calls these trigger functions directly, stage a narrow privilege change for these two exact signatures only:

```sql
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.northstar_assign_free_plan() FROM PUBLIC, anon, authenticated;
```

Do not revoke EXECUTE from service_role or postgres as part of this proposal. PostgreSQL checks the function privilege when a trigger is created, not on every trigger invocation; nevertheless, this must be confirmed against the deployed Postgres behavior and a synthetic signup test in a disposable test environment before rollout. Re-check effective privileges after the change and verify that both auth.users triggers still create the profile and free subscription.

For `northstar_assign_free_plan()`, separately evaluate changing its function-level setting to `SET search_path = ''` (all object references must remain schema-qualified) and retest signup.

## Important non-action

This review does NOT recommend blanket revocation from all `northstar_*` functions. Several are intentional authenticated RPC endpoints; their authorization checks, business scope, and role semantics need individual review. Do not change their grants based solely on the generic SECURITY DEFINER advisor warning.

## Required verification before production

1. Confirm no direct PostgREST/client references to either trigger function.
2. Apply the narrow ACL change only in a disposable test database first.
3. Register a synthetic user and verify profile creation and exactly one free subscription.
4. Confirm direct RPC execution is denied to anon and authenticated.
5. Confirm service_role/postgres maintenance workflows remain functional.
6. Run Supabase security advisors and compare the exact two findings.
7. Prepare rollback SQL and obtain explicit rollout approval before production changes.

## Status

- Trigger attachment and function ACL metadata: verified read-only.
- Proposed ACL changes: NOT executed.
- Signup regression test: NOT RUN.
- Production changes: none.

Supabase guidance: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
