# Entity-Relationship Diagram

The database models a typical online retailer. The grain at which money is
recognized is the **order line item** (`order_items`), with dimension tables
hanging off of it.

```
                         ┌──────────────────┐
                         │    campaigns     │
                         │──────────────────│
                         │ campaign_id (PK) │
                         │ channel          │
                         │ spend_usd        │
                         └────────┬─────────┘
                                  │ 1
                                  │
                                  │ N
                    ┌─────────────┴──────────────┐
                    │   customer_acquisition      │
                    │─────────────────────────────│
                    │ customer_id (PK, FK)        │
                    │ campaign_id (FK)            │
                    └─────────────┬───────────────┘
                                  │ 1
                                  │
   ┌──────────────┐              │ 1            ┌──────────────────┐
   │  categories  │              │              │    customers     │
   │──────────────│         ┌────┴─────┐        │──────────────────│
   │ category_id  │◄──┐     │          │        │ customer_id (PK) │
   │ name         │   │     │          ▼        │ email (UQ)       │
   │ parent_id(FK)│───┘     │   ┌──────────────────────┐          │
   └──────┬───────┘ self-   │   │       orders         │◄─────────┘
          │ 1       ref      │   │──────────────────────│  1     N
          │                  │   │ order_id (PK)        │
          │ N                │   │ customer_id (FK)     │
   ┌──────┴───────┐          │   │ order_date           │
   │   products   │          │   │ status               │
   │──────────────│          │   └──────────┬───────────┘
   │ product_id PK│          │              │ 1
   │ category_id  │          │              │
   │ sku (UQ)     │          │              │ N
   │ cost         │   1      │   ┌──────────┴───────────┐
   │ list_price   │──────────┴──►│     order_items      │
   └──────────────┘   N          │──────────────────────│
                                 │ order_item_id (PK)   │
                                 │ order_id (FK)        │
                                 │ product_id (FK)      │
                                 │ quantity             │
                                 │ unit_price           │
                                 │ discount_pct         │
                                 └──────────┬───────────┘
                                            │ 1
                                            │
                                            │ 0..1
                                 ┌──────────┴───────────┐
                                 │       returns        │
                                 │──────────────────────│
                                 │ return_id (PK)       │
                                 │ order_item_id(FK,UQ) │
                                 │ return_date          │
                                 │ reason               │
                                 └──────────────────────┘
```

## Relationships

| From | To | Cardinality | Meaning |
|------|----|-------------|---------|
| `categories` | `categories` | self, 1→N | sub-category hierarchy (3 levels) |
| `categories` | `products` | 1→N | each product belongs to one leaf category |
| `customers` | `orders` | 1→N | a customer places many orders |
| `orders` | `order_items` | 1→N | an order has many line items |
| `products` | `order_items` | 1→N | a product appears on many lines |
| `order_items` | `returns` | 1→0..1 | a line item may be returned once |
| `campaigns` | `customer_acquisition` | 1→N | a campaign acquires many customers |
| `customers` | `customer_acquisition` | 1→1 | first-touch attribution |

## Design notes

- **Grain:** `order_items` is the fact table; everything else is a dimension.
- **Cancelled orders** are kept (not deleted) so funnel/cancellation analysis is
  possible; revenue queries filter them out with `status <> 'cancelled'`.
- **Returns** are modeled at line-item level with a `UNIQUE` constraint, so a
  line can be returned at most once (partial-quantity returns are out of scope).
- **Discounts** are stored as a percentage on the line, applied at query time —
  this keeps the raw `unit_price` auditable.
