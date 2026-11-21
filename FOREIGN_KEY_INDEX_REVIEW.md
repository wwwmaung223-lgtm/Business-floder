# Foreign-Key Index Review

**Review type:** Read-only PostgreSQL catalog inspection  
**Project:** Existing Northstar production database  
**Production changes:** None

## Finding

A read-only catalog query compared every public-schema foreign-key column sequence with the leading columns of valid indexes on the referencing table. It returned 13 foreign keys without a matching leading-column index at the time of inspection:

| Table | Foreign key | Referencing columns |
|---|---|---|
| audit_logs | audit_logs_actor_id_fkey | actor_id |
| business_memberships | business_memberships_member_user_id_fkey | member_user_id |
| ocr_notes | ocr_notes_user_id_fkey | user_id |
| order_items | order_items_order_id_fkey | order_id |
| order_items | order_items_product_id_fkey | product_id |
| order_items | order_items_user_id_fkey | user_id |
| orders | orders_customer_id_user_id_fkey | customer_id, user_id |
| stock_movements | stock_movements_created_by_fkey | created_by |
| stock_movements | stock_movements_product_id_fkey | product_id |
| subscription_requests | subscription_requests_requested_plan_code_fkey | requested_plan_code |
| subscription_requests | subscription_requests_reviewed_by_fkey | reviewed_by |
| subscription_requests | subscription_requests_user_id_fkey | user_id |
| subscriptions | subscriptions_plan_code_fkey | plan_code |

This is a catalog-level missing-index finding, not proof that all 13 indexes should be created. PostgreSQL does not automatically create an index on the referencing side of every foreign key.

## Prioritization for later workload review

**First review:**
- `order_items.order_id`
- `order_items.product_id`
- `stock_movements.product_id`
- `orders(customer_id, user_id)`

These relate to order detail retrieval, product history, stock movement history, and customer-linked orders. Check query plans and actual query patterns before choosing index definitions.

**Next review:**
- `business_memberships.member_user_id`
- `audit_logs.actor_id`
- `stock_movements.created_by`
- `order_items.user_id`
- `ocr_notes.user_id`

These may help membership lookups, audit actor history, stock actor history, and per-user listing/filtering.

**Lower-priority / verify actual usage:**
- `subscription_requests.requested_plan_code`
- `subscription_requests.reviewed_by`
- `subscription_requests.user_id`
- `subscriptions.plan_code`

These should be prioritized according to billing/admin query frequency and table growth.

## Safe next steps

1. Inspect existing query plans and production query statistics for the candidate joins and filters.
2. Check row counts, table growth, index size, and write frequency.
3. Confirm whether an existing index with a different column ordering or expression already serves the actual workload.
4. Prepare only the smallest set of justified indexes in a reviewed migration.
5. Apply and validate in a disposable PostgreSQL environment first; measure query plans and write overhead.
6. Request explicit approval before any production DDL.

## Important limitation

The index inventory does not prove a performance incident. No index was created or dropped, no table was altered, and no production data was modified. The findings are a review queue, not an automatic migration plan.
