# Supabase Auth Email Confirmation Setup

Status: frontend callback support is committed; the hosted Supabase email templates and redirect allowlist still require dashboard verification.

## Why this is needed

The current confirmation email uses Supabase's default confirmation URL on `*.supabase.co`. On the owner's mobile network/browser, opening that host produced `ERR_QUIC_PROTOCOL_ERROR`. The app's same-origin Auth relay fixes Auth API requests made by the app, but it cannot intercept a link opened directly from an email to the Supabase hostname.

The frontend now accepts a Supabase `token_hash` on the Vercel app origin and verifies it with `supabase.auth.verifyOtp`. The email template must therefore link to the app origin and include the token hash.

## Dashboard settings

In Supabase Dashboard → Authentication → URL Configuration:

- Set the Site URL to the canonical Northstar app URL selected for the release.
- Add that exact URL to the Redirect URLs allowlist.
- Add any Preview URL used for testing only if it is needed, and remove temporary preview URLs after testing.

Do not use a random or expired deployment URL as the permanent Site URL.

## Confirm signup email template

In Authentication → Email Templates → Confirm signup, use:

```html
<h2>Confirm your email address</h2>
<p>Confirm your email to finish signing up.</p>
<p>
  <a href="{{ .RedirectTo }}/?token_hash={{ .TokenHash }}&amp;type=email">
    Confirm email address
  </a>
</p>
```

## Reset password email template

In Authentication → Email Templates → Reset Password, use:

```html
<h2>Reset your password</h2>
<p>Follow this link to choose a new password.</p>
<p>
  <a href="{{ .RedirectTo }}/?token_hash={{ .TokenHash }}&amp;type=recovery">
    Reset password
  </a>
</p>
```

The app calls `resetPasswordForEmail` with the app origin as `redirectTo`, and handles the `recovery` token on return.

## Verification checklist

1. Create a fresh test account using an email inbox the owner can access.
2. Confirm the email link opens the canonical Vercel app origin, not `*.supabase.co`.
3. Verify the app shows the authenticated workspace after signup confirmation.
4. Sign out and sign back in with the new account.
5. Request password recovery; confirm the link opens the app origin and presents the new-password form.
6. Set a new password and verify sign-in with it.
7. Check Auth logs for successful verification and confirm no duplicate test users were created.

## Current release boundary

- Frontend callback implementation: committed in `d821d5246f054859fd82a2c46a2aadc1d1f44886`.
- GitHub Frontend static checks: success (run #96).
- Vercel Preview for that exact commit: READY.
- Hosted email templates, Site URL, redirect allowlist, and real email round-trip: not verified from the available Supabase connector.
- Do not merge the draft PR or change Production deployment until the owner completes the dashboard template/URL settings and the live signup + recovery checklist passes.
