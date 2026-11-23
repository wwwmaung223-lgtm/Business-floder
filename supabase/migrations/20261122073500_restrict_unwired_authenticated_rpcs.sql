-- Keep SECURITY DEFINER helpers required by RLS policies callable:
-- has_subscription_access() and is_platform_admin() remain available.
-- The current deployed frontend does not call these nine RPCs. Keep them
-- unavailable through the public PostgREST API until their UI integration
-- and authorization flows are explicitly reviewed.
REVOKE ALL ON FUNCTION public.northstar_accept_team_invites() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.northstar_add_team_member(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.northstar_adjust_stock(uuid, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.northstar_current_business_owner_id() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.northstar_current_team_role() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.northstar_has_permission(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.northstar_remove_team_member(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.northstar_review_subscription_request(uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.review_kpay_payment(uuid, boolean, text) FROM PUBLIC, anon, authenticated;
