-- Remove the unnecessary public RPC exposure of the platform-admin predicate.
-- The only current caller is public.review_kpay_payment(...), which is
-- SECURITY DEFINER and owned by postgres. Its nested call continues to run
-- with the function owner's privileges; authenticated users do not need
-- direct EXECUTE permission on this helper.
--
-- Keep review_kpay_payment executable by authenticated users because it
-- performs its own server-side platform-admin authorization check.
REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC, anon, authenticated;
