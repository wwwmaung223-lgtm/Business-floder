# Foreign-Key Index Review

**Review type:** Read-only PostgreSQL catalog and Supabase Performance Advisor inspection  
**Project:** Existing Northstar Production database  
**Last checked:** 2026-11-22  
**Production changes:** None

## Current finding

The current Supabase Performance Advisor reports **21 unindexed foreign keys**. A separate catalog check requiring a valid, ready, non-partial index whose leading key columns exactly match each FK column sequence returned **22 candidates**.

The one-count difference is understood: `source_media.user_id` has a partial composite index on `(user_id, sha256) WHERE sha256 IS NOT NULL`. The Advisor does not list that FK, while a strict all-rows coverage check does. This partial index can serve queries for rows with non-null hashes, but it is not a general all-row FK-supporting index.

### Current Advisor findings (21)

| Table | Foreign-key columns |
|---|---|
| audit_logs | actor_id |
| business_memberships | member_user_id |
| duplicate_matches | candidate_id |
| duplicate_matches | decided_by |
| duplicate_matches | matched_candidate_id |
| duplicate_matches | matched_order_id |
| import_batches | user_id |
| import_notifications | related_batch_id |
| import_notifications | related_candidate_id |
| ocr_notes | user_id |
| order_candidates | approved_order_id |
| order_candidates | import_batch_id |
| order_candidates | reviewed_by |
| order_items | order_id |
| order_items | product_id |
| order_items | user_id |
| orders | (customer_id, user_id) |
| source_media | import_batch_id |
| stock_movements | created_by |
| stock_movements | product_id |
| subscription_requests | user_id |

Strict catalog review additionally flags `source_media.user_id` because its existing `(user_id, sha256)` index is partial.

## Workload and size observations

The current inspected tables are very small: most have estimated row counts of zero; `orders` has an estimated two rows. Several indexes on import, OCR, stock, and audit tables currently show zero scans. These statistics are a snapshot of a low-volume environment and do not predict production workload after merchants begin using POS and imports.

The findings are therefore a review queue, **not proof of a live performance incident and not an instruction to create 21 or 22 indexes immediately**.

## Prioritization for later workload review

**First review when transactional POS is implemented and exercised:**
- `order_items.order_id`
- `order_items.product_id`
- `stock_movements.product_id`
- `orders(customer_id, user_id)`

These relate to order detail retrieval, product history, stock movement history, and customer-linked orders. Confirm actual query filters, sort order, join keys, and query plans before choosing definitions.

**Next review:**
- `business_memberships.member_user_id`
- `audit_logs.actor_id`
- `stock_movements.created_by`
- `order_items.user_id`
- `ocr_notes.user_id`
- import/duplicate-review relationships, as those workflows are exercised

**Lower-priority / verify actual usage:**
- `subscription_requests.user_id`
- the remaining duplicate/import relationship keys

Do not recreate indexes that already cover the actual query pattern. In particular, review partial-index predicates and composite-key ordering rather than relying only on index names.

## Safe next steps

1. Exercise representative POS, stock-history, audit, OCR, and import queries with realistic synthetic data in an isolated PostgreSQL environment.
2. Capture `EXPLAIN (ANALYZE, BUFFERS)` for representative reads and inspect write frequency, table growth, index size, and index scans.
3. Confirm whether an existing full, partial, or composite index serves the actual query.
4. Prepare only the smallest set of justified indexes in a reviewed migration.
5. Apply and validate in a disposable PostgreSQL environment first; measure read plans and write overhead.
6. Request explicit approval before any Production DDL.

## Important limitation

No index was created or dropped, no table was altered, and no Production data was modified. The local execution environment does not currently provide an isolated PostgreSQL server or container runtime, so migration and query-plan integration testing remains a wait gate.
