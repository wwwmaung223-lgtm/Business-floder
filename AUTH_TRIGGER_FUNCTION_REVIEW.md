# Auth Trigger Function and Effective EXECUTE Grant Review
Date: 2026-11-21
Production inspection only. No changes made.

## handle_new_user()
- SECURITY DEFINER: yes
- search_path: empty string (fixed empty search path)
- Effective EXECUTE grants: PUBLIC, postgres
- Trigger body inserts `new.id` and `new.raw_user_meta_data ->> 'full_name'` into `public.profiles`.
- Security Advisor flags this function as executable by anon and authenticated roles.
- The function is intended as an auth trigger, not a general client RPC. Keep trigger execution working while removing unintended direct EXECUTE access, after confirming trigger invocation semantics and testing signup in a free local-compatible environment.
- Empty search_path is a good hardening control; body uses schema-qualified `public.profiles`.

## northstar_assign_free_plan()
- SECURITY DEFINER: yes
- search_path: public
- Effective EXECUTE grants: PUBLIC, postgres
- Trigger body inserts a free active subscription for `new.id` and ignores an existing user subscription.
- Security Advisor flags this function as executable by anon and authenticated roles.
- This is intended as an auth trigger, not a general client RPC. It needs an explicit fixed search_path strategy and removal of unintended direct EXECUTE access, while preserving trigger behavior. Test sign-up and duplicate-trigger behavior before changing ACLs.

## Important distinction
The advisor warning and effective ACL inspection establish broad EXECUTE grants. They do not by themselves prove a successful exploit through PostgREST for trigger-returning functions. Do not overstate this as a reproduced remote exploit. The safe remediation is to limit direct invocation while retaining required trigger execution, then verify with signup tests and re-run Security Advisors.

## Verification
- Function definitions and effective ACLs: inspected read-only.
- ACLs changed: no.
- Trigger/signup tests: NOT RUN.
- Production DDL: NOT PERFORMED.
