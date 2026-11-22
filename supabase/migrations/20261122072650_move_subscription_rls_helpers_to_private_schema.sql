-- Move authenticated RLS helpers out of the API-exposed public schema.
-- Preserve the existing subscription/admin policy semantics while preventing
-- direct RPC calls with arbitrary user identifiers.

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.current_user_has_subscription_access()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT (SELECT auth.uid()) IS NOT NULL
    AND (
      EXISTS (
        SELECT 1
        FROM public.teacher_subscriptions s
        WHERE s.user_id = (SELECT auth.uid())
          AND (
            s.status = 'admin_free'
            OR (s.status = 'trial' AND s.trial_ends_at + interval '3 days' > now())
            OR (s.status = 'active' AND s.current_period_ends_at + interval '3 days' > now())
            OR (s.status = 'grace' AND coalesce(s.grace_ends_at, s.current_period_ends_at + interval '3 days') > now())
          )
      )
      OR EXISTS (
        SELECT 1
        FROM public.platform_admins a
        WHERE a.user_id = (SELECT auth.uid())
      )
    );
$function$;

CREATE OR REPLACE FUNCTION private.current_user_is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT (SELECT auth.uid()) IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.platform_admins a
      WHERE a.user_id = (SELECT auth.uid())
    );
$function$;

REVOKE ALL ON FUNCTION private.current_user_has_subscription_access() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.current_user_is_platform_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.current_user_has_subscription_access() TO authenticated;
GRANT EXECUTE ON FUNCTION private.current_user_is_platform_admin() TO authenticated;

ALTER POLICY "Subscription required for homework_assignments"
  ON public.homework_assignments
  USING ((SELECT private.current_user_has_subscription_access()))
  WITH CHECK ((SELECT private.current_user_has_subscription_access()));

ALTER POLICY "Subscription required for lesson_plans"
  ON public.lesson_plans
  USING ((SELECT private.current_user_has_subscription_access()))
  WITH CHECK ((SELECT private.current_user_has_subscription_access()));

ALTER POLICY "Subscription required for question_bank"
  ON public.question_bank
  USING ((SELECT private.current_user_has_subscription_access()))
  WITH CHECK ((SELECT private.current_user_has_subscription_access()));

ALTER POLICY "Subscription required for teacher quiz access"
  ON public.quiz_assessments
  USING ((SELECT private.current_user_has_subscription_access()))
  WITH CHECK ((SELECT private.current_user_has_subscription_access()));

ALTER POLICY "Subscription required for teacher submission deletes"
  ON public.quiz_submissions
  USING ((SELECT private.current_user_has_subscription_access()));

ALTER POLICY "Subscription required for teacher submission reads"
  ON public.quiz_submissions
  USING ((SELECT private.current_user_has_subscription_access()));

ALTER POLICY "Subscription required for teacher submission updates"
  ON public.quiz_submissions
  USING ((SELECT private.current_user_has_subscription_access()))
  WITH CHECK ((SELECT private.current_user_has_subscription_access()));

ALTER POLICY "Subscription required for teacher_classes"
  ON public.teacher_classes
  USING ((SELECT private.current_user_has_subscription_access()))
  WITH CHECK ((SELECT private.current_user_has_subscription_access()));

ALTER POLICY "Admins review payment requests"
  ON public.payment_requests
  USING ((SELECT private.current_user_is_platform_admin()))
  WITH CHECK ((SELECT private.current_user_is_platform_admin()));

ALTER POLICY "Users read own payment requests"
  ON public.payment_requests
  USING (
    user_id = (SELECT auth.uid())
    OR (SELECT private.current_user_is_platform_admin())
  );

ALTER POLICY "Admins manage subscriptions"
  ON public.teacher_subscriptions
  USING ((SELECT private.current_user_is_platform_admin()))
  WITH CHECK ((SELECT private.current_user_is_platform_admin()));

ALTER POLICY "Users read own subscription"
  ON public.teacher_subscriptions
  USING (
    user_id = (SELECT auth.uid())
    OR (SELECT private.current_user_is_platform_admin())
  );

REVOKE EXECUTE ON FUNCTION public.has_subscription_access(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.is_platform_admin() FROM PUBLIC, anon, authenticated;
