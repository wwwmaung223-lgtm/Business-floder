# Personal KBZPay Receipt Verification Workflow

Date: 2026-11-21
Status: design specification only
Account: owner-confirmed personal KBZPay
Budget: strict $0
Production changes: none

## Executive decision

A personal KBZPay receive QR is not a merchant payment API. A receipt image and its last six transaction-reference characters can be OCR-read and matched as screening signals, but neither proves that funds reached the recipient. Never activate a paid subscription from a screenshot, OCR result, customer-entered reference, or AI confidence score alone.

The safe interim workflow is AI-assisted receipt screening with a pending status, followed by confirmation against recipient-side KBZPay transaction history. To reduce manual work, apply for KBZPay Partner / merchant acceptance and ask KBZ Bank whether an approved transaction-status API, merchant portal export, webhook, or statement feed is available. Do not assume an API exists until KBZ confirms it in writing.

KBZPay's public MMQR partner page lists an individual current bank account as one possible account document, alongside business registration/licence and other application materials. This does not mean a personal wallet QR is already a merchant account or has an API:
- https://www.kbzpay.com/my/products/mmqr
- https://play.google.com/store/apps/details?id=com.kbzbank.kpaypartner

## Customer payment journey

1. Customer signs in and selects a plan. Server creates a unique pending payment intent with immutable amount snapshot, plan code, currency MMK, random public reference, and expiry.
2. Website displays the owner's approved KPay QR privately in checkout with the exact amount. Never store the QR image in a public Git repository or embed sensitive details in frontend source.
3. Customer pays in KBZPay, uploads the receipt, and enters the last six characters of the transaction reference. Also request the full transaction reference where visible; six characters alone are not unique enough.
4. Store the receipt in a private bucket with a random object key. Restrict size and MIME type; do not expose public URLs.
5. OCR extracts candidate transaction reference, amount, date/time, payer/payee display text, and any receipt verification data. Store raw OCR text with restricted access and short retention.
6. Deterministic checks compare expected amount, payment-intent time window, normalized last-six, full reference when available, duplicate image hash, duplicate transaction reference, and intent status.
7. AI may explain anomalies and produce risk flags, but it must not decide that funds were received. AI output is advisory and untrusted.
8. Until trusted recipient-side confirmation arrives from an approved KBZ merchant interface/export/API or controlled owner-side account record, payment remains pending_confirmation.
9. A server-only idempotent function marks the payment confirmed and activates the subscription exactly once.
10. Customer sees clear statuses: Submitted → Receipt checks passed → Awaiting KPay confirmation → Paid / Rejected / Needs new receipt. Never show Paid before trusted confirmation.

## Status model

- created: intent generated, not yet paid.
- receipt_submitted: customer supplied receipt and last-six.
- ocr_processed: extraction completed.
- needs_review: ambiguous or conflicting data.
- pending_confirmation: OCR and deterministic checks passed, but recipient-side funds confirmation is missing.
- confirmed: trusted recipient-side record proves the exact transaction and amount.
- rejected: confirmed invalid, duplicate, wrong amount, expired, or not received.
- expired: no valid payment within the intent window.
- refunded: refund confirmed through a trusted record.

Only confirmed may activate a paid plan.

## Agent responsibilities

### 1. Receipt OCR Agent
Extract fields and field-level confidence. Do not infer missing digits or invent transaction IDs. Mark unreadable values null. Image manipulation signals are risk indicators, not proof of fraud.

### 2. Reference Matching Agent
Normalize customer-entered and OCR references. Compare last six; compare full reference when available. Detect last-six collisions. Require amount and time-window agreement. Never accept last-six alone as payment proof.

### 3. Duplicate/Fraud Screening Agent
Check receipt SHA-256, perceptual image hash, normalized transaction reference, payment intent, amount, and reuse history. Flag duplicates and inconsistencies; route to needs_review without accusing the customer.

### 4. Reconciliation Agent
Consume only trusted recipient-side transaction data from an approved API/webhook or controlled owner-side import. Match amount, reference, timestamp, and recipient. If no trusted feed exists, leave pending. Never log into the owner's personal KBZPay app, scrape its UI, or request PIN/OTP.

### 5. Customer Support Agent
Explain payment steps and status in Burmese and English. Never ask for PIN, OTP, password, or card details. Never claim payment succeeded while pending.

## Suggested $0 architecture

- Existing Northstar frontend on Vercel: checkout, receipt upload, status page, bilingual support UI.
- Existing Supabase project: payment intents, receipt metadata, audit trail, private storage, server-side confirmation function.
- n8n Community Edition: orchestration only if it can run on an existing always-on device/server at no extra cost. Do not create a paid hosted account or server.
- Browser Tesseract.js or locally hosted OCR for zero-API-cost extraction. Browser OCR is not a payment verifier.
- Gemini API optional for support/risk explanation only. Do not send full receipts, names, phone numbers, account identifiers, or financial data to a free AI API without reviewing data-use and retention terms. Prefer deterministic code and local OCR.
- Keep secrets and service-role keys server-side. Browser gets publishable keys and scoped short-lived upload URLs only.

## Proposed data model — no SQL applied

### payment_intents
- id UUID primary key
- user_id UUID
- plan_code text
- amount_mmk numeric
- currency text default MMK
- status text with strict allowlist
- public_reference text unique
- expires_at timestamptz
- confirmed_at timestamptz nullable
- created_at timestamptz

### payment_submissions
- id UUID primary key
- payment_intent_id UUID
- storage_object_path text
- receipt_sha256 text
- customer_reference_last6 text
- customer_reference_full text nullable
- ocr_reference text nullable
- ocr_amount_mmk numeric nullable
- ocr_timestamp timestamptz nullable
- ocr_result jsonb restricted to admin/service role
- risk_flags jsonb
- status text
- created_at timestamptz

### payment_confirmations
- id UUID primary key
- payment_intent_id UUID unique
- provider text
- provider_transaction_reference text unique
- amount_mmk numeric
- recipient_account_fingerprint text
- provider_event_id text unique nullable
- confirmed_at timestamptz
- source_record_hash text
- created_at timestamptz

RLS lets customers create/read only their own intent/submission. Customers cannot write confirmation, paid status, amount snapshot, or subscription status. A server-only function inserts confirmations and activates the plan atomically. Add uniqueness constraints and audit records. Avoid storing full bank account numbers or unnecessary payer data.

## Personal-account interim limitation

Without an official transaction feed, no agent can independently know that the owner's personal wallet received the money. Options:
- safest interim: OCR triage + pending status; recipient checks KBZPay transaction history;
- better: ask KBZPay/KBZ Bank about merchant/partner onboarding and approved reconciliation/API access;
- if the bank provides a downloadable recipient transaction history, use a controlled CSV import with restricted access; do not scrape the app or automatically read private SMS.

KBZPay's customer app listing describes receipt QR verification features. This may help verify a receipt in the app, but it is not evidence of an API or automatic recipient-side settlement confirmation:
https://play.google.com/store/apps/details?id=com.kbzbank.kpaycustomer

## Security and privacy

- Never collect KPay PIN, OTP, password, or account login.
- Private receipt storage only; short-lived signed URLs.
- Restrict receipt access to uploader and authorized review service.
- Rate-limit submissions and cap image size.
- Do not expose OCR text or payer identity in logs.
- Publish retention/deletion policy.
- Do not automatically reject solely from AI suspicion.
- Record actor, timestamp, reason, and source for every status change.
- Use idempotency for confirmation and subscription activation.

## Acceptance tests before launch

Wrong last-six; wrong amount; stale receipt; duplicate reference; duplicate image; receipt reused across accounts; low-resolution image; OCR misread; expired intent; concurrent submissions; customer attempts to set status=confirmed; customer attempts to write payment confirmation; duplicate provider webhook; partial/late payment; refund/dispute.
Also verify cross-customer isolation, no paid subscription from OCR alone, exactly-once activation after trusted confirmation, and Burmese/English status messages.

## KBZPay merchant follow-up

Ask KBZPay support:
1. Can this personal account apply for KBZPay Partner / MMQR using an individual current bank account?
2. What KYC/licence documents are required for a sole proprietor or individual SaaS operator?
3. Is an official merchant transaction API, webhook, portal export, or statement feed available for reconciliation?
4. Can online subscription payments be accepted for this business category and QR?
5. What are MDR, settlement, refund, dispute, and daily limits?

Official support email listed by KBZPay: query@kbzpay.com. Never send PIN/OTP or sensitive credentials.

## Current status

- Owner confirmed personal KBZPay account.
- QR was provided in chat; it must not be copied into a public repository.
- Workflow specified; no code, schema, storage, payment, or production settings changed.
- Merchant API availability for this personal account: NOT VERIFIED.
- Automatic bank-side reconciliation: NOT AVAILABLE until KBZ confirms an approved feed/API or partner facility.
- Subscription auto-activation: NOT IMPLEMENTED.
- Strict $0 constraint preserved.
