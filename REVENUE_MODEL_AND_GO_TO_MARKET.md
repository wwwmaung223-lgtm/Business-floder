# Northstar Business OS — Revenue Model and Go-to-Market Plan

**Purpose:** Turn Northstar into a sustainable SaaS business that earns recurring revenue for its operator while giving Myanmar small businesses a useful free starting point.
**Budget:** Strict $0 for launch. No paid infrastructure, paid ads, or paid integrations assumed.
**Status:** Business design based on read-only inspection. No production database, payment, or pricing changes made.

## 1. Recommended business model

Use a **freemium SaaS + optional paid setup services** model.

- Free plan creates a low-friction way for shops to try the product and build trust.
- Monthly subscriptions unlock capacity and higher-value features.
- Optional one-time onboarding services create early cash flow before the SaaS customer base becomes large.
- Referral partnerships with local accountants, POS resellers, shop consultants, and business communities can reduce acquisition costs.
- Do not rely on advertising revenue at launch. It needs scale and can weaken trust in a business-management product.

Primary target customers: small retailers, mini-marts, online/social-commerce sellers, cafes, and service businesses that need sales, stock, customer, and finance records.

## 2. Existing production plan catalog (verified read-only)

The production `plans` table currently contains four active monthly plans:

| Plan | Current price | Intended positioning |
|---|---:|---|
| Free | 0 MMK/month | Solo shop testing and basic daily records |
| Starter | 9,900 MMK/month | One small shop ready to use more products and staff |
| Growth | 29,900 MMK/month | Growing shop needing reports, OCR, export, and automation |
| Business | 79,900 MMK/month | Larger team, advanced features, and multi-branch use |

The current `plan_features` catalog already differentiates product/customer limits, sales history, staff, reports, export, OCR, AI assistant, automation, and multi-branch features. Keep this as the starting structure; do not change prices or feature flags in production as part of this review.

## 3. Market price positioning (public competitor snapshot, checked 21 Nov 2026)

Public Myanmar POS pricing pages observed during research include:
- ShopMaster: Starter 9,900 MMK/month; Growth 27,000 MMK per 3 months; Pro 89,000 MMK/year. https://shopmastermm.org/pricing
- Htoomyat: Business 29,000 MMK/month; Pro 59,000 MMK/month. https://www.htoomyat.cloud/
- Irratech Myanmar: Starter 50,000 MMK/month; Growth 100,000 MMK/month. https://www.irratechmyanmar.com/en/pricing
- YangonPOS: 30,000–50,000 MMK/month. https://yangonpos.com/plans
- inpayar: Standard 100,000 MMK/month; Pro 150,000 MMK/month. https://inpayar.com/pricing

These are public advertised prices, not independently verified sales volumes or proof of willingness to pay. Northstar's current 9,900 / 29,900 / 79,900 MMK ladder spans the lower-to-middle portion of the visible market. Validate with real shop interviews and paid pilots before increasing prices.

## 4. Suggested offer design

Keep the existing production prices for the first validation period. Explain each plan in terms of outcomes rather than a long feature list.

### Free — 0 MMK/month
- Basic POS/order records and small product/customer limits.
- Suitable for one owner learning the workflow.
- Clear upgrade prompt only when the user needs more capacity or premium tools.

### Starter — 9,900 MMK/month
- Small-shop daily sales and stock workflow.
- Higher product/customer capacity and a small number of staff seats.
- Core sales history and basic reports.

### Growth — 29,900 MMK/month
- Advanced reports and data export.
- OCR and AI allowance with clear usage limits.
- Workflow automation and growing-team support.

### Business — 79,900 MMK/month
- Larger staff allowance and multi-branch support.
- Advanced reporting, OCR/AI capacity, and workflow controls.
- Priority onboarding/support only once it can actually be delivered.

Do not advertise any feature as included until the application and server-side entitlements enforce it. The current feature catalog is not proof that all corresponding UI workflows are complete.

## 5. Early cash-flow services (optional, manual)

Offer these only when the operator can deliver the work reliably:
- Guided setup and first product import: suggested pilot price 25,000–50,000 MMK one-time.
- Data cleanup / spreadsheet import: quote by file size and quality; do not promise a fixed price before inspection.
- Staff training session: suggested pilot price 15,000–30,000 MMK.
- Custom reports or integrations: quote separately after scope review.

These are suggested test prices, not market-validated rates. Keep services optional so the product remains self-serve.

## 6. Revenue scenarios (gross subscription revenue, not profit)

Illustrative scenarios using current monthly list prices:

| Paying customers | Mix | Gross monthly recurring revenue |
|---|---|---:|
| Early validation | 10 Starter + 3 Growth | 188,700 MMK |
| First milestone | 20 Starter + 10 Growth + 2 Business | 656,800 MMK |
| Growth milestone | 40 Starter + 20 Growth + 5 Business | 1,195,500 MMK |

These are arithmetic scenarios only, not forecasts or guarantees. Actual net income will be lower after payment fees, taxes, refunds, support time, hosting limits, and any operating costs.

## 7. Customer acquisition with $0 spend

1. Build a short Burmese/English demo showing a shop owner entering products, recording a sale, checking stock, and reviewing a daily summary.
2. Recruit 5–10 pilot shops from existing personal/business networks and relevant Facebook, TikTok, and Telegram communities. Do not spam groups or claim endorsements.
3. Offer a time-limited assisted setup to the first pilot shops in exchange for honest feedback and permission before publishing any testimonial.
4. Publish short practical videos: stock mismatch, daily sales closing, customer history, expense tracking, and how to move from notebook/Excel to Northstar.
5. Add a referral code or tracked referral process only after billing and attribution are implemented safely.
6. Interview users after 7 and 30 days; measure activation, weekly use, support burden, paid conversion, and cancellations.

Suggested first validation target: 10 active pilot businesses, then 3 paying customers. Do not treat sign-ups or likes as revenue validation.

## 8. Myanmar payment collection — safe launch path

Do not build a custom payment gateway or claim automatic payment confirmation at the $0 launch stage.

Recommended initial flow:
1. The operator uses their own registered merchant/bank account and displays their own approved merchant QR or bank-transfer details.
2. Customer chooses a Northstar plan and sees the exact amount, billing period, and payment instructions.
3. Customer submits a transaction reference and payment date in an authenticated upgrade request.
4. The platform operator independently checks the merchant transaction history and amount.
5. Only then does a trusted server-side admin action activate the subscription and record the verified reference.
6. Customer sees request status and subscription expiry.

Never activate a plan based only on a screenshot or user-submitted text. Do not collect customer payments on behalf of shops; Northstar subscription fees should settle directly to the operator's own merchant account.

Wave Money's official help page says Wave Merchant users can accept WaveQR and MMQR, and merchant registration requires a valid NRC and active registered mobile number with KYM verification: https://www.wavemoney.com.mm/help-center/
Wave's merchant partner page describes static QR, dynamic QR/POS, and MMQR merchant options: https://www.wavemoney.com.mm/partner/
MMQR is intended to support payments from participating wallets/apps; details and merchant onboarding must be confirmed with the chosen provider before promising in-app automated checkout: https://www.moi.gov.mm/news/67733

Do not assume that a personal wallet QR is approved for commercial collection. Confirm account type, merchant terms, transaction limits, settlement timing, and fees with the provider.

## 9. Billing implementation gaps found in read-only review

Existing production schema:
- `plans`: plan catalog and MMK monthly price.
- `plan_features`: feature entitlements and limits.
- `subscriptions`: active plan, dates, and payment reference.
- `subscription_requests`: user upgrade request, requested plan, status, note, and review metadata.
- `usage_records`: per-user feature usage counters.

Existing policies let authenticated users read active plans/features, read their own subscription and own upgrade requests, and create their own pending upgrade requests. Platform owner/admin policies manage subscription requests and subscriptions.

Important gaps:
1. `subscription_requests` has no dedicated `payment_method`, `payment_reference`, `amount_mmk`, or `billing_period` columns. The current review RPC writes the supplied payment reference into the generic `note` field when approving or rejecting a request.
2. The current `northstar_review_subscription_request` RPC requires a payment reference even for rejection.
3. The RPC sets subscription expiry to one month regardless of the plan's `billing_period`; annual billing is not supported by this function.
4. A plan request does not snapshot the price at request time. If a plan price changes before review, the amount expected by the reviewer may be unclear.
5. The current browser app does not show a complete customer-facing pricing/upgrade/payment-request flow.
6. Feature flags/limits must be enforced server-side; hiding buttons in the browser is not security.
7. Usage counting and limits must be atomic and tested against concurrent requests.

## 10. Proposed billing schema and workflow (design only)

Before production implementation, propose a migration that adds:
- `subscription_requests.payment_method` (allowlisted text),
- `subscription_requests.payment_reference` (dedicated text, length-limited),
- `subscription_requests.amount_mmk` (integer snapshot),
- `subscription_requests.billing_period` (allowlisted monthly/annual),
- optionally `subscription_requests.proof_object_path` only if secure private proof storage is genuinely needed.

Add constraints for valid statuses, nonnegative amount, allowed billing periods, and reasonable reference length. Keep payment proof optional; a transaction reference checked against the merchant statement may be safer and simpler at launch.

Review and replace the current subscription review RPC only after:
- rejection no longer requires a payment reference;
- approval checks the requested plan and snapshotted amount;
- activation period matches the requested billing period;
- duplicate approvals are prevented with row locking and status checks;
- an immutable audit event records who approved/rejected, when, amount, plan, and reference;
- only trusted platform admins can activate a plan;
- customer-visible status and expiry are correct.

## 11. Launch gates

- [ ] Confirm the operator's merchant account and permitted QR/payment method.
- [ ] Interview 10 target shops and validate the plan ladder.
- [ ] Finish core POS sale and stock transaction before charging customers for POS reliability.
- [ ] Complete tenant-aware roles and RLS.
- [ ] Build customer pricing/upgrade request UI.
- [ ] Add dedicated payment request fields and safe admin review workflow.
- [ ] Enforce plan limits server-side and test concurrent usage.
- [ ] Test synthetic subscriptions, approvals, rejections, expiry, duplicate requests, and unauthorized users.
- [ ] Publish clear Burmese/English terms, cancellation, refund, data export, and support policy.
- [ ] Obtain explicit approval before any production DDL, payment integration, or deployment.

## 12. What not to do

- Do not promise guaranteed income or a guaranteed customer count.
- Do not add paid ads, paid tools, or paid infrastructure while the launch budget is $0.
- Do not build automated wallet payment integration before a verified merchant/provider agreement and API documentation.
- Do not store payment screenshots in a public bucket.
- Do not activate subscriptions based on unverified screenshots.
- Do not advertise AI/OCR/automation limits as working until enforced and measured.
- Do not merge or deploy this plan without implementation tests and explicit rollout approval.
