-- Keep KPay receipt Storage policies functional after moving the
-- platform-admin SECURITY DEFINER helper out of the exposed public schema.

ALTER POLICY "Admins delete KPay receipts"
  ON storage.objects
  USING (
    bucket_id = 'kpay-receipts'
    AND (SELECT private.current_user_is_platform_admin())
  );

ALTER POLICY "Users read own KPay receipts"
  ON storage.objects
  USING (
    bucket_id = 'kpay-receipts'
    AND (
      (storage.foldername(name))[1] = ((SELECT auth.uid()))::text
      OR (SELECT private.current_user_is_platform_admin())
    )
  );
