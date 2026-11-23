-- Production hardening: keep trigger-only SECURITY DEFINER functions internal.
-- Trigger execution does not require callers to have EXECUTE on the trigger function.
REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.initialize_teacher_trial() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.northstar_assign_free_plan() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.provision_teacher_trial() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.sync_platform_admin_allowlist() FROM PUBLIC, anon, authenticated;

-- POS RPC is not wired into the production UI and has not passed authorization,
-- pricing, pending-stock, and idempotency review. Keep it unavailable until hardened.
REVOKE ALL ON FUNCTION public.northstar_create_pos_sale(
  uuid, integer, numeric, uuid, text, text, text
) FROM PUBLIC, anon, authenticated;
